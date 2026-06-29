extends Node2D

var stats: EntityStats = EntityStats.new()

@export var move_speed: float = 100.0
@export var rotation_speed: float = 5.0
@export var wander_radius: float = 400.0

@export var min_idle_time: float = 0.01
@export var max_idle_time: float = 0.1
@export var arrive_threshold: float = 8.0

var _bounds_rect: Rect2 = Rect2(0, 0, 1920, 1080)

# ──────────────────────────────────────────────
# РАЗДЕЛЕНИЕ СУЩЕСТВ (separation steering)
# ──────────────────────────────────────────────
const SEPARATION_FORCE: float  = 300.0
const SEPARATION_RADIUS: float = 15.0

@export var hunger_max: float = 20.0
@export var hunger_regen: float = 15.0

@export var entity_color: Color

# ──────────────────────────────────────────────
# СИСТЕМА СТАРЕНИЯ
# ──────────────────────────────────────────────
enum LifeStage { CHILD, ADULT, OLD }

# Базовый масштаб всех существ
const BASE_ENTITY_SCALE: float  = 2.0

const CHILD_SCALE_START: float  = 0.4
const CHILD_GROW_TIME:   float  = 30.0

const ADULT_DURATION:    float  = 120.0
const OLD_DURATION:      float  = 60.0
const OLD_AGE_DECAY:     float  = 0.5

const OLD_AGE_MIN_ALPHA: float  = 0.4
const OLD_AGE_BLINK_FREQ: float = 2.5

const BIRTH_LEVEL: int = 15

var _life_stage:  LifeStage = LifeStage.ADULT
var _stage_timer: float     = 0.0
var _parent_scale: float    = BASE_ENTITY_SCALE
var _old_age_base_speed:         float = 0.0
var _old_age_base_turn_speed:    float = 0.0
var _old_age_base_wander_radius: float = 0.0

var _blink_time: float = 0.0

signal fed(entity)
signal child_spawned(child_entity)
signal organ_tick(delta)
signal food_detected(food_node: Node, priority: int)

enum State { MOVING, IDLE, CHASING_FOOD }

var _state: State = State.IDLE
var _target: Vector2 = Vector2.ZERO
var _origin: Vector2 = Vector2.ZERO
var _idle_timer: float = 0.0
var _velocity: Vector2 = Vector2.ZERO
var _half_size: Vector2 = Vector2.ZERO

var _hunger: float = 0.0
var _eat_count: int = 0

var _food_target: Node = null
var _food_target_priority: int = 0

@export var organ_genome: Array[OrganData] = []
var _organ_nodes: Dictionary = {}

const NEW_ORGAN_CHANCE:    float = 0.3
const ORGAN_LOSS_CHANCE:   float = 0.05
const ORGAN_MUTATE_CHANCE: float = 0.3
const STAT_WORSEN_CHANCE:  float = 0.15
const STAT_WORSEN_AMOUNT:  float = 0.20

const _PALETTE_SIZE: int = 16
static var _palette_index: int = 0

static func _next_palette_color() -> Color:
	var hue: float = fmod(float(_palette_index) / float(_PALETTE_SIZE), 1.0)
	hue = fmod(hue + randf_range(-0.03, 0.03), 1.0)
	_palette_index += 1
	return Color.from_hsv(hue, 1.0, 1.0)


func offer_food_target(food_node: Node, priority: int) -> void:
	if food_node == null or not is_instance_valid(food_node):
		return
	if _food_target != null and priority <= _food_target_priority:
		return
	_food_target = food_node
	_food_target_priority = priority
	_target = food_node.global_position
	_state = State.CHASING_FOOD

func has_food_target() -> bool:
	return _food_target != null and is_instance_valid(_food_target)

func get_speed() -> float:        return stats.speed()
func get_turn_speed() -> float:   return stats.turn_speed()
func get_wander_radius() -> float: return stats.wander_radius()
func get_life_stage() -> LifeStage: return _life_stage
func is_fertile() -> bool:        return _life_stage == LifeStage.ADULT


# ──────────────────────────────────────────────
# АБСТРАКТНЫЕ МЕТОДЫ — переопределить в подклассе
# ──────────────────────────────────────────────

# Вызывается при достижении цели-еды. Возвращает true если еда была съедена.
func _try_eat_target() -> bool:
	push_error("Entity: _try_eat_target() не переопределён в подклассе!")
	return false

# Возвращает true, если данный узел является допустимой целью питания для этого существа.
func _is_valid_food(node: Node) -> bool:
	push_error("Entity: _is_valid_food() не переопределён в подклассе!")
	return false


func add_organ(data: OrganData) -> void:
	if data.scene_path in _organ_nodes:
		return
	var scene = load(data.scene_path)
	if scene == null:
		push_warning("Entity: не удалось загрузить сцену органа: %s" % data.scene_path)
		return
	if not scene is PackedScene:
		push_error("Entity: scene_path должен вести на .tscn, а не на скрипт/ресурс: %s" % data.scene_path)
		return
	var node: BaseOrgan = scene.instantiate()
	add_child(node)
	_organ_nodes[data.scene_path] = node
	node._attach_to_entity(self, stats, data)
	if not _genome_has(data.scene_path):
		organ_genome.append(data)


func remove_organ_by_path(scene_path: String) -> void:
	if not _organ_nodes.has(scene_path):
		return
	var node: BaseOrgan = _organ_nodes[scene_path]
	node._detach_from_entity()
	node.queue_free()
	_organ_nodes.erase(scene_path)
	organ_genome = organ_genome.filter(func(d): return d.scene_path != scene_path)


func has_organ(scene_path: String) -> bool:
	return _organ_nodes.has(scene_path)


func _genome_has(scene_path: String) -> bool:
	for d in organ_genome:
		if d.scene_path == scene_path:
			return true
	return false


func _ready() -> void:
	stats.base_speed         = move_speed
	stats.base_turn_speed    = rotation_speed
	stats.base_wander_radius = wander_radius

	var sprite := _find_sprites()
	if sprite.size() > 0 and sprite[0].texture:
		var tex_size: Vector2 = sprite[0].texture.get_size() * sprite[0].scale
		var half_diag: float = tex_size.length() / 2.0
		_half_size = Vector2(half_diag, half_diag)
	else:
		push_warning("Entity: Sprite2D с текстурой не найден.")

	if _life_stage != LifeStage.CHILD:
		entity_color = _next_palette_color()
		scale = Vector2(BASE_ENTITY_SCALE, BASE_ENTITY_SCALE)
		_parent_scale = BASE_ENTITY_SCALE

	_origin = global_position.clamp(
		_bounds_rect.position + _half_size,
		_bounds_rect.end - _half_size
	)

	food_detected.connect(_on_food_detected)
	_pick_new_target()
	_instantiate_genome()


func _physics_process(delta: float) -> void:
	_tick_hunger(delta)
	organ_tick.emit(delta)
	_tick_aging(delta)

	match _state:
		State.IDLE:
			_tick_idle(delta)
		State.MOVING:
			_tick_moving(delta)
		State.CHASING_FOOD:
			_tick_chasing_food(delta)

	_apply_separation(delta)


func _on_food_detected(food_node: Node, priority: int) -> void:
	offer_food_target(food_node, priority)


# ──────────────────────────────────────────────
# ГОЛОД
# ──────────────────────────────────────────────
func _tick_hunger(delta: float) -> void:
	_hunger += delta
	if _hunger >= stats.max_energy():
		queue_free()
		return
	_update_visuals(delta)


func feed() -> void:
	_hunger = max(0.0, _hunger - hunger_regen)
	_food_target = null
	_food_target_priority = 0
	_eat_count += 1
	_check_reproduction()
	fed.emit(self)


# ──────────────────────────────────────────────
# ВИЗУАЛИЗАЦИЯ (голод + старость + мигание)
# ──────────────────────────────────────────────
func _update_visuals(delta: float) -> void:
	var hunger_t: float = _hunger / stats.max_energy()
	var brightness: float = lerp(1.0, 0.15, hunger_t)

	var alpha: float = 1.0

	if _life_stage == LifeStage.OLD:
		_blink_time += delta
		var old_t: float = clampf(_stage_timer / OLD_DURATION, 0.0, 1.0)
		var base_alpha: float = lerp(1.0, OLD_AGE_MIN_ALPHA, old_t)
		var blink_amp: float = lerp(0.0, 0.35, old_t)
		var blink: float = (sin(_blink_time * OLD_AGE_BLINK_FREQ * TAU) * 0.5 + 0.5) * blink_amp
		alpha = clampf(base_alpha - blink, 0.05, 1.0)

	_set_modulate(brightness, alpha)


func _set_modulate(brightness: float, alpha: float) -> void:
	var col := entity_color * Color(brightness, brightness, brightness, 1.0)
	col.a = alpha
	for sprite in _find_sprites():
		sprite.modulate = col


# ──────────────────────────────────────────────
# СИСТЕМА СТАРЕНИЯ
# ──────────────────────────────────────────────
func _tick_aging(delta: float) -> void:
	_stage_timer += delta

	match _life_stage:
		LifeStage.CHILD:
			_tick_child_growth()
			if _stage_timer >= CHILD_GROW_TIME:
				_enter_stage(LifeStage.ADULT)

		LifeStage.ADULT:
			if _stage_timer >= ADULT_DURATION:
				_enter_stage(LifeStage.OLD)

		LifeStage.OLD:
			_tick_old_age_decay()
			if _stage_timer >= OLD_DURATION:
				queue_free()
				return


func _enter_stage(stage: LifeStage) -> void:
	_life_stage = stage
	_stage_timer = 0.0
	_blink_time  = 0.0

	match stage:
		LifeStage.ADULT:
			scale = Vector2(_parent_scale, _parent_scale)

		LifeStage.OLD:
			_old_age_base_speed         = stats.base_speed
			_old_age_base_turn_speed    = stats.base_turn_speed
			_old_age_base_wander_radius = stats.base_wander_radius


func _tick_child_growth() -> void:
	var grow_t: float = clampf(_stage_timer / CHILD_GROW_TIME, 0.0, 1.0)
	var target_scale: float = lerp(CHILD_SCALE_START * _parent_scale, _parent_scale, grow_t)
	scale = Vector2(target_scale, target_scale)


func _tick_old_age_decay() -> void:
	var decay_t: float = clampf(_stage_timer / OLD_DURATION, 0.0, 1.0)
	var factor: float = lerp(1.0, 1.0 - OLD_AGE_DECAY, decay_t)
	stats.base_speed         = _old_age_base_speed * factor
	stats.base_turn_speed    = _old_age_base_turn_speed * factor
	stats.base_wander_radius = _old_age_base_wander_radius * factor


# ──────────────────────────────────────────────
# РАЗМНОЖЕНИЕ
# ──────────────────────────────────────────────
func _check_reproduction() -> void:
	if not is_fertile():
		return
	if _eat_count % BIRTH_LEVEL != 0:
		return
	_spawn_child()


func _spawn_child() -> void:
	var parent_scale: float = scale.x
	var spawn_pos: Vector2 = global_position + Vector2(randf_range(-60, 60), randf_range(-60, 60))
	var child_genome: Array[OrganData] = _build_child_genome()
	var child_stats: EntityStats = _build_child_stats()
	call_deferred("_deferred_add_child", parent_scale, spawn_pos, child_genome, child_stats)


func _build_child_genome() -> Array[OrganData]:
	var child_genome: Array[OrganData] = []
	for parent_organ_data in organ_genome:
		if randf() < ORGAN_LOSS_CHANCE:
			continue
		if randf() < ORGAN_MUTATE_CHANCE:
			var copy := parent_organ_data.mutated_copy(1.0)
			if randf() < STAT_WORSEN_CHANCE:
				copy = _worsen_organ_params(copy)
			child_genome.append(copy)
		else:
			child_genome.append(parent_organ_data.exact_copy())

	if randf() < NEW_ORGAN_CHANCE:
		var existing_paths: Array = child_genome.map(func(d): return d.scene_path)
		var new_template := OrganRegistry.random_organ(existing_paths)
		if new_template != null:
			child_genome.append(new_template.exact_copy())

	return child_genome


func _worsen_organ_params(data: OrganData) -> OrganData:
	var copy := OrganData.new()
	copy.scene_path   = data.scene_path
	copy.display_name = data.display_name
	copy.spawn_weight = data.spawn_weight
	copy.params       = {}
	for key in data.params:
		var val = data.params[key]
		if val is float or val is int:
			var penalty: float = randf_range(0.0, STAT_WORSEN_AMOUNT)
			copy.params[key] = maxf(0.0, float(val) * (1.0 - penalty))
		else:
			copy.params[key] = val
	return copy


func _build_child_stats() -> EntityStats:
	var child_stats := EntityStats.new()
	child_stats.base_speed         = _maybe_worsen(stats.base_speed)
	child_stats.base_turn_speed    = _maybe_worsen(stats.base_turn_speed)
	child_stats.base_wander_radius = _maybe_worsen(stats.base_wander_radius)
	child_stats.base_max_energy    = _maybe_worsen(stats.base_max_energy)
	child_stats.base_energy_drain  = _maybe_worsen(stats.base_energy_drain)
	child_stats.base_vision_range  = stats.base_vision_range
	child_stats.base_vision_angle  = stats.base_vision_angle
	child_stats.base_smell_radius  = stats.base_smell_radius
	child_stats.base_armor         = stats.base_armor
	child_stats.base_attack        = stats.base_attack
	child_stats.base_size          = stats.base_size
	return child_stats


func _maybe_worsen(value: float) -> float:
	if randf() < STAT_WORSEN_CHANCE:
		return maxf(0.0, value * (1.0 - randf_range(0.0, STAT_WORSEN_AMOUNT)))
	return value


func _deferred_add_child(
	parent_scale: float, spawn_pos: Vector2,
	child_genome: Array[OrganData],
	child_stats: EntityStats
) -> void:
	var child = duplicate()

	child._life_stage     = LifeStage.CHILD
	child._stage_timer    = 0.0
	child._blink_time     = 0.0
	child._parent_scale   = parent_scale
	child.entity_color    = entity_color

	child._eat_count            = 0
	child._hunger               = 0.0
	child._food_target          = null
	child._food_target_priority = 0

	child.stats = child_stats
	child.scale = Vector2(CHILD_SCALE_START * parent_scale, CHILD_SCALE_START * parent_scale)

	for old_node in child.get_children():
		if old_node is BaseOrgan:
			old_node.free()

	child._organ_nodes = {}
	child.organ_genome.clear()
	for d in child_genome:
		child.organ_genome.append(d)

	get_parent().add_child(child)
	child.global_position = spawn_pos
	child_spawned.emit(child)


func _instantiate_genome() -> void:
	var genome_copy := organ_genome.duplicate()
	organ_genome.clear()
	_organ_nodes.clear()
	for organ_data in genome_copy:
		add_organ(organ_data)


func _tick_idle(delta: float) -> void:
	_velocity = _velocity.move_toward(Vector2.ZERO, stats.speed() * 4.0 * delta)
	global_position += _velocity * delta
	_clamp_position()
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		_pick_new_target()
		_state = State.MOVING


func _tick_moving(delta: float) -> void:
	var to_target: Vector2 = _target - global_position
	var distance: float = to_target.length()
	if distance <= arrive_threshold:
		_state = State.IDLE
		_idle_timer = randf_range(min_idle_time, max_idle_time)
		return
	var target_angle: float = to_target.angle()
	rotation = lerp_angle(rotation, target_angle, clampf(stats.turn_speed() * delta, 0.0, 1.0))
	var forward: Vector2 = Vector2.RIGHT.rotated(rotation)
	var speed_factor: float = clampf(distance / 40.0, 0.2, 1.0)
	_velocity = forward * stats.speed() * speed_factor
	global_position += _velocity * delta
	_clamp_position()


func _tick_chasing_food(delta: float) -> void:
	if not has_food_target():
		_food_target = null
		_food_target_priority = 0
		_pick_new_target()
		_state = State.MOVING
		return
	_target = _food_target.global_position
	var to_target: Vector2 = _target - global_position
	var distance: float = to_target.length()
	var target_angle: float = to_target.angle()
	rotation = lerp_angle(rotation, target_angle, clampf(stats.turn_speed() * delta, 0.0, 1.0))
	var dir: Vector2 = to_target.normalized()
	var speed_factor: float = clampf(distance / 30.0, 0.5, 1.0)
	_velocity = dir * stats.speed() * speed_factor
	global_position += _velocity * delta
	_clamp_position()

	# Проверяем, достигли ли цели
	if distance <= arrive_threshold:
		_try_eat_target()


func _clamp_position() -> void:
	if _bounds_rect.size == Vector2.ZERO:
		return
	global_position = global_position.clamp(
		_bounds_rect.position + _half_size,
		_bounds_rect.end - _half_size
	)

func _apply_separation(delta: float) -> void:
	var parent_node := get_parent()
	if parent_node == null:
		return

	var my_scale: float = scale.x
	var push: Vector2 = Vector2.ZERO

	for sibling in parent_node.get_children():
		if sibling == self:
			continue
		if not sibling is Node2D:
			continue
		if not sibling.get_script() == get_script():
			continue
		var sibling_node := sibling as Node2D
		var diff: Vector2 = global_position - sibling_node.global_position
		var dist: float   = diff.length()
		var sibling_scale: float = sibling_node.scale.x
		var min_dist: float      = SEPARATION_RADIUS * (my_scale + sibling_scale) * 0.5
		if dist < min_dist and dist > 0.001:
			var strength: float = (1.0 - dist / min_dist)
			push += diff.normalized() * strength

	if push == Vector2.ZERO:
		return

	global_position += push * SEPARATION_FORCE * delta
	_clamp_position()

	if push.length() > 0.5:
		var escape_dir: Vector2 = push.normalized()
		var escape_dist: float  = randf_range(80.0, 200.0)
		var new_target: Vector2 = global_position + escape_dir * escape_dist
		var min_pos: Vector2    = _bounds_rect.position + _half_size
		var max_pos: Vector2    = _bounds_rect.end - _half_size
		_target = new_target.clamp(min_pos, max_pos)
		if _state != State.CHASING_FOOD:
			_state = State.MOVING


func _find_sprites() -> Array[Sprite2D]:
	var result: Array[Sprite2D] = []
	for child in get_children():
		if child is Sprite2D:
			result.append(child)
	return result

func _pick_new_target() -> void:
	var min_pos: Vector2 = _bounds_rect.position + _half_size
	var max_pos: Vector2 = _bounds_rect.end - _half_size
	var angle: float = randf() * TAU
	var radius: float = randf() * stats.wander_radius()
	_target = (_origin + Vector2(cos(angle), sin(angle)) * radius).clamp(min_pos, max_pos)

func force_new_wander() -> void:
	_pick_new_target()
	_state = State.MOVING
