# ProtoController v2.1 by Brackeys & CvRain
# CC0 License
# Intended for rapid prototyping of first-person games.
# Happy prototyping!

extends CharacterBody3D

# --- Enums ---
enum MoveState {GROUND, FLYING, NOCLIP}

# --- Exports ---
@export_group("Movement")
@export var can_move: bool = true
@export var has_gravity: bool = true
@export var can_jump: bool = true
@export var can_sprint: bool = true
@export var can_fly: bool = true
@export var can_noclip: bool = true
@export var step_height: float = 1.1 # Max height to step up (0.25 is block size)
@export var step_smooth_time: float = 0.15 # 阶梯上升的平滑时间

@export_group("Speeds")
@export var look_speed: float = 0.0035
@export var base_speed: float = 6.0
@export var sprint_speed: float = 9.0
@export var jump_velocity: float = 4.8
@export var fly_speed: float = 12.0

@export_group("Tuning")
@export var acceleration: float = 12.0
@export var deacceleration: float = 16.0
@export var max_pitch_degrees: float = 89.0

@export_group("Input Actions")
@export var input_left: String = "move_left"
@export var input_right: String = "move_right"
@export var input_forward: String = "move_forward"
@export var input_back: String = "move_back"
@export var input_jump: String = "jump"
@export var input_sprint: String = "sprint"
@export var input_fly_down: String = "sprint"
@export var input_noclip_toggle: String = "noclip_toggle"
@export var input_right_click: String = "right_click"
@export var input_left_click: String = "left_click"

@export_group("Debug")
@export var debug_enabled: bool = false
@export var debug_interval: float = 0.5

# --- Private Variables ---
var _mouse_captured: bool = false
var _look_rotation: Vector2
var _gravity: float
var _debug_timer: float = 0.0

var _current_state: MoveState = MoveState.GROUND
var _last_jump_press: float = 1.0
const _DOUBLE_JUMP_TIME: float = 0.3

# ===== 阶梯平滑相关变量 =====
var _stepping_up: bool = false
var _step_start_pos: Vector3 = Vector3.ZERO
var _step_target_pos: Vector3 = Vector3.ZERO
var _step_elapsed_time: float = 0.0
var _step_target_height: float = 0.0

# --- Node References ---
@onready var head: Node3D = $Head
@onready var collider: CollisionShape3D = $Collider
@onready var raycast: RayCast3D = $Head/RayCast3D

# --- Interaction ---
var _highlighter: VoxelHighlighter
var _brush_size: int = 4 # Voxels (4 = 1m, 2 = 0.5m, 1 = 0.25m)
var _interaction_dist: float = 5.0

# --- Godot Lifecycle ---
func _ready() -> void:
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
	check_input_mappings()
	
	_look_rotation.y = rotation.y
	_look_rotation.x = head.rotation.x
	
	capture_mouse()
	
	# Setup RayCast
	raycast.transform = Transform3D.IDENTITY # Reset transform to ensure it points forward relative to Head
	raycast.target_position = Vector3(0, 0, -_interaction_dist)
	raycast.enabled = true
	raycast.add_exception(self) # Ignore player body (CharacterBody3D is a CollisionObject3D)
	
	# Setup Highlighter
	_highlighter = VoxelHighlighter.new()
	# Use add_child on the current scene (RandomWorld) or the player itself if we want it to move with player?
	# No, highlighter position is global.
	# Let's try adding it to the main scene root.
	get_tree().current_scene.call_deferred("add_child", _highlighter)


func _input(event: InputEvent) -> void:
	if Input.is_key_pressed(KEY_ESCAPE):
		release_mouse()
		
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not _mouse_captured:
		capture_mouse()

	if _mouse_captured and event is InputEventMouseMotion:
		_handle_mouse_look(event.relative)
		
	if Input.is_action_just_pressed("ui_focus_next"): # Tab key usually
		_toggle_brush_size()

func _physics_process(delta: float) -> void:
	_last_jump_press += delta
	
	_handle_interaction()
	
	if debug_enabled:
		_debug_timer += delta
		if _debug_timer >= debug_interval:
			_debug_timer = 0.0
			print("Player Pos: %s | State: %s | Stepping: %s" % [global_position, _current_state, _stepping_up])

	# --- State Transitions ---
	if can_fly and Input.is_action_just_pressed(input_jump):
		if _last_jump_press < _DOUBLE_JUMP_TIME:
			if _current_state == MoveState.GROUND:
				_set_state(MoveState.FLYING)
			else:
				_set_state(MoveState.GROUND)
		_last_jump_press = 0.0
		
	if can_noclip and Input.is_action_just_pressed(input_noclip_toggle):
		if _current_state == MoveState.NOCLIP:
			_set_state(MoveState.FLYING)
		else:
			_set_state(MoveState.NOCLIP)

	# --- 处理阶梯平滑上升 ---
	if _stepping_up:
		_update_step_smoothing(delta)
		return # 在阶梯上升期间，跳过普通物理计算

	# --- State Logic ---
	match _current_state:
		MoveState.GROUND:
			_ground_physics(delta)
		MoveState.FLYING:
			_flying_physics(delta)
		MoveState.NOCLIP:
			_flying_physics(delta)

# --- State Implementations ---
func _ground_physics(delta: float):
	var vel := velocity
	
	# Apply gravity
	if has_gravity and not is_on_floor():
		vel.y -= _gravity * delta

	# Handle jumping
	if can_jump and Input.is_action_pressed(input_jump) and is_on_floor():
		vel.y = jump_velocity

	# Get input direction
	var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
	var move_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Determine target speed
	var current_speed = base_speed
	if can_sprint and Input.is_action_pressed(input_sprint):
		current_speed = sprint_speed
	
	var target_velocity = move_dir * current_speed
	
	# Apply acceleration/deacceleration
	var accel = deacceleration if input_dir == Vector2.ZERO else acceleration
	vel.x = move_toward(vel.x, target_velocity.x, accel * delta)
	vel.z = move_toward(vel.z, target_velocity.z, accel * delta)
	
	velocity = vel
	move_and_slide()
	
	# 检查并处理阶梯
	if is_on_wall() and not _stepping_up:
		_attempt_step_up(move_dir)

func _flying_physics(delta: float):
	var vel := velocity
	
	# Get input direction (3D)
	var input_dir_2d := Input.get_vector(input_left, input_right, input_forward, input_back)
	var move_dir := (head.global_basis * Vector3(input_dir_2d.x, 0, input_dir_2d.y)).normalized()
	
	# Handle vertical movement
	if Input.is_action_pressed(input_jump):
		move_dir.y += 1.0
	if Input.is_action_pressed(input_fly_down):
		move_dir.y -= 1.0
	
	var target_velocity = move_dir.normalized() * fly_speed
	
	# Apply acceleration/deacceleration
	var is_moving = input_dir_2d != Vector2.ZERO or Input.is_action_pressed(input_jump) or Input.is_action_pressed(input_fly_down)
	var accel = deacceleration if not is_moving else acceleration
	vel = vel.move_toward(target_velocity, accel * delta)
	
	velocity = vel
	move_and_slide()

# --- Helper Functions ---
func _set_state(new_state: MoveState):
	if _current_state == new_state:
		return
		
	_current_state = new_state
	velocity = Vector3.ZERO
	
	match _current_state:
		MoveState.GROUND:
			collider.disabled = false
			has_gravity = true
		MoveState.FLYING:
			collider.disabled = false
			has_gravity = false
		MoveState.NOCLIP:
			collider.disabled = true
			has_gravity = false

func _handle_mouse_look(relative_motion: Vector2):
	_look_rotation.y -= relative_motion.x * look_speed
	_look_rotation.x -= relative_motion.y * look_speed
	_look_rotation.x = clamp(_look_rotation.x, deg_to_rad(-max_pitch_degrees), deg_to_rad(max_pitch_degrees))
	
	transform.basis = Basis()
	rotate_object_local(Vector3.UP, _look_rotation.y)
	head.rotation.x = _look_rotation.x

func capture_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_mouse_captured = true

func release_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_mouse_captured = false

func check_input_mappings():
	var actions = {
		"Movement": [can_move, [input_left, input_right, input_forward, input_back]],
		"Jumping": [can_jump, [input_jump]],
		"Sprinting": [can_sprint, [input_sprint]],
		"Flying": [can_fly, [input_fly_down]],
		"Noclip": [can_noclip, [input_noclip_toggle]]
	}
	
	for feature in actions:
		var enabled = actions[feature][0]
		var action_names = actions[feature][1]
		if enabled:
			for action_name in action_names:
				if not InputMap.has_action(action_name):
					push_warning("%s disabled. No InputAction found for: %s" % [feature, action_name])
					break

# ===== 改进的阶梯系统 =====

func _attempt_step_up(move_dir: Vector3) -> void:
	"""尝试爬上前方的方块"""
	if not is_on_floor():
		return
	
	# 只有在有水平移动时才尝试爬阶梯
	var horizontal_dir = (move_dir * Vector3(1, 0, 1)).normalized()
	if horizontal_dir.length() < 0.5:
		return
	
	# 1. 检查前方是否被挡住
	var check_distance = 0.15
	if not test_move(global_transform, horizontal_dir * check_distance):
		return # 没有被挡住
	
	# 2. 扫描上方找到台阶高度
	var step_height_found = _scan_step_height(horizontal_dir)
	
	if step_height_found > 0.0 and step_height_found <= step_height:
		# 3. 开始平滑的阶梯上升动画
		_start_step_up(horizontal_dir, step_height_found)

func _scan_step_height(direction: Vector3) -> float:
	"""扫描前方找到可以爬上去的台阶高度，返回高度值或0"""
	var scan_distance = 0.2
	var step_increment = 0.05
	var max_scan_height = step_height
	
	var current_height = step_increment
	
	while current_height <= max_scan_height:
		var up_offset = Vector3(0, current_height, 0)
		var test_pos = global_transform.translated(up_offset)
		
		# 检查该高度是否会穿过天花板
		if test_move(global_transform, up_offset):
			return 0.0 # 头会撞到天花板
		
		# 检查该高度是否可以向前走
		if not test_move(test_pos, direction * scan_distance):
			# 找到了可以站立的高度
			return current_height
		
		current_height += step_increment
	
	return 0.0 # 没找到合适的高度

func _start_step_up(direction: Vector3, height: float) -> void:
	"""开始阶梯平滑上升"""
	_stepping_up = true
	_step_start_pos = global_position
	_step_target_height = height
	
	# 计算目标位置：上升 + 向前推进
	_step_target_pos = _step_start_pos + Vector3(0, height, 0) + direction * 0.1
	
	_step_elapsed_time = 0.0
	velocity = Vector3.ZERO # 停止现有的速度

func _update_step_smoothing(delta: float) -> void:
	"""平滑地从起点移动到目标点"""
	_step_elapsed_time += delta
	
	# 使用缓动函数实现平滑的曲线运动
	var progress = clamp(_step_elapsed_time / step_smooth_time, 0.0, 1.0)
	
	# 使用平滑的缓动曲线（ease-out）
	var eased_progress = _ease_out_cubic(progress)
	
	# 在起点和目标点之间插值
	global_position = _step_start_pos.lerp(_step_target_pos, eased_progress)
	
	# 检查是否完成
	if progress >= 1.0:
		_stepping_up = false
		global_position = _step_target_pos
		velocity = Vector3.ZERO

func _ease_out_cubic(t: float) -> float:
	"""缓出三次方函数，提供自然的减速运动"""
	var t_normalized = t - 1.0
	return t_normalized * t_normalized * t_normalized + 1.0

# 也可以选择其他缓动函数：
# func _ease_in_out_cubic(t: float) -> float:
#     if t < 0.5:
#         return 4.0 * t * t * t
#     else:
#         var t_norm = 2.0 * t - 2.0
#         return 0.5 * t_norm * t_norm * t_norm + 1.0
#
# func _ease_out_quad(t: float) -> float:
#     return 1.0 - (1.0 - t) * (1.0 - t)

func _toggle_brush_size() -> void:
	if _brush_size == 4:
		_brush_size = 2
		print("Brush size: 2x2x2 (0.5m)")
	elif _brush_size == 2:
		_brush_size = 1
		print("Brush size: 1x1x1 (0.25m)")
	elif _brush_size == 1:
		_brush_size = 4
		print("Brush size: 4x4x4 (1m)")

var _last_interact_time: float = 0.0
var _interact_delay: float = 0.2 # 200ms delay between interactions

func _can_interact_delay() -> bool:
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - _last_interact_time > _interact_delay:
		_last_interact_time = current_time
		return true
	return false

func _handle_interaction() -> void:
	if not raycast.is_colliding():
		_highlighter.visible = false
		# print("Raycast not colliding") 
		return
		
	var _hit_collider = raycast.get_collider()
	# print("Hit: ", _hit_collider.name) 
	
	var hit_point = raycast.get_collision_point()
	var normal = raycast.get_collision_normal()
	
	# Debug print every 60 frames or so to avoid spam, or just rely on the fact that if we see it, it works.
	# print("Hit at: ", hit_point, " Normal: ", normal)
	
	# Move slightly into the block to get the coordinate of the block we hit
	var block_pos_global = hit_point - (normal * (Constants.VOXEL_SIZE * 0.5))
	
	# Snap to voxel grid
	var vx = floor(block_pos_global.x / Constants.VOXEL_SIZE)
	var vy = floor(block_pos_global.y / Constants.VOXEL_SIZE)
	var vz = floor(block_pos_global.z / Constants.VOXEL_SIZE)
	
	# Center the brush on the hit voxel
	var offset = int(_brush_size / 2)
	var bx = vx - offset
	var by = vy - offset
	var bz = vz - offset
	
	var highlight_pos = Vector3(bx, by, bz) * Constants.VOXEL_SIZE
	
	# Collect existing voxels in the selection
	var existing_voxels: Array[Vector3] = []
	var world = get_tree().current_scene
	
	# Center offset for BoxMesh (since BoxMesh origin is center)
	# We want the offset in "voxel units" to add to x,y,z
	var center_offset_normalized = Vector3(0.5, 0.5, 0.5)
	
	for x in range(_brush_size):
		for y in range(_brush_size):
			for z in range(_brush_size):
				var loop_vx = bx + x
				var loop_vy = by + y
				var loop_vz = bz + z
				
				# Check if voxel exists (not air)
				if world.has_method("get_voxel_at"):
					var block_id = world.get_voxel_at(Vector3i(loop_vx, loop_vy, loop_vz))
					if block_id != Constants.AIR_BLOCK_ID:
						existing_voxels.append(Vector3(x, y, z) + center_offset_normalized)
	
	_highlighter.visible = true
	_highlighter.update_voxels(highlight_pos, existing_voxels)
	
	# Handle Input
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): # Destroy
		if _can_interact_delay():
			_modify_voxels(Vector3(bx, by, bz), Constants.AIR_BLOCK_ID)
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT): # Place
		if _can_interact_delay():
			# For placement, we need to calculate the position adjacent to the hit face
			# But wait, if we are snapping to a 4x4 grid, simply moving by normal * brush_size might not align perfectly if we are at the edge of a chunk?
			# Actually, we should probably use the face normal to determine which "grid cell" to place in.
			# Re-calculate for placement based on normal
			var place_pos_global = hit_point + (normal * (Constants.VOXEL_SIZE * 0.5))
			var pvx = floor(place_pos_global.x / Constants.VOXEL_SIZE)
			var pvy = floor(place_pos_global.y / Constants.VOXEL_SIZE)
			var pvz = floor(place_pos_global.z / Constants.VOXEL_SIZE)
			
			var p_offset = int(_brush_size / 2)
			var pbx = pvx - p_offset
			var pby = pvy - p_offset
			var pbz = pvz - p_offset
			
			# Default to Stone for now, or use a selected block
			_modify_voxels(Vector3(pbx, pby, pbz), 1) # 1 = Stone

func _modify_voxels(start_voxel: Vector3, block_id: int) -> void:
	# We need to find which chunk(s) these voxels belong to.
	# Since we might cross chunk boundaries, we should handle this carefully.
	# For simplicity, let's assume we can access the world or use a global helper.
	# But we don't have one.
	# We can try to get the chunk from the collider if we hit one.
	# However, for placement, we might be placing into AIR, so we might not hit the chunk we are placing into.
	# We need a way to get a chunk at a specific world position.
	# Let's assume the RandomWorld is the parent of the chunks and we can find it.
	var world = get_tree().current_scene
	if world.has_method("get_chunk_at"):
		# We need to implement get_chunk_at in RandomWorld
		pass
	
	# Fallback: Iterate through all voxels and find their chunk
	# This is slow but works for now.
	# Better: Calculate chunk coord from voxel coord.
	
	var chunks_to_update = {}
	
	for x in range(_brush_size):
		for y in range(_brush_size):
			for z in range(_brush_size):
				var vx = int(start_voxel.x) + x
				var vy = int(start_voxel.y) + y
				var vz = int(start_voxel.z) + z
				
				var cx = floor(vx / float(Constants.CHUNK_SIZE))
				var cz = floor(vz / float(Constants.CHUNK_SIZE))
				var chunk_key = Vector2i(cx, cz)
				
				# Local voxel coordinates
				var lx = vx % Constants.CHUNK_SIZE
				var lz = vz % Constants.CHUNK_SIZE
				if lx < 0: lx += Constants.CHUNK_SIZE
				if lz < 0: lz += Constants.CHUNK_SIZE
				
				# Find chunk
				# We need access to the world's chunk map.
				# Let's assume we can call a function on the main scene.
				if world.has_method("set_voxel_at"):
					world.set_voxel_at(Vector3i(vx, vy, vz), block_id)
					chunks_to_update[chunk_key] = true

	# Request mesh updates
	if world.has_method("update_chunks"):
		world.update_chunks(chunks_to_update.keys())
