extends Node3D

# The game starts itself as soon as the scene loads — the intro video already gated the
# launch, so there is no separate "press START" screen any more. See start_game() for the
# one wrinkle this leaves: browser pointer lock wants a user gesture, which a video that
# played to the end does not provide, so on web the capture waits for the first click.
#
# This node also owns the two things that have to happen to the PLAYER when the run state
# changes — being put in the pod, and being taken out of the world at the end — because
# RunState deliberately knows nothing about the player, the camera or the cursor.
#
# There is no PlayerSpawn marker any more: the run opens with the player sealed inside the
# stasis pod, so the pod's own PodView/PodExit markers are the only start positions there are.
# See _pose_in_pod().

signal started

@onready var _player: CharacterBody3D = $Player
@onready var _pause_menu: CanvasLayer = $PauseMenu
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
## Volume of the cork pop that starts the pod door opening. See _on_pod_door_moved.
const POD_POP_DB := 0.0
## How long the pop gets to itself before the door's own sound comes in under it. Long enough
## for the cork's attack to clear (plug_in decays 0.85 -> 0.12 in 60 ms), short enough that the
## panel is not visibly moving in silence.
const POD_POP_LEAD := 0.32
## Leaning in to the nav console is a shorter move over a shorter distance.
const NAV_MOVE_TIME := 0.55
## How long the player lies sealed in the pod before the ship wakes them, at the very start of
## the run. Long enough to register the shell around you and the stasis readout spinning up,
## short enough that it is a beat rather than a wait. [E] skips it like any other stasis.
const OPENING_STASIS_TIME := 1.6

## Same reasoning as PodPhase: the approach has to reject a second interact press, and the
## run can end while the player is stood reading.
enum NavPhase { AWAY, APPROACHING, READING, LEAVING }

var is_started: bool = false

## True from load until the ship wakes the player for the first time. The cold open runs
## silent and bare — no music, no HUD, no "IN STASIS" panel — so the first thing the player
## gets is the pod's seal letting go. See _pose_in_pod() and _on_stasis_changed().
var _in_opening_stasis: bool = true
## Latch for the computer's low-air call, so it happens once. See _on_oxygen_for_audio().
var _warned_low_air: bool = false
## Set when the opening stasis ends, spent when the player is out of the pod and back in
## control. A latch rather than a call at the wake, because [E] and the timer both end that
## stasis and only _finish_exit() knows when the ride out is over.
var _intro_line_pending: bool = false

var _pod_phase: PodPhase = PodPhase.OUT
var _nav_phase: NavPhase = NavPhase.AWAY
var _nav_return_position: Vector3 = Vector3.ZERO
var _nav_return_yaw: float = 0.0
var _nav_return_pitch: float = 0.0


func _ready() -> void:
	_reticle.bind(_interactor)
	_lighting.bind_environment($WorldEnvironment)
	# Room culling: only the room the player is in (and its near neighbours) stays lit. The
	# nine-room ship has 93 fixtures, well past what GL Compatibility will draw at once.
	_lighting.bind_occupancy($Ship, $Player)
	_readout.bind(_motion)
	# The cursor is visible while paused, so the reticle would be a second,
	# misleading pointer.
	# Pausing the SceneTree does NOT pause audio in Godot — streams carry on regardless — so
	# the klaxon and the music kept going over the pause menu until this was explicit.
	_pause_menu.paused.connect(func() -> void:
		_refresh_reticle()
		Audio.set_paused(true))
	_pause_menu.resumed.connect(func() -> void:
		_refresh_reticle()
		Audio.set_paused(false))

	_pod.interacted_with.connect(_on_pod_used)
	_run.stasis_changed.connect(_on_stasis_changed)
	# Every pod starts sealed, the player's included — they are asleep inside it. It used to
	# swing open so it read as the one to use, back when the run began with the player stood
	# outside looking at it.
	for pod in get_tree().get_nodes_in_group(&"interactables"):
		if pod is StasisPod:
			(pod as StasisPod).set_door_open(false, true)
	# Before _wire_audio(), and that ordering is load-bearing: posing the player in the pod
	# marks it occupied, and the `entered` signal that fires from it is wired below to the
	# click of climbing in. Connect first and frame zero opens with a sound for an action the
	# player never took.
	_pose_in_pod()
	_wire_audio()
	_computer.bind(_run)
	_computer.opened.connect(_open_nav_screen)
	_nav_screen.closed.connect(_close_nav_screen)
	_run.run_ended.connect(_on_run_ended)
	_run_end.dismissed.connect(_on_run_end_dismissed)
	_hud.bind(_run)

	# The game starts itself the moment the scene loads: the intro video already gated the
	# launch, so a second "press START" screen in here was just a redundant click. On desktop
	# the mouse captures immediately. On web, pointer lock needs a user gesture — if the
	# intro played to the end there was none, so Godot defers the capture to the player's
	# first click, which is the graceful fallback rather than a wall.
	start_game()
	# After start_game(), because RunState.enter_stasis() refuses to do anything until the
	# run is actually running.
	_wake_from_opening_stasis()


## Every sound the run makes, in one place. Game already holds references to all of these
## and RunState already emits the events, so this is purely connections — none of the systems
## below had to learn that audio exists.
func _wire_audio() -> void:
	# The IMPACT is an event — a one-shot on the frame the fault fires. The KLAXON is not;
	# it belongs to the fault's whole lifetime and is driven from state below.
	_run.alarm.connect(func(malfunction: Malfunction, _patch_failure: bool) -> void:
		Audio.impact(malfunction.severity == Malfunction.Severity.CRITICAL)
		# ...and the computer says which system it was. Unlike the klaxon this DOES speak
		# into the sealed pod: the klaxon is a loop that would run for the whole of a stasis,
		# whereas one line telling you what broke is exactly the thing that should get you
		# out of bed. Which line is the fault's own data — see Malfunction.vo_line.
		if malfunction.vo_line != &"":
			Audio.say(malfunction.vo_line))
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
	# Climbing in gets a small CLICK, on the frame the player commits to the pod. It used to be
	# the "plug" cork pop, which was far too big for the moment and landed a full second before
	# the door moved, so getting in sounded like "pop ... and then the door closes".
	_pod.entered.connect(func() -> void: Audio.play_at(&"click", _pod.global_position, -3.0))
	# The pod's door gets its own sound. It is a curved panel driven round a cylinder and
	# sealed, not a door sliding in a frame, and it is the one you hear from the inside.
	_pod.door_moved.connect(_on_pod_door_moved)


## The pod door's sound. Opening LEADS with the cork pop, and the door's own sound follows a
## beat later — which is both what the request was ("a pop as soon as you exit") and what
## actually happens: the seal lets go, then the servo drives the panel.
##
## The pop cannot simply be played on top of the door sound, which is the obvious-looking
## version and the one that failed. pod_open is at ~0.84 amplitude within its first 10 ms and
## holds ~0.75 for 300 ms, and the cork's 150 Hz seat sits right inside the servo's 188-262 Hz
## range, so mixing them together masks the pop no matter how far POD_POP_DB is pushed. The
## lead is what makes it audible: it gives the cork's whole attack a clear window (plug_in
## decays 0.85 -> 0.12 in 60 ms) before the hiss starts.
func _on_pod_door_moved(opening: bool) -> void:
	if not opening:
		Audio.pod_door(false, _pod.global_position)
		return
	Audio.play_at(&"plug", _pod.global_position, POD_POP_DB)
	await get_tree().create_timer(POD_POP_LEAD).timeout
	# The run can end, or the scene be torn down, inside that gap.
	if not is_instance_valid(_pod):
		return
	Audio.pod_door(true, _pod.global_position)


## Music AND klaxon follow the ship's state, both from the same function so the alarm and the
## score can never disagree. Music priority, highest first:
##   STASIS      — sealed in the pod (klaatu_barada_nikto)
##   LOW_OXYGEN  — out of the pod and below the air warning (crash_landing): the death timer
##                 is the tensest state, so it wins even over a critical fault
##   PANIC       — a critical fault is active (red_alert)
##   NORMAL      — walking the ship, nothing wrong (lost_in_space)
## Called from stasis/systems signals AND from the oxygen handler, so crossing the air
## threshold switches the track. play_music() is idempotent, so re-calling is free.
func _update_ship_audio() -> void:
	if _run.finished:
		return
	var critical := false
	for malfunction in _run.malfunctions():
		if malfunction.is_critical():
			critical = true
			break

	# The cold open plays in silence — except for the klaxon, which is the whole point of it.
	# The run starts with the drive already broken, and the alarm coming through the shell is
	# how the player learns that before they can see anything: they are not waking up on
	# schedule, they are being woken. So the pod is deliberately left UNSEALED here, the one
	# time in the run it ever is.
	#
	# Guarded here rather than at the call sites because three separate signals (stasis,
	# systems, oxygen) reach this function while the player is still asleep, and any one of
	# them getting through would start the stasis track under the alarm. Explicitly NONE
	# rather than an early return: whatever the menu or the intro left playing has to be
	# faded out, not inherited.
	if _in_opening_stasis:
		Audio.play_music(Audio.Music.NONE)
		Audio.set_sealed(false)
		Audio.set_alarm(critical)
		return

	# Every other stasis, the shell does its job: the pod is sealed and nothing from the ship
	# reaches the player until they are out of it.
	Audio.set_sealed(_run.in_stasis)
	# The klaxon is about critical faults only, and never sounds inside the sealed pod.
	Audio.set_alarm(critical and not _run.in_stasis)

	if _run.in_stasis:
		Audio.play_music(Audio.Music.STASIS)
	elif _is_low_oxygen():
		Audio.play_music(Audio.Music.LOW_OXYGEN)
	elif critical:
		Audio.play_music(Audio.Music.PANIC)
	else:
		Audio.play_music(Audio.Music.NORMAL)


func _is_low_oxygen() -> bool:
	return not _run.in_stasis and _run.oxygen_warning > 0.0 \
		and _run.oxygen_remaining <= _run.oxygen_warning


## Breathing starts at the same threshold the HUD's vignette does, so the two escalate
## together rather than the player seeing red before they hear it.
func _on_oxygen_for_audio(remaining: float, _total: float) -> void:
	var warn: float = _run.oxygen_warning
	if warn <= 0.0 or remaining > warn or _run.in_stasis:
		Audio.set_breathing(0.0)
	else:
		Audio.set_breathing(1.0 - remaining / warn)
	# The computer calls the air ONCE, on the way down. Latched rather than compared against
	# the threshold every frame: oxygen_changed fires every frame of the run, and a line that
	# re-triggered would have the computer stuck repeating itself for the last minute of it.
	# Never re-armed — air only goes one way, so a second warning would be a bug, not a beat.
	if not _warned_low_air and warn > 0.0 and remaining <= warn:
		_warned_low_air = true
		Audio.say(&"oxygen_low")
	# Crossing the air threshold (either way) swaps the music to/from crash_landing.
	_update_ship_audio()


func start_game() -> void:
	if is_started:
		return
	is_started = true
	_refresh_reticle()
	# The HUD waits for the player to wake. Nothing on it is readable from inside a sealed pod
	# and the one panel that IS — "IN STASIS · [E] WAKE" — is the wrong first impression: the
	# game telling you about a mechanic before it has shown you a single thing.
	_hud.visible = not _in_opening_stasis
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
	_refresh_reticle()

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
	_refresh_reticle()
	_set_player_active(true)


func _on_pod_used(_interactable: Interactable) -> void:
	if not is_started or _run.finished or _pod_phase != PodPhase.OUT:
		return
	# Climbing in with a spare under your arm would otherwise teleport it across the ship.
	if _carry.is_holding():
		_carry.drop(false)
	_enter_pod()


func _on_stasis_changed(in_stasis: bool) -> void:
	# The first wake is also the end of the cold open, and this is the only place that catches
	# both ways out of it: the timer in _wake_from_opening_stasis() and the player's own [E],
	# which goes straight to RunState and never touches that function.
	#
	# _update_ship_audio() is called here rather than left to the stasis_changed handler
	# _wire_audio() also connects, which would only do the right thing while this handler
	# happens to be connected first. play_music() is idempotent, so the second call is free.
	if not in_stasis and _in_opening_stasis:
		_in_opening_stasis = false
		# The HUD hides its own stasis panel from this same signal. Which of the two handlers
		# runs first does not matter: signal emission is synchronous, so both have run before
		# anything is drawn and "IN STASIS" cannot flash up as the overlay arrives.
		_hud.visible = true
		_update_ship_audio()
		# The greeting waits until the player is actually STOOD in the room — see
		# _finish_exit(). Played here it would land under the cork pop and the door servo,
		# which is the one stretch of the run guaranteed to be noisy.
		_intro_line_pending = true

	# Only the WAKING half of the pod is driven from here. Entering is sequenced by
	# _enter_pod(), which has to finish moving the player before the clock starts running fast.
	if not in_stasis and _pod_phase == PodPhase.IN:
		_exit_pod()


## Pose the player asleep in the pod, sealed, before frame zero is drawn.
##
## The run opens mid-voyage — the whole premise is that the ship woke you — so starting the
## player stood in front of the pod put them one beat past their own story, looking at the
## thing they were supposed to have just climbed out of. This puts them where the fiction says
## they already are, and _wake_from_opening_stasis() plays the ordinary wake from there.
##
## Nothing here is intro-specific: it is exactly the state _enter_pod() leaves behind once the
## lid has shut, which is why the exit path needs no special case for the first one.
func _pose_in_pod() -> void:
	# The whole transform, not just the origin: snap_to_body() re-derives the camera's yaw from
	# the body basis, so setting the look direction here instead would simply be discarded.
	_player.global_transform = _pod.view_transform()
	# Without this the camera renders ONE frame at the world origin (down at floor level in
	# the middle of the ship) before snapping into place: it reads the anchor's INTERPOLATED
	# transform, which on the very first frame lerps from identity. Resetting the interpolation
	# makes frame zero use the real pose. It used to be masked by the START prompt covering
	# that frame; auto-starting exposed it.
	_player.reset_physics_interpolation()
	_camera.snap_to_body()
	_camera.input_enabled = false
	_set_player_active(false)
	_pod.set_occupied(true)
	_pod_phase = PodPhase.IN


## Bring the player out of that opening stasis after a beat. Deliberately on a timer rather
## than immediately: the pause is what sells it — the shell around you, the stasis readout
## winding up, and then the seal letting go. From there it is the same wake every other stasis
## gets, cork pop and ride out included, with no branch for the first one.
func _wake_from_opening_stasis() -> void:
	_run.enter_stasis()
	# A timer that PAUSES with the tree, unlike the pod's other two. The opening is exactly
	# when a player is most likely to be sat on the pause menu — still loading, or alt-tabbed
	# away — and waking them behind it would spend the one beat this exists for on a screen
	# they are not looking at.
	await get_tree().create_timer(OPENING_STASIS_TIME, false).timeout
	# The scene can be torn down inside that gap, and [E] wakes you early — the stasis panel
	# says so — in which case exit_stasis() is already a no-op. The phase check is what stops
	# a stale timer ejecting a player who has since climbed back in.
	if not is_inside_tree() or _pod_phase != PodPhase.IN:
		return
	_run.exit_stasis()


## Ride into the pod: freeze the player, fly the view in, shut the door, then start the
## fast-forward. The order matters — starting the clock first would have days ticking past
## while the player is still visibly walking in.
func _enter_pod() -> void:
	_pod_phase = PodPhase.ENTERING
	_set_player_active(false)
	_player.velocity = Vector3.ZERO
	_refresh_reticle()
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
	_refresh_reticle()
	if not _run.finished:
		_set_player_active(true)
	_camera.input_enabled = true
	# The computer greets you once you are on your feet, over the klaxon that woke you. Not
	# on a run that ended in the pod — there is nothing to welcome anyone to.
	if _intro_line_pending and not _run.finished:
		_intro_line_pending = false
		Audio.say(&"intro")


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


## The reticle is shown ONLY when the player is actually free to aim at something, and every
## caller re-derives it from state rather than setting `visible` directly. It used to be
## assigned true/false at each transition, and the pause/resume pair did it unconditionally —
## so unpausing inside the stasis pod (or at the nav console) put the dot and its interaction
## prompt back on screen over a view the player has no control of. Deriving it means a resume
## can only ever restore what the current state actually allows.
func _reticle_should_show() -> bool:
	return (
		is_started
		and not _run.finished
		and not _pause_menu.is_paused
		and _pod_phase == PodPhase.OUT
		and _nav_phase == NavPhase.AWAY
	)


func _refresh_reticle() -> void:
	_reticle.visible = _reticle_should_show()


func _on_run_ended(won: bool, summary: Dictionary) -> void:
	if _nav_phase == NavPhase.READING:
		_nav_screen.close()
	_refresh_reticle()
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
