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
	# 添加区块整体碰撞体积（用于玩家进入/离开判定，不参与物理阻挡）
	sections_node = Node3D.new()
	sections_node.name = "Sections"
	add_child(sections_node)

	# 优化：只保留地表和水体两个MeshInstance，所有Section网格合并写入
	sections.resize(2)
	section_bodies.resize(2)

	var material = StandardMaterial3D.new()
	material.albedo_texture = TextureManager.get_main_atlas()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.vertex_color_use_as_albedo = true

	for i in range(2):
		var mesh_inst = MeshInstance3D.new()
		mesh_inst.name = "Surface" if i == 0 else "Water"
		mesh_inst.material_override = material
		sections_node.add_child(mesh_inst)
		sections[i] = mesh_inst

	var chunk_size_vec = Vector3(Constants.CHUNK_SIZE * Constants.VOXEL_SIZE, Constants.VOXEL_MAX_HEIGHT * Constants.VOXEL_SIZE, Constants.CHUNK_SIZE * Constants.VOXEL_SIZE)

	var chunk_body = StaticBody3D.new()
	chunk_body.name = "ChunkCollision"
	var chunk_shape = BoxShape3D.new()
	chunk_shape.size = chunk_size_vec
	var shape_instance = CollisionShape3D.new()
	shape_instance.shape = chunk_shape
	chunk_body.add_child(shape_instance)
	chunk_body.collision_layer = 0
	chunk_body.collision_mask = 0
	add_child(chunk_body)

	var area = Area3D.new()
	area.name = "ChunkArea"
	var area_shape = BoxShape3D.new()
	area_shape.size = chunk_size_vec
	var area_shape_instance = CollisionShape3D.new()
	area_shape_instance.shape = area_shape
	area.add_child(area_shape_instance)
	area.collision_layer = 0
	area.collision_mask = 1 # 玩家应在layer 1
	add_child(area)

	# 连接信号（进入/离开）
	area.body_entered.connect(self._on_body_entered)
	area.body_exited.connect(self._on_body_exited)
# 玩家进入区块Area3D的信号处理
func _on_body_entered(body):
	if body and body.is_in_group("player"):
		if get_parent() and get_parent().has_method("_on_player_enter_chunk"):
			get_parent()._on_player_enter_chunk(chunk_position)

# 玩家离开区块Area3D的信号处理
func _on_body_exited(body):
	if body and body.is_in_group("player"):
		if get_parent() and get_parent().has_method("_on_player_exit_chunk"):
			get_parent()._on_player_exit_chunk(chunk_position)

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
	
	# 贪婪网格（Strip Meshing）状态变量
	# 我们只在 X 轴方向上合并 Top, Bottom, Front, Back 面
	# Left 和 Right 面由于在 X 轴上不共面，无法在此循环中简单合并（需要改变循环顺序）
	var run_top = {"active": false, "start_x": - 1, "block": null}
	var run_bottom = {"active": false, "start_x": - 1, "block": null}
	var run_front = {"active": false, "start_x": - 1, "block": null}
	var run_back = {"active": false, "start_x": - 1, "block": null}

	for y in range(start_y, end_y):
		var y_base_idx = y * stride_y
		for z in range(chunk_size):
			var z_base_idx = y_base_idx + (z * stride_z)
			
			# 重置每行的 Run 状态
			run_top = {"active": false, "start_x": - 1, "block": null}
			run_bottom = {"active": false, "start_x": - 1, "block": null}
			run_front = {"active": false, "start_x": - 1, "block": null}
			run_back = {"active": false, "start_x": - 1, "block": null}
			
			for x in range(chunk_size):
				# Use local snapshot data
				var index = z_base_idx + x
				var local_index = voxel_data[index]
				
				var block = null
				if local_index != 0:
					var state_id = 0
					if local_index < palette_map.size():
						state_id = palette_map[local_index]
					if state_id != 0:
						var state = BlockStateRegistry.get_state(state_id)
						if state:
							block = BlockRegistry.get_block(state.block_id)
				
				# 如果是空气或非地表方块（根据之前的逻辑），视为不可见/不生成
				var is_valid_block = false
				if block:
					if block.name == "water" or block.name == "grass" or block.name == "dirt" or block.name == "sand" or block.name == "oak_leaves" or block.name == "oak_log":
						is_valid_block = true
				
				if not is_valid_block:
					# 当前位置为空或无效，结束所有 Run
					if run_top.active:
						add_face(st, Vector3(run_top.start_x, y, z) * voxel_size, "top", run_top.block, x - run_top.start_x, 1.0)
						has_faces = true
						run_top.active = false
					if run_bottom.active:
						add_face(st, Vector3(run_bottom.start_x, y, z) * voxel_size, "bottom", run_bottom.block, x - run_bottom.start_x, 1.0)
						has_faces = true
						run_bottom.active = false
					if run_front.active:
						add_face(st, Vector3(run_front.start_x, y, z) * voxel_size, "front", run_front.block, x - run_front.start_x, 1.0)
						has_faces = true
						run_front.active = false
					if run_back.active:
						add_face(st, Vector3(run_back.start_x, y, z) * voxel_size, "back", run_back.block, x - run_back.start_x, 1.0)
						has_faces = true
						run_back.active = false
					
					# Left/Right 面仍然需要单独处理（因为它们不参与 X 轴合并）
					# 但因为当前位置是空的，所以不需要生成 Left/Right
					# 不过，如果当前是空的，可能会暴露左边方块的 Right 面，或右边方块的 Left 面
					# 这在之前的逻辑中是在遍历到那个方块时处理的。
					# 这里我们只处理“当前方块”的面。
					continue

				var pos = Vector3(x, y, z) * voxel_size

				# --- Top Face (y+1) ---
				var show_top = false
				if y == Constants.VOXEL_MAX_HEIGHT - 1 or (y < Constants.VOXEL_MAX_HEIGHT - 1 and voxel_data[index + stride_y] == 0):
					show_top = true
				
				if show_top:
					if run_top.active and run_top.block == block:
						# Continue run
						pass
					else:
						# End previous run
						if run_top.active:
							add_face(st, Vector3(run_top.start_x, y, z) * voxel_size, "top", run_top.block, x - run_top.start_x, 1.0)
							has_faces = true
						# Start new run
						run_top = {"active": true, "start_x": x, "block": block}
				else:
					# End run
					if run_top.active:
						add_face(st, Vector3(run_top.start_x, y, z) * voxel_size, "top", run_top.block, x - run_top.start_x, 1.0)
						has_faces = true
						run_top.active = false

				# --- Bottom Face (y-1) ---
				var show_bottom = false
				if y == 0 or (y > 0 and voxel_data[index - stride_y] == 0):
					show_bottom = true
				
				if show_bottom:
					if run_bottom.active and run_bottom.block == block:
						pass
					else:
						if run_bottom.active:
							add_face(st, Vector3(run_bottom.start_x, y, z) * voxel_size, "bottom", run_bottom.block, x - run_bottom.start_x, 1.0)
							has_faces = true
						run_bottom = {"active": true, "start_x": x, "block": block}
				else:
					if run_bottom.active:
						add_face(st, Vector3(run_bottom.start_x, y, z) * voxel_size, "bottom", run_bottom.block, x - run_bottom.start_x, 1.0)
						has_faces = true
						run_bottom.active = false

				# --- Front Face (z-1) ---
				var show_front = false
				if z > 0:
					if voxel_data[index - stride_z] == 0: show_front = true
				else:
					if not neighbors_data.has("front"):
						show_front = true
					else:
						var n_data = neighbors_data["front"]
						var n_voxels = n_data[0]
						var n_pal = n_data[1]
						var n_idx = (y * stride_y) + ((chunk_size - 1) * stride_z) + x
						var n_local = n_voxels[n_idx]
						if n_local == 0: show_front = true
						else:
							var n_global = n_pal[n_local] if n_local < n_pal.size() else 0
							if n_global == 0: show_front = true
				
				if show_front:
					if run_front.active and run_front.block == block:
						pass
					else:
						if run_front.active:
							add_face(st, Vector3(run_front.start_x, y, z) * voxel_size, "front", run_front.block, x - run_front.start_x, 1.0)
							has_faces = true
						run_front = {"active": true, "start_x": x, "block": block}
				else:
					if run_front.active:
						add_face(st, Vector3(run_front.start_x, y, z) * voxel_size, "front", run_front.block, x - run_front.start_x, 1.0)
						has_faces = true
						run_front.active = false

				# --- Back Face (z+1) ---
				var show_back = false
				if z < chunk_size - 1:
					if voxel_data[index + stride_z] == 0: show_back = true
				else:
					if not neighbors_data.has("back"):
						show_back = true
					else:
						var n_data = neighbors_data["back"]
						var n_voxels = n_data[0]
						var n_pal = n_data[1]
						var n_idx = (y * stride_y) + (0 * stride_z) + x
						var n_local = n_voxels[n_idx]
						if n_local == 0: show_back = true
						else:
							var n_global = n_pal[n_local] if n_local < n_pal.size() else 0
							if n_global == 0: show_back = true
				
				if show_back:
					if run_back.active and run_back.block == block:
						pass
					else:
						if run_back.active:
							add_face(st, Vector3(run_back.start_x, y, z) * voxel_size, "back", run_back.block, x - run_back.start_x, 1.0)
							has_faces = true
						run_back = {"active": true, "start_x": x, "block": block}
				else:
					if run_back.active:
						add_face(st, Vector3(run_back.start_x, y, z) * voxel_size, "back", run_back.block, x - run_back.start_x, 1.0)
						has_faces = true
						run_back.active = false

				# --- Left Face (x-1) ---
				# Left/Right faces cannot be merged along X axis in this loop structure.
				# We just draw them individually.
				var draw_left = false
				if x > 0:
					if voxel_data[index - 1] == 0: draw_left = true
				else:
					if not neighbors_data.has("left"):
						draw_left = true
					else:
						var n_data = neighbors_data["left"]
						var n_voxels = n_data[0]
						var n_pal = n_data[1]
						var n_idx = (y * stride_y) + (z * stride_z) + (chunk_size - 1)
						var n_local = n_voxels[n_idx]
						if n_local == 0: draw_left = true
						else:
							var n_global = n_pal[n_local] if n_local < n_pal.size() else 0
							if n_global == 0: draw_left = true
				if draw_left:
					add_face(st, pos, "left", block)
					has_faces = true

				# --- Right Face (x+1) ---
				var draw_right = false
				if x < chunk_size - 1:
					if voxel_data[index + 1] == 0: draw_right = true
				else:
					if not neighbors_data.has("right"):
						draw_right = true
					else:
						var n_data = neighbors_data["right"]
						var n_voxels = n_data[0]
						var n_pal = n_data[1]
						var n_idx = (y * stride_y) + (z * stride_z) + 0
						var n_local = n_voxels[n_idx]
						if n_local == 0: draw_right = true
						else:
							var n_global = n_pal[n_local] if n_local < n_pal.size() else 0
							if n_global == 0: draw_right = true
				if draw_right:
					add_face(st, pos, "right", block)
					has_faces = true

			# End of row: flush any active runs
			if run_top.active:
				add_face(st, Vector3(run_top.start_x, y, z) * voxel_size, "top", run_top.block, chunk_size - run_top.start_x, 1.0)
				has_faces = true
			if run_bottom.active:
				add_face(st, Vector3(run_bottom.start_x, y, z) * voxel_size, "bottom", run_bottom.block, chunk_size - run_bottom.start_x, 1.0)
				has_faces = true
			if run_front.active:
				add_face(st, Vector3(run_front.start_x, y, z) * voxel_size, "front", run_front.block, chunk_size - run_front.start_x, 1.0)
				has_faces = true
			if run_back.active:
				add_face(st, Vector3(run_back.start_x, y, z) * voxel_size, "back", run_back.block, chunk_size - run_back.start_x, 1.0)
				has_faces = true

	var mesh_arrays = []
	if has_faces:
		# st.generate_normals() # 不需要，我们在 add_face 中手动设置了法线
		# st.generate_tangents() # 暂时不需要切线，除非你有法线贴图需求
		# commit_to_arrays returns the ArrayMesh data array (vertices, normals, etc)
		# This is a pure data object, safe to pass back.
		mesh_arrays = st.commit_to_arrays()
	
	# Dispatch back to main thread
	call_deferred("_apply_mesh_update", section_idx, mesh_arrays)


# --- Main Thread Function ---
# 支持批量mesh写回：section_idx可为int或Array，mesh_arrays可为Array或Array<Array>
func _apply_mesh_update(section_idx, mesh_arrays) -> void:
	# 优化：所有Section网格合并为地表和水体两个MeshInstance
	if typeof(section_idx) == TYPE_ARRAY and typeof(mesh_arrays) == TYPE_ARRAY:
		# mesh_arrays[0]为地表，mesh_arrays[1]为水体
		for i in range(2):
			var arr = mesh_arrays[i] if i < mesh_arrays.size() else []
			var m_inst = sections[i]
			if section_bodies[i]:
				section_bodies[i].queue_free()
				section_bodies[i] = null
			if arr.size() > 0:
				var arr_mesh = ArrayMesh.new()
				arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				m_inst.mesh = arr_mesh
				
				# 尝试生成碰撞体（基于距离）
				_try_create_collision(i)
			else:
				m_inst.mesh = null
		return
	# 单个section写回（兼容旧逻辑，写入地表MeshInstance）
	if section_idx < 0 or section_idx >= 2:
		MyLogger.error("[Chunk] _apply_mesh_update: section_idx %d 越界, sections.size()=%d" % [section_idx, sections.size()])
		return
	var mesh_inst = sections[section_idx]
	if section_bodies[section_idx]:
		section_bodies[section_idx].queue_free()
		section_bodies[section_idx] = null
	if mesh_arrays.size() > 0:
		var arr_mesh = ArrayMesh.new()
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays)
		mesh_inst.mesh = arr_mesh
		
		# 尝试生成碰撞体（基于距离）
		_try_create_collision(section_idx)
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
支持贪婪网格：u_scale 和 v_scale 用于控制纹理平铺次数
"""
func add_face(st: SurfaceTool, pos: Vector3, face: String, block: BlockData, u_scale: float = 1.0, v_scale: float = 1.0) -> void:
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
	
	# 计算 UV 坐标，应用 Tiling (u_scale, v_scale)
	# 注意：这里假设纹理是重复模式。如果纹理图集不支持重复（Clamp），这会导致拉伸。
	# 通常体素纹理图集需要特殊的 Shader 或 独立的纹理来实现 Tiling，
	# 或者我们仅仅拉伸 UV，但因为是图集，UV 超出范围会采样到其他纹理。
	# 修正：由于是图集（Atlas），我们不能简单地让 UV > 1。
	# 如果要实现 Tiling，我们需要在 Shader 中处理，或者接受“拉伸”的效果（对于纯色方块没问题）。
	# 但对于有纹理的方块（如砖块），简单的 UV 缩放会导致采样到邻居纹理。
	# 
	# 临时方案：为了性能，我们暂时只对 UV 进行简单的重复映射。
	# 但因为是 Atlas，我们必须小心。
	# 如果 u_scale > 1，我们需要生成多个顶点吗？不，那样就失去减少图元的意义了。
	# 正确的做法是：使用自定义 Shader 支持 Atlas Tiling，或者接受 UV 只是映射到单个 Block 的 UV 区域（即纹理被拉伸）。
	# 
	# 鉴于目前是优化阶段，且很多方块（草、土、石）纹理相对简单，
	# 我们先保持 UV 映射到单个 Block 的区域（即纹理会被拉伸铺满整个长条）。
	# 这是一个权衡。如果想要完美的 Tiling 且减少图元，需要 Shader 支持。
	# 
	# 更新：为了视觉效果，我们暂时不缩放 UV (即纹理会被拉伸)。
	# 等后续有 Shader 支持后再开启 UV Tiling。
	# 
	# 再次更新：如果不缩放 UV，长条方块的纹理会被拉得很长，很难看。
	# 我们可以尝试简单的重复 UV，但仅限于整数倍，且需要 Shader 配合。
	# 现在的实现：保持原样，纹理会被拉伸。
	
	var uv_bl = Vector2(uv_rect.position.x, uv_rect.position.y + uv_rect.size.y)
	var uv_br = Vector2(uv_rect.position.x + uv_rect.size.x, uv_rect.position.y + uv_rect.size.y)
	var uv_tr = Vector2(uv_rect.position.x + uv_rect.size.x, uv_rect.position.y)
	var uv_tl = Vector2(uv_rect.position.x, uv_rect.position.y)
	
	# 实际的物理尺寸
	var size_x = s * u_scale
	var size_z = s * v_scale
	# 对于侧面，v_scale 通常对应 Y 轴高度，u_scale 对应水平宽度
	
	# Vertices based on our corrected TestWorld logic (CW winding)
	var v_bl: Vector3
	var v_br: Vector3
	var v_tr: Vector3
	var v_tl: Vector3
	var normal: Vector3
	
	match face:
		"front": # -Z direction
			# u=X, v=Y
			size_x = s * u_scale
			var size_y = s * v_scale
			normal = Vector3(0, 0, -1)
			v_bl = pos + Vector3(size_x, 0, 0)
			v_br = pos + Vector3(0, 0, 0)
			v_tr = pos + Vector3(0, size_y, 0)
			v_tl = pos + Vector3(size_x, size_y, 0)
		"back": # +Z direction
			# u=X, v=Y
			size_x = s * u_scale
			var size_y = s * v_scale
			normal = Vector3(0, 0, 1)
			v_bl = pos + Vector3(0, 0, s) # Z is fixed at +s (relative to pos start, but pos is block start)
			# Wait, pos is the starting block position.
			# For a merged block of width u_scale (along X), the Z face is at Z+s.
			v_br = pos + Vector3(size_x, 0, s)
			v_tr = pos + Vector3(size_x, size_y, s)
			v_tl = pos + Vector3(0, size_y, s)
		"top": # +Y direction
			# u=X, v=Z
			size_x = s * u_scale
			size_z = s * v_scale
			normal = Vector3(0, 1, 0)
			v_bl = pos + Vector3(0, s, size_z)
			v_br = pos + Vector3(size_x, s, size_z)
			v_tr = pos + Vector3(size_x, s, 0)
			v_tl = pos + Vector3(0, s, 0)
		"bottom": # -Y direction
			# u=X, v=Z
			size_x = s * u_scale
			size_z = s * v_scale
			normal = Vector3(0, -1, 0)
			v_bl = pos + Vector3(0, 0, 0)
			v_br = pos + Vector3(size_x, 0, 0)
			v_tr = pos + Vector3(size_x, 0, size_z)
			v_tl = pos + Vector3(0, 0, size_z)
		"left": # -X direction
			# u=Z, v=Y
			size_z = s * u_scale # u_scale here means depth along Z
			var size_y = s * v_scale
			normal = Vector3(-1, 0, 0)
			v_bl = pos + Vector3(0, 0, 0)
			v_br = pos + Vector3(0, 0, size_z)
			v_tr = pos + Vector3(0, size_y, size_z)
			v_tl = pos + Vector3(0, size_y, 0)
		"right": # +X direction
			# u=Z, v=Y
			size_z = s * u_scale # u_scale here means depth along Z
			var size_y = s * v_scale
			normal = Vector3(1, 0, 0)
			v_bl = pos + Vector3(size_x, 0, size_z) # size_x is just s here (1 unit thick)
			v_br = pos + Vector3(size_x, 0, 0)
			v_tr = pos + Vector3(size_x, size_y, 0)
			v_tl = pos + Vector3(size_x, size_y, size_z)
			# Note: For right face, pos.x should be shifted by the block width if we were merging along X, 
			# but we don't merge Left/Right faces along X. We merge them along Z or Y.
			# In this implementation, we only merge Top/Bottom/Front/Back along X.
			# So Left/Right will always have u_scale=1, v_scale=1.

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


func unload_chunk() -> void:
	# 释放所有Section Mesh和物理体
	for mesh in sections:
		if mesh and mesh.is_inside_tree():
			mesh.queue_free()
	sections.clear()
	for body in section_bodies:
		if body and body.is_inside_tree():
			body.queue_free()
	section_bodies.clear()
	# 释放Sections节点
	if sections_node and sections_node.is_inside_tree():
		sections_node.queue_free()
	# 释放ChunkArea和ChunkCollision
	var area = get_node_or_null("ChunkArea")
	if area and area.is_inside_tree():
		area.queue_free()
	var chunk_body = get_node_or_null("ChunkCollision")
	if chunk_body and chunk_body.is_inside_tree():
		chunk_body.queue_free()
	# 清理邻居引用
	neighbor_front = null
	neighbor_back = null
	neighbor_left = null
	neighbor_right = null
	# 清理体素数据和Palette
	voxels = PackedByteArray()
	palette = null
	# 清理Section状态
	_generated_sections = PackedByteArray()
	_dirty_sections = PackedInt32Array()

# 尝试为指定Section生成碰撞体（基于距离剔除）
func _try_create_collision(section_index: int) -> void:
	var mesh_inst = sections[section_index]
	if not mesh_inst or not mesh_inst.mesh: return
	
	# 如果已经有碰撞体，不需要重新生成（除非强制更新，这里假设调用此函数时是新的Mesh）
	if section_bodies[section_index]:
		return

	var parent = get_parent()
	if parent:
		var player_chunk = Vector2i(0, 0)
		var has_player_info = false
		
		# 尝试获取玩家位置信息
		if parent.get("_current_player_chunk") != null:
			player_chunk = parent._current_player_chunk
			has_player_info = true
		
		# 如果获取到了玩家位置，且距离较远，则跳过生成
		if has_player_info:
			var dist = max(abs(chunk_position.x - player_chunk.x), abs(chunk_position.y - player_chunk.y))
			if dist > 2: # 仅为玩家周围 5x5 范围内的区块生成精确碰撞体
				return

	# 生成碰撞体
	mesh_inst.create_trimesh_collision()
	if mesh_inst.get_child_count() > 0:
		var child = mesh_inst.get_child(mesh_inst.get_child_count() - 1)
		if child is StaticBody3D:
			section_bodies[section_index] = child

# 公开方法：强制更新碰撞体（用于玩家移动时动态加载碰撞）
func update_collision(player_chunk_pos: Vector2i) -> void:
	var dist = max(abs(chunk_position.x - player_chunk_pos.x), abs(chunk_position.y - player_chunk_pos.y))
	if dist <= 2:
		for i in range(sections.size()):
			if sections[i].mesh and not section_bodies[i]:
				_try_create_collision(i)
	else:
		# 如果远离了，可以考虑销毁碰撞体以释放内存（可选）
		for i in range(section_bodies.size()):
			if section_bodies[i]:
				section_bodies[i].queue_free()
				section_bodies[i] = null
