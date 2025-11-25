extends Node3D

var _noise: FastNoiseLite
var _chunks: Dictionary = {} # Vector2i -> Chunk
var _is_generating: bool = false

# World Generation Settings
const WORLD_SIZE_CHUNKS: int = 4 # 4x4 chunks
const TERRAIN_HEIGHT_SCALE: float = 512.0
const TERRAIN_BASE_HEIGHT: float = 256.0
const TERRAIN_VOXEL_SCALE: int = 2 # 4x4x4 voxel groups (1m x 1m x 1m)

# Block IDs (cached on load)
var _id_stone: int = 0
var _id_dirt: int = 0
var _id_grass: int = 0
var _id_bedrock: int = 0
var _id_log: int = 0
var _id_leaves: int = 0
var _id_water: int = 0

func _ready() -> void:
	_initialize_systems()

func _initialize_systems() -> void:
	print("Initializing systems for RandomWorld...")
	
	# Setup Noise
	_noise = FastNoiseLite.new()
	_noise.seed = randi()
	_noise.frequency = 0.00125
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 5
	
	# Ensure singletons are present if not autoloaded (TextureManager/BlockRegistry are usually singletons or managed by World)
	# In this project structure, they seem to be added as children.
	
	if not TextureManager.get_instance():
		add_child(TextureManager.new())
	
	if not BlockRegistry.get_instance():
		add_child(BlockRegistry.new())
	
	# Initialize BlockBehavior system
	var BlockBehaviorScript = load("res://Scripts/Voxel/block_behavior.gd")
	if not BlockBehaviorScript.get_instance():
		add_child(BlockBehaviorScript.new())
	
	var block_manager = BlockManager.new()
	block_manager.loading_complete.connect(_on_loading_complete)
	add_child(block_manager)

func _on_loading_complete() -> void:
	print("Block loading complete. Generating world...")
	_cache_block_ids()
	_generate_world()

func _cache_block_ids() -> void:
	var stone = BlockRegistry.get_block_by_name("stone")
	var dirt = BlockRegistry.get_block_by_name("dirt")
	var grass = BlockRegistry.get_block_by_name("grass")
	var bedrock = BlockRegistry.get_block_by_name("bedrock")
	var oak_log = BlockRegistry.get_block_by_name("oak_log")
	var leaves = BlockRegistry.get_block_by_name("oak_leaves")
	var water = BlockRegistry.get_block_by_name("water")
	
	if stone: _id_stone = stone.id
	if dirt: _id_dirt = dirt.id
	if grass: _id_grass = grass.id
	if bedrock: _id_bedrock = bedrock.id
	if oak_log: _id_log = oak_log.id
	if leaves: _id_leaves = leaves.id
	if water: _id_water = water.id
	
	print("Cached Block IDs: Stone=%d, Dirt=%d, Grass=%d, Bedrock=%d, Log=%d, Leaves=%d, Water=%d" % [_id_stone, _id_dirt, _id_grass, _id_bedrock, _id_log, _id_leaves, _id_water])

func _generate_world() -> void:
	if _is_generating: return
	_is_generating = true
	print("Starting world generation...")
	
	var start_time = Time.get_ticks_msec()
	
	# 1. Create Chunks
	for cx in range(WORLD_SIZE_CHUNKS):
		for cz in range(WORLD_SIZE_CHUNKS):
			print("Creating chunk %d,%d" % [cx, cz])
			var chunk_pos = Vector2i(cx, cz)
			var chunk = Chunk.new(chunk_pos)
			# Position in world space
			chunk.position = Vector3(cx * Constants.CHUNK_WORLD_SIZE, 0, cz * Constants.CHUNK_WORLD_SIZE)
			add_child(chunk)
			_chunks[chunk_pos] = chunk
			
			# Try to load first, if not found, generate
			var ChunkSerializerScript = load("res://Scripts/Persistence/chunk_serializer.gd")
			if not ChunkSerializerScript.load_chunk(chunk, SAVE_DIR_CHUNKS):
				_fill_chunk_data(chunk)
			else:
				print("Loaded chunk %d,%d from disk" % [cx, cz])
	
		# 2. Link Neighbors
	for pos in _chunks:
		var chunk = _chunks[pos]
		chunk.neighbor_left = _chunks.get(pos + Vector2i(-1, 0))
		chunk.neighbor_right = _chunks.get(pos + Vector2i(1, 0))
		chunk.neighbor_front = _chunks.get(pos + Vector2i(0, -1)) # -Z is Front in our logic? Wait, grid logic usually: Z-1 is "North/Front"
		chunk.neighbor_back = _chunks.get(pos + Vector2i(0, 1))
	
	# 3. Decorate World (Trees, etc)
	# We do this after all chunks are created so we can place blocks across chunk boundaries
	print("Decorating world...")
	for chunk in _chunks.values():
		_decorate_chunk(chunk)
	
	# 4. Generate Meshes
	print("Generating meshes...")
	var chunks_processed = 0
	for chunk in _chunks.values():
		chunk.generate_mesh()
		
		chunks_processed += 1
		# 每处理 2 个区块，暂停一帧，让出主线程给渲染和物理引擎
		# 同时也让后台线程池有机会消化一下刚才提交的网格生成任务
		if chunks_processed % 2 == 0:
			await get_tree().process_frame
		
	var end_time = Time.get_ticks_msec()
	print("World generation took: %d ms" % (end_time - start_time))
	
	# Move player to surface
	_spawn_player()
	
	_is_generating = false

func _decorate_chunk(chunk: Chunk) -> void:
	# Simple tree generation
	# Iterate over the chunk surface and decide where to place trees
	var cx_offset = chunk.chunk_position.x * Constants.CHUNK_SIZE
	var cz_offset = chunk.chunk_position.y * Constants.CHUNK_SIZE
	
	# Use a deterministic random generator based on chunk position
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(chunk.chunk_position)
	
	for x in range(2, Constants.CHUNK_SIZE - 2, 4): # Step 4 to avoid too dense forests
		for z in range(2, Constants.CHUNK_SIZE - 2, 4):
			# Check noise for "Forest" biome
			var world_x = cx_offset + x
			var world_z = cz_offset + z
			
			# Use a different noise frequency for biomes
			var biome_val = _noise.get_noise_2d(world_x * 0.5, world_z * 0.5)
			
			if biome_val > 0.2: # Forest biome
				if rng.randf() < 0.3: # 30% chance in forest
					# Find surface height
					var surface_y = _get_surface_height(chunk, x, z)
					if surface_y > 0:
						_generate_tree(world_x, surface_y, world_z)

func _get_surface_height(chunk: Chunk, x: int, z: int) -> int:
	# Scan from top down
	for y in range(Constants.VOXEL_MAX_HEIGHT - 1, 0, -1):
		var block_id = chunk.get_voxel(x, y, z)
		if block_id == _id_grass:
			return y + 1
	return -1

func _generate_tree(world_x: int, y: int, world_z: int) -> void:
	var height = 4 + randi() % 3
	
	# Trunk
	for i in range(height):
		set_voxel_at_raw(Vector3i(world_x, y + i, world_z), _id_log)
		
	# Leaves
	var leaf_start_y = y + height - 2
	var leaf_end_y = y + height + 1
	
	for ly in range(leaf_start_y, leaf_end_y + 1):
		var radius = 2
		if ly == leaf_end_y: radius = 1 # Top is narrower
		
		for lx in range(world_x - radius, world_x + radius + 1):
			for lz in range(world_z - radius, world_z + radius + 1):
				# Skip corners for rounded look
				if abs(lx - world_x) == radius and abs(lz - world_z) == radius:
					continue
					
				if get_voxel_at(Vector3i(lx, ly, lz)) == Constants.AIR_BLOCK_ID:
					set_voxel_at_raw(Vector3i(lx, ly, lz), _id_leaves)

const SAVE_DIR_BASE = "user://saves/world_test/"
const SAVE_DIR_CHUNKS = "user://saves/world_test/chunks/"

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_K:
			save_world()
		elif event.keycode == KEY_L:
			load_world()

func save_world() -> void:
	print("Saving world...")
	var start_time = Time.get_ticks_msec()
	
	var ChunkSerializerScript = load("res://Scripts/Persistence/chunk_serializer.gd")
	var PlayerSerializerScript = load("res://Scripts/Persistence/player_serializer.gd")
	
	# 1. Save Chunks
	for chunk_pos in _chunks:
		var chunk = _chunks[chunk_pos]
		ChunkSerializerScript.save_chunk(chunk, SAVE_DIR_CHUNKS)
	
	# 2. Save Player
	var player = $ProtoController
	if player:
		PlayerSerializerScript.save_player(player, SAVE_DIR_BASE)
			
	var end_time = Time.get_ticks_msec()
	print("World saved in %d ms" % (end_time - start_time))
	
	# Show a toast or message (optional)

func load_world() -> void:
	if _is_generating:
		print("World is currently processing, please wait.")
		return
		
	_is_generating = true # Reuse this flag to prevent double loading
	print("Loading world...")
	var start_time = Time.get_ticks_msec()
	
	var ChunkSerializerScript = load("res://Scripts/Persistence/chunk_serializer.gd")
	var PlayerSerializerScript = load("res://Scripts/Persistence/player_serializer.gd")
	var loaded_count = 0
	
	# 1. Load Chunks
	var chunks_processed = 0
	for chunk_pos in _chunks:
		var chunk = _chunks[chunk_pos]
		if ChunkSerializerScript.load_chunk(chunk, SAVE_DIR_CHUNKS):
			loaded_count += 1
			# After loading data, we must regenerate the mesh
			chunk.generate_mesh()
		
		chunks_processed += 1
		# 每处理 2 个区块，暂停一帧，让出主线程给渲染和物理引擎
		# 同时也让后台线程池有机会消化一下刚才提交的网格生成任务
		if chunks_processed % 2 == 0:
			await get_tree().process_frame
	
	# 2. Load Player
	var player = $ProtoController
	if player:
		if PlayerSerializerScript.load_player(player, SAVE_DIR_BASE):
			print("Player state loaded.")
	
	var end_time = Time.get_ticks_msec()
	print("World loaded (%d chunks) in %d ms" % [loaded_count, end_time - start_time])
	_is_generating = false

func _spawn_player() -> void:
	var player = $ProtoController
	if not player: return
	
	# Try to load player state first
	var PlayerSerializerScript = load("res://Scripts/Persistence/player_serializer.gd")
	if PlayerSerializerScript.load_player(player, SAVE_DIR_BASE):
		print("Player spawned from save file.")
		return
	
	# Fallback to default spawn logic
	var center_x = (WORLD_SIZE_CHUNKS * Constants.CHUNK_SIZE) / 2
	var center_z = (WORLD_SIZE_CHUNKS * Constants.CHUNK_SIZE) / 2
	
	# Find height at center
	var noise_val = _noise.get_noise_2d(center_x, center_z)
	var height = int(TERRAIN_BASE_HEIGHT + (noise_val * TERRAIN_HEIGHT_SCALE))
	
	# Convert to world coordinates (voxel units * voxel size)
	var spawn_pos = Vector3(center_x, height + 5, center_z) * Constants.VOXEL_SIZE
	player.global_position = spawn_pos
	print("Player spawned at: %s" % spawn_pos)

func _fill_chunk_data(chunk: Chunk) -> void:
	var cx_offset = chunk.chunk_position.x * Constants.CHUNK_SIZE
	var cz_offset = chunk.chunk_position.y * Constants.CHUNK_SIZE
	
	var step = TERRAIN_VOXEL_SCALE
	
	for x in range(0, Constants.CHUNK_SIZE, step):
		for z in range(0, Constants.CHUNK_SIZE, step):
			var world_x = cx_offset + x
			var world_z = cz_offset + z
			
			# Get height from noise
			var noise_val = _noise.get_noise_2d(world_x, world_z)
			var raw_height = int(TERRAIN_BASE_HEIGHT + (noise_val * TERRAIN_HEIGHT_SCALE))
			
			# Quantize height to step size (create flat layers)
			var height = int(round(raw_height / float(step)) * step)
			height = clamp(height, 0, Constants.VOXEL_MAX_HEIGHT - 1)
			
			# Fill the block group (step x step)
			for i in range(step):
				for k in range(step):
					var vx = x + i
					var vz = z + k
					
					if vx >= Constants.CHUNK_SIZE or vz >= Constants.CHUNK_SIZE:
						continue
					
					for y in range(height + 1):
						var block_id = Constants.AIR_BLOCK_ID
						
						if y == 0:
							block_id = _id_bedrock
						elif y < height - (step - 1): # Adjust soil depth based on scale
							block_id = _id_stone
						elif y < height:
							block_id = _id_dirt
						elif y == height:
							block_id = _id_grass
						
						if block_id != Constants.AIR_BLOCK_ID:
							chunk.set_voxel_raw(vx, y, vz, block_id)

func set_voxel_at(pos: Vector3i, block_id: int) -> void:
	var cx = floor(pos.x / float(Constants.CHUNK_SIZE))
	var cz = floor(pos.z / float(Constants.CHUNK_SIZE))
	var chunk_pos = Vector2i(cx, cz)
	
	if not _chunks.has(chunk_pos):
		return # Chunk not loaded or out of bounds
		
	var chunk = _chunks[chunk_pos]
	
	# Local coordinates
	var lx = pos.x % Constants.CHUNK_SIZE
	var lz = pos.z % Constants.CHUNK_SIZE
	var ly = pos.y
	
	if lx < 0: lx += Constants.CHUNK_SIZE
	if lz < 0: lz += Constants.CHUNK_SIZE
	
	chunk.set_voxel(lx, ly, lz, block_id)

func set_voxel_at_raw(pos: Vector3i, block_id: int) -> void:
	var cx = floor(pos.x / float(Constants.CHUNK_SIZE))
	var cz = floor(pos.z / float(Constants.CHUNK_SIZE))
	var chunk_pos = Vector2i(cx, cz)
	
	if not _chunks.has(chunk_pos):
		return
		
	var chunk = _chunks[chunk_pos]
	
	# Local coordinates
	var lx = pos.x % Constants.CHUNK_SIZE
	var lz = pos.z % Constants.CHUNK_SIZE
	var ly = pos.y
	
	if lx < 0: lx += Constants.CHUNK_SIZE
	if lz < 0: lz += Constants.CHUNK_SIZE
	
	chunk.set_voxel_raw(lx, ly, lz, block_id)

func update_chunks(chunk_keys: Array) -> void:
	for key in chunk_keys:
		if _chunks.has(key):
			_chunks[key].generate_mesh()

func update_chunks_sections(changes: Dictionary) -> void:
	for chunk_pos in changes:
		if _chunks.has(chunk_pos):
			var section_indices = changes[chunk_pos]
			# Use the optimized method to update only specific sections with one snapshot
			_chunks[chunk_pos].update_specific_sections(section_indices)

func get_voxel_at(pos: Vector3i) -> int:
	var cx = floor(pos.x / float(Constants.CHUNK_SIZE))
	var cz = floor(pos.z / float(Constants.CHUNK_SIZE))
	var chunk_pos = Vector2i(cx, cz)
	
	if not _chunks.has(chunk_pos):
		return Constants.AIR_BLOCK_ID
		
	var chunk = _chunks[chunk_pos]
	
	# Local coordinates
	var lx = pos.x % Constants.CHUNK_SIZE
	var lz = pos.z % Constants.CHUNK_SIZE
	var ly = pos.y
	
	if lx < 0: lx += Constants.CHUNK_SIZE
	if lz < 0: lz += Constants.CHUNK_SIZE
	
	return chunk.get_voxel(lx, ly, lz)
