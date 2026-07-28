extends CanvasLayer

# End of run, win or lose. Shows the numbers, then the list of choices the player made.
#
# The choice list is the cheapest part of step 12d and does the most work: a branch the
# player cannot remember taking may as well not have branched. Seeing "Vented 25s of air
# to patch the coolant loop" next to "Your patch on the main drive gave out" is what turns
# a run into a story they can retell — and what makes the next run's decisions feel loaded.

const COLOR_WIN := Color(0.24, 0.90, 0.40)
const COLOR_LOSE := Color(1.00, 0.22, 0.18)

signal dismissed

@onready var _dim: ColorRect = $Dim
@onready var _center: CenterContainer = $Center
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _stats: GridContainer = %Stats
@onready var _choices: VBoxContainer = %Choices
@onready var _button: Button = %ContinueButton


func _ready() -> void:
	visible = false
	# Both end states arrive with the tree paused, so this layer has to keep processing
	# to accept the click that gets the player out.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_button.pressed.connect(func() -> void: dismissed.emit())


## Wipe to black over whatever the player is left looking at, before any of the numbers
## arrive. Its own step rather than part of show_result() because it has to finish while the
## game is still RUNNING: the tree is paused the moment the summary goes up, and the collapse
## it follows would freeze mid-fall if the pause came first.
func fade_to_black(duration: float) -> void:
	visible = true
	_center.visible = false
	_dim.modulate.a = 0.0
	var tween := create_tween()
	# Explicit, like SceneManager's: this layer runs while paused, and the tween has to as well
	# or a pause landing mid-wipe would leave the screen half-black forever.
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_dim, "modulate:a", 1.0, duration)
	await tween.finished


func show_result(won: bool, summary: Dictionary) -> void:
	# Self-sufficient: fade_to_black() is the way in from a real run, but tests and any future
	# caller must be able to put the screen up without one.
	visible = true
	_dim.modulate.a = 1.0
	_center.visible = true
	# There is more than one way to die now. Running out of air is still the default and still
	# reads "OUT OF AIR", but a need that killed you names its own death (Need.fatal_title) and
	# it arrives here through the summary — so the screen never has to know what a need is.
	var title: String = summary.get("end_title", "")
	_title.text = "ARRIVED" if won else (title if title != "" else "OUT OF AIR")
	_title.add_theme_color_override("font_color", COLOR_WIN if won else COLOR_LOSE)

	var covered: float = summary.get("distance_covered", 0.0)
	var total: float = maxf(summary.get("total_distance", 1.0), 1.0)
	var text: String = summary.get("end_text", "")
	if won:
		_subtitle.text = "You made the destination with %s of air to spare." % _clock(summary.get("air_left", 0.0))
	elif text != "":
		_subtitle.text = "%s The ship drifted on without you, %.0f%% of the way there." % [
			text, covered / total * 100.0
		]
	else:
		_subtitle.text = "The ship drifted on without you, %.0f%% of the way there." % (covered / total * 100.0)

	for child in _stats.get_children():
		child.queue_free()
	# MILLION MILES, which is the unit the player has been reading on the HUD all run. This used
	# to divide by 1000 and call the result km — so an entire 82-million-mile crossing reported
	# "0.1 km of 0.1 km".
	_stat("Distance covered", "%.1f of %.1f million miles" % [covered, total])
	_stat("Time survived", "%.1f days" % summary.get("days_elapsed", 0.0))
	# NO DENOMINATOR. Canisters refill the tank, so `oxygen_total` is the tank's size and not
	# the run's air budget — "X of Y" was inviting a reading that stops being true the first
	# time anyone refills. The canister count is the honest scarcity figure and sits beside it.
	_stat("Air breathed", _clock(summary.get("air_breathed", 0.0)))
	_stat("Canisters used", "%d" % int(summary.get("canisters_used", 0)))
	_stat("Permanent repairs", "%d" % int(summary.get("repairs_permanent", 0)))
	_stat("Patches", "%d  (%d gave out)" % [
		int(summary.get("repairs_patched", 0)), int(summary.get("patch_failures", 0))
	])

	for child in _choices.get_children():
		child.queue_free()
	# TWO LISTS, not one. What the player chose and what happened to them were a single
	# undifferentiated bullet list, so a screen headed by the player's own decisions was half
	# full of things they did not do — "Your patch gave out" sitting under the same dot as
	# "Repaired the coolant loop properly".
	_section("What you did", summary.get("choices", []), Color(0.72, 0.78, 0.86))
	_section("What went wrong", summary.get("events", []), Color(1.00, 0.62, 0.10))

	visible = true
	_button.grab_focus()


## One headed, de-duplicated block of the summary. Empty sections are omitted entirely rather
## than left as a heading over nothing — a flawless run should not be told what went wrong.
func _section(heading: String, entries: Array, color: Color) -> void:
	if entries.is_empty():
		return
	var title := Label.new()
	title.text = heading
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.55, 0.60, 0.68))
	_choices.add_child(title)

	for line in _collapsed(entries):
		var label := Label.new()
		label.text = "·  %s" % line
		label.add_theme_font_size_override("font_size", 28)
		label.add_theme_color_override("font_color", color)
		_choices.add_child(label)


## Identical entries folded into one line with a count, in the order they first happened.
##
## A crossing throws about forty repairs across the same handful of systems, so the raw list is
## forty lines of near-duplicates — which is not a story, and is most of why the screen ran off
## the bottom. Scrolling alone would not have fixed that: forty lines that scroll are still
## forty lines.
static func _collapsed(entries: Array) -> Array[String]:
	var order: Array[String] = []
	var counts := {}
	for entry in entries:
		var text := String(entry)
		if not counts.has(text):
			order.append(text)
			counts[text] = 0
		counts[text] += 1
	var out: Array[String] = []
	for text in order:
		var n: int = counts[text]
		out.append(text if n == 1 else "%s  x%d" % [text, n])
	return out


func _stat(label: String, value: String) -> void:
	var name_label := Label.new()
	name_label.text = label
	name_label.add_theme_font_size_override("font_size", 30)
	name_label.add_theme_color_override("font_color", Color(0.55, 0.60, 0.68))
	_stats.add_child(name_label)

	var value_label := Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 30)
	value_label.add_theme_color_override("font_color", Color(0.80, 0.86, 0.94))
	_stats.add_child(value_label)


static func _clock(seconds: float) -> String:
	var total := int(round(maxf(seconds, 0.0)))
	return "%d:%02d" % [total / 60, total % 60]
