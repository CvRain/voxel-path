class_name Chunk
extends Node3D

# 引入区块生成阶段枚举
const ChunkGenerationStage = preload("res://Scripts/Voxel/chunk_generation_stage.gd").ChunkGenerationStage

var chunk_position: Vector2i
var voxels: PackedByteArray # Stores PALETTE INDICES. 0 is always Air (Global ID 0).
var palette: Resource # Maps Local Index -> Global ID (Type is Resource to avoid cyclic dependency issues if any, but ideally ChunkPalette)
var is_modified: bool = false
var generation_stage: int = 0 # 使用ChunkGenerationStage枚举跟踪生成阶段

# Sections
var sections: Array[MeshInstance3D] = []
var section_bodies: Array[StaticBody3D] = []
var sections_node: Node3D

# Threading tracking
var _active_tasks: Dictionary = {} # section_idx -> task_id

# Neighbors for face culling
var neighbor_front: Chunk
var neighbor_back: Chunk
var neighbor_left: Chunk
var neighbor_right: Chunk

# Section生成状态跟踪
var _generated_sections: PackedByteArray
var _dirty_sections: PackedInt32Array # 需要重新生成网格的Section

# Section 高度使用全局常量：每个 Section 的高度为 Constants.CHUNK_SECTION_SIZE

func _init(pos: Vector2i) -> void:
	chunk_position = pos
	name = "Chunk_%d_%d" % [pos.x, pos.y]
	
	# Initialize Palette
	var ChunkPaletteScript = load("res://Scripts/Voxel/chunk_palette.gd")
	palette = ChunkPaletteScript.new()
	
	# Initialize voxel data
	# Size = Width * Width * Height
	var size = Constants.CHUNK_SIZE * Constants.CHUNK_SIZE * Constants.VOXEL_MAX_HEIGHT
	voxels = PackedByteArray()
	voxels.resize(size)
	voxels.fill(0) # Fill with Index 0 (which is Air in a new Palette)
	
	# 初始化Section生成状态跟踪（仅按 Y 轴分段）
	var section_count = int(ceil(Constants.VOXEL_MAX_HEIGHT / float(Constants.CHUNK_SECTION_SIZE)))
	_generated_sections = PackedByteArray()
	_generated_sections.resize(section_count)
	_generated_sections.fill(0)
	
	_dirty_sections = PackedInt32Array()

func _ready() -> void:
	sections_node = Node3D.new()
	sections_node.name = "Sections"
	add_child(sections_node)
	
	var num_sections = ceil(Constants.VOXEL_MAX_HEIGHT / float(Constants.CHUNK_SECTION_SIZE))
	sections.resize(num_sections)
	section_bodies.resize(num_sections)
	
	var material = StandardMaterial3D.new()
	material.albedo_texture = TextureManager.get_main_atlas()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.vertex_color_use_as_albedo = true # Enabled for biome tinting
	
	for i in range(num_sections):
		var mesh_inst = MeshInstance3D.new()
		mesh_inst.name = "Section_%d" % i
		mesh_inst.material_override = material
		sections_node.add_child(mesh_inst)
		sections[i] = mesh_inst

# 获取指定坐标的Section索引
func _get_section_index(_x: int, y: int, _z: int) -> int:
	# Sections are vertical slices along Y. Compute section index by Y only.
	return int(floor(y / float(Constants.CHUNK_SECTION_SIZE)))

# 标记Section为已生成
func _mark_section_generated(x: int, y: int, z: int) -> void:
	var section_index = _get_section_index(x, y, z)
	if section_index >= 0 and section_index < _generated_sections.size():
		_generated_sections[section_index] = 1

# 检查Section是否已生成
func is_section_generated(x: int, y: int, z: int) -> bool:
	var section_index = _get_section_index(x, y, z)
	if section_index >= 0 and section_index < _generated_sections.size():
		return _generated_sections[section_index] == 1
	return false

# 检查是否所有Section都已生成
func are_all_sections_generated() -> bool:
	for i in range(_generated_sections.size()):
		if _generated_sections[i] == 0:
			return false
	return true

# 获取未生成的Section数量
func get_pending_sections_count() -> int:
	var count = 0
	for i in range(_generated_sections.size()):
		if _generated_sections[i] == 0:
			count += 1
	return count

# 标记Section为脏（需要重新生成网格）
func mark_section_dirty(section_index: int) -> void:
	if not _dirty_sections.has(section_index):
		_dirty_sections.append(section_index)

# 获取Section在世界坐标中的最小和最大坐标
func get_section_bounds(section_index: int) -> Dictionary:
	# Sections span the full X/Z of the chunk and are sliced along Y using Constants.CHUNK_SECTION_SIZE
	var min_x = 0
	var max_x = Constants.CHUNK_SIZE - 1
	var min_z = 0
	var max_z = Constants.CHUNK_SIZE - 1

	var min_y = section_index * Constants.CHUNK_SECTION_SIZE
	var max_y = min(min_y + Constants.CHUNK_SECTION_SIZE - 1, Constants.VOXEL_MAX_HEIGHT - 1)

	return {
		"min": Vector3i(min_x, min_y, min_z),
		"max": Vector3i(max_x, max_y, max_z)
	}

# 生成指定Section的体素数据
func generate_section_voxels(section_index: int, _generator: Node) -> void:
	var bounds = get_section_bounds(section_index)
	var min_pos = bounds.min
	var max_pos = bounds.max
	
	# 生成这个Section的体素数据
	for y in range(min_pos.y, max_pos.y + 1):
		for z in range(min_pos.z, max_pos.z + 1):
			for x in range(min_pos.x, max_pos.x + 1):
				# 这里应该调用适当的生成函数
				# 为了简化，我们现在只是标记Section为已生成
				pass
	
	_mark_section_generated(min_pos.x, min_pos.y, min_pos.z)

# 生成指定Section的网格
func generate_section_mesh(section_index: int) -> void:
	# 创建网格生成任务
	schedule_section_update(section_index)
	
	# 从脏列表中移除
	_dirty_sections.erase(section_index)

func set_voxel(x: int, y: int, z: int, block_id: int, properties: Dictionary = {}) -> void:
	if not is_valid_position(x, y, z):
		return
	
	var state_id = 0
	if properties.is_empty():
		state_id = BlockStateRegistry.get_default_state_id(block_id)
	else:
		state_id = BlockStateRegistry.get_state_id_by_properties(block_id, properties)
		if state_id == -1:
			# Fallback to default if properties are invalid
			state_id = BlockStateRegistry.get_default_state_id(block_id)
			
	set_voxel_state(x, y, z, state_id)

func set_voxel_state(x: int, y: int, z: int, state_id: int) -> void:
	if not is_valid_position(x, y, z):
		return
	
	var index = get_voxel_index(x, y, z)
	# Convert Global State ID -> Local Index
	var local_index = palette.get_local_index(state_id)
	
	if voxels[index] != local_index:
		voxels[index] = local_index
		is_modified = true
		
		# 更新受影响的Section
		var section_index = _get_section_index(x, y, z)
		mark_section_dirty(section_index)
		
		# 更新相邻的Section（如果在边界上）
		_check_and_mark_adjacent_sections(x, y, z)

# 检查并标记相邻的Section（如果在边界上）
func _check_and_mark_adjacent_sections(x: int, y: int, z: int) -> void:
	# 检查X边界
	if x == 0:
		if x > 0:
			mark_section_dirty(_get_section_index(x - 1, y, z))
	elif x == Constants.CHUNK_SIZE - 1:
		if x < Constants.CHUNK_SIZE - 1:
			mark_section_dirty(_get_section_index(x + 1, y, z))
	
	# 检查Y边界
	if y == 0:
		if y > 0:
			mark_section_dirty(_get_section_index(x, y - 1, z))
	elif y == Constants.VOXEL_MAX_HEIGHT - 1:
		if y < Constants.VOXEL_MAX_HEIGHT - 1:
			mark_section_dirty(_get_section_index(x, y + 1, z))
	
	# 检查Z边界
	if z == 0:
		if z > 0:
			mark_section_dirty(_get_section_index(x, y, z - 1))
	elif z == Constants.CHUNK_SIZE - 1:
		if z < Constants.CHUNK_SIZE - 1:
			mark_section_dirty(_get_section_index(x, y, z + 1))

# Raw setter that DOES NOT trigger mesh updates.
# Use this for world generation or batch updates.
func set_voxel_raw(x: int, y: int, z: int, block_id: int) -> void:
	if not is_valid_position(x, y, z):
		return
		
	var state_id = BlockStateRegistry.get_default_state_id(block_id)
	set_voxel_state_raw(x, y, z, state_id)

func set_voxel_state_raw(x: int, y: int, z: int, state_id: int) -> void:
	if not is_valid_position(x, y, z):
		return
	
	var index = get_voxel_index(x, y, z)
	# Convert Global State ID -> Local Index
	var local_index = palette.get_local_index(state_id)
	
	if voxels[index] != local_index:
		voxels[index] = local_index
		is_modified = true

func update_mesh_for_voxel(x: int, y: int, z: int) -> void:
	var section_idx = floori(y / float(Constants.CHUNK_SECTION_SIZE))
	schedule_section_update(section_idx)
	
	# Check if we need to update neighbors (if on boundary)
	var local_y = y % Constants.CHUNK_SECTION_SIZE
	if local_y == 0 and section_idx > 0:
		schedule_section_update(section_idx - 1)
	elif local_y == Constants.CHUNK_SECTION_SIZE - 1 and section_idx < sections.size() - 1:
		schedule_section_update(section_idx + 1)
	
	# Check Chunk Neighbors
	if x == 0 and neighbor_left:
		neighbor_left.schedule_section_update(section_idx)
	elif x == Constants.CHUNK_SIZE - 1 and neighbor_right:
		neighbor_right.schedule_section_update(section_idx)
		
	if z == 0 and neighbor_front:
		neighbor_front.schedule_section_update(section_idx)
	elif z == Constants.CHUNK_SIZE - 1 and neighbor_back:
		neighbor_back.schedule_section_update(section_idx)

func schedule_section_update(section_idx: int) -> void:
	# For single updates, we still need a snapshot to be thread-safe
	var voxel_snapshot = voxels.duplicate()
	# Also snapshot the palette map to ensure thread safety
	var palette_map = palette._id_map.duplicate()
	_schedule_section_update_internal(section_idx, voxel_snapshot, palette_map)

func _schedule_section_update_internal(section_idx: int, voxel_snapshot: PackedByteArray, palette_map: Array) -> void:
	# Capture neighbor snapshots for thread safety
	# We pass the raw voxels (COW) and a duplicate of the palette map
	var neighbors_data = {}
	
	if neighbor_left:
		neighbors_data["left"] = [neighbor_left.voxels.duplicate(), neighbor_left.palette._id_map.duplicate()]
	if neighbor_right:
		neighbors_data["right"] = [neighbor_right.voxels.duplicate(), neighbor_right.palette._id_map.duplicate()]
	if neighbor_front:
		neighbors_data["front"] = [neighbor_front.voxels.duplicate(), neighbor_front.palette._id_map.duplicate()]
	if neighbor_back:
		neighbors_data["back"] = [neighbor_back.voxels.duplicate(), neighbor_back.palette._id_map.duplicate()]

	WorkerThreadPool.add_task(
		_thread_generate_mesh.bind(section_idx, voxel_snapshot, palette_map, neighbors_data),
		true,
		"Mesh Gen Section %d" % section_idx
	)

func update_specific_sections(section_indices: Array) -> void:
	if section_indices.is_empty():
		return
		
	# Create ONE snapshot for this batch
	var shared_snapshot = voxels.duplicate()
	var palette_map = palette._id_map.duplicate()
	
	for section_idx in section_indices:
		if section_idx >= 0 and section_idx < sections.size():
			_schedule_section_update_internal(section_idx, shared_snapshot, palette_map)

func generate_mesh() -> void:
	# 为了避免阻塞主线程，我们将网格生成任务加入队列而不是立即执行
	schedule_all_sections_update()

func schedule_all_sections_update() -> void:
	# OPTIMIZATION: Create ONE snapshot for all sections
	# This prevents 16x memory usage explosion (16 sections * 4MB = 64MB per chunk!)
	var shared_snapshot = voxels.duplicate()
	var palette_map = palette._id_map.duplicate()
	
	# Generate all sections using the shared snapshot
	for i in range(sections.size()):
		_schedule_section_update_internal(i, shared_snapshot, palette_map)

# --- Threaded Function ---
# This runs on a background thread. CANNOT touch SceneTree nodes.
func _thread_generate_mesh(section_idx: int, voxel_data: PackedByteArray, palette_map: Array, neighbors_data: Dictionary) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var voxel_size = Constants.VOXEL_SIZE
	var start_y = section_idx * Constants.CHUNK_SECTION_SIZE
	var end_y = min((section_idx + 1) * Constants.CHUNK_SECTION_SIZE, Constants.VOXEL_MAX_HEIGHT)
	
	var has_faces = false
	
	# Pre-calculate bounds to avoid repeated lookups
	var chunk_size = Constants.CHUNK_SIZE
	var stride_y = chunk_size * chunk_size
	var stride_z = chunk_size
	
	for y in range(start_y, end_y):
		var y_base_idx = y * stride_y
		for z in range(chunk_size):
			var z_base_idx = y_base_idx + (z * stride_z)
			for x in range(chunk_size):
				# Use local snapshot data
				var index = z_base_idx + x
				var local_index = voxel_data[index]
				
				if local_index == 0: # Index 0 is always Air
					continue
				
				# Convert Local Index -> Global ID using the snapshot palette map
				var state_id = 0
				if local_index < palette_map.size():
					state_id = palette_map[local_index]
				
				if state_id == 0: # Air State
					continue
				
				# BlockRegistry is static, safe to read if not modifying
				var state = BlockStateRegistry.get_state(state_id)
				if not state: continue
				
				var block = BlockRegistry.get_block(state.block_id)
				if not block: continue
				
				var pos = Vector3(x, y, z) * voxel_size
				
				# --- Face Culling Logic ---
				
				# Top (y+1)
				if y == Constants.VOXEL_MAX_HEIGHT - 1 or (y < Constants.VOXEL_MAX_HEIGHT - 1 and voxel_data[index + stride_y] == 0):
					add_face(st, pos, "top", block)
					has_faces = true
				
				# Bottom (y-1)
				if y == 0 or (y > 0 and voxel_data[index - stride_y] == 0):
					add_face(st, pos, "bottom", block)
					has_faces = true
				
				# Right (x+1)
				var draw_right = false
				if x < chunk_size - 1:
					if voxel_data[index + 1] == 0: draw_right = true
				else:
					# Check neighbor right
					if not neighbors_data.has("right"):
						draw_right = true
					else:
						var n_data = neighbors_data["right"]
						var n_voxels = n_data[0]
						var n_pal = n_data[1]
						# Neighbor x=0, same y, z
						var n_idx = (y * stride_y) + (z * stride_z) + 0
						var n_local = n_voxels[n_idx]
						if n_local == 0:
							draw_right = true
						else:
							var n_global = n_pal[n_local] if n_local < n_pal.size() else 0
							if n_global == 0: draw_right = true
				
				if draw_right:
					add_face(st, pos, "right", block)
					has_faces = true
				
				# Left (x-1)
				var draw_left = false
				if x > 0:
					if voxel_data[index - 1] == 0: draw_left = true
				else:
					# Check neighbor left
					if not neighbors_data.has("left"):
						draw_left = true
					else:
						var n_data = neighbors_data["left"]
						var n_voxels = n_data[0]
						var n_pal = n_data[1]
						# Neighbor x=chunk_size-1, same y, z
						var n_idx = (y * stride_y) + (z * stride_z) + (chunk_size - 1)
						var n_local = n_voxels[n_idx]
						if n_local == 0:
							draw_left = true
						else:
							var n_global = n_pal[n_local] if n_local < n_pal.size() else 0
							if n_global == 0: draw_left = true
				
				if draw_left:
					add_face(st, pos, "left", block)
					has_faces = true
				
				# Back (z+1)
				var draw_back = false
				if z < chunk_size - 1:
					if voxel_data[index + stride_z] == 0: draw_back = true
				else:
					# Check neighbor back
					if not neighbors_data.has("back"):
						draw_back = true
					else:
						var n_data = neighbors_data["back"]
						var n_voxels = n_data[0]
						var n_pal = n_data[1]
						# Neighbor z=0, same y, x
						var n_idx = (y * stride_y) + (0 * stride_z) + x
						var n_local = n_voxels[n_idx]
						if n_local == 0:
							draw_back = true
						else:
							var n_global = n_pal[n_local] if n_local < n_pal.size() else 0
							if n_global == 0: draw_back = true
				
				if draw_back:
					add_face(st, pos, "back", block)
					has_faces = true
				
				# Front (z-1)
				var draw_front = false
				if z > 0:
					if voxel_data[index - stride_z] == 0: draw_front = true
				else:
					# Check neighbor front
					if not neighbors_data.has("front"):
						draw_front = true
					else:
						var n_data = neighbors_data["front"]
						var n_voxels = n_data[0]
						var n_pal = n_data[1]
						# Neighbor z=chunk_size-1, same y, x
						var n_idx = (y * stride_y) + ((chunk_size - 1) * stride_z) + x
						var n_local = n_voxels[n_idx]
						if n_local == 0:
							draw_front = true
						else:
							var n_global = n_pal[n_local] if n_local < n_pal.size() else 0
							if n_global == 0: draw_front = true
				
				if draw_front:
					add_face(st, pos, "front", block)
					has_faces = true

	var mesh_arrays = []
	if has_faces:
		st.generate_normals()
		st.generate_tangents()
		# commit_to_arrays returns the ArrayMesh data array (vertices, normals, etc)
		# This is a pure data object, safe to pass back.
		mesh_arrays = st.commit_to_arrays()
	
	# Dispatch back to main thread
	call_deferred("_apply_mesh_update", section_idx, mesh_arrays)

# --- Main Thread Function ---
func _apply_mesh_update(section_idx: int, mesh_arrays: Array) -> void:
	var mesh_inst = sections[section_idx]
	
	# Clear existing collision
	if section_bodies[section_idx]:
		section_bodies[section_idx].queue_free()
		section_bodies[section_idx] = null

	if mesh_arrays.size() > 0:
		var arr_mesh = ArrayMesh.new()
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays)
		mesh_inst.mesh = arr_mesh
		
		# Create collision (Must be on main thread)
		mesh_inst.create_trimesh_collision()
		if mesh_inst.get_child_count() > 0:
			var child = mesh_inst.get_child(mesh_inst.get_child_count() - 1)
			if child is StaticBody3D:
				section_bodies[section_idx] = child
	else:
		mesh_inst.mesh = null

# 回写 section 的体素数据（由后台线程完成计算后在主线程调用）
func _apply_section_voxels(section_index: int, voxel_data: PackedInt32Array, stage: int) -> void:
	# voxel_data: sequence of ints in groups of 4: x, y, z, block_id
	var data_len = voxel_data.size()
	for i in range(0, data_len, 4):
		var x = voxel_data[i]
		var y = voxel_data[i + 1]
		var z = voxel_data[i + 2]
		var block_id = voxel_data[i + 3]
		set_voxel_raw(x, y, z, block_id)

	# 标记该 section 为已生成（使用 section 内任意坐标）
	var bounds = get_section_bounds(section_index)
	var min_pos = bounds.min
	_mark_section_generated(min_pos.x, min_pos.y, min_pos.z)

	# 立即安排该 Section 的网格生成以便可见切换
	generate_section_mesh(section_index)

	# 如果这是最终阶段（整个区块完成），则触发整区网格生成
	if stage >= ChunkGenerationStage.FULLY_GENERATED:
		generate_mesh()

	# 通知父节点（通常是 RandomWorld）某个 section 已完成
	if get_parent() and get_parent().has_method("_on_chunk_section_complete"):
		get_parent().call_deferred("_on_chunk_section_complete", self, stage)

# Thread-safe visibility check
func _thread_is_face_visible(_x: int, _y: int, _z: int, _local_voxels: PackedByteArray) -> bool:
	# DEPRECATED: This function is no longer used by the optimized mesh generator.
	# It is kept only if needed for other logic, but should be removed eventually.
	return true

func get_voxel(x: int, y: int, z: int) -> int:
	if not is_valid_position(x, y, z):
		return Constants.AIR_BLOCK_ID
	
	var local_index = voxels[get_voxel_index(x, y, z)]
	var state_id = palette.get_global_id(local_index)
	
	if state_id == 0:
		return Constants.AIR_BLOCK_ID
		
	var state = BlockStateRegistry.get_state(state_id)
	if state:
		return state.block_id
	return Constants.AIR_BLOCK_ID

func get_voxel_state(x: int, y: int, z: int) -> int:
	if not is_valid_position(x, y, z):
		return 0 # Air State ID
	
	var local_index = voxels[get_voxel_index(x, y, z)]
	return palette.get_global_id(local_index)

func get_voxel_global(x: int, y: int, z: int) -> int:
	# Check if inside this chunk
	if is_valid_position(x, y, z):
		var local_index = voxels[get_voxel_index(x, y, z)]
		var state_id = palette.get_global_id(local_index)
		if state_id == 0: return Constants.AIR_BLOCK_ID
		var state = BlockStateRegistry.get_state(state_id)
		return state.block_id if state else Constants.AIR_BLOCK_ID
	
	# Check neighbors
	if x < 0:
		return neighbor_left.get_voxel(x + Constants.CHUNK_SIZE, y, z) if neighbor_left else Constants.AIR_BLOCK_ID
	if x >= Constants.CHUNK_SIZE:
		return neighbor_right.get_voxel(x - Constants.CHUNK_SIZE, y, z) if neighbor_right else Constants.AIR_BLOCK_ID
	if z < 0:
		return neighbor_front.get_voxel(x, y, z + Constants.CHUNK_SIZE) if neighbor_front else Constants.AIR_BLOCK_ID
	if z >= Constants.CHUNK_SIZE:
		return neighbor_back.get_voxel(x, y, z - Constants.CHUNK_SIZE) if neighbor_back else Constants.AIR_BLOCK_ID
		
	return Constants.AIR_BLOCK_ID

func get_voxel_index(x: int, y: int, z: int) -> int:
	return (y * Constants.CHUNK_SIZE * Constants.CHUNK_SIZE) + (z * Constants.CHUNK_SIZE) + x

func is_valid_position(x: int, y: int, z: int) -> bool:
	return x >= 0 and x < Constants.CHUNK_SIZE and \
		   z >= 0 and z < Constants.CHUNK_SIZE and \
		   y >= 0 and y < Constants.VOXEL_MAX_HEIGHT


func is_face_visible(x: int, y: int, z: int) -> bool:
	# If y is out of bounds (top/bottom of world), face is visible
	if y < 0 or y >= Constants.VOXEL_MAX_HEIGHT:
		return true
	
	var neighbor_id = get_voxel_global(x, y, z)
	
	# If neighbor is air, face is visible
	if neighbor_id == Constants.AIR_BLOCK_ID:
		return true
		
	# If neighbor is transparent (e.g. glass, water), face is visible
	# TODO: Check block transparency
	
	return false

"""
为方块贴上纹理，并根据方块类型进行简单的生物群系染色处理。
不过有些写法需要优化。
首先是提供的纹理素材是16x16的，考虑到方块会存在不同的变体，比如树干，那么在角落上和面上的贴图中，纹理是不一样的，而树心就应该是比较单一的颜色。
而且现在也简单的使用的一种素材，之后还要考虑到顶部贴图和侧面贴图是不一样的情况。

其次是生物群系染色处理，现在只是简单的对草方块进行染色处理，之后还要考虑更多的方块类型和更复杂的染色逻辑。
"""
func add_face(st: SurfaceTool, pos: Vector3, face: String, block: BlockData) -> void:
	var s = Constants.VOXEL_SIZE
	var uv_rect = Rect2(0, 0, 1, 1)
	
	# Determine texture frame
	var frame_index = 0
	if block.random_texture_frames > 1:
		# Deterministic random based on position
		# We use a simple hash of the coordinates
		var pos_hash = int(pos.x / s) * 31 + int(pos.y / s) * 37 + int(pos.z / s) * 41
		frame_index = abs(pos_hash) % block.random_texture_frames
	
	var texture_uv = block.get_texture_uv(face, "diffuse", frame_index)
	if texture_uv:
		uv_rect = texture_uv.uv_rect
		
		# 使用16x16的素材，裁剪成16x16的素材
		var crop_ratio = 16.0 / 16.0
		uv_rect.size *= crop_ratio
	
	# Determine color (Biome tinting)
	# todo: 这是需要优化的写法
	var color = Color.WHITE
	if block.name == "grass":
		if face != "bottom":
			# Basic green tint for grass
			color = Color(0.4, 0.85, 0.4)

	if block.name == "oak_leaves":
		# Light green tint for leaves
		color = Color(0.5, 0.8, 0.5)
	
	var uv_bl = Vector2(uv_rect.position.x, uv_rect.position.y + uv_rect.size.y)
	var uv_br = Vector2(uv_rect.position.x + uv_rect.size.x, uv_rect.position.y + uv_rect.size.y)
	var uv_tr = Vector2(uv_rect.position.x + uv_rect.size.x, uv_rect.position.y)
	var uv_tl = Vector2(uv_rect.position.x, uv_rect.position.y)
	
	# Vertices based on our corrected TestWorld logic (CW winding)
	var v_bl: Vector3
	var v_br: Vector3
	var v_tr: Vector3
	var v_tl: Vector3
	var normal: Vector3
	
	match face:
		"front": # -Z direction
			normal = Vector3(0, 0, -1)
			v_bl = pos + Vector3(s, 0, 0)
			v_br = pos + Vector3(0, 0, 0)
			v_tr = pos + Vector3(0, s, 0)
			v_tl = pos + Vector3(s, s, 0)
		"back": # +Z direction
			normal = Vector3(0, 0, 1)
			v_bl = pos + Vector3(0, 0, s)
			v_br = pos + Vector3(s, 0, s)
			v_tr = pos + Vector3(s, s, s)
			v_tl = pos + Vector3(0, s, s)
		"top": # +Y direction
			normal = Vector3(0, 1, 0)
			v_bl = pos + Vector3(0, s, s)
			v_br = pos + Vector3(s, s, s)
			v_tr = pos + Vector3(s, s, 0)
			v_tl = pos + Vector3(0, s, 0)
		"bottom": # -Y direction
			normal = Vector3(0, -1, 0)
			v_bl = pos + Vector3(0, 0, 0)
			v_br = pos + Vector3(s, 0, 0)
			v_tr = pos + Vector3(s, 0, s)
			v_tl = pos + Vector3(0, 0, s)
		"left": # -X direction
			normal = Vector3(-1, 0, 0)
			v_bl = pos + Vector3(0, 0, 0)
			v_br = pos + Vector3(0, 0, s)
			v_tr = pos + Vector3(0, s, s)
			v_tl = pos + Vector3(0, s, 0)
		"right": # +X direction
			normal = Vector3(1, 0, 0)
			v_bl = pos + Vector3(s, 0, s)
			v_br = pos + Vector3(s, 0, 0)
			v_tr = pos + Vector3(s, s, 0)
			v_tl = pos + Vector3(s, s, s)

	# Triangle 1: BL -> TR -> BR (CW)
	st.set_normal(normal)
	st.set_color(color)
	st.set_uv(uv_bl)
	st.add_vertex(v_bl)
	
	st.set_normal(normal)
	st.set_color(color)
	st.set_uv(uv_tr)
	st.add_vertex(v_tr)
	
	st.set_normal(normal)
	st.set_color(color)
	st.set_uv(uv_br)
	st.add_vertex(v_br)
	
	# Triangle 2: BL -> TL -> TR (CW)
	st.set_normal(normal)
	st.set_color(color)
	st.set_uv(uv_bl)
	st.add_vertex(v_bl)
	
	st.set_normal(normal)
	st.set_color(color)
	st.set_uv(uv_tl)
	st.add_vertex(v_tl)
	
	st.set_normal(normal)
	st.set_color(color)
	st.set_uv(uv_tr)
	st.add_vertex(v_tr)
