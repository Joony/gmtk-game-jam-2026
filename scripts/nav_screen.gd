extends CanvasLayer

# The "you are reading the console" state. Deliberately thin: the chart lives on the
# terminal's own SubViewport screen, which the camera has just been walked up to, so there
# is nothing to draw here but the way out.

signal closed

var _terminal: ComputerTerminal = null


func _ready() -> void:
	visible = false


func open(terminal: ComputerTerminal) -> void:
	_terminal = terminal
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	_terminal = null
	closed.emit()


func is_open() -> bool:
	return visible
