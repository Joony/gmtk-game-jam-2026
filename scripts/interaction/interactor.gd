class_name Interactor
extends Node3D

# Camera-ray interaction detection, ported from GMTK 2025's check_for_interactables().
#
# Raycast, not proximity+cone: the reticle promises "you will act on whatever the dot
# covers", and only a ray keeps that promise. (The 2025 project reached the same
# conclusion — it has an `interaction_angle` export whose cone check is commented out.)
#
# Owns the interact/throw input and routes it to Carry.

## Emitted when the focused interactable, its prompt, or its actionability changes.
## `actionable` is what turns the reticle green — see Interactable.can_act_on().
signal focus_changed(interactable: Interactable, prompt: String, actionable: bool)

@export var camera_path: NodePath = NodePath("../CameraRig/Camera3D")
@export var carry_path: NodePath = NodePath("../Carry")
@export var body_path: NodePath = NodePath("..")
@export var ray_length: float = 2.5

## The forgiveness cone, in degrees off dead centre, walked inside-out. Only consulted when the
## centre ray finds nothing usable — see cast_from().
##
## 1.6 and 3.2 degrees is about 6cm and 11cm of slack at the two metres you actually stand at,
## which is roughly "the reticle is touching it" rather than "the reticle is near it". Wide
## enough to fix a hammer lying end-on, narrow enough that it never picks a thing you were not
## looking at: a second ring at 6 degrees started answering for props a clear hand's width away.
const CONE_RINGS := [1.6, 3.2]
## Rays per ring. Eight is one every 45 degrees around the circle, which is dense enough that a
## sliver of hammer cannot fall between two of them at these radii.
const CONE_RAYS := 8

@onready var _cam: Camera3D = get_node_or_null(camera_path)
@onready var _carry: Carry = get_node_or_null(carry_path)
@onready var _body: PhysicsBody3D = get_node_or_null(body_path)

var current: Interactable = null

var _prompt: String = ""
var _actionable: bool = false


func _ready() -> void:
	add_to_group(&"interactors")


func get_prompt() -> String:
	return _prompt


func is_actionable() -> bool:
	return _actionable


func _physics_process(_delta: float) -> void:
	var found := _cast()
	var held := _carry.held_item() if _carry != null else null
	var prompt := ""
	var actionable := false
	if found != null:
		actionable = found.can_act_on(held)
		prompt = found.get_interaction_text(held)
		# Only offer the key when pressing it would do something.
		if actionable:
			prompt = "[E] %s" % prompt
	# Emit on prompt/actionability change too: "Pick up crate" becomes "Hands full"
	# without the focused node changing at all.
	if found != current or prompt != _prompt or actionable != _actionable:
		current = found
		_prompt = prompt
		_actionable = actionable
		focus_changed.emit(current, prompt, actionable)


func _cast() -> Interactable:
	if _cam == null:
		return null
	return cast_from(_cam.global_position, -_cam.global_transform.basis.z)


## The aim, as a function of where you are and where you are looking. Public and parameterised
## so a test can sweep it without standing a real camera up — see tests/diag_aim.gd.
##
## DEAD CENTRE FIRST, then a thin cone. The centre ray is the reticle's promise — "you act on
## whatever the dot covers" — and it still wins outright whenever it finds anything, so precise
## aim is never overruled by something merely near the dot. The cone only runs when the centre
## ray came back with nothing usable, which is exactly the case where the player currently gets
## no prompt at all.
##
## A CONE OF RAYS rather than a swept sphere or a nearest-within-an-angle search, and the reason
## is occlusion: every ray in the cone still stops at the first thing it hits, so a ray that
## meets a wall returns the wall and contributes nothing. You cannot reach through geometry or
## around a crate. A swept sphere leaks past both and would need guarding against it.
##
## Measured in tests/diag_aim.gd. Over a 12-degree aim window, a hammer on the floor answers
## 37%..82% of directions depending which way it landed — the L-shape means its silhouette
## genuinely changes by more than double — and the small spares are far worse, from 9% to 30%.
##
## WHAT THE CONE ACTUALLY BUYS, since it is less than it sounds: the small spares roughly DOUBLE
## their hit area (gear 9%->20%, screw 19%->35%), and the hammer gains about a degree — it goes
## from failing at 7 degrees off to succeeding there. The big props were already fine and are
## unaffected.
##
## AND THE KNOWN COST. Aim far enough off and the cone can answer with a DIFFERENT nearby prop:
## rays in a ring all share an angle, so ties break on distance-to-camera, and a neighbour closer
## to you beats the thing you were pointing at. Measured in a cargo bay, aiming 8 degrees off a
## hammer returns a canister a hand's width away. It is bounded by the ring radius, so CONE_RINGS
## is the knob — a single 1.6-degree ring nearly removes it and keeps most of the spare-part win.
func cast_from(from: Vector3, forward: Vector3) -> Interactable:
	var space := get_world_3d().direct_space_state
	if space == null:
		return null
	var exclude: Array[RID] = []
	if _body != null:
		exclude.append(_body.get_rid())
	# Without this the thing in your hands blocks every ray.
	if _carry != null and _carry.is_holding():
		var held := _carry.held_item() as CollisionObject3D
		if held != null:
			exclude.append(held.get_rid())

	var aim := forward.normalized()
	var found := _probe(space, from, aim, exclude)
	if found != null:
		return found

	# The cone. Rings are walked from the inside out and the first ring to find anything wins,
	# so a near miss is preferred to a wide one; within a ring the NEAREST hit wins, so two
	# things beside the reticle resolve to the closer.
	var right := aim.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		# Looking straight up or down — any perpendicular will do, and the ship's forward axis
		# is as good as anything.
		right = aim.cross(Vector3.FORWARD)
	right = right.normalized()
	var up := right.cross(aim).normalized()

	for degrees in CONE_RINGS:
		var spread := tan(deg_to_rad(degrees))
		var best: Interactable = null
		var best_distance := INF
		for i in CONE_RAYS:
			var theta := TAU * float(i) / float(CONE_RAYS)
			var offset := right * (cos(theta) * spread) + up * (sin(theta) * spread)
			var probe := (aim + offset).normalized()
			var distance := [INF]
			var candidate := _probe(space, from, probe, exclude, distance)
			if candidate != null and distance[0] < best_distance:
				best = candidate
				best_distance = distance[0]
		if best != null:
			return best
	return null


## One ray. Returns the interactable it lands on, or null — including when it hits something
## that simply is not one, which is the case the cone above exists to rescue.
##
## `out_distance`, when given, receives how far away the hit was, so the caller can prefer the
## nearest of several cone hits.
func _probe(space: PhysicsDirectSpaceState3D, from: Vector3, direction: Vector3,
		exclude: Array[RID], out_distance: Array = []) -> Interactable:
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * ray_length)
	query.collide_with_areas = true
	query.exclude = exclude
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	var found := find_interactable_in_hierarchy(resolve_hit(hit))
	if found == null:
		return null
	var held_item := _carry.held_item() if _carry != null else null
	if not found.can_interact(held_item):
		return null
	if not out_distance.is_empty():
		out_distance[0] = from.distance_to(hit.get("position", from))
	return found


## What an intersect_ray hit MEANS, which is not always the body it struck.
##
## A single shape on a body can be a stand-in for something else. CablePlug clones its own
## collider onto a dynamic mount so a tipped battery props itself off the floor rather than
## letting the frozen plug rotate under it (CablePlug._install_mount_guard). That clone sits
## exactly where the seated plug is, and the mount — the battery — is itself a pickup. So the
## ray struck the guard, the hierarchy walk found the cube, and the reticle offered "pick up
## battery" over a plug the player was aiming at: **you could not disconnect a plug from a
## battery at all**, from the one direction you ever approach it.
##
## The obvious fix, putting the guard on a layer this ray does not scan, is not available:
## collision layers belong to the whole CollisionObject3D, not to individual shapes. So the
## shape declares what it stands for (Interactable.PROXY_META) and this reads it back. The
## guard keeps every bit of its physics behaviour and simply stops answering for itself.
static func resolve_hit(hit: Dictionary) -> Object:
	var collider := hit.get("collider") as CollisionObject3D
	if collider == null:
		return hit.get("collider")
	var owner_id := collider.shape_find_owner(hit.get("shape", 0))
	var shape_node := collider.shape_owner_get_owner(owner_id) as Node
	if shape_node == null or not shape_node.has_meta(Interactable.PROXY_META):
		return collider
	var stands_for = shape_node.get_meta(Interactable.PROXY_META)
	if stands_for is Node and is_instance_valid(stands_for):
		return stands_for
	return collider


# The ray hits a CollisionShape/body, so walk up to the node owning the Interactable.
static func find_interactable_in_hierarchy(node: Object) -> Interactable:
	var current_node := node as Node
	var guard := 0
	while current_node != null and guard < 64:
		if current_node is Interactable:
			return current_node
		current_node = current_node.get_parent()
		guard += 1
	return null


func _unhandled_input(event: InputEvent) -> void:
	if _carry == null:
		return

	if event.is_action_pressed("interact"):
		var holding := _carry.is_holding()
		var held := _carry.held_item()
		# Using the held item on something takes priority over dropping it —
		# that's the repair loop: carry the part, look at the panel, press E. The held item is
		# passed in so a target can present as USE_ITEM only for what you're carrying (the battery
		# accepts a plug this way).
		if holding and current != null and current.get_interaction_type(held) == Interactable.InteractionType.USE_ITEM:
			var item := _carry.held_item()
			current.use_with_item(item)
			# A part fitted into a panel is gone. Drop first so Carry lets go of a body
			# it is about to lose, then free it.
			if current.consumed_last_item() and is_instance_valid(item):
				_carry.drop(false)
				item.queue_free()
		elif holding:
			_carry.drop(false)
		elif current != null:
			_activate(current)
		else:
			return
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("throw") and _carry.is_holding():
		_carry.drop(true)
		get_viewport().set_input_as_handled()


func _activate(interactable: Interactable) -> void:
	match interactable.get_interaction_type():
		Interactable.InteractionType.PICKUP:
			_carry.grab(interactable)
		Interactable.InteractionType.DISABLED:
			pass
		_:
			interactable.interact()
