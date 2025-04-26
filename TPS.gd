extends CharacterBody3D

@export var acceleration := 3.0
@export var max_speed := 18
@export var deceleration := 10.0
@export var turn_speed := 145.0  # degrees per second
@export var gravity := Vector3.DOWN * 9.8
@export var desired_turn_radius := 5.0 # smaller = tighter turn
var current_speed := 0.0
var move_input := 0.0  # -1 for back, 1 for forward
var is_moving = false
const JUMP = 5
@onready var cam_pivot := $CameraPivot
@export var max_tilt_angle := 10.0 # degrees
@export var tilt_speed := 5.0 # how fast the tilt reacts
@export var turn_speed_boost := 60.0 # added at max speed
@export var base_turn_speed := 90.0
@export var max_turn_speed := 145.0
@onready var camera := $CameraPivot/SpringArm3D/FPCamera

func _physics_process(delta):
	if not is_multiplayer_authority(): return
	handle_input(delta)
	apply_movement(delta)
	update_camera_tilt(delta)
@export var player_id := 1:
	set(id):
		player_id = id
func _enter_tree() -> void:
	set_multiplayer_authority(str(name).to_int())
	$Model/Label3D.text = name
func _ready() -> void:
	if is_multiplayer_authority():
		camera.current = true
	else:
		camera.current = false
func handle_input(delta):
	if not is_multiplayer_authority(): return
	move_input = 0.0
	var speed_ratio: float = clamp(current_speed / max_speed, 0.0, 1.0)
	var dynamic_turn_speed: float = lerp(base_turn_speed, max_turn_speed, speed_ratio)

	if Input.is_action_pressed("forward"):
		move_input = 1.0
		is_moving = true
	elif Input.is_action_pressed("backward"):
		move_input = -1.0
		is_moving = true

	# Turning logic

	var angular_velocity = current_speed / desired_turn_radius
	var angular_velocity_deg = rad_to_deg(angular_velocity)
	if current_speed < 5:
		desired_turn_radius = 2.5
	else:
		desired_turn_radius = 5
	if Input.is_action_pressed("left"):
		cam_pivot.rotate_y(deg_to_rad(angular_velocity_deg * delta))
	elif Input.is_action_pressed("right"):
		cam_pivot.rotate_y(deg_to_rad(-angular_velocity_deg * delta))

	if velocity.length() < 0.1:
		is_moving = false

func apply_movement(delta):
	if not is_multiplayer_authority(): return
	var forward: Vector3 = cam_pivot.global_transform.basis.z
	var direction: Vector3 = forward.normalized() * move_input
	var target_angle: float = atan2(forward.x, forward.z)
	$Model.rotation.y = target_angle

	# Accelerate or decelerate based on input
	if move_input != 0.0:
		current_speed = move_toward(current_speed, max_speed, acceleration * delta)
	else:
		current_speed = move_toward(current_speed, 0.0, deceleration * delta)

	# Calculate desired velocity in the horizontal direction
	var horizontal_velocity = direction * current_speed

	# Only modify X and Z (horizontal) components, keep Y from gravity
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	if Input.is_action_just_pressed("ui_accept"):
		velocity.y = JUMP
	# Apply gravity
	velocity.y += gravity.y * delta

	# Move the character
	move_and_slide()

	# Rotate player
func update_camera_tilt(delta):
	if not is_multiplayer_authority(): return
	# Compute tilt angle based on speed ratio
	var speed_ratio := current_speed / max_speed
	var base_tilt: float = lerp(0.0, max_tilt_angle, speed_ratio)

	# Determine turning direction
	var tilt_direction := 0.0
	if Input.is_action_pressed("left"):
		tilt_direction = 0.5
	elif Input.is_action_pressed("right"):
		tilt_direction = -0.5

	# Boost model tilt based on turning *and* speed
	var camera_tilt_target = deg_to_rad(base_tilt * tilt_direction)
	var model_tilt_target = deg_to_rad((base_tilt + 8.0) * -tilt_direction)  # Extra 10 degrees for style

	# Interpolate camera pivot tilt
	var cam_rot_z = cam_pivot.rotation.z
	cam_pivot.rotation.z = lerp_angle(cam_rot_z, camera_tilt_target, tilt_speed * delta)

	# Interpolate model tilt more dramatically
	var model_rot_z = $Model.rotation.z
	$Model.rotation.z = lerp_angle(model_rot_z, model_tilt_target, tilt_speed * delta)
