# Scripts/Voxel/block_data.gd
class_name BlockData
extends Resource

@export var id: int
@export var name: String
@export var display_name: String
@export var category: String = "unknown"
@export var description: String = ""

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

func _init() -> void:
	resource_path = ""

func get_texture_uv(face: String, texture_type: String = "diffuse") -> TextureUV:
	var key = "%s_%s" % [face, texture_type]
	if key in textures:
		return textures[key]
	return textures.get(texture_type, null)

func get_variant(variant_name: String) -> BlockData:
	return variants.get(variant_name, self)

func validate() -> bool:
	if id <= 0 or name.is_empty():
		return false
	if textures.is_empty():
		return false
	return true

func _to_string() -> String:
	return "BlockData(id=%d, name='%s', display='%s')" % [id, name, display_name]
