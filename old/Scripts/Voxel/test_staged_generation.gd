# Scripts/Voxel/test_staged_generation.gd
# 测试分阶段地形生成系统的脚本

class_name TestStagedGeneration
extends Node

# 引入区块生成阶段枚举
const ChunkGenerationStage = preload("res://Scripts/Voxel/chunk_generation_stage.gd").ChunkGenerationStage

# 测试分阶段生成
static func test_staged_generation(chunk: Chunk, world_generator: Node) -> void:
	print("Testing staged chunk generation...")
	
	# 检查初始阶段
	assert(chunk.generation_stage == ChunkGenerationStage.NOT_GENERATED)
	print("Initial stage: NOT_GENERATED")
	
	# 生成基础地形
	world_generator.generate_chunk_stage(chunk, ChunkGenerationStage.BASE_TERRAIN)
	chunk.generation_stage = ChunkGenerationStage.BASE_TERRAIN
	print("Stage 1 complete: BASE_TERRAIN")
	
	# 生成水体和表层
	world_generator.generate_chunk_stage(chunk, ChunkGenerationStage.WATER_AND_SURFACE)
	chunk.generation_stage = ChunkGenerationStage.WATER_AND_SURFACE
	print("Stage 2 complete: WATER_AND_SURFACE")
	
	# 生成矿石和洞穴
	world_generator.generate_chunk_stage(chunk, ChunkGenerationStage.ORES_AND_CAVES)
	chunk.generation_stage = ChunkGenerationStage.ORES_AND_CAVES
	print("Stage 3 complete: ORES_AND_CAVES")
	
	# 生成装饰物
	world_generator.generate_chunk_stage(chunk, ChunkGenerationStage.DECORATIONS)
	chunk.generation_stage = ChunkGenerationStage.FULLY_GENERATED
	print("Stage 4 complete: DECORATIONS")
	
	# 生成网格
	chunk.generate_mesh()
	print("Mesh generation complete")
	
	print("All stages completed successfully!")
