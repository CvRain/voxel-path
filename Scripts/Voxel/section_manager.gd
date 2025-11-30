# Scripts/Voxel/section_manager.gd
# Section管理器，用于管理基于16x16x16 Section的地形生成

class_name SectionManager
extends Node

const SECTION_WIDTH: int = 16
const SECTION_HEIGHT: int = 16
const SECTION_DEPTH: int = 16

func _init() -> void:
	MyLogger.info("[SectionManager] Initialized")


# Section生成优先级枚举
enum SectionPriority {
	HIGH, # 高优先级（靠近玩家）
	MEDIUM, # 中优先级
	LOW # 低优先级
}

# Section生成任务
class SectionTask:
	var chunk: Chunk
	var section_index: int
	var priority: int
	var world_generator: Node
	
	func _init(c: Chunk, index: int, p: int, generator: Node):
		chunk = c
		section_index = index
		priority = p
		world_generator = generator

# 创建Section生成任务
static func create_section_tasks(chunk: Chunk, player_position: Vector3, world_generator: Node) -> Array:
	MyLogger.info("[SectionManager] Creating section tasks")

	# 检查参数有效性
	if not is_instance_valid(chunk) or not is_instance_valid(world_generator):
		return []
		
	var tasks: Array = []
	var chunk_world_pos = chunk.position
	
	# 计算玩家在区块中的相对位置
	var player_relative_x = player_position.x - chunk_world_pos.x
	var player_relative_z = player_position.z - chunk_world_pos.z
	
	# 计算玩家所在的Section（X/Z/Y均动态）
	var player_section_x = int(player_relative_x / SECTION_WIDTH)
	var player_section_z = int(player_relative_z / SECTION_DEPTH)
	var player_section_y = int(player_position.y / SECTION_HEIGHT)

	# 计算区块中Section的总数
	var sections_x = Constants.CHUNK_SIZE / SECTION_WIDTH
	var sections_z = Constants.CHUNK_SIZE / SECTION_DEPTH
	var sections_y = Constants.VOXEL_MAX_HEIGHT / SECTION_HEIGHT

	# debug: 记录各优先级分布
	var debug_priority_count = {SectionPriority.HIGH: 0, SectionPriority.MEDIUM: 0, SectionPriority.LOW: 0}

	# 为区块中的每个Section创建任务，根据距离设置优先级

	var max_section_count = chunk.sections.size()
	for sx in range(sections_x):
		for sz in range(sections_z):
			for sy in range(sections_y):
				# 计算一维索引
				var section_index = sy * sections_x * sections_z + sz * sections_x + sx
				if section_index >= max_section_count:
					continue # 跳过越界section

				# 计算优先级：越靠近玩家的Section优先级越高
				var distance_x = abs(sx - player_section_x)
				var distance_z = abs(sz - player_section_z)
				var distance_y = abs(sy - player_section_y)

				var priority = SectionPriority.LOW
				if distance_x <= 1 and distance_z <= 1 and distance_y <= 1:
					priority = SectionPriority.HIGH
				elif distance_x <= 2 and distance_z <= 2 and distance_y <= 2:
					priority = SectionPriority.MEDIUM

				tasks.append(SectionTask.new(chunk, section_index, priority, world_generator))
				debug_priority_count[priority] += 1

	# debug输出优先级分布，便于后续测试
	MyLogger.info("[SectionManager] Section任务优先级分布: HIGH=%d MEDIUM=%d LOW=%d" % [debug_priority_count[SectionPriority.HIGH], debug_priority_count[SectionPriority.MEDIUM], debug_priority_count[SectionPriority.LOW]])

	return tasks

# 按优先级排序Section任务
static func sort_section_tasks(tasks: Array) -> void:
	tasks.sort_custom(Callable(_sort_section_tasks_func))

static func _sort_section_tasks_func(a: SectionTask, b: SectionTask) -> bool:
	# 检查参数有效性
	if not is_instance_valid(a) or not is_instance_valid(b):
		return false
		
	# 高优先级的排在前面
	if a.priority != b.priority:
		return a.priority < b.priority
	
	# 如果优先级相同，按Section索引排序
	return a.section_index < b.section_index

# 生成Section的体素数据
static func generate_section_voxels(task: SectionTask) -> void:
	# 检查参数有效性
	if not is_instance_valid(task) or not is_instance_valid(task.chunk) or not is_instance_valid(task.world_generator):
		return
		
	var chunk = task.chunk
	var section_index = task.section_index
	var generator = task.world_generator
	
	# 获取Section边界
	var bounds = chunk.get_section_bounds(section_index)
	var min_pos = bounds.min
	var max_pos = bounds.max
	
	# 生成这个Section的体素数据
	# 这里应该调用适当的生成函数，现在我们简化处理
	for y in range(min_pos.y, max_pos.y + 1):
		for z in range(min_pos.z, max_pos.z + 1):
			for x in range(min_pos.x, max_pos.x + 1):
				# 这里应该根据世界生成器生成适当的方块
				# 为简化起见，我们现在只生成基岩和石头
				if y == 0:
					chunk.set_voxel_raw(x, y, z, generator._id_bedrock)
				elif y < 32:
					chunk.set_voxel_raw(x, y, z, generator._id_stone)
	
	# 标记Section为已生成
	# 注意：由于我们无法直接访问_chunk的私有方法，需要修改Chunk类

# 生成Section的网格
static func generate_section_mesh(chunk: Chunk, section_index: int) -> void:
	# 检查参数有效性
	if not is_instance_valid(chunk):
		return
		
	chunk.generate_section_mesh(section_index)
