class_name LightingController
extends Node

# Ship-wide lighting state: NORMAL (white) and ALERT (red).
#
# Modes are DATA, not branches — adding a third state (emergency, power loss) is a new
# entry in MODES, not new code.
#
# Values are applied to every node in the `room_lights` / `room_light_panels` groups each
# frame rather than tweened per-light. That is what makes the mode a property of the SHIP:
# rooms built *after* the mode was set come up in the right colour automatically, with no
# registration step. With a dozen fixtures the cost is nothing.

enum Mode { NORMAL, ALERT }

const MODES := {
	Mode.NORMAL: {
		"light_color": Color(0.95, 0.96, 1.00),
		"light_energy": 1.6,
		"ambient_color": Color(0.62, 0.66, 0.72),
		"ambient_energy": 0.45,
		"pulse": 0.0,
	},
	Mode.ALERT: {
		# Dimmer as well as red: a darker room reads as more oppressive than a bright
		# red one, and keeps the emissive panels legible as the light source.
		"light_color": Color(1.00, 0.16, 0.12),
		"light_energy": 1.15,
		"ambient_color": Color(0.34, 0.11, 0.11),
		"ambient_energy": 0.28,
		"pulse": 0.30,
	},
}

## Signs that should take the ship's lighting without being lit by it.
##
## The doorway signs are `Sprite3D`s, and SpriteBase3D.shaded defaults to FALSE — so they draw
## their texture at full albedo and scene lights and ambient pass straight through them. On red
## alert the whole ship went red around a set of signs that stayed daylight-white.
##
## Turning `shaded` on was the other option and is worse here: a sign tucked above a doorway sits
## away from the omnis, so it would read as murky in a lit room and vanish outright in an unlit
## one. Modulating keeps them legible and is the same move the emissive light panels already
## make — the sign reads as lit by the room without depending on a lamp being near it.
##
## They are NOT built by RoomBuilder (they are authored in game.tscn), so the group lives here
## with its consumer rather than beside GROUP_LIGHT.
const GROUP_SIGN := &"lit_signs"

## How far a sign is dragged toward the light colour. Not 1.0: a sign taking the alert colour
## outright is red text on a red sign, and the point of a doorway sign is to be readable at the
## moment the ship is telling you to go somewhere.
const SIGN_TINT := 0.8
## ...and how far it follows the room's BRIGHTNESS. Alert is dimmer as well as red, and a sign
## that stayed at full brightness would float off the wall. Kept shallow, and floored, so it
## never goes black.
const SIGN_DIM := 0.35

## Emitted when the mode actually changes (not when re-set to the current mode).
signal mode_changed(mode: Mode)

@export var transition_time: float = 0.4
## Throb speed while pulsing. Step 12 can raise this as the countdown runs down.
@export var pulse_hz: float = 0.55

## Light only the room the player is in, plus its near neighbours.
##
## WHY. GL Compatibility caps how many lights one MESH may receive
## (rendering/limits/opengl/max_lights_per_object) and how many the renderer will draw at all
## (max_renderable_lights). RoomBuilder emits ONE box per floor and ceiling, so a big room's
## floor is a single mesh under every fixture in that room. The nine-room ship has 93
## fixtures; past the caps the renderer keeps whichever it prefers for the current view, so
## surfaces visibly dimmed and brightened as the camera turned on the spot.
##
## Gating is per ROOM, never per light: switching individual fixtures by distance would pop
## them on and off as the player walks a long room. A room is all-lit or all-dark.
@export var cull_by_room: bool = true
## How far outside a room's walls the player can be and still have it lit. Covers the case of
## standing in a corridor looking through an open door into the room beyond — that room has
## to already be lit or the doorway reads as a hole into nothing.
@export var cull_margin: float = 7.0

var mode: Mode = Mode.NORMAL

var _environment: Environment
var _from: Dictionary = MODES[Mode.NORMAL]
var _to: Dictionary = MODES[Mode.NORMAL]
var _blend: float = 1.0
var _time: float = 0.0
var _occupant: Node3D = null
var _builder: RoomBuilder = null
## room_id -> bool. Recomputed only when the player changes room, not every frame.
var _lit: Dictionary = {}
var _last_cell := Vector2i(-99999, -99999)


func _ready() -> void:
	# Keep running while paused so a transition doesn't freeze half-finished; harmless
	# either way, and step 12 may flip modes from a paused menu.
	process_mode = Node.PROCESS_MODE_ALWAYS


## Point the controller at the scene's WorldEnvironment so ambient follows the mode too.
func bind_environment(world_environment: WorldEnvironment) -> void:
	if world_environment == null or world_environment.environment == null:
		return
	# Duplicate: the Environment is a scene sub-resource, so mutating it in place would
	# leak state between instantiations of the game scene (notably across tests).
	_environment = world_environment.environment.duplicate()
	world_environment.environment = _environment


## Point the controller at the ship and whoever is walking around it, so room culling knows
## where the rooms are and who is standing in one. Without this, culling is inert and every
## light stays on — which is the correct fallback for tests that build a bare RoomBuilder.
func bind_occupancy(builder: RoomBuilder, occupant: Node3D) -> void:
	_builder = builder
	_occupant = occupant
	_last_cell = Vector2i(-99999, -99999)  # force a recompute on the next frame


## `immediate` skips the blend and lands on the mode this frame.
##
## For the OPENING. The run begins with a critical fault already broken, so the alert is raised
## during RunState.start() — but a blended transition starts from the NORMAL defaults the rooms
## were built with, so the first 0.4s of every session was a white ship fading to red. That
## reads as the alarm going off just after you wake, when the fiction is that it woke you.
##
## Applied here rather than left to the next _process, so it holds even if something renders
## before this node next ticks.
func set_mode(new_mode: Mode, immediate: bool = false) -> void:
	if new_mode == mode and not immediate:
		return
	# `_from` FIRST: _current_values() interpolates toward `_to`, so assigning `_to` before
	# reading it makes the blend start from the destination — every transition snaps.
	if immediate:
		_from = MODES[new_mode]
		_blend = 1.0
	else:
		_from = _current_values()
		_blend = 0.0
	_to = MODES[new_mode]
	if new_mode != mode:
		mode = new_mode
		mode_changed.emit(mode)
	if immediate:
		_apply(_current_values())


func set_alert(on: bool, immediate: bool = false) -> void:
	set_mode(Mode.ALERT if on else Mode.NORMAL, immediate)


func is_alert() -> bool:
	return mode == Mode.ALERT


func _process(delta: float) -> void:
	_time += delta
	if _blend < 1.0:
		_blend = 1.0 if transition_time <= 0.0 else minf(_blend + delta / transition_time, 1.0)
	_update_occupancy()
	_apply(_current_values())


## Recompute which rooms are lit, but only when the player has actually moved a metre or so.
## The set changes at walking pace; recomputing it every frame for every room would be work
## for nothing.
func _update_occupancy() -> void:
	if not cull_by_room or _builder == null or _occupant == null:
		return
	if not is_instance_valid(_occupant) or not is_instance_valid(_builder):
		return
	var at := _occupant.global_position
	var cell := Vector2i(int(floor(at.x)), int(floor(at.z)))
	if cell == _last_cell:
		return
	_last_cell = cell

	_lit.clear()
	for room in _builder.rooms:
		_lit[room.id] = _near(at, room)


## Is the player inside this room, or within cull_margin of its walls? Distance is measured to
## the RECT, not to its centre — a 21x33 room's centre can be 20m from a player standing just
## inside its door.
func _near(at: Vector3, room: Room) -> bool:
	var scale := _builder.tile_size
	var x0 := float(room.rect.position.x) * scale
	var z0 := float(room.rect.position.y) * scale
	var x1 := x0 + float(room.rect.size.x) * scale
	var z1 := z0 + float(room.rect.size.y) * scale
	var dx := maxf(maxf(x0 - at.x, at.x - x1), 0.0)
	var dz := maxf(maxf(z0 - at.z, at.z - z1), 0.0)
	return dx * dx + dz * dz <= cull_margin * cull_margin


func _current_values() -> Dictionary:
	var t := _blend * _blend * (3.0 - 2.0 * _blend)  # smoothstep
	return {
		"light_color": Color(_from["light_color"]).lerp(_to["light_color"], t),
		"light_energy": lerpf(_from["light_energy"], _to["light_energy"], t),
		"ambient_color": Color(_from["ambient_color"]).lerp(_to["ambient_color"], t),
		"ambient_energy": lerpf(_from["ambient_energy"], _to["ambient_energy"], t),
		"pulse": lerpf(_from["pulse"], _to["pulse"], t),
	}


func _apply(values: Dictionary) -> void:
	var pulse: float = values["pulse"]
	var throb := 1.0
	if pulse > 0.001:
		throb = 1.0 + pulse * sin(TAU * pulse_hz * _time)

	var color: Color = values["light_color"]
	var energy: float = values["light_energy"] * throb

	var culling := cull_by_room and _builder != null and not _lit.is_empty()
	for light in get_tree().get_nodes_in_group(RoomBuilder.GROUP_LIGHT):
		if light is OmniLight3D:
			light.light_color = color
			light.light_energy = energy
			# `visible` and not `light_energy = 0`: an energy-zero light still occupies one
			# of the renderer's light slots, which is the whole thing being economised.
			if culling:
				light.visible = _lit.get(light.get_meta("room_id", ""), true)

	for panel in get_tree().get_nodes_in_group(RoomBuilder.GROUP_LIGHT_PANEL):
		if panel is MeshInstance3D:
			var material := (panel as MeshInstance3D).material_override as StandardMaterial3D
			if material != null:
				material.albedo_color = color
				material.emission = color

	# The doorway signs. Unshaded sprites, so they are tinted rather than lit — see GROUP_SIGN.
	# Measured against NORMAL rather than against 1.0, so "normal" is exactly no change however
	# the mode table is retuned: at NORMAL this comes out white and the signs are untouched.
	var normal_energy: float = MODES[Mode.NORMAL]["light_energy"]
	var brightness := lerpf(1.0, energy / maxf(normal_energy, 0.001), SIGN_DIM)
	var tint := Color.WHITE.lerp(color, SIGN_TINT) * maxf(brightness, 0.35)
	tint.a = 1.0
	for sign_node in get_tree().get_nodes_in_group(GROUP_SIGN):
		if sign_node is GeometryInstance3D:
			(sign_node as GeometryInstance3D).set("modulate", tint)

	if _environment != null:
		_environment.ambient_light_color = values["ambient_color"]
		_environment.ambient_light_energy = values["ambient_energy"]
