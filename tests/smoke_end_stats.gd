extends SceneTree
# Every figure on the end screen, against a run whose numbers are KNOWN.
#
# `smoke_run_end` covers that the screen appears and the button works. It asserts nothing about
# the numbers, which is how four of the six came to be wrong at once — the distance was reported
# in kilometres after dividing millions of miles by a thousand, and "air spent" printed the same
# value for every run that ended in suffocation.
#
# Both endings are the same screen (RunEnd.show_result branches on `won` for the title and one
# subtitle line), so everything here is checked in BOTH states.
#
# Run: godot --headless --path . -s tests/smoke_end_stats.gd

const Opening := preload("res://tests/opening.gd")

var _failures: Array[String] = []
var _game: Node


func _init() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		push_error("end stats test timed out")
		quit(1))
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _run() -> void:
	_game = load("res://scenes/game.tscn").instantiate()
	root.add_child(_game)
	current_scene = _game
	await process_frame
	_check("the opening stasis lets go", await Opening.wake(self, _game))
	await _frames(4)

	var run: RunState = _game.get_node("Run")
	var screen = _game.get_node("RunEnd")

	await _test_the_numbers(run, screen)
	await _test_air_is_accumulated(run)
	await _test_the_two_lists(run, screen)
	await _test_the_button_survives_a_long_run(screen)
	await _test_a_restart_forgets_the_last_run(run)

	_finish()


## Distance in the unit the player has been reading all run, and the tallies straight through.
func _test_the_numbers(run: RunState, screen) -> void:
	run.distance_remaining = run.total_distance * 0.25   # three quarters of the way
	run.days_elapsed = 12.5
	run.air_breathed = 185.0
	run.canisters_used = 3
	run.repairs_permanent = 4
	run.repairs_patched = 2
	run.patch_failures = 1

	for won in [false, true]:
		screen.show_result(won, run.summary())
		await _frames(2)
		var stats := _stats(screen)
		var covered: float = run.total_distance * 0.75

		# THE BUG THAT STARTED THIS. 82 million miles divided by 1000 and called km reported
		# "0.1 km of 0.1 km" for an entire crossing.
		_check("[won=%s] distance is in million miles, not km (%s)" % [won, stats.get("Distance covered", "")],
			stats.get("Distance covered", "").contains("million miles"))
		_check("[won=%s] ...and it is the real figure (%s, want %.1f)"
			% [won, stats.get("Distance covered", ""), covered],
			stats.get("Distance covered", "").begins_with("%.1f" % covered))
		_check("[won=%s] the days survived are shown (%s)" % [won, stats.get("Time survived", "")],
			stats.get("Time survived", "").begins_with("12.5"))
		# 185s = 3:05, and with NO denominator: there is no honest total once canisters exist.
		_check("[won=%s] air breathed reads as a clock (%s)" % [won, stats.get("Air breathed", "")],
			stats.get("Air breathed", "") == "3:05")
		_check("[won=%s] ...and carries no 'of Y' (%s)" % [won, stats.get("Air breathed", "")],
			not stats.get("Air breathed", "").contains(" of "))
		_check("[won=%s] canisters used (%s)" % [won, stats.get("Canisters used", "")],
			stats.get("Canisters used", "") == "3")
		_check("[won=%s] permanent repairs (%s)" % [won, stats.get("Permanent repairs", "")],
			stats.get("Permanent repairs", "") == "4")
		_check("[won=%s] patches and failures (%s)" % [won, stats.get("Patches", "")],
			stats.get("Patches", "").begins_with("2") and stats.get("Patches", "").contains("1"))


## Air is a RUNNING TOTAL, not the tank's deficit. The old figure was
## `oxygen_total - oxygen_remaining`, which every suffocation death drove to exactly
## `oxygen_total` — the same number for every run that ever ended that way.
func _test_air_is_accumulated(run: RunState) -> void:
	run.air_breathed = 0.0
	run.oxygen_remaining = run.oxygen_total
	await _frames(20)
	var breathed_before := run.air_breathed
	_check("air breathed climbs as the run runs (%.2f)" % breathed_before, breathed_before > 0.0)

	# Refill the tank the way a canister does. The deficit goes back to zero; the total must not.
	run.oxygen_remaining = run.oxygen_total
	await _frames(20)
	_check("...and a refill does not undo it (%.2f -> %.2f)" % [breathed_before, run.air_breathed],
		run.air_breathed > breathed_before)
	_check("...which the old deficit arithmetic would have reported as nearly nothing (%.2f)"
		% (run.oxygen_total - run.oxygen_remaining),
		run.air_breathed > (run.oxygen_total - run.oxygen_remaining))


## Two lists, and repeats folded together.
func _test_the_two_lists(run: RunState, screen) -> void:
	run.choices.clear()
	run.events.clear()
	for i in 4:
		run.choices.append("Patched DRIVE COUPLER (temporary)")
	run.choices.append("Repaired COOLANT LOOP properly")
	run.events.append("Your patch on DRIVE COUPLER gave out")

	screen.show_result(false, run.summary())
	await _frames(2)
	var lines := _lines(screen)
	var joined := "\n".join(lines)

	_check("the summary is split into what you did and what went wrong",
		joined.contains("What you did") and joined.contains("What went wrong"))
	# FOUR identical patches become one line with a count. A crossing throws about forty
	# repairs across the same handful of systems, so this is what takes the list from
	# unreadable to a story.
	_check("repeats are collapsed with a count (%s)" % joined.replace("\n", " | "),
		joined.contains("Patched DRIVE COUPLER (temporary)  x4"))
	_check("...and a one-off carries no count",
		joined.contains("Repaired COOLANT LOOP properly") and not joined.contains("properly  x"))

	# A clean run must not be told what went wrong under an empty heading.
	run.events.clear()
	screen.show_result(true, run.summary())
	await _frames(2)
	_check("a flawless run gets no 'what went wrong' heading",
		not "\n".join(_lines(screen)).contains("What went wrong"))


## THE REGRESSION THAT MATTERS. A long run used to grow the layout past the bottom of the screen
## and take the Continue button with it — and the button is the only way out.
func _test_the_button_survives_a_long_run(screen) -> void:
	var summary := {
		"distance_covered": 40.0, "total_distance": 82.0, "air_breathed": 300.0,
		"canisters_used": 6, "days_elapsed": 20.0, "repairs_permanent": 9,
		"repairs_patched": 9, "patch_failures": 4, "choices": [], "events": [],
	}
	# Deliberately all DIFFERENT, so collapsing cannot save it and the scroller is what is
	# under test.
	var many: Array[String] = []
	for i in 60:
		many.append("Repaired SYSTEM %d properly" % i)
	summary["choices"] = many
	screen.show_result(false, summary)
	await _frames(4)

	var button: Button = screen._button
	var viewport := root.get_visible_rect()
	var rect := button.get_global_rect()
	_check("60 entries leave the Continue button on screen (button %s, viewport %s)"
		% [rect, viewport.size],
		rect.position.y >= 0.0 and rect.end.y <= viewport.size.y)
	_check("...and it can still take focus", button.focus_mode != Control.FOCUS_NONE)


## start() used to clear the clocks but not the tallies, so a second run in the same scene
## opened with the first run's list already in it.
func _test_a_restart_forgets_the_last_run(run: RunState) -> void:
	run.choices.append("Repaired SOMETHING properly")
	run.events.append("Your patch on SOMETHING gave out")
	run.repairs_permanent = 7
	run.canisters_used = 5
	run.air_breathed = 99.0

	run.running = false
	run.start()
	await _frames(2)
	var summary := run.summary()
	_check("a restarted run has no choices from the last one (%d)" % summary["choices"].size(),
		summary["choices"].is_empty())
	_check("...nor events (%d)" % summary["events"].size(), summary["events"].is_empty())
	_check("...nor repair tallies (%d)" % int(summary["repairs_permanent"]),
		int(summary["repairs_permanent"]) == 0)
	_check("...nor canisters (%d)" % int(summary["canisters_used"]),
		int(summary["canisters_used"]) == 0)
	_check("...nor air breathed (%.2f)" % float(summary["air_breathed"]),
		float(summary["air_breathed"]) < 1.0)


## The stats grid, read back as {label: value}. It is two columns of Labels.
func _stats(screen) -> Dictionary:
	var out := {}
	var children: Array = screen._stats.get_children()
	var i := 0
	while i + 1 < children.size():
		out[(children[i] as Label).text] = (children[i + 1] as Label).text
		i += 2
	return out


func _lines(screen) -> Array[String]:
	var out: Array[String] = []
	for child in screen._choices.get_children():
		if child is Label:
			out.append((child as Label).text)
	return out


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _finish() -> void:
	if _failures.is_empty():
		print("END STATS TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("END STATS TEST FAIL")
		quit(1)
