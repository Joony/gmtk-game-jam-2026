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

## Emitted when the mode actually changes (not when re-set to the current mode).
signal mode_changed(mode: Mode)

@export var transition_time: float = 0.4
## Throb speed while pulsing. Step 12 can raise this as the countdown runs down.
@export var pulse_hz: float = 0.55

var mode: Mode = Mode.NORMAL

var _environment: Environment
var _from: Dictionary = MODES[Mode.NORMAL]
var _to: Dictionary = MODES[Mode.NORMAL]
var _blend: float = 1.0
var _time: float = 0.0


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


func set_mode(new_mode: Mode) -> void:
	if new_mode == mode:
		return
	_from = _current_values()
	_to = MODES[new_mode]
	_blend = 0.0
	mode = new_mode
	mode_changed.emit(mode)


func set_alert(on: bool) -> void:
	set_mode(Mode.ALERT if on else Mode.NORMAL)


func is_alert() -> bool:
	return mode == Mode.ALERT


func _process(delta: float) -> void:
	_time += delta
	if _blend < 1.0:
		_blend = 1.0 if transition_time <= 0.0 else minf(_blend + delta / transition_time, 1.0)
	_apply(_current_values())


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

	for light in get_tree().get_nodes_in_group(RoomBuilder.GROUP_LIGHT):
		if light is OmniLight3D:
			light.light_color = color
			light.light_energy = energy

	for panel in get_tree().get_nodes_in_group(RoomBuilder.GROUP_LIGHT_PANEL):
		if panel is MeshInstance3D:
			var material := (panel as MeshInstance3D).material_override as StandardMaterial3D
			if material != null:
				material.albedo_color = color
				material.emission = color

	if _environment != null:
		_environment.ambient_light_color = values["ambient_color"]
		_environment.ambient_light_energy = values["ambient_energy"]
