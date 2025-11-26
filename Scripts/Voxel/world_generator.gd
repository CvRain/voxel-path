class_name WorldGenerator
extends Node

var _seed: int
var _continental_noise: FastNoiseLite
var _erosion_noise: FastNoiseLite
var _temperature_noise: FastNoiseLite
var _humidity_noise: FastNoiseLite
var _biomes: Array = []

# Cached Block IDs
var _id_bedrock: int = 0
var _id_water: int = 0
var _id_log: int = 0
var _id_leaves: int = 0

# Ore IDs
var _ore_ids: Dictionary = {}

func _init(seed_val: int) -> void:
	_seed = seed_val
	_initialize_noise()
	_initialize_biomes()

func _initialize_noise() -> void:
	# 1. Continental Noise: Determines general elevation (Ocean vs Land vs Mountain base)
	_continental_noise = FastNoiseLite.new()
	_continental_noise.seed = _seed
	_continental_noise.frequency = 0.0005 # Very low frequency for large continents
	_continental_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_continental_noise.fractal_octaves = 4
	
	# 2. Erosion Noise: Adds local detail/roughness
	_erosion_noise = FastNoiseLite.new()
	_erosion_noise.seed = _seed + 1
	_erosion_noise.frequency = 0.003
	_erosion_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_erosion_noise.fractal_octaves = 5
	
	# 3. Temperature Noise: Large climate zones
	_temperature_noise = FastNoiseLite.new()
	_temperature_noise.seed = _seed + 2
	_temperature_noise.frequency = 0.001
	
	# 4. Humidity Noise: Rainfall distribution
	_humidity_noise = FastNoiseLite.new()
	_humidity_noise.seed = _seed + 3
	_humidity_noise.frequency = 0.001

func _initialize_biomes() -> void:
	var BiomeScript = load("res://Scripts/Voxel/biome.gd")
	
	# 0: Ocean
	var ocean = BiomeScript.new()
	ocean.name = "Ocean"
	ocean.top_block_name = "sand" # Ocean floor
	ocean.dirt_block_name = "sand"
	ocean.tree_density = 0.0
	_biomes.append(ocean)
	
	# 1: Beach
	var beach = BiomeScript.new()
	beach.name = "Beach"
	beach.top_block_name = "sand"
	beach.dirt_block_name = "sand"
	beach.tree_density = 0.001 # Palm trees?
	_biomes.append(beach)
	
	# 2: Plains
	var plains = BiomeScript.new()
	plains.name = "Plains"
	plains.top_block_name = "grass"
	plains.tree_density = 0.005
	_biomes.append(plains)
	
	# 3: Forest
	var forest = BiomeScript.new()
	forest.name = "Forest"
	forest.top_block_name = "grass"
	forest.tree_density = 0.05
	_biomes.append(forest)
	
	# 4: Jungle
	var jungle = BiomeScript.new()
	jungle.name = "Jungle"
	jungle.top_block_name = "grass"
	jungle.tree_density = 0.15
	_biomes.append(jungle)
	
	# 5: Desert
	var desert = BiomeScript.new()
	desert.name = "Desert"
	desert.top_block_name = "sand"
	desert.dirt_block_name = "sand"
	desert.stone_block_name = "sandstone" # Need to add sandstone
	desert.tree_density = 0.002 # Cactus
	_biomes.append(desert)
	
	# 6: Snow
	var snow = BiomeScript.new()
	snow.name = "Snow"
	snow.top_block_name = "snow"
	snow.tree_density = 0.02
	_biomes.append(snow)
	
	# 7: Mountains
	var mountains = BiomeScript.new()
	mountains.name = "Mountains"
	mountains.top_block_name = "stone" # Exposed stone
	mountains.dirt_block_name = "stone"
	mountains.tree_density = 0.01
	_biomes.append(mountains)

func _get_biome(height: int, temp: float, humidity: float) -> Resource:
	var sea_level = 64
	
	# 1. Ocean / Beach
	if height < sea_level - 5:
		return _biomes[0] # Ocean
	elif height < sea_level + 2:
		return _biomes[1] # Beach
		
	# 2. Mountains (High Altitude)
	if height > 140:
		if temp < 0.0:
			return _biomes[6] # Snowy Peaks
		else:
			return _biomes[7] # Stone Peaks
			
	# 3. Land Biomes (Based on Temp/Humidity)
	if temp > 0.5: # Hot
		if humidity < -0.2:
			return _biomes[5] # Desert
		elif humidity > 0.2:
			return _biomes[4] # Jungle
		else:
			return _biomes[2] # Plains (Savanna-ish)
	elif temp < -0.5: # Cold
		return _biomes[6] # Snow
	else: # Temperate
		if humidity > 0.0:
			return _biomes[3] # Forest
		else:
			return _biomes[2] # Plains
			
	return _biomes[2] # Fallback

func cache_block_ids() -> void:
	var bedrock = BlockRegistry.get_block_by_name("bedrock")
	var water = BlockRegistry.get_block_by_name("water")
	var oak_log = BlockRegistry.get_block_by_name("oak_log")
	var leaves = BlockRegistry.get_block_by_name("oak_leaves")
	
	if bedrock: _id_bedrock = bedrock.id
	if water: _id_water = water.id
	if oak_log: _id_log = oak_log.id
	if leaves: _id_leaves = leaves.id
	
	# Cache biome blocks
	for biome in _biomes:
		biome.cache_ids()
		
	# Cache Ores
	var ores = ["coal_ore", "iron_ore", "copper_ore", "gold_ore", "tin_ore", "aluminum_ore", "silver_ore", "zinc_ore", "diamond_ore", "emerald_ore", "lapis_ore"]
	for ore_name in ores:
		var block = BlockRegistry.get_block_by_name(ore_name)
		if block:
			_ore_ids[ore_name] = block.id

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
			var temp = _temperature_noise.get_noise_2d(world_x, world_z)
			var humidity = _humidity_noise.get_noise_2d(world_x, world_z)
			var biome = _get_biome(final_height, temp, humidity)
			
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
			var continental_val = _continental_noise.get_noise_2d(world_x, world_z)
			var erosion_val = _erosion_noise.get_noise_2d(world_x, world_z)
			
			# Simplified height recalc for biome selection (should match generate_chunk logic roughly)
			# Note: In a real engine, we'd cache the biome map.
			var base_height = 64.0
			var height_scale = 0.0
			if continental_val < -0.2: base_height = 40.0; height_scale = 20.0
			elif continental_val < 0.0: base_height = 64.0; height_scale = 5.0
			elif continental_val < 0.5: base_height = 70.0; height_scale = 30.0
			else: base_height = 100.0; height_scale = 120.0
			
			var final_height = int(base_height + (continental_val * 10.0) + (erosion_val * height_scale))
			
			var temp = _temperature_noise.get_noise_2d(world_x, world_z)
			var humidity = _humidity_noise.get_noise_2d(world_x, world_z)
			var biome = _get_biome(final_height, temp, humidity)
			
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
