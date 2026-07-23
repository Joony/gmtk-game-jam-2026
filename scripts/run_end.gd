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


func show_result(won: bool, summary: Dictionary) -> void:
	_title.text = "ARRIVED" if won else "OUT OF AIR"
	_title.add_theme_color_override("font_color", COLOR_WIN if won else COLOR_LOSE)

	var covered: float = summary.get("distance_covered", 0.0)
	var total: float = maxf(summary.get("total_distance", 1.0), 1.0)
	if won:
		_subtitle.text = "You made the destination with %s of air to spare." % _clock(summary.get("air_left", 0.0))
	else:
		_subtitle.text = "The ship drifted on without you, %.0f%% of the way there." % (covered / total * 100.0)

	for child in _stats.get_children():
		child.queue_free()
	_stat("Distance covered", "%.1f km of %.1f km" % [covered / 1000.0, total / 1000.0])
	_stat("Air spent", "%s of %s" % [_clock(summary.get("air_spent", 0.0)), _clock(summary.get("air_total", 0.0))])
	_stat("Permanent repairs", "%d" % int(summary.get("repairs_permanent", 0)))
	_stat("Patches", "%d  (%d gave out)" % [
		int(summary.get("repairs_patched", 0)), int(summary.get("patch_failures", 0))
	])

	for child in _choices.get_children():
		child.queue_free()
	var choices: Array = summary.get("choices", [])
	for entry in choices:
		var label := Label.new()
		label.text = "·  %s" % entry
		label.add_theme_font_size_override("font_size", 28)
		label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.86))
		_choices.add_child(label)

	visible = true
	_button.grab_focus()


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
