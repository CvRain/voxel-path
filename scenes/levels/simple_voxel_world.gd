extends Node3D

## 简单的体素世界设置脚本
## 用于在 level_playground 场景中快速生成一个基础的方块世界

@export var world_size: int = 64
@export var world_height: int = 32

var terrain: VoxelTerrain
var library: VoxelBlockyLibrary
var mesher: VoxelMesherBlocky
var generator: VoxelGeneratorFlat

func _ready():
	print("=== SimpleVoxelWorld Initializing ===")
	
	setup_voxel_library()
	setup_voxel_mesher()
	setup_voxel_generator()
	setup_voxel_terrain()
	
	print("=== SimpleVoxelWorld Ready ===")

## 创建方块库 - 目前只有石头
func setup_voxel_library():
	library = VoxelBlockyLibrary.new()
	
	# ID 0 是空气（自动保留）
	
	# ID 1 - 石头方块
	var stone_model = VoxelBlockyModelCube.new()
	stone_model.set_material_override(0, create_stone_material())
	
	library.add_model(stone_model)
	
	print("[VoxelLibrary] Created with 1 block (Stone)")

## 创建石头材质
func create_stone_material() -> Material:
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.5, 0.5) # 灰色
	
	# 如果有纹理，可以加载
	var texture_path = "res://Assets/Textures/Natural/stone.png"
	if ResourceLoader.exists(texture_path):
		var texture = load(texture_path) as Texture2D
		material.albedo_texture = texture
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST # 像素风格
		print("[Material] Loaded stone texture")
	else:
		print("[Material] Using solid gray color (texture not found)")
	
	return material

## 设置方块网格生成器
func setup_voxel_mesher():
	mesher = VoxelMesherBlocky.new()
	mesher.library = library
	
	print("[VoxelMesher] Blocky mesher configured")

## 设置世界生成器 - 简单的平坦世界
func setup_voxel_generator():
	generator = VoxelGeneratorFlat.new()
	generator.channel = VoxelBuffer.CHANNEL_TYPE
	generator.voxel_type = 1 # 石头的 ID
	generator.height = 10.0 # 10 格高的石头层
	
	print("[VoxelGenerator] Flat generator: height=10, type=Stone")

## 设置并添加 VoxelTerrain 节点
func setup_voxel_terrain():
	terrain = VoxelTerrain.new()
	
	# 基本设置
	terrain.mesher = mesher
	terrain.generator = generator
	
	# 视距设置
	terrain.view_distance = 128 # 可视距离
	terrain.max_view_distance = 256
	
	# 添加到场景树
	add_child(terrain)
	terrain.name = "VoxelTerrain"
	terrain.owner = get_tree().edited_scene_root if get_tree().edited_scene_root else self
	
	print("[VoxelTerrain] Created - ViewDistance: ", terrain.view_distance)
	print("=== World generation started ===")

## 获取指定位置的方块 ID
func get_voxel(position: Vector3i) -> int:
	if not terrain:
		return 0
	
	var tool = terrain.get_voxel_tool()
	return tool.get_voxel(position)

## 设置指定位置的方块
func set_voxel(position: Vector3i, voxel_id: int):
	if not terrain:
		return
	
	var tool = terrain.get_voxel_tool()
	tool.set_voxel(position, voxel_id)

## 射线检测 - 用于方块选择
func raycast(origin: Vector3, direction: Vector3, max_distance: float):
	if not terrain:
		return null
	
	var tool = terrain.get_voxel_tool()
	return tool.raycast(origin, direction, max_distance)
