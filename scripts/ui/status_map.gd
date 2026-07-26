class_name StatusMap
extends Control

# The ship's damage control plan: a tube diagram of the ship with pulsating blobs in the rooms
# where something needs doing. The second page of the nav console — see ComputerTerminal.
#
# The HUD fault list already says WHAT is wrong. It has never said WHERE, and that is the
# question the player actually has to answer on waking, because every fault is priced in
# walking distance and walking distance is priced in air.
#
# EVERYTHING IS `_draw()`, like NavChart, and the two pages are meant to look like one hand
# drew them — same ink, same paper, same sin-fract wobble hash.
#
# COLOUR IS RESERVED FOR TROUBLE. The diagram itself is green ink on dark paper, so the blobs
# are the only saturated pixels on the page and nothing competes with them. Two colours, and
# they are the game's only two responses to a problem:
#
#   RED     an active fault      -> REPAIR it. The hammer, or a spare part.
#   ORANGE  a supply or a need   -> FETCH something. A canister, a cell, a crate.
#
# PATCHED FAULTS ARE NOT ON THIS MAP. A patch is not somewhere you have to go — it is a bill
# that falls due later, and the HUD fault list already carries it with the number that matters
# (how much drive it locked in). Drawing it here would put a third symbol on a page whose whole
# argument is that a blob means "walk here now".
#
# Those are the values the silo lamps already use in the world (Silo.LAMP_CRIT / LAMP_WARN),
# deliberately: the map and the room have to agree, and the player has already been taught the
# code by walking past a tank. `smoke_status_map` asserts the equality rather than importing
# it, so a UI script does not end up depending on a game script for a colour.
#
# PULSE RATE CARRIES URGENCY, BLOB SIZE DOES NOT. The base radius is constant across every
# blob, so the map cannot lie about magnitude — the NUMBER of blobs in a room is the magnitude.
# Rate-as-signal is the grammar the HUD already uses for the air vignette.
#
# This class knows nothing about RunState. It is handed a plan and a list of dictionaries, and
# `blob_layout()` is the same list `_draw()` draws — so the headless test can assert where every
# blob lands without a renderer, and the drawing cannot disagree with the thing under test.

enum Kind {
	## An active Malfunction — something to repair. Filled red.
	FAULT,
	## A silo low or empty, or a need pressing — something to fetch. Filled orange.
	WARNING,
}

const INK := Color(0.30, 0.85, 0.45)
const INK_MID := Color(0.30, 0.85, 0.45, 0.70)
const INK_FAINT := Color(0.30, 0.85, 0.45, 0.45)
const PAPER := Color(0.05, 0.09, 0.06)

## Same values as Silo.LAMP_CRIT / Silo.LAMP_WARN. See the note above.
const FAULT_COLOR := Color(1.00, 0.16, 0.12)
const WARN_COLOR := Color(1.00, 0.62, 0.10)

## Stroke weight per line, in schematic units.
##
## NOT one hue per line, and not one dash pattern per line either. A tube map colours its lines
## so you can follow one ACROSS A CROSSING; this graph is a tree with no crossings at all, so
## the colour would be decoration — and colour is spent on trouble. What is worth showing is how
## much of the ship hangs off each run, so the trunk is heaviest, the two arms are equal (they
## are mirror images and distinguishing them would be arbitrary), and the stubs are hairlines.
const WEIGHTS := {
	"SPINE": 0.085,
	"PORT": 0.060,
	"STARBOARD": 0.060,
	"": 0.032,
}

## Glyph and blob geometry, all in schematic units so the page is resolution-independent.
##
## The station rings are deliberately CHUNKY. This screen is read from a couple of metres on the
## way past, not studied, and a tube map's interchange circles are the thing the eye lands on
## first — a hairline ring reads as a dot and the diagram stops looking like a diagram.
const NODE_RADIUS := 0.145
const BLOB_RADIUS := 0.190
## How far from a node's centre blobs sit when there is more than one of them. Wide enough that
## three blobs on one room read as three, rather than as one smear with lumps.
const FAN_RADIUS := 0.380
## Empty space kept around the diagram for labels, in schematic units.
const MARGIN := Vector2(0.62, 0.46)

## How far from the player's node the YOU ARE HERE caption sits, in schematic units.
const HERE_GAP := 0.66
const HERE_TEXT := "YOU ARE HERE"
## The player, marked as a small pulsating white dot with the arrow pointing at it.
##
## WHITE, and that does not break "colour is reserved for trouble": white is not a hue, it is
## the absence of one, and it is the one mark on the page that is about the player rather than
## about the ship. Red says repair, orange says fetch, white says you.
##
## SMALLER than a blob — deliberately about half — because it is not a problem and must never
## be mistaken for one at a glance across a room.
const HERE_COLOR := Color(0.93, 0.96, 1.00)
const HERE_RADIUS := 0.075
## Fixed, unlike a blob's. A blob's rate carries how bad it is; the player's location has no
## urgency to carry, so its rate says nothing except that the screen is live. Slower than the
## calmest blob (PULSE_MIN_HZ), so it can never look like the most pressing thing on the page.
const HERE_HZ := 0.35
const HERE_PULSE_DEPTH := 0.22

const PULSE_MIN_HZ := 0.5
const PULSE_MAX_HZ := 2.2

## How far a blob breathes, as a fraction of its base radius.
const PULSE_DEPTH := 0.15

@export var title: String = "DAMAGE CONTROL — DECK PLAN"

var _plan: ShipPlan = null
## {"room": String, "kind": Kind, "urgency": 0..1, "label": String}
var _problems: Array[Dictionary] = []
## Room the player is standing in, or "" for none — which is a real state, not an error: a
## player in a doorway is between two rooms and `RoomBuilder.room_at()` says so.
var _here: String = ""
var _pulse: float = 0.0
var _font: Font

# Page transform, recomputed whenever the control resizes. Held rather than passed around
# because blob_layout() needs exactly the same numbers _draw() uses.
var _scale: float = 1.0
var _offset: Vector2 = Vector2.ZERO
var _plot_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	_font = ThemeDB.fallback_font
	var theme_font := get_theme_default_font()
	if theme_font != null:
		_font = theme_font
	resized.connect(_recompute_transform)
	_recompute_transform()
	_refresh_processing()


func set_plan(plan: ShipPlan) -> void:
	_plan = plan
	queue_redraw()


## Replace the problem list. Sorted before it is stored, so a re-collection that happens to
## return the same problems in a different order does not make the blobs swap places.
func set_problems(problems: Array) -> void:
	_problems = []
	for problem in problems:
		_problems.append(problem as Dictionary)
	_problems.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.get("room", "") != b.get("room", ""):
			return a.get("room", "") < b.get("room", "")
		if int(a.get("kind", 0)) != int(b.get("kind", 0)):
			return int(a.get("kind", 0)) < int(b.get("kind", 0))
		return String(a.get("label", "")) < String(b.get("label", "")))
	_refresh_processing()
	queue_redraw()


## Where the player is. "" hides the marker.
func set_player_room(room_id: String) -> void:
	if _here == room_id:
		return
	_here = room_id
	_refresh_processing()
	queue_redraw()


func player_room() -> String:
	return _here


func problem_count() -> int:
	return _problems.size()


# A static drawing does not need a frame loop. Only something that PULSES does — a blob, or the
# player's own dot — so the page redraws per frame while either is on it and not at all when
# there is nothing moving. Same reasoning that put NavChart on a 0.25s timer instead of _process.
func _refresh_processing() -> void:
	var alive := not _problems.is_empty() or _here != ""
	set_process(alive and is_visible_in_tree())


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_refresh_processing()


func _process(delta: float) -> void:
	_pulse += delta
	queue_redraw()


## The pulse clock, exposed so a test can drive it to an exact phase rather than waiting.
func set_pulse(seconds: float) -> void:
	_pulse = seconds
	queue_redraw()


# --- layout -----------------------------------------------------------------

## Fit the schematic into the page. UNIFORM scale, so the diagram is never stretched: a tube map
## that has been squashed to fill a widescreen is no longer octilinear, and the 45° stubs stop
## being 45°.
func _recompute_transform() -> void:
	var plot := _plot_rect()
	var lo := Vector2.INF
	var hi := -Vector2.INF
	for id in ShipPlan.NODES:
		var at: Vector2 = ShipPlan.NODES[id]["at"]
		lo = lo.min(at)
		hi = hi.max(at)
	lo -= MARGIN
	hi += MARGIN
	_plot_size = hi - lo
	if _plot_size.x <= 0.0 or _plot_size.y <= 0.0:
		return
	_scale = minf(plot.size.x / _plot_size.x, plot.size.y / _plot_size.y)
	# Centre what is left over, so the diagram sits in the middle of the page whichever axis
	# ended up binding.
	_offset = plot.position + (plot.size - _plot_size * _scale) * 0.5 - lo * _scale


## The band of the page the diagram gets: below the title, above the legend.
func _plot_rect() -> Rect2:
	return Rect2(size.x * 0.05, size.y * 0.17, size.x * 0.90, size.y * 0.68)


func _px(at: Vector2) -> Vector2:
	return _offset + at * _scale


## Every blob the page will draw, resolved to pixels. `_draw()` consumes exactly this, so a test
## that asserts against it is asserting against the drawing rather than beside it.
func blob_layout() -> Array[Dictionary]:
	_recompute_transform()
	var out: Array[Dictionary] = []
	# Group first: a blob's position depends on how many others share its room.
	var by_room := {}
	for problem in _problems:
		var room: String = problem.get("room", "")
		if not ShipPlan.has_node(room):
			# A problem in a room that is not on the map — a doorway gap, or a prop outside the
			# hull. Dropping it silently would be a lie of omission, so it is a warning.
			push_warning("StatusMap: no node for room '%s'" % room)
			continue
		if not by_room.has(room):
			by_room[room] = []
		by_room[room].append(problem)

	for room in by_room:
		var group: Array = by_room[room]
		var centre := _px(ShipPlan.node_at(room))
		for i in group.size():
			var problem: Dictionary = group[i]
			var at := centre
			# ONE problem sits ON the room, which is the strongest possible "here". Several fan
			# out around it, because then the count is the information — three blobs on ENGINE
			# means three walks, and it should look as bad as it is.
			if group.size() > 1:
				var angle := TAU * float(i) / float(group.size()) - PI * 0.5
				at = centre + Vector2(cos(angle), sin(angle)) * FAN_RADIUS * _scale
			var kind: int = int(problem.get("kind", Kind.FAULT))
			var hz := _hz(kind, float(problem.get("urgency", 0.0)))
			# The breath is resolved HERE rather than in _draw_blob, so the pulse is something a
			# headless test can measure. Everything the page draws is in this list.
			var breath := 0.5 + 0.5 * sin(TAU * hz * _pulse)
			var base: float = BLOB_RADIUS * _scale
			out.append({
				"room": room,
				"kind": kind,
				"label": String(problem.get("label", "")),
				"at": at,
				"base_radius": base,
				"radius": base * (1.0 - PULSE_DEPTH + 2.0 * PULSE_DEPTH * breath),
				"breath": breath,
				"hz": hz,
				"color": WARN_COLOR if kind == Kind.WARNING else FAULT_COLOR,
			})
	return out


## The YOU ARE HERE arrow, resolved to pixels, or an empty dictionary when there is nobody to
## point at. Same contract as blob_layout(): this IS what gets drawn, so a test can assert the
## arrow lands on the right room without a renderer.
##
## The arrow points INWARD, from a caption outside the diagram to the node itself, which is what
## a mall map does and what makes it read as an annotation rather than as another symbol on the
## line. Its direction is away from the middle of the diagram, because every room on this ship is
## on the perimeter of it — so "outward" is reliably the empty part of the page.
func here_layout() -> Dictionary:
	_recompute_transform()
	if _here == "" or not ShipPlan.has_node(_here):
		return {}
	var node := _px(ShipPlan.node_at(_here))
	var dir := (ShipPlan.node_at(_here) - _schematic_centre())
	if dir.length() < 0.001:
		dir = Vector2(0.0, 1.0)
	dir = dir.normalized()
	# Straight up or straight down puts the caption on top of the node's own label, which sits
	# there. Nudged onto a diagonal, which is also where the page is emptiest.
	if absf(dir.x) < 0.35:
		dir = Vector2(0.7071, signf(dir.y) if absf(dir.y) > 0.001 else 1.0).normalized()

	var font_size := int(maxf(size.y * 0.038, 8.0))
	var extent := _font.get_string_size(HERE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var tail := node + dir * HERE_GAP * _scale
	var tip := node + dir * NODE_RADIUS * 1.75 * _scale

	# Caption beyond the tail, reading horizontally whichever way the arrow points.
	var caption := tail + Vector2(
		font_size * 0.4 if dir.x >= 0.0 else -font_size * 0.4 - extent.x,
		font_size * 0.35)
	# Clamped into the page, so a room near an edge cannot push the caption off it. The arrow
	# still points at the node either way — it is the caption that moves.
	var edge := size.x * 0.04
	caption.x = clampf(caption.x, edge, maxf(size.x - edge - extent.x, edge))
	caption.y = clampf(caption.y, _plot_rect().position.y + font_size, size.y * 0.90)

	var breath := 0.5 + 0.5 * sin(TAU * HERE_HZ * _pulse)
	return {
		"room": _here,
		"node": node,
		"tail": tail,
		"tip": tip,
		"caption": caption,
		"font_size": font_size,
		"base_radius": HERE_RADIUS * _scale,
		"radius": HERE_RADIUS * _scale
			* (1.0 - HERE_PULSE_DEPTH + 2.0 * HERE_PULSE_DEPTH * breath),
		"breath": breath,
	}


func _schematic_centre() -> Vector2:
	var lo := Vector2.INF
	var hi := -Vector2.INF
	for id in ShipPlan.NODES:
		var at: Vector2 = ShipPlan.NODES[id]["at"]
		lo = lo.min(at)
		hi = hi.max(at)
	return (lo + hi) * 0.5


## Urgency to pulse rate. The rate IS the signal — a blob that is about to kill you races, one
## you noticed early breathes.
static func _hz(_kind: int, urgency: float) -> float:
	return lerpf(PULSE_MIN_HZ, PULSE_MAX_HZ, clampf(urgency, 0.0, 1.0))


# --- drawing ----------------------------------------------------------------

func _draw() -> void:
	if _font == null:
		_font = ThemeDB.fallback_font
	_recompute_transform()
	draw_rect(Rect2(Vector2.ZERO, size), PAPER, true)

	var title_size := int(size.y * 0.075)
	draw_string(_font, Vector2(size.x * 0.06, size.y * 0.11), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, INK)
	_shaky_line(Vector2(size.x * 0.06, size.y * 0.145), Vector2(size.x * 0.94, size.y * 0.145),
		INK_FAINT, 2.0, 3.1)

	if _plan != null:
		for edge in _plan.edges:
			_draw_edge(edge)
	for id in ShipPlan.NODES:
		_draw_node(id)
	for blob in blob_layout():
		_draw_blob(blob)
	# LAST, and over the top of the blobs. A room in enough trouble to be worth walking to is
	# exactly the room whose name gets buried under three blobs — which is the one case where
	# the label has to survive. Haloed in paper so it stays legible on red.
	for id in ShipPlan.NODES:
		_draw_label(id)
	_draw_here()
	_draw_legend()


func _draw_edge(edge: Dictionary) -> void:
	var a := _px(ShipPlan.node_at(edge["a"]))
	var b := _px(ShipPlan.node_at(edge["b"]))
	var width: float = float(WEIGHTS.get(edge.get("line", ""), WEIGHTS[""])) * _scale
	var color: Color = INK if edge.get("line", "") != "" else INK_MID
	draw_line(a, b, color, width, true)
	# Segments meet AT a node, so a bend leaves a notch where two rectangles cross at 90° or
	# 45°. A dot of the same weight fills it. Cheaper than mitring, and invisible when it is
	# not needed.
	draw_circle(a, width * 0.5, color)
	draw_circle(b, width * 0.5, color)


func _draw_node(id: String) -> void:
	var spec: Dictionary = ShipPlan.NODES[id]
	var at := _px(spec["at"])
	var r := NODE_RADIUS * _scale
	match int(spec["glyph"]):
		ShipPlan.Glyph.TICK:
			draw_circle(at, r * 0.55, INK_MID)
		ShipPlan.Glyph.STATION:
			# Tube-style: a hole in the line with a ring round it, not a dot on top of it.
			draw_circle(at, r, PAPER)
			draw_arc(at, r, 0.0, TAU, 28, INK, r * 0.34, true)
		_:
			# Junction and terminus both get the double ring — the two rooms every route runs
			# between, and the two the player is always orienting from.
			draw_circle(at, r * 1.4, PAPER)
			draw_arc(at, r * 1.4, 0.0, TAU, 32, INK, r * 0.32, true)
			draw_arc(at, r * 0.75, 0.0, TAU, 24, INK, r * 0.28, true)


func _draw_label(id: String) -> void:
	var spec: Dictionary = ShipPlan.NODES[id]
	var text := String(spec["label"])
	if text == "":
		return
	var at := _px(spec["at"])
	var r := NODE_RADIUS * _scale
	var dir := String(spec["label_dir"])
	var font_size := int(maxf(size.y * 0.040, 8.0))
	var extent := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var gap := r * 1.9
	var pos := at
	match dir:
		"left":
			pos = at + Vector2(-gap - extent.x, font_size * 0.35)
		"right":
			pos = at + Vector2(gap, font_size * 0.35)
		"above":
			pos = at + Vector2(-extent.x * 0.5, -gap - font_size * 0.25)
		_:
			pos = at + Vector2(-extent.x * 0.5, gap + font_size * 0.85)
	draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		int(maxf(font_size * 0.30, 3.0)), PAPER)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK)


## A blob, not a circle: a wobbled polygon with two fainter copies stacked behind it for glow.
## There is no shader on a Control here, so the glow is just three polygons — which suits a page
## that is meant to look drawn rather than rendered.
func _draw_blob(blob: Dictionary) -> void:
	var breath: float = blob["breath"]
	var radius: float = blob["radius"]
	var color: Color = blob["color"]
	var at: Vector2 = blob["at"]
	# Seeded from where it sits, so a blob keeps the same silhouette for as long as it is there.
	var seed_value := at.x * 0.031 + at.y * 0.017

	draw_colored_polygon(_blob_points(at, radius * 1.95, seed_value + 5.0),
		Color(color, 0.10 + 0.10 * breath))
	draw_colored_polygon(_blob_points(at, radius * 1.45, seed_value + 11.0),
		Color(color, 0.18 + 0.14 * breath))
	draw_colored_polygon(_blob_points(at, radius, seed_value),
		Color(color, 0.75 + 0.25 * breath))


func _blob_points(centre: Vector2, radius: float, seed_value: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps := 22
	for i in steps:
		var a := TAU * float(i) / float(steps)
		# Hashed from the ANGLE, so the blob keeps its shape frame to frame and only breathes.
		# A per-frame random radius would boil.
		var r := radius * (1.0 + 0.16 * _hash_signed(seed_value + a * 3.0))
		points.append(centre + Vector2(cos(a), sin(a)) * r)
	return points


## Green, not a trouble colour: where you are is not a problem. It is the only annotation on the
## page that is about the player rather than about the ship.
func _draw_here() -> void:
	var here := here_layout()
	if here.is_empty():
		return
	var tail: Vector2 = here["tail"]
	var tip: Vector2 = here["tip"]
	var font_size: int = here["font_size"]
	var weight := maxf(_scale * 0.022, 2.0)

	# The dot itself, on the node, with a soft halo so it reads as a light rather than a sticker.
	var node: Vector2 = here["node"]
	var radius: float = here["radius"]
	var breath: float = here["breath"]
	draw_circle(node, radius * 2.1, Color(HERE_COLOR, 0.10 + 0.10 * breath))
	draw_circle(node, radius * 1.5, Color(HERE_COLOR, 0.20 + 0.15 * breath))
	draw_circle(node, radius, Color(HERE_COLOR, 0.80 + 0.20 * breath))

	draw_line(tail, tip, INK, weight, true)
	# Arrowhead at the node end.
	var along := (tip - tail).normalized()
	var across := Vector2(-along.y, along.x)
	var head := _scale * 0.10
	draw_colored_polygon(PackedVector2Array([
		tip,
		tip - along * head * 1.6 + across * head * 0.7,
		tip - along * head * 1.6 - across * head * 0.7,
	]), INK)

	var caption: Vector2 = here["caption"]
	draw_string_outline(_font, caption, HERE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		int(maxf(font_size * 0.30, 3.0)), PAPER)
	draw_string(_font, caption, HERE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK)


func _draw_legend() -> void:
	var font_size := int(maxf(size.y * 0.038, 8.0))
	var y := size.y * 0.94
	var x := size.x * 0.06
	var r := size.y * 0.016

	# THE KEY ONLY EVER EXPLAINS MARKS THAT ARE ACTUALLY ON THE PAGE. A key to symbols that are
	# not there is noise, and it would also make "colour is reserved for trouble" merely a figure
	# of speech — a clean ship would still have red on it. So a clean ship says so instead, and
	# each entry below appears with the mark it describes.
	var entries := []
	if _problems.is_empty():
		draw_string(_font, Vector2(x, y), "ALL SYSTEMS NOMINAL",
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK_MID)
		x += _font.get_string_size("ALL SYSTEMS NOMINAL",
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + size.x * 0.035
	else:
		# Two entries, because there are two things a blob can ask of you. The verb is half the
		# legend: the colour says which, and the word says what to bring.
		entries.append({"color": FAULT_COLOR, "text": "FAULT · REPAIR"})
		entries.append({"color": WARN_COLOR, "text": "WARNING · FETCH"})
	if not here_layout().is_empty():
		# Keyed by the DOT, at the size it really is relative to a blob, because the dot is what
		# identifies the player — the arrow is only there to find it.
		entries.append({"color": HERE_COLOR, "scale": HERE_RADIUS / BLOB_RADIUS,
			"text": HERE_TEXT})

	for entry in entries:
		var at := Vector2(x + r, y - font_size * 0.3)
		draw_circle(at, r * float(entry.get("scale", 1.0)), entry["color"])
		var text: String = entry["text"]
		draw_string(_font, Vector2(x + r * 2.6, y), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK_MID)
		x += r * 2.6 + _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		x += size.x * 0.035


# --- the wobble -------------------------------------------------------------

## The same sin-fract hash NavChart draws its shaky lines with, so the two pages of the console
## look like one hand drew them. Deterministic: same input, same squiggle, every frame.
static func _hash_signed(seed_value: float) -> float:
	var a := sin(seed_value * 12.9898) * 43758.5453
	return (a - floorf(a) - 0.5) * 2.0


func _shaky_line(from: Vector2, to: Vector2, color: Color, width: float, seed_value: float) -> void:
	var points := PackedVector2Array()
	var steps := maxi(3, int(from.distance_to(to) / 26.0))
	for i in steps + 1:
		var t := float(i) / float(steps)
		var wobble := Vector2(
			_hash_signed(seed_value + t * 7.0),
			_hash_signed(seed_value + t * 7.0 + 31.0)
		) * 2.2
		points.append(from.lerp(to, t) + wobble)
	draw_polyline(points, color, width)
