# Scripts/Core/texture_uv.gd
class_name TextureUV
extends Resource

@export var atlas_name: String
@export var tile_index: int
@export var uv_rect: Rect2

func _init(p_atlas: String = "", p_tile: int = 0, p_rect: Rect2 = Rect2()) -> void:
	atlas_name = p_atlas
	tile_index = p_tile
	uv_rect = p_rect

func get_face_uv(face_index: int, rotation: int = 0) -> PackedVector2Array:
	var uv_corners = PackedVector2Array([
		uv_rect.position,
		Vector2(uv_rect.position.x + uv_rect.size.x, uv_rect.position.y),
		Vector2(uv_rect.position.x + uv_rect.size.x, uv_rect.position.y + uv_rect.size.y),
		Vector2(uv_rect.position.x, uv_rect.position.y + uv_rect.size.y)
	])
	
	var rotated = uv_corners.duplicate()
	for i in range(rotation):
		rotated = PackedVector2Array([rotated[3], rotated[0], rotated[1], rotated[2]])
	
	return rotated

func _to_string() -> String:
	return "TextureUV(atlas=%s, tile=%d, uv=%.2f,%.2f-%.2f,%.2f)" % [
		atlas_name, tile_index,
		uv_rect.position.x, uv_rect.position.y,
		uv_rect.size.x, uv_rect.size.y
	]
