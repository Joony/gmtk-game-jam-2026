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
@onready var _computer: ComputerTerminal = $Computer
@onready var _nav_screen: CanvasLayer = $NavScreen

## Where the player is in the pod cycle. A plain bool could not express "half way in", and
## every one of these phases has to reject the inputs that belong to the others — the alarm
## can fire while the lid is still closing.
enum PodPhase { OUT, ENTERING, IN, EXITING }

## How long the ride into or out of the pod takes.
const POD_MOVE_TIME := 1.1
## Leaning in to the nav console is a shorter move over a shorter distance.
const NAV_MOVE_TIME := 0.55

## Same reasoning as PodPhase: the approach has to reject a second interact press, and the
## run can end while the player is stood reading.
enum NavPhase { AWAY, APPROACHING, READING, LEAVING }

var is_started: bool = false

var _pod_phase: PodPhase = PodPhase.OUT
var _nav_phase: NavPhase = NavPhase.AWAY
var _nav_return_position: Vector3 = Vector3.ZERO
var _nav_return_yaw: float = 0.0
var _nav_return_pitch: float = 0.0


func _ready() -> void:
	_player.global_transform = _spawn.global_transform
	_start_prompt.get_node("%StartButton").pressed.connect(start_game)
	_reticle.bind(_interactor)
	_lighting.bind_environment($WorldEnvironment)
	_readout.bind(_motion)
	# The cursor is visible while paused, so the reticle would be a second,
	# misleading pointer.
	# Pausing the SceneTree does NOT pause audio in Godot — streams carry on regardless — so
	# the klaxon and the music kept going over the pause menu until this was explicit.
	_pause_menu.paused.connect(func() -> void:
		_reticle.visible = false
		Audio.set_paused(true))
	_pause_menu.resumed.connect(func() -> void:
		_reticle.visible = true
		Audio.set_paused(false))

	_pod.interacted_with.connect(_on_pod_used)
	_run.stasis_changed.connect(_on_stasis_changed)
	# Every pod starts sealed; the player's swings open so it reads as the one to use.
	for pod in get_tree().get_nodes_in_group(&"interactables"):
		if pod is StasisPod:
			(pod as StasisPod).set_door_open((pod as StasisPod).is_player_pod, true)
	_wire_audio()
	_computer.bind(_run)
	_computer.opened.connect(_open_nav_screen)
	_nav_screen.closed.connect(_close_nav_screen)
	_run.run_ended.connect(_on_run_ended)
	_run_end.dismissed.connect(_on_run_end_dismissed)
	_hud.bind(_run)

	_show_start_prompt()


## Every sound the run makes, in one place. Game already holds references to all of these
## and RunState already emits the events, so this is purely connections — none of the systems
## below had to learn that audio exists.
func _wire_audio() -> void:
	# The IMPACT is an event — a one-shot on the frame the fault fires. The KLAXON is not;
	# it belongs to the fault's whole lifetime and is driven from state below.
	_run.alarm.connect(func(malfunction: Malfunction, _patch_failure: bool) -> void:
		Audio.impact(malfunction.severity == Malfunction.Severity.CRITICAL))
	_run.stasis_changed.connect(func(_in_stasis: bool) -> void: _update_ship_audio())
	_run.systems_changed.connect(_update_ship_audio)
	_run.run_ended.connect(func(_won: bool, _summary: Dictionary) -> void: Audio.stop_all())
	_run.oxygen_changed.connect(_on_oxygen_for_audio)

	# The repair sounds are per-fault, and they are the ones that matter most: the ratchet
	# and the tape are how the player hears which choice they just made. Positional, so a
	# fault you have not reached yet is quieter than the one under your hands.
	for node in get_tree().get_nodes_in_group(Malfunction.GROUP_MALFUNCTION):
		var fault := node as Malfunction
		fault.repaired.connect(func(m: Malfunction, permanent: bool) -> void:
			Audio.repair(permanent, m.global_position))

	# Doors are built at runtime by the Ship node, whose _ready() has already run by the time
	# this does — children are readied before their parent, which is the only reason these
	# can be connected here rather than through a build callback.
	for node in get_tree().get_nodes_in_group(RoomBuilder.GROUP_DOOR):
		var door := node as SlidingDoor
		if door == null:
			continue
		door.opened.connect(func() -> void: Audio.door(true, door.global_position))
		door.closed.connect(func() -> void: Audio.door(false, door.global_position))

	# Carried items make their noise where the player is, which is close enough to the
	# camera that positional and non-positional are indistinguishable — but doing it
	# positionally means a dropped crate sounds like it landed where it landed.
	_carry.picked_up.connect(func(item: Node3D) -> void: Audio.play_at(&"click", item.global_position))
	_carry.dropped.connect(func(item: Node3D) -> void:
		Audio.play_at(&"click_low", item.global_position, -4.0))
	_computer.opened.connect(func() -> void: Audio.play_at(&"click", _computer.global_position))
	_pod.entered.connect(func() -> void: Audio.play_at(&"plug", _pod.global_position, -2.0))
	# The pod's door gets its own sound. It is a curved panel driven round a cylinder and
	# sealed, not a door sliding in a frame, and it is the one you hear from the inside.
	_pod.door_moved.connect(func(opening: bool) -> void:
		Audio.pod_door(opening, _pod.global_position))


## Music AND klaxon follow the ship's state: stasis wins over everything, then any CRITICAL
## fault, then normal. Driven off signals that already existed rather than polled — and both
## from the same function, so the alarm and the score can never disagree about the situation.
func _update_ship_audio() -> void:
	if _run.finished:
		return
	if _run.in_stasis:
		# Sealed in the pod. An alarm loud enough to wake you has already done its job.
		Audio.set_alarm(false)
		Audio.play_music(Audio.Music.STASIS)
		return

	var critical := false
	for malfunction in _run.malfunctions():
		if malfunction.is_critical():
			critical = true
			break
	Audio.set_alarm(critical)
	Audio.play_music(Audio.Music.PANIC if critical else Audio.Music.NORMAL)


## Breathing starts at the same threshold the HUD's vignette does, so the two escalate
## together rather than the player seeing red before they hear it.
func _on_oxygen_for_audio(remaining: float, _total: float) -> void:
	var warn: float = _run.oxygen_warning
	if warn <= 0.0 or remaining > warn or _run.in_stasis:
		Audio.set_breathing(0.0)
		return
	Audio.set_breathing(1.0 - remaining / warn)


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
	Audio.play(&"click")
	_start_prompt.visible = false
	_reticle.visible = true
	_hud.visible = true
	_player.process_mode = Node.PROCESS_MODE_INHERIT
	_pause_menu.enabled = true
	# Only now does either countdown begin — neither should run down behind the prompt.
	_run.start()
	Audio.set_paused(false)
	_update_ship_audio()
	capture_mouse()
	started.emit()


func capture_mouse() -> void:
	MouseCapture.capture()


## The Audio autoload outlives this scene, so anything still playing would follow the player
## out to the main menu. Covers every exit: Quit to Menu, the end-of-run summary, and any
## future path out of the game.
func _exit_tree() -> void:
	Audio.stop_all()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	# Waking up. The player's own Interactor is switched off in stasis, so Game is the
	# only thing still listening. Ignored mid-transition: the pod is not yours to leave
	# until the lid has actually shut.
	if _pod_phase == PodPhase.IN:
		_run.exit_stasis()
		get_viewport().set_input_as_handled()
	elif _nav_phase == NavPhase.READING:
		# Same key that opened it. The Interactor is switched off while reading, so the
		# press cannot re-trigger the console the player is stood in front of.
		_nav_screen.close()
		get_viewport().set_input_as_handled()


## Reading the console walks the camera up to it rather than cutting to a menu. The screen
## in the room is the real one — a SubViewport rendering the same NavChart — so leaning in
## to read it keeps the player in the world, and the clock keeps running while they do.
## Freezing but NOT pausing is the point: checking your progress costs air like anything else.
func _open_nav_screen() -> void:
	if not is_started or _run.finished or _nav_phase != NavPhase.AWAY or _pod_phase != PodPhase.OUT:
		return
	_nav_phase = NavPhase.APPROACHING
	# Where to put the player back afterwards, including exactly where they were looking.
	_nav_return_position = _player.global_position
	_nav_return_yaw = _camera.get_yaw()
	_nav_return_pitch = _camera.get_pitch()

	_set_player_active(false)
	_player.velocity = Vector3.ZERO
	_reticle.visible = false

	var view := _computer.view_transform()
	await _glide_player(view.origin, view.basis.get_euler().y, 0.0, NAV_MOVE_TIME)
	if _nav_phase != NavPhase.APPROACHING:
		return
	_nav_phase = NavPhase.READING
	_nav_screen.open(_computer)


func _close_nav_screen() -> void:
	if _nav_phase != NavPhase.READING:
		return
	_nav_phase = NavPhase.LEAVING
	if _run.finished:
		_nav_phase = NavPhase.AWAY
		return
	await _glide_player(_nav_return_position, _nav_return_yaw, _nav_return_pitch, NAV_MOVE_TIME)
	_nav_phase = NavPhase.AWAY
	_camera.input_enabled = true
	_reticle.visible = true
	_set_player_active(true)


func _on_pod_used(_interactable: Interactable) -> void:
	if not is_started or _run.finished or _pod_phase != PodPhase.OUT:
		return
	# Climbing in with a spare under your arm would otherwise teleport it across the ship.
	if _carry.is_holding():
		_carry.drop(false)
	_enter_pod()


func _on_stasis_changed(in_stasis: bool) -> void:
	# Only the WAKING half is driven from here. Entering is sequenced by _enter_pod(),
	# which has to finish moving the player before the clock starts running fast.
	if not in_stasis and _pod_phase == PodPhase.IN:
		_exit_pod()


## Ride into the pod: freeze the player, fly the view in, shut the door, then start the
## fast-forward. The order matters — starting the clock first would have days ticking past
## while the player is still visibly walking in.
func _enter_pod() -> void:
	_pod_phase = PodPhase.ENTERING
	_set_player_active(false)
	_player.velocity = Vector3.ZERO
	_reticle.visible = false
	_pod.set_occupied(true)
	_pod.set_door_open(true)

	await _glide_player_to(_pod.view_transform(), POD_MOVE_TIME)
	if _pod_phase != PodPhase.ENTERING:
		return
	_pod.set_door_open(false)
	await get_tree().create_timer(_pod.door_duration()).timeout
	if _pod_phase != PodPhase.ENTERING:
		return

	_pod_phase = PodPhase.IN
	_run.enter_stasis()


## Ejected: open the door, fly the view back out, hand control back.
func _exit_pod() -> void:
	_pod_phase = PodPhase.EXITING
	# A run that ended while asleep goes straight to the summary; animating the player out
	# of a pod they are never going to use again just delays the screen they need to see.
	if _run.finished:
		_finish_exit()
		return
	_pod.set_door_open(true)
	await get_tree().create_timer(_pod.door_duration() * 0.5).timeout
	await _glide_player_to(_pod.exit_transform(), POD_MOVE_TIME)
	_finish_exit()


func _finish_exit() -> void:
	_pod.set_occupied(false)
	_pod_phase = PodPhase.OUT
	if not _run.finished:
		_reticle.visible = true
		_set_player_active(true)
	_camera.input_enabled = true


## Move the player smoothly to a transform, aiming the camera as it goes.
func _glide_player_to(target: Transform3D, duration: float) -> void:
	await _glide_player(target.origin, target.basis.get_euler().y, 0.0, duration)


## The one place the camera is flown by anything other than the mouse.
##
## The body is tweened rather than teleported, and the CAMERA is aimed through
## CameraController.set_look() rather than by rotating the body — the controller rewrites
## the body basis from its own yaw every frame, so a rotation applied here would be thrown
## away on the very next one.
func _glide_player(to_pos: Vector3, to_yaw: float, to_pitch: float, duration: float) -> void:
	_camera.input_enabled = false
	var from_pos := _player.global_position
	var from_yaw := _camera.get_yaw()
	var from_pitch := _camera.get_pitch()

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(
		func(t: float) -> void:
			_player.global_position = from_pos.lerp(to_pos, t)
			# lerp_angle, not lerpf: the short way round, so turning from -170 to 170
			# degrees does not spin the player through a full circle.
			_camera.set_look(lerp_angle(from_yaw, to_yaw, t), lerpf(from_pitch, to_pitch, t)),
		0.0, 1.0, duration
	)
	await tween.finished
	_player.global_position = to_pos
	_camera.set_look(to_yaw, to_pitch)
	# The interpolator would otherwise blend the camera from wherever the body was on the
	# previous physics tick, smearing the first frame after control returns.
	_player.reset_physics_interpolation()


func _set_player_active(active: bool) -> void:
	_player.set_physics_process(active)
	_interactor.set_physics_process(active)
	_interactor.set_process_unhandled_input(active)
	_carry.set_process(active)


func _on_run_ended(won: bool, summary: Dictionary) -> void:
	if _nav_phase == NavPhase.READING:
		_nav_screen.close()
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
