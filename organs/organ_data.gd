class_name OrganData
extends Resource

@export var scene_path:    String     = ""
@export var display_name:  String     = ""
@export var params:        Dictionary = {}
@export var spawn_weight:  float      = 1.0

# ──────────────────────────────────────────────
# mutated_copy — изменяет числовые параметры органа на случайную величину.
# mutation_strength = 1.0 означает изменение до ±20% от значения (вверх или вниз).
# Используется для передачи генома детям.
# ──────────────────────────────────────────────
func mutated_copy(mutation_strength: float = 0.1) -> OrganData:
	var copy := OrganData.new()
	copy.scene_path   = scene_path
	copy.display_name = display_name
	copy.spawn_weight = spawn_weight
	copy.params       = {}
	for key in params:
		var val = params[key]
		if val is float or val is int:
			# Изменение может быть как положительным, так и отрицательным
			var delta: float = (randf() * 2.0 - 1.0) * mutation_strength * float(val) * 0.2
			copy.params[key] = maxf(0.0, float(val) + delta)
		else:
			copy.params[key] = val
	return copy

func exact_copy() -> OrganData:
	return mutated_copy(0.0)
