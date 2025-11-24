class_name ChunkPalette
extends Resource

# 存储映射关系: Local Index (数组下标) -> Global ID (值)
# 例如: [0, 1, 56] 表示:
# Index 0 -> Global ID 0 (Air)
# Index 1 -> Global ID 1 (Stone)
# Index 2 -> Global ID 56 (Diamond Ore)
@export var _id_map: Array[int] = []

# 反向查找缓存: Global ID -> Local Index
# 这是一个运行时缓存，不需要序列化保存到磁盘
var _reverse_map: Dictionary = {}

func _init() -> void:
	# 默认总是包含空气，且空气总是索引 0
	if _id_map.is_empty():
		_id_map.append(Constants.AIR_BLOCK_ID)
		_reverse_map[Constants.AIR_BLOCK_ID] = 0

# 从本地索引获取全局 ID (用于读取方块)
func get_global_id(local_index: int) -> int:
	if local_index >= 0 and local_index < _id_map.size():
		return _id_map[local_index]
	# 如果索引越界，默认返回空气
	return Constants.AIR_BLOCK_ID

# 从全局 ID 获取本地索引 (用于写入方块)
# 如果该 ID 尚未在 Palette 中，会自动添加
func get_local_index(global_id: int) -> int:
	# 1. 尝试从缓存中查找
	if global_id in _reverse_map:
		return _reverse_map[global_id]
	
	# 2. 如果缓存没有，可能是在 _id_map 里但没建立缓存 (比如刚加载完)
	# 这种情况通常只发生在初始化后第一次访问。
	# 为了性能，我们主要依赖 _reverse_map，如果 _reverse_map 没找到，
	# 我们就认为它不在 Palette 中，需要添加。
	
	# 3. 添加新映射
	# 检查是否超过了存储限制 (目前 Chunk 使用 8-bit 存储，最大 256)
	if _id_map.size() >= 256:
		push_warning("ChunkPalette full! Cannot add block ID: %d" % global_id)
		# 降级处理：返回空气或者一个特殊的 '错误方块' 索引
		# 这里简单返回 0 (Air)
		return 0
		
	var new_index = _id_map.size()
	_id_map.append(global_id)
	_reverse_map[global_id] = new_index
	
	return new_index

# 在加载资源后重建反向映射缓存
func rebuild_reverse_map() -> void:
	_reverse_map.clear()
	for i in range(_id_map.size()):
		var global_id = _id_map[i]
		_reverse_map[global_id] = i

# 序列化支持：ResourceLoader 加载时会自动处理 @export 的 _id_map
# 我们只需要确保加载后重建缓存即可
# 注意：Resource 没有 _ready 方法，通常由使用者调用初始化
