extends Node3D

func _ready() -> void:
	_initialize_systems()

func _initialize_systems() -> void:
	print("Initializing systems for TestWorld...")
	
	var texture_manager = TextureManager.new()
	add_child(texture_manager)
	
	var block_registry = BlockRegistry.new()
	add_child(block_registry)
	
	var block_manager = BlockManager.new()
	block_manager.loading_complete.connect(_on_loading_complete)
	add_child(block_manager)

func _on_loading_complete() -> void:
	print("Generating test blocks...")
	_generate_test_blocks()

func _generate_test_blocks() -> void:
	var block_ids = BlockRegistry.get_all_block_ids()
	block_ids.sort()
	
	var x = 0
	var z = 0
	var spacing = 2.0
	var row_length = 5
	
	for id in block_ids:
		var block = BlockRegistry.get_block(id)
		if not block: continue
		
		_create_block_mesh(block, Vector3(x * spacing, 1, z * spacing))
		
		x += 1
		if x >= row_length:
			x = 0
			z += 1

func _create_block_mesh(block: BlockData, pos: Vector3) -> void:
	print("Creating mesh for block: %s at %s" % [block.name, pos])
	var mesh_instance = MeshInstance3D.new()
	var mesh = ArrayMesh.new()
	var st = SurfaceTool.new()
	
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Create a simple cube
	var size = 0.5 # Visual size for test
	var vertices = [
		Vector3(0, 0, 0), Vector3(size, 0, 0), Vector3(size, size, 0), Vector3(0, size, 0), # Front
		Vector3(0, 0, size), Vector3(size, 0, size), Vector3(size, size, size), Vector3(0, size, size), # Back
		Vector3(0, size, 0), Vector3(size, size, 0), Vector3(size, size, size), Vector3(0, size, size), # Top
		Vector3(0, 0, 0), Vector3(size, 0, 0), Vector3(size, 0, size), Vector3(0, 0, size), # Bottom
		Vector3(0, 0, 0), Vector3(0, size, 0), Vector3(0, size, size), Vector3(0, 0, size), # Left
		Vector3(size, 0, 0), Vector3(size, size, 0), Vector3(size, size, size), Vector3(size, 0, size) # Right
	]
	
	# Define faces and their UVs
	# Note: Godot uses Right-Handed coordinate system.
	# -Z is Forward (Front), +Z is Backward (Back)
	# +X is Right, -X is Left
	# +Y is Up, -Y is Down
	var faces = [
		# Front Face (+Z direction)
		# Vertices: 5, 4, 7, 6 (BR, BL, TL, TR)
		{"name": "front", "indices": [5, 7, 4, 5, 6, 7], "normal": Vector3(0, 0, 1)},
		
		# Back Face (-Z direction)
		# Vertices: 0, 1, 2, 3 (BL, BR, TR, TL)
		{"name": "back", "indices": [0, 2, 1, 0, 3, 2], "normal": Vector3(0, 0, -1)},
		
		# Top Face (+Y direction)
		# Vertices: 8, 9, 10, 11 (TL, TR, BR, BL)
		{"name": "top", "indices": [8, 9, 10, 8, 10, 11], "normal": Vector3(0, 1, 0)},
		
		# Bottom Face (-Y direction)
		{"name": "bottom", "indices": [12, 14, 13, 12, 15, 14], "normal": Vector3(0, -1, 0)},
		
		# Left Face (-X direction)
		# Vertices: 16, 18, 17, 16, 19, 18 (BL, TR, BR, BL, TL, TR)
		{"name": "left", "indices": [16, 18, 17, 16, 19, 18], "normal": Vector3(-1, 0, 0)},
		
		# Right Face (+X direction)
		# Vertices: 20, 21, 22, 23 (BL, BR, TR, TL)
		{"name": "right", "indices": [20, 21, 22, 20, 22, 23], "normal": Vector3(1, 0, 0)}
	]
	
	for face in faces:
		var uv_rect = Rect2(0, 0, 1, 1)
		var texture_uv = block.get_texture_uv(face.name)
		if texture_uv:
			uv_rect = texture_uv.uv_rect
		
		var indices = face.indices
		var normal = face.normal
		
		# UV Coordinates
		# (0,0) Top-Left, (1,1) Bottom-Right in Godot Texture Space
		# But we need to map them to vertices.
		# Standard Quad Mapping:
		# 0: Bottom-Left  -> UV(0, 1)
		# 1: Bottom-Right -> UV(1, 1)
		# 2: Top-Right    -> UV(1, 0)
		# 3: Top-Left     -> UV(0, 0)
		
		var uv_bl = Vector2(uv_rect.position.x, uv_rect.position.y + uv_rect.size.y)
		var uv_br = Vector2(uv_rect.position.x + uv_rect.size.x, uv_rect.position.y + uv_rect.size.y)
		var uv_tr = Vector2(uv_rect.position.x + uv_rect.size.x, uv_rect.position.y)
		var uv_tl = Vector2(uv_rect.position.x, uv_rect.position.y)
		
		# Triangle 1: 0, 1, 2 (BL, BR, TR) - CCW
		st.set_normal(normal)
		st.set_uv(uv_bl)
		st.add_vertex(vertices[indices[0]])
		
		st.set_normal(normal)
		st.set_uv(uv_br) # Was Top-Right in previous code, fixed to Bottom-Right
		st.add_vertex(vertices[indices[1]])
		
		st.set_normal(normal)
		st.set_uv(uv_tr) # Was Bottom-Right in previous code, fixed to Top-Right
		st.add_vertex(vertices[indices[2]])
		
		# Triangle 2: 0, 2, 3 (BL, TR, TL) - CCW
		st.set_normal(normal)
		st.set_uv(uv_bl)
		st.add_vertex(vertices[indices[3]])
		
		st.set_normal(normal)
		st.set_uv(uv_tr) # Was Top-Left in previous code, fixed to Top-Right
		st.add_vertex(vertices[indices[4]])
		
		st.set_normal(normal)
		st.set_uv(uv_tl) # Was Top-Right in previous code, fixed to Top-Left
		st.add_vertex(vertices[indices[5]])

	st.generate_normals()
	st.generate_tangents()
	mesh = st.commit()
	
	mesh_instance.mesh = mesh
	mesh_instance.position = pos
	
	# Create material
	var material = StandardMaterial3D.new()
	material.albedo_texture = TextureManager.get_main_atlas()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mesh_instance.material_override = material
	
	add_child(mesh_instance)
	
	# Add label
	var label = Label3D.new()
	label.text = block.display_name
	label.position = pos + Vector3(0.25, 0.8, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 24
	add_child(label)
