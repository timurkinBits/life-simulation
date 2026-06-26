extends BaseMutation
# Сцена: res://mutations/nose.tscn
# Дочерние узлы сцены не нужны — вся логика в process().
#
# Нос — каждый кадр ищет ближайшую еду в радиусе smell_radius.
# Если находит — существо немедленно разворачивается и бежит к ней.

@export var smell_radius: float = 150.0

func process(delta: float) -> void:
	if entity == null:
		return

	var closest: Node = null
	var closest_dist: float = smell_radius

	for food in entity.get_tree().get_nodes_in_group("food"):
		var d: float = entity.global_position.distance_to(food.global_position)
		if d < closest_dist:
			closest_dist = d
			closest = food

	if closest != null:
		entity._on_nose_detected_food(closest, closest_dist)
