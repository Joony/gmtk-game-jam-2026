extends SceneTree
# Dev utility: WHY does turning around on the first load cost a frame?
#
# Two candidate causes look identical from the chair:
#   (a) draw cost - too many lights/meshes in view. Recurs EVERY time you face that way.
#   (b) a one-time cost - shader variants compiled, GPU resources uploaded, on first draw.
#       Happens once and never again.
#
# So: sweep the camera 360 degrees three times over and print per-frame times for each pass.
# If pass 1 spikes and passes 2-3 are flat, it is (b) and the lights are innocent.
#
# Run WITHOUT --headless:
#   godot --path . --resolution 1280x720 -s tests/probe_turn_hitch.gd

const STEPS := 72          # 5 degrees per step
const FRAMES_PER_STEP := 2
const PASSES := 3
## Stand in the cryo bay, where the run actually starts.
const AT := Vector3(6.0, 0.95, 11.0)

var _game: Node3D
var _player: CharacterBody3D
var _camera


func _init() -> void:
	_go.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _go() -> void:
	# Vsync would cap every frame at 16.7ms and hide exactly the spike being measured.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	_game = load("res://scenes/game.tscn").instantiate()
	root.add_child(_game)
	current_scene = _game
	await _frames(2)
	if _game.has_method("start_game"):
		_game.start_game()
	await _frames(30)

	_player = _game.get_node("Player")
	_camera = _player.get_node("CameraController") if _player.has_node("CameraController") \
		else _player.find_children("*", "CameraController", true, false)[0]

	var lights: int = _game.find_children("*", "OmniLight3D", true, false).size()
	var mode := "baseline"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = args[0]
	print("[probe] mode=%s  %d omni lights in the scene, vsync off" % [mode, lights])

	match mode:
		"nostars":
			for n in get_nodes_in_group(&"starfield"):
				(n as Node3D).visible = false
		"nolights":
			var lighting: LightingController = _game.get_node("Lighting")
			lighting.cull_by_room = false
			for n in _game.find_children("*", "OmniLight3D", true, false):
				(n as OmniLight3D).visible = false
		"nomodels":
			# Only the imported .blend props. The RoomBuilder's own geometry stays up.
			for n in _game.find_children("CD_*", "Node3D", false, false):
				(n as Node3D).visible = false
		"noship":
			# Only the RoomBuilder's geometry. The imported props stay up.
			(_game.get_node("Ship") as Node3D).visible = false

	# Face one way and settle, so the sweep starts from a warmed-up baseline the way the
	# player does: the game has been on screen for a moment before they turn.
	_player.global_position = AT
	_player.reset_physics_interpolation()
	_camera.set_look(0.0, 0.0)
	# Long enough for the whole opening to have played out - the stasis beat, the pod door, the
	# ride out. Those are one-off timed events, and at a 30-frame settle they landed INSIDE
	# pass 1 and read as a turn spike at a yaw that wandered from run to run.
	await _frames(240)

	# "warmup" renders the whole 360 once before the timed passes begin - the candidate FIX.
	if mode == "warmup":
		for step in STEPS:
			_camera.set_look(deg_to_rad(float(step) * (360.0 / float(STEPS))), 0.0)
			await _frames(1)
		_camera.set_look(0.0, 0.0)
		await _frames(4)

	for pass_i in PASSES:
		var times: Array[float] = []
		var yaws: Array[float] = []
		for step in STEPS:
			var yaw := float(step) * (360.0 / float(STEPS))
			_camera.set_look(deg_to_rad(yaw), 0.0)
			for f in FRAMES_PER_STEP:
				var t0 := Time.get_ticks_usec()
				await process_frame
				times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
				yaws.append(yaw)
		_report(pass_i, times, yaws)

	quit(0)


func _report(pass_i: int, times: Array[float], yaws: Array[float]) -> void:
	var sorted := times.duplicate()
	sorted.sort()
	var total := 0.0
	for t in times:
		total += t
	var mean := total / float(times.size())
	var median: float = sorted[sorted.size() / 2]
	var worst: float = sorted[sorted.size() - 1]

	# Where the bad frames landed, and how much time the sweep lost to them overall.
	var over := 0
	var lost := 0.0
	var spikes: PackedStringArray = []
	for i in times.size():
		if times[i] > median * 3.0 and times[i] > 5.0:
			over += 1
			lost += times[i] - median
			if spikes.size() < 8:
				spikes.append("%.0fdeg:%.1fms" % [yaws[i], times[i]])

	print("[probe] pass %d  median %.2fms  mean %.2fms  worst %.1fms  spikes %d (%.0fms lost)  %s"
		% [pass_i + 1, median, mean, worst, over, lost, " ".join(spikes)])
