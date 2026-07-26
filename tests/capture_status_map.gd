extends SceneTree
# Renders the status map and MEASURES it. Two things no headless test can see:
#
#   1. WHERE THE COLOUR LANDS. `smoke_status_map` asserts blob coordinates, but nothing there
#      proves the drawing puts ink at those coordinates — a blob computed onto ENGINE and
#      painted onto CARGO would pass the whole suite. So every saturated pixel on the page is
#      checked against the blob it should belong to.
#   2. THAT IT PULSES ON SCREEN. Rendered at two phases: the pixels inside the blobs have to
#      change, and the pixels everywhere else have to not.
#
# The classifier is one comparison, and it works because of the design rule the page is built
# on: colour is reserved for trouble. The diagram is green ink (r < g) on dark paper (r < g), so
# ANY pixel with r > g is a blob. Red and orange separate on green — 0.16 against 0.62.
#
# Needs a real renderer, so NOT --headless:
#   godot --path . -s tests/capture_status_map.gd -- <out_dir>

const SHIP_LAYOUT := preload("res://scripts/level/ship_layout.gd")
const PAGE := Vector2i(1024, 640)

## A pixel is "trouble" when red beats green by this much. Slack for the glow's alpha blend
## against the paper, which drags both channels toward the background.
const HOT := 0.10
## Green above this is orange, below it is red.
const ORANGE_G := 0.35
## How far from a blob's centre its ink is allowed to reach, as a multiple of the base radius.
## Three factors stack: the outer glow is drawn at 1.95x, the breath adds up to 1.15x, and the
## wobble that makes it a blob rather than a circle adds up to 1.16x on top of both. 1.95 x 1.15
## x 1.16 = 2.60, and the last of it is a pixel of slack.
const REACH := 2.75

var _failures: Array[String] = []
var _dir: String = "user://"
var _viewport: SubViewport
var _map: StatusMap


func _init() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("status map capture timed out")
		quit(1))
	_go.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_dir = args[0]

	var world := Node3D.new()
	root.add_child(world)
	current_scene = world

	var ship := SHIP_LAYOUT.new()
	ship.build_doors = false
	ship.build_lights = false
	world.add_child(ship)
	await process_frame

	# The console's own screen, at the console's own resolution — see scenes/props/computer.tscn.
	_viewport = SubViewport.new()
	_viewport.size = PAGE
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world.add_child(_viewport)

	_map = StatusMap.new()
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(_map)
	_map.set_plan(ShipPlan.from_builder(ship))
	# Where the console is bolted, and so where the player is standing whenever they can read
	# this. See scenes/game.tscn: the Computer sits at (9.75, 0, 5.5), inside the cryo bay.
	_map.set_player_room("cryo_bay")
	await _frames(3)

	# 1. A clean ship. Nothing but the diagram — and it must contain NO trouble colour at all,
	# which is the strongest possible statement of "colour is reserved for trouble".
	_map.set_problems([])
	_map.set_pulse(0.0)
	await _frames(2)
	var clean := await _shot("01_clean")
	var clean_hot := _hot_pixels(clean)
	_check("a clean ship has no saturated pixels anywhere (%d)" % clean_hot.size(),
		clean_hot.is_empty())

	# 2. The ship in trouble, in every state the page can draw: a fault, a warning, and a room
	# carrying three problems at once.
	var problems := [
		{"room": "bridge", "kind": StatusMap.Kind.FAULT, "urgency": 0.9, "label": "NAV ARRAY"},
		{"room": "life_support", "kind": StatusMap.Kind.WARNING, "urgency": 0.6, "label": "CO2"},
		{"room": "cargo_bay", "kind": StatusMap.Kind.WARNING, "urgency": 0.5, "label": "VENDING"},
		{"room": "engine_room", "kind": StatusMap.Kind.FAULT, "urgency": 0.3, "label": "MAIN DRIVE"},
		{"room": "engine_room", "kind": StatusMap.Kind.FAULT, "urgency": 0.5, "label": "COOLANT"},
		{"room": "engine_room", "kind": StatusMap.Kind.WARNING, "urgency": 0.8, "label": "DRIVE FUEL"},
	]
	_map.set_problems(problems)
	_map.set_pulse(0.0)
	await _frames(2)
	var phase_a := await _shot("02_trouble")
	var blobs := _map.blob_layout()
	_check("six problems drew six blobs (%d)" % blobs.size(), blobs.size() == 6)

	_measure_placement(phase_a, blobs)

	# 3. A quarter cycle on for the fastest blob, so every one of them has moved.
	_map.set_pulse(0.25 / StatusMap.PULSE_MAX_HZ)
	await _frames(2)
	var phase_b := await _shot("03_trouble_pulsed")
	_measure_pulse(phase_a, phase_b, blobs)

	if _failures.is_empty():
		print("STATUS MAP CAPTURE PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("STATUS MAP CAPTURE FAIL")
		quit(1)


func _shot(shot_name: String) -> Image:
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	var path := "%s/%s.png" % [_dir, shot_name]
	if image.save_png(path) != OK:
		push_error("save_png failed for %s" % path)
	else:
		print("saved %s" % path)
	return image


## Every pixel where red beats green — which, on this page, means every pixel of every blob.
func _hot_pixels(image: Image) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.r - c.g > HOT:
				out.append(Vector2i(x, y))
	return out


# --- placement ---------------------------------------------------------------

## The check the smoke suite structurally cannot make: that the ink went where the layout said.
func _measure_placement(image: Image, blobs: Array[Dictionary]) -> void:
	var hot := _hot_pixels(image)
	_check("the ship in trouble has saturated pixels at all (%d)" % hot.size(), hot.size() > 500)

	# a) No stray ink. Every trouble pixel belongs to a blob — so a blob painted on the wrong
	# room, or a legend swatch that has drifted into the diagram, fails here.
	var orphans := 0
	var worst := Vector2i.ZERO
	for pixel in hot:
		# -2 is the legend band, which is trouble-coloured on purpose. Only -1 is a stray.
		if _owner_of(pixel, blobs) == -1:
			orphans += 1
			worst = pixel
	# The legend swatches at the bottom of the page are trouble-coloured on purpose, so they are
	# excluded by band rather than by position — anything above the legend line must belong.
	_check("no saturated pixel outside a blob (%d strays, e.g. %v)" % [orphans, worst],
		orphans == 0)

	# b) Every blob actually got drawn, near enough to its own node.
	for i in blobs.size():
		var blob: Dictionary = blobs[i]
		var count := 0
		for pixel in hot:
			if _owner_of(pixel, blobs) == i:
				count += 1
		_check("%s / %s drew ink (%d pixels)" % [blob["room"], blob["label"], count],
			count >= 200)

		# c) ...and in the right colour, which is the half of the code the player reads without
		# reading. An orange blob on a fault would send them for a canister instead of a hammer.
		#
		# Measured on the CORE, not the whole reach: several problems in one room fan out close
		# enough that their glows legitimately overlap and tint each other, so a halo says
		# nothing about whose blob it is. The solid middle does.
		var oranges := 0
		var reds := 0
		var at: Vector2 = blob["at"]
		for pixel in hot:
			if at.distance_to(Vector2(pixel)) > float(blob["base_radius"]):
				continue
			if image.get_pixel(pixel.x, pixel.y).g > ORANGE_G:
				oranges += 1
			else:
				reds += 1
		var warning := int(blob["kind"]) == StatusMap.Kind.WARNING
		_check("%s / %s is %s (%d orange, %d red)" % [
			blob["room"], blob["label"], "orange" if warning else "red", oranges, reds],
			oranges > reds if warning else reds > oranges)


## Index of the blob a pixel belongs to, or a negative code for the parts of the page that are
## deliberately not blobs:
##
##   -1  ordinary diagram. Must be static, and must carry no trouble colour.
##   -2  the legend band, whose swatches are trouble-coloured by design.
##   -3  the player's own dot, which is white and pulses — so it is neither a stray colour nor
##       a stationary part of the drawing, and both checks have to know about it.
func _owner_of(pixel: Vector2i, blobs: Array[Dictionary]) -> int:
	if float(pixel.y) > _map.size.y * 0.88:
		return -2
	var here := _map.here_layout()
	if not here.is_empty():
		var to_dot := (here["node"] as Vector2).distance_to(Vector2(pixel))
		if to_dot <= float(here["base_radius"]) * 2.8:
			return -3
	var best := -1
	var best_distance := INF
	for i in blobs.size():
		var blob: Dictionary = blobs[i]
		var at: Vector2 = blob["at"]
		var d := at.distance_to(Vector2(pixel))
		if d <= float(blob["base_radius"]) * REACH and d < best_distance:
			best_distance = d
			best = i
	return best


# --- the pulse ---------------------------------------------------------------

## Rendered proof that the thing breathes, and that nothing else does. The second half matters
## as much as the first: a page that redrew the whole diagram every frame would be a CRT full of
## crawling ink, and the wobble hash exists precisely to stop that.
func _measure_pulse(a: Image, b: Image, blobs: Array[Dictionary]) -> void:
	var inside_changed := 0
	var inside_total := 0
	var outside_changed := 0
	var dot_changed := 0
	for y in a.get_height():
		for x in a.get_width():
			var pixel := Vector2i(x, y)
			var owner := _owner_of(pixel, blobs)
			var changed := _differs(a.get_pixel(x, y), b.get_pixel(x, y))
			if owner >= 0:
				inside_total += 1
				if changed:
					inside_changed += 1
			elif owner == -1 and changed:
				outside_changed += 1
			elif owner == -3 and changed:
				dot_changed += 1

	# The player's dot has its own slow pulse and has to be seen to move too — it is the one
	# mark on the page that is there whether or not anything is wrong.
	_check("the player's dot pulses as well (%d pixels)" % dot_changed, dot_changed > 20)
	_report_pulse(inside_changed, inside_total, outside_changed)


## Two colours far enough apart to be a real change rather than 8-bit rounding.
static func _differs(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.02


func _report_pulse(inside_changed: int, inside_total: int, outside_changed: int) -> void:
	var fraction := 0.0 if inside_total == 0 else float(inside_changed) / float(inside_total)
	_check("the blobs change between phases (%.1f%% of %d pixels)" % [
		fraction * 100.0, inside_total], fraction > 0.15)
	# Not "few": NONE. The diagram is hashed-deterministic, so a single changed pixel outside a
	# blob means something is crawling that should be standing still.
	_check("and nothing else on the page does (%d pixels)" % outside_changed,
		outside_changed == 0)
