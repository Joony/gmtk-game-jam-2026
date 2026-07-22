class_name SlidingDoor
extends Node3D

# Two panels that slide apart when the player approaches, ported from GMTK 2025's
# V1/DoorManager.gd (307 lines, of which the panel geometry, the proximity Area3D and
# the slide tween are the parts worth keeping).
#
# Left behind: the control panel (already commented out in 2025), is_player_near_door()'s
# manual distance check (the Area3D supersedes it), the player_node reference, and its
# grid_boundary_to_world helper (our coordinate convention differs — see RoomBuilder).
#
# UPGRADE ON PORT: panels are AnimatableBody3D, not 2025's StaticBody3D. Moving a static
# body does not sweep against other bodies — a closing panel would clip through the player
# or trap them. AnimatableBody3D with sync_to_physics pushes properly, which also means the
# tween must run on the PHYSICS clock, not the render clock.

signal opened
signal closed

# Panels overlap the lintel above and the floor below by this much. Sitting flush would
# put the panel's top face exactly on the lintel's underside and its base exactly on the
# floor — coplanar overlapping faces, the same z-fighting that thickness fixes sideways.
# Interpenetrating slightly is invisible and cannot shimmer.
const SEAM_OVERLAP := 0.02

@export var open_time: float = 0.4
## A jammed door refuses to open. Cheap hook for step 12d: "the door won't open" is a
## repair with no new mechanics behind it.
@export var jammed: bool = false

var is_open: bool = false

var _panels: Array[AnimatableBody3D] = []
var _closed_positions: Array[Vector3] = []
var _open_positions: Array[Vector3] = []
var _tween: Tween
var _occupants: int = 0


## Build the panels and the proximity trigger for `doorway`. Called by RoomBuilder.
## `thickness` must be LESS than the wall thickness: an open panel slides inside the
## wall, and equal thickness makes the two coplanar, which z-fights badly.
func build(
	doorway: Doorway,
	height: float,
	thickness: float,
	tile: float,
	material: StandardMaterial3D,
	approach: float = 1.6
) -> void:
	name = "Door_%s" % doorway.id
	position = Vector3(doorway.position.x * tile, 0.0, doorway.position.y * tile)

	var along := Vector3.RIGHT if doorway.axis == Doorway.Axis.X else Vector3.BACK
	var half_width := doorway.width * 0.5 * tile
	# Each panel covers half the opening; sliding by 0.6x the full width clears it
	# entirely and tucks the panel into the wall, as if into a pocket.
	var slide := doorway.width * 0.6 * tile

	for i in 2:
		var direction := 1.0 if i == 0 else -1.0
		var panel := AnimatableBody3D.new()
		panel.name = "Panel_%d" % i
		panel.sync_to_physics = true

		var panel_height := height + SEAM_OVERLAP * 2.0
		var size := Vector3(half_width, panel_height, thickness)
		if doorway.axis == Doorway.Axis.Z:
			size = Vector3(thickness, panel_height, half_width)

		var mesh := MeshInstance3D.new()
		mesh.name = "Mesh"
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		mesh.material_override = material
		panel.add_child(mesh)

		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		panel.add_child(shape)

		var closed_at := along * (direction * half_width * 0.5) + Vector3(0.0, height * 0.5, 0.0)
		panel.position = closed_at
		add_child(panel)

		_panels.append(panel)
		_closed_positions.append(closed_at)
		_open_positions.append(closed_at + along * (direction * slide))

	_build_trigger(doorway, height, tile, approach)


func _build_trigger(doorway: Doorway, height: float, tile: float, approach: float) -> void:
	var area := Area3D.new()
	area.name = "Trigger"
	# Only the player opens doors — otherwise a thrown crate would trip it.
	area.collision_mask = 1
	area.position = Vector3(0.0, height * 0.5, 0.0)

	var span := doorway.width * tile + 1.0
	var size := Vector3(span, height, approach * 2.0)
	if doorway.axis == Doorway.Axis.Z:
		size = Vector3(approach * 2.0, height, span)

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	area.add_child(shape)
	add_child(area)

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group(&"player"):
		return
	_occupants += 1
	open()


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group(&"player"):
		return
	_occupants = maxi(0, _occupants - 1)
	if _occupants == 0:
		close()


func open() -> void:
	if is_open or jammed:
		return
	is_open = true
	_slide_to(_open_positions)
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_slide_to(_closed_positions)
	closed.emit()


func _slide_to(targets: Array[Vector3]) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	# AnimatableBody3D only sweeps correctly when moved during the physics step.
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.set_parallel(true)
	for i in _panels.size():
		_tween.tween_property(_panels[i], "position", targets[i], open_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
