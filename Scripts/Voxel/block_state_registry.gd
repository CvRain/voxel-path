class_name BlockStateRegistry
extends Node

static var _instance: BlockStateRegistry

# 映射: Global State ID -> BlockState 对象
static var _states: Dictionary = {}

# 映射: Block ID -> List of State IDs (该方块拥有的所有状态ID)
static var _block_to_states: Dictionary = {}

# 映射: Block ID + Properties Hash -> State ID (用于快速查找)
static var _lookup_cache: Dictionary = {}

# 默认状态映射: Block ID -> Default State ID
static var _default_states: Dictionary = {}

# 全局状态 ID 计数器 (从 0 开始，0 预留给 Air 的默认状态)
static var _next_state_id: int = 0

func _enter_tree() -> void:
	if _instance != null:
		queue_free()
		return
	_instance = self
	
	# 注册 Air 的默认状态 (State ID 0)
	_register_air_state()

static func _register_air_state() -> void:
	var BlockStateScript = load("res://Scripts/Voxel/block_state.gd")
	var air_id = Constants.AIR_BLOCK_ID
	var state = BlockStateScript.new(air_id, 0, {})
	_states[0] = state
	_block_to_states[air_id] = [0]
	_default_states[air_id] = 0
	_next_state_id = 1

# 为一个方块生成并注册所有可能的状态
static func register_block_states(block: BlockData) -> void:
	var BlockStateScript = load("res://Scripts/Voxel/block_state.gd")
	var definitions = block.state_definitions
	var property_names = definitions.keys()
	property_names.sort() # 保证顺序一致
	
	# 生成所有属性组合 (笛卡尔积)
	var combinations = _generate_combinations(definitions, property_names)
	
	if combinations.is_empty():
		# 如果没有定义状态，则注册一个默认的空状态
		combinations.append({})
	
	var state_ids = []
	var default_state_id = -1
	
	for props in combinations:
		var state_id = _next_state_id
		_next_state_id += 1
		
		var state = BlockStateScript.new(block.id, state_id, props)
		_states[state_id] = state
		state_ids.append(state_id)
		
		# 构建查找缓存 Key: "BlockID|Prop1:Val1|Prop2:Val2"
		var cache_key = _build_cache_key(block.id, props)
		_lookup_cache[cache_key] = state_id
		
		# 检查是否是默认状态
		if _is_match(props, block.default_state):
			default_state_id = state_id
	
	# 如果没有匹配到默认状态，使用第一个生成的
	if default_state_id == -1:
		default_state_id = state_ids[0]
		
	_block_to_states[block.id] = state_ids
	_default_states[block.id] = default_state_id
	
	if Constants.DEBUG_BLOCK_LOADING and not definitions.is_empty():
		MyLogger.debug("Generated %d states for block '%s'" % [state_ids.size(), block.name])

# 递归生成组合
static func _generate_combinations(definitions: Dictionary, keys: Array, index: int = 0) -> Array:
	if index >= keys.size():
		return [ {}]
	
	var key = keys[index]
	var values = definitions[key]
	var sub_combinations = _generate_combinations(definitions, keys, index + 1)
	var result = []
	
	for val in values:
		for sub in sub_combinations:
			var new_comb = sub.duplicate()
			new_comb[key] = val
			result.append(new_comb)
	
	return result

static func _build_cache_key(block_id: int, props: Dictionary) -> String:
	if props.is_empty():
		return str(block_id)
	
	var keys = props.keys()
	keys.sort()
	var s = str(block_id)
	for k in keys:
		s += "|%s:%s" % [k, props[k]]
	return s

static func _is_match(props: Dictionary, target: Dictionary) -> bool:
	if props.size() != target.size():
		return false
	for k in target:
		if not props.has(k) or props[k] != target[k]:
			return false
	return true

# --- Public API ---

static func get_state(state_id: int) -> RefCounted: # Returns BlockState
	return _states.get(state_id)

static func get_default_state_id(block_id: int) -> int:
	return _default_states.get(block_id, 0) # Default to Air State 0

# 根据属性查找 State ID
# Example: get_state_id_by_properties(10, {"facing": "north"})
static func get_state_id_by_properties(block_id: int, props: Dictionary) -> int:
	var key = _build_cache_key(block_id, props)
	return _lookup_cache.get(key, -1)

static func get_instance() -> BlockStateRegistry:
	return _instance
