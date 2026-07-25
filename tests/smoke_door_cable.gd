extends SceneTree
# Step 14d playtest fix: a sliding door must not guillotine a cable running through it.
# Running power between rooms drapes a cable through a doorway; the door used to close the instant
# the player left, severing the line (or popping the plug via breakaway). Now a door stays open
# while a cable's polyline crosses its opening, and closes once the line is clear. Opening stays
# player-only — a cable near a CLOSED door must never make it yawn open. The rope is not a physics
# body, so the door finds cables via the "cables" group and tests their public `points`.
# Run: godot --headless --path . -s tests/smoke_door_cable.gd

var _failures: Array[String] = []


func _init() -> void:
	create_timer(20.0).timeout.connect(func() -> void:
		push_error("door cable test timed out")
		quit(1))
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _run() -> void:
	# A door at the origin spanning X (opening runs along X, wall plane is Z). With width 1.8, tile
	# 2.0, height 2.2: opening box is x in [-1.8, 1.8], y in [~0, 2.2], z in [-0.25, 0.25] (the depth
	# widened from the thin panel so a crossing rope point always lands inside).
	var door := SlidingDoor.new()
	root.add_child(door)
	var doorway := Doorway.new(Vector2.ZERO, Doorway.Axis.X, 1.8)
	door.build(doorway, 2.2, 0.1, 2.0, StandardMaterial3D.new(), 1.6)

	var cable := Cable3D.new()
	root.add_child(cable)

	var player := Node3D.new()
	player.add_to_group(&"player")
	root.add_child(player)

	await process_frame  # let _ready run (cable joins the "cables" group)

	# --- Obstruction geometry (points set by hand; no physics frames re-simulate them) ----------
	cable.points = PackedVector3Array([Vector3(0, 1.1, -1), Vector3(0, 1.1, 0), Vector3(0, 1.1, 1)])
	_check("a cable crossing the opening is detected", door._is_obstructed())

	cable.points = PackedVector3Array([Vector3(0, 1.1, 3), Vector3(0, 1.1, 4)])
	_check("a cable clear of the opening is not detected", not door._is_obstructed())

	cable.points = PackedVector3Array([Vector3(1.79, 1.1, 0.24)])
	_check("a rope point just inside the box counts", door._is_obstructed())
	cable.points = PackedVector3Array([Vector3(0, 1.1, 0.26)])
	_check("a rope point just past the depth is clear", not door._is_obstructed())

	# --- A cable in the doorway defers the close, then it closes once clear ----------------------
	cable.points = PackedVector3Array([Vector3(0, 1.1, 0)])  # spanning the opening
	door._on_body_entered(player)
	_check("the player opens the door", door.is_open)
	door._on_body_exited(player)
	_check("a cable in the doorway keeps the door open when the player leaves", door.is_open)

	cable.points = PackedVector3Array([Vector3(0, 1.1, 5)])  # line dragged clear
	door._physics_process(0.11)  # one recheck past RECHECK_INTERVAL
	_check("the door closes once the cable clears", not door.is_open)

	# --- Regression: with the opening clear, a normal exit closes immediately --------------------
	door._on_body_entered(player)
	_check("the door re-opens for the player", door.is_open)
	door._on_body_exited(player)
	_check("with the opening clear, leaving closes the door as before", not door.is_open)

	if _failures.is_empty():
		print("DOOR CABLE TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("DOOR CABLE TEST FAIL")
		quit(1)
