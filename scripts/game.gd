extends Node3D

# The game does not begin until the player clicks START. That click is what makes
# mouse capture work in a browser: pointer lock is only granted inside a user-gesture
# handler, so requesting it from _ready() after a scene transition is rejected on web.
# It doubles as a decent "here are the controls" beat on desktop.

signal started

@onready var _player: CharacterBody3D = $Player
@onready var _spawn: Marker3D = $PlayerSpawn
@onready var _pause_menu: CanvasLayer = $PauseMenu
@onready var _start_prompt: CanvasLayer = $StartPrompt

var is_started: bool = false


func _ready() -> void:
	_player.global_transform = _spawn.global_transform
	_start_prompt.get_node("%StartButton").pressed.connect(start_game)
	_show_start_prompt()


func _show_start_prompt() -> void:
	is_started = false
	_start_prompt.visible = true
	# Freeze the player and disable Esc until the game actually begins.
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_pause_menu.enabled = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_start_prompt.get_node("%StartButton").grab_focus()


func start_game() -> void:
	if is_started:
		return
	is_started = true
	_start_prompt.visible = false
	_player.process_mode = Node.PROCESS_MODE_INHERIT
	_pause_menu.enabled = true
	capture_mouse()
	started.emit()


func capture_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
