class_name CablePlug
extends Interactable

# A cable end-plug: a small carriable RigidBody3D that a Cable3D pins one rope end to.
#
# Rebased from Doortal's CablePlug (which extended PickableObject, a RigidBody3D) onto this
# project's Interactable + Carry. Two things move:
#   * Held-state is no longer self-authored. Carry freezes and drives the body; we learn we are
#     held through the on_pickup()/on_drop() hooks it calls, and expose is_held() from that flag
#     (the cable's tension/breakaway logic asks for it).
#   * Seat-on-release hooks the DROP instead of a bespoke end_hold(): releasing with a socket in
#     snap range seats the plug there rather than dropping it on the floor.
#
# The script extends Interactable (a Node3D) but is attached to a RigidBody3D node — the same
# convention pickup_crate.tscn uses. Body operations go through `_body` (self, cast once).
#
# Proximity socket snapping: while held, each render frame the plug scans the "cable_sockets"
# group for the nearest acceptable CableSocket within ITS snap_radius of the plug's position and
# lights its preview ring. Releasing with a candidate seats the plug: frozen kinematic, body
# server-set onto the socket's snap_transform(), socket claimed. Picking a seated plug back up
# unseats it first, then Carry holds it as usual. Overstretching never drops a HELD plug — the
# cable pops a SEATED end instead, calling force_unseat() here with an elastic recoil.

# Seconds after a breakaway pop during which this plug refuses to re-seat (no snap candidate
# lights, releasing never seats) — an overstretched cable must not immediately re-plug itself
# into the socket it just popped out of.
const RESEAT_COOLDOWN := 0.75
# Group every CableSocket registers in (see cable_socket.gd).
const SOCKET_GROUP := &"cable_sockets"

# Back-reference to the cable whose rope ends at this plug (set by Cable3D at its ready via the
# duck-typed `"cable" in node` probe — so the plug must expose this property by this name).
var cable: Cable3D = null

# This node, typed as the RigidBody3D it actually is (see the class comment).
var _body: RigidBody3D = null
# True while Carry is holding this plug (on_pickup/on_drop toggle it).
var _held: bool = false
# Remaining re-seat cooldown after a breakaway pop (see RESEAT_COOLDOWN).
var _reseat_cooldown: float = 0.0
# Nearest acceptable socket in snap range while held (its preview is lit).
var _snap_candidate: CableSocket = null
# The socket this plug is seated in (null while free or held).
var _seated_socket: CableSocket = null
# The socket's mount body this seated plug is collision-excepted against (the nose-in
# snap_transform overlaps the mount BY DESIGN, and the frozen plug is re-authored onto the moving
# socket every tick — without the exception the physics engine perpetually extrudes the dynamic
# mount away from the chasing kinematic plug, accelerating a plugged cube without bound).
var _mount_exception: PhysicsBody3D = null
# Last snap transform authored to the seated body, to re-author only when the socket's mount
# actually moves (e.g. a socket on a carried cube).
var _last_snap_xform := Transform3D.IDENTITY


func _ready() -> void:
	super()  # Interactable._ready: register in the interactables group
	# A cable plug is definitionally a pickup.
	interaction_type = InteractionType.PICKUP
	# This script's static base is Interactable (a Node3D); the node it is attached to is a
	# RigidBody3D. Those are sibling branches, so `self as RigidBody3D` is a compile error — the
	# cast is laundered through Node (a common ancestor), which the compiler accepts and which
	# succeeds at runtime because the node really is a RigidBody3D.
	var this_node: Node = self
	_body = this_node as RigidBody3D
	if _body == null:
		push_error("CablePlug must be attached to a RigidBody3D node")
		return
	# Contact reporting feeds the cable's contact-aware tension clamp
	# (Cable3D._receiver_touching_dynamic): while this plug is pressed against another dynamic
	# body, endpoint tension is softened so the spring can't keep feeding energy THROUGH the
	# contact (the play-reported cube shove).
	_body.contact_monitor = true
	_body.max_contacts_reported = 4


func is_held() -> bool:
	return _held


func is_seated() -> bool:
	return _seated_socket != null and is_instance_valid(_seated_socket)


func _process(_delta: float) -> void:
	_update_snap_candidate()


func _physics_process(delta: float) -> void:
	if _reseat_cooldown > 0.0:
		_reseat_cooldown = maxf(0.0, _reseat_cooldown - delta)
	_follow_seated_socket()


# Carry hook (grab() calls this AFTER it has frozen the body kinematic for the carry). Re-grabbing
# a seated plug unplugs it first: free the socket and tell the cable so it recomputes power; the
# body stays frozen (Carry wants it frozen), so this is bookkeeping only.
func on_pickup() -> void:
	if is_seated():
		var socket := _seated_socket
		_seated_socket = null
		_clear_mount_exception()
		socket.unseat()
		if cable != null:
			cable.set_endpoint_socket(self, null)
	_held = true
	super()  # Interactable.on_pickup: is_enabled = false, emit picked_up


# Carry hook (drop() calls this LAST, after it has unfrozen the body and set the release
# velocity). Releasing with a socket in snap range seats the plug there instead of dropping it.
func on_drop() -> void:
	_held = false
	super()  # Interactable.on_drop: is_enabled = true, emit dropped
	var socket := _snap_candidate
	_set_snap_candidate(null)
	if _reseat_cooldown > 0.0:
		return
	if socket != null and is_instance_valid(socket) and socket.can_accept(self):
		_seat(socket)


# The cable pops this SEATED plug loose with an elastic recoil (ADR 0046 breakaway). The
# seated-socket reference clears FIRST so _follow_seated_socket can never re-author the freed body
# onto the vacated socket; the unseat + set_endpoint_socket(null) route the power unfeed; the body
# unfreezes BEFORE the impulse (an impulse on a frozen body is a no-op); and the re-seat cooldown
# blocks an immediate re-plug.
func force_unseat(recoil: Vector3) -> void:
	if not is_seated():
		return
	var socket := _seated_socket
	_seated_socket = null
	_clear_mount_exception()
	socket.unseat()
	if cable != null:
		cable.set_endpoint_socket(self, null)
	_body.freeze = false
	_body.sleeping = false
	_body.apply_central_impulse(recoil)
	_reseat_cooldown = RESEAT_COOLDOWN


# The cable's PHYSICS pin: where the rope endpoint is constrained each tick. The body centre is
# the attachment point (v1 — no tail offset); a seated plug pins at the socket, which tracks a
# moving mount ahead of the body's tick lag.
func cable_pin() -> Vector3:
	if is_seated():
		return _seated_socket.snap_transform().origin
	return global_position


# The cable's RENDER pin. Unlike Doortal (where the held mesh was top_level and authored ahead of
# the body), our Carry authors the whole BODY's transform each render frame, so the body pose IS
# the render pose — global_position serves both held and free. A seated plug pins at the socket.
func cable_render_pin() -> Vector3:
	if is_seated():
		return _seated_socket.snap_transform().origin
	return global_position


# Seat into `socket`: freeze kinematic and hard-SERVER-set the body onto the snap transform
# (never set global_transform on the body for a teleport-style move — the node write path bounces;
# the node syncs from the server over the next tick). The velocity re-zero is deferred past
# Carry.drop's own velocity write.
func _seat(socket: CableSocket) -> void:
	_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_body.freeze = true
	_seated_socket = socket
	var mount := socket.mount_body()
	if mount != null:
		_body.add_collision_exception_with(mount)
		_mount_exception = mount
	_author_seated_body(socket.snap_transform())
	socket.seat(self)
	if cable != null:
		cable.set_endpoint_socket(self, socket)
	_body.set_deferred("linear_velocity", Vector3.ZERO)
	_body.set_deferred("angular_velocity", Vector3.ZERO)


func _clear_mount_exception() -> void:
	if _mount_exception != null and is_instance_valid(_mount_exception):
		_body.remove_collision_exception_with(_mount_exception)
	_mount_exception = null


func _author_seated_body(xform: Transform3D) -> void:
	PhysicsServer3D.body_set_state(_body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xform)
	PhysicsServer3D.body_set_state(_body.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(_body.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	_body.reset_physics_interpolation()
	_last_snap_xform = xform


# A socket can be mounted on a moving body (e.g. a socket on a carried cube): while seated,
# re-author the frozen body whenever the snap transform moves.
func _follow_seated_socket() -> void:
	if not is_seated():
		return
	var xform := _seated_socket.snap_transform()
	if not xform.is_equal_approx(_last_snap_xform):
		_author_seated_body(xform)


# While held, light the nearest acceptable socket whose snap_radius contains the plug's rendered
# position; clear the highlight otherwise. No candidate ever lights while the post-breakaway
# re-seat cooldown runs.
func _update_snap_candidate() -> void:
	if not _held or _reseat_cooldown > 0.0:
		_set_snap_candidate(null)
		return
	var pin := cable_render_pin()
	var best: CableSocket = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group(SOCKET_GROUP):
		var socket := node as CableSocket
		if socket == null or not socket.can_accept(self):
			continue
		var dist := pin.distance_to(socket.global_position)
		if dist <= socket.snap_radius and dist < best_dist:
			best_dist = dist
			best = socket
	_set_snap_candidate(best)


func _set_snap_candidate(socket: CableSocket) -> void:
	if socket == _snap_candidate:
		return
	if _snap_candidate != null and is_instance_valid(_snap_candidate):
		_snap_candidate.set_preview(false)
	_snap_candidate = socket
	if _snap_candidate != null:
		_snap_candidate.set_preview(true)
