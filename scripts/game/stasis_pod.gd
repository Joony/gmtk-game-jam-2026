class_name StasisPod
extends Interactable

# The loop anchor, wrapped around LoganDevz's CD_Cryo_v2 model.
#
# The pod does NOT refill air — it slows the bleed to `RunState.stasis_oxygen_rate`. That
# rule is the spine of the design: a pod that refuelled you would reduce every problem to
# "walk back and top up", and the air budget would stop being a budget. What it buys you is
# TIME, at 24x, which is the only way to cross 82 million miles inside a jam-length run.
#
# THE MODEL'S GEOMETRY. The .blend authors one pod of a five-pod ring: its meshes hang off a
# shared pivot at (0.8, 1, 0) which is the pod's vertical axis, with the door facing local
# +X. `cryo_pod.tscn` rotates the model 90 degrees so the door faces -Z (Godot's forward)
# and shifts it so that pivot lands on the wrapper's origin. Everything below — the view
# marker, the exit marker, the door swing — is then expressed in sane local coordinates.
#
# The door shares that pivot, so opening it is a plain Y rotation: the panel swings around
# the cylinder rather than hinging outward, which is what the curved shell wants.

signal entered
signal exited

## Only one pod in the bay is the player's. The rest are scenery and must never offer a
## prompt — five identical interactable pods would be five identical wrong answers.
@export var is_player_pod: bool = true
@export var enter_text: String = "Enter stasis pod"

@export_group("Door")
@export var door_path: NodePath = NodePath("Model/Door")
## How far the panel swings round the shell. Roughly the arc the door itself covers.
@export var door_open_degrees: float = 105.0
@export var door_time: float = 0.9

@export_group("Player positions")
## Where the player's BODY goes while sealed in.
@export var view_path: NodePath = NodePath("PodView")
## Where the player is set down on the way out, in front of the door.
@export var exit_path: NodePath = NodePath("PodExit")

var occupied: bool = false

var _door: Node3D = null
var _door_closed_y: float = 0.0
var _door_tween: Tween


func _ready() -> void:
	super()
	interaction_type = InteractionType.ACTIVATE
	interaction_text = enter_text
	if not is_player_pod:
		is_enabled = false

	_door = get_node_or_null(door_path) as Node3D
	if _door != null:
		_door_closed_y = _door.rotation.y


func get_interaction_text(_held_item: Node3D = null) -> String:
	# You cannot look at the pod from inside it, so there is no "exit" prompt here —
	# leaving is driven by the stasis overlay.
	return enter_text


# Climbing into a pod with a spare under your arm should not silently eat the spare, and
# mid-repair is exactly when a player might wander back. Let them in regardless; Game drops
# whatever they are carrying first.
func can_act_on(_held_item: Node3D = null) -> bool:
	return is_enabled and not occupied


func set_occupied(value: bool) -> void:
	if occupied == value:
		return
	occupied = value
	if occupied:
		entered.emit()
	else:
		exited.emit()


## Where the player's body sits while sealed in. Falls back to the pod's own transform so a
## missing marker cannot silently teleport the player into the floor.
func view_transform() -> Transform3D:
	var marker := get_node_or_null(view_path) as Node3D
	return marker.global_transform if marker != null else global_transform


func exit_transform() -> Transform3D:
	var marker := get_node_or_null(exit_path) as Node3D
	return marker.global_transform if marker != null else global_transform


func set_door_open(open: bool, instant: bool = false) -> void:
	if _door == null:
		return
	var target := _door_closed_y + (deg_to_rad(door_open_degrees) if open else 0.0)
	if _door_tween != null and _door_tween.is_valid():
		_door_tween.kill()
	if instant or door_time <= 0.0:
		_door.rotation.y = target
		return
	_door_tween = create_tween()
	_door_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_door_tween.tween_property(_door, "rotation:y", target, door_time)


## Seconds the door takes to move, so Game can sequence the walk-in against it.
func door_duration() -> float:
	return door_time if _door != null else 0.0
