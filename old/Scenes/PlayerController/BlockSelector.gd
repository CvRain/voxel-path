extends Node3D

@export var camera_path: NodePath = NodePath("../Head/Camera3D") # Adjust based on your hierarchy
@export var max_distance: float = 8.0
@export var collision_mask: int = 1

const VOXEL_SIZE: float = 0.25
const EPS: float = 0.001

var brush_size: int = 1

var _cam: Camera3D
var _outline: MeshInstance3D
var _last_voxel_idx: Vector3i = Vector3i(2147483647, 2147483647, 2147483647) # Invalid init

func set_brush_size(size: int) -> void:
	brush_size = size
	# Force update next frame
	_last_voxel_idx = Vector3i(2147483647, 2147483647, 2147483647)

func _ready() -> void:
	# 1. Find Camera
	if has_node(camera_path):
		_cam = get_node(camera_path)
	else:
		# Fallback: try to find any camera in parent or viewport
		_cam = get_viewport().get_camera_3d()
		if not _cam and get_parent() is Node3D:
			# Try to find a camera sibling or child of parent
			var parent = get_parent()
			for child in parent.get_children():
				if child is Camera3D:
					_cam = child
					break
				if child.name == "Head": # Common FPS structure
					for grand_child in child.get_children():
						if grand_child is Camera3D:
							_cam = grand_child
							break
	
	if not _cam:
		push_warning("BlockSelector: No camera found!")
		set_process(false)
		return

	# 2. Create Outline Mesh (Wireframe)
	_create_outline_mesh()

func _create_outline_mesh() -> void:
	_outline = MeshInstance3D.new()
	_outline.name = "SelectionOutline"
	add_child(_outline)
	
	# Ensure it's independent of parent transforms for easier global positioning
	_outline.top_level = true
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# Create a 1x1x1 wireframe cube (centered at 0,0,0 or 0.5,0.5,0.5?)
	# Let's create it from -0.5 to 0.5 so origin is center.
	var mesh = ArrayMesh.new()
	var vertices = PackedVector3Array()
	var h = 0.5 # Half size for 1.0 unit cube
	
	var v = [
		Vector3(-h, -h, -h), Vector3(h, -h, -h), Vector3(h, h, -h), Vector3(-h, h, -h),
		Vector3(-h, -h, h), Vector3(h, -h, h), Vector3(h, h, h), Vector3(-h, h, h)
	]
	
	var lines = [
		v[0], v[1], v[1], v[2], v[2], v[3], v[3], v[0], # Front
		v[4], v[5], v[5], v[6], v[6], v[7], v[7], v[4], # Back
		v[0], v[4], v[1], v[5], v[2], v[6], v[3], v[7] # Sides
	]
	
	vertices.append_array(lines)
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	
	_outline.mesh = mesh
	
	# Material
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0) # Black outline or White?
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	mat.vertex_color_use_as_albedo = false
	_outline.material_override = mat
	
	_outline.visible = false

func _process(_delta: float) -> void:
	if not _cam: return
	
	# Raycast from camera center
	var from = _cam.global_position
	var dir = - _cam.global_transform.basis.z
	var to = from + dir * max_distance
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to, collision_mask)
	# Exclude player if needed (assuming this script is on player or child)
	# query.exclude = [self, get_parent()] 
	
	var result = space_state.intersect_ray(query)
	
	if not result:
		_outline.visible = false
		_last_voxel_idx = Vector3i(2147483647, 2147483647, 2147483647)
		return
	
	var hit_pos = result.position
	var hit_normal = result.normal
	
	# Move slightly into the block to get the correct voxel
	var inside_pos = hit_pos - (hit_normal * EPS)
	
	var voxel_idx = world_to_voxel_index(inside_pos, VOXEL_SIZE)
	
	# Update visibility and position
	_outline.visible = true
	
	# Calculate center of the brush selection
	# 1. Determine the "origin" voxel (bottom-left-back) based on brush size
	# Logic must match ProtoController's offset logic: offset = -floori(size / 2.0)
	var offset = - floori(brush_size / 2.0)
	var origin_voxel = voxel_idx + Vector3i(offset, offset, offset)
	
	# 2. Calculate world position of that origin voxel's corner (min corner)
	var origin_world = Vector3(origin_voxel) * VOXEL_SIZE
	
	# 3. Calculate center of the total brush volume
	# Volume size = brush_size * VOXEL_SIZE
	var total_size = float(brush_size) * VOXEL_SIZE
	var center_pos = origin_world + (Vector3.ONE * total_size * 0.5)
	
	_outline.global_position = center_pos
	
	# Scale to match total brush size
	# Add a tiny bit of scale to prevent z-fighting
	_outline.scale = Vector3.ONE * total_size * 1.01

static func world_to_voxel_index(pos: Vector3, size: float) -> Vector3i:
	return Vector3i(
		floori(pos.x / size),
		floori(pos.y / size),
		floori(pos.z / size)
	)

static func voxel_index_to_world_center(idx: Vector3i, size: float) -> Vector3:
	return Vector3(
		(float(idx.x) + 0.5) * size,
		(float(idx.y) + 0.5) * size,
		(float(idx.z) + 0.5) * size
	)
