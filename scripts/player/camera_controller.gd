class_name CameraController
extends Node3D

# First-person mouse look, ported from Doortal. Two-clock camera: POSITION comes
# from the interpolated body (smooth while walking), ROTATION is applied directly
# each render frame. Rotation is input-driven rather than physics-driven, so
# routing it through get_global_transform_interpolated() (sampled at the physics
# tick) reintroduces visible rotation stepping. Taking only .origin keeps position
# smooth without interpolating rotation.
#
# Requires physics/common/physics_interpolation = true in project settings.
#
# Mouse capture is deliberately NOT handled here — the pause menu owns the cursor
# so there is a single source of truth for capture state.

## Turned off while the camera is being driven by something else — the ride into the
## stasis pod, for instance. The controller keeps running (so the view still tracks and
## renders smoothly), it just stops taking the mouse.
@export var input_enabled: bool = true
@export var mouse_sensitivity: float = 0.002
@export var pitch_min_deg: float = -89.0
@export var pitch_max_deg: float = 89.0

var _player: CharacterBody3D
var _anchor: Node3D
var _pitch: float = 0.0
var _yaw: float = 0.0
var _mouse: Vector2 = Vector2.ZERO


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	_anchor = _player.get_node("CameraAnchor")
	_yaw = _player.rotation.y


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		# Use screen_relative, NOT relative: with window/stretch/mode=canvas_items the
		# viewport `relative` delta is scaled and re-quantized by the stretch/DPI matrix,
		# which shows up as discrete rotation steps on slow mouse movement.
		# screen_relative is the raw, untransformed screen-pixel delta.
		_mouse.x += -event.screen_relative.x * mouse_sensitivity
		_mouse.y += -event.screen_relative.y * mouse_sensitivity


func _process(_delta: float) -> void:
	_pitch = clampf(_pitch + _mouse.y, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	_yaw += _mouse.x
	_mouse = Vector2.ZERO
	# Pitch on the anchor, yaw on the body — these drive the physics-side hold
	# point and the movement wishdir (read in _physics_process).
	_anchor.transform.basis = Basis.from_euler(Vector3(_pitch, 0.0, 0.0))
	_player.global_transform.basis = Basis.from_euler(Vector3(0.0, _yaw, 0.0))
	var eye: Vector3 = _anchor.get_global_transform_interpolated().origin
	global_transform = Transform3D(Basis.from_euler(Vector3(_pitch, _yaw, 0.0)), eye)


# Place the camera at the anchor NOW, reading the anchor's real transform rather than its
# interpolated one. _process normally reads get_global_transform_interpolated(), which on
# the very first frame after a teleport lerps from identity — showing the world origin for
# one frame. Call this right after moving the player to skip that frame.
func snap_to_body() -> void:
	adopt_body_yaw()
	_anchor.transform.basis = Basis.from_euler(Vector3(_pitch, 0.0, 0.0))
	global_transform = Transform3D(Basis.from_euler(Vector3(_pitch, _yaw, 0.0)), _anchor.global_transform.origin)
	reset_physics_interpolation()


# Re-derive yaw from the body's current basis. Needed if anything other than this
# controller rotates the player body (this controller otherwise overwrites the
# body basis every frame and would discard that rotation).
func adopt_body_yaw() -> void:
	_yaw = _player.global_transform.basis.get_euler().y


func get_yaw() -> float:
	return _yaw


func get_pitch() -> float:
	return _pitch


## Aim the camera directly. Used to fly the view into and out of the pod: the controller
## overwrites the body basis from `_yaw` every frame, so rotating the body from outside
## would simply be discarded — the yaw has to be set here instead.
func set_look(yaw: float, pitch: float) -> void:
	_yaw = yaw
	_pitch = clampf(pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	_mouse = Vector2.ZERO
