class_name VendingStock
extends Node3D

# What is actually sitting in the vending machine: a cake, a can and a plant, in the nine
# pigeonholes you can see through the glass. Take something and one of them is gone; load a
# crate in and three more appear.
#
# A VIEW OVER THE SILO, NOT A SECOND COPY OF IT. The `Silo` remains the only thing that knows
# how full the machine is — the HUD reads it, the hunger need is cleared by it, and the
# interaction prompt counts from it. This watches `level_changed` and reconciles the grid to
# match, which is where the randomness lives: WHICH pigeonhole empties is arbitrary, and the
# machine is the only place in the game where that is true. Two stores of the same number would
# eventually disagree, and the one the player can see is the one that would be wrong.
#
# So `use()` on the silo does not have to know this exists, and a test that drives the silo
# directly still gets a correct-looking machine.
#
# THE HOLES ARE READ FROM THE MODEL, not laid out on a computed grid. CD_VendingMachine_v1
# carries nine empties named slot1..slot9, and they are not a perfect lattice — the rows sit at
# y 2.54, 1.57 and 0.38 with a few millimetres of wobble across each one. A grid computed here
# would be subtly wrong everywhere and would need re-deriving every time the model is redrawn.
#
# ITEM TYPES ROTATE rather than being random. The counter means the first three loaded are one
# cake, one can and one plant, and a machine filled to all nine holds three of each — which is
# both what was asked for and tidier than nine random draws that happen to be all cake.

## The three things the machine sells. `height` is the target in METRES and `units` is how tall
## the model is in its own space, so the scale works out whatever the machine is dressed at.
## Every one of these has its origin at its base, so an item stands on the floor of its hole.
##
## `yaw` turns the item to face out through the glass. The pigeonhole empties carry no rotation
## of their own, so an item lands in the machine's own frame — and these are authored presenting
## their front along X, which puts it against the side wall of the hole. It only really shows on
## the cake, whose slice is three units deep and one wide: unturned, you see the icing edge-on.
const ITEMS := [
	{"path": "res://3D-Models/CD_Cake_v1.blend", "height": 0.26, "units": 2.48, "yaw": 90.0},
	{"path": "res://3D-Models/CD_Can_v1.blend", "height": 0.30, "units": 4.00, "yaw": 90.0},
	{"path": "res://3D-Models/CD_Plant_v1.blend", "height": 0.28, "units": 2.05, "yaw": 90.0},
]

## Names the model uses for its pigeonholes, in the order they are indexed here.
const SLOT_PREFIX := "slot"

## Emitted when the displayed contents change, carrying how many are left.
signal stock_changed(occupied: int)

## 0 randomises. Set it in a test to make which-hole-empties repeatable.
@export var rng_seed: int = 0

## The `slotN` nodes found in the model, in name order.
var _holes: Array[Node3D] = []
## hole index -> the item node standing in it, or null.
var _items: Array = []
## hole index -> which of ITEMS it holds, or -1.
var _kinds: Array[int] = []
var _next_kind: int = 0
var _rng := RandomNumberGenerator.new()
var _silo: Silo = null


func _ready() -> void:
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()


## Point it at the machine whose level it is showing and at the model holding the pigeonholes,
## then match the grid to that level.
##
## `model` is the decor node in the scene. The items become children of its `slotN` empties, so
## they inherit its placement and scale and cannot drift from it — nothing is written to the
## scene file by that, only to the running tree.
func bind(silo: Silo, model: Node) -> void:
	_silo = silo
	_holes = _find_holes(model)
	_items.resize(_holes.size())
	_kinds.resize(_holes.size())
	_kinds.fill(-1)
	if _holes.is_empty():
		push_warning("VendingStock: %s has no %sN nodes to put anything in"
			% [model.name if model != null else "<null>", SLOT_PREFIX])
	if not silo.level_changed.is_connected(_on_level_changed):
		silo.level_changed.connect(_on_level_changed)
	_reconcile()


## Take everything back out. The items are parented to the MODEL's empties rather than to this
## node, so freeing the stock on its own would leave nine of them standing in an empty machine.
func clear() -> void:
	for i in _items.size():
		_empty_hole(i)
	_silo = null
	queue_free()


func slot_count() -> int:
	return _holes.size()


func occupied() -> int:
	var n := 0
	for item in _items:
		if item != null:
			n += 1
	return n


## Which item is in each hole, -1 for empty. For tests, and for anything that later wants to
## know the machine is not showing nine of the same thing.
func contents() -> Array[int]:
	return _kinds.duplicate()


## slot1, slot2, ... in name order, however they are arranged in the model's tree.
func _find_holes(model: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if model == null:
		return out
	var index := 1
	while true:
		var hole := model.get_node_or_null(NodePath("%s%d" % [SLOT_PREFIX, index])) as Node3D
		if hole == null:
			break
		out.append(hole)
		index += 1
	return out


func _on_level_changed(_silo_ref: Silo, _level: float) -> void:
	_reconcile()


## Bring the grid to the number of items the silo says it holds, filling or emptying random
## holes. ROUNDED rather than floored: the level is a fraction of nine and floating point will
## not land on ninths exactly, so flooring loses an item roughly a third of the time.
func _reconcile() -> void:
	if _silo == null or _holes.is_empty():
		return
	var want := clampi(int(round(_silo.level * float(slot_count()))), 0, slot_count())
	var changed := false
	while occupied() > want:
		_empty_hole(_random_hole(true))
		changed = true
	while occupied() < want:
		_fill_hole(_random_hole(false))
		changed = true
	if changed:
		stock_changed.emit(occupied())


## A random occupied hole (`filled`) or a random empty one, or -1 if there are none.
func _random_hole(filled: bool) -> int:
	var candidates: Array[int] = []
	for i in slot_count():
		if (_items[i] != null) == filled:
			candidates.append(i)
	if candidates.is_empty():
		return -1
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _empty_hole(index: int) -> void:
	if index < 0:
		return
	var node: Node3D = _items[index]
	if node != null and is_instance_valid(node):
		node.queue_free()
	_items[index] = null
	_kinds[index] = -1


func _fill_hole(index: int) -> void:
	if index < 0:
		return
	var kind := _next_kind % ITEMS.size()
	_next_kind += 1
	var item: Dictionary = ITEMS[kind]
	var scene: PackedScene = load(item["path"])
	var node: Node3D = scene.instantiate()
	var hole := _holes[index]
	hole.add_child(node)
	# AFTER add_child, and divided by the hole's own scale: the empties are inside the machine,
	# which the mess dresses at 0.6, so a scale set in model space would come out 40% short.
	# This asks for a height in metres and gets one.
	var host_scale: float = maxf(hole.global_transform.basis.get_scale().y, 0.0001)
	var want_height: float = float(item["height"]) / float(item["units"])
	node.scale = Vector3.ONE * (want_height / host_scale)
	node.rotation = Vector3(0.0, deg_to_rad(float(item.get("yaw", 0.0))), 0.0)
	node.position = Vector3.ZERO
	_items[index] = node
	_kinds[index] = kind
