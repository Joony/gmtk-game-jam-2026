extends CanvasLayer

# The "you are reading the console" state. Deliberately thin: the chart lives on the
# terminal's own SubViewport screen, which the camera has just been walked up to, so there
# is nothing to draw here but the way out — and, now that the console has two pages, the way
# between them.
#
# The prompt names the OTHER page rather than saying "flip", so the player knows what they are
# about to get before spending the keypress on finding out.

signal closed

@onready var _hint: Label = %Hint

var _terminal: ComputerTerminal = null


func _ready() -> void:
	visible = false


func open(terminal: ComputerTerminal) -> void:
	_terminal = terminal
	visible = true
	if _terminal != null and not _terminal.page_changed.is_connected(_on_page_changed):
		_terminal.page_changed.connect(_on_page_changed)
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	if _terminal != null and _terminal.page_changed.is_connected(_on_page_changed):
		_terminal.page_changed.disconnect(_on_page_changed)
	_terminal = null
	closed.emit()


func is_open() -> bool:
	return visible


func refresh() -> void:
	if _terminal == null:
		_hint.text = "[E] STEP AWAY"
		return
	_hint.text = "[E] STEP AWAY     [A/D] %s" % _terminal.other_page_name()


func _on_page_changed(_page: int) -> void:
	refresh()
