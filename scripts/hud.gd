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

@onready var _oxygen_value: DigitReadout = %OxygenValue
@onready var _oxygen_bar: ProgressBar = %OxygenBar
@onready var _eta_value: DigitReadout = %EtaValue
@onready var _distance_value: DigitReadout = %DistanceValue
@onready var _drive_value: DigitReadout = %DriveValue
@onready var _system_list: VBoxContainer = %SystemList
@onready var _vignette: Control = %Vignette
@onready var _stasis_panel: Control = %StasisPanel
@onready var _stasis_hint: Label = %StasisHint

var _run: RunState = null
var _pulse: float = 0.0
## The system-list rows, paired with the fault each one describes, so a bleeding fault's line
## can be re-texted in place. Rebuilding the list every frame would mean a queue_free() and a
## fresh Label per fault per frame for a number that fits in the row already there.
var _system_lines: Array[Dictionary] = []
## Need rows, kept separately from the fault rows because they are re-texted on a different
## schedule (every frame, since a need is a clock) and rebuilt off a different signal.
var _need_lines: Array[Dictionary] = []
var _oxygen_bar_style: StyleBoxFlat = null
## The life-support tank, so the readout can call for a canister. See CanisterSilo.
var _oxygen: CanisterSilo = null


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
	run.needs_changed.connect(_rebuild_needs)
	run.stasis_changed.connect(_on_stasis_changed)
	_on_oxygen_changed(run.oxygen_remaining, run.oxygen_total)
	_on_distance_changed(run.distance_remaining, run.total_distance)
	_rebuild_systems()
	_rebuild_needs()


## Bound separately from the run: the tank is a prop, and RunState does not know about props.
func bind_oxygen(silo: CanisterSilo) -> void:
	_oxygen = silo
	if silo != null and not silo.recharged.is_connected(_on_recharged):
		silo.recharged.connect(_on_recharged)
	_rebuild_needs()


func _on_recharged(_seconds: float) -> void:
	_rebuild_needs()


func _process(delta: float) -> void:
	if _run == null or not _run.running:
		return
	_pulse += delta
	_update_air_pressure()
	# A critical fault bleeds speed continuously, so its line has to be RE-TEXTED every frame,
	# not rebuilt on systems_changed like the list itself. Watching the number climb while you
	# decide is the mechanic; a figure that only moved when something broke would tell the
	# player the loss was a one-off charge, which is exactly what it no longer is.
	for line in _system_lines:
		var malfunction: Malfunction = line["malfunction"]
		if malfunction.is_active and malfunction.speed_decay_per_day > 0.0:
			(line["label"] as Label).text = _fault_line(malfunction)
	# A need is a clock, so its row is a clock: re-texted every frame, unconditionally. This
	# is the row the player is reading while deciding whether the walk is worth it. The fuel
	# tank is the same — it drains on the ship's clock, so it moves without anything happening.
	for line in _need_lines:
		var label := line["label"] as Label
		if line.has("oxygen"):
			continue  # fixed text; the air clock next to it is the number that moves
		if line.has("need"):
			var need: Need = line["need"]
			label.text = _need_line(need)
			label.add_theme_color_override("font_color", _need_color(need))
		else:
			var silo: Silo = line["silo"]
			label.text = _silo_line(silo)
			label.add_theme_color_override("font_color", _silo_color(silo))
	if _stasis_panel.visible:
		_update_stasis_rate()


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
	_oxygen_value.set_value(_clock(remaining))
	_oxygen_bar.value = 0.0 if total <= 0.0 else remaining / total * 100.0
	var color := COLOR_OK
	if _run != null and remaining <= _run.oxygen_warning * 0.35:
		color = COLOR_CRIT
	elif _run != null and remaining <= _run.oxygen_warning:
		color = COLOR_WARN
	_oxygen_value.set_color(color)
	if _oxygen_bar_style != null:
		_oxygen_bar_style.bg_color = color


func _on_distance_changed(remaining: float, _total: float) -> void:
	if _run == null:
		return
	# Zero-padded to a constant width. Fixed-width SLOTS stop a glyph swap shifting the
	# row, but 9.9 becoming 10.0 adds a character and would still shunt everything left.
	_eta_value.set_value(_days(_run.eta_days()))
	_distance_value.set_value("%06.2f" % minf(remaining, 999.99))
	var fraction := _run.speed_fraction()
	_drive_value.set_value("%3d%%" % int(round(fraction * 100.0)))
	var color := COLOR_OK
	if fraction < SPEED_WARN * 0.6:
		color = COLOR_CRIT
	elif fraction < SPEED_WARN:
		color = COLOR_WARN
	_eta_value.set_color(color)
	_drive_value.set_color(color)


func _rebuild_systems() -> void:
	# Frees ITS OWN rows, not every child of the container: the need rows live in the same
	# list and are rebuilt on a different signal, so clearing the container wholesale would
	# take the CO2 clock off the screen every time a fault changed.
	for line in _system_lines:
		(line["label"] as Label).queue_free()
	_system_lines.clear()
	if _run == null:
		return
	for malfunction in _run.malfunctions():
		if malfunction.is_active:
			_add_system_line(
				malfunction,
				_fault_line(malfunction),
				COLOR_CRIT if malfunction.is_critical() else COLOR_WARN
			)
		elif malfunction.is_patched:
			# Naming the patch keeps its eventual failure attributable to the player's
			# own choice rather than reading as random punishment — and now the line has to
			# carry the speed the bodge LOCKED IN too, because that is the part of the
			# player's own choice that never goes away.
			var kept := ""
			if malfunction.speed_decay > 0.0:
				kept = ", -%d%% drive for good" % int(round(malfunction.speed_decay * 100.0))
			_add_system_line(
				malfunction,
				"~ %s — running on a patch%s" % [malfunction.system_name, kept],
				COLOR_WARN
			)


## The need rows. A need only gets one once it has crossed its warning line — the readout
## starts clean and fills up as the run goes wrong, rather than shipping nine dials on the
## chance one of them matters (TODO 17e). Rebuilt on `needs_changed`, never per frame; the
## text inside an existing row is what moves.
func _rebuild_needs() -> void:
	for line in _need_lines:
		(line["label"] as Label).queue_free()
	_need_lines.clear()
	if _run == null:
		return
	for need in _run.pressing_needs():
		var label := _make_line(_need_line(need), _need_color(need))
		# Above the fault list: a need is about your body and a fault is about the ship, and
		# the one that can kill you in the next minute should not be underneath the one that
		# is costing you half a day of travel.
		_system_list.move_child(label, 0)
		_need_lines.append({"need": need, "label": label})
	# Silos share the row list rather than getting their own: a tank running low and a body
	# clock running down are the same problem to the player — something needs fetching.
	# OXYGEN LOW is a WARNING, not a fault — nothing is broken, the canister is spent and
	# there is a fresh one in the cargo bay. It says what to do rather than what is wrong,
	# because at under a minute of air the player has no time to work it out.
	if _oxygen != null and _oxygen.is_low():
		var label := _make_line("~ OXYGEN LOW — REPLACE O2 CANISTER", COLOR_WARN)
		_system_list.move_child(label, 0)
		_need_lines.append({"oxygen": _oxygen, "label": label})
	for silo in _run.pressing_silos():
		var label := _make_line(_silo_line(silo), _silo_color(silo))
		_system_list.move_child(label, 0)
		_need_lines.append({"silo": silo, "label": label})


## Shown as TIME, like both of the other clocks — "1:12 of CO2" is a number you can weigh a
## walk against, where "24%" is not.
func _need_line(need: Need) -> String:
	return "%s %s — %s" % [
		"!" if need.lethal else "~", need.display_name, _clock(need.remaining)
	]


func _need_color(need: Need) -> Color:
	if need.fraction() <= need.warn_at * 0.4:
		return COLOR_CRIT
	return COLOR_WARN


## A tank reads as a PERCENTAGE, unlike the two clocks. It is not a countdown the player can
## convert into "can I get there and back" — what they need to know is how much is left and
## what to bring, so the row says both.
func _silo_line(silo: Silo) -> String:
	if silo.is_exhausted():
		return "%s %s — EMPTY, needs %s" % [
			"!" if _silo_is_critical(silo) else "~", silo.display_name, silo.accepts
		]
	return "~ %s — %d%%, needs %s" % [
		silo.display_name, int(round(silo.headroom() * 100.0)), silo.accepts
	]


func _silo_color(silo: Silo) -> Color:
	return COLOR_CRIT if _silo_is_critical(silo) else COLOR_WARN


## AN EMPTY TANK IS A WARNING, NOT A FAULT. Nothing is broken and there is nothing to repair —
## the answer is a walk to the cargo bay — so it must not sit in the list wearing the same red
## "!" as a ruptured coolant line. An empty vending machine reading like a hull breach teaches
## the player to distrust the colour, and then the coolant line does not land either.
##
## The silo says which of the two it is (`empty_is_critical`) rather than the HUD guessing.
## An earlier version of this asked whether the tank stopped the DRIVE, which is the wrong
## question: a jammed vending machine does not touch the drive and still kills you, just
## slower. What separates them is WHEN — see the field's own note.
func _silo_is_critical(silo: Silo) -> bool:
	return silo.empty_is_critical and silo.is_exhausted()


## One broken system's line. Split out because a bleeding fault re-texts every frame from
## _process(); a fault and its line must never be able to disagree about the wording.
func _fault_line(malfunction: Malfunction) -> String:
	if malfunction.speed_decay_per_day > 0.0:
		# Where it is NOW and where it is going. Without the ceiling the number is just
		# alarming; with it, the player can price the walk to fetch a spare against it.
		return "! %s — %s  (-%d%% drive, falling to -%d%%)" % [
			malfunction.system_name,
			malfunction.fault_text,
			int(round(malfunction.speed_decay * 100.0)),
			int(round(malfunction.speed_penalty * 100.0)),
		]
	# A fault that costs no drive says nothing about drive. Not every system is a ship system:
	# the vending machine jamming is a real problem, but "(-0% drive)" reads as a bug in the
	# readout rather than as a fault with no speed cost.
	if malfunction.speed_penalty <= 0.0:
		return "! %s — %s" % [malfunction.system_name, malfunction.fault_text]
	return "! %s — %s  (-%d%% drive)" % [
		malfunction.system_name,
		malfunction.fault_text,
		int(round(malfunction.speed_penalty * 100.0)),
	]


func _add_system_line(malfunction: Malfunction, text: String, color: Color) -> void:
	_system_lines.append({
		"malfunction": malfunction,
		"label": _make_line(text, color),
	})


## One row of the list. Faults and needs share it so they cannot drift apart typographically —
## they sit in the same column and have to read as one readout.
func _make_line(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_font_size_override("font_size", 30)
	_system_list.add_child(label)
	return label


## Hide the fault list while the player is leaning into the nav console.
##
## Not cosmetic: the console screen fills the middle of the view when the camera walks up to it,
## and the list runs straight across it — the damage plan's LIFE SUPPORT blob was underneath
## "! LIFE SUPPORT — EMPTY, NEEDS O2". Losing the list for those few seconds costs nothing,
## because the page it is covering is the same information laid out on the ship.
##
## The two CLOCKS stay up. Reading the console costs air like everything else, and hiding the
## gauge that says how much would be hiding the price of the thing the player is doing.
func set_list_visible(shown: bool) -> void:
	_system_list.visible = shown


func _on_stasis_changed(in_stasis: bool) -> void:
	_stasis_panel.visible = in_stasis
	if in_stasis:
		_update_stasis_rate()


## The live rate, not the configured one. The drive takes a moment to wind up, and watching
## the number climb is most of what sells the spin-up as acceleration rather than a cut.
func _update_stasis_rate() -> void:
	if _run == null:
		return
	_stasis_hint.text = "%.2f DAYS PER SECOND  ·  [E] WAKE" % (
		_run.days_per_real_second * _run.time_scale
	)


## Air, as m:ss. The whole budget is a few minutes, so one minutes digit is always enough.
static func _clock(seconds: float) -> String:
	var total := int(ceil(maxf(seconds, 0.0)))
	return "%01d:%02d" % [mini(total / 60, 9), total % 60]


## Days to arrival. Dashes when the ship is stopped dead, rather than an arrival date it
## cannot promise — and the same character count, so the row does not jump.
static func _days(days: float) -> String:
	# A dead drive never arrives, and the readout should say that rather than showing a row of
	# dashes that reads as "no data". Same width as the digits it replaces so the panel does
	# not reflow the moment the engine dies.
	if is_inf(days) or is_nan(days):
		return "  ∞  "
	return "%05.1f" % minf(maxf(days, 0.0), 999.9)
