# Scripts/Voxel/block_data.gd
class_name BlockData
extends Resource

@export var id: int
@export var name: String
@export var display_name: String
@export var category: String = "unknown"
@export var description: String = ""

@export var texture_paths: Dictionary = {}
@export var textures: Dictionary = {}
@export var is_transparent: bool = false
@export var blend_mode: String = "opaque"

@export var hardness: float = 1.0
@export var resistance: float = 1.0
@export var is_solid: bool = true
@export var has_collision: bool = true

@export var can_place: bool = true
@export var can_break: bool = true
@export var tool_required: String = "none"
@export var mine_level: int = 0
@export var mine_time: float = 1.0

@export var custom_properties: Dictionary = {}
@export var variants: Dictionary = {}

# Block State Definitions
# Format: { "property_name": [value1, value2, ...] }
# Example: { "facing": ["north", "south", "east", "west"], "lit": [true, false] }
@export var state_definitions: Dictionary = {}
# Default state values
# Example: { "facing": "north", "lit": false }
@export var default_state: Dictionary = {}

# Texture Variation
@export var random_texture_frames: int = 1

func _init() -> void:
	resource_path = ""

func get_texture_uv(face: String, texture_type: String = "diffuse", frame: int = 0) -> TextureUV:
	var key = "%s_%s" % [face, texture_type]
	if frame > 0:
		key = "%s#%d" % [key, frame]
		
	if key in textures:
		return textures[key]
		
	# Fallback to default frame if specific frame not found
	if frame > 0:
		key = "%s_%s" % [face, texture_type]
		if key in textures:
			return textures[key]
			
	# Fallback to generic type (e.g. "diffuse")
	key = texture_type
	if frame > 0:
		key = "%s#%d" % [key, frame]
	
	if key in textures:
		return textures[key]
		
	return textures.get(texture_type, null)

func get_variant(variant_name: String) -> BlockData:
	return variants.get(variant_name, self)

func validate() -> bool:
	if name.is_empty():
		return false
	# textures will be empty initially, check texture_paths instead
	if texture_paths.is_empty() and textures.is_empty():
		return false
	return true

func _to_string() -> String:
	return "BlockData(id=%d, name='%s', display='%s')" % [id, name, display_name]
