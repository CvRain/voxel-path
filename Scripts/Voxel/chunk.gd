class_name Chunk
extends Node3D

var chunk_position: Vector2i
var voxels: PackedByteArray # Stores block IDs. 0 is air.
var is_modified: bool = false

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

func _init(pos: Vector2i) -> void:
	chunk_position = pos
	name = "Chunk_%d_%d" % [pos.x, pos.y]
	
	# Initialize voxel data
	# Size = Width * Width * Height
	var size = Constants.CHUNK_SIZE * Constants.CHUNK_SIZE * Constants.VOXEL_MAX_HEIGHT
	voxels = PackedByteArray()
	voxels.resize(size)
	voxels.fill(Constants.AIR_BLOCK_ID)

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

func set_voxel(x: int, y: int, z: int, block_id: int) -> void:
	if not is_valid_position(x, y, z):
		return
	
	var index = get_voxel_index(x, y, z)
	if voxels[index] != block_id:
		voxels[index] = block_id
		is_modified = true
		
		# Update the specific section
		update_mesh_for_voxel(y)

# Raw setter that DOES NOT trigger mesh updates.
# Use this for world generation or batch updates.
func set_voxel_raw(x: int, y: int, z: int, block_id: int) -> void:
	if not is_valid_position(x, y, z):
		return
	
	var index = get_voxel_index(x, y, z)
	if voxels[index] != block_id:
		voxels[index] = block_id
		is_modified = true

func update_mesh_for_voxel(y: int) -> void:
	var section_idx = int(y / Constants.CHUNK_SECTION_SIZE)
	schedule_section_update(section_idx)
	
	# Check if we need to update neighbors (if on boundary)
	var local_y = y % Constants.CHUNK_SECTION_SIZE
	if local_y == 0 and section_idx > 0:
		schedule_section_update(section_idx - 1)
	elif local_y == Constants.CHUNK_SECTION_SIZE - 1 and section_idx < sections.size() - 1:
		schedule_section_update(section_idx + 1)

func schedule_section_update(section_idx: int) -> void:
	# For single updates, we still need a snapshot to be thread-safe
	var voxel_snapshot = voxels.duplicate()
	_schedule_section_update_internal(section_idx, voxel_snapshot)

func _schedule_section_update_internal(section_idx: int, voxel_snapshot: PackedByteArray) -> void:
	WorkerThreadPool.add_task(
		_thread_generate_mesh.bind(section_idx, voxel_snapshot),
		true,
		"Mesh Gen Section %d" % section_idx
	)

func update_specific_sections(section_indices: Array) -> void:
	if section_indices.is_empty():
		return
		
	# Create ONE snapshot for this batch
	var shared_snapshot = voxels.duplicate()
	
	for section_idx in section_indices:
		if section_idx >= 0 and section_idx < sections.size():
			_schedule_section_update_internal(section_idx, shared_snapshot)

func generate_mesh() -> void:
	# OPTIMIZATION: Create ONE snapshot for all sections
	# This prevents 16x memory usage explosion (16 sections * 4MB = 64MB per chunk!)
	var shared_snapshot = voxels.duplicate()
	
	# Generate all sections using the shared snapshot
	for i in range(sections.size()):
		_schedule_section_update_internal(i, shared_snapshot)

# --- Threaded Function ---
# This runs on a background thread. CANNOT touch SceneTree nodes.
func _thread_generate_mesh(section_idx: int, voxel_data: PackedByteArray) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var voxel_size = Constants.VOXEL_SIZE
	var start_y = section_idx * Constants.CHUNK_SECTION_SIZE
	var end_y = min((section_idx + 1) * Constants.CHUNK_SECTION_SIZE, Constants.VOXEL_MAX_HEIGHT)
	
	var has_faces = false
	
	# Pre-calculate bounds to avoid repeated lookups
	var chunk_size = Constants.CHUNK_SIZE
	
	for y in range(start_y, end_y):
		for z in range(chunk_size):
			for x in range(chunk_size):
				# Use local snapshot data
				var index = (y * chunk_size * chunk_size) + (z * chunk_size) + x
				var block_id = voxel_data[index]
				
				if block_id == Constants.AIR_BLOCK_ID:
					continue
				
				# BlockRegistry is static, safe to read if not modifying
				var block = BlockRegistry.get_block(block_id)
				if not block: continue
				
				var pos = Vector3(x, y, z) * voxel_size
				
				# Check neighbors for culling
				# We pass the snapshot to the visibility check
				if _thread_is_face_visible(x, y + 1, z, voxel_data):
					add_face(st, pos, "top", block)
					has_faces = true
				
				if _thread_is_face_visible(x, y - 1, z, voxel_data):
					add_face(st, pos, "bottom", block)
					has_faces = true
				
				if _thread_is_face_visible(x + 1, y, z, voxel_data):
					add_face(st, pos, "right", block)
					has_faces = true
				
				if _thread_is_face_visible(x - 1, y, z, voxel_data):
					add_face(st, pos, "left", block)
					has_faces = true
				
				if _thread_is_face_visible(x, y, z + 1, voxel_data):
					add_face(st, pos, "back", block)
					has_faces = true
				
				if _thread_is_face_visible(x, y, z - 1, voxel_data):
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

# Thread-safe visibility check
func _thread_is_face_visible(x: int, y: int, z: int, local_voxels: PackedByteArray) -> bool:
	# If y is out of bounds (top/bottom of world), face is visible
	if y < 0 or y >= Constants.VOXEL_MAX_HEIGHT:
		return true
	
	# Check local bounds first
	if x >= 0 and x < Constants.CHUNK_SIZE and \
	   z >= 0 and z < Constants.CHUNK_SIZE:
		var index = (y * Constants.CHUNK_SIZE * Constants.CHUNK_SIZE) + (z * Constants.CHUNK_SIZE) + x
		var neighbor_id = local_voxels[index]
		return neighbor_id == Constants.AIR_BLOCK_ID
	
	# Neighbor chunks logic (Cross-chunk culling)
	# SAFETY FIX: Accessing neighbor chunks from a thread is NOT safe because PackedByteArray is not thread-safe.
	# For now, we assume chunk boundaries are always visible (no culling between chunks).
	# This prevents the "Out of bounds" crash and race conditions.
	return true

func get_voxel(x: int, y: int, z: int) -> int:
	if not is_valid_position(x, y, z):
		return Constants.AIR_BLOCK_ID
	return voxels[get_voxel_index(x, y, z)]

func get_voxel_global(x: int, y: int, z: int) -> int:
	# Check if inside this chunk
	if is_valid_position(x, y, z):
		return voxels[get_voxel_index(x, y, z)]
	
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
	var texture_uv = block.get_texture_uv(face)
	if texture_uv:
		uv_rect = texture_uv.uv_rect
		
		# Temporary: Crop to top-left 2x2 pixels of the 16x16 texture
		# This reduces high-frequency noise on small blocks (0.25m).
		# TODO: Make this configurable per block/texture in the future.
		var crop_ratio = 8.0 / 16.0
		uv_rect.size *= crop_ratio
	
	# Determine color (Biome tinting)
	# todo: 这是需要优化的写法
	var color = Color.WHITE
	if block.name == "grass":
		if face != "bottom":
			# Basic green tint for grass
			color = Color(0.4, 0.85, 0.4)
	
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
