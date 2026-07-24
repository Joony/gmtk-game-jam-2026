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
# A seated plug's body sits this far OUT along the socket's +Z, so its prongs go into the
# receptacle while its body stays OUTSIDE the socket/mount — otherwise a plug seated in the
# battery's face socket buried itself in the cube. (A wall plug just sits proud of the wall.)
const SEAT_STANDOFF := 0.18
# Group every CableSocket registers in (see cable_socket.gd).
const SOCKET_GROUP := &"cable_sockets"

# A FIXED plug is bolted to the ship: it starts permanently seated in `fixed_socket_path`,
# is never a pickup target (is_enabled stays false), and never pops (force_unseat is a no-op).
# So the player only ever handles the OTHER, free end of the cable.
@export var fixed: bool = false
@export var fixed_socket_path: NodePath

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
	# Tick AFTER Carry (priority 10): when this plug is seated in a socket on a CARRIED body (the
	# battery), Carry moves that body each render frame, and we must re-read the socket and re-author
	# this plug in the SAME frame — otherwise the plug renders a step behind the battery.
	process_priority = 20
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

	if fixed:
		# Freeze immediately so it can't fall in the frame before the deferred seat authors it
		# onto the socket. The seat is deferred because it needs the cable back-ref (set in
		# Cable3D._ready) and the socket's own _ready to have run first.
		_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		_body.freeze = true
		is_enabled = false  # a bolted-in end is never a ray target
		_seat_fixed.call_deferred()


# Seat a `fixed` plug into its bolted socket at startup. Idempotent-safe: only seats a free
# socket, and does nothing if already seated.
func _seat_fixed() -> void:
	if is_seated():
		return
	var socket := get_node_or_null(fixed_socket_path) as CableSocket
	if socket == null:
		push_error("CablePlug.fixed is set but fixed_socket_path did not resolve to a CableSocket")
		return
	if socket.can_accept(self):
		_seat(socket)


func is_held() -> bool:
	return _held


# Explicitly seat this plug into `socket`, dropping it from the player's hands first if held. This
# is the look-and-press route (a USE_ITEM target like the battery calls it), as opposed to nosing
# the plug into snap range and releasing. Returns whether it seated.
func plug_into(socket: CableSocket) -> bool:
	if socket == null or not socket.can_accept(self) or is_seated():
		return false
	if is_held():
		# Clear any snap candidate so on_drop (fired inside Carry.drop) can't seat us elsewhere.
		_set_snap_candidate(null)
		var carrier := _carrier_holding_self()
		if carrier != null:
			carrier.drop(false)
	if is_seated():
		return true  # already handled by on_drop (shouldn't happen with the candidate cleared)
	_seat(socket)
	return true


func is_seated() -> bool:
	return _seated_socket != null and is_instance_valid(_seated_socket)


func _process(_delta: float) -> void:
	_update_snap_candidate()
	# Track the socket at RENDER rate (see process_priority), matching how Carry authors the body it
	# is mounted on, so a plug seated in a carried battery never lags a frame behind it.
	_follow_seated_socket()


func _physics_process(delta: float) -> void:
	if _reseat_cooldown > 0.0:
		_reseat_cooldown = maxf(0.0, _reseat_cooldown - delta)


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


# The cable's overstretch release (called by Cable3D._break_away). Returns whether this end
# actually gave. A bolted-in end never does; a seated end pops out of its socket; a held end drops
# from the player's hands — but only on the second (allow_drop_held) pass, so the cable sacrifices
# a socketed end before the player's grip. In every case the plug whips back along the cable with
# `recoil` for a little elastic snap.
func break_connection(recoil: Vector3, allow_drop_held: bool) -> bool:
	if fixed:
		return false
	if is_seated():
		force_unseat(recoil)
		return true
	if allow_drop_held and is_held():
		_drop_from_carrier(recoil)
		return true
	return false


# Drop this plug out of the player's hands, then fling it toward the far end of the cable. The
# re-seat cooldown is set BEFORE the drop so on_drop() (which fires inside Carry.drop) can't
# immediately re-seat the plug into a socket it happens to be near.
func _drop_from_carrier(recoil: Vector3) -> void:
	_reseat_cooldown = RESEAT_COOLDOWN
	var carrier := _carrier_holding_self()
	if carrier != null:
		carrier.drop(false)
	_body.sleeping = false
	_body.apply_central_impulse(recoil)


# The Carry currently holding this plug, found via the "carries" group Carry registers in. There
# is normally one carrier (the player), but the held_item() check is exact regardless.
func _carrier_holding_self() -> Carry:
	for node in get_tree().get_nodes_in_group(&"carries"):
		var carry := node as Carry
		if carry != null and carry.held_item() == self:
			return carry
	return null


# The cable pops this SEATED plug loose with an elastic recoil (ADR 0046 breakaway). The
# seated-socket reference clears FIRST so _follow_seated_socket can never re-author the freed body
# onto the vacated socket; the unseat + set_endpoint_socket(null) route the power unfeed; the body
# unfreezes BEFORE the impulse (an impulse on a frozen body is a no-op); and the re-seat cooldown
# blocks an immediate re-plug.
func force_unseat(recoil: Vector3) -> void:
	if fixed:
		return  # a bolted-in end never pops, no matter how hard the cable is pulled
	if not is_seated():
		return
	var socket := _seated_socket
	_seated_socket = null
	_clear_mount_exception()
	socket.unseat()
	if cable != null:
		cable.set_endpoint_socket(self, null)
	_body.freeze = false
	# Was OFF while seated (render-rate authoring) — restore normal interpolation now it is a free
	# dynamic body again.
	_body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	_body.reset_physics_interpolation()
	_body.sleeping = false
	_body.apply_central_impulse(recoil)
	_reseat_cooldown = RESEAT_COOLDOWN


# The cable attaches at a gland just behind the plug's body centre, toward the back (the nose is
# -Z, so the back is +Z). Kept SMALL — well inside the ~0.22 m base half-extent — so the gland
# stays within the plug body at any orientation (a loose plug on the floor can point its +Z any
# way; a bigger offset floated the attach point out to the side, reading as disconnected).
# cable_exit_dir() lines the first rope segment up with the plug's axis so a held/seated plug's
# cable still comes straight out the back.
const CABLE_BACK_Z_OFFSET := 0.00
const CABLE_BACK_Y_OFFSET := 0.09

# The transform whose +Z is the plug's back: the socket while seated (so the pin tracks a moving
# mount ahead of the body's tick lag), else the body itself. Carry authors the whole body each
# render frame, so global_transform is both the physics and the render pose.
func _attach_transform() -> Transform3D:
	return _seated_body_xform() if is_seated() else global_transform


# The cable's PHYSICS pin: the back-gland world position.
func cable_pin() -> Vector3:
	return _attach_transform() * Vector3(0.0, CABLE_BACK_Y_OFFSET, CABLE_BACK_Z_OFFSET)


# The cable's RENDER pin — same gland (see _attach_transform).
func cable_render_pin() -> Vector3:
	return cable_pin()


# The world direction the cable should leave the plug: straight out the back (+Z). Zero while the
# plug is loose and tumbling (let the rope just hang); only enforced when held or seated, where the
# plug has a stable orientation to line up with.
func cable_exit_dir() -> Vector3:
	if is_seated() or is_held():
		return _attach_transform().basis.z
	return Vector3.ZERO


# Seat into `socket`: freeze kinematic and hard-SERVER-set the body onto the snap transform
# (never set global_transform on the body for a teleport-style move — the node write path bounces;
# the node syncs from the server over the next tick). The velocity re-zero is deferred past
# Carry.drop's own velocity write.
func _seat(socket: CableSocket) -> void:
	_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_body.freeze = true
	# Author at render rate like Carry (see _follow_seated_socket): interpolation OFF so the plug
	# tracks a carried socket exactly instead of lagging a physics step behind.
	_body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_seated_socket = socket
	var mount := socket.mount_body()
	if mount != null:
		_body.add_collision_exception_with(mount)
		_mount_exception = mount
	_author_seated_body(_seated_body_xform())
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


# A socket can be mounted on a moving body (a carried battery): while seated, re-author the frozen
# body onto the snap transform whenever it moves. Runs in _process (render rate) and sets
# global_transform directly — the same way Carry drives a held item — so the plug stays glued to a
# carried socket with no interpolation lag. (The initial seat still uses the server-set teleport in
# _author_seated_body; this is only the per-frame follow of small deltas.)
# Where the seated body sits: the socket transform pushed out along its +Z by SEAT_STANDOFF, so
# the plug stays outside the socket/mount (see SEAT_STANDOFF).
func _seated_body_xform() -> Transform3D:
	return _seated_socket.snap_transform().translated_local(Vector3(0.0, 0.0, SEAT_STANDOFF))


func _follow_seated_socket() -> void:
	if not is_seated():
		return
	var xform := _seated_body_xform()
	if not xform.is_equal_approx(_last_snap_xform):
		_body.global_transform = xform
		_last_snap_xform = xform


# While held, light the nearest acceptable socket whose snap_radius contains the plug's rendered
# position; clear the highlight otherwise. No candidate ever lights while the post-breakaway
# re-seat cooldown runs.
func _update_snap_candidate() -> void:
	if not _held or _reseat_cooldown > 0.0:
		_set_snap_candidate(null)
		return
	# Proximity snapping measures from the plug CENTRE (where the body meets the socket), not the
	# back-gland cable pin — you nose the plug INTO the socket.
	var pin := global_position
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
