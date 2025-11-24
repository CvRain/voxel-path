class_name BlockBehavior
extends Node

# 单例引用
static var _instance: BlockBehavior

# 更新队列：存储需要检查的方块的世界坐标
var _update_queue: Array[Vector3i] = []
# 防止重复添加：快速查找集合
var _pending_updates: Dictionary = {}

# 每帧最大处理的更新数量（防止卡顿的核心！）
const MAX_UPDATES_PER_FRAME: int = 200

# 常用方块 ID (缓存)
var _sand_id: int = -1
var _air_id: int = 0

func _enter_tree() -> void:
	if _instance != null:
		queue_free()
		return
	_instance = self
	_air_id = Constants.AIR_BLOCK_ID

func _ready() -> void:
	# 尝试获取沙子的 ID，如果没有则默认为 -1
	var sand_block = BlockRegistry.get_block_by_name("sand")
	if sand_block:
		_sand_id = sand_block.id
	else:
		# 如果还没加载完，稍后重试或在逻辑中动态获取
		pass

func _process(_delta: float) -> void:
	process_update_queue()

# --- 公共 API ---

static func get_instance() -> BlockBehavior:
	return _instance

# 请求更新一个方块及其邻居
func schedule_update_and_neighbors(pos: Vector3i) -> void:
	schedule_update(pos)
	schedule_update(pos + Vector3i.UP)
	schedule_update(pos + Vector3i.DOWN)
	schedule_update(pos + Vector3i.LEFT)
	schedule_update(pos + Vector3i.RIGHT)
	schedule_update(pos + Vector3i.FORWARD)
	schedule_update(pos + Vector3i.BACK)

# 请求更新单个方块
func schedule_update(pos: Vector3i) -> void:
	if pos in _pending_updates:
		return
	
	_update_queue.append(pos)
	_pending_updates[pos] = true

# --- 核心逻辑 ---

func process_update_queue() -> void:
	if _update_queue.is_empty():
		return
	
	var processed_count = 0
	var world = get_tree().current_scene
	
	# 动态获取 ID (如果 _ready 时未加载)
	if _sand_id == -1:
		var sand = BlockRegistry.get_block_by_name("sand")
		if sand: _sand_id = sand.id
	
	# 每帧只处理有限数量的更新
	while processed_count < MAX_UPDATES_PER_FRAME and not _update_queue.is_empty():
		var pos = _update_queue.pop_front()
		_pending_updates.erase(pos)
		
		_process_single_block(world, pos)
		processed_count += 1

func _process_single_block(world: Node, pos: Vector3i) -> void:
	if not world.has_method("get_voxel_at"):
		return
		
	var block_id = world.get_voxel_at(pos)
	
	if block_id == _air_id:
		return
		
	# --- 沙子重力逻辑 ---
	if block_id == _sand_id: # 假设沙子 ID
		_handle_gravity(world, pos, block_id)

func _handle_gravity(world: Node, pos: Vector3i, block_id: int) -> void:
	var below_pos = pos + Vector3i.DOWN
	var below_id = world.get_voxel_at(below_pos)
	
	# 如果下方是空气，则掉落
	if below_id == _air_id:
		# 1. 移动数据
		world.set_voxel_at_raw(pos, _air_id)
		world.set_voxel_at_raw(below_pos, block_id)
		
		# 2. 触发网格更新 (使用我们优化过的批量更新接口)
		# 这里为了简单，我们手动构造更新请求，或者让 World 提供一个 helper
		# 为了演示，我们假设 World 有一个高效的单点更新或小批量更新
		# 在实际项目中，最好把这些变更收集起来，在帧末尾统一提交给 World
		
		# 临时：直接调用 World 的更新 (注意：这可能会导致每帧多次小更新，但因为有 MAX_UPDATES_PER_FRAME 限制，是安全的)
		_notify_world_update(world, pos)
		_notify_world_update(world, below_pos)
		
		# 3. 连锁反应：
		# - 原位置上方可能还有沙子，需要更新原位置上方
		schedule_update(pos + Vector3i.UP)
		# - 新位置继续尝试下落
		schedule_update(below_pos)
		# - 新位置的邻居可能受影响
		schedule_update_and_neighbors(below_pos)

func _notify_world_update(world: Node, pos: Vector3i) -> void:
	# 这是一个简化的更新触发，理想情况下应该复用 ProtoController 中的 _batch_modify_voxels 逻辑
	# 这里我们简单地调用 update_chunks
	var cx = floor(pos.x / float(Constants.CHUNK_SIZE))
	var cz = floor(pos.z / float(Constants.CHUNK_SIZE))
	var chunk_pos = Vector2i(cx, cz)
	
	# 尝试使用优化过的 update_chunks_sections
	if world.has_method("update_chunks_sections"):
		var y = pos.y
		var section_idx = floori(y / float(Constants.CHUNK_SECTION_SIZE))
		var changes = {chunk_pos: [section_idx]}
		
		# 检查边界
		var max_sections = ceil(Constants.VOXEL_MAX_HEIGHT / float(Constants.CHUNK_SECTION_SIZE))
		var local_y = y % Constants.CHUNK_SECTION_SIZE
		if local_y == 0 and section_idx > 0:
			changes[chunk_pos].append(section_idx - 1)
		elif local_y == Constants.CHUNK_SECTION_SIZE - 1 and section_idx < max_sections - 1:
			changes[chunk_pos].append(section_idx + 1)
			
		world.update_chunks_sections(changes)
	elif world.has_method("update_chunks"):
		world.update_chunks([chunk_pos])
