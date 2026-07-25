extends SceneTree
# Step 14d (Phase 4): placement + permanently-seated ends.
# Part A drives the reusable power_cable.tscn in isolation:
#   * the FixedPlug starts seated in the source socket, powers the cable, is frozen, and is NOT a
#     ray target (is_enabled false),
#   * the FreePlug is loose, grabbable, and falls under gravity,
#   * a bolted-in end never pops — overstretching the cable can't force_unseat the fixed plug.
# Part B checks the in-ship instance in game.tscn is wired and the player carries cable_ignore.
# Run: godot --headless --path . -s tests/smoke_cable_placement.gd

const GAME_SCENE := "res://scenes/game.tscn"
const CABLE_SCENE := "res://scenes/props/power_cable.tscn"

var _failures: Array[String] = []


func _init() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("cable placement test timed out")
		quit(1))
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures.append(label)


func _physics_frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	# --- Part A: the packaged cable in isolation ------------------------------------------
	var world := Node3D.new()
	root.add_child(world)
	# A floor so the free plug has something to land on.
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(40, 1, 40)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	floor_body.global_position = Vector3(0, -0.5, 0)

	var rig: Node3D = load(CABLE_SCENE).instantiate()
	world.add_child(rig)
	rig.global_position = Vector3(0, 1.3, 0)  # socket at chest height, like a wall mount
	# The rig has no player; give the cable something to exclude so refresh_exclusions is happy.
	await _physics_frames(10)  # _seat_fixed is deferred; let it and the drape settle

	var fixed_plug := rig.get_node("FixedPlug")
	var free_plug := rig.get_node("FreePlug")
	var socket := rig.get_node("SourceSocket") as CableSocket
	var cable := rig.get_node("Cable") as Cable3D
	var cfixed := fixed_plug as CablePlug
	var cfree := free_plug as CablePlug
	var body_fixed := fixed_plug as RigidBody3D

	_check("the fixed plug seated into the source socket", cfixed.is_seated())
	_check("the source socket is occupied by the fixed plug", socket.occupied_by == fixed_plug)
	_check("the cable records the source on end A", cable.socket_a == socket)
	_check("a source-seated cable is powered", cable.powered)
	_check("the fixed plug is frozen", body_fixed.freeze)
	_check("the fixed plug is NOT a ray target", not cfixed.is_enabled)

	_check("the free plug is loose (not seated)", not cfree.is_seated())
	_check("the free plug is grabbable", cfree.is_enabled)
	# It should have fallen from its spawn toward the floor.
	var free_y_start := (free_plug as Node3D).global_position.y
	await _physics_frames(60)
	var free_y_now := (free_plug as Node3D).global_position.y
	_check("the free plug fell under gravity (%.2f -> %.2f)" % [free_y_start, free_y_now],
		free_y_now < free_y_start - 0.3)

	# --- A bolted-in end never pops -------------------------------------------------------
	# Pin the free end far away so the rope is massively overstretched, then hold it there long
	# enough for the breakaway timer to fire. The only seated end is the fixed one, so the cable
	# will try to pop IT — and must fail.
	(free_plug as RigidBody3D).freeze = true
	(free_plug as Node3D).global_position = Vector3(0, 1.3, 8.0)  # 8 m from the 4 m rope
	await _physics_frames(60)  # warm-up + several breakaway windows
	_check("overstretch cannot pop the bolted-in end", cfixed.is_seated())
	_check("the source is still on end A after the yank", cable.socket_a == socket)
	_check("the bolted-in cable stays powered", cable.powered)

	world.queue_free()
	await _physics_frames(2)

	# --- Part B: the in-ship instance is wired -------------------------------------------
	var game: Node3D = load(GAME_SCENE).instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.start_game()
	await _physics_frames(20)

	var player := game.get_node("Player")
	_check("the player carries the cable_ignore group", player.is_in_group(&"cable_ignore"))

	var ship_cable := game.get_node_or_null("PowerCable")
	_check("game.tscn contains a PowerCable", ship_cable != null)
	if ship_cable != null:
		var ship_fixed := ship_cable.get_node("FixedPlug") as CablePlug
		var ship_cab := ship_cable.get_node("Cable") as Cable3D
		_check("the ship cable's fixed end is seated", ship_fixed.is_seated())
		_check("the ship cable is powered from its source", ship_cab.powered)

	if _failures.is_empty():
		print("CABLE PLACEMENT TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("CABLE PLACEMENT TEST FAIL")
		quit(1)
