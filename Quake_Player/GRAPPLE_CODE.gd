extends Node

@export var ray: RayCast3D
@export var rope: Node3D

@export var grapple_speed = 70.0  # Initial speed at which the player is pulled toward the target
@export var max_grapple_speed = 12000.0  # Maximum speed the grapple can reach
@export var speed_increment = 10.0  # How much the speed increases per second
@export var stop_distance = 1.0  # Minimum distance to stop near the target

@onready var player: CharacterBody3D = get_parent()

var target: Vector3
var launched = false
var grapple_disabled = false

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		if Input.is_action_just_pressed("shoot") and grapple_disabled == false:
			grapple_speed = 70.0  # Reset speed when launching
			launch()
		if launched:
			move_toward_target(delta)

	update_rope()
	if player.grapple.is_colliding() and !player.is_on_floor():
		$"Control/Crosshair".visible = false
		$Control/Crosshair2.visible = true
	elif !player.grapple.is_colliding() and !player.is_on_floor():
		$"Control/Crosshair".visible = true
		$Control/Crosshair2.visible = false
@rpc
func launch():
	# Check if the raycast hits something
	if ray.is_colliding():
		target = ray.get_collision_point()
		launched = true
		player.velocity = Vector3.ZERO  # Reset velocity to avoid interference

func retract():
	# Stop grappling and reset speed
	launched = false
	rope.visible = false  # Make the rope disappear
	grapple_speed = 60.0  # Reset speed after retracting

func move_toward_target(delta: float):
	# Calculate the direction and distance to the target
	var target_dir = player.global_position.direction_to(target)
	var distance_to_target = player.global_position.distance_to(target)

	# If close enough to the target, stop moving
	if distance_to_target <= 4:
		retract()
		return

	# Increase grapple speed over time, clamped to the maximum speed
	grapple_speed = clamp(grapple_speed + (speed_increment * delta), 70.0, max_grapple_speed)

	# Apply movement toward the target
	player.velocity = target_dir * grapple_speed

	# Apply gravity so the player falls after grappling
	player.velocity.y -= 9.8 * delta

	# Use the player's move_and_slide() to integrate physics
	player.move_and_slide()

func update_rope():
	if !launched:
		rope.visible = false
		return

	rope.visible = true

	# Update the rope visuals to connect the player and the target
	var distance = player.global_position.distance_to(target)
	rope.look_at(target)
	rope.scale = Vector3(1, 1, distance)


func _on_fps_grapple_disable() -> void:
	grapple_disabled = true
