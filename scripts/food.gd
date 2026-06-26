extends Node2D

@export var food_radius: float = 5.0

func _ready() -> void:
	add_to_group("food")   # нос существа ищет еду по этой группе

	var r := randf_range(food_radius * 0.8, food_radius * 1.5)
	var color := Color(
		randf_range(0.7, 1.0),
		randf_range(0.5, 0.9),
		randf_range(0.0, 0.3)
	)

	# Визуал
	var poly := $Polygon2D
	var verts := PackedVector2Array()
	for i in range(16):
		var a := i * TAU / 16
		verts.append(Vector2(cos(a), sin(a)) * r)
	poly.polygon = verts
	poly.color = color

	# Коллизия
	var shape := CircleShape2D.new()
	shape.radius = r
	$Area2D/CollisionShape2D.shape = shape

	# Сигнал поедания
	$Area2D.area_entered.connect(_on_mouth_entered)


func _on_mouth_entered(other_area: Area2D) -> void:
	if other_area.name != "mouth":
		return
	var entity = other_area.get_parent()
	if entity and entity.has_method("feed"):
		entity.feed()
	queue_free()
