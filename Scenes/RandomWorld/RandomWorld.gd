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
	
	if stone: _id_stone = stone.id
	if dirt: _id_dirt = dirt.id
	if grass: _id_grass = grass.id
	if bedrock: _id_bedrock = bedrock.id
	
	print("Cached Block IDs: Stone=%d, Dirt=%d, Grass=%d, Bedrock=%d" % [_id_stone, _id_dirt, _id_grass, _id_bedrock])

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
			
			_fill_chunk_data(chunk)
	
	# 2. Link Neighbors
	for pos in _chunks:
		var chunk = _chunks[pos]
		chunk.neighbor_left = _chunks.get(pos + Vector2i(-1, 0))
		chunk.neighbor_right = _chunks.get(pos + Vector2i(1, 0))
		chunk.neighbor_front = _chunks.get(pos + Vector2i(0, -1)) # -Z is Front in our logic? Wait, grid logic usually: Z-1 is "North/Front"
		chunk.neighbor_back = _chunks.get(pos + Vector2i(0, 1))
	
	# 3. Generate Meshes
	print("Generating meshes...")
	for chunk in _chunks.values():
		chunk.generate_mesh()
		
	var end_time = Time.get_ticks_msec()
	print("World generation took: %d ms" % (end_time - start_time))
	
	# Move player to surface
	_spawn_player()
	
	_is_generating = false

func _spawn_player() -> void:
	var player = $ProtoController
	if not player: return
	
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
							chunk.set_voxel(vx, y, vz, block_id)
