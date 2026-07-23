class_name NavChart
extends Control

# The ship's navigation display, drawn as if someone sketched it on the back of a manifest.
#
# Everything here is `_draw()` calls rather than art assets, and every stroke is jittered
# off its true position. A crisp vector diagram would look like a satnav; this is meant to
# look like the least reassuring thing on the ship — an engineer's biro drawing of where
# you are, which fits a game about a crew improvising its way to a destination.
#
# The wobble is HASHED FROM POSITION, not random: a random offset per frame would make the
# whole chart crawl and shimmer. Same input, same squiggle, every frame.

## Deterministic wobble, so the drawing holds still between frames.
const WOBBLE := 2.6
const INK := Color(0.30, 0.85, 0.45)
const INK_FAINT := Color(0.30, 0.85, 0.45, 0.45)
const PAPER := Color(0.05, 0.09, 0.06)

@export var origin_name: String = "TERRA STATION"
@export var destination_name: String = "KEPLER YARD"

var _progress: float = 0.0
var _days_left: float = 0.0
var _distance_left: float = 0.0
var _drive: float = 1.0
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	var theme_font := get_theme_default_font()
	if theme_font != null:
		_font = theme_font


## `progress` is 0 at departure, 1 on arrival.
func set_voyage(progress: float, days_left: float, distance_left: float, drive: float) -> void:
	_progress = clampf(progress, 0.0, 1.0)
	_days_left = days_left
	_distance_left = distance_left
	_drive = drive
	queue_redraw()


# Hash a point to a repeatable offset. sin-fract is the classic cheap hash and is plenty
# for something that only has to look untidy.
func _wobble(seed_value: float, amount: float = WOBBLE) -> Vector2:
	var a := sin(seed_value * 12.9898) * 43758.5453
	var b := sin(seed_value * 78.233) * 12345.6789
	return Vector2(a - floorf(a) - 0.5, b - floorf(b) - 0.5) * 2.0 * amount


func _shaky_line(from: Vector2, to: Vector2, color: Color, width: float, seed_value: float) -> void:
	# Drawn as several short segments so the line bends along its length instead of just
	# being a straight line with displaced ends.
	var points := PackedVector2Array()
	var steps := maxi(3, int(from.distance_to(to) / 26.0))
	for i in steps + 1:
		var t := float(i) / float(steps)
		points.append(from.lerp(to, t) + _wobble(seed_value + t * 7.0))
	draw_polyline(points, color, width)


func _shaky_circle(centre: Vector2, radius: float, color: Color, width: float, seed_value: float) -> void:
	var points := PackedVector2Array()
	var steps := 30
	for i in steps + 1:
		var a := TAU * float(i) / float(steps)
		var r := radius + _wobble(seed_value + a).x
		points.append(centre + Vector2(cos(a), sin(a)) * r)
	draw_polyline(points, color, width)


## The flight path: a shallow arc, because a straight line between two planets would look
## like a ruler and this drawing is not meant to have had one.
func _path_point(t: float) -> Vector2:
	var w := size.x
	var h := size.y
	var from := Vector2(w * 0.16, h * 0.66)
	var to := Vector2(w * 0.84, h * 0.40)
	var mid := from.lerp(to, 0.5) + Vector2(0.0, -h * 0.22)
	# Quadratic Bezier.
	var a := from.lerp(mid, t)
	var b := mid.lerp(to, t)
	return a.lerp(b, t)


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), PAPER, true)

	var title_size := int(h * 0.075)
	var body_size := int(h * 0.055)
	var small_size := int(h * 0.045)

	draw_string(_font, Vector2(w * 0.06, h * 0.12), "NAV PLOT — DEAD RECKONING",
		HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, INK)
	_shaky_line(Vector2(w * 0.06, h * 0.155), Vector2(w * 0.94, h * 0.155), INK_FAINT, 2.0, 3.1)

	# Dotted course line: dashes drawn one at a time along the arc.
	var dashes := 46
	for i in dashes:
		var t0 := float(i) / float(dashes)
		var t1 := t0 + 0.5 / float(dashes)
		_shaky_line(_path_point(t0), _path_point(t1), INK_FAINT, 2.0, 11.0 + float(i))

	# The two worlds.
	var start := _path_point(0.0)
	var end := _path_point(1.0)
	_shaky_circle(start, h * 0.075, INK, 3.0, 1.7)
	_shaky_circle(start, h * 0.075 * 0.55, INK_FAINT, 2.0, 5.3)
	_shaky_circle(end, h * 0.105, INK, 3.0, 2.9)
	# A ring, so the destination reads as somewhere worth arriving at.
	_shaky_circle(end, h * 0.15, INK_FAINT, 2.0, 8.8)

	# Above the circle, not below: the readout block occupies the lower left.
	draw_string(_font, start + Vector2(-h * 0.10, -h * 0.14), origin_name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, small_size, INK_FAINT)
	draw_string(_font, end + Vector2(-h * 0.14, -h * 0.20), destination_name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, small_size, INK)

	_draw_ship()
	_draw_readout(body_size, small_size)


## The ship: a little sketched arrowhead, stuck on the arc at the current progress and
## turned to follow it, the way you would draw it if you were marking your position.
func _draw_ship() -> void:
	var at := _path_point(_progress)
	# Tangent by sampling slightly ahead (or behind, at the very end).
	var ahead := _path_point(minf(_progress + 0.01, 1.0))
	var behind := _path_point(maxf(_progress - 0.01, 0.0))
	var heading := (ahead - behind)
	if heading.length() < 0.001:
		heading = Vector2.RIGHT
	heading = heading.normalized()
	var side := Vector2(-heading.y, heading.x)
	var scale := size.y * 0.055

	var nose := at + heading * scale * 1.5
	var tail_l := at - heading * scale * 0.8 + side * scale * 0.75
	var tail_r := at - heading * scale * 0.8 - side * scale * 0.75
	var notch := at - heading * scale * 0.25

	_shaky_line(nose, tail_l, INK, 3.0, 21.0)
	_shaky_line(tail_l, notch, INK, 3.0, 22.0)
	_shaky_line(notch, tail_r, INK, 3.0, 23.0)
	_shaky_line(tail_r, nose, INK, 3.0, 24.0)
	# Exhaust scratches, shorter when the drive is limping — a second, wordless readout.
	var plume: float = scale * (0.5 + 1.4 * _drive)
	for i in 3:
		var offset := side * scale * (float(i) - 1.0) * 0.4
		_shaky_line(notch + offset, notch - heading * plume + offset, INK_FAINT, 2.0, 31.0 + float(i))


func _draw_readout(body_size: int, small_size: int) -> void:
	var w := size.x
	var h := size.y
	var lines := [
		"ELAPSED   %s" % _bar(_progress),
		"REMAINING %05.2f MILLION MILES" % _distance_left,
		"ETA       %05.1f DAYS AT PRESENT DRIVE" % _days_left,
		"DRIVE     %3d%%" % int(round(_drive * 100.0)),
	]
	# Bottom-right: the arc sweeps up and away from this corner, so it is the one reliably
	# empty patch of the chart at every point in the voyage.
	var x := w * 0.50
	var y := h * 0.80
	for line in lines:
		draw_string(_font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, small_size, INK)
		y += small_size * 1.25

	if _drive < 0.999:
		draw_string(_font, Vector2(x, h * 0.755), "** DRIVE BELOW RATED OUTPUT **",
			HORIZONTAL_ALIGNMENT_LEFT, -1, body_size, INK)


static func _bar(fraction: float) -> String:
	var filled := int(round(clampf(fraction, 0.0, 1.0) * 24.0))
	return "[%s%s] %d%%" % ["#".repeat(filled), ".".repeat(24 - filled), int(round(fraction * 100.0))]
