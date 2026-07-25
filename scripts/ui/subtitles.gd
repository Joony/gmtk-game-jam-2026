extends CanvasLayer

# Autoload "Subtitles": the one place the ship computer's words appear on screen.
#
# AN AUTOLOAD RATHER THAN A HUD ELEMENT, for two reasons. The HUD is hidden for the whole cold
# open and the computer's first line lands on the frame it appears — a caption parented to it
# would miss the one line that explains the game. And the HUD belongs to the game scene, while
# Audio does not: anything that ever speaks from a menu, an intro or a run-end screen gets
# captioned for free this way, with no second copy of this node to keep in step.
#
# It owns no timing of its own. Audio drives the text off the voice player's playback position
# and emits subtitle_changed; this node draws whatever it is handed and is otherwise inert.

## Bottom-anchored and BOTTOM-ALIGNED, so the last line always sits the same distance from the
## edge and a two-line caption grows upward into empty screen instead of shunting itself down
## over the "IN STASIS" panel.
@onready var _line: Label = %Line

## Off hides the caption without stopping anything upstream — Audio keeps tracking, so turning
## it back on mid-line picks up the current cue rather than waiting for the next one.
var enabled: bool = true:
	set(value):
		enabled = value
		if is_node_ready():
			_redraw()


func _ready() -> void:
	# The pause menu pauses the tree; Audio does not stop emitting (it runs while paused so the
	# menu's own click is audible), and a caption frozen half-drawn would be worse than one
	# that simply holds.
	process_mode = Node.PROCESS_MODE_ALWAYS
	Audio.subtitle_changed.connect(_on_subtitle_changed)
	# Whatever is already being said. Matters on a scene change mid-line, where this node is
	# built after the signal that would have told it.
	_redraw()


func _on_subtitle_changed(_text: String) -> void:
	_redraw()


func _redraw() -> void:
	var text := Audio.subtitle if enabled else ""
	_line.text = text
	# Hidden rather than blank: an empty Label still draws its background in any theme that
	# gives it one, and this sits over the middle of the screen.
	_line.visible = text != ""
