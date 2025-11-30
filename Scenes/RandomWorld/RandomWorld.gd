extends Node3D

# --- 无限区块世界管理器 ---
var _world_manager: WorldManager

func _ready() -> void:
	_initialize_systems()

func _initialize_systems() -> void:
	print("Initializing systems for RandomWorld...")
	# 等待BlockManager加载完成
	if BlockManager.has_signal("loading_complete"):
		BlockManager.loading_complete.connect(_on_block_manager_ready)
	else:
		# 若无信号，直接初始化（兼容旧逻辑）
		_on_block_manager_ready()

func _on_block_manager_ready() -> void:
	print("[RandomWorld] BlockManager加载完成，已注册方块如下：")
	BlockRegistry.debug_print_blocks()
	# 初始化WorldManager并启动区块生成
	if not _world_manager:
		_world_manager = $WorldManager
		_world_manager._initialize_world()
		_world_manager._generate_initial_chunks()

func _process(delta: float) -> void:
	if _world_manager:
		_world_manager._process(delta)
		# 主线程处理异步区块生成结果
		if _world_manager._world_generator:
			_world_manager._world_generator.process_pending_results()

# --- 视距调整接口（可用于UI或快捷键） ---
func set_render_distance(new_distance: int) -> void:
	if _world_manager:
		_world_manager.set_render_distance(new_distance)

# --- 存档/加载接口保留 ---
func save_world() -> void:
	# 可调用 WorldManager 或原有 ChunkSerializerScript 实现
	print("Saving world...")
	# ...existing code...

func load_world() -> void:
	print("Loading world...")
	# ...existing code...

# --- 预留地形/生物群系扩展入口 ---
# 可在 _initialize_systems 或 _process 中集成更多系统
