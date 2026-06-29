class_name FinOrgan
extends BaseOrgan
 
@export var speed_bonus: float       = 40.0   # плоская прибавка к скорости
@export var turn_speed: float = 10.0   # штраф к скорости поворота
 
func on_attached() -> void:
	stats.add_flat(organ_id(), "speed", speed_bonus)
	stats.add_flat(organ_id(), "turn_speed", turn_speed)
