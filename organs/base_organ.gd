class_name BaseOrgan
extends Node

var entity: Node        = null
var stats:  EntityStats = null
var organ_data: OrganData = null

func organ_id() -> String:
	return get_script().get_global_name()

func on_attached() -> void:
	pass

func on_detached() -> void:
	pass

func _attach_to_entity(p_entity: Node, p_stats: EntityStats, p_data: OrganData) -> void:
	entity     = p_entity
	stats      = p_stats
	organ_data = p_data
	_apply_params()
	_apply_entity_color()
	on_attached()

func _detach_from_entity() -> void:
	if stats != null:
		stats.remove_organ_mods(organ_id())
	on_detached()

func _apply_params() -> void:
	if organ_data == null or organ_data.params.is_empty():
		return
	for key in organ_data.params:
		if get(key) != null:
			set(key, organ_data.params[key])
		else:
			push_warning("BaseOrgan (%s): неизвестный параметр '%s'" % [organ_id(), key])

func _apply_entity_color() -> void:
	if entity == null:
		return
	_colorize_node(self, entity.entity_color)

func _colorize_node(node: Node, color: Color) -> void:
	if node is Sprite2D:
		node.modulate = color
	elif node is Polygon2D:
		node.color = color
	for child in node.get_children():
		_colorize_node(child, color)
