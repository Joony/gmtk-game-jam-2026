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
const FOOD_CRATE_SCENE := preload("res://scenes/props/food_crate.tscn")
const SILO_SCENE := preload("res://scenes/props/silo.tscn")
const REPAIR_PANEL_SCENE := preload("res://scenes/props/repair_panel.tscn")

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
	{
		# The beer silo in the mess. Adopts the tank already dressed in there.
		"id": &"beer",
		"display_name": "BEER",
		"decor": ^"MessSilo",
		"mode": Silo.Mode.SUPPLY,
		"accepts": &"beer",
		"level": 1.0,
		"use_amount": 0.25,
		"warn_at": 0.3,
		"vo_line": &"no_beer",
		"use_text": "Have a drink",
		"service_text": "Load a beer canister",
		"size": Vector3(1.0, 2.4, 1.8),
		"offset": Vector3(0.0, 1.2, 0.5),
	},
	{
		# The vending machine in the mess. A Silo like every other, which is the point: TODO
		# 17e's worry that hunger had "an extra hop" was a miscount — need, silo in a room,
		# crate from cargo is the same three steps every other need takes.
		#
		# The only thing that makes it different from a tank is its shape, so its collider and
		# lamp are bigger and sit in the machine's own frame — which is why adoption now takes
		# the decor node's rotation as well as its position: this one is turned to face out of
		# the wall it stands against.
		# THE MACHINE IS COUNTED IN SLOTS, not in an abstract fraction, because you can see
		# them: nine pigeonholes behind the glass, and the model carries an empty for each.
		# `use_amount` is one ninth so a purchase is exactly one item, and a food crate is
		# worth three. It starts with three in it — one cake, one can, one plant.
		"id": &"food",
		"display_name": "VENDING",
		"decor": ^"MessVending",
		"mode": Silo.Mode.SUPPLY,
		"accepts": &"food",
		"level": 3.0 / 9.0,
		"use_amount": 1.0 / 9.0,
		# Two items left. Below a third of a machine there is not enough in it to matter.
		"warn_at": 2.0 / 9.0,
		"vo_line": &"ate_food",
		"use_text": "Get something to eat",
		"service_text": "Load the crate in",
		# Shows what is in it, in the model's own slot1..slot9 empties. See VendingStock.
		"stock": true,
		# The one silo that can BREAK. It is a machine with moving parts, not a tank, so it
		# gets an ordinary Malfunction with an ordinary repair hatch: a spare part or a hammer
		# bodge, a row in the HUD fault list, the same repair sounds as everything else.
		"fault": {
			"system_name": "VENDING MACHINE",
			"fault_text": "dispenser jammed",
			# Genuinely random, unlike every other fault on the ship, which fires at a fixed
			# point in the voyage. A vending machine packing up is comic rather than
			# structural — there is nothing to learn the timing of and no reason to make it
			# learnable, so it just happens somewhere in the middle third of the crossing.
			"fire_between": Vector2(62.0, 30.0),
			# Costs no drive. It is not a ship system; it is the thing standing between the
			# player and lunch, and hunger is the clock it actually presses on.
			"speed_penalty": 0.0,
			# A short bodge, and that is the whole trade the hammer offers here: the fault is
			# cheap to patch and comes back soon, so the spare part is worth spending on a
			# machine you are going to keep needing.
			"bodge_distance": 9.0,
			"patch_text": "Thump the dispenser",
			"fit_text": "Fit a spare dispenser motor",
			# A service hatch on the machine's front, below the keypad and just proud of the
			# face — outside the silo's own collider, so the ray reaches it. Half size: the
			# ship's standard panel is 0.9 x 1.1m and would swallow the machine.
			"panel_at": Vector3(0.84, 0.42, 0.735),
			"panel_scale": 0.5,
		},
		# 2.4m wide x 2.4m tall x 1.29m deep, at the 0.6 the mess dresses it at. The model's
		# origin is at its base, so the box sits entirely above the floor.
		"size": Vector3(2.4, 2.4, 1.29),
		"offset": Vector3(0.0, 1.2, 0.045),
		# On the KEYPAD panel to the right of the glass, not on the glass: the machine now shows
		# what is in it, and a lamp in the middle of the window was covering a pigeonhole. The
		# panel is the `Cube` mesh, model x 1.0..1.8 and y 1.3..2.7, which at 0.6 is x 0.6..1.08
		# and y 0.78..1.62 — this sits above its buttons and just proud of its face.
		"lamp_offset": Vector3(0.84, 1.45, 0.70),
	},
	{
		# The head. Its own prop rather than an adoption, because the bathroom's decorative
		# silo is a tank and this is the thing you sit on — and the whole point of the chain is
		# that both halves happen in the same place. See scenes/props/toilet.tscn.
		#
		# Everything about it is in the prop scene, so this row is only where it stands.
		"id": &"crap",
		"scene": "res://scenes/props/toilet.tscn",
		"at": Vector3(-7.0, 0.0, -5.7),
		# Yawed to face the door, which is in the aft wall at (-3.5, -12).
		"yaw": 180.0,
	},
]

## Loose supplies, spawned where they lie. The cargo bay runs x 13..28, z -2..14; these sit in
## its aft-starboard corner beside the crates, which is where the decorative canisters already
## are — so the room reads the same and the walk is the measured 67.1 m the balance assumes.
const CANISTERS := [
	{"kind": &"o2", "at": Vector3(25.6, 0.5, 5.2)},
	{"kind": &"o2", "at": Vector3(25.6, 0.5, 6.1)},
	{"kind": &"o2", "at": Vector3(24.8, 0.5, 5.6)},
	{"kind": &"beer", "at": Vector3(24.8, 0.5, 6.5)},
	{"kind": &"beer", "at": Vector3(24.0, 0.5, 5.9)},
	# Empties, for pumping the septic tank out. Deliberately FEWER than there are beers: every
	# beer you drink is a trip to the toilet and every few trips is a tank to empty, so running
	# the mess dry and running out of empties are the same mistake seen from two ends. An air
	# canister you have already spent becomes one of these, which is the way out.
	{"kind": &"empty", "at": Vector3(24.0, 0.5, 6.8)},
	{"kind": &"empty", "at": Vector3(23.3, 0.5, 6.2)},
]

## Fuel cells, a little further into the room so they are a separate errand rather than
## something you sweep up on the same trip as the air.
## On a 0.9m grid, comfortably clear of the 0.5m cell, so they stand in a row rather than
## climbing on each other. A cell resting on another cell is not a bug, but it makes the
## "everything is on the floor" check in smoke_supplies unable to tell stacked from floating —
## and that check is what caught these being launched through the hull in the first place.
const POWER_CELLS := [
	Vector3(21.2, 0.5, 6.4),
	Vector3(22.1, 0.5, 6.4),
	Vector3(21.2, 0.5, 7.3),
	Vector3(22.1, 0.5, 7.3),
]

## Food crates, further in again, beside the big decorative crates they are small versions of.
const FOOD_CRATES := [
	Vector3(19.5, 0.5, 9.5),
	Vector3(20.3, 0.5, 9.8),
	Vector3(19.9, 0.5, 10.6),
]

var _silos: Array[Silo] = []
var _canisters: Array[Consumable] = []
var _stocks: Array[VendingStock] = []


func _ready() -> void:
	build()


## Idempotent, so a rebuild during development does not leave two of everything.
func build() -> void:
	for old in _silos + _canisters:
		if is_instance_valid(old):
			old.queue_free()
	_silos.clear()
	_canisters.clear()
	# Not freed with the silos: a stock's items live inside the DECOR model's slot empties, so
	# they outlive the silo body they were built from unless they are cleared here.
	for stock in _stocks:
		if is_instance_valid(stock):
			stock.clear()
	_stocks.clear()

	for row in SILOS:
		var silo := _build_silo(row)
		if silo != null:
			_silos.append(silo)
	for row in CANISTERS:
		_canisters.append(_spawn(CANISTER_SCENE, row["kind"], row["at"]))
	for at in POWER_CELLS:
		_canisters.append(_spawn(POWER_CELL_SCENE, &"battery", at))
	for at in FOOD_CRATES:
		_canisters.append(_spawn(FOOD_CRATE_SCENE, &"food", at))


func silos() -> Array[Silo]:
	return _silos


func canisters() -> Array[Consumable]:
	return _canisters


## Build one row of SILOS, adopting a decor prop or spawning a tank of its own.
func _build_silo(row: Dictionary) -> Silo:
	var adopting := row.has("decor")
	var at := Vector3.ZERO
	var facing := Basis.IDENTITY
	# Kept in scope past the branch: a vending machine's pigeonholes are empties inside this
	# node, so the stock display below needs it too.
	var host: Node3D = null
	if adopting:
		var decor := get_node_or_null(decor_root)
		if decor != null:
			host = decor.get_node_or_null(row["decor"]) as Node3D
		if host == null:
			# Loud, because the silo simply not being there is the kind of failure a player
			# experiences as "the game is broken" rather than as a missing prop.
			push_warning("ShipSupplies: no decor node at %s/%s to host the %s silo"
				% [decor_root, row["decor"], row["id"]])
			return null
		at = host.global_position
		# The ROTATION too, not just the position. The tanks all sit square, but the vending
		# machine is turned to face out of its wall — and an adopted body's collider and lamp
		# are described in the prop's own frame, so without this they would be laid out across
		# a machine that is standing side-on to them.
		facing = host.global_transform.basis.orthonormalized()
	else:
		at = row["at"]

	# Three ways to get a body, in order of how much the row has to say:
	#   a named `scene`  a prop that already knows what it is — the toilet
	#   adopting         a bare body; the decor prop it stands on IS the model
	#   otherwise        the generic tank, which brings its own model
	var node: Node
	if row.has("scene"):
		var scene: PackedScene = load(row["scene"])
		node = scene.instantiate()
	elif adopting:
		node = _bare_silo_body(row)
	else:
		node = SILO_SCENE.instantiate()

	var view: Node3D = node
	var silo := view as Silo
	silo.name = "Silo_%s" % row["id"]
	silo.silo_id = row["id"]
	# ONLY what the row actually says, so a prop scene that already configured itself is not
	# quietly reset to the generic defaults. The toilet is entirely its own scene; its row here
	# is just where it stands.
	for key in ["display_name", "mode", "accepts", "level", "use_amount", "drain_per_day",
			"stops_the_drive", "warn_at", "vo_line", "use_text", "service_text",
			"block_when_exhausted", "lamp_offset"]:
		if row.has(key):
			silo.set(key, row[key])

	add_child(node)
	# AFTER add_child: a global transform on a node outside the tree is meaningless.
	var body := node as Node3D
	body.global_transform = Transform3D(facing, at)
	if row.has("yaw"):
		body.rotation.y = deg_to_rad(row["yaw"])

	# A machine that shows what is left in it. Bound to the DECOR node, because the pigeonholes
	# are empties inside that model — an adopted silo has no geometry of its own to hang them on.
	if row.get("stock", false) and host != null:
		var stock := VendingStock.new()
		stock.name = "Stock"
		silo.add_child(stock)
		stock.bind(silo, host)
		_stocks.append(stock)

	if row.has("fault"):
		silo.bind_malfunction(_build_fault(silo, row["fault"]))
	return silo


## A Malfunction standing where the silo does, with a repair hatch on it. Built rather than
## placed for the same reason as everything else here, and collected by RunState the same way
## every scene-placed fault is — it joins the `malfunctions` group in its own _ready().
##
## A CHILD of the silo, so the hatch's offset is expressed in the machine's own frame and the
## whole thing travels if the prop is ever moved.
func _build_fault(silo: Silo, spec: Dictionary) -> Malfunction:
	var fault := Malfunction.new()
	fault.name = "Fault_%s" % silo.silo_id
	fault.system_name = spec.get("system_name", "SYSTEM")
	fault.fault_text = spec.get("fault_text", "fault detected")
	fault.severity = spec.get("severity", Malfunction.Severity.DEGRADING)
	fault.speed_penalty = spec.get("speed_penalty", 0.0)
	fault.bodge_distance = spec.get("bodge_distance", 25.0)
	fault.vo_line = spec.get("vo_line", &"")

	# `fire_between` is million-miles-remaining, counting DOWN, so x is the earlier end.
	var window: Vector2 = spec.get("fire_between", Vector2.ZERO)
	if window != Vector2.ZERO:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		fault.fire_at_distance = rng.randf_range(minf(window.x, window.y), maxf(window.x, window.y))
	else:
		fault.fire_at_distance = spec.get("fire_at_distance", 0.0)

	var panel: Node = REPAIR_PANEL_SCENE.instantiate()
	var point := panel as RepairPoint
	point.patch_text = spec.get("patch_text", "Patch it")
	point.fit_text = spec.get("fit_text", "Fit a spare part")
	fault.add_child(panel)
	# Parented BEFORE the fault joins the tree, so Malfunction._ready() finds and binds it.
	silo.add_child(fault)
	(panel as Node3D).position = spec.get("panel_at", Vector3.ZERO)
	(panel as Node3D).scale = Vector3.ONE * float(spec.get("panel_scale", 1.0))
	return fault


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
