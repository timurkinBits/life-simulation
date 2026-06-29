extends Node

var _all_organs: Array[OrganData] = []

func _ready() -> void:
	_scan_folder("res://organs/")

func _scan_folder(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if dir.current_is_dir() and fname != "." and fname != "..":
			_scan_folder(path + fname + "/")
		elif fname.ends_with(".tres") or fname.ends_with(".res"):
			var full_path := path + fname
			var res = load(full_path)
			if res is OrganData:
				register_organ(res)
		fname = dir.get_next()
	dir.list_dir_end()

func register_organ(data: OrganData) -> void:
	for existing in _all_organs:
		if existing.scene_path == data.scene_path:
			return
	_all_organs.append(data)

func random_organ(exclude_paths: Array = []) -> OrganData:
	var pool: Array = []
	var total: float = 0.0
	for organ in _all_organs:
		if organ.scene_path in exclude_paths:
			continue
		pool.append(organ)
		total += organ.spawn_weight

	if pool.is_empty():
		return null

	var r: float = randf() * total
	var acc: float = 0.0
	for organ in pool:
		acc += organ.spawn_weight
		if r <= acc:
			return organ
	return pool[-1]

func all_organs() -> Array[OrganData]:
	return _all_organs.duplicate()

func random_starting_organs(count: int = 1) -> Array[OrganData]:
	var result: Array[OrganData] = []
	var used_paths: Array = []
	for i in count:
		var template := random_organ(used_paths)
		if template == null:
			break
		var instance := template.exact_copy()
		result.append(instance)
		used_paths.append(instance.scene_path)
	return result
