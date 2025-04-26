extends CharacterBody3D

@onready var camera: Camera3D = $FPCamera
@onready var speed_label: Label = $Control/Speed
@onready var grapple = $FPCamera/GrappleHookCheck
@onready var speed_multi = 0.7
@onready var max_bounce_force = 25
@onready var mouse_sens = 0.01
@onready var camera_fov = 90
@onready var raycast = $FPCamera/Arm
var friction: float = 5
var accel: float = 20 
var accel_air: float = 40  # 4 for Quake 2/3, 40 for Quake 1/Source
var top_speed_ground: float = 30 
var top_speed_air: float = 5 # 15 for Quake 2/3, 2.5 for Quake 1/Source
var lin_friction_speed: float = 10
var jump_force: float = 11
var projected_speed: float = 0
var grounded_prev: bool = true
var grounded: bool = true
var wish_dir: Vector3 = Vector3.ZERO
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_punching = false
var isin_menu = false
var frozen = false
@export var health = 150
#wall variables
var is_wall_running = false
var wall_normal = Vector3.ZERO
var wall_contact_position = Vector3.ZERO
@export var spawns: PackedVector3Array = ([
	Vector3(-18, 0.2, 0),
	Vector3(18, 0.2, 0),
	Vector3(-2.8, 0.2, -6),
	Vector3(-17,0,17),
	Vector3(17,0,17),
	Vector3(17,0,-17),
	Vector3(-17,0,-17)
])
@export var player_id := 1:
	set(id):
		player_id = id
#Sliding
var is_sliding: bool = false
var slide_speed: float = 0
var slide_timer: float = 0
var slide_duration: float = 1.0  # How long the slide lasts
var slide_friction: float = 10  # How fast speed decrease
var slide_camera_offset := 0.5  # How much the camera moves down
var slide_camera_tilt := 10.0  # How much the camera tilts
var camera_lerp_speed := 5.0  # Speed of transition
#Ground Slam
@export var gravity_multiplier: float = 6  # Increases fall speed
@export var bounce_multiplier: float = 1.2 # Bounce height scaling
@export var min_move_distance: float = 2.0  # Distance player must move before slamming again
var is_ground_slamming = false
var can_slam = true  # Prevents instant re-slam
var impact_speed = 0.0  # Tracks downward velocity before bounce
var slam_force = 0.0
var last_position = Vector3.ZERO  # Tracks movement distance
func _enter_tree() -> void:
	set_multiplayer_authority(str(name).to_int())
func _ready() -> void:
	if not is_multiplayer_authority():
		# Hide UI and stop processing it on remote players
		$Control.visible = false
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		camera.current = true
		position = spawns[randi() % spawns.size()]

func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority(): return
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		frozen = true
	else: 
		frozen = false
	if !frozen:
		if event is InputEventMouseButton and isin_menu == false:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		elif event.is_action_pressed("ui_cancel"):
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			if event is InputEventMouseMotion:
				self.rotate_y(-event.relative.x * mouse_sens)
				camera.rotate_x(-event.relative.y * mouse_sens)
				camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))
				camera.rotation.z = clamp(camera.rotation.z, deg_to_rad(-90), deg_to_rad(90))
		if Input.is_action_just_pressed("punch"):
			$FPCamera/Arms/AnimationPlayer.play("Punch")
				
		if Input.is_action_just_pressed("slide") and is_on_floor():  # Replace with your slide key
			start_slide()
		elif Input.is_action_just_pressed("slam") and !is_on_floor():
			ground_slam()
	#if Input.is_action_just_pressed("esc") and isin_menu == false:
		#$Menu.visible = true
		#$FPCamera/Arms/AnimationPlayer.stop()
		#frozen = true
		#$Menu.process_mode = Node.PROCESS_MODE_ALWAYS  # Allow menu to work while paused
		#get_tree().paused = true
		#Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		#isin_menu = true  # Mark that we are in the menu
	elif Input.is_action_just_pressed("esc") and isin_menu == true:
		$Menu.visible = false
		update_settings()
		frozen = false
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		isin_menu = false  # Mark that we are no longer in the menu
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	
func update_settings():
	if not is_multiplayer_authority(): return
	speed_multi = $"Menu/Sprint multiplier".value
	max_bounce_force = $"Menu/Max_Ground_Slam".value
	mouse_sens = $"Menu/Mouse Sensitivity".value/100
	camera_fov = $Menu/Fov.value
func _process(delta: float) -> void:
	if not is_multiplayer_authority(): return
	update_score(delta)
	camera.fov = camera_fov
func clip_velocity(normal: Vector3, overbounce: float, delta) -> void:
	if not is_multiplayer_authority(): return
	var correction_amount: float = velocity.normalized().dot(normal) * overbounce
	velocity -= normal * correction_amount
	velocity.y -= normal.y * (gravity / 20)

func apply_friction(delta):
	if not is_multiplayer_authority(): return
	var current_speed: float = velocity.length()
	if current_speed < 0.1:
		velocity.x = 0
		velocity.y = 0
		return
	
	var friction_curve = clampf(current_speed, lin_friction_speed, INF)
	var speed_loss = friction_curve * friction * delta
	var speed_scalar = clampf(current_speed - speed_loss, 0, INF) / max(current_speed, 1)
	
	velocity *= speed_scalar

func apply_acceleration(acceleration: float, top_speed: float, delta):
	if not is_multiplayer_authority(): return
	var speed_remaining = (top_speed * wish_dir.length()) - projected_speed
	if speed_remaining <= 0:
		if is_on_floor() and !is_punching:
			$FPCamera/Arms/AnimationPlayer.play("move")
		return

	var accel_final = clampf(acceleration * delta * top_speed, 0, speed_remaining)
	velocity.x += accel_final * wish_dir.x
	velocity.z += accel_final * wish_dir.z
	if is_on_floor() and !is_punching:
		$FPCamera/Arms/AnimationPlayer.play("move")

func air_move(delta):
	if not is_multiplayer_authority(): return
	apply_acceleration(accel_air, top_speed_air, delta)
	clip_velocity(get_wall_normal(), 14, delta)
	clip_velocity(get_floor_normal(), 14, delta)
	velocity.y -= gravity * delta

func ground_move(delta):
	if not is_multiplayer_authority(): return
	floor_snap_length = 0.4
	apply_acceleration(accel, top_speed_ground, delta)

	if Input.is_action_pressed("jump") and is_on_floor():
		velocity.y = jump_force
		if !is_punching:
			$FPCamera/Arms/AnimationPlayer.play("In_Air")

	if grounded == grounded_prev:
		apply_friction(delta)

	if is_on_wall():
		clip_velocity(get_wall_normal(), 1, delta)
func wall_jump():
	if not is_multiplayer_authority(): return
	if is_on_wall():
		velocity.y = 0  # Cancel gravity
		velocity = wall_normal * 10  # Stronger push to stick to the wall
	elif not is_on_wall():
		return

	var _wall_normal = get_wall_normal()
	var camera_forward = -camera.global_transform.basis.z.normalized()

	# Ignore angles and just use the camera's forward direction
	var jump_direction = (camera_forward + Vector3.UP * 0.5).normalized()
	velocity = jump_direction * jump_force * 2
func _physics_process(delta):
	if multiplayer.multiplayer_peer != null:
		if not is_multiplayer_authority(): return
	if !frozen:
		$states.play("area_flicker")
		grounded_prev = grounded
		var input_dir: Vector2 = Input.get_vector("left", "right", "forward", "backward")
		wish_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		projected_speed = (velocity * Vector3(1, 0, 1)).dot(wish_dir)
		punch()
		speed_label.text = str(int((velocity * Vector3(1, 0, 1)).length()))
		#Global.speed = int((velocity * Vector3(1, 0, 1)).length())
		var sprint = Input.is_action_pressed("ui_sprint")
		
		if sprint:
			accel = 9 * speed_multi
			accel_air = 15 * speed_multi
			top_speed_air = 6 * speed_multi
			top_speed_ground = 25 * speed_multi
			camera.fov = lerp(camera.fov as float, 130.0, 0.05)
			jump_force = 12
		else:
			accel = 6 * speed_multi
			accel_air = 8 * speed_multi
			top_speed_air = 3 * speed_multi
			top_speed_ground = 20 * speed_multi
			camera.fov = lerp(camera.fov as float, 110.0, 0.05)
			jump_force = 11

		if not is_on_floor():
			grounded = false
			air_move(delta)
			if !is_punching:
				$FPCamera/Arms/AnimationPlayer.play("In_Air")
		else:
			if velocity.y > 10:
				grounded = false
				air_move(delta)
			else:
				grounded = true
				ground_move(delta)

		if is_on_wall() and Input.is_action_just_pressed("jump"):
			wall_jump()

		if is_sliding:
			slide_timer -= delta
			velocity *= 1.0 - (slide_friction * delta)  # Reduce speed over time
			if slide_timer <= 0 or velocity.length() < 2:  # Stop when slow
				stop_slide()
			else:
				if Input.is_action_just_pressed("jump"):  # Jump while sliding
					velocity = transform.basis.z * -slide_speed  # Keep stored speed
					velocity.y = jump_force  # Launch upwards
					stop_slide()

		if not is_on_floor():
			impact_speed = velocity.y  # Track last fall speed

		move_and_slide() 

		if is_ground_slamming and is_on_floor():
			bounce_up()

		# Check if player has moved enough after landing to allow another slam
		if not can_slam:
			check_movement_for_reset()














func start_slide():
	if not is_multiplayer_authority(): return
	if is_sliding or not is_on_floor():
		return

	is_sliding = true
	slide_timer = slide_duration
	slide_speed = velocity.length() * 3  # Store current speed

	# Lower & tilt camera slightly
	$States.play("Slide_IN")

	# Set initial slide velocity in movement direction
	velocity = (transform.basis.z * -slide_speed).normalized() * (slide_speed * 2)

func stop_slide():
	if not is_multiplayer_authority(): return
	if not is_sliding:
		return

	is_sliding = false

	# Reset camera position & rotation
	$States.play("Slide_OUT")

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if  anim_name == "Punch":
		is_punching = false


func _on_player_area_entered(area: Area3D) -> void:
	if not is_multiplayer_authority(): return
	if area.name == "Death":
		call_deferred("queue_free")
	if area.name == "Hit":
		update_health()
	
func punch():
	if Input.is_action_just_pressed("punch"):
		if raycast.is_colliding() && str(raycast.get_collider()).contains("CharacterBody3D") :
			var hit_player: Object = raycast.get_collider()
			hit_player.update_health.rpc_id(hit_player.get_multiplayer_authority())
		is_punching = true
		
func ground_slam():
	if not is_multiplayer_authority(): return
	if can_slam and not is_on_floor() and not is_ground_slamming:
		is_ground_slamming = true
		can_slam = false  # Disable re-slam until movement is detected
		slam_force = abs(velocity.length()) * 4
		velocity = Vector3.ZERO
		velocity.y = -slam_force

func bounce_up():
	if not is_multiplayer_authority(): return
	$States.play("Slam_Land")
	is_ground_slamming = false
	var bounce_force = abs(impact_speed) * bounce_multiplier
	bounce_force = min(bounce_force, max_bounce_force)  # Cap bounce speed
	velocity.y = bounce_force * bounce_multiplier
	last_position = global_position  # Save position for movement check

func check_movement_for_reset():
	if not is_multiplayer_authority(): return
	if global_position.distance_to(last_position) >= min_move_distance:
		can_slam = true  # Allow slamming again


func _on_shaders_toggled(toggled_on: bool) -> void:
	pass
	#if toggled_on == true:
		#camera.environment = load("res://Shader_On.tres")
	#elif toggled_on == false:
		#camera.environment = load("res://Shader_Off.tres")
		
@rpc("any_peer","call_local")
func update_health(damage:= 10):
	if not is_multiplayer_authority(): return
	health = clamp(health,0,150)
	if health > 0:
		health -= damage
		$states.play("Hurt")
	elif health <= 0:
		position = spawns[randi() % spawns.size()]
		health += 150
	$Control/Health.text = str(health) + "/150"
func update_score(delta):
	pass
	#$Control/Score.text = str(Global.score) + "/100"


func _on_fps_boost_toggled(toggled_on: bool) -> void:
	if toggled_on == true:
		camera.far = 250
	elif toggled_on == false:
		camera.far = 4000
