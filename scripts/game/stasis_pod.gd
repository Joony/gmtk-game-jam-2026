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
## Emitted when the door actually starts moving — not for the instant set-up call that
## poses every pod at startup, and not when re-setting a state it is already in. Game wires
## this to the audio, so the pod itself still knows nothing about sound.
signal door_moved(opening: bool)

## The number on the inside of the door. See _build_door_label().
const LABEL_FONT := preload("res://assets/AbolitionTest-Regular.otf")
## Rendered at this size and then scaled to LABEL_HEIGHT, so the glyphs are rasterised big
## enough to stay crisp with the player's face 0.7m from them.
const LABEL_FONT_SIZE := 128
## Em size in metres. This is the ONLY thing that sets how big the label looks —
## LABEL_FONT_SIZE above is rasterisation resolution and is divided straight back out by
## `pixel_size`, so raising it sharpens the glyphs and changes nothing on screen. The digits
## themselves come out about three quarters of this tall.
const LABEL_HEIGHT := 0.64
## How far to lift the label so the DIGITS are centred on the eye rather than their line box.
##
## Label3D centres the box, and a box is ascent + descent — but "01" has no descender, so its
## ink sits in the upper part and the visible number lands low. Measured off a render rather
## than derived: Godot exposes no cap height, only ascent and descent. As a FRACTION of
## LABEL_HEIGHT, so it stays right when the size changes.
##
## To re-measure: tint the label a colour nothing else in the pod uses, render
## tests/capture_pod_label.gd, and find the first and last rows containing it.
const LABEL_INK_LIFT := 0.1375
## Where it sits in POD space: level with the eye, just inside the door's inner face.
const LABEL_POSITION := Vector3(0.0, 1.6, -0.74)
## Slightly transparent — stencilled onto the panel, not a sign hung in front of it.
const LABEL_COLOR := Color(0.86, 0.90, 0.95, 0.4)

## Only one pod in the bay is the player's. The rest are scenery and must never offer a
## prompt — five identical interactable pods would be five identical wrong answers.
@export var is_player_pod: bool = true
@export var enter_text: String = "Enter stasis pod"

@export_group("Door")
@export var door_path: NodePath = NodePath("Model/Door")
## How far the panel swings round the shell. Roughly the arc the door itself covers.
@export var door_open_degrees: float = 105.0
@export var door_time: float = 0.9
## The pod's number, stencilled on the INSIDE of the door at eye height. Blank for none.
## Only the player's pod gets one — it is the only door there is ever anyone behind.
@export var door_label: String = "01"

@export_group("Player positions")
## Where the player's BODY goes while sealed in.
@export var view_path: NodePath = NodePath("PodView")
## Where the player is set down on the way out, in front of the door.
@export var exit_path: NodePath = NodePath("PodExit")

var occupied: bool = false

var _door: Node3D = null
var _door_closed_y: float = 0.0
var _door_open: bool = false
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
		_build_door_label()


## Stencil the pod's number on the inside of the door, where the player reads it for the whole
## of every stasis: they are sealed in facing it, and it is the only thing to look at.
##
## Built here rather than placed in cryo_pod.tscn because it is parented to `Door`, which lives
## inside the imported .blend and carries that model's own baked rotation — a hand-authored
## transform under it would be an unreadable basis literal that a re-import could invalidate.
## Setting `global_transform` AFTER the reparent lets the engine work the door-local transform
## out, so the only number written down is the one that means something: where the label sits
## in POD space, which is the frame every other marker in cryo_pod.tscn is written in too.
##
## Being a child of the door is the whole point — it swings out of the way with the panel on
## the same tween, with nothing to keep in sync.
func _build_door_label() -> void:
	if door_label.is_empty() or not is_player_pod:
		return
	var label := Label3D.new()
	label.name = "DoorLabel"
	label.text = door_label
	label.font = LABEL_FONT
	label.font_size = LABEL_FONT_SIZE
	label.pixel_size = LABEL_HEIGHT / float(LABEL_FONT_SIZE)
	# Printed ON the door, not lit as an object: the ship's interior is shadowless, so a shaded
	# label would just be a slightly different flat grey. Transparent enough to read as a
	# stencil on the panel rather than a decal floating in front of it.
	label.shaded = false
	label.modulate = LABEL_COLOR
	# The default 12px outline is a black halo, which at this alpha reads as a drop shadow.
	label.outline_size = 0
	# Only ever seen from inside. Culling the back face means it cannot ghost through the panel
	# from outside the pod once the door has swung open.
	label.double_sided = false
	_door.add_child(label)
	# Pod space: dead ahead of the eye (PodView + the 0.65m camera anchor = 1.6m), a few
	# centimetres clear of the door's inner surface at z = -0.782 so the two cannot z-fight.
	label.global_transform = global_transform * Transform3D(
		Basis.IDENTITY, LABEL_POSITION + Vector3.UP * LABEL_HEIGHT * LABEL_INK_LIFT)


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
	var changed := open != _door_open
	_door_open = open
	var target := _door_closed_y + (deg_to_rad(door_open_degrees) if open else 0.0)
	if _door_tween != null and _door_tween.is_valid():
		_door_tween.kill()
	if instant or door_time <= 0.0:
		_door.rotation.y = target
		return
	if changed:
		door_moved.emit(open)
	_door_tween = create_tween()
	_door_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_door_tween.tween_property(_door, "rotation:y", target, door_time)


## Seconds the door takes to move, so Game can sequence the walk-in against it.
func door_duration() -> float:
	return door_time if _door != null else 0.0
