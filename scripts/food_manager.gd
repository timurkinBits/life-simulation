extends Node2D

# ──────────────────────────────────────────────
# Менеджер еды — спавнит отдельные сцены Food
# ──────────────────────────────────────────────
# Требуется экспортировать сцену еды:
#   @export var food_scene: PackedScene
# Если food_scene не задана, еда создаётся программно.
# ──────────────────────────────────────────────

@export var food_scene: PackedScene           # назначьте сцену Food в инспекторе
@export var max_food_count: int = 250
@export var spawn_time: float = 0.1
@export var food_radius: float = 8.0

var _bounds_rect: Rect2 = Rect2(0, 0, 1920, 1080)
var _spawn_timer: float = 0.0
var _food_items: Array = []

func _process(delta: float) -> void:
	_spawn_timer += delta

	if _spawn_timer >= spawn_time and _food_items.size() < max_food_count:
		_spawn_food()
		_spawn_timer = 0.0

	# Удаляем недействительные записи (еда была съедена через queue_free)
	_food_items = _food_items.filter(func(f): return is_instance_valid(f))


func _spawn_food() -> void:
	var margin := food_radius + 10.0
	var world_pos := Vector2(
		randf_range(_bounds_rect.position.x + margin, _bounds_rect.end.x - margin),
		randf_range(_bounds_rect.position.y + margin, _bounds_rect.end.y - margin)
	)

	var food: Node2D
	if food_scene:
		food = food_scene.instantiate()
	else:
		push_warning("Нет сцены еды")

	add_child(food)
	food.global_position = world_pos
	_food_items.append(food)
