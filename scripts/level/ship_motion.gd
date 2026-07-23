class_name ShipMotion
extends Node

# The ship's travel state, and the single source of truth every window reads from — so
# they can never disagree about speed or heading.
#
# Same pattern as LightingController: values are pushed to everything in the
# `space_windows` group each frame, so a window built later (a new room, a repaired
# section) picks up the current motion with no registration step.

signal speed_changed(speed: float)

## Metres per second at full health. Step 12 scales the actual speed down per malfunction.
@export var cruise_speed: float = 18.0
@export var travel_direction: Vector3 = Vector3(0, 0, -1)
## Star brightness, exposed for tuning against the interior lighting.
@export var star_brightness: float = 1.6
## How much the stars smear at cruise speed.
@export var streak_at_cruise: float = 0.7

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


## Fraction of cruise speed, for anything that wants "how fast are we going, really".
func speed_fraction() -> float:
	if cruise_speed <= 0.0:
		return 0.0
	return clampf(speed / cruise_speed, 0.0, 1.0)


func _apply() -> void:
	var fraction := speed_fraction()
	for pane in get_tree().get_nodes_in_group(RoomBuilder.GROUP_WINDOW):
		var material := (pane as MeshInstance3D).material_override as ShaderMaterial
		if material == null:
			continue
		material.set_shader_parameter("travel_direction", travel_direction.normalized())
		material.set_shader_parameter("travelled", distance_travelled)
		material.set_shader_parameter("brightness", star_brightness)
		material.set_shader_parameter("streak", streak_at_cruise * fraction)
		material.set_shader_parameter("destination_brightness", destination_brightness)
