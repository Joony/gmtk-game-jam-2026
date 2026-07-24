class_name Carry
extends Node3D

# Render-frame kinematic follow, extracted from Doortal's Carry.gd (755 lines, of
# which ~80% was portal machinery: beam forwarding through portal chains, clip-clone
# meshes, cross-room server sets, transit tick budgets). None of that applies here.
#
# What's kept is the mechanism that makes carrying feel good:
#   * while held the item is a FROZEN KINEMATIC RigidBody3D whose transform we author
#     every _process from the HoldPoint under the camera — 1:1 with the view, no
#     physics-clock lag
#   * a per-frame test_move collide-and-slide sweep so the item is pushed aside by
#     walls instead of clipping through them
#   * break-free when a wall holds the item too far from the hold point for a grace
#     period, so you can't drag things through geometry
#   * release keeps the carry velocity (capped) so items can be flung
#
# MUST run after CameraController: this node's process_priority is 10, the camera's
# is 0. Otherwise the held item renders a frame behind the view.

signal picked_up(item: Node3D)
signal dropped(item: Node3D)

## Marker the item is held at. Lives under Camera3D so it carries render-rate rotation.
@export var hold_point_path: NodePath = NodePath("../CameraRig/Camera3D/HoldPoint")
## The player body, for collision exceptions while carrying.
@export var body_path: NodePath = NodePath("..")
## Seconds to ease a newly grabbed item from where it sat to the hold point. 0 snaps.
@export var pickup_smooth_time: float = 0.2
## A wall clamp must hold the item this far from the hold point to start breaking.
@export var break_distance: float = 1.5
## ...and persist this long (seconds) before it actually drops. Brief clips recover.
@export var break_grace: float = 0.25
@export var throw_impulse: float = 6.0
## Carry velocity is kept on release so items can be flung, capped so a hard mouse
## flick can't reach tunnelling speeds.
@export var max_release_speed: float = 12.0
## Safety skin left between the swept body and geometry per test_move.
@export var cast_margin: float = 0.04

@onready var _holder: Node3D = get_node_or_null(hold_point_path)
@onready var _body: PhysicsBody3D = get_node_or_null(body_path)

var _held: RigidBody3D = null
var _held_interactable: Interactable = null
var _break_timer: float = 0.0
var _pickup_from: Transform3D = Transform3D.IDENTITY
var _pickup_t: float = 1.0
var _carry_velocity: Vector3 = Vector3.ZERO
var _prev_origin: Vector3 = Vector3.ZERO
var _prior_gravity_scale: float = 1.0


func _ready() -> void:
	# Must tick after CameraController has written the rig transform for this frame.
	process_priority = 10
	# So a held item can find its carrier (e.g. CablePlug asks to be dropped on overstretch).
	add_to_group(&"carries")


func is_holding() -> bool:
	return _held != null


func held_item() -> Node3D:
	return _held


func grab(interactable: Interactable) -> bool:
	if _held != null or interactable == null or _holder == null:
		return false
	var item := interactable.get_item_node() as RigidBody3D
	if item == null:
		push_warning("Carry.grab: %s is PICKUP but its item node is not a RigidBody3D" % interactable.name)
		return false

	_held = item
	_held_interactable = interactable
	_break_timer = 0.0
	_prior_gravity_scale = item.gravity_scale

	if _body != null:
		item.add_collision_exception_with(_body)
	item.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	item.freeze = true
	# The transform is authored verbatim each render frame; interpolating it would
	# fight that and smear the item behind the view.
	item.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	# Ease from where it sat rather than snapping it to the face.
	_pickup_from = item.global_transform
	_pickup_t = 0.0 if pickup_smooth_time > 0.0 else 1.0
	_prev_origin = item.global_transform.origin
	_carry_velocity = Vector3.ZERO

	interactable.on_pickup()
	picked_up.emit(item)
	return true


func drop(throw_it: bool = false) -> void:
	if _held == null:
		return
	var item := _held
	_held = null
	_break_timer = 0.0

	# Unfreeze BEFORE setting velocity — a frozen body ignores it.
	item.freeze = false
	item.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	item.reset_physics_interpolation()
	# Jolt derives a wild velocity from the kinematic transform deltas; replace it
	# with our own smoothed, capped estimate.
	item.angular_velocity = Vector3.ZERO
	item.linear_velocity = _carry_velocity.limit_length(max_release_speed)
	item.gravity_scale = _prior_gravity_scale
	if _body != null:
		item.remove_collision_exception_with(_body)
	if throw_it and _holder != null:
		item.apply_central_impulse(-_holder.global_transform.basis.z * throw_impulse)

	if _held_interactable != null:
		_held_interactable.on_drop()
		_held_interactable = null
	dropped.emit(item)


func _process(delta: float) -> void:
	if _held == null or _holder == null:
		return

	var forward := -_holder.global_transform.basis.z
	var goal := Transform3D(_upright_facing_basis(forward), _holder.global_position)

	# Pickup fly-in: ease from the grabbed pose. No break checks while easing.
	if _pickup_t < 1.0:
		_pickup_t = minf(_pickup_t + delta / pickup_smooth_time, 1.0)
		var eased := pickup_blend(_pickup_from, goal, _pickup_t)
		var fly_origin := _clamp_to_walls(_prev_origin, eased.origin, eased.basis)
		_held.global_transform = Transform3D(eased.basis, fly_origin)
		_prev_origin = fly_origin
		return

	# Break free if a wall has held the item away from the hold point for long enough.
	if _prev_origin.distance_to(goal.origin) > break_distance:
		_break_timer += delta
		if _break_timer >= break_grace:
			drop(false)
		return
	_break_timer = 0.0

	var clamped := _clamp_to_walls(_prev_origin, goal.origin, goal.basis)
	_held.global_transform = Transform3D(goal.basis, clamped)
	if delta > 0.0:
		# Smoothed so a single stuttery frame doesn't produce a silly release velocity.
		_carry_velocity = _carry_velocity.lerp((clamped - _prev_origin) / delta, 0.5)
	_prev_origin = clamped


# Sweep the held body from `origin` toward `desired` using its own shapes. test_move
# honours the item's collision mask AND the player exception, so it stops at and slides
# along walls without colliding with its carrier. Only translation is swept; rotation
# follows the camera directly.
func _clamp_to_walls(origin: Vector3, desired: Vector3, basis: Basis) -> Vector3:
	if _held == null:
		return desired
	var cur := origin
	var motion := desired - cur
	var collision := KinematicCollision3D.new()
	for _i in 4:
		if motion.length() < 1e-5:
			break
		if _held.test_move(Transform3D(basis, cur), motion, collision, cast_margin):
			cur += collision.get_travel()
			motion = collision.get_remainder().slide(collision.get_normal())
		else:
			cur += motion
			break
	return cur


# Keep the item upright and yaw it with the view, so looking up and down doesn't
# tip it over. (Doortal mapped local +Z to world up for its cube's axis convention;
# this is the general version.)
static func _upright_facing_basis(view_forward: Vector3) -> Basis:
	return Basis(Vector3.UP, atan2(-view_forward.x, -view_forward.z))


## Smoothstep-eased blend, used for the pickup fly-in. t<=0 is `from`, t>=1 exactly `to`.
static func pickup_blend(from: Transform3D, to: Transform3D, t: float) -> Transform3D:
	var f := clampf(t, 0.0, 1.0)
	f = f * f * (3.0 - 2.0 * f)
	return Transform3D(from.basis.slerp(to.basis, f), from.origin.lerp(to.origin, f))
