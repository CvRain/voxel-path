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

# --- Godot Lifecycle ---
func _ready() -> void:
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
	check_input_mappings()
	
	_look_rotation.y = rotation.y
	_look_rotation.x = head.rotation.x
	
	capture_mouse()

func _input(event: InputEvent) -> void:
	if Input.is_key_pressed(KEY_ESCAPE):
		release_mouse()
		
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not _mouse_captured:
		capture_mouse()

	if _mouse_captured and event is InputEventMouseMotion:
		_handle_mouse_look(event.relative)

func _physics_process(delta: float) -> void:
	_last_jump_press += delta
	
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
