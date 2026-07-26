class_name IndicatorLight
extends Node3D

# The little light on a thing that tells you, from across a room, whether it wants attention.
# Green nominal, amber needs something fetching, red broken — and red FLASHES, because the
# difference between "deal with this eventually" and "deal with this now" has to survive being
# seen out of the corner of your eye.
#
# ONE of these, used by everything. RepairPoint and Silo each grew their own emissive-quad
# routine, subtly different, and a third was about to appear for the engine and the nav
# computer. A lamp that is subtly wrong is worse than no lamp — it teaches the wrong thing
# quietly — so there is now a single answer to what a status light looks like and how it pulses.
#
# WHERE IT MOUNTS, in order of preference:
#
#   1. an `Indicator` empty inside the model, which is what the art now ships for the engine
#      and the silos and is always the right spot because the modeller chose it
#   2. an existing `StatusLight` mesh, which the repair panel prop carries
#   3. a quad built here at a stated offset, for a prop with neither
#
# Scale is compensated at every step: these mount inside props dressed at 0.25 or 0.6, so local
# units are not metres, and an indicator sized in local units would come out a quarter-size on
# one prop and full-size on the next.

## The name of the empty the models carry for this.
const EMPTY_NAME := &"Indicator"
## The name of the mesh the repair panel prop already had.
const LIGHT_NAME := &"StatusLight"

const COLOR_OK := Color(0.24, 0.90, 0.40)
const COLOR_WARN := Color(1.00, 0.62, 0.10)
const COLOR_CRIT := Color(1.00, 0.16, 0.12)

## Edge of the built quad, in metres.
const SIZE := 0.16
## Flashes per second. Fast enough to read as an alarm, slow enough not to strobe.
const FLASH_HZ := 2.0
## How far down the pulse dips. Not to black: a light that goes fully out reads as a dead lamp
## on the half-cycle you happen to glance at it.
const FLASH_FLOOR := 0.25

var _material: StandardMaterial3D = null
var _color: Color = COLOR_OK
var _flashing: bool = false
var _clock: float = 0.0


## Put an indicator on `host` and return it, or null if there is nowhere sensible to put one.
## `fallback_offset` is in METRES from the host's own origin, used only when the host carries
## neither an `Indicator` empty nor a `StatusLight` mesh.
static func attach(host: Node3D, fallback_offset: Vector3 = Vector3.ZERO) -> IndicatorLight:
	if host == null:
		return null
	var indicator := IndicatorLight.new()
	indicator.name = "IndicatorLight"

	var empty := _find_named(host, EMPTY_NAME)
	var existing := _find_named(host, LIGHT_NAME) as MeshInstance3D
	if empty != null:
		empty.add_child(indicator)
		indicator._build_quad(empty)
	elif existing != null:
		# Drive the mesh the prop already has rather than adding a second one beside it.
		host.add_child(indicator)
		indicator._adopt_mesh(existing)
	else:
		host.add_child(indicator)
		indicator.position = fallback_offset / _scale_of(host)
		indicator._build_quad(host)
	indicator._apply()
	return indicator


## Colour it, and say whether it should pulse. Cheap enough to call every frame.
func set_state(color: Color, flashing: bool = false) -> void:
	if color == _color and flashing == _flashing:
		return
	_color = color
	_flashing = flashing
	if not flashing:
		_clock = 0.0
	_apply()


## What it is showing right now. For tests and for anything that wants to mirror the light
## somewhere else — the ship map, say. Reading the material back would couple the caller to how
## the light happens to be built.
func current_color() -> Color:
	return _color


func is_flashing() -> bool:
	return _flashing


func _process(delta: float) -> void:
	if not _flashing or _material == null:
		return
	_clock += delta
	# Sine rather than a square wave: a hard on/off at 2 Hz is a strobe, and this has to be
	# legible in peripheral vision without being unpleasant to stand next to.
	var pulse := 0.5 + 0.5 * sin(TAU * FLASH_HZ * _clock)
	var level: float = lerpf(FLASH_FLOOR, 1.0, pulse)
	_material.albedo_color = _color * level
	_material.emission = _color
	_material.emission_energy_multiplier = level


func _build_quad(mount: Node3D) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * SIZE
	mesh.mesh = box
	# Sized in metres whatever the prop is dressed at.
	mesh.scale = Vector3.ONE / _scale_of(mount)
	_material = _new_material()
	mesh.material_override = _material
	add_child(mesh)


func _adopt_mesh(mesh: MeshInstance3D) -> void:
	_material = _new_material()
	mesh.material_override = _material


func _new_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	# Unshaded, because the ship's interior is flat-lit: a shaded indicator is just a slightly
	# different grey. Per-instance, or every light on the ship would change colour together.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	return material


func _apply() -> void:
	if _material == null:
		return
	_material.albedo_color = _color
	_material.emission = _color
	_material.emission_energy_multiplier = 1.0


## Uniform scales only, which every prop on the ship uses; y stands for all three.
static func _scale_of(node: Node3D) -> float:
	return maxf(node.global_transform.basis.get_scale().y, 0.0001)


## Depth-first by name, because the empties sit inside the imported model rather than as
## direct children of whatever the script is attached to.
static func _find_named(node: Node, wanted: StringName) -> Node3D:
	if node.name == wanted:
		return node as Node3D
	for child in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null
