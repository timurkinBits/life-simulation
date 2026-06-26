extends BaseMutation
# Сцена: res://mutations/fin.tscn
#
# Плавник — постоянная прибавка к базовой скорости и скорости пворота.

@export var speed_bonus: float = 1.1
@export var rot_bonus:float = 1.1

func on_attached(p_entity: Node) -> void:
	super.on_attached(p_entity)
	entity._base_move_speed *= speed_bonus
	entity.move_speed       *= speed_bonus
	entity._base_rotation_speed *= rot_bonus
	entity.rotation_speed       *= rot_bonus
