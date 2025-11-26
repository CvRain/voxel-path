class_name FluidManager
extends Node

var _world: Node
var _rng: RandomNumberGenerator

func _init(world_node: Node) -> void:
	_world = world_node
	_rng = RandomNumberGenerator.new()

func is_infinite_source(pos: Vector3i, block_data: FluidBlockData) -> bool:
	"""
	Checks if the fluid block at 'pos' is part of a large enough body to be infinite.
	Counts connected blocks of the same ID at the same Y level (Surface Area).
	"""
	var target_id = block_data.id
	var threshold = block_data.infinite_threshold
	var count = 0
	var queue: Array[Vector3i] = [pos]
	var visited: Dictionary = {pos: true}
	
	while not queue.is_empty():
		var current = queue.pop_front()
		count += 1
		if count >= threshold:
			return true
			
		# Check horizontal neighbors
		var neighbors = [
			Vector3i(current.x + 1, current.y, current.z),
			Vector3i(current.x - 1, current.y, current.z),
			Vector3i(current.x, current.y, current.z + 1),
			Vector3i(current.x, current.y, current.z - 1)
		]
		
		for n in neighbors:
			if visited.has(n): continue
			
			# We use get_voxel_at from world, which handles chunk lookups
			if _world.get_voxel_at(n) == target_id:
				visited[n] = true
				queue.append(n)
				
	return false

func process_rain_tick(chunk: Chunk, water_id: int) -> void:
	"""
	Called randomly for chunks to simulate rain filling depressions.
	"""
	# 1. Pick a random column in the chunk
	var rx = _rng.randi_range(0, Constants.CHUNK_SIZE - 1)
	var rz = _rng.randi_range(0, Constants.CHUNK_SIZE - 1)
	
	# 2. Find the surface block
	# We can scan down from top, or use a heightmap if available.
	# Scanning is safer.
	var surface_y = -1
	for y in range(Constants.VOXEL_MAX_HEIGHT - 1, 0, -1):
		var id = chunk.get_voxel(rx, y, rz)
		if id != Constants.AIR_BLOCK_ID:
			surface_y = y
			break
			
	if surface_y == -1: return # Void?
	
	# 3. Check if it's a valid spot for a puddle
	# The block at surface_y must be solid (ground)
	# The block at surface_y + 1 must be Air (which it is, since we scanned)
	
	var ground_id = chunk.get_voxel(rx, surface_y, rz)
	if ground_id == water_id: return # Already water
	
	# Check if it forms a depression (neighbors at surface_y + 1 are solid)
	# This is a strict "cup" check.
	# Or we can just check if neighbors at surface_y are solid/higher.
	
	var target_y = surface_y + 1
	var is_depression = true
	
	# Check 4 neighbors at target_y
	var neighbors = [
		Vector3i(rx + 1, target_y, rz),
		Vector3i(rx - 1, target_y, rz),
		Vector3i(rx, target_y, rz + 1),
		Vector3i(rx, target_y, rz - 1)
	]
	
	for n in neighbors:
		if not chunk.is_valid_position(n.x, n.y, n.z):
			continue # Skip chunk borders for simplicity in this tick
			
		var nid = chunk.get_voxel(n.x, n.y, n.z)
		if nid == Constants.AIR_BLOCK_ID:
			is_depression = false
			break
			
	if is_depression:
		# Fill with water
		chunk.set_voxel(rx, target_y, rz, water_id)
		chunk.generate_mesh() # Trigger update
