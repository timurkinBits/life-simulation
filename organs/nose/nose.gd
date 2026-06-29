class_name NoseOrgan
extends BaseOrgan

@export var smell_radius: float = 150.0

const DETECTION_PRIORITY: int = 10

func on_attached() -> void:
	stats.add_flat(organ_id(), "smell_radius", smell_radius)

func on_detached() -> void:
	pass

func _process(_delta: float) -> void:
	if entity == null:
		return

	var current_radius: float = stats.smell_radius()
	if current_radius <= 0.0:
		return

	var closest: Node = null
	var closest_dist: float = current_radius

	for food in entity.get_tree().get_nodes_in_group("food"):
		var d: float = entity.global_position.distance_to(food.global_position)
		if d < closest_dist:
			closest_dist = d
			closest = food

	if closest != null:
		entity.offer_food_target(closest, DETECTION_PRIORITY)
