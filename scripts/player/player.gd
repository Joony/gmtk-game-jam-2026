extends CharacterBody3D

# Source-engine-style (Half-Life 2 / Portal) movement: Quake-derived
# friction-then-accelerate on ground, capped air-acceleration enabling
# air-strafe / bunny-hop. Ported from the Doortal project.
#
# Camera / mouse-look lives in camera_controller.gd on the CameraRig node; yaw is
# applied to this body, so wishdir is computed from the body basis.

@export var max_speed := 7.0
@export var ground_accel := 10.0
@export var friction := 6.0
@export var stop_speed := 1.5
@export var air_accel := 40.0
@export var air_speed_cap := 0.8
@export var jump_velocity := 5.0
@export var gravity := 18.0

# Pure movement helpers (no physics step, unit-tested headlessly).

static func apply_friction(horiz_vel: Vector3, friction: float, stop_speed: float, delta: float) -> Vector3:
	var speed := horiz_vel.length()
	if speed < 0.0001:
		return Vector3.ZERO
	var control := maxf(speed, stop_speed)
	var drop := control * friction * delta
	var new_speed := maxf(speed - drop, 0.0)
	return horiz_vel * (new_speed / speed)


static func accelerate(horiz_vel: Vector3, wishdir: Vector3, wishspeed: float, accel: float, delta: float) -> Vector3:
	var current := horiz_vel.dot(wishdir)
	var addspeed := wishspeed - current
	if addspeed <= 0.0:
		return horiz_vel
	var accel_speed := minf(accel * wishspeed * delta, addspeed)
	return horiz_vel + wishdir * accel_speed


func _physics_process(delta: float) -> void:
	var input_dir := Input.get_vector("left", "right", "forward", "back")
	var wishdir: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y))
	wishdir.y = 0.0
	wishdir = wishdir.normalized() if wishdir.length() > 0.0 else Vector3.ZERO

	var horiz := Vector3(velocity.x, 0, velocity.z)
	var grounded := is_on_floor()

	var just_jumped := false
	if grounded and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
		just_jumped = true

	if grounded and not just_jumped:
		horiz = apply_friction(horiz, friction, stop_speed, delta)
		horiz = accelerate(horiz, wishdir, max_speed, ground_accel, delta)
	else:
		horiz = accelerate(horiz, wishdir, air_speed_cap, air_accel, delta)

	if not grounded:
		velocity.y -= gravity * delta

	velocity.x = horiz.x
	velocity.z = horiz.z

	move_and_slide()
