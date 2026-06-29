# entity_stats.gd
# res://entity_stats.gd
#
# Resource, хранящий все характеристики существа.
#
# ПОЧЕМУ Resource, а не просто переменные в Entity?
#   - Его можно передавать по ссылке между органами и Entity
#   - Органы пишут в него через единый API, не трогая Entity
#   - В будущем можно сохранять/загружать геном как Resource
#   - Легко сериализовать для отображения в UI
#
# КАК РАБОТАЮТ МОДИФИКАТОРЫ:
#   Каждая характеристика имеет base (базовое значение) и
#   вычисляемое final = (base + flat_bonus) * multiplier.
#   Органы добавляют flat_bonus или multiplier через add_modifier() / remove_modifier().
#   Entity читает только final значения.

class_name EntityStats
extends Resource

# ──────────────────────────────────────────────
# Базовые значения (наследуются и мутируют)
# ──────────────────────────────────────────────
@export var base_speed:           float = 100.0
@export var base_turn_speed:      float = 5.0
@export var base_wander_radius:   float = 400.0
@export var base_vision_range:    float = 0.0    # 0 = слепой (нет глаз)
@export var base_vision_angle:    float = 0.0    # в радианах
@export var base_smell_radius:    float = 0.0    # 0 = нет носа
@export var base_max_energy:      float = 20.0
@export var base_energy_drain:    float = 1.0    # единиц в секунду
@export var base_armor:           float = 0.0
@export var base_attack:          float = 0.0
@export var base_size:            float = 1.0

# ──────────────────────────────────────────────
# Модификаторы от органов
# Структура: { "stat_name": { "organ_id": value, ... } }
# ──────────────────────────────────────────────
var _flat_mods:   Dictionary = {}  # flat_mods["speed"]["nose"] = 20.0
var _multi_mods:  Dictionary = {}  # multi_mods["speed"]["wings"] = 1.5

# ──────────────────────────────────────────────
# Добавить плоский бонус к характеристике
#   organ_id  — уникальный идентификатор органа (его имя класса или ID)
#   stat_name — имя характеристики, напр. "speed"
#   value     — величина бонуса (может быть отрицательной)
# ──────────────────────────────────────────────
func add_flat(organ_id: String, stat_name: String, value: float) -> void:
	if not _flat_mods.has(stat_name):
		_flat_mods[stat_name] = {}
	_flat_mods[stat_name][organ_id] = value

# ──────────────────────────────────────────────
# Добавить мультипликатор к характеристике
# Мультипликаторы перемножаются между собой
# ──────────────────────────────────────────────
func add_multiplier(organ_id: String, stat_name: String, value: float) -> void:
	if not _multi_mods.has(stat_name):
		_multi_mods[stat_name] = {}
	_multi_mods[stat_name][organ_id] = value

# ──────────────────────────────────────────────
# Убрать все модификаторы данного органа
# Вызывается автоматически при отсоединении органа
# ──────────────────────────────────────────────
func remove_organ_mods(organ_id: String) -> void:
	for stat_name in _flat_mods:
		_flat_mods[stat_name].erase(organ_id)
	for stat_name in _multi_mods:
		_multi_mods[stat_name].erase(organ_id)

# ──────────────────────────────────────────────
# Получить итоговое значение характеристики
# final = (base + sum(flat_mods)) * product(multipliers)
# ──────────────────────────────────────────────
func get_stat(stat_name: String) -> float:
	var base: float = get("base_" + stat_name)
	if base == null:
		push_warning("EntityStats: неизвестная характеристика '%s'" % stat_name)
		return 0.0

	var flat_sum: float = 0.0
	if _flat_mods.has(stat_name):
		for v in _flat_mods[stat_name].values():
			flat_sum += v

	var multi_product: float = 1.0
	if _multi_mods.has(stat_name):
		for v in _multi_mods[stat_name].values():
			multi_product *= v

	return (base + flat_sum) * multi_product

# ──────────────────────────────────────────────
# Удобные геттеры для часто используемых характеристик
# (чтобы не писать get_stat("speed") везде в Entity)
# ──────────────────────────────────────────────
func speed()         -> float: return get_stat("speed")
func turn_speed()    -> float: return get_stat("turn_speed")
func wander_radius() -> float: return get_stat("wander_radius")
func vision_range()  -> float: return get_stat("vision_range")
func vision_angle()  -> float: return get_stat("vision_angle")
func smell_radius()  -> float: return get_stat("smell_radius")
func max_energy()    -> float: return get_stat("max_energy")
func energy_drain()  -> float: return get_stat("energy_drain")
func armor()         -> float: return get_stat("armor")
func attack()        -> float: return get_stat("attack")
func size()          -> float: return get_stat("size")

# ──────────────────────────────────────────────
# Создать копию для передачи ребёнку
# ──────────────────────────────────────────────
func clone() -> EntityStats:
	var copy := EntityStats.new()
	copy.base_speed         = base_speed
	copy.base_turn_speed    = base_turn_speed
	copy.base_wander_radius = base_wander_radius
	copy.base_vision_range  = base_vision_range
	copy.base_vision_angle  = base_vision_angle
	copy.base_smell_radius  = base_smell_radius
	copy.base_max_energy    = base_max_energy
	copy.base_energy_drain  = base_energy_drain
	copy.base_armor         = base_armor
	copy.base_attack        = base_attack
	copy.base_size          = base_size
	# Модификаторы не копируем — они будут добавлены органами заново
	return copy
