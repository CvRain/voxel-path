# Scripts/Voxel/advanced_biome.gd
# 高级生物群系类，支持更多参数和特性

class_name AdvancedBiome
extends Resource

@export var name: String = "Plains"

# 地表方块
@export var top_block_name: String = "grass"
@export var dirt_block_name: String = "dirt"
@export var stone_block_name: String = "stone"
@export var underwater_block_name: String = "sand"

# 植被参数
@export var tree_density: float = 0.01
@export var tree_types: Array[String] = ["oak"]
@export var flower_density: float = 0.0
@export var grass_density: float = 0.0

# 地形参数
@export var height_offset: int = 0
@export var height_scale: float = 1.0
@export var temperature: float = 0.5  # 0.0 = 冷, 1.0 = 热
@export var humidity: float = 0.5     # 0.0 = 干燥, 1.0 = 潮湿

# 洞穴参数
@export var cave_density: float = 0.05

# 缓存的ID (运行时)
var _top_block_id: int = -1
var _dirt_block_id: int = -1
var _stone_block_id: int = -1
var _underwater_block_id: int = -1

func cache_ids() -> void:
	var top = BlockRegistry.get_block_by_name(top_block_name)
	var dirt = BlockRegistry.get_block_by_name(dirt_block_name)
	var stone = BlockRegistry.get_block_by_name(stone_block_name)
	var underwater = BlockRegistry.get_block_by_name(underwater_block_name)
	
	if top: _top_block_id = top.id
	if dirt: _dirt_block_id = dirt.id
	if stone: _stone_block_id = stone.id
	if underwater: _underwater_block_id = underwater.id

func get_top_block() -> int:
	return _top_block_id

func get_dirt_block() -> int:
	return _dirt_block_id

func get_stone_block() -> int:
	return _stone_block_id

func get_underwater_block() -> int:
	return _underwater_block_id if _underwater_block_id != -1 else _dirt_block_id