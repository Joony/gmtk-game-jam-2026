class_name MouseCapture

# Single gate for grabbing the OS cursor.
#
# Capturing the mouse in a script run (`godot -s <script>`) steals the real cursor from
# whoever is using the machine, and — worse — their mouse movements are then fed to the
# camera, so screenshots come out at random angles and tests see phantom input. Script
# runs therefore do NOT capture unless they explicitly opt in.
#
# Tests that are specifically verifying capture/mouse-look set `allow_in_script_runs = true`
# first. Those runs DO briefly take the cursor, so run them deliberately, not casually.

## Opt-in for tests that genuinely need a captured cursor.
static var allow_in_script_runs: bool = false

## How long a capture request is given to land before capture_lost() will call it a failure.
## On web, capture() only *asks* the browser for pointer lock: is_captured() reads back
## `document.pointerLockElement`, which stays empty until the browser grants it a frame or two
## later. Without this window every successful capture would read as an instant loss.
const SETTLE_MS := 500

## Whether the game currently wants the cursor. Not the same as HAVING it — see capture_lost().
static var _wants_capture: bool = false
static var _requested_ms: int = 0


static func capture() -> void:
	if _is_script_run() and not allow_in_script_runs:
		return
	_wants_capture = true
	_requested_ms = Time.get_ticks_msec()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


static func release() -> void:
	_wants_capture = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


static func is_captured() -> bool:
	return Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED


## True when the game asked for the cursor, gave the request time to land, and still doesn't
## have it. In a browser that means pointer lock was taken away — the tab lost focus, the player
## clicked outside the canvas, or they hit the browser's own Esc. The game cannot simply ask for
## it back: browsers only grant pointer lock from a user gesture, so something has to notice and
## put a clickable thing in front of the player. That's the pause menu.
static func capture_lost() -> bool:
	if not _wants_capture or is_captured():
		return false
	return Time.get_ticks_msec() - _requested_ms > SETTLE_MS


# True when launched as `godot -s script.gd` / `--script` — a test or a screenshot
# capture, never the real game.
static func _is_script_run() -> bool:
	var args := OS.get_cmdline_args()
	return args.has("-s") or args.has("--script")
