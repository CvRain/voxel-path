extends Node3D

# 引入区块生成阶段枚举
const ChunkGenerationStage = preload("res://Scripts/Voxel/chunk_generation_stage.gd").ChunkGenerationStage
const PlayerControllerScript = preload("res://Scenes/PlayerController/ProtoController.gd")
const PlayerMoveState = PlayerControllerScript.MoveState

var _world_generator: Node
var _fluid_manager: Node
var _chunks: Dictionary = {} # Ve ctor2i -> Chunk
var _is_generating: bool = false
@export var DEBUG_GEN: bool = true

# 添加生成队列和相关变量
var _generation_queue: Array = [] # 存储待生成的区块和阶段
var _section_generation_queue: Array = [] # 存储待生成的Section任务
var _chunk_stage_pending: Dictionary = {} # chunk -> {"stage": int, "pending": int}
var _generation_timer: float = 0.0
const GENERATION_INTERVAL: float = 0.1 # 增加间隔到0.1秒，减轻CPU压力
var _max_generations_per_frame: int = 2 # 每帧最多处理的生成任务数（初始值设为2以提升响应）

@export var view_distance: int = 10
@export var simulation_distance: int = 6
var _keep_distance: int = 32
var _pred_load_lookahead: int = 3 # how many chunks ahead of movement to pre-load

# 控制全局待处理 section 数量的阈值，超过时延迟展开 chunk->section 入队
const MAX_PENDING_SECTION_QUEUE: int = 800
var _deferred_chunk_enqueues: Array = [] # 存储被延迟展开的 chunk 入队任务
# 添加性能监控变量
var _last_process_time: float = 0.0
var _frame_count: int = 0
var _fps: float = 0.0
var _last_chunk_update: float = 0.0
const CHUNK_UPDATE_INTERVAL: float = 0.5 # 每0.5秒更新一次区块加载

var _player: CharacterBody3D
var _deferred_generation_chunks: Dictionary = {} # Vector2i -> true 表示已创建但延迟生成
# When player comes within `simulation_distance`, deferred chunks start generating
@export var initial_spawn_dim: int = 3 # number of chunks per side to immediately generate at spawn (3 => 3x3=9, 4 => 4x4=16)

var _emerge_manager = null
@export var max_mesh_updates_per_frame: int = 1
var _mesh_update_queue: Array = []

func _enqueue_mesh_update(chunk: Chunk) -> void:
	# Avoid duplicates
	for c in _mesh_update_queue:
		if c == chunk:
			return
	_mesh_update_queue.append(chunk)

func _process_mesh_updates(_delta: float) -> void:
	if _mesh_update_queue.size() == 0:
		return
	var processed = 0
	var pcx = null
	var pcz = null
	if is_instance_valid(_player):
		pcx = floor(_player.global_position.x / Constants.CHUNK_WORLD_SIZE)
		pcz = floor(_player.global_position.z / Constants.CHUNK_WORLD_SIZE)

	while processed < max_mesh_updates_per_frame and _mesh_update_queue.size() > 0:
		var best_idx = 0
		if pcx != null:
			var best_d = 999999
			for i in range(_mesh_update_queue.size()):
				var ch = _mesh_update_queue[i]
				if not is_instance_valid(ch):
					continue
				var cp = ch.chunk_position
				var d = max(abs(cp.x - pcx), abs(cp.y - pcz))
				if d < best_d:
					best_d = d
					best_idx = i
		var c = _mesh_update_queue[best_idx]
		_mesh_update_queue.remove_at(best_idx)
		if is_instance_valid(c):
			c.generate_mesh()
		processed += 1

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
	
	# 计算玩家所在的区块
	var player_chunk_x = floor(spawn_position.x / Constants.CHUNK_WORLD_SIZE)
	var player_chunk_z = floor(spawn_position.z / Constants.CHUNK_WORLD_SIZE)
	
	# 使用 exported `initial_spawn_dim` 构建一个 exact dim x dim 的启动方块
	var dim = max(1, initial_spawn_dim)
	var half = int(floor(dim / 2))
	# 当 dim 为偶数时，使起始坐标向负方向偏移一个单位以保证对称性
	var start_x = player_chunk_x - half
	var start_z = player_chunk_z - half
	var spawn_chunks = []
	for cx in range(start_x, start_x + dim):
		for cz in range(start_z, start_z + dim):
			var chunk_pos = Vector2i(cx, cz)
			if not _chunks.has(chunk_pos):
				var chunk = Chunk.new(chunk_pos)
				chunk.position = Vector3(chunk_pos.x * Constants.CHUNK_WORLD_SIZE, 0, chunk_pos.y * Constants.CHUNK_WORLD_SIZE)
				add_child(chunk)
				_chunks[chunk_pos] = chunk
				spawn_chunks.append(chunk)
			else:
				spawn_chunks.append(_chunks[chunk_pos])
	
	# 更新所有新创建区块的邻居引用
	for cx in range(start_x, start_x + dim):
		for cz in range(start_z, start_z + dim):
			var chunk_pos = Vector2i(cx, cz)
			if _chunks.has(chunk_pos):
				_update_chunk_neighbors(chunk_pos)
	
	# 生成所有区块的地形（按阶段进行）
	# 将所有区块的基础生成任务加入队列，交由分帧处理执行，避免一次性阻塞主线程
	# 按玩家距离对 spawn_chunks 排序，优先生成近处区块
	var center_chunk = Vector2i(player_chunk_x, player_chunk_z)
	var spawn_list = []
	for c in spawn_chunks:
		var cp = c.chunk_position
		var dist = max(abs(cp.x - center_chunk.x), abs(cp.y - center_chunk.y))
		spawn_list.append({"chunk": c, "distance": dist})

	spawn_list.sort_custom(func(a, b):
		return a["distance"] < b["distance"]
	)

	for item in spawn_list:
		var chunk = item["chunk"]
		var dist = item["distance"]
		if is_instance_valid(chunk) and is_instance_valid(_world_generator):
			# 仅把 initial_spawn_dim^2 区块加入立即生成，其它标记为延迟生成
			# spawn_list 已按距离排序，前面的就是中心附近的区块
			# 检查 chunk 是否在我们创建的 spawn_chunks 区域（spawn_chunks 包含 exact dim^2）
			var in_initial = false
			for sc in spawn_chunks:
				if sc.chunk_position == chunk.chunk_position:
					in_initial = true
					break
			if in_initial:
				_enqueue_chunk_generation(chunk, ChunkGenerationStage.BASE_TERRAIN)
				if DEBUG_GEN:
					print("[GEN] Spawn enqueue -> %s dist=%d" % [chunk.name, dist])
			else:
				_deferred_generation_chunks[chunk.chunk_position] = true
				if DEBUG_GEN:
					print("[GEN] Spawn deferred -> %s dist=%d" % [chunk.name, dist])

	# 可选：等待最近邻的一些基础阶段完成以避免玩家瞬移到完全空白的地面
	# 这里采用非阻塞的方式轮询，最多等待若干帧（例如 120 帧 ~ 2 秒），以平滑体验
	var wait_frames = 0
	var max_wait_frames = 120
	while wait_frames < max_wait_frames:
		var all_ready = true
		for chunk in spawn_chunks:
			if is_instance_valid(chunk):
				# 如果任一区块尚未进入第二阶段（WATER_AND_SURFACE），继续等待
				if chunk.generation_stage < ChunkGenerationStage.WATER_AND_SURFACE:
					all_ready = false
					break
		if all_ready:
			break
		wait_frames += 1
		await get_tree().process_frame

	# 触发可见区块的网格生成（若区块已完成生成阶段，网格会在队列处理后自动生成）
	for chunk in spawn_chunks:
		if is_instance_valid(chunk) and chunk.generation_stage >= ChunkGenerationStage.FULLY_GENERATED:
			_enqueue_mesh_update(chunk)
	
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
		# 如果加载失败则将生成任务加入队列（分帧处理），避免阻塞主线程
		_enqueue_chunk_generation(chunk, ChunkGenerationStage.BASE_TERRAIN)
		print("Started generating new chunk at %d, %d (enqueued)" % [chunk_pos.x, chunk_pos.y])
	else:
		print("Loaded existing chunk at %d, %d" % [chunk_pos.x, chunk_pos.y])
		# 如果已完全生成，则更新网格
		if chunk.generation_stage >= ChunkGenerationStage.FULLY_GENERATED:
				_enqueue_mesh_update(chunk)
	
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

		# Initialize Emerger (queue manager prototype)
		var EmergerScript = load("res://Scripts/Voxel/emerge_manager.gd")
		_emerge_manager = EmergerScript.new(self)
		add_child(_emerge_manager)
		
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

	# 处理受限的网格更新队列（每帧限制）
	_process_mesh_updates(delta)
	
	# 控制区块加载频率，避免过于频繁
	_last_chunk_update += delta
	if _last_chunk_update >= CHUNK_UPDATE_INTERVAL:
		_last_chunk_update = 0.0
		# 检查是否需要更新区块加载
		if _player:
			_update_chunk_loading()

# 处理分阶段区块生成
func _process_chunk_generation(delta: float) -> void:
	# If Emerger exists, delegate chunk/section generation processing to it
	if _emerge_manager:
		_emerge_manager.process(delta)
		return
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

		# 每帧按小批量（分段）展开被延迟的 chunk 入队，避免一次性把大量 section 推到队列中
		# 逐块分批展开可以把瞬时内存/列表压力摊平，让工作线程持续消费
		var deferred_expanded = 0
		const MAX_DEFERRED_EXPAND_PER_TICK = 6
		const EXPAND_SECTIONS_PER_DEFERRED = 2
		while _deferred_chunk_enqueues.size() > 0 and deferred_expanded < MAX_DEFERRED_EXPAND_PER_TICK:
			# 优先选择玩家附近的被延迟项以保证视野内优先生成
			var picked_index = -1
			var d = null
			if is_instance_valid(_player):
				var player_chunk = Vector2i(floor(_player.global_position.x / Constants.CHUNK_WORLD_SIZE), floor(_player.global_position.z / Constants.CHUNK_WORLD_SIZE))
				for i in range(_deferred_chunk_enqueues.size()):
					var cand = _deferred_chunk_enqueues[i]
					if is_instance_valid(cand.chunk):
						var cp = cand.chunk.chunk_position
						var dist = max(abs(cp.x - player_chunk.x), abs(cp.y - player_chunk.y))
						if dist <= view_distance + 1:
							picked_index = i
							break
					
			if picked_index >= 0:
				# read then remove (remove_at returns void)
				d = _deferred_chunk_enqueues[picked_index]
				_deferred_chunk_enqueues.remove_at(picked_index)
			else:
				d = _deferred_chunk_enqueues.pop_front()
			# d now contains incremental state: {"chunk": Chunk, "stage": int, "next_section": int, "num_sections": int}
			if not is_instance_valid(d.chunk):
				# skip dead chunks
				deferred_expanded += 1
				continue

			var start_i = d.get("next_section", 0)
			var num_sections = d.num_sections
			var end_i = min(start_i + EXPAND_SECTIONS_PER_DEFERRED, num_sections)

			for i in range(start_i, end_i):
				_section_generation_queue.append({"chunk": d.chunk, "section_index": i, "stage": d.stage})
				if DEBUG_GEN and i % 4 == 0:
					print("[GEN] Enqueued section (deferred)-> chunk=%s stage=%d section=%d queue_len=%d" % [d.chunk.name, d.stage, i, _section_generation_queue.size()])

			# if still have remaining sections, push back with updated next_section
			if end_i < num_sections:
				d.next_section = end_i
				_deferred_chunk_enqueues.append(d)

			deferred_expanded += 1
		
		# 处理Section生成任务（优先处理）
		while not _section_generation_queue.is_empty() and generations_processed < _max_generations_per_frame:
			# 限制每帧处理时间，避免卡顿
			if Time.get_ticks_usec() - start_time > 10000: # 10ms限制（放宽一点，允许更多生产量但仍受限）
				break
				
			# 从队列中取出一个Section生成任务
			var task = _section_generation_queue.pop_front()
		
			# 检查任务中的区块是否仍然有效
			if is_instance_valid(task.chunk):
				# 提交到 WorldGenerator 的后台 section 生成任务（异步）
				_world_generator.generate_chunk_section_async(task.chunk, task.section_index, task.stage)
				if DEBUG_GEN:
					print("[GEN] Submit section task -> chunk=%s stage=%d section=%d" % [task.chunk.name, task.stage, task.section_index])
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
				if DEBUG_GEN:
					print("[GEN] Processing chunk stage -> chunk=%s stage=%d" % [chunk.name, stage])
				
				# 执行对应阶段的生成
				_world_generator.generate_chunk_stage(chunk, stage)
				
				# 更新区块生成阶段
				chunk.generation_stage = stage
				
				# 如果不是最终阶段，则将下一阶段加入队列
				if stage < ChunkGenerationStage.FULLY_GENERATED:
					_enqueue_chunk_generation(chunk, stage + 1)
				else:
					# 完全生成后更新网格（受限队列）
					_enqueue_mesh_update(chunk)
				
				generations_processed += 1

# 将区块生成任务加入队列
func _enqueue_chunk_generation(chunk: Chunk, stage: int) -> void:
	# If an Emerger is present, delegate enqueueing to it
	if _emerge_manager:
		_emerge_manager.enqueue_chunk_generation(chunk, stage)
		return
	# 检查WorldGenerator是否仍然有效
	if not is_instance_valid(_world_generator):
		return
	# 如果相同 chunk 和阶段已被入队，跳过
	var existing = _chunk_stage_pending.get(chunk)
	if existing and existing.stage == stage:
		return

	# 拆分为 section 级任务以减小每帧负载
	var num_sections = int(ceil(Constants.VOXEL_MAX_HEIGHT / float(Constants.CHUNK_SECTION_SIZE)))
	_chunk_stage_pending[chunk] = {"stage": stage, "pending": num_sections}

	if DEBUG_GEN:
		print("[GEN] Enqueue chunk -> %s stage=%d sections=%d" % [chunk.name, stage, num_sections])

	# 如果全局待处理 section 数量已经非常大，延迟展开该 chunk 的 section 入队
	if _section_generation_queue.size() + num_sections > MAX_PENDING_SECTION_QUEUE:
		# 推入延迟队列，稍后由 _process_chunk_generation 分帧展开
		_deferred_chunk_enqueues.append({"chunk": chunk, "stage": stage, "num_sections": num_sections})
		if DEBUG_GEN:
			print("[GEN] Deferred enqueue -> %s stage=%d sections=%d (queue_len=%d)" % [chunk.name, stage, num_sections, _section_generation_queue.size()])
		return

	for i in range(num_sections):
		_enqueue_section_generation(chunk, i, stage)

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
	if DEBUG_GEN and section_index % 4 == 0:
		# Reduce noise by only printing every 4th section
		print("[GEN] Enqueued section -> chunk=%s stage=%d section=%d queue_len=%d" % [chunk.name, stage, section_index, _section_generation_queue.size()])


# Called by Chunk when a section has been applied on the main thread
func _on_chunk_section_complete(chunk: Chunk, stage: int) -> void:
	var info = _chunk_stage_pending.get(chunk)
	if not info:
		return

	info.pending -= 1
	if DEBUG_GEN:
		print("[GEN] Section complete -> chunk=%s stage=%d remaining=%d" % [chunk.name, stage, info.pending])
	if info.pending <= 0:
		# 当前阶段所有 section 完成
		chunk.generation_stage = info.stage
		_chunk_stage_pending.erase(chunk)
		if info.stage < ChunkGenerationStage.FULLY_GENERATED:
			_enqueue_chunk_generation(chunk, info.stage + 1)
		else:
			_enqueue_mesh_update(chunk)

# 根据玩家位置更新区块加载
func _update_chunk_loading() -> void:
	if not _player or not is_instance_valid(_world_generator):
		return
		
	var player_pos = _player.global_position
	var player_chunk_x = floor(player_pos.x / Constants.CHUNK_WORLD_SIZE)
	var player_chunk_z = floor(player_pos.z / Constants.CHUNK_WORLD_SIZE)
	
	var chunks_to_load = []
	var chunks_to_unload = []

	# 使用螺旋顺序围绕玩家枚举需要加载的区块，优先按视觉方向评分
	var spiral = _spiral_positions(Vector2i(player_chunk_x, player_chunk_z), view_distance)
	for idx in range(spiral.size()):
		var cp = spiral[idx]
		# compute Chebyshev distance
		var distance = max(abs(cp.x - player_chunk_x), abs(cp.y - player_chunk_z))
		if distance <= view_distance:
			# Score chunks higher if they're roughly in front of the player view direction
			var score = distance
			if is_instance_valid(_player):
				var forward = _player.head.global_transform.basis.z.normalized() if _player.has_node("Head") else Vector3(0, 0, 1)
				var dir_to_chunk = Vector3((cp.x - player_chunk_x), 0, (cp.y - player_chunk_z)).normalized()
				var dot = - forward.dot(dir_to_chunk) # forward.z points -Z; invert if needed
				# Favor chunks in front (dot close to 1). Increase weight to bias forward path generation.
				score = distance - int(clamp(dot * 4.0, -4.0, 4.0))
			chunks_to_load.append({"pos": cp, "distance": score})
	
	# 确定需要卸载的区块（在_keep_distance之外的区块）
	for chunk_pos in _chunks.keys():
		var distance = max(abs(chunk_pos.x - player_chunk_x), abs(chunk_pos.y - player_chunk_z))
		if distance > _keep_distance:
			chunks_to_unload.append(chunk_pos)
	
	# 卸载超出范围的区块
	for chunk_pos in chunks_to_unload:
		_unload_chunk(chunk_pos)
	
	# 按距离排序需要加载的区块，优先加载近的
	# Predictive preloading: if player moving, add chunks ahead of movement to the load list with high priority
	if is_instance_valid(_player):
		var vel_vec = Vector2(_player.velocity.x, _player.velocity.z)
		if vel_vec.length() > 0.1:
			var dir_x = int(sign(vel_vec.x))
			var dir_z = int(sign(vel_vec.y))
			for look in range(1, _pred_load_lookahead + 1):
				var pred_pos = Vector2i(player_chunk_x + dir_x * look, player_chunk_z + dir_z * look)
				# add a small cross area ahead
				for ox in range(-1, 2):
					for oz in range(-1, 2):
						var ppos = Vector2i(pred_pos.x + ox, pred_pos.y + oz)
						# only add if within view distance and not already present
						var already = false
						for existing in chunks_to_load:
							if existing["pos"] == ppos:
								already = true
								break
						if not already:
							chunks_to_load.append({"pos": ppos, "distance": 0})

	# 按距离排序需要加载的区块，优先加载近的
	chunks_to_load.sort_custom(func(a, b):
		return a["distance"] < b["distance"]
	)
	
	# 限制每帧加载的区块数量，避免卡顿
	const MAX_CHUNKS_PER_FRAME = 1
	var loaded_this_frame = 0

	# 动态调整每帧处理的生成任务数以适应队列长度
	if _section_generation_queue.size() > 200:
		_max_generations_per_frame = clamp(_max_generations_per_frame + 1, 1, 16)
	elif _section_generation_queue.size() < 50:
		_max_generations_per_frame = clamp(_max_generations_per_frame - 1, 1, 8)
	
	for item in chunks_to_load:
		if loaded_this_frame >= MAX_CHUNKS_PER_FRAME:
			break
			
		var chunk_pos = item["pos"]
		var cheb = max(abs(chunk_pos.x - player_chunk_x), abs(chunk_pos.y - player_chunk_z))
		if not _chunks.has(chunk_pos):
			# 创建区块节点：如果该区块在初始 spawn 方块内则立即生成，否则延迟
			_create_chunk_node(chunk_pos, _is_within_initial_spawn(chunk_pos, Vector2i(player_chunk_x, player_chunk_z)))
			loaded_this_frame += 1
		else:
			# 如果区块已存在但之前被标记为延迟，且玩家足够接近，则触发生成
			if _deferred_generation_chunks.has(chunk_pos) and cheb <= simulation_distance:
				var c = _chunks[chunk_pos]
				if is_instance_valid(c) and is_instance_valid(_world_generator) and (not _chunk_stage_pending.has(c)):
					_enqueue_chunk_generation(c, ChunkGenerationStage.BASE_TERRAIN)
					_deferred_generation_chunks.erase(chunk_pos)
					if DEBUG_GEN:
						print("[GEN] Triggered deferred generation -> %s dist=%d" % [c.name, cheb])

# 更新区块邻居引用
func _update_chunk_neighbors(chunk_pos: Vector2i) -> void:
	var chunk = _chunks.get(chunk_pos)
	if not chunk:
		return
		
	chunk.neighbor_left = _chunks.get(Vector2i(chunk_pos.x - 1, chunk_pos.y))
	chunk.neighbor_right = _chunks.get(Vector2i(chunk_pos.x + 1, chunk_pos.y))
	chunk.neighbor_front = _chunks.get(Vector2i(chunk_pos.x, chunk_pos.y - 1))
	chunk.neighbor_back = _chunks.get(Vector2i(chunk_pos.x, chunk_pos.y + 1))

# 返回以 center 为中心、半径为 radius 的螺旋顺序 Vector2i 列表
func _spiral_positions(center: Vector2i, radius: int) -> Array:
	var res: Array = []
	res.append(center)
	var x = center.x
	var y = center.y
	var step = 1
	while step <= radius:
		# move right step times
		for i in range(step):
			x += 1
			res.append(Vector2i(x, y))
		# move down step times
		for i in range(step):
			y += 1
			res.append(Vector2i(x, y))
		step += 1
		# move left step times
		for i in range(step):
			x -= 1
			res.append(Vector2i(x, y))
		# move up step times
		for i in range(step):
			y -= 1
			res.append(Vector2i(x, y))
		step += 1
		# stop if we've grown beyond radius in all directions
		if abs(x - center.x) > radius and abs(y - center.y) > radius:
			break

	# filter to radius (Chebyshev) and ensure uniqueness
	var filtered: Array = []
	var seen = {}
	for p in res:
		if max(abs(p.x - center.x), abs(p.y - center.y)) <= radius:
			var key = "%d,%d" % [p.x, p.y]
			if not seen.has(key):
				filtered.append(p)
				seen[key] = true
	return filtered


func _is_within_initial_spawn(chunk_pos: Vector2i, center_chunk: Vector2i) -> bool:
	var dim = max(1, initial_spawn_dim)
	var half = int(floor(dim / 2))
	var start_x = center_chunk.x - half
	var start_z = center_chunk.y - half
	if chunk_pos.x >= start_x and chunk_pos.x < start_x + dim and chunk_pos.y >= start_z and chunk_pos.y < start_z + dim:
		return true
	return false

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
			_enqueue_mesh_update(chunk)
	
	# 更新邻居引用
	_update_chunk_neighbors(chunk_pos)


# Helper: create chunk node and optionally enqueue generation immediately
func _create_chunk_node(chunk_pos: Vector2i, enqueue_immediately: bool) -> void:
	if _chunks.has(chunk_pos):
		return
	# 创建新区块节点
	var chunk = Chunk.new(chunk_pos)
	chunk.position = Vector3(chunk_pos.x * Constants.CHUNK_WORLD_SIZE, 0, chunk_pos.y * Constants.CHUNK_WORLD_SIZE)
	add_child(chunk)
	_chunks[chunk_pos] = chunk

	# 尝试从磁盘加载
	var ChunkSerializerScript = load("res://Scripts/Persistence/chunk_serializer.gd")
	if ChunkSerializerScript.load_chunk(chunk, SAVE_DIR_CHUNKS):
		if DEBUG_GEN:
			print("Loaded chunk %d,%d from disk" % [chunk_pos.x, chunk_pos.y])
			if chunk.generation_stage >= ChunkGenerationStage.FULLY_GENERATED:
				_enqueue_mesh_update(chunk)
	else:
		if enqueue_immediately:
			_enqueue_chunk_generation(chunk, ChunkGenerationStage.BASE_TERRAIN)
			if DEBUG_GEN:
				print("[GEN] Immediately enqueued created chunk -> %d,%d" % [chunk_pos.x, chunk_pos.y])
		else:
			_deferred_generation_chunks[chunk_pos] = true
			if DEBUG_GEN:
				print("[GEN] Created chunk deferred -> %d,%d" % [chunk_pos.x, chunk_pos.y])

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
	# 只在玩家视野半径内创建区块，按螺旋顺序优先创造靠近玩家的区块，避免一次性创建大量区块
	var center_chunk = Vector2i(0, 0)
	if _player:
		var pcx = floor(_player.global_position.x / Constants.CHUNK_WORLD_SIZE)
		var pcz = floor(_player.global_position.z / Constants.CHUNK_WORLD_SIZE)
		center_chunk = Vector2i(pcx, pcz)

	var positions: Array = _spiral_positions(center_chunk, view_distance)

	for pos in positions:
		var cx = pos.x
		var cz = pos.y
		var dist = max(abs(cx - center_chunk.x), abs(cz - center_chunk.y))
		if dist > view_distance:
			continue
		if DEBUG_GEN:
			print("Creating chunk %d,%d (dist=%d)" % [cx, cz, dist])
		var chunk_pos = Vector2i(cx, cz)
		if _chunks.has(chunk_pos):
			continue
		var chunk = Chunk.new(chunk_pos)
		# Position in world space
		chunk.position = Vector3(cx * Constants.CHUNK_WORLD_SIZE, 0, cz * Constants.CHUNK_WORLD_SIZE)
		add_child(chunk)
		_chunks[chunk_pos] = chunk

		# Try to load first, if not found, either enqueue or defer generation
		var ChunkSerializerScript = load("res://Scripts/Persistence/chunk_serializer.gd")
		if not ChunkSerializerScript.load_chunk(chunk, SAVE_DIR_CHUNKS):
			# 将初始生成阶段加入队列或延迟（以避免瞬时爆发）
			if _is_within_initial_spawn(chunk_pos, center_chunk):
				_enqueue_chunk_generation(chunk, ChunkGenerationStage.BASE_TERRAIN)
				if DEBUG_GEN:
					print("[GEN] Enqueue generated chunk -> %d,%d (dist=%d)" % [cx, cz, dist])
			else:
				_deferred_generation_chunks[chunk_pos] = true
				if DEBUG_GEN:
					print("[GEN] Deferred generation for chunk -> %d,%d (dist=%d)" % [cx, cz, dist])
		else:
			if DEBUG_GEN:
				print("Loaded chunk %d,%d from disk" % [cx, cz])
			# 已加载的区块直接生成网格
			_enqueue_mesh_update(chunk)
	
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
						_enqueue_mesh_update(chunk)
				
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
						_enqueue_mesh_update(_chunks[key])

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
