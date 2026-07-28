extends SceneTree
# Nothing carryable may leave the ship for ever.
#
# Two independent defences, tested separately because either one alone is a regression waiting
# to happen:
#   1. Carry refuses to unfreeze a body that is inside geometry (the CAUSE — see carry.gd's
#      drop(), and tests/diag_floor_escape.gd for the measurement behind it).
#   2. LostAndFound sweeps the `interactables` group and puts back anything under the deck (the
#      NET, for the causes we have not found).
#
# The stakes are not cosmetic: the run is balanced at thirteen spares against roughly
# forty-seven repairs, and the canisters ARE the oxygen. One lost under a doorway can make a run
# unwinnable with no feedback at all.
#
# Run: godot --headless --path . -s tests/smoke_lost_items.gd

const PROPS := [
	"res://scenes/props/canister.tscn",
	"res://scenes/props/spare_gear.tscn",
	"res://scenes/props/spare_screw.tscn",
	"res://scenes/props/hammer.tscn",
	"res://scenes/props/power_cell.tscn",
]

## Deep enough that every prop was measured falling through at this penetration.
const EMBED_DEPTH := 0.19

var _failures: Array[String] = []
var _game: Node


func _init() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		push_error("lost items test timed out")
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
	await _physics_frames(20)

	var net: LostAndFound = _game.get_node_or_null("LostAndFound")
	_check("the ship has a lost-and-found", net != null)
	if net == null:
		return _finish()

	await _test_the_net(net)
	await _test_carry_refuses_to_release_embedded(net)
	await _test_nothing_normal_is_disturbed(net)

	_finish()


## THE NET. Props put under the deck — where a depenetration ejection leaves them — come back.
func _test_the_net(net: LostAndFound) -> void:
	# Connected ONCE, collecting names rather than nodes. Per-iteration lambdas would each
	# capture a body this loop then frees, and a lambda holding a freed capture is an error at
	# every later emission — noise that buries whatever the suite is actually saying.
	var announced: Array[String] = []
	net.recovered.connect(func(item: Node3D, _f: Vector3, _t: Vector3) -> void:
		announced.append(String(item.name)))

	for path in PROPS:
		var body := _spawn(path, Vector3(0.5, -6.0, 8.0))
		var name := String(body.name)
		net.sweep()
		await _physics_frames(30)
		_check("%s under the deck is recovered (y %+.2f)"
			% [path.get_file(), body.global_position.y],
			body.global_position.y > -0.5)
		_check("...and %s says so, so the loss is findable in a log" % path.get_file(),
			name in announced)
		_check("%s comes back inside the ship (%s)"
			% [path.get_file(), _room(body.global_position)],
			_room(body.global_position) != "")
		body.queue_free()
		await _physics_frames(2)

	# Gone through near the HULL, over no room at all — the awkward case, which falls back to the
	# player rather than guessing a room.
	var stray := _spawn(PROPS[0], Vector3(-40.0, -6.0, 40.0))
	net.sweep()
	await _physics_frames(30)
	_check("one lost outside the hull comes back to the player (y %+.2f)"
		% stray.global_position.y, stray.global_position.y > -0.5)
	stray.queue_free()
	await _physics_frames(2)


## THE CAUSE. Carry must not hand physics a body that is inside the floor. Driven through the
## real grab/drop path, with the item forced into the slab while held — which is what the
## unswept rotation in _clamp_to_walls can do in a corner.
##
## THE NET IS SWITCHED OFF for this section, and that is the whole point of it. With the net
## running these props are rescued within a second whatever Carry does, so the section passed
## with the guard deliberately broken — it was testing the backstop twice and the cause not at
## all. Two defences are only two defences if each is proved on its own.
func _test_carry_refuses_to_release_embedded(net: LostAndFound) -> void:
	var carry: Carry = _game.get_node("Player/Carry")
	net.process_mode = Node.PROCESS_MODE_DISABLED
	for path in PROPS:
		var body := _spawn(path, Vector3(2.5, 0.5, 8.0))
		await _physics_frames(20)
		var interactable := body as Node3D as Interactable
		_check("%s can be picked up" % path.get_file(), carry.grab(interactable))
		await _frames(4)
		# Force it into the deck behind Carry's back, then release.
		body.global_position = Vector3(2.5, -EMBED_DEPTH, 8.0)
		carry.drop(false)
		await _physics_frames(120)
		_check("%s released inside the floor does not fall through (y %+.2f)"
			% [path.get_file(), body.global_position.y], body.global_position.y > -0.5)
		body.queue_free()
		await _physics_frames(2)
	net.process_mode = Node.PROCESS_MODE_INHERIT


## ...and the net must not be a thing that shuffles the ship around. Everything the run spawned
## should be exactly where it was after a sweep.
func _test_nothing_normal_is_disturbed(net: LostAndFound) -> void:
	var supplies: ShipSupplies = _game.get_node("Supplies")
	var before := {}
	for supply in supplies.canisters():
		before[supply] = (supply as Node3D).global_position
	for spare in supplies.spares():
		before[spare] = spare.global_position
	_check("there is something to leave alone (%d)" % before.size(), before.size() > 5)

	var rescues := net.rescues()
	net.sweep()
	await _physics_frames(4)
	_check("a sweep over a healthy ship recovers nothing", net.rescues() == rescues)
	var moved := 0
	for item in before:
		if (item as Node3D).global_position.distance_to(before[item]) > 0.01:
			moved += 1
	_check("and moves nothing (%d moved)" % moved, moved == 0)


func _room(at: Vector3) -> String:
	return (_game.get_node("Ship") as RoomBuilder).room_at(at)


func _spawn(path: String, at: Vector3) -> RigidBody3D:
	var node: Node = load(path).instantiate()
	_game.add_child(node)
	var body := _first_body(node)
	body.global_position = at
	return body


func _first_body(node: Node) -> RigidBody3D:
	if node is RigidBody3D:
		return node
	for child in node.get_children():
		var found := _first_body(child)
		if found != null:
			return found
	return null


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _physics_frames(n: int) -> void:
	for i in n:
		await physics_frame


func _finish() -> void:
	if _failures.is_empty():
		print("LOST ITEMS TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("LOST ITEMS TEST FAIL")
		quit(1)
