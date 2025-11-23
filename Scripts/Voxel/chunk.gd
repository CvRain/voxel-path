# Scripts/Voxel/chunk.gd
class_name Chunk
extends Node3D

var chunk_position: Vector2i
var voxels: PackedByteArray # Stores block IDs. 0 is air.
var is_modified: bool = false
var mesh_instance: MeshInstance3D
var collision_body: StaticBody3D
var max_height: int = 0 # Track max height for optimization

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
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	
	# Set material
	var material = StandardMaterial3D.new()
	material.albedo_texture = TextureManager.get_main_atlas()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.vertex_color_use_as_albedo = true # Enabled for biome tinting
	mesh_instance.material_override = material

func set_voxel(x: int, y: int, z: int, block_id: int) -> void:
	if not is_valid_position(x, y, z):
		return
	
	var index = get_voxel_index(x, y, z)
	if voxels[index] != block_id:
		voxels[index] = block_id
		is_modified = true
		if block_id != Constants.AIR_BLOCK_ID and y > max_height:
			max_height = y

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

func generate_mesh() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var voxel_size = Constants.VOXEL_SIZE
	
	# Optimization: Only loop up to max_height + 1 (to check top faces)
	var loop_height = min(max_height + 2, Constants.VOXEL_MAX_HEIGHT)
	
	for y in range(loop_height):
		for z in range(Constants.CHUNK_SIZE):
			for x in range(Constants.CHUNK_SIZE):
				var block_id = get_voxel(x, y, z)
				if block_id == Constants.AIR_BLOCK_ID:
					continue
				
				var block = BlockRegistry.get_block(block_id)
				if not block: continue
				
				var pos = Vector3(x, y, z) * voxel_size
				
				# Check neighbors for culling
				# Top (+Y)
				if is_face_visible(x, y + 1, z):
					add_face(st, pos, "top", block)
				
				# Bottom (-Y)
				if is_face_visible(x, y - 1, z):
					add_face(st, pos, "bottom", block)
				
				# Right (+X)
				if is_face_visible(x + 1, y, z):
					add_face(st, pos, "right", block)
				
				# Left (-X)
				if is_face_visible(x - 1, y, z):
					add_face(st, pos, "left", block)
				
				# Back (+Z) - Note: In our corrected system, +Z is Back
				if is_face_visible(x, y, z + 1):
					add_face(st, pos, "back", block)
				
				# Front (-Z) - Note: In our corrected system, -Z is Front
				if is_face_visible(x, y, z - 1):
					add_face(st, pos, "front", block)

	st.generate_normals()
	st.generate_tangents()
	
	if mesh_instance.mesh:
		mesh_instance.mesh.clear_surfaces()
	
	mesh_instance.mesh = st.commit()
	
	# Update collision
	if collision_body:
		collision_body.queue_free()
	
	if mesh_instance.mesh.get_surface_count() > 0:
		mesh_instance.create_trimesh_collision()
		collision_body = mesh_instance.get_child(0)

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
