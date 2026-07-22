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
	var space := get_world_3d().direct_space_state
	if space == null:
		return null

	var from := _cam.global_position
	var to := from + (-_cam.global_transform.basis.z * ray_length)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true

	var exclude: Array[RID] = []
	if _body != null:
		exclude.append(_body.get_rid())
	# Without this the thing in your hands blocks every ray.
	if _carry != null and _carry.is_holding():
		var held := _carry.held_item() as CollisionObject3D
		if held != null:
			exclude.append(held.get_rid())
	query.exclude = exclude

	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null

	var found := find_interactable_in_hierarchy(hit["collider"])
	if found == null:
		return null
	var held_item := _carry.held_item() if _carry != null else null
	if not found.can_interact(held_item):
		return null
	return found


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
		# Using the held item on something takes priority over dropping it —
		# that's the repair loop: carry the part, look at the panel, press E.
		if holding and current != null and current.get_interaction_type() == Interactable.InteractionType.USE_ITEM:
			current.use_with_item(_carry.held_item())
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
