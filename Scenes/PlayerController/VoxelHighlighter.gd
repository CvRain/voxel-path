class_name VoxelHighlighter
extends MultiMeshInstance3D

var color: Color = Color(1.0, 1.0, 1.0, 1.0) # White with glow
var border_thickness: float = 0.02 # 2cm thickness

func _ready() -> void:
	# Setup MultiMesh
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.instance_count = 0 # Will be resized dynamically
	multimesh.mesh = BoxMesh.new()
	multimesh.mesh.size = Vector3(Constants.VOXEL_SIZE, Constants.VOXEL_SIZE, Constants.VOXEL_SIZE)
	
	var shader = Shader.new()
	shader.code = """
	shader_type spatial;
	render_mode unshaded, cull_disabled, blend_add;

	uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
	uniform float border_width = 0.05;

	void fragment() {
		vec2 uv = UV;
		vec2 d = min(uv, 1.0 - uv);
		float min_d = min(d.x, d.y);
		
		if (min_d > border_width) {
			discard;
		}
		
		ALBEDO = color.rgb;
		ALPHA = color.a;
		EMISSION = color.rgb * 3.0; // Strong glow
	}
	"""
	
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("color", color)
	
	# Calculate border width relative to voxel size (0.25)
	# UV 0..1 covers 0.25m
	# We want 0.02m thickness
	# ratio = 0.02 / 0.25 = 0.08
	var uv_width = border_thickness / Constants.VOXEL_SIZE
	mat.set_shader_parameter("border_width", uv_width * 0.5) # Half width for threshold
	
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func update_voxels(origin: Vector3, voxel_offsets: Array[Vector3]) -> void:
	var count = voxel_offsets.size()
	if multimesh.instance_count != count:
		multimesh.instance_count = count
	
	var epsilon = 0.002
	var scale_vec = Vector3(1.0, 1.0, 1.0) * (1.0 + epsilon * 4.0) # Slightly larger than 1.0 to encompass voxel
	
	for i in range(count):
		var pos = origin + voxel_offsets[i] * Constants.VOXEL_SIZE
		var t = Transform3D()
		t.origin = pos
		t = t.scaled(scale_vec)
		multimesh.set_instance_transform(i, t)
