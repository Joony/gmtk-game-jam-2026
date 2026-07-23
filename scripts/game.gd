extends Node3D

# The game does not begin until the player clicks START. That click is what makes
# mouse capture work in a browser: pointer lock is only granted inside a user-gesture
# handler, so requesting it from _ready() after a scene transition is rejected on web.
# It doubles as a decent "here are the controls" beat on desktop.
#
# This node also owns the two things that have to happen to the PLAYER when the run state
# changes — being put in the pod, and being taken out of the world at the end — because
# RunState deliberately knows nothing about the player, the camera or the cursor.

signal started

@onready var _player: CharacterBody3D = $Player
@onready var _spawn: Marker3D = $PlayerSpawn
@onready var _pause_menu: CanvasLayer = $PauseMenu
@onready var _start_prompt: CanvasLayer = $StartPrompt
@onready var _reticle: CanvasLayer = $Reticle
@onready var _interactor: Interactor = $Player/Interactor
@onready var _carry: Carry = $Player/Carry
@onready var _camera: CameraController = $Player/CameraRig
@onready var _lighting: LightingController = $Lighting
@onready var _motion: ShipMotion = $Motion
@onready var _readout: CanvasLayer = $DebugReadout
@onready var _run: RunState = $Run
@onready var _hud: CanvasLayer = $HUD
@onready var _run_end: CanvasLayer = $RunEnd
@onready var _pod: StasisPod = $StasisPod

var is_started: bool = false

## Where the player was standing when they climbed into the pod, so waking up puts them
## back on their feet rather than dumping them at the spawn point.
var _pre_stasis_transform: Transform3D = Transform3D.IDENTITY


func _ready() -> void:
	_player.global_transform = _spawn.global_transform
	_start_prompt.get_node("%StartButton").pressed.connect(start_game)
	_reticle.bind(_interactor)
	_lighting.bind_environment($WorldEnvironment)
	_readout.bind(_motion)
	# The cursor is visible while paused, so the reticle would be a second,
	# misleading pointer.
	_pause_menu.paused.connect(func() -> void: _reticle.visible = false)
	_pause_menu.resumed.connect(func() -> void: _reticle.visible = true)

	_pod.interacted_with.connect(_on_pod_used)
	_run.stasis_changed.connect(_on_stasis_changed)
	_run.run_ended.connect(_on_run_ended)
	_run_end.dismissed.connect(_on_run_end_dismissed)
	_hud.bind(_run)

	_show_start_prompt()


func _show_start_prompt() -> void:
	is_started = false
	_start_prompt.visible = true
	_reticle.visible = false
	_hud.visible = false
	# Freeze the player and disable Esc until the game actually begins.
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_pause_menu.enabled = false
	MouseCapture.release()
	_start_prompt.get_node("%StartButton").grab_focus()


func start_game() -> void:
	if is_started:
		return
	is_started = true
	_start_prompt.visible = false
	_reticle.visible = true
	_hud.visible = true
	_player.process_mode = Node.PROCESS_MODE_INHERIT
	_pause_menu.enabled = true
	# Only now does either countdown begin — neither should run down behind the prompt.
	_run.start()
	capture_mouse()
	started.emit()


func capture_mouse() -> void:
	MouseCapture.capture()


func _unhandled_input(event: InputEvent) -> void:
	# Waking up. The player node is disabled in stasis, so its Interactor cannot serve
	# this — Game is the only thing still listening.
	if _run.in_stasis and event.is_action_pressed("interact"):
		_run.exit_stasis()
		get_viewport().set_input_as_handled()


func _on_pod_used(_interactable: Interactable) -> void:
	if not is_started or _run.finished or _run.in_stasis:
		return
	# Climbing in with a part under your arm would otherwise teleport it across the ship.
	if _carry.is_holding():
		_carry.drop(false)
	_run.enter_stasis()


func _on_stasis_changed(in_stasis: bool) -> void:
	_pod.set_occupied(in_stasis)
	_reticle.visible = not in_stasis
	if in_stasis:
		_pre_stasis_transform = _player.global_transform
		_player.velocity = Vector3.ZERO
		_move_player_to(_pod.get_node("PodView") as Node3D)
	else:
		_move_player_to(null)
	# NOTE: movement, interaction and carrying stop, but the CAMERA keeps running, so you
	# can still look around from inside the pod. Disabling the whole Player subtree would
	# have been one line, but CameraRig is a child of it — the view would freeze on
	# whatever you happened to be facing when you climbed in, which reads as a crash.
	_set_player_active(not in_stasis)


## Stop everything the player does without stopping them seeing. `to` of null restores
## the transform saved on entering stasis.
func _move_player_to(to: Node3D) -> void:
	_player.global_transform = to.global_transform if to != null else _pre_stasis_transform
	# Teleporting with physics interpolation on otherwise smears the camera across the
	# ship for one frame, because the interpolator blends from the old origin.
	_player.reset_physics_interpolation()
	# The camera owns yaw and would overwrite the body basis we just set.
	_camera.adopt_body_yaw()


func _set_player_active(active: bool) -> void:
	_player.set_physics_process(active)
	_interactor.set_physics_process(active)
	_interactor.set_process_unhandled_input(active)
	_carry.set_process(active)


func _on_run_ended(won: bool, summary: Dictionary) -> void:
	_reticle.visible = false
	_hud.visible = false
	_pause_menu.enabled = false
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	MouseCapture.release()
	get_tree().paused = true
	_run_end.show_result(won, summary)


func _on_run_end_dismissed() -> void:
	# Unpause BEFORE the scene change: the flag is on the tree, not the scene, so leaving
	# it set would deliver a frozen main menu.
	get_tree().paused = false
	SceneManager.change_scene("res://scenes/main_menu.tscn")
