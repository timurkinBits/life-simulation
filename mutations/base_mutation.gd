extends Node
class_name BaseMutation

# ══════════════════════════════════════════════════════════════════════════════
# BaseMutation — базовый класс для всех мутаций-узлов.
#
# Каждая сцена мутации должна содержать скрипт, наследующий этот класс.
# Entity добавляет инстанс сцены как дочерний узел и вызывает on_attached().
#
# Хуки, которые можно переопределить:
#   on_attached(entity)          — мутация добавлена к существу
#   on_detached()                — мутация удалена (при queue_free существа)
#   on_food_spawned(food_node)   — в мире появилась еда (если entity подписан)
#   on_food_nearby(food_node, distance) — еда попала в зону мутации
#   on_fed()                     — существо поело
#   on_child_spawned(child)      — существо породило ребёнка
#   process(delta)               — каждый кадр физики
# ══════════════════════════════════════════════════════════════════════════════

var mutation_id: int = -1       # заполняется Entity при добавлении
var entity: Node = null         # ссылка на владельца


func on_attached(p_entity: Node) -> void:
	entity = p_entity
	_apply_entity_color()

func on_detached() -> void:
	pass

func on_food_nearby(food_node: Node, distance: float) -> void:
	pass

func on_fed() -> void:
	pass

func on_child_spawned(child: Node) -> void:
	pass

func process(delta: float) -> void:
	pass
	
# Красит все Sprite2D и Polygon2D внутри мутации в цвет существа.
# Вызывается автоматически при on_attached — переопределять не нужно.
func _apply_entity_color() -> void:
	if entity == null or not entity.get("entity_color"):
		return
	var color: Color = entity.entity_color
	_colorize_node(self, color)

func _colorize_node(node: Node, color: Color) -> void:
	if node is Sprite2D:
		node.modulate = color
	elif node is Polygon2D:
		node.color = color
	for child in node.get_children():
		_colorize_node(child, color)
