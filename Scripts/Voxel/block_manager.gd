# Scripts/Voxel/block_manager.gd
class_name BlockManager
extends Node

static var _instance: BlockManager

var _config_loader: ConfigLoader
var _texture_manager: TextureManager
var _block_registry: BlockRegistry

var _loaded_categories: Dictionary = {}
var _manifest: Dictionary = {}
var _loading_complete: bool = false

signal loading_started
signal loading_progress(current: int, total: int)
signal loading_complete

func _enter_tree() -> void:
	if _instance != null:
		queue_free()
		return
	_instance = self
	set_process_mode(Node.PROCESS_MODE_ALWAYS)

func _ready() -> void:
	_config_loader = ConfigLoader.new()
	add_child(_config_loader)
	
	_texture_manager = TextureManager.get_instance()
	if _texture_manager == null:
		MyLogger.error("TextureManager not found")
		return
	
	_block_registry = BlockRegistry.get_instance()
	if _block_registry == null:
		MyLogger.error("BlockRegistry not found")
		return
	
	# Initialize BlockStateRegistry
	var BlockStateRegistryScript = load("res://Scripts/Voxel/block_state_registry.gd")
	if not BlockStateRegistryScript.get_instance():
		add_child(BlockStateRegistryScript.new())
	
	load_all_blocks()

func load_all_blocks() -> void:
	MyLogger.info("=== Starting Block Loading ===")
	loading_started.emit()
	
	_manifest = _config_loader.load_json_cached(Constants.DATA_BLOCKS_MANIFEST)
	if _manifest.is_empty():
		MyLogger.error("Failed to load manifest")
		return
	
	var categories = _manifest.get("categories", [])
	categories.sort_custom(func(a, b): return a.get("priority", 0) < b.get("priority", 0))
	
	var total = categories.size()
	var current = 0
	
	for category_info in categories:
		if not category_info.get("enabled", true):
			MyLogger.info("Skipping disabled category: %s" % category_info.get("path"))
			current += 1
			continue
		
		load_category(category_info)
		current += 1
		loading_progress.emit(current, total)
	
	_texture_manager.build_atlas()
	_resolve_all_block_uvs()
	
	_loading_complete = true
	MyLogger.success("Block loading complete. Total blocks: %d" % BlockRegistry.get_block_count())
	loading_complete.emit()

func load_category(category_info: Dictionary) -> void:
	var category_path = category_info.get("path", "")
	var config_file = category_info.get("config", "config.json")
	var config_path = category_path.path_join(config_file)
	
	MyLogger.info("Loading category: %s" % category_path)
	
	var category_config = _config_loader.load_json_cached(config_path)
	if category_config.is_empty():
		MyLogger.error("Failed to load category config: %s" % config_path)
		return
	
	var category_name = category_config.get("category", "unknown")
	
	# Textures are now loaded per-block
	# await _load_category_textures(category_config)
	_load_category_blocks(category_path, category_config)
	
	_loaded_categories[category_name] = category_config
	MyLogger.debug("Category loaded: %s" % category_name)

func _load_category_textures(category_config: Dictionary) -> void:
	pass # Deprecated: Textures are loaded from block files directly

func _load_category_blocks(category_path: String, category_config: Dictionary) -> void:
	var block_files = category_config.get("blocks", [])
	
	for block_file in block_files:
		var block_path = category_path.path_join(block_file)
		var block_config = _config_loader.load_json_cached(block_path)
		
		if block_config.is_empty():
			MyLogger.error("Failed to load block: %s" % block_path)
			continue
		
		_create_and_register_block(block_config)

func _create_and_register_block(block_config: Dictionary) -> BlockData:
	var block = BlockData.new()
	
	# ID is now assigned dynamically by BlockRegistry
	# block.id = block_config.get("id", -1) 
	block.name = block_config.get("name", "")
	block.display_name = block_config.get("display_name", block.name)
	block.category = block_config.get("category", "unknown")
	block.description = block_config.get("description", "")
	
	var properties = block_config.get("properties", {})
	block.hardness = properties.get("hardness", 1.0)
	block.resistance = properties.get("resistance", 1.0)
	block.is_solid = properties.get("is_solid", true)
	block.is_transparent = properties.get("is_transparent", false)
	
	var physics = block_config.get("physics", {})
	block.has_collision = physics.get("has_collision", true)
	
	var interactions = block_config.get("interactions", {})
	block.can_place = interactions.get("can_place", true)
	block.can_break = interactions.get("can_break", true)
	block.tool_required = interactions.get("tool_required", "none")
	block.mine_level = interactions.get("mine_level", 0)
	block.mine_time = interactions.get("mine_time", 1.0)
	
	# Load State Definitions
	block.state_definitions = block_config.get("states", {})
	block.default_state = block_config.get("default_state", {})
	
	_load_block_textures(block, block_config)
	
	if block.validate():
		BlockRegistry.register_block(block)
		
		# Register Block States
		var BlockStateRegistryScript = load("res://Scripts/Voxel/block_state_registry.gd")
		if BlockStateRegistryScript.get_instance():
			BlockStateRegistryScript.get_instance().register_block_states(block)
			
		if Constants.DEBUG_BLOCK_LOADING:
			MyLogger.debug("Registered block: %s (id: %d)" % [block.name, block.id])
	else:
		MyLogger.error("Invalid block config: %s" % block_config)
	
	return block

func _load_block_textures(block: BlockData, block_config: Dictionary) -> void:
	var textures_config = block_config.get("textures", {})
	
	# Handle "all" shortcut
	if "all" in textures_config:
		var path = textures_config["all"]
		block.texture_paths["all"] = path
		_texture_manager.register_texture(path)
		
	# Handle specific faces
	for face in ["top", "bottom", "left", "right", "front", "back", "side"]:
		if face in textures_config:
			var path = textures_config[face]
			block.texture_paths[face] = path
			_texture_manager.register_texture(path)

func _resolve_all_block_uvs() -> void:
	var block_ids = BlockRegistry.get_all_block_ids()
	for id in block_ids:
		var block = BlockRegistry.get_block(id)
		if not block: continue
		
		# Handle "all"
		if "all" in block.texture_paths:
			var path = block.texture_paths["all"]
			var uv = _texture_manager.get_texture_uv(path)
			if uv:
				block.textures["diffuse"] = uv
		
		# Handle specific faces
		for face in ["top", "bottom", "left", "right", "front", "back"]:
			var path = null
			if face in block.texture_paths:
				path = block.texture_paths[face]
			elif "side" in block.texture_paths and face in ["left", "right", "front", "back"]:
				path = block.texture_paths["side"]
			
			if path:
				var uv = _texture_manager.get_texture_uv(path)
				if uv:
					block.textures["%s_diffuse" % face] = uv

static func get_loaded_categories() -> Dictionary:
	return _instance._loaded_categories.duplicate() if _instance else {}

static func is_loading_complete() -> bool:
	return _instance != null and _instance._loading_complete

static func debug_print_categories() -> void:
	if _instance == null:
		return
	
	print("=== Loaded Categories ===")
	for cat_name in _instance._loaded_categories:
		var config = _instance._loaded_categories[cat_name]
		var blocks_count = config.get("blocks", []).size()
		print("  [%s] %s - %d blocks" % [cat_name, config.get("display_name"), blocks_count])

static func get_instance() -> BlockManager:
	return _instance
