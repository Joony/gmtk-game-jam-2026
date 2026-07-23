class_name ShipMotion
extends Node

# The ship's travel state, and the single source of truth for the starfield.
#
# The stars live on a BACKDROP SHELL around the ship, not on panes in the windows.
# That makes each window a genuine hole: real geometry outside the hull (a station,
# a planet, debris) is simply visible through it, correctly occluded by the walls and
# correctly parallaxed, because it is actually there.
#
# Same push-to-a-group pattern as LightingController, so anything added to the
# `starfield` group later is driven with no registration step.

## Anything carrying the starfield material — currently the backdrop shell.
const GROUP_STARFIELD := &"starfield"

signal speed_changed(speed: float)
## Emitted when a tuning value (currently star density) changes.
signal settings_changed

## Metres per second at full health. Step 12 scales the actual speed down per malfunction.
@export var cruise_speed: float = 18.0
@export var travel_direction: Vector3 = Vector3(0, 0, -1)
## Star brightness, exposed for tuning against the interior lighting.
@export var star_brightness: float = 1.6
## How much the stars smear at cruise speed.
@export var streak_at_cruise: float = 0.7
## Fraction of cells containing a star — the main "how many stars" control.
## Driven from here rather than left on the material so it can be changed at runtime.
@export_range(0.0, 1.0) var star_density: float = 0.15
## Ceiling for the speed control, as a multiple of cruise. High enough that the stars
## become long streaks rather than points.
@export var max_speed_multiplier: float = 60.0
## Each speed key press MULTIPLIES by this. Additive steps cannot span 0 to 60x cruise
## in a usable number of presses; multiplicative gives fine control when slow and a
## fast climb when fast.
@export var speed_step_factor: float = 1.5
## Streak is unbounded by speed otherwise, and past a point the sky turns into a smear.
@export var max_streak: float = 22.0

# NOTE: the star grid's cell size and range are deliberately NOT driven from here.
# An earlier version scaled them with speed so stars would last longer at speed, but
# changing cell_size re-rolls the whole grid — every star jumps to a new position, which
# read as the sky flickering whenever you changed speed. Stars are fixed objects: going
# faster moves you past them faster, nothing more. The distant shell supplies the
# persistence that scaling was trying to buy.

## Current speed. Zero stops the starfield dead, which is what a stalled ship should look like.
var speed: float = 0.0:
	set(value):
		var clamped := maxf(value, 0.0)
		if is_equal_approx(clamped, speed):
			return
		speed = clamped
		speed_changed.emit(speed)

## Total distance covered. Stars sit at fixed world positions, so this is what streams them.
var distance_travelled: float = 0.0

## Set by RunState as the destination nears: 0 hides it entirely.
var destination_brightness: float = 0.0

## Ship time per real second. RunState raises this while the player is in stasis, which
## is what makes fast-forward *look* like fast-forward: the stars stream and streak at
## the scaled rate without touching Engine.time_scale (that would speed the player up too).
var time_scale: float = 1.0

## Set by RunState for the duration of a run. Speed is then a function of which systems
## are broken, rewritten every frame — so the debug speed keys would silently accomplish
## nothing. Better to switch them off than to leave them looking broken. The star-density
## keys are untouched, since nothing else drives those.
var speed_driven_externally: bool = false


func _ready() -> void:
	speed = cruise_speed


func _process(delta: float) -> void:
	distance_travelled += speed * delta * time_scale
	_apply()


## Fraction of cruise speed, clamped to 0..1 — for game logic ("how healthy are we?").
func speed_fraction() -> float:
	if cruise_speed <= 0.0:
		return 0.0
	return clampf(speed / cruise_speed, 0.0, 1.0)


## Unclamped ratio, for visuals: above cruise the stars should keep stretching.
func speed_ratio() -> float:
	if cruise_speed <= 0.0:
		return 0.0
	return speed / cruise_speed


## Nudge the speed, multiplicatively. `steps` is the number of key presses.
func adjust_speed(steps: float) -> void:
	var target := speed
	if steps > 0.0:
		# From a standstill there is nothing to multiply, so start from a slow crawl.
		target = maxf(speed, cruise_speed * 0.04) * pow(speed_step_factor, steps)
	elif steps < 0.0:
		target = speed / pow(speed_step_factor, -steps)
		if target < cruise_speed * 0.02:
			target = 0.0
	speed = clampf(target, 0.0, cruise_speed * max_speed_multiplier)


func adjust_density(amount: float) -> void:
	star_density = clampf(star_density + amount, 0.0, 1.0)
	settings_changed.emit()


# Debug/tuning keys. Step 12 drives speed from malfunctions instead; these stay useful
# for dialling in the look, and are harmless because they only exist while unpaused.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("speed_up"):
		if speed_driven_externally:
			return
		adjust_speed(1.0)
	elif event.is_action_pressed("speed_down"):
		if speed_driven_externally:
			return
		adjust_speed(-1.0)
	elif event.is_action_pressed("stars_more"):
		adjust_density(0.05)
	elif event.is_action_pressed("stars_fewer"):
		adjust_density(-0.05)
	else:
		return
	get_viewport().set_input_as_handled()


func _apply() -> void:
	for pane in get_tree().get_nodes_in_group(GROUP_STARFIELD):
		var material := (pane as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
		if material == null:
			material = (pane as MeshInstance3D).material_override as ShaderMaterial
		if material == null:
			continue
		material.set_shader_parameter("travel_direction", travel_direction.normalized())
		material.set_shader_parameter("travelled", distance_travelled)
		material.set_shader_parameter("brightness", star_brightness)
		material.set_shader_parameter("star_density", star_density)
		# Stretch only ABOVE cruise. The previous form scaled by speed_ratio directly,
		# so at cruise it already pushed the field 4x further out and the near stars
		# barely moved — the stretch has to be 1.0 at normal speed by construction.
		# time_scale counts toward the streak: in stasis you are covering ground 24x faster,
		# so the sky should smear like it.
		material.set_shader_parameter("streak", minf(streak_at_cruise * speed_ratio() * time_scale, max_streak))
		material.set_shader_parameter("destination_brightness", destination_brightness)
