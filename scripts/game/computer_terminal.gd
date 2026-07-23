class_name ComputerTerminal
extends Interactable

# The nav console, in the spirit of GMTK 2025's computer: a Control rendered into a
# SubViewport and mapped onto a quad, so it is a real screen in the room rather than a
# texture of one.
#
# Two views of the same NavChart. The one on the console is always live, readable from a
# couple of metres and glanceable on your way past; interacting brings up a full-screen
# copy for when you actually want to study it. Same class drawing both, so they can never
# disagree about where the ship is.
#
# The chart is pushed data on a timer rather than every frame. Nothing on it moves fast —
# the ship crosses a pixel every few seconds — and redrawing a few hundred jittered line
# segments at 60Hz to show a number that has not changed would be silly.

## Emitted when the player asks for the full-screen chart.
signal opened

## Seconds between chart updates. Fast enough to feel live while asleep at 24x.
@export var refresh_interval: float = 0.25
@export var chart_path: NodePath = NodePath("SubViewport/NavChart")

var _chart: NavChart
var _run: RunState = null
var _since_refresh: float = 0.0


func _ready() -> void:
	super()
	interaction_type = InteractionType.ACTIVATE
	interaction_text = "Read the nav plot"
	_chart = get_node_or_null(chart_path) as NavChart


func bind(run: RunState) -> void:
	_run = run
	_refresh()


func get_interaction_text(_held_item: Node3D = null) -> String:
	return interaction_text


# Usable with your hands full: reading a screen does not require putting the spare down,
# and making the player drop it first would be pure friction.
func can_act_on(_held_item: Node3D = null) -> bool:
	return is_enabled


func _process(delta: float) -> void:
	_since_refresh += delta
	if _since_refresh < refresh_interval:
		return
	_since_refresh = 0.0
	_refresh()


func _refresh() -> void:
	if _chart == null or _run == null:
		return
	push_to(_chart)


## Fill in a chart from the run. Used for the console and for the full-screen copy.
func push_to(chart: NavChart) -> void:
	if _run == null or chart == null:
		return
	var total: float = maxf(_run.total_distance, 0.001)
	chart.set_voyage(
		1.0 - _run.distance_remaining / total,
		_run.eta_days(),
		_run.distance_remaining,
		_run.speed_fraction()
	)


func interact() -> void:
	if not is_enabled:
		return
	opened.emit()
	interacted_with.emit(self)
