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

# --- Field depth -----------------------------------------------------------------
# The star field spans a fixed depth range, so at speed a star crosses the whole range
# in well under a second: it fades in, streaks, and fades out almost at once, which
# reads as stars vanishing mid-view. Scaling the grid WITH speed fixes that — cell size
# and the near/far limits grow together, so angular density and star size are unchanged
# but each star lasts proportionally longer.
#
# TRADE-OFF: scaling fully would make warp look like cruise (apparent motion is
# speed/cell_size, so scaling cell with speed cancels it out). This factor is the dial:
# 0 keeps the old behaviour and the full sense of speed but short-lived stars; 1.0 makes
# stars maximally persistent but flattens the speed sensation. The streaking carries the
# speed impression either way.
@export_range(0.0, 1.0) var field_stretch_with_speed: float = 0.35
@export var base_cell_size: float = 45.0
@export var base_near_distance: float = 15.0
@export var base_far_distance: float = 700.0

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

## Set by step 12 once there is a distance countdown: 0 hides the destination entirely.
var destination_brightness: float = 0.0


func _ready() -> void:
	speed = cruise_speed


func _process(delta: float) -> void:
	distance_travelled += speed * delta
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
		adjust_speed(1.0)
	elif event.is_action_pressed("speed_down"):
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
		var stretch := 1.0 + speed_ratio() * field_stretch_with_speed * max_speed_multiplier / 4.0
		material.set_shader_parameter("cell_size", base_cell_size * stretch)
		material.set_shader_parameter("near_distance", base_near_distance * stretch)
		material.set_shader_parameter("far_distance", base_far_distance * stretch)
		material.set_shader_parameter("streak", minf(streak_at_cruise * speed_ratio(), max_streak))
		material.set_shader_parameter("destination_brightness", destination_brightness)
