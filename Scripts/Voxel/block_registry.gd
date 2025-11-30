# Scripts/Voxel/block_registry.gd
extends Node

static var _blocks: Dictionary = {}
static var _block_names: Dictionary = {}
static var _next_free_id: int = 1 # Start from 1, 0 is reserved for Air

# ID Mapping Persistence
const MAPPING_FILE_PATH: String = "user://level_block_mappings.json"

func _enter_tree() -> void:
	# Load existing mappings if available
	_load_id_mappings()

static func register_block(block: BlockData) -> bool:
	if block.name.is_empty():
		push_error("[BlockRegistry] Block name cannot be empty! BlockData: %s" % str(block))
		MyLogger.error("Block name cannot be empty! BlockData: %s" % str(block))
		return false

	if block.name in _block_names:
		push_error("[BlockRegistry] Block name already registered: %s" % block.name)
		MyLogger.error("Block name already registered: %s" % block.name)
		return false

	# Dynamic ID Allocation with Persistence
	if block.name == "air":
		block.id = Constants.AIR_BLOCK_ID # 0
	else:
		# Check if this block name already has an assigned ID from previous sessions
		var existing_id = _get_existing_id_for_name(block.name)
		if existing_id != -1:
			block.id = existing_id
			# Ensure _next_free_id is always ahead of the max assigned ID
			if existing_id >= _next_free_id:
				_next_free_id = existing_id + 1
		else:
			# Assign next free ID
			block.id = _next_free_id
			_next_free_id += 1
			# Save the new mapping immediately (or batch save later)
			_save_id_mapping(block.name, block.id)

	if block.id < 0:
		push_warning("[BlockRegistry] Registered block with invalid ID: %s (%d)" % [block.name, block.id])
		MyLogger.warn("Registered block with invalid ID: %s (%d)" % [block.name, block.id])

	_blocks[block.id] = block
	_block_names[block.name] = block.id
	MyLogger.info("[BlockRegistry] Registered block: %s (ID=%d)" % [block.name, block.id])
	return true

# --- Persistence Logic ---

static var _persistent_mappings: Dictionary = {}

func _load_id_mappings() -> void:
	if not FileAccess.file_exists(MAPPING_FILE_PATH):
		return
		
	var file = FileAccess.open(MAPPING_FILE_PATH, FileAccess.READ)
	if file:
		var json_text = file.get_as_text()
		var json = JSON.new()
		var error = json.parse(json_text)
		if error == OK:
			var data = json.data
			if data is Dictionary:
				_persistent_mappings = data
				MyLogger.info("Loaded %d block ID mappings." % _persistent_mappings.size())
		else:
			MyLogger.error("Failed to parse block mappings: %s" % json.get_error_message())

static func _get_existing_id_for_name(block_name: String) -> int:
	if block_name in _persistent_mappings:
		return int(_persistent_mappings[block_name])
	return -1

static func _save_id_mapping(block_name: String, id: int) -> void:
	_persistent_mappings[block_name] = id
	# In a real game, you might want to save only on exit or world save.
	# For now, we save on every new registration to be safe.
	_save_mappings_to_disk()

static func _save_mappings_to_disk() -> void:
	var file = FileAccess.open(MAPPING_FILE_PATH, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(_persistent_mappings, "\t")
		file.store_string(json_string)
	else:
		MyLogger.error("Failed to save block mappings to %s" % MAPPING_FILE_PATH)

static func allocate_mod_block_id() -> int:
	# Deprecated: IDs are now allocated automatically in register_block
	return 0

static func get_block(block_id: int) -> BlockData:
	return _blocks.get(block_id)

static func get_block_by_name(block_name: String) -> BlockData:
	var id = _block_names.get(block_name, -1)
	var block = _blocks.get(id) if id >= 0 else null
	if block:
		print("[BlockRegistry] get_block_by_name:", block_name, "id:", block.id)
	else:
		print("[BlockRegistry] get_block_by_name:", block_name, "NOT FOUND!")
	return block

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
