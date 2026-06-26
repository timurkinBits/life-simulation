extends Node

# ══════════════════════════════════════════════════════════════════════════════
# MutationRegistry — глобальный реестр всех возможных мутаций в игре.
#
# Как добавить новую мутацию:
#   1. Добавь её ID в enum MutationID.
#   2. Добавь запись в _build_registry() с описанием.
#   3. Создай сцену мутации (например res://mutations/wings.tscn) и прикрепи
#      к ней скрипт, расширяющий BaseMutation.
#   4. Зарегистрируй обработчики через хуки в entity.gd (см. комментарии там).
# ══════════════════════════════════════════════════════════════════════════════

enum MutationID {
	NOSE,
	FIN
	# ← добавляй сюда новые мутации
}

# Одна запись реестра
class MutationDef:
	var id:          int      # MutationID
	var display_name: String
	var description: String
	var scene_path:  String   # путь к сцене-узлу мутации (пустой — только логика)
	var weight:      float    # вес при случайном выборе (больше = чаще)

	func _init(p_id, p_name, p_desc, p_scene, p_weight := 1.0) -> void:
		id           = p_id
		display_name = p_name
		description  = p_desc
		scene_path   = p_scene
		weight       = p_weight

# ──────────────────────────────────────────────
# Внутренний реестр
# ──────────────────────────────────────────────
var _registry: Dictionary = {}   # MutationID -> MutationDef
var _all_ids:  Array      = []   # для случайного выбора

func _ready() -> void:
	_build_registry()

func _build_registry() -> void:
	_register(MutationDef.new(
		MutationID.NOSE,
		"Нос",
		"Существо чует еду в радиусе и мгновенно меняет на неё цель.",
		"res://mutations/nose.tscn",
		0.5
	))
	_register(MutationDef.new(
		MutationID.FIN,
		"Плавник",
		"Постоянная прибавка к базовой скорости и скорости пворота",
		"res://mutations/fin.tscn",
		1.0
	))
	# ← _register(MutationDef.new(...)) для новых мутаций

func _register(def: MutationDef) -> void:
	_registry[def.id] = def
	_all_ids.append(def.id)

# ──────────────────────────────────────────────
# Публичный API
# ──────────────────────────────────────────────

## Возвращает MutationDef по ID или null.
func get_def(id: int) -> MutationDef:
	return _registry.get(id, null)

## Выбирает случайную мутацию с учётом весов.
## exclude — массив MutationID, которые нужно исключить (уже есть у существа).
func random_mutation(exclude: Array = []) -> int:
	var pool: Array = []
	var total_weight: float = 0.0
	for id in _all_ids:
		if id in exclude:
			continue
		var def: MutationDef = _registry[id]
		pool.append({ "id": id, "w": def.weight })
		total_weight += def.weight

	if pool.is_empty():
		return -1   # все мутации уже есть

	var r: float = randf() * total_weight
	var acc: float = 0.0
	for entry in pool:
		acc += entry["w"]
		if r <= acc:
			return entry["id"]
	return pool[-1]["id"]

## Все зарегистрированные ID.
func all_ids() -> Array:
	return _all_ids.duplicate()
