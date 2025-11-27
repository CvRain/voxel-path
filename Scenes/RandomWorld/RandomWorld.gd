extends Node3D

# 引入区块生成阶段枚举
const ChunkGenerationStage = preload("res://Scripts/Voxel/chunk_generation_stage.gd").ChunkGenerationStage

var _world_generator: Node
var _fluid_manager: Node
var _chunks: Dictionary = {} # Vector2i -> Chunk
var _is_generating: bool = false
var _is_raining: bool = true # Default to raining for testing
var _rain_timer: float = 0.0

# 添加生成队列和相关变量
var _generation_queue: Array = [] # 存储待生成的区块和阶段
var _generation_timer: float = 0.0
const GENERATION_INTERVAL: float = 0.01 # 每0.01秒处理一个生成任务

# World Generation Settings
const WORLD_SIZE_CHUNKS: int = 4 # 4x4 chunks

func _ready() -> void:
		_initialize_systems()

func _initialize_systems() -> void:
		print("Initializing systems for RandomWorld...")
		
		# Ensure singletons are present
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
		
		# Initialize World Generator
		var WorldGeneratorScript = load("res://Scripts/Voxel/world_generator.gd")
		_world_generator = WorldGeneratorScript.new(randi())
		add_child(_world_generator)
		_world_generator.cache_block_ids()
		
		# Initialize Fluid Manager
		var FluidManagerScript = load("res://Scripts/Voxel/fluid_manager.gd")
		_fluid_manager = FluidManagerScript.new(self)
		add_child(_fluid_manager)
		
		_generate_world()

func _process(delta: float) -> void:
	# 处理分阶段地形生成
	_process_chunk_generation(delta)

# 处理分阶段区块生成
func _process_chunk_generation(delta: float) -> void:
	_generation_timer += delta
	
	if _generation_timer >= GENERATION_INTERVAL and not _generation_queue.is_empty():
		_generation_timer = 0.0
		
		# 从队列中取出一个生成任务
		var task = _generation_queue.pop_front()
		var chunk = task.chunk
		var stage = task.stage
		
		# 执行对应阶段的生成
		_world_generator.generate_chunk_stage(chunk, stage)
		
		# 更新区块生成阶段
		chunk.generation_stage = stage
		
		# 如果不是最终阶段，则将下一阶段加入队列
		if stage < ChunkGenerationStage.FULLY_GENERATED:
			_enqueue_chunk_generation(chunk, stage + 1)
		else:
			# 完全生成后更新网格
			chunk.generate_mesh()

# 将区块生成任务加入队列
func _enqueue_chunk_generation(chunk: Chunk, stage: int) -> void:
	_generation_queue.append({
		"chunk": chunk,
		"stage": stage
	})

# 修改 _generate_world 方法以使用分阶段生成
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
				# 将初始生成阶段加入队列
				_enqueue_chunk_generation(chunk, ChunkGenerationStage.BASE_TERRAIN)
			else:
				print("Loaded chunk %d,%d from disk" % [cx, cz])
				# 已加载的区块直接生成网格
				chunk.generate_mesh()
	
	# 2. Link Neighbors
	for pos in _chunks:
		var chunk = _chunks[pos]
		chunk.neighbor_left = _chunks.get(pos + Vector2i(-1, 0))
		chunk.neighbor_right = _chunks.get(pos + Vector2i(1, 0))
		chunk.neighbor_front = _chunks.get(pos + Vector2i(0, -1))
		chunk.neighbor_back = _chunks.get(pos + Vector2i(0, 1))
	
	var end_time = Time.get_ticks_msec()
	print("World generation initiated in %d ms" % (end_time - start_time))
	
	# Move player to surface
	_spawn_player()
	
	# 不再阻塞等待生成完成
	# _is_generating = false

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
		
		# Find height at center using WorldGenerator
		var height = _world_generator.get_noise_height(center_x, center_z)
		
		# Convert to world coordinates (voxel units * voxel size)
		var spawn_pos = Vector3(center_x, height + 5, center_z) * Constants.VOXEL_SIZE
		player.global_position = spawn_pos
		print("Player spawned at: %s" % spawn_pos)

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

func load_world() -> void:
		if _is_generating:
				print("World is currently processing, please wait.")
				return
				
		_is_generating = true
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
						chunk.generate_mesh()
				
				chunks_processed += 1
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

func set_voxel_at(pos: Vector3i, block_id: int) -> void:
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
