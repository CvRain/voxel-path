extends Node3D

func _ready() -> void:
	_initialize_systems()

func _initialize_systems() -> void:
	print("Initializing systems for TestWorld...")
	
	var texture_manager = TextureManager.new()
	add_child(texture_manager)
	
	var block_registry = BlockRegistry.new()
	add_child(block_registry)
	
	BlockManager.loading_complete.connect(_on_loading_complete)

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
	
	# We define indices to match the UV mapping order:
	# Triangle 1: Bottom-Left, Top-Right, Bottom-Right (CW)
	# Triangle 2: Bottom-Left, Top-Left, Top-Right (CW)
	# We are flipping to CW because the previous CCW appeared inverted/culled.
	
	var faces = [
		# Front Face (+Z direction)
		# Normal (0,0,1). Looking from +Z towards -Z.
		# BL: 4, BR: 5, TR: 6, TL: 7
		{"name": "front", "indices": [4, 6, 5, 4, 7, 6], "normal": Vector3(0, 0, 1)},
		
		# Back Face (-Z direction)
		# Normal (0,0,-1). Looking from -Z towards +Z.
		# BL: 1 (size,0,0), BR: 0 (0,0,0), TR: 3 (0,size,0), TL: 2 (size,size,0)
		{"name": "back", "indices": [1, 3, 0, 1, 2, 3], "normal": Vector3(0, 0, -1)},
		
		# Top Face (+Y direction)
		# Normal (0,1,0). Looking from +Y down.
		# BL: 7 (0,size,size), BR: 6 (size,size,size), TR: 2 (size,size,0), TL: 3 (0,size,0)
		{"name": "top", "indices": [7, 2, 6, 7, 3, 2], "normal": Vector3(0, 1, 0)},
		
		# Bottom Face (-Y direction)
		# Normal (0,-1,0). Looking from -Y up.
		# BL: 0 (0,0,0), BR: 1 (size,0,0), TR: 5 (size,0,size), TL: 4 (0,0,size)
		{"name": "bottom", "indices": [0, 5, 1, 0, 4, 5], "normal": Vector3(0, -1, 0)},
		
		# Left Face (-X direction)
		# Normal (-1,0,0). Looking from -X towards +X.
		# BL: 0 (0,0,0), BR: 4 (0,0,size), TR: 7 (0,size,size), TL: 3 (0,size,0)
		{"name": "left", "indices": [0, 7, 4, 0, 3, 7], "normal": Vector3(-1, 0, 0)},
		
		# Right Face (+X direction)
		# Normal (1,0,0). Looking from +X towards -X.
		# BL: 5 (size,0,size), BR: 1 (size,0,0), TR: 2 (size,size,0), TL: 6 (size,size,size)
		{"name": "right", "indices": [5, 2, 1, 5, 6, 2], "normal": Vector3(1, 0, 0)}
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
		
		# Triangle 1: 0, 1, 2 (BL, TR, BR) - CW
		st.set_normal(normal)
		st.set_uv(uv_bl)
		st.add_vertex(vertices[indices[0]])
		
		st.set_normal(normal)
		st.set_uv(uv_tr)
		st.add_vertex(vertices[indices[1]])
		
		st.set_normal(normal)
		st.set_uv(uv_br)
		st.add_vertex(vertices[indices[2]])
		
		# Triangle 2: 0, 2, 3 (BL, TL, TR) - CW
		st.set_normal(normal)
		st.set_uv(uv_bl)
		st.add_vertex(vertices[indices[3]])
		
		st.set_normal(normal)
		st.set_uv(uv_tl)
		st.add_vertex(vertices[indices[4]])
		
		st.set_normal(normal)
		st.set_uv(uv_tr)
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
	
	# Add collision if block has collision
	if block.has_collision:
		mesh_instance.create_trimesh_collision()
	
	# Add label
	var label = Label3D.new()
	label.text = block.display_name
	label.position = pos + Vector3(0.25, 0.8, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 24
	add_child(label)
