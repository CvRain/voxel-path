# ProtoController v2.0 by Brackeys & CvRain
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
@export var input_fly_down: String = "sprint" # In fly mode, sprint key becomes fly_down
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
			print("Player Pos: %s | Rot: %s" % [global_position, rotation_degrees])

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
			_set_state(MoveState.FLYING) # Toggle back to flying
		else:
			_set_state(MoveState.NOCLIP)

	# --- State Logic ---
	match _current_state:
		MoveState.GROUND:
			_ground_physics(delta)
		MoveState.FLYING:
			_flying_physics(delta)
		MoveState.NOCLIP:
			_flying_physics(delta) # Reuse flying physics for noclip

# --- State Implementations ---
func _ground_physics(delta: float):
	var vel := velocity
	
	# Apply gravity
	if has_gravity and not is_on_floor():
		vel.y -= _gravity * delta

	# Handle jumping - 连续跳跃逻辑
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


func _flying_physics(delta: float):
	var vel := velocity
	
	# Get input direction (3D)
	var input_dir_2d := Input.get_vector(input_left, input_right, input_forward, input_back)
	var move_dir := (head.global_basis * Vector3(input_dir_2d.x, 0, input_dir_2d.y)).normalized() # 移除 - 符号
	
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
			collider.disabled = false # Enable collision for normal flying
			has_gravity = false
		MoveState.NOCLIP:
			collider.disabled = true # Disable collision for noclip
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
					# You might want to disable the feature here, e.g., can_move = false
					break
