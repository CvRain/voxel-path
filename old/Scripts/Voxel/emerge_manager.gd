extends Node

class_name Emerger

const ChunkGenerationStage = preload("res://Scripts/Voxel/chunk_generation_stage.gd").ChunkGenerationStage

const RESULT_ACCEPTED = 0
const RESULT_DEFERRED = 1
const RESULT_REJECTED = 2

var world = null

# Queues and tracking (prototype)
var _generation_queue: Array = []
var _section_generation_queue: Array = []
var _deferred_chunk_enqueues: Array = []

var MAX_PENDING_SECTION_QUEUE: int = 512
const EXPAND_SECTIONS_PER_DEFERRED: int = 1
const MAX_DEFERRED_EXPAND_PER_TICK: int = 3


var _generation_timer: float = 0.0
const GENERATION_INTERVAL: float = 0.1
var _max_generations_per_frame: int = 2
var _auto_adjust_timer: float = 0.0
const AUTO_ADJUST_INTERVAL: float = 2.0 # 每2秒动态调整一次

func _init(_world: Node) -> void:
	world = _world

func enqueue_chunk_generation(chunk, stage: int) -> int:
	if not is_instance_valid(world) or not is_instance_valid(world._world_generator):
		return RESULT_REJECTED

	# 获取玩家位置
	var player_pos = world._player.global_position if is_instance_valid(world._player) else Vector3(0, 64, 0)
	# 生成section任务并排序（优先级分配）
	var section_tasks = SectionManager.create_section_tasks(chunk, player_pos, world._world_generator)
	SectionManager.sort_section_tasks(section_tasks)
	var num_sections = section_tasks.size()

	# mirror RandomWorld's pending tracking
	world._chunk_stage_pending[chunk] = {"stage": stage, "pending": num_sections}

	# If global pending would exceed threshold, defer
	if _section_generation_queue.size() + num_sections > MAX_PENDING_SECTION_QUEUE:
		_deferred_chunk_enqueues.append({"chunk": chunk, "stage": stage, "num_sections": num_sections, "next_section": 0, "section_tasks": section_tasks})
		if world.DEBUG_GEN:
			print("[EMERGER] Deferred enqueue -> %s stage=%d sections=%d (queue_len=%d)" % [chunk.name, stage, num_sections, _section_generation_queue.size()])
		return RESULT_DEFERRED

	# otherwise expand immediately，按优先级顺序入队
	for t in section_tasks:
		_section_generation_queue.append({"chunk": chunk, "section_index": t.section_index, "stage": stage})
	if world.DEBUG_GEN:
		print("[EMERGER] Enqueue chunk sections (priority) -> %s stage=%d sections=%d" % [chunk.name, stage, num_sections])
	return RESULT_ACCEPTED

func process(delta: float) -> void:
	# Basic time slicing and deferred expansion
	_generation_timer += delta
	_auto_adjust_timer += delta
	if _generation_timer < GENERATION_INTERVAL:
		return
	_generation_timer = 0.0

	# 动态调整队列上限和每帧生成速率（参考luanti）
	if _auto_adjust_timer >= AUTO_ADJUST_INTERVAL:
		_auto_adjust_timer = 0.0
		var queue_len = _section_generation_queue.size() + _deferred_chunk_enqueues.size()
		var cpu_count = OS.get_processor_count()
		if queue_len > MAX_PENDING_SECTION_QUEUE * 0.8:
			_max_generations_per_frame = clamp(_max_generations_per_frame + 1, 2, cpu_count * 2)
			MAX_PENDING_SECTION_QUEUE = clamp(MAX_PENDING_SECTION_QUEUE + 128, 512, 4096)
			print("[EMERGER] Auto-Expand: queue_len=%d, max_gen_per_frame=%d, max_queue=%d" % [queue_len, _max_generations_per_frame, MAX_PENDING_SECTION_QUEUE])
		elif queue_len < MAX_PENDING_SECTION_QUEUE * 0.3:
			_max_generations_per_frame = clamp(_max_generations_per_frame - 1, 1, cpu_count * 2)
			MAX_PENDING_SECTION_QUEUE = clamp(MAX_PENDING_SECTION_QUEUE - 64, 256, 4096)
			print("[EMERGER] Auto-Shrink: queue_len=%d, max_gen_per_frame=%d, max_queue=%d" % [queue_len, _max_generations_per_frame, MAX_PENDING_SECTION_QUEUE])

	# 优先处理高优先级Section任务，低优先级任务在队列超限时自动降级或丢弃
	var deferred_expanded = 0
	while _deferred_chunk_enqueues.size() > 0 and deferred_expanded < MAX_DEFERRED_EXPAND_PER_TICK:
		var picked_index = -1
		var d = null
		if is_instance_valid(world) and is_instance_valid(world._player):
			var player_chunk = Vector2i(floor(world._player.global_position.x / Constants.CHUNK_WORLD_SIZE), floor(world._player.global_position.z / Constants.CHUNK_WORLD_SIZE))
			for i in range(_deferred_chunk_enqueues.size()):
				var cand = _deferred_chunk_enqueues[i]
				if is_instance_valid(cand.chunk):
					var cp = cand.chunk.chunk_position
					var dist = max(abs(cp.x - player_chunk.x), abs(cp.y - player_chunk.y))
					if dist <= world.view_distance + 1:
						picked_index = i
						break
		if picked_index >= 0:
			d = _deferred_chunk_enqueues[picked_index]
			_deferred_chunk_enqueues.remove_at(picked_index)
		else:
			d = _deferred_chunk_enqueues.pop_front()

		if not is_instance_valid(d.chunk):
			deferred_expanded += 1
			continue

		var start_i = d.get("next_section", 0)
		var num_sections = d.num_sections
		var section_tasks = d.get("section_tasks", [])
		var end_i = min(start_i + EXPAND_SECTIONS_PER_DEFERRED, num_sections)

		# 优先处理高优先级Section，低优先级在队列超限时丢弃
		section_tasks.sort_custom(func(a, b):
			if a.priority != b.priority:
				return a.priority < b.priority
			return a.section_index < b.section_index)

		var appended = 0
		for i in range(start_i, end_i):
			if _section_generation_queue.size() >= MAX_PENDING_SECTION_QUEUE:
				# 低优先级直接丢弃，保证高优先级实时响应
				if section_tasks[i].priority == SectionManager.SectionPriority.LOW:
					continue
				d.next_section = i
				_deferred_chunk_enqueues.append(d)
				appended = -1
				break
			if i < section_tasks.size():
				var t = section_tasks[i]
				_section_generation_queue.append({"chunk": d.chunk, "section_index": t.section_index, "stage": d.stage})
				appended += 1
				if world.DEBUG_GEN and i % 4 == 0:
					print("[EMERGER] Enqueued section (deferred, priority)-> chunk=%s stage=%d section=%d queue_len=%d" % [d.chunk.name, d.stage, t.section_index, _section_generation_queue.size()])

		if appended == -1:
			break

		var new_next = start_i + appended
		if new_next < num_sections:
			d.next_section = new_next
			_deferred_chunk_enqueues.append(d)

		deferred_expanded += 1

	# 批量Mesh/物理体写回限流，主线程每帧只处理有限数量
	var generations_processed = 0
	var start_time = Time.get_ticks_usec()
	while not _section_generation_queue.is_empty() and generations_processed < _max_generations_per_frame:
		if Time.get_ticks_usec() - start_time > 10000: # 10ms
			break
		var task = _section_generation_queue.pop_front()
		if is_instance_valid(task.chunk) and is_instance_valid(world) and is_instance_valid(world._world_generator):
			world._world_generator.generate_chunk_section_async(task.chunk, task.section_index, task.stage)
			if world.DEBUG_GEN:
				print("[EMERGER] Submit section task -> chunk=%s stage=%d section=%d" % [task.chunk.name, task.stage, task.section_index])
			generations_processed += 1

	# Optionally: process high-level chunk generation queue if any (left as hook)
	while not _generation_queue.is_empty() and generations_processed < _max_generations_per_frame:
		if Time.get_ticks_usec() - start_time > 5000:
			break
		var task = _generation_queue.pop_front()
		if is_instance_valid(task.chunk) and is_instance_valid(world) and is_instance_valid(world._world_generator):
			world._world_generator.generate_chunk_stage(task.chunk, task.stage)
			# after stage processed, update chunk state and possibly enqueue next stage
			task.chunk.generation_stage = task.stage
			if task.stage < ChunkGenerationStage.FULLY_GENERATED:
				enqueue_chunk_generation(task.chunk, task.stage + 1)
			else:
				task.chunk.generate_mesh()
			generations_processed += 1
