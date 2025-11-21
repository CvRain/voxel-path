# Scripts/Core/config_loader.gd
class_name ConfigLoader
extends Node

var _config_cache: Dictionary = {}

static func load_json(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		MyLogger.error("File not found: %s" % path)
		return {}
	
	var json_str = FileAccess.get_file_as_string(path)
	if json_str.is_empty():
		MyLogger.error("File is empty: %s" % path)
		return {}
	
	var json = JSON.new()
	var error = json.parse(json_str)
	
	if error != OK:
		MyLogger.error("Failed to parse JSON: %s" % path)
		return {}
	
	return json.data if json.data is Dictionary else {}

func load_json_cached(path: String) -> Dictionary:
	if path in _config_cache:
		return _config_cache[path]
	
	var data = ConfigLoader.load_json(path)
	_config_cache[path] = data
	return data

static func load_all_json_in_directory(dir_path: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var dir = DirAccess.open(dir_path)
	
	if dir == null:
		MyLogger.error("Directory not found: %s" % dir_path)
		return results
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if file_name.ends_with(".json") and not file_name.begins_with("_"):
			var file_path = dir_path.path_join(file_name)
			var data = load_json(file_path)
			if not data.is_empty():
				results.append(data)
		
		file_name = dir.get_next()
	
	return results

func clear_cache() -> void:
	_config_cache.clear()
	MyLogger.info("Config cache cleared")
