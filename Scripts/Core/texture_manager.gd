extends Node3D

var _atlas_texture: ImageTexture
var _uv_cache: Dictionary = {} # path -> TextureUV
var _pending_textures: Dictionary = {} # path -> Image
var _texture_frame_counts: Dictionary = {} # path -> int (number of frames for strips)

func register_texture(path: String) -> void:
	if path in _pending_textures or path in _texture_frame_counts:
		return
		
	if not FileAccess.file_exists(path):
		MyLogger.error("Texture file not found: %s" % path)
		return
		
	# Use ResourceLoader to load the image properly in both editor and export
	var texture = load(path)
	if texture is Texture2D:
		var image = texture.get_image()
		if image:
			# Ensure format is RGBA8 for atlas consistency
			if image.get_format() != Image.FORMAT_RGBA8:
				image.convert(Image.FORMAT_RGBA8)
				
			var w = image.get_width()
			var h = image.get_height()
			
			# Check for vertical strip (16x112, 16x32, etc)
			# We assume tiles are square based on width
			if h > w and h % w == 0:
				var frames = int(h / w)
				_texture_frame_counts[path] = frames
				MyLogger.debug("Detected texture strip: %s (%d frames)" % [path, frames])
				
				for i in range(frames):
					var frame_img = image.get_region(Rect2i(0, i * w, w, w))
					var frame_key = "%s#%d" % [path, i]
					_pending_textures[frame_key] = frame_img
			else:
				_pending_textures[path] = image
				_texture_frame_counts[path] = 1
		else:
			MyLogger.error("Failed to get image data from texture: %s" % path)
	else:
		MyLogger.error("Failed to load texture resource: %s" % path)

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

func get_texture_uv(path: String, frame: int = 0) -> TextureUV:
	if frame > 0:
		var frame_key = "%s#%d" % [path, frame]
		return _uv_cache.get(frame_key)
	
	# Try direct path first (for non-strips)
	if path in _uv_cache:
		return _uv_cache[path]
		
	# If path was a strip, default to frame 0
	var frame0_key = "%s#0" % path
	return _uv_cache.get(frame0_key)

func get_frame_count(path: String) -> int:
	return _texture_frame_counts.get(path, 1)

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
