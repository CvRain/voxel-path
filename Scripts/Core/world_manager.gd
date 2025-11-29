class_name WorldManager
extends Node

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

var _chunks: Dictionary = {} # Vector2i -> ChunkData
var _player: Node3D = null
var _world_generator: WorldGenerator = null
var _fluid_manager: Node = null

# 队列
var _generation_queue: Array = [] # 待生成的区块位置
var _load_queue: Array = [] # 待加载的区块
var _unload_queue: Array = [] # 待卸载的区块

# 线程
var _is_generating: bool = false # 是否有区块正在生成

func _ready() -> void:
	_initialize_world()

func set_player(player: Node3D) -> void:
	_player = player

func _initialize_world() -> void:
	# Initialize World Generator
	var WorldGeneratorScript = load("res://Scripts/Voxel/world_generator.gd")
	_world_generator = WorldGeneratorScript.new(randi())
	add_child(_world_generator)
	
	# Initialize Fluid Manager
	var FluidManagerScript = load("res://Scripts/Voxel/fluid_manager.gd")
	_fluid_manager = FluidManagerScript.new(self)
func _enqueue_load(pos: Vector2i) -> void:
	if not _load_queue.has(pos):
		_load_queue.append(pos)
func _process(_delta: float) -> void:
	if not _world_generator or not _player:
		# _generation_thread = Thread.new() # Removed as it's no longer needed
		return
	print("DEBUG: Player pos: %s, Chunk pos: %s" % [_player.global_position, _world_to_chunk_pos(_player.global_position)])
	_update_chunks_around_player()
	_process_queues()

func _update_chunks_around_player() -> void:
	# 可在此处使用自定义logger
	var player_chunk_pos = _world_to_chunk_pos(_player.global_position)
	
	# 计算需要加载的区块
	var chunks_to_load = _get_chunks_in_range(player_chunk_pos, render_distance)
	print("DEBUG: Player chunk pos: %s, chunks to load: %d" % [player_chunk_pos, chunks_to_load.size()])
	# 可在此处使用自定义logger

	# 计算需要卸载的区块
	var chunks_to_unload = []
	for pos in _chunks.keys():
		if pos.distance_to(player_chunk_pos) > unload_distance:
			chunks_to_unload.append(pos)
	
	# 排队生成和加载
	for pos in chunks_to_load:
		if not _chunks.has(pos):
			print("DEBUG: Enqueuing generation for chunk: %s" % pos)
			_enqueue_generation(pos)
		elif _chunks[pos].state == ChunkState.GENERATED:
			# 可在此处使用自定义logger
			_enqueue_load(pos)
	
	# 排队卸载
	for pos in chunks_to_unload:
		_enqueue_unload(pos)
		# 可在此处使用自定义logger

func _enqueue_generation(pos: Vector2i) -> void:
	if not _generation_queue.has(pos):
		_generation_queue.append(pos)
	## 日志模块示例（WMLogger）


func _enqueue_unload(pos: Vector2i) -> void:
	if not _unload_queue.has(pos):
		_unload_queue.append(pos)

func _process_queues() -> void:
	# 处理生成队列（使用WorkerThreadPool）
	if not _generation_queue.is_empty() and not _is_generating:
		var pos = _generation_queue.pop_front()
		# 可在此处使用自定义logger
		_is_generating = true
		WorkerThreadPool.add_task(_generate_chunk_thread.bind(pos), true, "ChunkGen %s" % pos)

	# 处理加载队列（最大加载区块数限制）
	if not _load_queue.is_empty():
		if _chunks.size() < max_loaded_chunks:
			var pos = _load_queue.pop_front()
			# 可在此处使用自定义logger
			_load_chunk(pos)
		else:
			# 超限时优先卸载最远区块
			var player_chunk_pos = _world_to_chunk_pos(_player.global_position)
			var farthest_pos = null
			var max_dist = -1
			for cpos in _chunks.keys():
				var dist = cpos.distance_to(player_chunk_pos)
				if dist > max_dist:
					max_dist = dist
					farthest_pos = cpos
			if farthest_pos:
				# 可在此处使用自定义logger
				_unload_chunk(farthest_pos)

	# 处理卸载队列
	if not _unload_queue.is_empty():
		var pos = _unload_queue.pop_front()
		# 可在此处使用自定义logger
		_unload_chunk(pos)

func _generate_chunk_thread(pos: Vector2i) -> Chunk:
	# WorkerThreadPool任务，线程安全生成区块
	var chunk = Chunk.new(pos)
	# 分阶段生成
	_world_generator.generate_chunk_stage(chunk, ChunkGenerationStage.BASE_TERRAIN)
	_world_generator.generate_chunk_stage(chunk, ChunkGenerationStage.WATER_AND_SURFACE)
	_world_generator.generate_chunk_stage(chunk, ChunkGenerationStage.ORES_AND_CAVES)
	_world_generator.generate_chunk_stage(chunk, ChunkGenerationStage.DECORATIONS)
	_world_generator.generate_chunk_stage(chunk, ChunkGenerationStage.FULLY_GENERATED)
	# 主线程回调
	call_deferred("_on_generation_completed", pos, chunk)
	return chunk

func _on_generation_completed(pos: Vector2i, chunk: Chunk) -> void:
	_is_generating = false
	_chunks[pos].chunk = chunk
	_chunks[pos].state = ChunkState.GENERATED
	# 自动排队加载
	_enqueue_load(pos)

func _load_chunk(pos: Vector2i) -> void:
	var chunk_data = _chunks[pos]
	if chunk_data.state != ChunkState.GENERATED:
		return

	var chunk = chunk_data.chunk
	# 统一区块坐标与世界坐标映射
	chunk.position = Vector3(pos.x * Constants.CHUNK_SIZE * Constants.VOXEL_SIZE, 0, pos.y * Constants.CHUNK_SIZE * Constants.VOXEL_SIZE)
	add_child(chunk)

	# 生成区块网格
	chunk.generate_mesh()

	# 只保留Chunk类中的碰撞体积，移除WorldManager中的重复碰撞体积创建
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
	if body == _player:
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
	if _player:
		_update_chunks_around_player()
		_process_queues()
	# 可扩展：保存配置、触发信号等
