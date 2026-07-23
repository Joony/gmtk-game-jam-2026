extends CanvasLayer

# Full-screen nav chart. Thin wrapper: the drawing and all the voyage data live in
# NavChart and ComputerTerminal, so this only decides when it is on screen and keeps the
# chart fed while it is.

signal closed

@onready var chart: NavChart = %Chart

var _terminal: ComputerTerminal = null


func _ready() -> void:
	visible = false


func open(terminal: ComputerTerminal) -> void:
	_terminal = terminal
	_terminal.push_to(chart)
	visible = true


func close() -> void:
	visible = false
	_terminal = null
	closed.emit()


func _process(_delta: float) -> void:
	# Days keep passing while you read, so the chart has to keep up. Only while open —
	# there is no point redrawing a hidden Control.
	if visible and _terminal != null:
		_terminal.push_to(chart)
