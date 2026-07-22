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


static func capture() -> void:
	if _is_script_run() and not allow_in_script_runs:
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


static func release() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


static func is_captured() -> bool:
	return Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED


# True when launched as `godot -s script.gd` / `--script` — a test or a screenshot
# capture, never the real game.
static func _is_script_run() -> bool:
	var args := OS.get_cmdline_args()
	return args.has("-s") or args.has("--script")
