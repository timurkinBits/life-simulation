extends Node2D

# ──────────────────────────────────────────────
# Настройки движения
# ──────────────────────────────────────────────
@export var move_speed: float = 100.0
@export var rotation_speed: float = 5.0
@export var wander_radius: float = 400.0
@export var min_idle_time: float = 0.01
@export var max_idle_time: float = 0.1
@export var arrive_threshold: float = 8.0

var _bounds_rect: Rect2 = Rect2(0, 0, 1920, 1080)

# ──────────────────────────────────────────────
# Настройки голода
# ──────────────────────────────────────────────
@export var hunger_max: float = 20.0
@export var hunger_regen: float = 15.0

# ──────────────────────────────────────────────
# Настройки эволюции
# ──────────────────────────────────────────────
@export var max_eat_level: int = 20
@export var speed_per_level: float = 15.0
@export var wander_radius_per_level: float = 30.0
@export var rotation_speed_per_level: float = 0.4

# ──────────────────────────────────────────────
# Цвет существа
# ──────────────────────────────────────────────
@export var entity_color: Color

# ──────────────────────────────────────────────
# Размножение
# ──────────────────────────────────────────────
const BIRTH_LEVEL: int = 15
const CHILD_SCALE_START: float = 0.4
const CHILD_GROW_TIME: float = 30.0

var _is_child: bool = false
var _child_grow_timer: float = 0.0
var _parent_eat_count: int = 0
var _parent_scale: float = 1.0
var _inherited_stat: String = ""
var _has_reproduced: bool = false

# ──────────────────────────────────────────────
# Внутреннее состояние
# ──────────────────────────────────────────────
enum State { MOVING, IDLE, CHASING_FOOD }

var _state: State = State.IDLE
var _target: Vector2 = Vector2.ZERO
var _origin: Vector2 = Vector2.ZERO
var _idle_timer: float = 0.0
var _velocity: Vector2 = Vector2.ZERO
var _half_size: Vector2 = Vector2.ZERO

var _hunger: float = 0.0
var _eat_count: int = 0

var _base_move_speed: float
var _base_wander_radius: float
var _base_rotation_speed: float

# ──────────────────────────────────────────────
# ══════════════════════════════════════════════
#  СИСТЕМА МУТАЦИЙ
# ══════════════════════════════════════════════
# ──────────────────────────────────────────────

# Вероятность получить новую случайную мутацию при рождении (0..1)
const MUTATION_CHANCE: float = 0.4

# Список ID активных мутаций (MutationRegistry.MutationID)
var mutations: Array[int] = []

# Словарь id -> экземпляр BaseMutation (узел)
var _mutation_nodes: Dictionary = {}

# Флаги, которые мутации могут выставлять для изменения поведения entity
var _mutation_ignore_bounds: bool = false   # Крылья: wrap вместо clamp

# Текущая пищевая цель (Node), если мутация перехватила управление
var _food_target: Node = null

# ──────────────────────────────────────────────
# Добавить мутацию по ID (загружает и добавляет сцену-узел)
# ──────────────────────────────────────────────
func add_mutation(id: int) -> void:
	if id in mutations:
		return   # уже есть

	var reg = _get_registry()
	if reg == null:
		push_warning("Entity: MutationRegistry не найден в автозагрузке.")
		return

	var def = reg.get_def(id)
	if def == null:
		push_warning("Entity: неизвестный MutationID %d" % id)
		return

	mutations.append(id)

	# Если у мутации есть сцена — инстанцируем и подключаем
	if def.scene_path != "":
		var scene = load(def.scene_path)
		if scene:
			var node = scene.instantiate()
			node.mutation_id = id
			add_child(node)
			_mutation_nodes[id] = node
			node.on_attached(self)
		else:
			push_warning("Entity: не удалось загрузить сцену мутации: %s" % def.scene_path)

# ──────────────────────────────────────────────
# Удалить мутацию по ID
# ──────────────────────────────────────────────
func remove_mutation(id: int) -> void:
	if id not in mutations:
		return
	mutations.erase(id)
	if _mutation_nodes.has(id):
		var node = _mutation_nodes[id]
		node.on_detached()
		node.queue_free()
		_mutation_nodes.erase(id)

# ──────────────────────────────────────────────
# Есть ли мутация?
# ──────────────────────────────────────────────
func has_mutation(id: int) -> bool:
	return id in mutations

# ──────────────────────────────────────────────
# Вспомогательный геттер реестра (AutoLoad "MutationRegistry")
# ──────────────────────────────────────────────
func _get_registry() -> Node:
	if Engine.has_singleton("MutationRegistry"):
		return Engine.get_singleton("MutationRegistry")
	# Fallback: ищем в дереве
	return get_tree().root.get_node_or_null("MutationRegistry")

# ──────────────────────────────────────────────
# Вызов хука process для всех мутаций
# ──────────────────────────────────────────────
func _tick_mutations(delta: float) -> void:
	for node in _mutation_nodes.values():
		node.process(delta)

# ──────────────────────────────────────────────
# Хук: мутация «Нос» обнаружила еду
# Немедленно бросаем всё и бежим к ней
# ──────────────────────────────────────────────
func _on_nose_detected_food(food_node: Node, _distance: float) -> void:
	_food_target = food_node
	_target = food_node.global_position
	_state = State.CHASING_FOOD

# ──────────────────────────────────────────────
# Хук: мутация «Глаза» обнаружила еду
# Перенаправляем мягко, только если нет другой цели
# ──────────────────────────────────────────────
func _on_eyes_detected_food(food_node: Node, _distance: float) -> void:
	if _food_target != null:
		return   # нос уже держит цель
	_food_target = food_node
	_target = food_node.global_position
	_state = State.CHASING_FOOD

# ──────────────────────────────────────────────
# Есть ли активная пищевая цель?
# ──────────────────────────────────────────────
func _has_food_target() -> bool:
	return _food_target != null and is_instance_valid(_food_target)

# ══════════════════════════════════════════════
#  КОНЕЦ БЛОКА МУТАЦИЙ
# ══════════════════════════════════════════════


func _ready() -> void:
	_base_move_speed     = move_speed
	_base_wander_radius  = wander_radius
	_base_rotation_speed = rotation_speed

	var sprite := _find_sprites()
	if sprite.size() > 0 and sprite[0].texture:
		var tex_size: Vector2 = sprite[0].texture.get_size() * sprite[0].scale
		var half_diag: float = tex_size.length() / 2.0
		_half_size = Vector2(half_diag, half_diag)
	else:
		push_warning("Entity: Sprite2D с текстурой не найден.")

	if not _is_child:
		entity_color = Color(randf(), randf(), randf())

	_origin = global_position.clamp(
		_bounds_rect.position + _half_size,
		_bounds_rect.end - _half_size
	)
	_pick_new_target()


func _physics_process(delta: float) -> void:
	_tick_hunger(delta)
	_tick_mutations(delta)

	if _is_child:
		_tick_child_growth(delta)

	match _state:
		State.IDLE:
			_tick_idle(delta)
		State.MOVING:
			_tick_moving(delta)
		State.CHASING_FOOD:
			_tick_chasing_food(delta)


# ──────────────────────────────────────────────
# Голод
# ──────────────────────────────────────────────

func _tick_hunger(delta: float) -> void:
	_hunger += delta
	if _hunger >= hunger_max:
		queue_free()
		return

	var t := _hunger / hunger_max
	var brightness: float = lerp(1.0, 0.15, t)
	_set_brightness(brightness)


func feed() -> void:
	_hunger = max(0.0, _hunger - hunger_regen)
	_food_target = null   # цель достигнута — сбрасываем
	_eat_count += 1
	_apply_evolution()
	_check_reproduction()
	# Хук мутациям
	for node in _mutation_nodes.values():
		node.on_fed()


func _apply_evolution() -> void:
	var level: int = mini(_eat_count, max_eat_level)
	move_speed     = _base_move_speed     + speed_per_level          * level
	wander_radius  = _base_wander_radius  + wander_radius_per_level  * level
	rotation_speed = _base_rotation_speed + rotation_speed_per_level * level

	var scale_factor: float
	if _is_child:
		var grow_t: float = clampf(_child_grow_timer / CHILD_GROW_TIME, 0.0, 1.0)
		scale_factor = lerp(CHILD_SCALE_START * _parent_scale, _parent_scale, grow_t)
	else:
		scale_factor = 1.0 + level * 0.04

	scale = Vector2(scale_factor, scale_factor)


func _set_brightness(b: float) -> void:
	for sprite in _find_sprites():
		sprite.modulate = entity_color * Color(b, b, b, 1.0)


# ──────────────────────────────────────────────
# Размножение
# ──────────────────────────────────────────────

func _check_reproduction() -> void:
	if _is_child or _has_reproduced:
		return
	if _eat_count < BIRTH_LEVEL:
		return
	_has_reproduced = true
	_spawn_child()


func _spawn_child() -> void:
	var best_stat: String = _get_best_stat()
	var level: int = mini(_eat_count, max_eat_level)
	var parent_scale: float = scale.x
	var spawn_pos: Vector2 = global_position + Vector2(randf_range(-60, 60), randf_range(-60, 60))

	var child_base_speed: float    = _base_move_speed
	var child_base_radius: float   = _base_wander_radius
	var child_base_rotation: float = _base_rotation_speed
	match best_stat:
		"speed":
			child_base_speed    = _base_move_speed     + speed_per_level          * level * 0.3
		"radius":
			child_base_radius   = _base_wander_radius  + wander_radius_per_level  * level * 0.3
		"rotation":
			child_base_rotation = _base_rotation_speed + rotation_speed_per_level * level * 0.3

	# Передаём мутации ребёнку через deferred
	call_deferred(
		"_deferred_add_child",
		best_stat, parent_scale, spawn_pos,
		child_base_speed, child_base_radius, child_base_rotation,
		mutations.duplicate()   # копия списка мутаций родителя
	)
	


func _deferred_add_child(
	best_stat: String, parent_scale: float, spawn_pos: Vector2,
	child_base_speed: float, child_base_radius: float, child_base_rotation: float,
	inherited_mutations: Array
) -> void:
	var child = duplicate()

	child._is_child         = true
	child._child_grow_timer = 0.0
	child._parent_eat_count = _eat_count
	child._parent_scale     = parent_scale
	child._inherited_stat   = best_stat
	child._has_reproduced   = false
	child.entity_color      = entity_color

	child._eat_count        = 0
	child._hunger           = 0.0
	child._food_target      = null

	child._base_move_speed     = child_base_speed
	child._base_wander_radius  = child_base_radius
	child._base_rotation_speed = child_base_rotation

	child.move_speed     = child_base_speed
	child.wander_radius  = child_base_radius
	child.rotation_speed = child_base_rotation

	child.scale = Vector2(CHILD_SCALE_START * parent_scale, CHILD_SCALE_START * parent_scale)

	# ── Сброс мутаций у дубликата (duplicate() копирует данные, но не узлы корректно) ──
	# Типизированный Array[int] нельзя присвоить через = [], используем clear()
	child.mutations.clear()
	child._mutation_nodes = {}

	get_parent().add_child(child)
	child.global_position = spawn_pos

	# ── Наследуем мутации родителя ──
	for id in inherited_mutations:
		child.add_mutation(id)

	# ── Шанс получить новую случайную мутацию ──
	if randf() < MUTATION_CHANCE:
		var reg = _get_registry()
		if reg:
			var new_id: int = reg.random_mutation(child.mutations)
			if new_id >= 0:
				child.add_mutation(new_id)

	# ── Хук мутациям родителя ──
	for node in _mutation_nodes.values():
		node.on_child_spawned(child)


func _get_best_stat() -> String:
	var speed_gain: float  = (move_speed - _base_move_speed) / maxf(_base_move_speed, 1.0)
	var radius_gain: float = (wander_radius - _base_wander_radius) / maxf(_base_wander_radius, 1.0)
	var rot_gain: float    = (rotation_speed - _base_rotation_speed) / maxf(_base_rotation_speed, 1.0)

	if speed_gain >= radius_gain and speed_gain >= rot_gain:
		return "speed"
	elif radius_gain >= rot_gain:
		return "radius"
	else:
		return "rotation"


# ──────────────────────────────────────────────
# Взросление ребёнка
# ──────────────────────────────────────────────

func _tick_child_growth(delta: float) -> void:
	if not _is_child:
		return

	_child_grow_timer += delta

	var grow_t: float = clampf(_child_grow_timer / CHILD_GROW_TIME, 0.0, 1.0)
	var target_scale: float = lerp(CHILD_SCALE_START * _parent_scale, _parent_scale, grow_t)
	scale = Vector2(target_scale, target_scale)

	var stat_t: float = grow_t
	move_speed     = lerp(_base_move_speed,     _base_move_speed     + speed_per_level         * mini(_eat_count, max_eat_level), stat_t * 0.5)
	wander_radius  = lerp(_base_wander_radius,  _base_wander_radius  + wander_radius_per_level * mini(_eat_count, max_eat_level), stat_t * 0.5)
	rotation_speed = lerp(_base_rotation_speed, _base_rotation_speed + rotation_speed_per_level* mini(_eat_count, max_eat_level), stat_t * 0.5)

	if _child_grow_timer >= CHILD_GROW_TIME:
		_is_child = false
		_apply_evolution()


# ──────────────────────────────────────────────
# Состояния движения
# ──────────────────────────────────────────────

func _tick_idle(delta: float) -> void:
	_velocity = _velocity.move_toward(Vector2.ZERO, move_speed * 4.0 * delta)
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
	rotation = lerp_angle(rotation, target_angle, clampf(rotation_speed * delta, 0.0, 1.0))

	var forward: Vector2 = Vector2.RIGHT.rotated(rotation)
	var speed_factor: float = clampf(distance / 40.0, 0.2, 1.0)
	_velocity = forward * move_speed * speed_factor

	global_position += _velocity * delta
	_clamp_position()


func _tick_chasing_food(delta: float) -> void:
	# Цель исчезла (съедена другим / удалена) — возвращаемся к блужданию
	if not _has_food_target():
		_food_target = null
		_pick_new_target()
		_state = State.MOVING
		return

	# Обновляем позицию цели (еда может двигаться)
	_target = _food_target.global_position

	var to_target: Vector2 = _target - global_position
	var distance: float = to_target.length()

	# Не останавливаемся принудительно — еда сама вызовет feed() через area_entered,
	# после чего _food_target сбросится в feed() и мы вернёмся к блужданию

	# Визуальный поворот — только для анимации, на движение не влияет
	var target_angle: float = to_target.angle()
	rotation = lerp_angle(rotation, target_angle, clampf(rotation_speed * delta, 0.0, 1.0))

	# Движемся строго к цели по нормализованному вектору — без дрейфа от угла поворота
	var dir: Vector2 = to_target.normalized()
	var speed_factor: float = clampf(distance / 30.0, 0.5, 1.0)
	_velocity = dir * move_speed * speed_factor

	global_position += _velocity * delta
	_clamp_position()


# ──────────────────────────────────────────────
# Вспомогательные
# ──────────────────────────────────────────────

func _clamp_position() -> void:
	if _bounds_rect.size == Vector2.ZERO:
		return
	# Мутация «Крылья» выставляет флаг — тогда wrap вместо clamp
	if _mutation_ignore_bounds:
		return   # wrap делает сама мутация в своём process()
	global_position = global_position.clamp(
		_bounds_rect.position + _half_size,
		_bounds_rect.end - _half_size
	)

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
	var radius: float = randf() * wander_radius
	_target = (_origin + Vector2(cos(angle), sin(angle)) * radius).clamp(min_pos, max_pos)

func force_new_wander() -> void:
	_pick_new_target()
	_state = State.MOVING
