extends SceneTree
# TODO 20: the deck plan as a THING IN A ROOM, rather than as a drawing or as a data feed.
#
# The other two suites cover the other two halves and neither can see this one:
#
#   smoke_status_map      the drawing, against a hand-written problem list, no ship at all
#   smoke_status_console  the collection — what the run is doing turning into the right blobs
#   THIS ONE             where the chart physically IS: which way up, on which surface, whether
#                        the whole page is in frame from the pose the game walks you to, and
#                        which screens offer to be read at all
#
# EVERY BUG THIS FEATURE ACTUALLY HAD WAS IN THAT LAST CATEGORY, and none of them would have
# failed a single existing check:
#
#   * the quad's rotation, written as a `.tscn` basis literal, came out as the INVERSE — so the
#     chart faced down into the table and the bridge appeared to have no display on it;
#   * before that it was vertical, standing in a surface that turned out to be horizontal, with
#     two thirds of it buried inside the console;
#   * the reading pose put the camera 1.15 m back at eye height, which is right for a wall CRT
#     and wrong for a chart lying flat.
#
# Run: godot --headless --path . -s tests/smoke_status_displays.gd

## The suite must not be allowed to call itself green off half a run.
const MIN_CHECKS := 25

var _failures: Array[String] = []
var _checks: int = 0
var _game: Node3D
var _displays: ShipDisplays
var _bridge: ComputerTerminal
var _console: ComputerTerminal


func _init() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("status displays test timed out")
		quit(1))
	_go.call_deferred()


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _go() -> void:
	# THE HEADLESS WINDOW IS SQUARE (64x64, reporting a 1920x1920 visible rect), and the framing
	# check below projects through the real camera — so at the dummy aspect a chart that fits the
	# game's 16:9 view fails by 54 pixels on each side. Force the project's own viewport size, or
	# the test is measuring the test harness.
	root.size = Vector2i(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1920),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1080))
	await process_frame

	_game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(_game)
	current_scene = _game
	await _frames(8)
	# Started, and out of the pod, before anything below: the Interactor does not run until the
	# player is in control, and a ray that never fires would let the "no prompt on the nav plot"
	# check pass for entirely the wrong reason.
	_game.start_game()
	var waited := 0
	while _game._pod_phase != _game.PodPhase.OUT and waited < 900:
		waited += 1
		await process_frame
	_check("the player got out of the pod (%d frames)" % waited,
		_game._pod_phase == _game.PodPhase.OUT)
	await _frames(6)

	_displays = _game.get_node_or_null("Displays") as ShipDisplays
	_check("the displays node was built", _displays != null)
	if _displays == null:
		_finish()
		return
	_bridge = _displays.bridge_display
	_console = _game.get_node_or_null("Computer") as ComputerTerminal
	_check("the bridge deck plan was built", _bridge != null)
	_check("the pod bay console is still there", _console != null)
	if _bridge == null or _console == null:
		_finish()
		return

	_test_host()
	_test_lies_flat()
	_test_on_the_surface()
	_test_reading_pose()
	await _test_framing()
	await _test_prompts()
	_test_rides_with_its_host()

	_finish()


func _finish() -> void:
	if _checks < MIN_CHECKS:
		_failures.append("only %d of the expected %d checks ran — a section died early"
			% [_checks, MIN_CHECKS])
	if _failures.is_empty():
		print("STATUS DISPLAYS TEST PASS (%d checks)" % _checks)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("STATUS DISPLAYS TEST FAIL")
		quit(1)


# --- the model decides where the chart is -----------------------------------

## The whole placement contract in three checks: the chart hangs off the artist's `Display` empty,
## it carries no offset of its own, and the terminal bank the ray hits is underneath the
## Interactable. Break any one and the chart is somewhere nobody chose.
func _test_host() -> void:
	var screen := _bridge.find_child("Screen", true, false) as MeshInstance3D
	_check("the chart has a mesh", screen != null)
	if screen == null:
		return

	var display: Node = screen
	while display != null and display.name != ShipDisplays.DISPLAY_NODE:
		display = display.get_parent()
	_check("the chart hangs off the model's own '%s' empty" % ShipDisplays.DISPLAY_NODE,
		display != null)
	if display == null:
		return

	# No offset of its own beyond the anti-z-fight lift. The moment this carries a measured
	# position, moving the empty in Blender stops moving the chart.
	var plan := screen.get_parent() as Node3D
	_check("the chart is placed by the empty, not by a number in here (%v)" % plan.position,
		plan.position.length() < 0.001)
	_check("...and sits within a hair of it vertically (%.3f m)" % screen.position.y,
		absf(screen.position.y) < 0.05)

	# The ray hits the BANK, not a collider stuck over the chart, and walks up to the Interactable
	# from there — which is what makes the whole console readable rather than a 2 m sweet spot.
	var body := _bridge.find_child("StaticBody3D", true, false)
	_check("the terminal bank's own collider is under the interactable", body != null)
	if body != null:
		_check("...and resolves back to the deck plan",
			Interactor.find_interactable_in_hierarchy(body) == _bridge)


# --- which way up -----------------------------------------------------------

## THE ROTATION, asserted in world space rather than as an angle. A QuadMesh faces its own +Z and
## its "up" is +Y, so laying a chart flat and pointing it at the bow is one rotation with two
## consequences — and getting it wrong is silent, because a quad facing the wrong way is simply
## not drawn.
func _test_lies_flat() -> void:
	var screen := _bridge.find_child("Screen", true, false) as MeshInstance3D
	if screen == null:
		return
	var basis := screen.global_basis

	# The face points UP, off the table.
	var face := basis.z.normalized()
	_check("the chart faces up off the table (%v)" % face.snapped(Vector3.ONE * 0.01),
		face.dot(Vector3.UP) > 0.99)

	# ...and the map's own up points at the BOW, so the diagram agrees with the ship: MESS really
	# is on your left, CARGO really is behind you. Travel is -Z.
	var up := basis.y.normalized()
	_check("the map's up points at the bow (%v)" % up.snapped(Vector3.ONE * 0.01),
		up.dot(Vector3.FORWARD) > 0.99)

	# And it is not mirrored — the third axis has to come out the way a right-handed basis says,
	# or port and starboard swap and every check above still passes.
	var right := basis.x.normalized()
	_check("port stays on the left (%v)" % right.snapped(Vector3.ONE * 0.01),
		right.dot(Vector3.RIGHT) > 0.99)


## On the surface, not floating over it and not sunk into it. The lift is deliberate — coplanar
## geometry z-fights — but it is a hair, not a hover.
func _test_on_the_surface() -> void:
	var screen := _bridge.find_child("Screen", true, false) as MeshInstance3D
	if screen == null:
		return
	var lift := screen.position.y
	_check("the chart is lifted clear of the table (%.4f m)" % lift, lift > 0.0)
	_check("...but only just, so it reads as printed on it (%.4f m)" % lift, lift < 0.03)

	# It also has to FIT. The measured plateau on CD_BridgeTerminals_v2 is 2.16 x 2.38 m, so a
	# chart wider than that hangs off the table in mid-air.
	var quad := screen.mesh as QuadMesh
	_check("the chart fits the table it lies on (%.2f x %.2f m)" % [quad.size.x, quad.size.y],
		quad.size.x <= 2.16 and quad.size.y <= 2.38)
	# ...and is not stretched: the viewport is 1024x640, so the quad must be 1.6:1 or the drawing
	# is squashed, which on an octilinear diagram means the 45 degree stubs stop being 45 degrees.
	_check("and is not stretched (%.3f vs 1.600)" % (quad.size.x / quad.size.y),
		absf(quad.size.x / quad.size.y - 1.6) < 0.01)


# --- the pose the game walks you to -----------------------------------------

## You do not stand BACK from a map lying flat, you stand OVER it. This is the check that would
## have caught the original pose — 1.15 m back at eye height, correct for a wall CRT and wrong
## here, with the far edge of the chart further away than the near edge.
func _test_reading_pose() -> void:
	var screen := _bridge.find_child("Screen", true, false) as MeshInstance3D
	if screen == null:
		return
	var chart := screen.global_position
	var view := _bridge.view_transform()
	# view_transform() carries the BODY position; the camera anchor rides above it.
	var eye := view.origin + Vector3(0.0, _displays.eye_height, 0.0)

	_check("the eye is above the chart (%.2f m)" % (eye.y - chart.y), eye.y > chart.y + 0.5)
	var over := Vector2(eye.x - chart.x, eye.z - chart.z).length()
	_check("...and more above it than back from it (%.2f up vs %.2f back)" % [
		eye.y - chart.y, over], (eye.y - chart.y) > over)

	# The pitch has to be IN the marker. Every readable thing on the ship used to be at eye height,
	# so Game passed a hardcoded 0.0 for it — and a flat chart read from a level camera is a
	# horizon line.
	var pitch := view.basis.get_euler().x
	_check("the marker carries a downward pitch (%.1f deg)" % rad_to_deg(pitch),
		pitch < deg_to_rad(-45.0))
	_check("...and not straight down, which would be a ceiling camera (%.1f deg)"
		% rad_to_deg(pitch), pitch > deg_to_rad(-85.0))

	# Looking AT it, not past it.
	var forward := -view.basis.z.normalized()
	_check("and the pose looks at the chart", forward.dot((chart - eye).normalized()) > 0.99)


## The whole page in frame, projected through the real camera. The pose can be pitched correctly
## and still cut the chart in half if it is too close, and no assertion above would notice.
func _test_framing() -> void:
	var screen := _bridge.find_child("Screen", true, false) as MeshInstance3D
	if screen == null:
		return
	var camera := _game.get_node_or_null("Player/CameraRig/Camera3D") as Camera3D
	_check("the player has a camera to project through", camera != null)
	if camera == null:
		return

	# Put the PLAYER where reading would put them and let CameraController pose the camera, so
	# this measures the view the game actually produces rather than one assembled here.
	var view := _bridge.view_transform()
	var pose := view.basis.get_euler()
	var player: CharacterBody3D = _game.get_node("Player")
	var rig := _game.get_node("Player/CameraRig") as CameraController
	player.global_position = view.origin
	player.reset_physics_interpolation()
	rig.set_look(pose.y, pose.x)
	await _frames(6)

	var quad := screen.mesh as QuadMesh
	var half := quad.size * 0.5
	var size := camera.get_viewport().get_visible_rect().size
	var inside := 0
	var report := PackedStringArray()
	for corner in [
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(-half.x, half.y), Vector2(half.x, half.y),
	]:
		var world := screen.global_transform * Vector3(corner.x, corner.y, 0.0)
		_check("the chart's corner %v is in front of the camera" % corner,
			not camera.is_position_behind(world))
		var at := camera.unproject_position(world)
		report.append("%v->%v" % [corner, at.snapped(Vector2.ONE)])
		if Rect2(Vector2.ZERO, size).has_point(at):
			inside += 1
	_check("all four corners of the chart are on screen (%d of 4, viewport %v: %s)" % [
		inside, size, ", ".join(report)], inside == 4)


# --- which screens ask to be read -------------------------------------------

func _test_prompts() -> void:
	# ONE PAGE EACH, so neither screen can turn into the other.
	_check("the console is the nav plot only",
		_console.pages == [ComputerTerminal.Page.NAV])
	_check("the bridge display is the deck plan only",
		_bridge.pages == [ComputerTerminal.Page.STATUS])

	# NO [E] ON THE NAV PLOT. `is_enabled` is what Interactor._cast() tests, so a screen that
	# fails it never becomes the focus at all — there is no prompt to suppress separately and no
	# half-lit reticle over it.
	_check("the nav plot cannot be leaned into", not _console.lean_in)
	_check("the deck plan still can be", _bridge.lean_in and _bridge.is_enabled)
	_check("and its prompt names what is on it (%s)" % _bridge.get_interaction_text(),
		_bridge.get_interaction_text().to_lower().contains("deck plan"))

	# THE GATE ITSELF. `Interactor._cast()` drops anything whose `can_interact()` is false before
	# it ever becomes the focus, so this is the property, stated directly.
	#
	# But only while the screen is HEALTHY. The nav computer is itself a repairable system now
	# (ShipFaults, "the bridge computer IS the repair point"), and a broken one has to be a ray
	# target even with `lean_in` off — otherwise the player watches a red flashing console and
	# cannot touch it. So the run has to be put in a known state before any of this means
	# anything: the run OPENS on that fault broken, which is the opening tutorial.
	# Found through the group rather than off the terminal, which keeps its fault private — and
	# through `is_broken()`, which is the terminal's own public answer to the same question.
	var fault: Malfunction = null
	for node in get_nodes_in_group(Malfunction.GROUP_MALFUNCTION):
		var m := node as Malfunction
		if m != null and _console.is_broken() and m.is_active and m.speed_penalty > 0.0:
			fault = m
			break
	_check("the nav computer is a repairable system", fault != null)
	if fault == null:
		return
	_check("and the run opens with it broken — the opening tutorial", _console.is_broken())
	_check("a broken screen IS a ray target, whatever lean_in says", _console.can_interact(null))

	var run: RunState = _game.get_node("Run")
	fault.repair(true, run.distance_remaining)
	await _frames(2)
	_check("a healthy nav plot refuses to be interacted with", not _console.can_interact(null))
	# ...and it is `is_enabled` that does it: Interactor._cast() tests that before anything else,
	# so a screen failing it never becomes the focus at all — no prompt to suppress separately and
	# no half-lit reticle over it. Asserted HERE rather than up with `lean_in`, because a broken
	# console overrides `is_enabled` back to true so it can still be repaired.
	_check("...which is what takes it out of the interaction ray", not _console.is_enabled)
	_check("the deck plan always accepts it", _bridge.can_interact(null))

	# ...and then proved through the REAL ray, because "never becomes the focus" is a property of
	# Interactor rather than of the terminal. SWEPT over several standing distances rather than
	# asserted from one lucky spot: the surfaces are waist height, so a couple of degrees is the
	# difference between hitting the bank and skimming over it, and a single position would make
	# this a test of my arithmetic.
	var player: CharacterBody3D = _game.get_node("Player")
	var rig := _game.get_node("Player/CameraRig") as CameraController
	var interactor: Interactor = _game.get_node("Player/Interactor")

	var chart := (_bridge.find_child("Screen", true, false) as Node3D).global_position
	var console_screen := _console.global_position + Vector3(0.0, 1.33, 0.0)
	var saw_console := 0
	var saw_chart := 0
	for back in [1.4, 1.7, 2.0, 2.4]:
		if await _looks_at(player, rig, interactor, console_screen, back) == _console:
			saw_console += 1
		if await _looks_at(player, rig, interactor, chart, back) == _bridge:
			saw_chart += 1
	_check("a healthy nav plot never becomes the focus, from any distance (%d of 4)"
		% saw_console, saw_console == 0)
	_check("the deck plan does (%d of 4)" % saw_chart, saw_chart > 0)

	# Break it again and the prompt comes back, or the fault is unfixable.
	fault.break_now()
	await _frames(2)
	var saw_broken := 0
	for back in [1.4, 1.7, 2.0]:
		if await _looks_at(player, rig, interactor, console_screen, back) == _console:
			saw_broken += 1
	_check("but a broken one does, so it can be repaired (%d of 3)" % saw_broken, saw_broken > 0)


## Stand `back` metres aft of `target`, aim straight at it, and report what the Interactor picked.
## Aimed rather than given a fixed pitch — a few degrees either way at waist height is the
## difference between hitting a console and skimming over it.
func _looks_at(player: CharacterBody3D, rig: CameraController, interactor: Interactor,
		target: Vector3, back: float) -> Interactable:
	player.global_position = Vector3(target.x, 0.9, target.z + back)
	player.reset_physics_interpolation()
	var eye := player.global_position + Vector3(0.0, 0.65, 0.0)
	var to_target := (target - eye).normalized()
	rig.set_look(atan2(-to_target.x, -to_target.z), asin(clampf(to_target.y, -1.0, 1.0)))
	await _frames(8)
	return interactor.current


# --- the host can move ------------------------------------------------------

## The display is parented into the bank's own frame, and that is load-bearing rather than tidy:
## `CD_BridgeTerminals` has an outstanding hull-clipping fix (a scale, or a shallower model), and
## the bank has already moved once mid-build — from `Decor` to the top of the scene.
func _test_rides_with_its_host() -> void:
	var screen := _bridge.find_child("Screen", true, false) as Node3D
	var marker := _bridge.find_child("ViewPoint", true, false) as Node3D
	if screen == null or marker == null:
		_check("the chart and its marker both exist", false)
		return

	var was_screen := screen.global_position
	var was_marker := marker.global_position
	var shift := Vector3(3.0, 0.0, 1.0)
	_bridge.global_position += shift
	# Position is derived from the parent chain, so no frame needs to pass.
	_check("moving the bank moves the chart with it",
		screen.global_position.distance_to(was_screen + shift) < 0.001)
	_check("...and the reading position with it",
		marker.global_position.distance_to(was_marker + shift) < 0.001)
	_bridge.global_position -= shift
	_check("and putting it back puts them back",
		screen.global_position.distance_to(was_screen) < 0.001)
