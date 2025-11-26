class_name Biome
extends Resource

@export var name: String = "Plains"

# Surface Blocks
@export var top_block_name: String = "grass"
@export var dirt_block_name: String = "dirt"
@export var stone_block_name: String = "stone"

# Vegetation
@export var tree_density: float = 0.01
@export var tree_type: String = "oak"

# Cached IDs (runtime)
var _top_block_id: int = -1
var _dirt_block_id: int = -1
var _stone_block_id: int = -1

func cache_ids() -> void:
	var top = BlockRegistry.get_block_by_name(top_block_name)
	var dirt = BlockRegistry.get_block_by_name(dirt_block_name)
	var stone = BlockRegistry.get_block_by_name(stone_block_name)
	
	if top: _top_block_id = top.id
	if dirt: _dirt_block_id = dirt.id
	if stone: _stone_block_id = stone.id

func get_top_block() -> int:
	return _top_block_id

func get_dirt_block() -> int:
	return _dirt_block_id

func get_stone_block() -> int:
	return _stone_block_id
