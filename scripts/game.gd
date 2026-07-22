extends Node3D

# Placeholder game scene controller. Step 5 hands cursor ownership to the pause menu.

@onready var _player: CharacterBody3D = $Player
@onready var _spawn: Marker3D = $PlayerSpawn


func _ready() -> void:
	_player.global_transform = _spawn.global_transform
	capture_mouse()


func capture_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
