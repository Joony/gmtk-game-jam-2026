extends SceneTree
# Dev utility: does a room stay lit as you turn on the spot?
#
# GL Compatibility caps how many lights one MESH can receive
# (rendering/limits/opengl/max_lights_per_object, default 8) and how many the renderer will
# draw at all (max_renderable_lights, default 32). RoomBuilder deliberately emits ONE box per
# floor and ceiling, so a big room's floor is a single mesh asking for every light above it.
# Past the cap the renderer keeps the lights it likes best for the current view — so the floor
# dims and brightens as the camera turns, which is not something any numeric test was looking
# for.
#
# Prints the mean luminance of each shot so the effect is a NUMBER, not an impression.
#
# Run WITHOUT --headless:
#   godot --path . --resolution 1280x720 -s tests/capture_lighting.gd -- <out_dir>

var _game: Node3D
var _player: CharacterBody3D
var _camera: CameraController
var _dir: String = "user://"

# Stand on CLEAR floor in the worst offenders and turn all the way round. Not the room
# centres: the pod bay's centre is inside the CryoStation furnace and the engine room's is
# among the drive props, so a centre sample measures those meshes rather than the floor.
const SPOTS := [
	{"name": "cargo_bay", "at": Vector3(29.5, 0.95, 15.5)},
	{"name": "pod_bay", "at": Vector3(7.0, 0.95, 12.0)},
	{"name": "engine_room", "at": Vector3(-30.0, 0.95, 13.0)},
]
const YAWS := [0, 90, 180, 270]


func _init() -> void:
	_go.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_dir = args[0]

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

	var lights := 0
	for _l in _game.find_children("*", "OmniLight3D", true, false):
		lights += 1
	print("[lighting] %d omni lights in the scene" % lights)
	print("[lighting] max_lights_per_object = %s, max_renderable_lights = %s" % [
		ProjectSettings.get_setting("rendering/limits/opengl/max_lights_per_object", 8),
		ProjectSettings.get_setting("rendering/limits/opengl/max_renderable_lights", 32),
	])

	# The HUD, the fault banner and the subtitles are all bright text over the middle of the
	# frame. Measuring luminance with them up measures THEM.
	for overlay in ["HUD", "Reticle", "DebugReadout", "NavScreen"]:
		var node := _game.get_node_or_null(overlay)
		if node != null:
			(node as CanvasLayer).visible = false

	# The run opens on a broken drive, so the ship is in ALERT: red at 1.15 energy against
	# NORMAL's near-white at 1.6. Red carries about a fifth of white's luminance, so an alert
	# frame reads as almost black whatever the light count is. Force NORMAL — this is a
	# measurement of how many lights reach a surface, not of the mode.
	var lighting: LightingController = _game.get_node("Lighting")
	lighting.transition_time = 0.0
	lighting.set_mode(LightingController.Mode.NORMAL)
	await _frames(4)

	for spot in SPOTS:
		var readings: Array[float] = []
		for yaw in YAWS:
			_player.global_position = spot["at"]
			_player.reset_physics_interpolation()
			# Look DOWN at the floor. A level shot frames windows, and the nebula outside is
			# far brighter than any interior surface — the metric ends up reporting the view,
			# not the lighting. Pitch -70 fills the frame with the one mesh this is about.
			_camera.set_look(deg_to_rad(float(yaw)), deg_to_rad(-70.0))
			await _frames(14)
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			readings.append(_mean_luminance(image))
			var path := "%s/light_%s_yaw%d.png" % [_dir, spot["name"], yaw]
			if image.save_png(path) != OK:
				push_error("save_png failed for %s" % path)
		var lo: float = readings.min()
		var hi: float = readings.max()
		var spread: float = (hi - lo) / maxf(hi, 0.0001)
		var on := 0
		for l in _game.find_children("*", "OmniLight3D", true, false):
			if (l as OmniLight3D).visible:
				on += 1
		print("[lighting] %-12s floor luminance by yaw %s  spread %.0f%%  (%d/%d lights on)" % [
			spot["name"], _fmt(readings), spread * 100.0, on, lights])

	# --- ALERT mode reaches every surface ------------------------------------
	# A surface lit by something OTHER than the room's own fixtures does not turn red with the
	# rest of the ship. That is how the exterior-layer collision showed up: ExteriorSun is a
	# white DirectionalLight3D masked to layer 2, so when the pod bay was handed layer 2 its
	# floor and the two walls facing the sun stayed grey while the other two went red.
	#
	# Measured as redness, r / (g + b): a red-lit surface is well above 1, a white-lit one
	# sits near 0.5. Sampled at the floor and at all four walls of the pod bay.
	lighting.set_mode(LightingController.Mode.ALERT)
	lighting.pulse_hz = 0.0  # hold it steady, or the throb makes the reading a coin flip
	await _frames(6)
	var worst := 999.0
	var worst_at := ""
	for probe in [["floor", 0.0, -70.0], ["fore wall", 0.0, 0.0], ["stbd wall", -90.0, 0.0],
			["aft wall", 180.0, 0.0], ["port wall", 90.0, 0.0]]:
		_player.global_position = Vector3(7.0, 0.95, 12.0)
		_player.reset_physics_interpolation()
		_camera.set_look(deg_to_rad(float(probe[1])), deg_to_rad(float(probe[2])))
		await _frames(14)
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.resize(64, 36, Image.INTERPOLATE_BILINEAR)
		var r := 0.0
		var gb := 0.0
		for y in image.get_height():
			for x in image.get_width():
				var c := image.get_pixel(x, y)
				r += c.r
				gb += c.g + c.b
		var redness := r / maxf(gb, 0.0001)
		if redness < worst:
			worst = redness
			worst_at = String(probe[0])
		print("[alert] pod bay %-10s redness %.2f" % [probe[0], redness])
	print("[alert] weakest surface: %s at %.2f  %s" % [worst_at, worst,
		"OK - every surface is red-lit" if worst > 1.0 else "*** a surface is not red ***"])

	quit(0)


func _fmt(values: Array[float]) -> String:
	var parts: PackedStringArray = []
	for v in values:
		parts.append("%.3f" % v)
	return "[" + ", ".join(parts) + "]"


## Mean perceptual luminance of the frame, 0..1.
func _mean_luminance(image: Image) -> float:
	# Downsample first: this is a whole-frame average, and 1280x720 pixel-by-pixel in
	# GDScript is slow enough to trip the harness.
	var small := image.duplicate() as Image
	small.resize(64, 36, Image.INTERPOLATE_BILINEAR)
	var total := 0.0
	for y in small.get_height():
		for x in small.get_width():
			var c := small.get_pixel(x, y)
			total += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
	return total / float(small.get_width() * small.get_height())
