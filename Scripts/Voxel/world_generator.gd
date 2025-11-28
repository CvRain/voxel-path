class_name WorldGenerator
extends Node

# 引入区块生成阶段枚举
const ChunkGenerationStage = preload("res://Scripts/Voxel/chunk_generation_stage.gd").ChunkGenerationStage

var _seed: int
var _continental_noise: FastNoiseLite
var _erosion_noise: FastNoiseLite
var _temperature_noise: FastNoiseLite
var _humidity_noise: FastNoiseLite
var _biomes: Array = []

# Cached Block IDs
var _id_bedrock: int = 0
var _id_stone: int = 0
var _id_dirt: int = 0
var _id_grass: int = 0
var _id_water: int = 0
var _id_log: int = 0
var _id_leaves: int = 0
var _id_sand: int = 0

# Ore IDs
var _ore_ids: Dictionary = {}

# 添加噪声缓存以提高性能
var _height_cache: Dictionary = {}
var _biome_cache: Dictionary = {}

func _init(seed_val: int) -> void:
	_seed = seed_val
	_initialize_noise()
	_initialize_biomes()

func _initialize_noise() -> void:
	# 1. Continental Noise: Determines general elevation (Ocean vs Land vs Mountain base)
	_continental_noise = FastNoiseLite.new()
	_continental_noise.seed = _seed
	_continental_noise.frequency = 0.0008 # 调整频率以获得更好的地形连贯性
	_continental_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_continental_noise.fractal_octaves = 5 # 增加细节层次
	_continental_noise.fractal_gain = 0.5
	_continental_noise.fractal_weighted_strength = 0.0
	_continental_noise.fractal_lacunarity = 2.0
	
	# 2. Erosion Noise: Adds local detail/roughness
	_erosion_noise = FastNoiseLite.new()
	_erosion_noise.seed = _seed + 1
	_erosion_noise.frequency = 0.005 # 调整频率
	_erosion_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_erosion_noise.fractal_octaves = 4 # 减少一些细节以提高性能
	_erosion_noise.fractal_gain = 0.4
	_erosion_noise.fractal_weighted_strength = 0.0
	_erosion_noise.fractal_lacunarity = 2.3
	
	# 3. Temperature Noise: Large climate zones
	_temperature_noise = FastNoiseLite.new()
	_temperature_noise.seed = _seed + 2
	_temperature_noise.frequency = 0.0015 # 调整频率
	_temperature_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_temperature_noise.fractal_octaves = 3
	_temperature_noise.fractal_gain = 0.5
	_temperature_noise.fractal_lacunarity = 2.0
	
	# 4. Humidity Noise: Rainfall distribution
	_humidity_noise = FastNoiseLite.new()
	_humidity_noise.seed = _seed + 3
	_humidity_noise.frequency = 0.0015 # 调整频率
	_humidity_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_humidity_noise.fractal_octaves = 3
	_humidity_noise.fractal_gain = 0.5
	_humidity_noise.fractal_lacunarity = 2.0

func _initialize_biomes() -> void:
	var AdvancedBiomeScript = load("res://Scripts/Voxel/advanced_biome.gd")
	
	# 0: Ocean
	var ocean = AdvancedBiomeScript.new()
	ocean.name = "Ocean"
	ocean.top_block_name = "sand"
	ocean.dirt_block_name = "sand"
	ocean.underwater_block_name = "sand"
	ocean.tree_density = 0.0
	ocean.temperature = 0.5
	ocean.humidity = 0.8
	_biomes.append(ocean)
	
	# 1: Beach
	var beach = AdvancedBiomeScript.new()
	beach.name = "Beach"
	beach.top_block_name = "sand"
	beach.dirt_block_name = "sand"
	beach.underwater_block_name = "sand"
	beach.tree_density = 0.001
	beach.temperature = 0.6
	beach.humidity = 0.6
	_biomes.append(beach)
	
	# 2: Plains
	var plains = AdvancedBiomeScript.new()
	plains.name = "Plains"
	plains.top_block_name = "grass"
	plains.tree_density = 0.005
	plains.flower_density = 0.01
	plains.temperature = 0.6
	plains.humidity = 0.5
	_biomes.append(plains)
	
	# 3: Forest
	var forest = AdvancedBiomeScript.new()
	forest.name = "Forest"
	forest.top_block_name = "grass"
	forest.tree_density = 0.05
	forest.temperature = 0.5
	forest.humidity = 0.7
	_biomes.append(forest)
	
	# 4: Jungle
	var jungle = AdvancedBiomeScript.new()
	jungle.name = "Jungle"
	jungle.top_block_name = "grass"
	jungle.tree_density = 0.15
	jungle.temperature = 0.9
	jungle.humidity = 0.9
	_biomes.append(jungle)
	
	# 5: Desert
	var desert = AdvancedBiomeScript.new()
	desert.name = "Desert"
	desert.top_block_name = "sand"
	desert.dirt_block_name = "sand"
	desert.underwater_block_name = "sand"
	desert.tree_density = 0.002
	desert.temperature = 1.0
	desert.humidity = 0.1
	_biomes.append(desert)
	
	# 6: Snow
	var snow = AdvancedBiomeScript.new()
	snow.name = "Snow"
	snow.top_block_name = "snow" # 需要添加雪方块
	snow.tree_density = 0.02
	snow.temperature = 0.1
	snow.humidity = 0.4
	_biomes.append(snow)
	
	# 7: Mountains
	var mountains = AdvancedBiomeScript.new()
	mountains.name = "Mountains"
	mountains.top_block_name = "stone"
	mountains.dirt_block_name = "stone"
	mountains.tree_density = 0.01
	mountains.temperature = 0.4
	mountains.humidity = 0.4
	_biomes.append(mountains)

# 根据坐标获取生物群系
func _get_biome(world_x: int, world_z: int) -> Resource:
	var temp = _temperature_noise.get_noise_2d(world_x, world_z)
	var humidity = _humidity_noise.get_noise_2d(world_x, world_z)
	
	# 归一化到 0-1 范围
	temp = (temp + 1.0) / 2.0
	humidity = (humidity + 1.0) / 2.0
	
	# 根据温度和湿度选择生物群系
	if temp < 0.2: # 极冷
		return _biomes[6] # Snow
	elif temp < 0.4: # 冷
		if humidity < 0.3:
			return _biomes[7] # Mountains
		elif humidity < 0.7:
			return _biomes[2] # Plains
		else:
			return _biomes[3] # Forest
	elif temp < 0.8: # 温暖
		if humidity < 0.2:
			return _biomes[5] # Desert
		elif humidity < 0.6:
			return _biomes[2] # Plains
		elif humidity < 0.8:
			return _biomes[3] # Forest
		else:
			return _biomes[4] # Jungle
	else: # 炎热
		if humidity < 0.3:
			return _biomes[5] # Desert
		else:
			return _biomes[5] # Desert

func cache_block_ids() -> void:
	var bedrock = BlockRegistry.get_block_by_name("bedrock")
	var stone = BlockRegistry.get_block_by_name("stone")
	var dirt = BlockRegistry.get_block_by_name("dirt")
	var grass = BlockRegistry.get_block_by_name("grass")
	var water = BlockRegistry.get_block_by_name("water")
	var oak_log = BlockRegistry.get_block_by_name("oak_log")
	var leaves = BlockRegistry.get_block_by_name("oak_leaves")
	var sand = BlockRegistry.get_block_by_name("sand")
	
	if bedrock: _id_bedrock = bedrock.id
	if stone: _id_stone = stone.id
	if dirt: _id_dirt = dirt.id
	if grass: _id_grass = grass.id
	if water: _id_water = water.id
	if oak_log: _id_log = oak_log.id
	if leaves: _id_leaves = leaves.id
	if sand: _id_sand = sand.id
	
	# Cache biome blocks
	for biome in _biomes:
		biome.cache_ids()
		
	# Cache Ores
	var ores = ["coal_ore", "iron_ore", "copper_ore", "gold_ore", "tin_ore", "aluminum_ore", "silver_ore", "zinc_ore", "diamond_ore", "emerald_ore", "lapis_ore"]
	for ore_name in ores:
		var block = BlockRegistry.get_block_by_name(ore_name)
		if block:
			_ore_ids[ore_name] = block.id

# 分阶段生成区块地形
func generate_chunk_stage(chunk: Chunk, stage: int) -> void:
	# 检查参数有效性
	if not is_instance_valid(chunk):
		return
		
	match stage:
		ChunkGenerationStage.BASE_TERRAIN:
			_generate_base_terrain(chunk)
		ChunkGenerationStage.WATER_AND_SURFACE:
			_generate_water_and_surface(chunk)
		ChunkGenerationStage.ORES_AND_CAVES:
			_generate_ores_and_caves(chunk)
		ChunkGenerationStage.DECORATIONS:
			_generate_decorations(chunk)

# 生成区块的Section（基于阶段）
func generate_chunk_section(chunk: Chunk, section_index: int, stage: int) -> void:
	# 检查参数有效性
	if not is_instance_valid(chunk):
		return
		
	match stage:
		ChunkGenerationStage.BASE_TERRAIN:
			_generate_section_base_terrain(chunk, section_index)
		ChunkGenerationStage.WATER_AND_SURFACE:
			_generate_section_water_and_surface(chunk, section_index)
		ChunkGenerationStage.ORES_AND_CAVES:
			_generate_section_ores_and_caves(chunk, section_index)
		ChunkGenerationStage.DECORATIONS:
			_generate_section_decorations(chunk, section_index)

# Section生成任务
class SectionGenerationTask:
	var chunk: Chunk
	var section_index: int
	var stage: int
	var generator: WorldGenerator
	
	func _init(c: Chunk, index: int, s: int, gen: WorldGenerator):
		chunk = c
		section_index = index
		stage = s
		generator = gen

# 生成Section的基础地形
func _generate_section_base_terrain(chunk: Chunk, section_index: int) -> void:
	var bounds = chunk.get_section_bounds(section_index)
	var min_pos = bounds.min
	var max_pos = bounds.max
	
	var cx_offset = chunk.chunk_position.x * Constants.CHUNK_SIZE
	var cz_offset = chunk.chunk_position.y * Constants.CHUNK_SIZE
	
	# 确保我们处理整个Section区域
	for x in range(min_pos.x, max_pos.x + 1):
		for z in range(min_pos.z, max_pos.z + 1):
			var world_x = cx_offset + x
			var world_z = cz_offset + z
			
			# 使用缓存的高度计算（使用与区块生成相同的算法确保一致性）
			var final_height = _get_cached_height(world_x, world_z)
			
			# 只生成这个Section范围内的Y值
			var y_start = max(min_pos.y, 0)
			var y_end = min(max_pos.y + 1, final_height + 1)
			
			for y in range(y_start, y_end):
				var block_id = Constants.AIR_BLOCK_ID
				
				if y == 0:
					block_id = _id_bedrock
				elif y < final_height - 3:
					block_id = _id_stone
					
				if block_id != Constants.AIR_BLOCK_ID:
					chunk.set_voxel_raw(x, y, z, block_id)

# 生成Section的水体和表层
func _generate_section_water_and_surface(chunk: Chunk, section_index: int) -> void:
	var bounds = chunk.get_section_bounds(section_index)
	var min_pos = bounds.min
	var max_pos = bounds.max
	
	var cx_offset = chunk.chunk_position.x * Constants.CHUNK_SIZE
	var cz_offset = chunk.chunk_position.y * Constants.CHUNK_SIZE
	var sea_level = 64
	
	for x in range(min_pos.x, max_pos.x + 1):
		for z in range(min_pos.z, max_pos.z + 1):
			var world_x = cx_offset + x
			var world_z = cz_offset + z
			
			# 使用缓存的高度和生物群系计算（使用与区块生成相同的算法确保一致性）
			var final_height = _get_cached_height(world_x, world_z)
			var biome = _get_cached_biome(world_x, world_z)
			
			# 只生成这个Section范围内的Y值
			var y_start = max(min_pos.y, 0)
			var y_end = min(max_pos.y + 1, final_height + 1)
			
			for y in range(y_start, y_end):
				var block_id = Constants.AIR_BLOCK_ID
				
				if y >= final_height - 3 and y < final_height:
					block_id = biome.get_dirt_block()
				elif y == final_height:
					block_id = biome.get_top_block()
					
				if block_id != Constants.AIR_BLOCK_ID:
					chunk.set_voxel_raw(x, y, z, block_id)
			
			# 生成水体（如果在这个Section范围内）
			if final_height < sea_level:
				y_start = max(min_pos.y, final_height + 1)
				y_end = min(max_pos.y + 1, sea_level + 1)
				
				for y in range(y_start, y_end):
					chunk.set_voxel_raw(x, y, z, _id_water)

# 生成Section的矿石和洞穴
func _generate_section_ores_and_caves(chunk: Chunk, section_index: int) -> void:
	# 矿石生成通常需要更大的范围来生成矿脉，这里简化处理
	# 只在特定Section中生成部分矿石
	var bounds = chunk.get_section_bounds(section_index)
	var min_pos = bounds.min
	var max_pos = bounds.max
	
	# 为简化，只生成部分矿石
	_generate_section_ores(chunk, section_index)

# 生成Section的矿石
func _generate_section_ores(chunk: Chunk, section_index: int) -> void:
	var bounds = chunk.get_section_bounds(section_index)
	var min_pos = bounds.min
	var max_pos = bounds.max
	
	# 配置矿石生成参数: [OreName, Attempts, MinY, MaxY, Size]
	var ore_configs = [
		["coal_ore", 3, 10, 128, 8],
		["iron_ore", 2, 5, 64, 6],
		["copper_ore", 2, 30, 90, 8],
		["tin_ore", 1, 20, 80, 6],
		["aluminum_ore", 1, 40, 100, 6],
		["zinc_ore", 1, 20, 70, 6],
		["gold_ore", 1, 0, 32, 4],
		["silver_ore", 1, 5, 40, 5],
		["lapis_ore", 1, 0, 30, 4],
		["diamond_ore", 1, 0, 16, 4],
		["emerald_ore", 1, 0, 32, 3]
	]
	
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(chunk.chunk_position) + section_index + 12345
	
	for config in ore_configs:
		var ore_name = config[0]
		if not _ore_ids.has(ore_name): continue
		
		var block_id = _ore_ids[ore_name]
		var attempts = config[1]
		var min_y = max(config[2], min_pos.y)
		var max_y = min(config[3], max_pos.y)
		var size = config[4]
		
		# 只在Y范围内的Section生成矿石
		if min_y <= max_y:
			for i in range(attempts):
				var x = rng.randi_range(min_pos.x, max_pos.x)
				var z = rng.randi_range(min_pos.z, max_pos.z)
				var y = rng.randi_range(min_y, max_y)
				
				_generate_vein_in_section(chunk, x, y, z, block_id, size, rng, min_pos, max_pos)

func _generate_vein_in_section(chunk: Chunk, start_x: int, start_y: int, start_z: int, block_id: int, size: int, rng: RandomNumberGenerator, min_pos: Vector3i, max_pos: Vector3i) -> void:
	var current_x = start_x
	var current_y = start_y
	var current_z = start_z
	
	for i in range(size):
		# 确保在Section范围内
		if current_x >= min_pos.x and current_x <= max_pos.x and \
		   current_y >= min_pos.y and current_y <= max_pos.y and \
		   current_z >= min_pos.z and current_z <= max_pos.z:
			
			if chunk.is_valid_position(current_x, current_y, current_z):
				# Only replace stone
				var current_id = chunk.get_voxel(current_x, current_y, current_z)
				if current_id != Constants.AIR_BLOCK_ID and current_id != _id_bedrock and current_id != _id_water:
					chunk.set_voxel_raw(current_x, current_y, current_z, block_id)
		
		current_x += rng.randi_range(-1, 1)
		current_y += rng.randi_range(-1, 1)
		current_z += rng.randi_range(-1, 1)

# 生成Section的装饰物
func _generate_section_decorations(chunk: Chunk, section_index: int) -> void:
	# 装饰物（如树木）通常跨越多个Section，这里我们只处理部分情况
	# 简化处理：只在地表Section生成装饰物
	pass

# 第一阶段：生成基础地形（基岩和石头）
func _generate_base_terrain(chunk: Chunk) -> void:
	var cx_offset = chunk.chunk_position.x * Constants.CHUNK_SIZE
	var cz_offset = chunk.chunk_position.y * Constants.CHUNK_SIZE
	
	# 使用更精确的地形生成，确保区块边界连续
	var step = 1 # 不再使用优化步长，确保连续性
	
	# 生成整个区块的地形
	for x in range(0, Constants.CHUNK_SIZE, step):
		for z in range(0, Constants.CHUNK_SIZE, step):
			var world_x = cx_offset + x
			var world_z = cz_offset + z
			
			# 使用缓存的高度计算
			var final_height = _get_cached_height(world_x, world_z)
			
			# Fill column
			for i in range(step):
				for k in range(step):
					var vx = x + i
					var vz = z + k
					
					if vx >= Constants.CHUNK_SIZE or vz >= Constants.CHUNK_SIZE:
						continue
						
					_fill_base_column(chunk, vx, vz, final_height)

# 填充基础列（基岩和石头）
func _fill_base_column(chunk: Chunk, x: int, z: int, height: int) -> void:
	for y in range(height + 1):
		var block_id = Constants.AIR_BLOCK_ID
		
		if y == 0:
			block_id = _id_bedrock
		elif y < height - 3:
			block_id = _id_stone
			
		if block_id != Constants.AIR_BLOCK_ID:
			chunk.set_voxel_raw(x, y, z, block_id)

# 第二阶段：生成水体和表层（泥土、草等）
func _generate_water_and_surface(chunk: Chunk) -> void:
	var cx_offset = chunk.chunk_position.x * Constants.CHUNK_SIZE
	var cz_offset = chunk.chunk_position.y * Constants.CHUNK_SIZE
	
	var step = 1 # 不再使用优化步长，确保连续性
	var sea_level = 64
	
	for x in range(0, Constants.CHUNK_SIZE, step):
		for z in range(0, Constants.CHUNK_SIZE, step):
			var world_x = cx_offset + x
			var world_z = cz_offset + z
			
			# 使用缓存的高度和生物群系计算
			var final_height = _get_cached_height(world_x, world_z)
			var biome = _get_cached_biome(world_x, world_z)
			
			# Fill column with water and surface blocks
			for i in range(step):
				for k in range(step):
					var vx = x + i
					var vz = z + k
					
					if vx >= Constants.CHUNK_SIZE or vz >= Constants.CHUNK_SIZE:
						continue
						
					_fill_surface_column(chunk, vx, vz, final_height, sea_level, biome)

# 修改 _fill_surface_column 方法以使用高级生物群系
func _fill_surface_column(chunk: Chunk, x: int, z: int, height: int, sea_level: int, biome: Resource) -> void:
	for y in range(height + 1):
		var block_id = Constants.AIR_BLOCK_ID
		
		if y >= height - 3 and y < height:
			block_id = biome.get_dirt_block()
		elif y == height:
			block_id = biome.get_top_block()
			
		if block_id != Constants.AIR_BLOCK_ID:
			chunk.set_voxel_raw(x, y, z, block_id)
			
	# 处理水下部分
	if height < sea_level:
		for y in range(height + 1, sea_level + 1):
			var block_id = biome.get_underwater_block()
			chunk.set_voxel_raw(x, y, z, block_id)

# 第三阶段：生成矿石和洞穴
func _generate_ores_and_caves(chunk: Chunk) -> void:
	_generate_ores(chunk)
	# TODO: 实现洞穴生成

# 第四阶段：生成装饰物（树木、花草等）
func _generate_decorations(chunk: Chunk) -> void:
	decorate_chunk(chunk, _seed)

# 原有的完整生成方法保持不变，以兼容现有代码
func generate_chunk(chunk: Chunk) -> void:
	var cx_offset = chunk.chunk_position.x * Constants.CHUNK_SIZE
	var cz_offset = chunk.chunk_position.y * Constants.CHUNK_SIZE
	
	var step = 2 # Voxel scale optimization
	var sea_level = 64
	
	for x in range(0, Constants.CHUNK_SIZE, step):
		for z in range(0, Constants.CHUNK_SIZE, step):
			var world_x = cx_offset + x
			var world_z = cz_offset + z
			
			# 1. Calculate Height (Continental + Erosion)
			var continental_val = _continental_noise.get_noise_2d(world_x, world_z)
			var erosion_val = _erosion_noise.get_noise_2d(world_x, world_z)
			
			# Map continental noise to base height zones
			var base_height = 64.0
			var height_scale = 0.0
			
			if continental_val < -0.2: # Ocean
				base_height = 40.0
				height_scale = 20.0
			elif continental_val < 0.0: # Coast/Beach
				base_height = 64.0
				height_scale = 5.0
			elif continental_val < 0.5: # Inland/Plains
				base_height = 70.0
				height_scale = 30.0
			else: # Mountains
				base_height = 100.0
				height_scale = 120.0
				
			# Apply erosion/detail
			var final_height = int(base_height + (continental_val * 10.0) + (erosion_val * height_scale))
			final_height = clamp(final_height, 0, Constants.VOXEL_MAX_HEIGHT - 1)
			
			# 2. Determine Biome
			var biome = _get_biome(world_x, world_z)
			
			# Quantize height for optimization
			var height = int(round(final_height / float(step)) * step)
			
			# Fill column
			for i in range(step):
				for k in range(step):
					var vx = x + i
					var vz = z + k
					
					if vx >= Constants.CHUNK_SIZE or vz >= Constants.CHUNK_SIZE:
						continue
						
					_fill_column(chunk, vx, vz, height, sea_level, biome)

	_generate_ores(chunk)

func _fill_column(chunk: Chunk, x: int, z: int, height: int, sea_level: int, biome: Resource) -> void:
	for y in range(height + 1):
		var block_id = Constants.AIR_BLOCK_ID
		
		if y == 0:
			block_id = _id_bedrock
		elif y < height - 3:
			block_id = biome.get_stone_block()
		elif y < height:
			block_id = biome.get_dirt_block()
		elif y == height:
			block_id = biome.get_top_block()
			
		if block_id != Constants.AIR_BLOCK_ID:
			chunk.set_voxel_raw(x, y, z, block_id)
			
	if height < sea_level:
		for y in range(height + 1, sea_level + 1):
			chunk.set_voxel_raw(x, y, z, _id_water)

func _generate_ores(chunk: Chunk) -> void:
	# Config: [OreName, Attempts, MinY, MaxY, Size]
	var ore_configs = [
		["coal_ore", 20, 10, 128, 8],
		["iron_ore", 15, 5, 64, 6],
		["copper_ore", 15, 30, 90, 8],
		["tin_ore", 12, 20, 80, 6],
		["aluminum_ore", 10, 40, 100, 6],
		["zinc_ore", 10, 20, 70, 6],
		["gold_ore", 5, 0, 32, 4],
		["silver_ore", 6, 5, 40, 5],
		["lapis_ore", 4, 0, 30, 4],
		["diamond_ore", 2, 0, 16, 4],
		["emerald_ore", 2, 0, 32, 3] # Usually mountain only
	]
	
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(chunk.chunk_position) + 12345
	
	for config in ore_configs:
		var ore_name = config[0]
		if not _ore_ids.has(ore_name): continue
		
		var block_id = _ore_ids[ore_name]
		var attempts = config[1]
		var min_y = config[2]
		var max_y = config[3]
		var size = config[4]
		
		for i in range(attempts):
			var x = rng.randi_range(0, Constants.CHUNK_SIZE - 1)
			var z = rng.randi_range(0, Constants.CHUNK_SIZE - 1)
			var y = rng.randi_range(min_y, max_y)
			
			_generate_vein(chunk, x, y, z, block_id, size, rng)

func _generate_vein(chunk: Chunk, start_x: int, start_y: int, start_z: int, block_id: int, size: int, rng: RandomNumberGenerator) -> void:
	var current_x = start_x
	var current_y = start_y
	var current_z = start_z
	
	for i in range(size):
		if chunk.is_valid_position(current_x, current_y, current_z):
			# Only replace stone
			# Note: We need to check against all biome stone types ideally, but for now just check if it's not air/water/bedrock
			var current_id = chunk.get_voxel(current_x, current_y, current_z)
			if current_id != Constants.AIR_BLOCK_ID and current_id != _id_bedrock and current_id != _id_water:
				# Ideally check if it is "stone" material
				chunk.set_voxel_raw(current_x, current_y, current_z, block_id)
		
		current_x += rng.randi_range(-1, 1)
		current_y += rng.randi_range(-1, 1)
		current_z += rng.randi_range(-1, 1)

func decorate_chunk(chunk: Chunk, world_seed: int) -> void:
	var cx_offset = chunk.chunk_position.x * Constants.CHUNK_SIZE
	var cz_offset = chunk.chunk_position.y * Constants.CHUNK_SIZE
	
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(chunk.chunk_position) + world_seed
	
	for x in range(2, Constants.CHUNK_SIZE - 2, 4):
		for z in range(2, Constants.CHUNK_SIZE - 2, 4):
			var world_x = cx_offset + x
			var world_z = cz_offset + z
			
			# Re-calculate biome context
			var biome = _get_biome(world_x, world_z)
			
			if rng.randf() < biome.tree_density:
				var surface_y = _get_surface_height(chunk, x, z, biome)
				if surface_y > 0:
					if chunk.get_voxel(x, surface_y, z) == Constants.AIR_BLOCK_ID:
						_generate_tree(chunk, x, surface_y, z, rng)

func _get_surface_height(chunk: Chunk, x: int, z: int, biome: Resource) -> int:
	for y in range(Constants.VOXEL_MAX_HEIGHT - 1, 0, -1):
		var block_id = chunk.get_voxel(x, y, z)
		if block_id == biome.get_top_block():
			return y + 1
	return -1

func _generate_tree(chunk: Chunk, x: int, y: int, z: int, rng: RandomNumberGenerator) -> void:
	var height = 4 + rng.randi() % 3
	
	# Trunk
	for i in range(height):
		if chunk.is_valid_position(x, y + i, z):
			chunk.set_voxel_raw(x, y + i, z, _id_log)
			
	# Leaves
	var leaf_start_y = y + height - 2
	var leaf_end_y = y + height + 1
	
	for ly in range(leaf_start_y, leaf_end_y + 1):
		var radius = 2
		if ly == leaf_end_y: radius = 1
		
		for lx in range(x - radius, x + radius + 1):
			for lz in range(z - radius, z + radius + 1):
				if abs(lx - x) == radius and abs(lz - z) == radius:
					continue
				
				if chunk.is_valid_position(lx, ly, lz):
					if chunk.get_voxel(lx, ly, lz) == Constants.AIR_BLOCK_ID:
						chunk.set_voxel_raw(lx, ly, lz, _id_leaves)

func _get_cached_height(world_x: int, world_z: int) -> int:
	var key = Vector2i(world_x, world_z)
	if _height_cache.has(key):
		return _height_cache[key]
	
	# 1. Calculate Height (Continental + Erosion)
	var continental_val = _continental_noise.get_noise_2d(world_x, world_z)
	var erosion_val = _erosion_noise.get_noise_2d(world_x, world_z)
	
	# Map continental noise to base height zones
	var base_height = 64.0
	var height_scale = 0.0
	
	if continental_val < -0.2: # Ocean
		base_height = 40.0
		height_scale = 20.0
	elif continental_val < 0.0: # Coast/Beach
		base_height = 64.0
		height_scale = 5.0
	elif continental_val < 0.5: # Inland/Plains
		base_height = 70.0
		height_scale = 30.0
	else: # Mountains
		base_height = 100.0
		height_scale = 120.0
		
	# Apply erosion/detail
	var final_height = int(base_height + (continental_val * 10.0) + (erosion_val * height_scale))
	final_height = clamp(final_height, 0, Constants.VOXEL_MAX_HEIGHT - 1)
	
	# 缓存结果
	_height_cache[key] = final_height
	
	# 限制缓存大小以避免内存问题
	if _height_cache.size() > 10000:
		_height_cache.clear()
	
	return final_height

func _get_cached_biome(world_x: int, world_z: int) -> Resource:
	var key = Vector2i(world_x, world_z)
	if _biome_cache.has(key):
		return _biome_cache[key]
	
	var biome = _get_biome(world_x, world_z)
	_biome_cache[key] = biome
	
	# 限制缓存大小以避免内存问题
	if _biome_cache.size() > 10000:
		_biome_cache.clear()
	
	return biome

func get_noise_height(world_x: int, world_z: int) -> int:
	# Helper for player spawn
	var continental_val = _continental_noise.get_noise_2d(world_x, world_z)
	var erosion_val = _erosion_noise.get_noise_2d(world_x, world_z)
	
	var base_height = 64.0
	var height_scale = 0.0
	
	if continental_val < -0.2: base_height = 40.0; height_scale = 20.0
	elif continental_val < 0.0: base_height = 64.0; height_scale = 5.0
	elif continental_val < 0.5: base_height = 70.0; height_scale = 30.0
	else: base_height = 100.0; height_scale = 120.0
	
	return int(base_height + (continental_val * 10.0) + (erosion_val * height_scale))
