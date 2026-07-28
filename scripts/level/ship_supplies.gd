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
const FOOD_CRATE_SCENE := preload("res://scenes/props/food_crate.tscn")
const SILO_SCENE := preload("res://scenes/props/silo.tscn")
const REPAIR_SCRIPT := preload("res://scripts/game/repair_point.gd")
const CANISTER_SILO_SCRIPT := preload("res://scripts/game/canister_silo.gd")
const SILO_SCRIPT := preload("res://scripts/game/silo.gd")

## Where the dressed-in props live, so the table below can name them by their own names.
@export var decor_root: NodePath = ^"../Decor"

## The fixed containers. A row with a `decor` key ADOPTS that prop; one with an `at` key is
## SPAWNED there with its own model.
const SILOS := [
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
		"id": &"head",
		"scene": "res://scenes/props/toilet.tscn",
		# Against the aft wall of the bathroom, which runs z -12 to -5.
		"at": Vector3(-7.0, 0.0, -5.7),
		# Yawed to face the door, which is in the aft wall at (-3.5, -12).
		"yaw": 180.0,
	},
]

## Loose supplies, spawned where they lie. The cargo bay runs x 13..28, z -2..14; these sit in
## its aft-starboard corner beside the crates, which is where the decorative canisters already
## are — so the room reads the same and the walk is the measured 67.1 m the balance assumes.
const CANISTERS := [
	# EIGHT air canisters, not three. Each is worth 150 s against a 240 s budget and the round
	# trip costs most of a minute, so a run that goes wrong burns through them — and running
	# out of air because the hold was empty is a dead end rather than a decision.
	{"kind": &"o2", "at": Vector3(25.6, 0.5, 5.2)},
	{"kind": &"o2", "at": Vector3(25.6, 0.5, 6.1)},
	{"kind": &"o2", "at": Vector3(24.8, 0.5, 5.6)},
	{"kind": &"o2", "at": Vector3(25.6, 0.5, 7.0)},
	{"kind": &"o2", "at": Vector3(24.8, 0.5, 7.4)},
	{"kind": &"o2", "at": Vector3(24.0, 0.5, 7.7)},
	{"kind": &"o2", "at": Vector3(25.4, 0.5, 8.3)},
	{"kind": &"o2", "at": Vector3(24.2, 0.5, 8.8)},
	{"kind": &"beer", "at": Vector3(24.8, 0.5, 6.5)},
	{"kind": &"beer", "at": Vector3(24.0, 0.5, 5.9)},
	# Empties, for pumping the septic tank out. Deliberately FEWER than there are beers: every
	# beer you drink is a trip to the toilet and every few trips is a tank to empty, so running
	# the mess dry and running out of empties are the same mistake seen from two ends. An air
	# canister you have already spent becomes one of these, which is the way out.
	{"kind": &"empty", "at": Vector3(24.0, 0.5, 6.8)},
	{"kind": &"empty", "at": Vector3(23.3, 0.5, 6.2)},
]

## Spare parts in the hold. The ship now throws about forty critical faults across a crossing
## and a fitted part is CONSUMED, so five spares between the closet and the bridge was a couple
## of hours of play at most — after which every fault could only ever be bodged, and the choice
## the whole repair economy is built on stopped existing.
##
## Still deliberately fewer than the faults. Scarce enough that "is this one worth a part?" is a
## real question; not so scarce that the answer is always no.
const SPARES := [
	{"scene": "res://scenes/props/spare_spring.tscn", "at": Vector3(17.2, 0.4, 4.2)},
	{"scene": "res://scenes/props/spare_screw.tscn", "at": Vector3(17.9, 0.4, 4.6)},
	{"scene": "res://scenes/props/spare_gear.tscn", "at": Vector3(16.6, 0.3, 5.0)},
	{"scene": "res://scenes/props/spare_spring.tscn", "at": Vector3(17.5, 0.4, 5.6)},
	{"scene": "res://scenes/props/spare_screw.tscn", "at": Vector3(16.8, 0.4, 6.2)},
	{"scene": "res://scenes/props/spare_gear.tscn", "at": Vector3(18.1, 0.3, 6.0)},
	{"scene": "res://scenes/props/spare_spring.tscn", "at": Vector3(26.4, 0.4, 10.5)},
	{"scene": "res://scenes/props/spare_gear.tscn", "at": Vector3(25.6, 0.3, 11.1)},
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
var _oxygen: CanisterSilo = null
var _tanks: Array[CanisterSilo] = []
## Loose props that are not Consumables — spare parts.
var _props: Array[Node3D] = []


func _ready() -> void:
	build()


## Idempotent, so a rebuild during development does not leave two of everything.
func build() -> void:
	for old in _silos + _canisters:
		if is_instance_valid(old):
			old.queue_free()
	_silos.clear()
	for old in _props:
		if is_instance_valid(old):
			old.queue_free()
	_props.clear()
	_tanks.clear()
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
	_build_canister_silos()
	for row in CANISTERS:
		_canisters.append(_spawn(CANISTER_SCENE, row["kind"], row["at"]))
	for row in SPARES:
		_props.append(_spawn_prop(load(row["scene"]), row["at"]))
	for at in FOOD_CRATES:
		_canisters.append(_spawn(FOOD_CRATE_SCENE, &"food", at))


func silos() -> Array[Silo]:
	return _silos


func canisters() -> Array[Consumable]:
	return _canisters


## Build one row of SILOS, adopting a decor prop or spawning a tank of its own.
func _build_silo(row: Dictionary) -> Silo:
	var silo: Silo = null
	# The prop, when adopting. Kept past the branch because the vending machine's pigeonholes
	# are empties inside it and the stock display needs them.
	var host: Node3D = null

	if row.has("decor"):
		host = _find_prop(row["decor"])
		if host == null:
			# Loud, because a silo simply not being there is the kind of failure a player
			# experiences as "the game is broken" rather than as a missing prop.
			push_warning("ShipSupplies: no prop named %s to make the %s silo out of"
				% [row["decor"], row["id"]])
			return null
		# THE PROP BECOMES THE SILO. Not a body standing invisibly beside it, which is what
		# this used to do and what stopped working the moment the tanks were redressed with a
		# model that brings its own collision: Interactor walks UP from whatever the ray hits,
		# so a hit on the prop's own collider found the prop — a plain Node3D — and gave up.
		# Attaching the script to the prop itself means the thing the player can see IS the
		# thing they can use, with no second collider to fight and nothing to keep aligned.
		host.set_script(SILO_SCRIPT)
		silo = host as Silo
	elif row.has("scene"):
		var scene: PackedScene = load(row["scene"])
		var node: Node = scene.instantiate()
		add_child(node)
		silo = node as Silo
	else:
		var node: Node = SILO_SCENE.instantiate()
		add_child(node)
		silo = node as Silo

	silo.silo_id = row["id"]
	# ONLY what the row actually says, so a prop scene that already configured itself is not
	# quietly reset to the generic defaults. The toilet is entirely its own scene; its row here
	# is just where it stands.
	for key in ["display_name", "mode", "accepts", "level", "use_amount", "drain_per_day",
			"stops_the_drive", "empty_is_critical", "warn_at", "vo_line", "use_text",
			"service_text", "block_when_exhausted", "lamp_offset"]:
		if row.has(key):
			silo.set(key, row[key])

	# An adopted prop is already standing where it belongs; only a spawned one needs placing.
	if host == null:
		var body := silo as Node3D
		body.global_position = row["at"]
		if row.has("yaw"):
			body.rotation.y = deg_to_rad(row["yaw"])
		silo.name = "Silo_%s" % row["id"]
	else:
		# Godot does not re-run _ready() after set_script() on a node already in the tree.
		silo.setup()

	if row.get("stock", false) and host != null:
		var stock := VendingStock.new()
		stock.name = "Stock"
		silo.add_child(stock)
		stock.bind(silo, host)
		_stocks.append(stock)

	if row.has("fault"):
		silo.bind_malfunction(_build_fault(silo, row["fault"]))
	return silo


## A prop by name, looked for under the decor root first and then at the scene root. Both are
## real: the dressed-in furniture lives under Decor, but the silos and the engine are parented
## straight to the game scene. Searching both means the table names a prop and does not have to
## know where in the tree somebody happened to drop it.
func _find_prop(prop_name: NodePath) -> Node3D:
	var decor := get_node_or_null(decor_root)
	if decor != null:
		var found := decor.get_node_or_null(prop_name) as Node3D
		if found != null:
			return found
	var root_node := get_parent()
	if root_node != null:
		return root_node.get_node_or_null(prop_name) as Node3D
	return null


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

	# A LOGIC-ONLY repair point, not the panel prop. A silo with a fault is repaired ON THE
	# SILO — you swing the hammer at the vending machine, not at a service hatch bolted to the
	# front of it — so this exists purely to own the hammer-versus-part dispatch and the prompt
	# wording, and the machine borrows it. No geometry, no indicator, never a ray target.
	var helper := Node3D.new()
	helper.name = "RepairLogic"
	helper.set_script(REPAIR_SCRIPT)
	var point := helper as RepairPoint
	point.show_indicator = false
	point.patch_text = spec.get("patch_text", "Patch it")
	point.fit_text = spec.get("fit_text", "Fit a spare part")
	fault.add_child(helper)
	# Parented BEFORE the fault joins the tree, so Malfunction._ready() finds and binds it.
	silo.add_child(fault)
	point.setup()
	point.bind(fault)
	# Out of the interactables group entirely. It has no collider so a ray could never find it,
	# but leaving it in the group means anything iterating "everything the player can touch"
	# counts a repair point that does not exist as an object. The machine is the object.
	point.remove_from_group(&"interactables")
	point.is_enabled = false
	silo.bind_repair(point)
	return fault


func _spawn(scene: PackedScene, kind: StringName, at: Vector3) -> Consumable:
	var node := scene.instantiate()
	var view: Node3D = node
	var item := view as Consumable
	item.name = "Supply_%s" % kind
	add_child(node)
	item.set_kind(kind)
	(node as Node3D).global_position = at
	return item


## The life-support tank (TODO 21e). Adopted onto the silo prop in life support, like the
## others — but with CanisterSilo rather than Silo, because it holds a canister you can see
## rather than a number, and refills the run's own air rather than clearing a countdown.
##
## Starts with a full canister in the cradle, so the mechanic is legible before it is urgent:
## the player sees the thing that has to be swapped long before they need to swap it.
## The socketed tanks — serviced by SWAPPING A CANISTER rather than by topping a number up.
## The same object three times, differing only in what goes in and which way it flows.
const CANISTER_SILOS := [
	{
		"id": &"life_support",
		"display_name": "LIFE SUPPORT",
		"prop": ^"CD_Silo_Base_v1_1",
		"mode": CanisterSilo.Mode.SUPPLY,
		"accepts": &"o2",
		"spent": &"empty",
		"seconds": 150.0,  # the only one that feeds the air budget
		"starts_with": &"empty",
	},
	{
		# The mess. Fitting a beer discharges it exactly as the air tank does; what it
		# discharges INTO is thirst, which is parked (TODO 21 scope note). So for now the swap
		# is the whole mechanic and the tank feeds nothing.
		"id": &"beer",
		"display_name": "BEER",
		"prop": ^"CD_Silo_Base_v1_3",
		"mode": CanisterSilo.Mode.SUPPLY,
		"accepts": &"beer",
		"spent": &"empty",
		"seconds": 0.0,
		"starts_with": &"beer",
	},
	{
		# The head's tank, and the one that runs backwards: you fit an EMPTY bottle and the ship
		# fills it. Nothing schedules that yet — the bladder is parked with thirst — so it fills
		# only when something calls add_waste(). The head does, so using it already works.
		"id": &"crap",
		"display_name": "SEPTIC TANK",
		"prop": ^"CD_Silo_Base_v1_2",
		"mode": CanisterSilo.Mode.WASTE,
		"accepts": &"empty",
		"spent": &"shit",
		"seconds": 0.0,
		"starts_with": &"empty",
	},
]


## Adopt each declared prop as a socketed tank, with a canister already in the cradle.
##
## Every one starts LOADED, and with the bottle that makes the mechanic legible before it is
## urgent: life support with a spent one (whoever was awake last used it), the mess with a full
## beer, the head with a clean empty. The object the player will be swapping is in front of them
## from the first minute, in the place they will swap it.
func _build_canister_silos() -> void:
	for row in CANISTER_SILOS:
		var host := _find_prop(row["prop"])
		if host == null:
			push_warning("ShipSupplies: no %s to make the %s tank out of"
				% [row["prop"], row["id"]])
			continue
		host.set_script(CANISTER_SILO_SCRIPT)
		var tank := host as CanisterSilo
		tank.silo_id = row["id"]
		tank.display_name = row["display_name"]
		tank.mode = row["mode"]
		tank.accepts = row["accepts"]
		tank.spent_kind = row["spent"]
		tank.seconds_per_canister = row["seconds"]
		tank.setup()
		_tanks.append(tank)
		if row["id"] == &"life_support":
			_oxygen = tank
		tank.install_spent(_spawn(CANISTER_SCENE, row["starts_with"], host.global_position))
		# `install_spent` forces the spent kind; a tank that starts loaded with something usable
		# has to be put back afterwards. Only the mess starts that way today.
		if row["starts_with"] != row["spent"]:
			tank.fitted().set_kind(row["starts_with"])

	# The head has no tank of its own any more — it fills the septic one next door. Nothing
	# calls this on a schedule yet (the bladder is parked), but using the head works.
	var head := _silo_by_id(&"head")
	var septic := tank_by_id(&"crap")
	if head != null and septic != null:
		head.used.connect(func(_s: Silo) -> void:
			# Its own level is meaningless now, so keep it at zero and let the tank hold the
			# state. One number for one thing.
			head.level = 0.0
			septic.add_waste(head.use_amount))


func tank_by_id(id: StringName) -> CanisterSilo:
	for tank in _tanks:
		if tank.silo_id == id:
			return tank
	return null


func tanks() -> Array[CanisterSilo]:
	return _tanks


func _silo_by_id(id: StringName) -> Silo:
	for silo in _silos:
		if silo.silo_id == id:
			return silo
	return null


func oxygen_silo() -> CanisterSilo:
	return _oxygen


## A plain prop with no `kind` to set — a spare part rather than a consumable.
func _spawn_prop(scene: PackedScene, at: Vector3) -> Node3D:
	var node := scene.instantiate()
	add_child(node)
	var body := node as Node3D
	body.global_position = at
	return body


func spares() -> Array[Node3D]:
	return _props
