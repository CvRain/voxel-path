extends Node3D
class_name WorldManager

# 引入区块生成阶段枚举
const ChunkGenerationStage = preload("res://Scripts/Voxel/chunk_generation_stage.gd").ChunkGenerationStage

# 区块状态枚举
enum ChunkState {
	EMPTY, # 未生成
	GENERATING, # 正在生成
	GENERATED, # 已生成但未加载
	LOADED, # 已加载到场景
	UNLOADING # 正在卸载
}

# 区块数据结构
class ChunkData:
	var position: Vector2i
	var state: ChunkState = ChunkState.EMPTY
	var chunk: Chunk = null
	var area: Area3D = null
	var last_accessed: float = 0.0
	
	func _init(pos: Vector2i):
		position = pos
		last_accessed = Time.get_ticks_msec()

# 世界管理器配置
@export var render_distance: int = 8 # 渲染距离（区块）
@export var simulation_distance: int = 12 # 模拟距离（区块）
@export var unload_distance: int = 16 # 卸载距离（区块）
@export var max_loaded_chunks: int = 256 # 最大加载区块数

@export var player: CharacterBody3D
@export var world_generator: Node3D

@onready var _fluid_manager: FluidManager = $FluidManager


var _chunks: Dictionary = {} # Vector2i -> ChunkData

# 队列
var _generation_queue: Array = [] # 待生成的区块位置
var max_enqueue_per_frame: int = 8 # 每帧最多排队生成区块数
var max_generation_queue_size: int = 64 # 生成队列最大长度
var max_async_tasks: int = 4 # 最大并发异步生成任务数
var _async_task_count: int = 0 # 当前异步生成任务数
var _load_queue: Array = [] # 待加载的区块
var _unload_queue: Array = [] # 待卸载的区块

# 线程
var _is_generating: bool = false # 是否有区块正在生成

# --- 分帧处理参数 ---
var max_gen_per_frame: int = 2 # 每帧最多生成区块数
var max_load_per_frame: int = 2 # 每帧最多加载区块数
var max_unload_per_frame: int = 2 # 每帧最多卸载区块数

func _ready() -> void:
	set_process_mode(Node.PROCESS_MODE_ALWAYS)
	set_process(true)
	print("[WorldManager] Ready")

	_initialize_world()
	_generate_initial_chunks()
func _generate_initial_chunks() -> void:
	# 检查stone方块是否注册成功
	var stone_block = BlockRegistry.get_block_by_name("stone")
	if stone_block:
		print("[WorldManager] Stone block registered, id:", stone_block.id)
	else:
		print("[WorldManager] Stone block NOT FOUND!")
	# 仅生成4x4区块，中心为(0,0)
	var radius = 2
	for x in range(-radius, radius):
		for y in range(-radius, radius):
			var pos = Vector2i(x, y)
			if not _chunks.has(pos):
				print("[WorldManager] Initial enqueuing generation for chunk:", pos)
				_enqueue_generation(pos)

func _initialize_world() -> void:
	# Initialize World Generator
	#var WorldGeneratorScript = load("res://Scripts/Voxel/world_generator.gd")
	#_world_generator = WorldGeneratorScript.new(randi())
	#add_child(_world_generator)
	# Initialize Fluid Manager
	#var FluidManagerScript = load("res://Scripts/Voxel/fluid_manager.gd")
	#_fluid_manager = FluidManagerScript.new(self)
	pass
	
func _enqueue_load(pos: Vector2i) -> void:
	if not _load_queue.has(pos):
		_load_queue.append(pos)
func _process(_delta: float) -> void:
	if not world_generator or not player:
		return
	print("DEBUG: Player pos: %s, Chunk pos: %s" % [player.global_position, _world_to_chunk_pos(player.global_position)])
	_update_chunks_around_player()
	_process_queues()
	# 主线程轮询WorldGenerator.pending_results，应用区块生成结果
	world_generator.process_pending_results()

func _update_chunks_around_player() -> void:
	var player_chunk_pos = _world_to_chunk_pos(player.global_position)
	var chunks_to_load = _get_chunks_in_range(player_chunk_pos, render_distance)
	print("DEBUG: Player chunk pos: %s, chunks to load: %d" % [player_chunk_pos, chunks_to_load.size()])

	var chunks_to_unload = []
	for pos in _chunks.keys():
		if pos.distance_to(player_chunk_pos) > unload_distance:
			chunks_to_unload.append(pos)

	# 每帧补充新区块到生成队列（只要队列未满且区块未生成）
	var enqueued_this_frame = 0
	for pos in chunks_to_load:
		if not _chunks.has(pos) and not _generation_queue.has(pos) and enqueued_this_frame < max_enqueue_per_frame and _generation_queue.size() < max_generation_queue_size:
			print("DEBUG: Enqueuing generation for chunk: %s" % pos)
			_enqueue_generation(pos)
			enqueued_this_frame += 1
		elif _chunks.has(pos) and _chunks[pos].state == ChunkState.GENERATED:
			_enqueue_load(pos)
	print("[WorldManager] Generation queue size:", _generation_queue.size(), "Enqueued this frame:", enqueued_this_frame)

	for pos in chunks_to_unload:
		_enqueue_unload(pos)

func _enqueue_generation(pos: Vector2i) -> void:
	if _generation_queue.size() >= max_generation_queue_size:
		print("[WorldManager] Generation queue full, drop chunk:", pos)
		return
	if not _generation_queue.has(pos):
		_generation_queue.append(pos)
		print("[WorldManager] Enqueued generation for chunk:", pos)


func _enqueue_unload(pos: Vector2i) -> void:
	if not _unload_queue.has(pos):
		_unload_queue.append(pos)

# --- 优先级队列排序（按距离玩家远近，兼容Godot 4） ---
func _sort_queue_by_distance(queue: Array, center: Vector2i) -> Array:
	var sorted = queue.duplicate()
	sorted.sort_custom(func(a, b):
		return a.distance_to(center) < b.distance_to(center)
	)
	return sorted

# --- 反转数组（兼容Godot 4） ---
func _reverse_array(arr: Array) -> Array:
	var rev = arr.duplicate()
	rev.reverse()
	return rev

# --- 优化后的 _process_queues ---
func _process_queues() -> void:
	var player_chunk_pos = _world_to_chunk_pos(player.global_position)
	# 处理生成队列（优先最近区块，分帧）
	if not _generation_queue.is_empty() and _async_task_count < max_async_tasks:
		var sorted_gen = _sort_queue_by_distance(_generation_queue, player_chunk_pos)
		print("[WorldManager] Generation queue:", sorted_gen)
		var tasks_to_start = min(max_gen_per_frame, max_async_tasks - _async_task_count, sorted_gen.size())
		for i in range(tasks_to_start):
			var pos = sorted_gen[i]
			_generation_queue.erase(pos)
			_async_task_count += 1
			print("[WorldManager] Start async generation for chunk:", pos)
			world_generator.generate_chunk_stage_async(pos, ChunkGenerationStage.BASE_TERRAIN)
			
	# 处理加载队列（优先最近区块，分帧）
	if not _load_queue.is_empty():
		var sorted_load = _sort_queue_by_distance(_load_queue, player_chunk_pos)
		for i in range(min(max_load_per_frame, sorted_load.size())):
			if _chunks.size() < max_loaded_chunks:
				var pos = sorted_load[i]
				_load_queue.erase(pos)
				_load_chunk(pos)
			else:
				# 超限时优先卸载最远区块
				var farthest_pos = null
				var max_dist = -1
				for cpos in _chunks.keys():
					var dist = cpos.distance_to(player_chunk_pos)
					if dist > max_dist:
						max_dist = dist
						farthest_pos = cpos
				if farthest_pos:
					_unload_chunk(farthest_pos)
	# 处理卸载队列（优先最远区块，分帧）
	if not _unload_queue.is_empty():
		var sorted_unload = _reverse_array(_sort_queue_by_distance(_unload_queue, player_chunk_pos))
		for i in range(min(max_unload_per_frame, sorted_unload.size())):
			var pos = sorted_unload[i]
			_unload_queue.erase(pos)
			_unload_chunk(pos)


# 新增：主线程应用异步生成结果，分配Chunk对象并批量写入体素数据
func apply_chunk_stage_result(chunk_pos: Vector2i, stage: int, result: Dictionary) -> void:
	print("[WorldManager] Generation completed for chunk:", chunk_pos)
	if _async_task_count > 0:
		_async_task_count -= 1
	# 主线程唯一分配Chunk对象
	if not _chunks.has(chunk_pos):
		_chunks[chunk_pos] = ChunkData.new(chunk_pos)
	var chunk = Chunk.new(chunk_pos)
	# 仅支持一维PackedInt32Array高效写入
	if result.has("buffer") and result["buffer"] != null:
		var buffer = result["buffer"]
		var size = Constants.CHUNK_SIZE
		for i in range(buffer.size()):
			var x = i % size
			var y = int(i / (size * size))
			var z = int((i / size) % size)
			chunk.set_voxel_raw(x, y, z, buffer[i])
	_chunks[chunk_pos].chunk = chunk
	_chunks[chunk_pos].state = ChunkState.GENERATED
	print("[WorldManager] Enqueue load for chunk:", chunk_pos)
	_enqueue_load(chunk_pos)

func _load_chunk(pos: Vector2i) -> void:
	print("[WorldManager] Loading chunk:", pos)
	var chunk_data = _chunks[pos]
	if chunk_data.state != ChunkState.GENERATED:
		print("[WorldManager] Chunk not in GENERATED state, skip load:", pos)
		return

	var chunk = chunk_data.chunk
	# 统一区块坐标与世界坐标映射
	chunk.position = Vector3(pos.x * Constants.CHUNK_SIZE * Constants.VOXEL_SIZE, 0, pos.y * Constants.CHUNK_SIZE * Constants.VOXEL_SIZE)
	add_child(chunk)

	# 生成区块网格（确保BlockRegistry已初始化）
	if BlockRegistry.get_instance():
		print("[WorldManager] Generating mesh for chunk:", pos)
		chunk.generate_mesh()
	else:
		print("[ERROR] BlockRegistry未初始化，区块内容为空！")

	chunk_data.area = chunk.area
	chunk_data.state = ChunkState.LOADED
	chunk_data.last_accessed = Time.get_ticks_msec()

func _unload_chunk(pos: Vector2i) -> void:
	var chunk_data = _chunks[pos]
	if chunk_data.state != ChunkState.LOADED:
		return

	# 区块卸载前预留持久化接口
	# TODO: 持久化chunk_data.chunk到磁盘

	if chunk_data.chunk:
		chunk_data.chunk.queue_free()
	if chunk_data.area:
		chunk_data.area.queue_free()

	_chunks.erase(pos)

func _on_chunk_entered(body: Node3D, pos: Vector2i) -> void:
	if body == player:
		_chunks[pos].last_accessed = Time.get_ticks_msec()

func _world_to_chunk_pos(world_pos: Vector3) -> Vector2i:
	var x = int(floor(world_pos.x / (Constants.CHUNK_SIZE * Constants.VOXEL_SIZE)))
	var z = int(floor(world_pos.z / (Constants.CHUNK_SIZE * Constants.VOXEL_SIZE)))
	return Vector2i(x, z)

func _get_chunks_in_range(center: Vector2i, radius: int) -> Array:
	var chunks = []
	for x in range(center.x - radius, center.x + radius + 1):
		for y in range(center.y - radius, center.y + radius + 1):
			var pos = Vector2i(x, y)
			if pos.distance_to(center) <= radius:
				chunks.append(pos)
	return chunks

## 公共接口
## 日志模块示例（Logger）
## 已移除临时日志模块Logger，统一使用你自己的logger工具
func get_chunk_at(pos: Vector2i) -> Chunk:
	if _chunks.has(pos) and _chunks[pos].state == ChunkState.LOADED:
		return _chunks[pos].chunk
	return null

func set_voxel_at_world(world_pos: Vector3i, block_id: int) -> void:
	var chunk_pos = _world_to_chunk_pos(world_pos)
	var chunk = get_chunk_at(chunk_pos)
	if chunk:
		var local_pos = _world_to_local_pos(world_pos, chunk_pos)
		chunk.set_voxel(local_pos.x, local_pos.y, local_pos.z, block_id)

func get_voxel_at_world(world_pos: Vector3i) -> int:
	var chunk_pos = _world_to_chunk_pos(world_pos)
	var chunk = get_chunk_at(chunk_pos)
	if chunk:
		var local_pos = _world_to_local_pos(world_pos, chunk_pos)
		return chunk.get_voxel(local_pos.x, local_pos.y, local_pos.z)
	return Constants.AIR_BLOCK_ID

func _world_to_local_pos(world_pos: Vector3i, chunk_pos: Vector2i) -> Vector3i:
	var local_x = world_pos.x - chunk_pos.x * Constants.CHUNK_SIZE
	var local_z = world_pos.z - chunk_pos.y * Constants.CHUNK_SIZE
	var local_y = world_pos.y
	return Vector3i(local_x, local_y, local_z)

# 支持动态调整视距，自动刷新区块加载/卸载
func set_render_distance(new_distance: int) -> void:
	render_distance = new_distance
	if player:
		_update_chunks_around_player()
		_process_queues()
	# 可扩展：保存配置、触发信号等

# --- 资源回收与异常处理建议 ---
# 1. 所有queue_free操作前判断对象是否有效
# 2. 所有异步任务建议try/catch，主线程回调时检测结果有效性
# 3. 可在主线程定期调用WorldGenerator.process_pending_results()
