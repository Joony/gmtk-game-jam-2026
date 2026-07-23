extends CanvasLayer

# The two countdowns, plus the fault list that explains why one of them is going so slowly.
#
# Both clocks are shown as TIME, never as percentages. "38% oxygen" is not a number anyone
# can act on; "2:31 of air" answers the only question the player is actually asking, which
# is "can I get to the engine room and back". The arrival clock is ship time at the current
# speed, so a fault visibly ADDS HOURS to it the instant it fires — that is what makes the
# cost of ignoring a problem legible without a tutorial.

const COLOR_OK := Color(0.78, 0.86, 0.94)
const COLOR_WARN := Color(1.00, 0.62, 0.10)
const COLOR_CRIT := Color(1.00, 0.22, 0.18)
const COLOR_GOOD := Color(0.24, 0.90, 0.40)

## Below this fraction of cruise the arrival clock turns amber.
const SPEED_WARN := 0.75

@onready var _oxygen_value: Label = %OxygenValue
@onready var _oxygen_bar: ProgressBar = %OxygenBar
@onready var _eta_value: Label = %EtaValue
@onready var _distance_value: Label = %DistanceValue
@onready var _system_list: VBoxContainer = %SystemList
@onready var _vignette: Control = %Vignette
@onready var _stasis_panel: Control = %StasisPanel
@onready var _stasis_hint: Label = %StasisHint

var _run: RunState = null
var _pulse: float = 0.0
var _oxygen_bar_style: StyleBoxFlat = null


func _ready() -> void:
	visible = false
	_vignette.modulate.a = 0.0
	_stasis_panel.visible = false
	# Own copy of the fill style so recolouring the bar under 60s does not bleed into
	# any other ProgressBar sharing the theme.
	var fill := _oxygen_bar.get_theme_stylebox("fill")
	if fill is StyleBoxFlat:
		_oxygen_bar_style = (fill as StyleBoxFlat).duplicate()
		_oxygen_bar.add_theme_stylebox_override("fill", _oxygen_bar_style)


func bind(run: RunState) -> void:
	_run = run
	run.oxygen_changed.connect(_on_oxygen_changed)
	run.distance_changed.connect(_on_distance_changed)
	run.systems_changed.connect(_rebuild_systems)
	run.stasis_changed.connect(_on_stasis_changed)
	_on_oxygen_changed(run.oxygen_remaining, run.oxygen_total)
	_on_distance_changed(run.distance_remaining, run.total_distance)
	_rebuild_systems()


func _process(delta: float) -> void:
	if _run == null or not _run.running:
		return
	_pulse += delta
	_update_air_pressure()


## Red creep at the edges of the screen as the air runs out, faster the lower it gets.
## Cheap, and it works peripherally — the player feels it while looking at the panel they
## are repairing rather than at the gauge.
func _update_air_pressure() -> void:
	var warn: float = _run.oxygen_warning
	if warn <= 0.0 or _run.oxygen_remaining > warn or _run.finished:
		_vignette.modulate.a = 0.0
		return
	var severity := 1.0 - _run.oxygen_remaining / warn
	# 0.6 Hz at the threshold rising to ~2.4 Hz at empty: the rate itself is the signal.
	var hz := lerpf(0.6, 2.4, severity)
	var throb := 0.5 + 0.5 * sin(TAU * hz * _pulse)
	_vignette.modulate.a = severity * (0.20 + 0.35 * throb)


func _on_oxygen_changed(remaining: float, total: float) -> void:
	_oxygen_value.text = _clock(remaining)
	_oxygen_bar.value = 0.0 if total <= 0.0 else remaining / total * 100.0
	var color := COLOR_OK
	if _run != null and remaining <= _run.oxygen_warning * 0.35:
		color = COLOR_CRIT
	elif _run != null and remaining <= _run.oxygen_warning:
		color = COLOR_WARN
	_oxygen_value.add_theme_color_override("font_color", color)
	if _oxygen_bar_style != null:
		_oxygen_bar_style.bg_color = color


func _on_distance_changed(remaining: float, _total: float) -> void:
	if _run == null:
		return
	_eta_value.text = _clock(_run.eta_seconds(), true)
	var fraction := _run.speed_fraction()
	_distance_value.text = "%.1f km  ·  drive %d%%" % [remaining / 1000.0, int(round(fraction * 100.0))]
	var color := COLOR_OK
	if fraction < SPEED_WARN * 0.6:
		color = COLOR_CRIT
	elif fraction < SPEED_WARN:
		color = COLOR_WARN
	_eta_value.add_theme_color_override("font_color", color)


func _rebuild_systems() -> void:
	for child in _system_list.get_children():
		child.queue_free()
	if _run == null:
		return
	for malfunction in _run.malfunctions():
		if malfunction.is_active:
			_add_system_line(
				"! %s — %s  (-%d%% drive)" % [
					malfunction.system_name,
					malfunction.fault_text,
					int(round(malfunction.speed_penalty * 100.0)),
				],
				COLOR_CRIT if malfunction.is_critical() else COLOR_WARN
			)
		elif malfunction.is_patched:
			# Naming the patch keeps its eventual failure attributable to the player's
			# own choice rather than reading as random punishment.
			_add_system_line("~ %s — running on a patch" % malfunction.system_name, COLOR_WARN)


func _add_system_line(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_font_size_override("font_size", 30)
	_system_list.add_child(label)


func _on_stasis_changed(in_stasis: bool) -> void:
	_stasis_panel.visible = in_stasis
	if in_stasis and _run != null:
		_stasis_hint.text = "TRAVELLING AT %dx  ·  [E] WAKE" % int(round(_run.stasis_time_scale))


## Seconds to a clock string. Air is mm:ss; the journey needs hours, and reads "--:--:--"
## when the ship is stopped rather than inventing an arrival time it cannot promise.
static func _clock(seconds: float, with_hours: bool = false) -> String:
	if is_inf(seconds) or is_nan(seconds):
		return "--:--:--" if with_hours else "--:--"
	var total := int(ceil(maxf(seconds, 0.0)))
	if with_hours:
		return "%d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]
	return "%d:%02d" % [total / 60, total % 60]
