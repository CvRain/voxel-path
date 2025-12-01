# Scenes/World.gd
extends Node3D

var _ui_label: Label

func _ready() -> void:
	MyLogger.info("=== Voxel Path Starting ===")
	MyLogger.info("Game: %s v%s" % [Constants.GAME_NAME, Constants.VERSION])
	
	_initialize_systems()
	
	await get_tree().process_frame

func _initialize_systems() -> void:
	var texture_manager = TextureManager.new()
	add_child(texture_manager)
	MyLogger.debug("TextureManager initialized")
	
	await get_tree().process_frame
	
	var block_registry = BlockRegistry.new()
	add_child(block_registry)
	MyLogger.debug("BlockRegistry initialized")
	
	await get_tree().process_frame
	
	var block_manager = BlockManager.new()
	add_child(block_manager)
	block_manager.loading_complete.connect(_on_block_loading_complete)
	MyLogger.debug("BlockManager initialized")

func _on_block_loading_complete() -> void:
	MyLogger.success("All systems initialized!")
	
	if Constants.DEBUG_ENABLED:
		BlockRegistry.debug_print_blocks()
		BlockManager.debug_print_categories()
	
	var stone = BlockRegistry.get_block_by_name("stone")
	if stone:
		MyLogger.info("✓ Stone block loaded: %s" % stone)
		var diffuse_uv = stone.get_texture_uv("top", "diffuse")
		if diffuse_uv:
			MyLogger.info("  Diffuse UV: %s" % diffuse_uv)
