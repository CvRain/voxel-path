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
var _section_generation_queue: Array = [] # 存储待生成的Section任务
var _generation_timer: float = 0.0
const GENERATION_INTERVAL: float = 0.1 # 增加间隔到0.1秒，减轻CPU压力
var _max_generations_per_frame: int = 1 # 每帧最多处理的生成任务数
var _spawn_area_radius:int =  5
var _view_distance: int = 10
var _keep_distance: int = 32

# 添加性能监控变量
var _last_process_time: float = 0.0
var _frame_count: int = 0
var _fps: float = 0.0
var _last_chunk_update: float = 0.0
const CHUNK_UPDATE_INTERVAL: float = 0.5 # 每0.5秒更新一次区块加载

var _player:CharacterBody3D

func _ready() -> void:
	_initialize_systems()
	# 在下一帧设置玩家引用，确保场景完全加载
	call_deferred("_setup_player")

func _setup_player() -> void:
	_player = $ProtoController
	# 初始化时加载玩家周围的区块
	_generate_spawn_area()

# 生成玩家出生区域
func _generate_spawn_area() -> void:
	if not _player:
		return
	
	print("Generating spawn area...")
	
	# 首先找到一个合适的出生点
	var spawn_position = _find_suitable_spawn_position()
	_player.global_position = spawn_position
	
	# 计算玩家所在的区块
	var player_chunk_x = floor(spawn_position.x / Constants.CHUNK_WORLD_SIZE)
	var player_chunk_z = floor(spawn_position.z / Constants.CHUNK_WORLD_SIZE)
	
	# 预先生成玩家周围的完整区域（确保是正方形而不是L形）
	var area_size = _spawn_area_radius * 2 + 1
	var area_center_offset = _spawn_area_radius
	
	print("Generating spawn area centered at chunk (%d, %d)" % [player_chunk_x, player_chunk_z])
	
	# 先创建所有需要的区块
	var spawn_chunks = []
	for cx in range(player_chunk_x - _spawn_area_radius, player_chunk_x + _spawn_area_radius + 1):
		for cz in range(player_chunk_z - _spawn_area_radius, player_chunk_z + _spawn_area_radius + 1):
			var chunk_pos = Vector2i(cx, cz)
			if not _chunks.has(chunk_pos):
				# 创建新区块
				var chunk = Chunk.new(chunk_pos)
				chunk.position = Vector3(chunk_pos.x * Constants.CHUNK_WORLD_SIZE, 0, chunk_pos.y * Constants.CHUNK_WORLD_SIZE)
				add_child(chunk)
				_chunks[chunk_pos] = chunk
				spawn_chunks.append(chunk)
			else:
				spawn_chunks.append(_chunks[chunk_pos])
	
	# 更新所有新创建区块的邻居引用
	for cx in range(player_chunk_x - _spawn_area_radius, player_chunk_x + _spawn_area_radius + 1):
		for cz in range(player_chunk_z - _spawn_area_radius, player_chunk_z + _spawn_area_radius + 1):
			var chunk_pos = Vector2i(cx, cz)
			if _chunks.has(chunk_pos):
				_update_chunk_neighbors(chunk_pos)
	
	# 生成所有区块的地形（按阶段进行）
	# 阶段1：基础地形
	for chunk in spawn_chunks:
		if is_instance_valid(chunk) and is_instance_valid(_world_generator):
			_world_generator.generate_chunk_stage(chunk, ChunkGenerationStage.BASE_TERRAIN)
			chunk.generation_stage = ChunkGenerationStage.BASE_TERRAIN
	
	# 阶段2：水体和表层
	for chunk in spawn_chunks:
		if is_instance_valid(chunk) and is_instance_valid(_world_generator):
			_world_generator.generate_chunk_stage(chunk, ChunkGenerationStage.WATER_AND_SURFACE)
			chunk.generation_stage = ChunkGenerationStage.WATER_AND_SURFACE
	
	# 阶段3：矿石和洞穴
	for chunk in spawn_chunks:
		if is_instance_valid(chunk) and is_instance_valid(_world_generator):
			_world_generator.generate_chunk_stage(chunk, ChunkGenerationStage.ORES_AND_CAVES)
			chunk.generation_stage = ChunkGenerationStage.ORES_AND_CAVES
	
	# 阶段4：装饰物
	for chunk in spawn_chunks:
		if is_instance_valid(chunk) and is_instance_valid(_world_generator):
			_world_generator.generate_chunk_stage(chunk, ChunkGenerationStage.DECORATIONS)
			chunk.generation_stage = ChunkGenerationStage.FULLY_GENERATED
	
	# 为所有区块生成网格
	for chunk in spawn_chunks:
		if is_instance_valid(chunk):
			chunk.generate_mesh()
	
	print("Spawn area generation completed")

# 寻找合适的出生点
func _find_suitable_spawn_position() -> Vector3:
	# 在世界中心附近寻找一个合适的出生点
	var center_x = 0
	var center_z = 0
	var attempts = 0
	var max_attempts = 100
	
	while attempts < max_attempts:
		# 在中心附近随机选择一个点
		var offset_x = randi_range(-100, 100)
		var offset_z = randi_range(-100, 100)
		var world_x = center_x + offset_x
		var world_z = center_z + offset_z
		
		# 计算该点的高度
		var height = _world_generator.get_noise_height(world_x, world_z)
		
		# 确保高度合适（不要太低或太高）
		if height > 60 and height < 120:
			# 检查该位置是否适合出生（需要是陆地）
			var biome = _world_generator._get_biome(world_x, world_z)
			if biome.name != "Ocean":
				return Vector3(world_x * Constants.VOXEL_SIZE, (height + 2) * Constants.VOXEL_SIZE, world_z * Constants.VOXEL_SIZE)
		
		attempts += 1
	
	# 如果找不到合适的随机点，则使用默认点
	var default_height = _world_generator.get_noise_height(0, 0)
	return Vector3(0, (default_height + 2) * Constants.VOXEL_SIZE, 0)

# 立即加载或生成区块（用于出生区域）
func _load_or_generate_chunk_immediate(chunk_pos: Vector2i) -> void:
	# 检查WorldGenerator是否仍然有效
	if not is_instance_valid(_world_generator):
		return
	
	# 创建新区块
	var chunk = Chunk.new(chunk_pos)
	chunk.position = Vector3(chunk_pos.x * Constants.CHUNK_WORLD_SIZE, 0, chunk_pos.y * Constants.CHUNK_WORLD_SIZE)
	add_child(chunk)
	_chunks[chunk_pos] = chunk
	
	# 尝试从磁盘加载
	var ChunkSerializerScript = load("res://Scripts/Persistence/chunk_serializer.gd")
	if not ChunkSerializerScript.load_chunk(chunk, SAVE_DIR_CHUNKS):
		# 如果加载失败则立即生成基础地形
		# 使用完整的区块生成而不是Section生成，确保地形连续性
		_world_generator.generate_chunk_stage(chunk, ChunkGenerationStage.BASE_TERRAIN)
		chunk.generation_stage = ChunkGenerationStage.BASE_TERRAIN
		
		_world_generator.generate_chunk_stage(chunk, ChunkGenerationStage.WATER_AND_SURFACE)
		chunk.generation_stage = ChunkGenerationStage.WATER_AND_SURFACE
		
		_world_generator.generate_chunk_stage(chunk, ChunkGenerationStage.ORES_AND_CAVES)
		chunk.generation_stage = ChunkGenerationStage.ORES_AND_CAVES
		
		_world_generator.generate_chunk_stage(chunk, ChunkGenerationStage.DECORATIONS)
		chunk.generation_stage = ChunkGenerationStage.FULLY_GENERATED
		
		print("Generated new chunk at %d, %d" % [chunk_pos.x, chunk_pos.y])
	else:
		print("Loaded existing chunk at %d, %d" % [chunk_pos.x, chunk_pos.y])
	
	# 更新网格
	chunk.generate_mesh()
	
	# 更新邻居引用
	_update_chunk_neighbors(chunk_pos)

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
	# FPS计算
	_frame_count += 1
	_last_process_time += delta
	if _last_process_time >= 1.0:
		_fps = _frame_count / _last_process_time
		_frame_count = 0
		_last_process_time = 0.0
		# print("FPS: %.2f" % _fps) # 可以取消注释来查看FPS
	
	# 处理分阶段地形生成
	_process_chunk_generation(delta)
	
	# 控制区块加载频率，避免过于频繁
	_last_chunk_update += delta
	if _last_chunk_update >= CHUNK_UPDATE_INTERVAL:
		_last_chunk_update = 0.0
		# 检查是否需要更新区块加载
		if _player:
			_update_chunk_loading()

# 处理分阶段区块生成
func _process_chunk_generation(delta: float) -> void:
	_generation_timer += delta
	
	# 检查WorldGenerator是否仍然有效
	if not is_instance_valid(_world_generator):
		# 如果WorldGenerator已被释放，则清空生成队列
		_generation_queue.clear()
		_section_generation_queue.clear()
		return
	
	if _generation_timer >= GENERATION_INTERVAL:
		_generation_timer = 0.0
		
		var generations_processed = 0
		var start_time = Time.get_ticks_usec()
		
		# 处理Section生成任务（优先处理）
		while not _section_generation_queue.is_empty() and generations_processed < _max_generations_per_frame:
			# 限制每帧处理时间，避免卡顿
			if Time.get_ticks_usec() - start_time > 5000: # 5ms限制
				break
				
			# 从队列中取出一个Section生成任务
			var task = _section_generation_queue.pop_front()
			
			# 检查任务中的区块是否仍然有效
			if is_instance_valid(task.chunk):
				_world_generator.generate_chunk_section(task.chunk, task.section_index, task.stage)
				
				# 更新Section网格
				task.chunk.generate_section_mesh(task.section_index)
				
				generations_processed += 1
		
		# 处理区块生成任务
		while not _generation_queue.is_empty() and generations_processed < _max_generations_per_frame:
			# 限制每帧处理时间，避免卡顿
			if Time.get_ticks_usec() - start_time > 5000: # 5ms限制
				break
				
			# 从队列中取出一个生成任务
			var task = _generation_queue.pop_front()
			
			# 检查任务中的区块是否仍然有效
			if is_instance_valid(task.chunk):
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
				
				generations_processed += 1

# 将区块生成任务加入队列
func _enqueue_chunk_generation(chunk: Chunk, stage: int) -> void:
	# 检查WorldGenerator是否仍然有效
	if not is_instance_valid(_world_generator):
		return
		
	_generation_queue.append({
		"chunk": chunk,
		"stage": stage
	})

# 将Section生成任务加入队列
func _enqueue_section_generation(chunk: Chunk, section_index: int, stage: int) -> void:
	# 检查WorldGenerator是否仍然有效
	if not is_instance_valid(_world_generator):
		return
		
	_section_generation_queue.append({
		"chunk": chunk,
		"section_index": section_index,
		"stage": stage
	})

# 根据玩家位置更新区块加载
func _update_chunk_loading() -> void:
	if not _player or not is_instance_valid(_world_generator):
		return
		
	var player_pos = _player.global_position
	var player_chunk_x = floor(player_pos.x / Constants.CHUNK_WORLD_SIZE)
	var player_chunk_z = floor(player_pos.z / Constants.CHUNK_WORLD_SIZE)
	
	var chunks_to_load = []
	var chunks_to_unload = []
	
	# 确定需要加载的区块范围（使用曼哈顿距离更准确）
	for cx in range(player_chunk_x - _view_distance, player_chunk_x + _view_distance + 1):
		for cz in range(player_chunk_z - _view_distance, player_chunk_z + _view_distance + 1):
			var chunk_pos = Vector2i(cx, cz)
			# 计算与玩家的距离（使用曼哈顿距离）
			var distance = max(abs(cx - player_chunk_x), abs(cz - player_chunk_z))
			if distance <= _view_distance:
				chunks_to_load.append({"pos": chunk_pos, "distance": distance})
	
	# 确定需要卸载的区块（在_keep_distance之外的区块）
	for chunk_pos in _chunks.keys():
		var distance = max(abs(chunk_pos.x - player_chunk_x), abs(chunk_pos.y - player_chunk_z))
		if distance > _keep_distance:
			chunks_to_unload.append(chunk_pos)
	
	# 卸载超出范围的区块
	for chunk_pos in chunks_to_unload:
		_unload_chunk(chunk_pos)
	
	# 按距离排序需要加载的区块，优先加载近的
	chunks_to_load.sort_custom(func(a, b):
		return a["distance"] < b["distance"]
	)
	
	# 限制每帧加载的区块数量，避免卡顿
	const MAX_CHUNKS_PER_FRAME = 1
	var loaded_this_frame = 0
	
	for item in chunks_to_load:
		if loaded_this_frame >= MAX_CHUNKS_PER_FRAME:
			break
			
		var chunk_pos = item["pos"]
		if not _chunks.has(chunk_pos):
			_load_or_generate_chunk(chunk_pos)
			loaded_this_frame += 1

# 更新区块邻居引用
func _update_chunk_neighbors(chunk_pos: Vector2i) -> void:
	var chunk = _chunks.get(chunk_pos)
	if not chunk:
		return
		
	chunk.neighbor_left = _chunks.get(Vector2i(chunk_pos.x - 1, chunk_pos.y))
	chunk.neighbor_right = _chunks.get(Vector2i(chunk_pos.x + 1, chunk_pos.y))
	chunk.neighbor_front = _chunks.get(Vector2i(chunk_pos.x, chunk_pos.y - 1))
	chunk.neighbor_back = _chunks.get(Vector2i(chunk_pos.x, chunk_pos.y + 1))

# 卸载区块
func _unload_chunk(chunk_pos: Vector2i) -> void:
	if _chunks.has(chunk_pos):
		var chunk = _chunks[chunk_pos]
		# 保存区块到磁盘
		var ChunkSerializerScript = load("res://Scripts/Persistence/chunk_serializer.gd")
		ChunkSerializerScript.save_chunk(chunk, SAVE_DIR_CHUNKS)
		
		# 断开邻居引用以防止循环引用
		chunk.neighbor_left = null
		chunk.neighbor_right = null
		chunk.neighbor_front = null
		chunk.neighbor_back = null
		
		# 从场景树中移除并释放
		chunk.queue_free()
		_chunks.erase(chunk_pos)
		print("Unloaded chunk at %d, %d" % [chunk_pos.x, chunk_pos.y])

# 加载或生成新区块
func _load_or_generate_chunk(chunk_pos: Vector2i) -> void:
	# 检查WorldGenerator是否仍然有效
	if not is_instance_valid(_world_generator):
		return
	
	# 创建新区块
	var chunk = Chunk.new(chunk_pos)
	chunk.position = Vector3(chunk_pos.x * Constants.CHUNK_WORLD_SIZE, 0, chunk_pos.y * Constants.CHUNK_WORLD_SIZE)
	add_child(chunk)
	_chunks[chunk_pos] = chunk
	
	# 尝试从磁盘加载
	var ChunkSerializerScript = load("res://Scripts/Persistence/chunk_serializer.gd")
	if not ChunkSerializerScript.load_chunk(chunk, SAVE_DIR_CHUNKS):
		# 如果加载失败则开始生成
		_enqueue_chunk_generation(chunk, ChunkGenerationStage.BASE_TERRAIN)
		print("Started generating new chunk at %d, %d" % [chunk_pos.x, chunk_pos.y])
	else:
		print("Loaded existing chunk at %d, %d" % [chunk_pos.x, chunk_pos.y])
		# 如果已完全生成，则更新网格
		if chunk.generation_stage >= ChunkGenerationStage.FULLY_GENERATED:
			chunk.generate_mesh()
	
	# 更新邻居引用
	_update_chunk_neighbors(chunk_pos)

# 设置玩家节点引用
func set_player(player: Node3D) -> void:
	_player = player

# 修改 _generate_world 方法以使用分阶段生成
func _generate_world() -> void:
	if _is_generating: return
	_is_generating = true
	print("Starting world generation...")
	
	var start_time = Time.get_ticks_msec()
	
	# 1. Create Chunks
	for cx in range(Constants.CHUNK_WORLD_SIZE):
		for cz in range(Constants.CHUNK_WORLD_SIZE):
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

# 移动玩家到合适的出生点
func _spawn_player() -> void:
	if not _player:
		return
	
	# 玩家位置已经在 _generate_spawn_area 中设置
	print("Player spawned at: %s" % _player.global_position)

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

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# 场景即将被删除时，清理所有引用
		_world_generator = null
		_fluid_manager = null
		_player = null
		
		# 清空生成队列
		_generation_queue.clear()
		_section_generation_queue.clear()
		
		# 清理所有区块引用
		for chunk in _chunks.values():
			if chunk:
				chunk.neighbor_left = null
				chunk.neighbor_right = null
				chunk.neighbor_front = null
				chunk.neighbor_back = null
		_chunks.clear()
