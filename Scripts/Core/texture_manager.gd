# Scripts/Core/texture_manager.gd
class_name TextureManager
extends Node

static var _instance: TextureManager
var _atlas_texture: ImageTexture
var _uv_cache: Dictionary = {} # path -> TextureUV
var _pending_textures: Dictionary = {} # path -> Image

func _enter_tree() -> void:
	if _instance != null:
		queue_free()
		return
	_instance = self
	set_process_mode(Node.PROCESS_MODE_ALWAYS)

func register_texture(path: String) -> void:
	if path in _pending_textures:
		return
		
	if not FileAccess.file_exists(path):
		MyLogger.error("Texture file not found: %s" % path)
		return
		
	var image = Image.load_from_file(path)
	if image:
		_pending_textures[path] = image
	else:
		MyLogger.error("Failed to load image: %s" % path)

func build_atlas() -> void:
	if _pending_textures.is_empty():
		return
		
	MyLogger.info("Building atlas from %d textures..." % _pending_textures.size())
	
	# Determine tile size (assume first image size)
	var first_img = _pending_textures.values()[0]
	var tile_size = first_img.get_width()
	
	# Calculate atlas size
	var count = _pending_textures.size()
	var atlas_width = int(ceil(sqrt(count))) * tile_size
	var atlas_height = int(ceil(float(count * tile_size) / atlas_width)) * tile_size
	
	# Power of 2
	atlas_width = _next_power_of_2(atlas_width)
	atlas_height = _next_power_of_2(atlas_height)
	
	var atlas_image = Image.create(atlas_width, atlas_height, false, Image.FORMAT_RGBA8)
	
	var x = 0
	var y = 0
	
	for path in _pending_textures:
		var img = _pending_textures[path]
		if img.get_width() != tile_size or img.get_height() != tile_size:
			img.resize(tile_size, tile_size)
			
		if x + tile_size > atlas_width:
			x = 0
			y += tile_size
			
		atlas_image.blit_rect(img, Rect2i(0, 0, tile_size, tile_size), Vector2i(x, y))
		
		var uv_rect = Rect2(
			float(x) / atlas_width,
			float(y) / atlas_height,
			float(tile_size) / atlas_width,
			float(tile_size) / atlas_height
		)
		
		# We use path as the key for retrieval
		_uv_cache[path] = TextureUV.new("main", 0, uv_rect)
		
		x += tile_size
		
	_atlas_texture = ImageTexture.create_from_image(atlas_image)
	MyLogger.success("Atlas generated: %dx%d" % [atlas_width, atlas_height])

func get_texture_uv(path: String) -> TextureUV:
	return _uv_cache.get(path)

static func get_instance() -> TextureManager:
	return _instance

static func get_main_atlas() -> Texture2D:
	if _instance:
		return _instance._atlas_texture
	return null

func _next_power_of_2(v: int) -> int:
	if v == 0: return 1
	v -= 1
	v |= v >> 1
	v |= v >> 2
	v |= v >> 4
	v |= v >> 8
	v |= v >> 16
	v += 1
	return v
