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

const MAX_PENDING_SECTION_QUEUE: int = 512
const EXPAND_SECTIONS_PER_DEFERRED: int = 1
const MAX_DEFERRED_EXPAND_PER_TICK: int = 3

var _generation_timer: float = 0.0
const GENERATION_INTERVAL: float = 0.1
var _max_generations_per_frame: int = 2

func _init(_world: Node) -> void:
    world = _world

func enqueue_chunk_generation(chunk, stage: int) -> int:
    if not is_instance_valid(world) or not is_instance_valid(world._world_generator):
        return RESULT_REJECTED

    var num_sections = int(ceil(Constants.VOXEL_MAX_HEIGHT / float(Constants.CHUNK_SECTION_SIZE)))

    # mirror RandomWorld's pending tracking
    world._chunk_stage_pending[chunk] = {"stage": stage, "pending": num_sections}

    # If global pending would exceed threshold, defer
    if _section_generation_queue.size() + num_sections > MAX_PENDING_SECTION_QUEUE:
        _deferred_chunk_enqueues.append({"chunk": chunk, "stage": stage, "num_sections": num_sections, "next_section": 0})
        if world.DEBUG_GEN:
            print("[EMERGER] Deferred enqueue -> %s stage=%d sections=%d (queue_len=%d)" % [chunk.name, stage, num_sections, _section_generation_queue.size()])
        return RESULT_DEFERRED

    # otherwise expand immediately
    for i in range(num_sections):
        _section_generation_queue.append({"chunk": chunk, "section_index": i, "stage": stage})
    if world.DEBUG_GEN:
        print("[EMERGER] Enqueue chunk sections -> %s stage=%d sections=%d" % [chunk.name, stage, num_sections])
    return RESULT_ACCEPTED

func process(delta: float) -> void:
    # Basic time slicing and deferred expansion
    _generation_timer += delta
    if _generation_timer < GENERATION_INTERVAL:
        return
    _generation_timer = 0.0

    # Expand deferred enqueues in small batches, but respect global capacity
    var deferred_expanded = 0
    while _deferred_chunk_enqueues.size() > 0 and deferred_expanded < MAX_DEFERRED_EXPAND_PER_TICK:
        var picked_index = -1
        var d = null
        # Prefer deferred items near player
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
        var end_i = min(start_i + EXPAND_SECTIONS_PER_DEFERRED, num_sections)

        # Append sections one-by-one but stop if global capacity reached
        var appended = 0
        for i in range(start_i, end_i):
            if _section_generation_queue.size() >= MAX_PENDING_SECTION_QUEUE:
                # put back the deferred entry with current next_section and stop expanding for this tick
                d.next_section = i
                _deferred_chunk_enqueues.append(d)
                appended = -1
                break
            _section_generation_queue.append({"chunk": d.chunk, "section_index": i, "stage": d.stage})
            appended += 1
            if world.DEBUG_GEN and i % 4 == 0:
                print("[EMERGER] Enqueued section (deferred)-> chunk=%s stage=%d section=%d queue_len=%d" % [d.chunk.name, d.stage, i, _section_generation_queue.size()])

        if appended == -1:
            # we hit capacity and already re-appended d
            break

        var new_next = start_i + appended
        if new_next < num_sections:
            d.next_section = new_next
            _deferred_chunk_enqueues.append(d)

        deferred_expanded += 1

    # Submit section jobs to world generator (bounded per frame)
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
