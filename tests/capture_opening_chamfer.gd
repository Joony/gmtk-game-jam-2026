extends SceneTree
# Visual check for the 45° corners on the ship's openings — windows and doorways. Headless
# assertions prove the prisms are the right size and in the right place; only a screenshot can
# answer the question the feature is actually about — can you SEE the chamfer? Under the ship's
# shadowless lighting an untinted 45° face renders as flat wall, so "geometrically correct" and
# "visible" are genuinely different claims.
#
# Run WITHOUT --headless:
#   godot --path . --resolution 1280x720 -s tests/capture_opening_chamfer.gd -- <out_dir> [off]
#
# The optional `off` rebuilds the ship with opening_chamfer = 0 and writes the same views with an
# `_off` suffix, so the before/after pair can be diffed rather than remembered.

var _dir: String = "user://"

## name, the opening's grid position, how far back to stand, and what to aim at:
## "centre" frames the whole opening, "corner" pulls in on the top corner nearest the camera.
const VIEWS := [
	["bathroom_porthole", Vector2(-9, -8.5), 1.7, "centre"],
	["corridor", Vector2(-11, -16), 2.2, "centre"],
	["bridge_forward", Vector2(0.5, -21), 4.0, "centre"],
	["bridge_corner", Vector2(0.5, -21), 1.2, "corner"],
	# The two widest openings on the ship fill the frame edge-to-edge from any sane standing
	# distance, so the only useful shot of them is a corner.
	["cryo_aft_corner", Vector2(0.5, 15), 1.5, "corner"],
	# The cryo bay's one door, shut and open. A doorway has to work BOTH ways: closed, the
	# chamfers frame a rectangular panel; open, they frame the room beyond.
	["door_closed", Vector2(0.5, -4), 3.2, "centre"],
	["door_open", Vector2(0.5, -4), 3.2, "centre-open"],
]


func _init() -> void:
	_go.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_dir = args[0]
	var chamfer_off := args.size() > 1 and args[1] == "off"

	# CameraController takes its POSITION from the body's `get_global_transform_interpolated()`,
	# so teleporting the player between views makes the eye GLIDE to the new spot over many
	# frames instead of arriving. Two shots came back mid-glide, pointing across the room at the
	# wrong wall — and looked plausible enough to be mistaken for a geometry bug. Stills gain
	# nothing from smoothing, so it is off for the whole capture.
	physics_interpolation = false

	var game: Node3D = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await _frames(2)
	game.start_game()
	await _frames(30)

	var ship: RoomBuilder = game.get_node("Ship")
	if chamfer_off:
		ship.opening_chamfer = 0.0
		ship.build()
		await _frames(5)

	var player: CharacterBody3D = game.get_node("Player")
	var controller: CameraController = player.find_children("*", "CameraController", true, false)[0]
	var camera: Camera3D = controller.find_children("*", "Camera3D", true, false)[0]

	# NORMAL light. The run opens on a broken drive, so everything is red otherwise — which is
	# exactly the tint this shot is trying to judge.
	var lighting: LightingController = game.get_node("Lighting")
	lighting.transition_time = 0.0
	lighting.set_mode(LightingController.Mode.NORMAL)

	for view in VIEWS:
		var opening := _find_opening(ship, view[1])
		if opening == null:
			push_error("no opening at %s" % view[1])
			continue
		await _shoot(ship, player, controller, camera, opening, view[0], view[2], view[3], chamfer_off)

	quit(0)


func _find_opening(ship: RoomBuilder, at: Vector2) -> Doorway:
	for opening in ship.doorways:
		if opening.position.distance_to(at) < 0.01:
			return opening
	return null


## By position, not by name: node names are sanitised on add (dots stripped), so "Door_door_0.5_-4"
## is not what a door ends up called.
func _door_at(ship: RoomBuilder, world: Vector2) -> SlidingDoor:
	for node in ship.get_tree().get_nodes_in_group(RoomBuilder.GROUP_DOOR):
		var door := node as SlidingDoor
		if door != null and Vector2(door.global_position.x, door.global_position.z).distance_to(world) < 0.1:
			return door
	return null


func _shoot(
	ship: RoomBuilder,
	player: CharacterBody3D,
	controller: CameraController,
	camera: Camera3D,
	opening: Doorway,
	view_name: String,
	distance: float,
	aim: String,
	chamfer_off: bool
) -> void:
	var wall := ship.grid_to_world(opening.position.x, opening.position.y)
	var top: float = opening.resolved_top(ship.doorway_height)
	var spans_x := opening.axis == Doorway.Axis.X
	# Which side of the wall is inside the ship? Probe both — the room the window belongs to is
	# the one room_at() can name. Guessing the normal from the layout would be a second copy of
	# knowledge the builder already has.
	var normal := Vector3.BACK if spans_x else Vector3.RIGHT
	var probe := Vector3(wall.x, 1.0, wall.y) + normal
	if ship.room_at(probe) == "":
		normal = -normal

	if aim == "centre-open":
		# Forced open rather than shot from inside the door's proximity trigger: `door_approach`
		# is 1.6m, and from that close a 1.8m doorway overflows the frame. _physics_process is
		# switched off too, or the door would notice nobody is standing in it and shut again.
		var door := _door_at(ship, wall)
		if door == null:
			push_error("no door at %v" % wall)
			return
		door.set_physics_process(false)
		door.open()
		await _frames(40)

	var half_span: float = opening.width * 0.5 * ship.tile_size
	var target := Vector3(wall.x, (opening.sill + top) * 0.5, wall.y)
	var stand := target + normal * distance
	if aim == "corner":
		# The top corner nearest the near end of the opening, pulled in close enough that the
		# 45° face is several dozen pixels across.
		var along := Vector3.RIGHT if spans_x else Vector3.BACK
		target = Vector3(wall.x, top, wall.y) - along * half_span
		stand = target + normal * distance + along * (half_span * 0.25) - Vector3.UP * 0.6

	# Pinned every frame, not set once, and then CHECKED. A big jump between views does not land
	# immediately, and a shot taken mid-flight looks perfectly plausible — it is just aimed across
	# the room at the wrong wall, which is indistinguishable from a geometry bug until you measure
	# it. So: hold the mark until the eye is actually over it, and refuse to save if it never gets
	# there rather than writing a lie.
	const SETTLE_MAX := 240
	const ON_MARK := 0.05
	var at := Vector3(stand.x, 0.95, stand.z)
	var mark := Vector2(at.x, at.z)
	var settled := 0
	for i in SETTLE_MAX:
		player.global_position = at
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
		# Aim from where the eye ACTUALLY ends up, not from the player's feet — the camera sits on
		# a pivot above the body, so a direction computed from `stand` misses high by ~0.75m.
		var dir := (target - camera.global_position).normalized()
		# Yaw 0 looks down -Z and positive yaw turns to port (-X); see CameraController.set_look.
		controller.set_look(atan2(-dir.x, -dir.z), asin(clampf(dir.y, -1.0, 1.0)))
		await process_frame
		var eye := camera.global_position
		# A few frames ON the mark, not just one — the aim is recomputed from the eye, so it needs
		# a moment to stop chasing itself once the eye stops moving.
		settled = settled + 1 if Vector2(eye.x, eye.z).distance_to(mark) < ON_MARK else 0
		if settled >= 8:
			break
	if settled < 8:
		push_error(
			"%s: the camera never reached its mark (eye %v, wanted %v) — not saving"
			% [view_name, camera.global_position, at]
		)
		return
	await RenderingServer.frame_post_draw

	var path := "%s/chamfer_%s%s.png" % [_dir, view_name, "_off" if chamfer_off else ""]
	if root.get_texture().get_image().save_png(path) != OK:
		push_error("save_png failed for %s" % path)
	else:
		# The pose, not just the filename: a shot that comes back looking at the wrong wall is
		# otherwise a guessing game about whether the camera or the aim was wrong.
		print("saved %s  eye %v  fwd %v  target %v" % [
			path, camera.global_position, -camera.global_transform.basis.z, target
		])
