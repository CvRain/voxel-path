# Scripts/Voxel/block_registry.gd
class_name BlockRegistry
extends Node

static var _instance: BlockRegistry
static var _blocks: Dictionary = {}
static var _block_names: Dictionary = {}
static var _next_mod_block_id: int = Constants.FIRST_MOD_BLOCK_ID

func _enter_tree() -> void:
	if _instance != null:
		queue_free()
		return
	_instance = self
	set_process_mode(Node.PROCESS_MODE_ALWAYS)

static func register_block(block: BlockData) -> bool:
	if block.id <= 0:
		MyLogger.error("Block ID must be > 0: %s" % block.name)
		return false
	
	if block.id in _blocks:
		MyLogger.error("Block ID already registered: %d" % block.id)
		return false
	
	if block.name in _block_names:
		MyLogger.error("Block name already registered: %s" % block.name)
		return false
	
	_blocks[block.id] = block
	_block_names[block.name] = block.id
	return true

static func allocate_mod_block_id() -> int:
	var id = _next_mod_block_id
	_next_mod_block_id += 1
	return id

static func get_block(block_id: int) -> BlockData:
	return _blocks.get(block_id)

static func get_block_by_name(block_name: String) -> BlockData:
	var id = _block_names.get(block_name, -1)
	return _blocks.get(id) if id >= 0 else null

static func get_all_block_ids() -> Array:
	return _blocks.keys()

static func has_block(block_id: int) -> bool:
	return block_id in _blocks

static func get_block_count() -> int:
	return _blocks.size()

static func debug_print_blocks() -> void:
	print("=== Registered Blocks (%d) ===" % _blocks.size())
	for block_id in _blocks:
		var block = _blocks[block_id]
		print("  [%3d] %-20s %-30s [%s]" % [block_id, block.name, block.display_name, block.category])
	for i in range(60):
		print("=")

static func get_instance() -> BlockRegistry:
	return _instance
