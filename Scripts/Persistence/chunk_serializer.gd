class_name ChunkSerializer
extends RefCounted

# 文件头标识 (Magic Number) - 用于识别文件类型
const MAGIC_HEADER = "VOXC" # Voxel Chunk
const VERSION = 1

# 保存区块到磁盘
# 格式设计:
# [Header 4 bytes] "VOXC"
# [Version 1 byte] 1
# [Palette Size 2 bytes] (N)
# [Palette Data N * 4 bytes] (Global State IDs)
# [Voxel Data Length 4 bytes] (Compressed Size)
# [Voxel Data Body] (ZSTD Compressed PackedByteArray)
static func save_chunk(chunk: Chunk, folder_path: String) -> void:
	var file_name = "chunk_%d_%d.dat" % [chunk.chunk_position.x, chunk.chunk_position.y]
	var full_path = folder_path.path_join(file_name)
	
	# 确保目录存在
	var dir = DirAccess.open("user://")
	if not dir.dir_exists(folder_path):
		dir.make_dir_recursive(folder_path)
	
	var file = FileAccess.open(full_path, FileAccess.WRITE)
	if not file:
		push_error("Failed to open file for saving: %s" % full_path)
		return
	
	# 1. 写入文件头
	file.store_buffer(MAGIC_HEADER.to_ascii_buffer())
	file.store_8(VERSION)
	
	# 2. 序列化 Palette
	# 获取 Palette 中的 Global State ID 列表
	var palette_map = chunk.palette._id_map
	var palette_size = palette_map.size()
	
	file.store_16(palette_size)
	for global_state_id in palette_map:
		file.store_32(global_state_id)
		
	# 3. 序列化 Voxel Data
	# 使用 ZSTD 压缩体素数组
	# 原始数据是 8-bit 的索引数组，其中包含大量的 0 (空气) 或重复数据
	# 压缩算法能极大地减小体积，起到类似"稀疏矩阵"存储的效果
	var raw_voxels = chunk.voxels
	var compressed_voxels = raw_voxels.compress(FileAccess.COMPRESSION_ZSTD)
	
	file.store_32(compressed_voxels.size())
	file.store_buffer(compressed_voxels)
	
	file.close()
	# print("Saved chunk: %s (Size: %d bytes)" % [file_name, file.get_length()])

# 从磁盘加载区块
static func load_chunk(chunk: Chunk, folder_path: String) -> bool:
	var file_name = "chunk_%d_%d.dat" % [chunk.chunk_position.x, chunk.chunk_position.y]
	var full_path = folder_path.path_join(file_name)
	
	if not FileAccess.file_exists(full_path):
		return false
		
	var file = FileAccess.open(full_path, FileAccess.READ)
	if not file:
		return false
		
	# 1. 验证文件头
	var magic = file.get_buffer(4).get_string_from_ascii()
	if magic != MAGIC_HEADER:
		push_error("Invalid chunk file format: %s" % full_path)
		return false
		
	var version = file.get_8()
	if version != VERSION:
		push_warning("Chunk file version mismatch. Expected %d, got %d" % [VERSION, version])
		# 这里可以添加版本迁移逻辑
		
	# 2. 读取 Palette
	var palette_size = file.get_16()
	var new_id_map: Array[int] = []
	new_id_map.resize(palette_size)
	
	for i in range(palette_size):
		new_id_map[i] = file.get_32()
	
	# 重建 ChunkPalette
	# 注意：我们需要清空旧的映射并重建反向查找表
	chunk.palette._id_map = new_id_map
	chunk.palette._reverse_map.clear()
	for i in range(palette_size):
		chunk.palette._reverse_map[new_id_map[i]] = i
		
	# 3. 读取 Voxel Data
	var compressed_size = file.get_32()
	var compressed_voxels = file.get_buffer(compressed_size)
	
	# 解压
	# 我们需要知道解压后的预期大小来分配缓冲区
	var expected_size = Constants.CHUNK_SIZE * Constants.CHUNK_SIZE * Constants.VOXEL_MAX_HEIGHT
	var decompressed_voxels = compressed_voxels.decompress(expected_size, FileAccess.COMPRESSION_ZSTD)
	
	if decompressed_voxels.size() != expected_size:
		push_error("Decompressed voxel data size mismatch! Expected %d, got %d" % [expected_size, decompressed_voxels.size()])
		return false
		
	chunk.voxels = decompressed_voxels
	chunk.is_modified = false # 加载后重置修改标记
	
	return true
