extends SceneTree
# Regression test for "the reticle comes back after unpausing while in stasis".
#
# The reticle (aim dot + interaction prompt) is hidden whenever the player has no control:
# sealed in the stasis pod, leaning in to read the nav console, or paused. The pause/resume
# handlers used to set `visible` unconditionally, so unpausing put it back on screen over a
# view the player cannot aim in. The fix derives visibility from state via
# Game._reticle_should_show(); this asserts the derivation across every pause point. Run:
#   godot --headless --path . -s tests/smoke_reticle_pause.gd

const GAME_SCENE := "res://scenes/game.tscn"
const Opening := preload("res://tests/opening.gd")

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


## Pause, hold long enough for any deferred work to land, then unpause and settle.
func _pause_cycle(game) -> void:
	game._pause_menu.pause_game()
	for _i in 20:
		await process_frame
	_check("reticle hidden WHILE paused", not game._reticle.visible)
	game._pause_menu.resume()
	for _i in 20:
		await process_frame


func _run() -> void:
	var game = load(GAME_SCENE).instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await process_frame

	# The run opens with the player asleep in the pod, which is its own reticle-hidden case —
	# covered by smoke_opening_stasis. This suite is about pausing, so get to the state it is
	# actually about first.
	_check("the opening stasis lets go", await Opening.wake(self, game))

	# --- Baseline: free to walk around, so the reticle is up and a pause cycle restores it.
	_check("reticle visible during normal play", game._reticle.visible)
	await _pause_cycle(game)
	_check("reticle restored after unpausing in normal play", game._reticle.visible)

	# --- In the pod. Ride the whole entry sequence rather than forcing the phase, so the
	# test exercises the same path the player takes.
	game._on_pod_used(null)
	var entered := false
	for _i in 600:
		await process_frame
		if game._run.in_stasis and game._pod_phase == game.PodPhase.IN:
			entered = true
			break
	_check("player reached stasis", entered)
	_check("reticle hidden in stasis", not game._reticle.visible)

	await _pause_cycle(game)
	_check("reticle STILL hidden after unpausing in stasis", not game._reticle.visible)

	# Waking up hands control back, so it has to come back on its own.
	game._run.exit_stasis()
	for _i in 400:
		await process_frame
		if game._pod_phase == game.PodPhase.OUT:
			break
	_check("player left the pod", game._pod_phase == game.PodPhase.OUT)
	_check("reticle restored after leaving the pod", game._reticle.visible)

	# --- At the nav console: frozen in place reading, so the reticle is hidden there too.
	game._open_nav_screen()
	var reading := false
	for _i in 300:
		await process_frame
		if game._nav_phase == game.NavPhase.READING:
			reading = true
			break
	_check("player reached the nav screen", reading)
	_check("reticle hidden at the nav screen", not game._reticle.visible)

	await _pause_cycle(game)
	_check("reticle STILL hidden after unpausing at the nav screen", not game._reticle.visible)

	if _failures.is_empty():
		print("RETICLE PAUSE TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("RETICLE PAUSE TEST FAIL")
		quit(1)
