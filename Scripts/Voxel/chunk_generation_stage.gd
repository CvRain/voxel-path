# Scripts/Voxel/chunk_generation_stage.gd
# 定义区块生成阶段的枚举

enum ChunkGenerationStage {
	NOT_GENERATED = 0,     # 未生成
	BASE_TERRAIN = 1,      # 基础地形（石头、基岩）
	WATER_AND_SURFACE = 2, # 水体和表层（泥土、草等）
	ORES_AND_CAVES = 3,    # 矿石和洞穴
	DECORATIONS = 4,       # 装饰物（树木、花草等）
	FULLY_GENERATED = 5    # 完全生成
}