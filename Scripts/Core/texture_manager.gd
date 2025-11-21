# Scripts/Core/texture_manager.gd
class_name TextureManager
extends Node

static var _instance: TextureManager
var _atlases: Dictionary = {}
var _tile_cache: Dictionary = {}
var _atlas_configs: Dictionary = {}

func _enter_tree() -> void:
	if _instance != null:
		queue_free()
		return
	_instance = self
	set_process_mode(Node.PROCESS_MODE_ALWAYS)

func register_atlas(atlas_name: String, atlas_config: Dictionary) -> void:
	var texture_path = atlas_config.get("path", "")
	
	if not ResourceLoader.exists(texture_path):
		MyLogger.error("Texture not found: %s" % texture_path)
		return
	
	if atlas_name in _atlases:
		MyLogger.warn("Overwriting existing atlas: %s" % atlas_name)
	
	var texture = load(texture_path) as Texture2D
	if texture == null:
		MyLogger.error("Failed to load texture: %s" % texture_path)
		return
	
	_atlases[atlas_name] = texture
	_atlas_configs[atlas_name] = atlas_config
	
	_compute_tile_uvs(atlas_name, atlas_config)
	
	MyLogger.debug("Registered texture atlas: %s" % atlas_name)

func _compute_tile_uvs(atlas_name: String, atlas_config: Dictionary) -> void:
	var tile_size = atlas_config.get("tile_size", 16)
	var padding = atlas_config.get("padding", 0)
	var tiles_config = atlas_config.get("tiles", {})
	var texture = _atlases[atlas_name]
	
	var atlas_width = float(texture.get_width())
	var atlas_height = float(texture.get_height())
	var tiles_per_row = int(atlas_width / (tile_size + padding))
	
	for tile_name in tiles_config:
		var tile_index = tiles_config[tile_name]
		var row = tile_index / tiles_per_row
		var col = tile_index % tiles_per_row
		
		var pixel_x = col * (tile_size + padding) + padding
		var pixel_y = row * (tile_size + padding) + padding
		
		var uv_x = float(pixel_x) / atlas_width
		var uv_y = float(pixel_y) / atlas_height
		var uv_size_x = float(tile_size) / atlas_width
		var uv_size_y = float(tile_size) / atlas_height
		
		var uv_rect = Rect2(uv_x, uv_y, uv_size_x, uv_size_y)
		var cache_key = "%s:%s" % [atlas_name, tile_name]
		
		_tile_cache[cache_key] = TextureUV.new(atlas_name, tile_index, uv_rect)

static func get_texture_uv(atlas_name: String, tile_name: String) -> TextureUV:
	if _instance == null:
		return null
	
	var cache_key = "%s:%s" % [atlas_name, tile_name]
	var uv = _instance._tile_cache.get(cache_key)
	
	if uv == null:
		MyLogger.warn("Texture UV not found: %s:%s" % [atlas_name, tile_name])
	
	return uv

static func get_atlas_texture(atlas_name: String) -> Texture2D:
	if _instance == null:
		return null
	return _instance._atlases.get(atlas_name)

static func has_atlas(atlas_name: String) -> bool:
	return _instance != null and atlas_name in _instance._atlases

static func get_instance() -> TextureManager:
	return _instance
