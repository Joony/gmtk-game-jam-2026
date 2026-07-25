class_name ShipSupplies
extends Node3D

# Where the ship's supplies physically are: the silos you service, and the canisters you fetch
# to service them with. The counterpart to ship_layout.gd, which declares the rooms.
#
# WHY THIS EXISTS AS A SCRIPT AND NOT AS NODES IN game.tscn. Partly the scene lock — it is
# being edited elsewhere and must not be touched — but mostly the same reason the ship itself
# is built in code: a supply layout is a table you want to read down and rebalance in one
# place, not sixty transforms scattered through a scene file.
#
# TWO WAYS A THING BECOMES REAL, and the difference is whether it moves.
#
#   ADOPT   A silo is fixed furniture and is ALREADY IN THE SCENE as decor. So rather than
#           spawning a second one on top of it, this reads the decor node's position and puts
#           a functional Silo body there. Nothing is duplicated and nothing looks different —
#           the prop the player can see simply becomes the prop the player can use.
#   SPAWN   A canister has to be picked up, and a decor Node3D cannot become a RigidBody3D.
#           So loose supplies are spawned fresh at declared positions.
#
# Positions for adopted silos are READ OFF THE DECOR NODE rather than copied into the table
# below, so the two cannot drift apart when someone nudges a prop. If the path stops resolving
# that is a warning, not a silent hole: smoke_supplies asserts every declared silo landed.

const CANISTER_SCENE := preload("res://scenes/props/canister.tscn")
const POWER_CELL_SCENE := preload("res://scenes/props/power_cell.tscn")
const SILO_SCENE := preload("res://scenes/props/silo.tscn")

## Where the dressed-in props live, so the table below can name them by their own names.
@export var decor_root: NodePath = ^"../Decor"

## The fixed containers. A row with a `decor` key ADOPTS that prop; one with an `at` key is
## SPAWNED there with its own model.
const SILOS := [
	{
		"id": &"life_support",
		"display_name": "LIFE SUPPORT",
		"decor": ^"LifeSilo1",
		"mode": Silo.Mode.SUPPLY,
		"accepts": &"o2",
		"level": 1.0,
		# Four charges from full. The number the player is actually budgeting against, so it
		# wants to be small enough to count on one hand.
		"use_amount": 0.25,
		"use_text": "Clear your head",
		"service_text": "Charge the scrubber",
		# Roughly the tank, in metres, offset back toward its body — CD_Silo_Base_v1 is a
		# 0.9m x 3.4m tank whose pipework runs behind the origin.
		"size": Vector3(1.0, 2.4, 1.8),
		"offset": Vector3(0.0, 1.2, 0.5),
	},
	{
		# The drive's fuel tank. Spawned rather than adopted: the engine room's model was pulled
		# (its animation was broken — see the log) and its only decor is four wall pipes, so
		# there is nothing standing there to take over.
		#
		# Standing off the aft wall rather than against one, because every wall in this room is
		# already spoken for: DRIVE REGULATOR owns the port wall, MAIN DRIVE the aft, COOLANT
		# LOOP the starboard, and each of them needs 0.9m of clear air in front of the panel —
		# which is what smoke_navigation caught the first placement doing to MAIN DRIVE.
		"id": &"power",
		"display_name": "DRIVE FUEL",
		"at": Vector3(-19.5, 0.0, 5.5),
		"mode": Silo.Mode.SUPPLY,
		"accepts": &"battery",
		"level": 1.0,
		"use_amount": 0.0,  # nothing to "use" — you do not sip fuel, the engine burns it
		# The one silo that empties on its own, on the SHIP's clock. 0.11/day against a ~31-day
		# crossing is a tank that will not survive the trip on its own: roughly nine days a
		# cell, so three or four runs to the cargo bay across a full voyage, and sleeping
		# through a stretch is what eats it fastest.
		"drain_per_day": 0.11,
		"stops_the_drive": true,
		"warn_at": 0.35,
		"vo_line": &"power_off",
		"service_text": "Slot the cell in",
	},
]

## Loose supplies, spawned where they lie. The cargo bay runs x 13..28, z -2..14; these sit in
## its aft-starboard corner beside the crates, which is where the decorative canisters already
## are — so the room reads the same and the walk is the measured 67.1 m the balance assumes.
const CANISTERS := [
	{"kind": &"o2", "at": Vector3(25.6, 0.5, 5.2)},
	{"kind": &"o2", "at": Vector3(25.6, 0.5, 6.1)},
	{"kind": &"o2", "at": Vector3(24.8, 0.5, 5.6)},
]

## Fuel cells, a little further into the room so they are a separate errand rather than
## something you sweep up on the same trip as the air.
const POWER_CELLS := [
	Vector3(21.5, 0.5, 6.5),
	Vector3(22.3, 0.5, 6.9),
	Vector3(21.9, 0.5, 7.6),
	Vector3(22.7, 0.5, 7.2),
]

var _silos: Array[Silo] = []
var _canisters: Array[Consumable] = []


func _ready() -> void:
	build()


## Idempotent, so a rebuild during development does not leave two of everything.
func build() -> void:
	for old in _silos + _canisters:
		if is_instance_valid(old):
			old.queue_free()
	_silos.clear()
	_canisters.clear()

	for row in SILOS:
		var silo := _build_silo(row)
		if silo != null:
			_silos.append(silo)
	for row in CANISTERS:
		_canisters.append(_spawn(CANISTER_SCENE, row["kind"], row["at"]))
	for at in POWER_CELLS:
		_canisters.append(_spawn(POWER_CELL_SCENE, &"battery", at))


func silos() -> Array[Silo]:
	return _silos


func canisters() -> Array[Consumable]:
	return _canisters


## Build one row of SILOS, adopting a decor prop or spawning a tank of its own.
func _build_silo(row: Dictionary) -> Silo:
	var adopting := row.has("decor")
	var at := Vector3.ZERO
	if adopting:
		var decor := get_node_or_null(decor_root)
		var host: Node3D = null
		if decor != null:
			host = decor.get_node_or_null(row["decor"]) as Node3D
		if host == null:
			# Loud, because the silo simply not being there is the kind of failure a player
			# experiences as "the game is broken" rather than as a missing prop.
			push_warning("ShipSupplies: no decor node at %s/%s to host the %s silo"
				% [decor_root, row["decor"], row["id"]])
			return null
		at = host.global_position
	else:
		at = row["at"]

	# An adopted silo gets a bare body — the decor prop it stands on IS the model. A spawned
	# one brings its own. Both end up the same kind of node, so nothing downstream cares.
	var node: Node = SILO_SCENE.instantiate() if not adopting else _bare_silo_body(row)
	var view: Node3D = node
	var silo := view as Silo
	silo.name = "Silo_%s" % row["id"]
	silo.silo_id = row["id"]
	silo.display_name = row.get("display_name", "SILO")
	silo.mode = row.get("mode", Silo.Mode.SUPPLY)
	silo.accepts = row.get("accepts", &"o2")
	silo.level = row.get("level", 1.0)
	silo.use_amount = row.get("use_amount", 0.25)
	silo.drain_per_day = row.get("drain_per_day", 0.0)
	silo.stops_the_drive = row.get("stops_the_drive", false)
	silo.warn_at = row.get("warn_at", 0.4)
	silo.vo_line = row.get("vo_line", &"")
	silo.use_text = row.get("use_text", "Use")
	silo.service_text = row.get("service_text", "Refill it")
	silo.lamp_offset = row.get("lamp_offset", Vector3(-0.11, 1.55, -0.30))

	add_child(node)
	# AFTER add_child: global_position on a node outside the tree is meaningless.
	(node as Node3D).global_position = at
	return silo


## The interaction half of a silo with no model of its own, for adopting a decor prop.
func _bare_silo_body(row: Dictionary) -> Node:
	var body := StaticBody3D.new()
	body.set_script(load("res://scripts/game/silo.gd"))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = row.get("size", Vector3.ONE)
	shape.shape = box
	shape.position = row.get("offset", Vector3.ZERO)
	body.add_child(shape)
	return body


func _spawn(scene: PackedScene, kind: StringName, at: Vector3) -> Consumable:
	var node := scene.instantiate()
	var view: Node3D = node
	var item := view as Consumable
	item.name = "Supply_%s" % kind
	add_child(node)
	item.set_kind(kind)
	(node as Node3D).global_position = at
	return item
