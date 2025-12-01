class_name BlockState
extends RefCounted

var block_id: int
var state_id: int
var properties: Dictionary = {}

func _init(p_block_id: int, p_state_id: int, p_properties: Dictionary) -> void:
	block_id = p_block_id
	state_id = p_state_id
	properties = p_properties

func get_property(name: String, default_value = null):
	return properties.get(name, default_value)

func _to_string() -> String:
	return "BlockState(id=%d, block=%d, props=%s)" % [state_id, block_id, properties]
