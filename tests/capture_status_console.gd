extends SceneTree
# TODO 19 Phase 2, proved end to end: the damage plan on the REAL console, in the room.
#
# smoke_status_console tests the collection and the page logic with no renderer at all, and
# capture_status_map measures the page in isolation. Neither of them can catch the thing that
# actually goes wrong when a Control is put on a screen in a room — that the second page was
# added to the scene but never reaches the quad, because the SubViewport texture, the material's
# resource_local_to_scene flag and the node path all have to line up (see the note in
# computer.tscn about how easily that goes wrong).
#
# So this walks the player up to the console the way the game does, with a fault actually broken,
# and photographs what is on the glass.
#
# Needs a real renderer, so NOT --headless:
#   godot --path . --resolution 1280x720 -s tests/capture_status_console.gd -- <out_dir>

var _game: Node3D
var _player: CharacterBody3D
var _camera: CameraController
var _run: RunState
var _computer: ComputerTerminal
var _failures: Array[String] = []
var _dir: String = "user://"


func _init() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("status console capture timed out")
		quit(1))
	_go.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> Image:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "%s/%s.png" % [_dir, shot_name]
	if image.save_png(path) != OK:
		push_error("save_png failed for %s" % path)
	else:
		print("saved %s" % path)
	return image


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_dir = args[0]

	_game = load("res://scenes/game.tscn").instantiate()
	root.add_child(_game)
	current_scene = _game
	await _frames(4)
	_game.start_game()
	# The run opens with the player SEALED IN THE POD and rides them out of it over about a
	# second and a half. `_open_nav_screen()` refuses while that is happening — quite correctly,
	# the pod is not yours to leave until the lid has moved — so a fixed frame count here is a
	# coin flip. Wait for the actual state.
	var waited := 0
	while _game._pod_phase != _game.PodPhase.OUT and waited < 600:
		waited += 1
		await process_frame
	_check("the player got out of the pod (%d frames)" % waited,
		_game._pod_phase == _game.PodPhase.OUT)
	await _frames(10)

	_player = _game.get_node("Player")
	_camera = _game.get_node("Player/CameraRig")
	_run = _game.get_node("Run")
	_computer = _game.get_node("Computer")

	# Break a spread of things, so the shot shows what the page is for: two rooms with faults,
	# one with a supply run, and the engine room carrying more than one problem at once.
	(_game.get_node("MainDrive") as Malfunction).break_now()
	(_game.get_node("CoolantLoop") as Malfunction).break_now()
	var life: Silo = _run.silo_by_id(&"life_support")
	if life != null:
		while not life.is_exhausted():
			life.use()
	await _frames(20)

	# Stand where the player stands to read it, and let the console pick its own page.
	_player.global_position = Vector3(4.9, 0.9, 5.0)
	_player.reset_physics_interpolation()
	_camera.set_look(deg_to_rad(-90.0), 0.0)
	await _frames(14)
	await _shot("01_console_in_the_room")

	# Lean in, the way interacting does.
	_game._open_nav_screen()
	var glided := 0
	while _game._nav_phase != _game.NavPhase.READING and glided < 300:
		glided += 1
		await process_frame
	_check("leaning in reached the reading state (%d frames)" % glided,
		_game._nav_phase == _game.NavPhase.READING)
	_check("...and put the damage plan up, unasked",
		_computer.page == ComputerTerminal.Page.STATUS)
	var status_a := await _shot("02_reading_damage_plan")

	# Flip to the nav plot and back, which is what left/right does while reading.
	_computer.flip_page()
	await _frames(6)
	_check("flipping shows the nav plot", _computer.page == ComputerTerminal.Page.NAV)
	var plot := await _shot("03_reading_nav_plot")

	_computer.flip_page()
	await _frames(6)
	_check("flipping back returns to the damage plan",
		_computer.page == ComputerTerminal.Page.STATUS)
	var status_b := await _shot("04_flipped_back")

	# THE MEASUREMENT, and it is a RELATIVE one on purpose. An absolute "is there red on the
	# screen" test is worthless in this room: a critical fault trips the ship-wide red alert, so
	# the walls, the ceiling and the HUD's own fault rows are all trouble-coloured and the count
	# comes out the same whatever is on the glass. What is not the same is the glass itself —
	# so compare the two pages to each other, against a control of the same page twice.
	var swapped := _diff(status_a, plot)
	var control := _diff(status_a, status_b)
	print("  screen pixels changed: page swap %.1f%%, same page %.1f%%" % [
		swapped * 100.0, control * 100.0])
	_check("swapping the page changes what is on the glass (%.1f%%)" % (swapped * 100.0),
		swapped > 0.08)
	# Without this the first check would pass off the starfield outside the window and the
	# clock ticking, neither of which has anything to do with the console.
	_check("...far more than the room changes on its own (%.1f%% vs %.1f%%)" % [
		swapped * 100.0, control * 100.0], swapped > control * 3.0)

	# Stepping away drops the manual choice.
	_game._nav_screen.close()
	await _frames(60)
	_check("stepping away hands the page back to the console",
		not _computer.is_page_manual())

	if _failures.is_empty():
		print("STATUS CONSOLE CAPTURE PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("STATUS CONSOLE CAPTURE FAIL")
		quit(1)


## Fraction of pixels that differ, over the middle of the view — which is where the console's
## glass is once the camera has been walked up to it.
func _diff(a: Image, b: Image) -> float:
	var x0 := int(a.get_width() * 0.28)
	var x1 := int(a.get_width() * 0.72)
	var y0 := int(a.get_height() * 0.22)
	var y1 := int(a.get_height() * 0.72)
	var changed := 0
	var total := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			total += 1
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > 0.05:
				changed += 1
	return 0.0 if total == 0 else float(changed) / float(total)
