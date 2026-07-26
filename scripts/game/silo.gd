class_name Silo
extends Interactable

# The fixed container you walk to: the life-support silo, the beer silo in the mess, the
# vending machine, the engine's battery bay, and the toilet's crap tank.
#
# Attach to the StaticBody3D the camera ray hits, like WallSocket. Two verbs, and which one you
# get is decided by what is in your hands — the dispatch Interactable already does:
#
#   empty hands            -> interact()      -> USE it. Breathe, drink, eat, flush.
#   holding a matching can -> use_with_item() -> SERVICE it. The trip from the cargo bay.
#
# SUPPLY AND WASTE ARE THE SAME OBJECT, WHICH IS THE WHOLE TRICK. `level` always means "how
# much stuff is in it", 0..1. A supply silo starts full and using it empties it; a waste silo
# starts empty and using it FILLS it. That is the only difference, and it is one sign:
#
#            supply (life support, beer, vending, power)   waste (the toilet)
#   use()    level goes DOWN                                level goes UP
#   service()level goes UP   (bring a full canister)        level goes DOWN (bring an empty one)
#   trouble  level == 0, nothing left to breathe            level == 1, nowhere left to put it
#
# So `headroom()` — how much of the thing you can still do before you are in trouble — reads
# the same for both, and the HUD, the Need and the tests can all be written once. Six systems,
# one script, which is TODO 17a.
#
# MOSTLY NOTHING HERE TICKS, and the exception is the interesting one. A silo's level normally
# changes only when the player uses or services it — the COUNTDOWNS belong to Need, which is a
# body clock, not a tank, and keeping the tank dumb is what stops "the beer silo evaporates
# while you sleep" being something anyone has to think about.
#
# `drain_per_day` is the exception, and it exists for the engine. A drive burns fuel because the
# ship is moving, not because the player did anything, so power has to run down on its own — and
# it runs on the SHIP's clock, which means STASIS BURNS IT. That is the point: the pod already
# costs oxygen at a reduced rate, and now it costs fuel at 24x, so sleeping is no longer the
# free half of the loop. Same unit as Malfunction.speed_decay_per_day, for the same reason.

## Emitted on any level change, for the HUD and for whoever is watching a tank fill.
signal level_changed(silo: Silo, level: float)
## Emitted when `headroom()` reaches zero — the supply ran dry, or the waste tank is full.
## ONE signal for both, because the consequence is the caller's business and the two read the
## same from here: there is nothing left to do at this silo until someone walks a can to it.
signal exhausted(silo: Silo)
## Emitted when a use succeeds. The Need that this silo serves resets on it.
signal used(silo: Silo)
## Emitted when a canister is spent on it.
signal serviced(silo: Silo, item: Consumable)

## A SUPPLY empties as it is used and is refilled from a full canister; a WASTE fills as it is
## used and is emptied into an empty canister.
enum Mode { SUPPLY, WASTE }

const GROUP_SILO := &"silos"

## Which silo this is, so a Need can name the one that services it without a NodePath. Same
## reasoning as Malfunction's group lookup: the wiring survives the scene being rearranged.
@export var silo_id: StringName = &"life_support"
@export var display_name: String = "LIFE SUPPORT"
@export var mode: Mode = Mode.SUPPLY

## The `Consumable.kind` that services this. An empty canister for a waste tank — which is why
## `accepts` is not derivable from `mode` and has to be stated.
@export var accepts: StringName = &"o2"

## 0..1, how much stuff is in it. Defaults suit a SUPPLY; a WASTE silo wants 0.0.
@export_range(0.0, 1.0) var level: float = 1.0

## How much one use costs. 0.25 means four uses from full, which is the number the player is
## actually budgeting against.
@export var use_amount: float = 0.25

## Refuse a use that would take the level past its limit. On for a supply (you cannot breathe
## air that is not there); OFF for a waste tank, because a toilet that politely declines is a
## worse outcome than one that overflows — the overflow IS the consequence.
@export var block_when_exhausted: bool = true

## Headroom lost per elapsed SHIP day, all on its own. 0 for everything the player drives; the
## engine's fuel tank is the one that burns whether you are watching or not. See the note above.
@export var drain_per_day: float = 0.0

## Headroom at which this starts shouting — the HUD row appears, and the lamp goes amber.
## Same idea as Need.warn_at: the readout grows as things get bad.
@export_range(0.0, 1.0) var warn_at: float = 0.4

## Line the ship computer says when this runs out, or &"" for silence. Data like
## Malfunction.vo_line, so giving a silo a voice is a field rather than a branch.
@export var vo_line: StringName = &""

## Empty means the ship stops. Only the engine's fuel tank. A flag rather than RunState
## matching on `silo_id`, so the fuel tank can be moved, renamed or duplicated without the
## consequence being wired to its name.
@export var stops_the_drive: bool = false

@export var use_text: String = "Use"
@export var service_text: String = "Refill it"

## Build a small emissive lamp on the tank, green through amber to red as it empties. Off for
## a silo whose art already says what it holds.
@export var show_lamp: bool = true
## Where the lamp sits relative to the silo's ORIGIN, in metres. A full offset rather than just
## a height, and the default is measured rather than guessed: CD_Silo_Base_v1's geometry is not
## centred on its own origin — at the 0.171429 the ship dresses it at, the drum occupies
## x -0.57..0.34 and z -0.34..1.42 — so a lamp at (0, h, 0) hangs in the air beside the tank
## rather than on it, which is exactly what the first render showed. This sits it on the drum's
## axis, at chest height, just proud of the face nearest the door.
@export var lamp_offset: Vector3 = Vector3(-0.11, 1.55, -0.30)

## Slack for comparing a level against a limit. Levels are fractions of the number of uses a
## silo holds, and thirds and ninths do not survive binary arithmetic intact.
const EPSILON := 0.0001

const LAMP_OK := Color(0.24, 0.90, 0.40)
const LAMP_WARN := Color(1.00, 0.62, 0.10)
const LAMP_CRIT := Color(1.00, 0.16, 0.12)

## A fault that takes this silo out of service while it is active, or null. The vending machine
## is the one that has one: it is a machine with moving parts, not a tank.
##
## Deliberately the ORDINARY Malfunction, with an ordinary RepairPoint on it — so a jammed
## vending machine is a spare part or a hammer bodge, appears in the HUD fault list, and sounds
## like every other repair. A bespoke "machine is broken" flag would have been less code and a
## worse game: the player would have had to learn a second repair idiom for one prop.
var malfunction: Malfunction = null

var _consumed: bool = false
var _lamp_material: StandardMaterial3D = null


func _ready() -> void:
	super()  # Interactable._ready: register in the interactables group
	add_to_group(GROUP_SILO)
	level = clampf(level, 0.0, 1.0)
	if show_lamp:
		_build_lamp()
	_refresh_lamp()


## How much doing is left before this is in trouble, 0..1. 1 is a full supply or an empty
## waste tank; 0 is a dry supply or a brimming one. Mode-agnostic on purpose — everything
## downstream (HUD rows, warnings, the Need that draws on it) reads this and never `level`.
func headroom() -> float:
	return level if mode == Mode.SUPPLY else 1.0 - level


## How many more uses are left in it. Rounded DOWN: a silo with half a use in it has none.
##
## Nudged by EPSILON first, because a level is not always a round number of uses. The vending
## machine is counted in NINTHS — nine pigeonholes — and three ninths taken one ninth at a time
## does not reach zero in binary: it lands a hair either side. Without the nudge the machine
## reports two items left when it is showing three.
func uses_left() -> int:
	if use_amount <= 0.0:
		return 0
	return int(floor(headroom() / use_amount + EPSILON))


func is_exhausted() -> bool:
	return headroom() <= EPSILON


## Bad enough to have earned a row on the HUD.
func is_pressing() -> bool:
	return headroom() <= warn_at


## Out of order. Not the same as empty: an empty machine needs a crate, a broken one needs a
## spare part or the hammer.
func is_broken() -> bool:
	return malfunction != null and malfunction.is_active


## Put this silo out of service whenever `fault` is active.
func bind_malfunction(fault: Malfunction) -> void:
	malfunction = fault
	if fault == null:
		return
	if not fault.broke.is_connected(_on_fault_changed):
		fault.broke.connect(_on_fault_changed)
	if not fault.repaired.is_connected(_on_fault_changed):
		fault.repaired.connect(_on_fault_changed)
	_refresh_lamp()


func _on_fault_changed(_fault: Malfunction, _flag: bool) -> void:
	_refresh_lamp()


## Burn what a silo loses on its own. `days` is ship time already scaled by stasis, so a fuel
## tank empties 24x faster in the pod — which is the whole reason this runs on the ship's clock
## rather than the player's. A no-op for every silo the player drives.
func advance(days: float) -> void:
	if drain_per_day <= 0.0 or days <= 0.0 or is_exhausted():
		return
	_set_level(level + drain_per_day * days * _use_direction())


## Use it: breathe, drink, eat, flush. Returns false if there was nothing to use.
##
## A WASTE silo with `block_when_exhausted` off accepts the use and clamps, so the tank sits at
## full and `exhausted` has fired — the player has flushed into a tank that cannot take it, and
## that is the state the explosion countdown hangs off.
func use() -> bool:
	if use_amount <= 0.0 or is_broken():
		return false
	# EPSILON again, and it is load-bearing rather than defensive. A level is arrived at by
	# adding and subtracting fractions that do not exist in binary — a food crate is worth a
	# third and a purchase costs a ninth — so the last item in a machine sits at 0.1111109
	# against a use_amount of 0.1111111 and a bare `<` refuses to sell it. The player sees an
	# item on the shelf and a prompt that will not take it.
	if block_when_exhausted and headroom() + EPSILON < use_amount:
		return false
	_set_level(level + use_amount * _use_direction())
	used.emit(self)
	return true


## Spend a carried canister on it. Returns false if the item is the wrong kind or the silo has
## no room for it — a full silo must reject the canister rather than swallowing it, or a
## mistimed press costs the player a whole trip to the cargo bay.
## Restocking a BROKEN machine is allowed on purpose. Refusing the crate would throw away a
## trip the player has already paid for in air, over a distinction they cannot see from the
## cargo bay — and a jammed machine full of food is a fair thing to be annoyed at.
func service(item: Consumable) -> bool:
	_consumed = false
	if item == null or not item.matches(accepts):
		return false
	if headroom() >= 1.0:
		return false
	_set_level(level - item.amount * _use_direction())
	# The canister is spent whether or not it filled the silo to the brim. Pouring half a can
	# away is the player's mistake to make, and pretending it did not happen would mean a can
	# that is somehow part-used, which nothing else in the game models.
	_consumed = not item.spend()
	serviced.emit(self, item)
	return true


## True when the last `service()` used the canister up entirely, so Interactor takes it out of
## the player's hands and frees it. A canister that turned into an empty one stays held.
func consumed_last_item() -> bool:
	return _consumed


# --- interaction ------------------------------------------------------------

func get_interaction_type(held_item: Node3D = null) -> InteractionType:
	if not is_enabled:
		return InteractionType.DISABLED
	return InteractionType.USE_ITEM if _servicer(held_item) != null else InteractionType.ACTIVATE


# Holding ANYTHING that is not a canister for this silo makes it un-actionable, and that is
# not a limitation to work around — Interactor sends a held item on an ACTIVATE target down
# the DROP path, so a green reticle there would promise a drink and deliver a dropped hammer.
# You have to have your hands free to eat, and the prompt says as much.
func can_act_on(held_item: Node3D = null) -> bool:
	if not is_enabled:
		return false
	if held_item != null:
		return _servicer(held_item) != null and headroom() < 1.0
	if is_broken():
		return false
	return not is_exhausted() or not block_when_exhausted


func get_interaction_text(held_item: Node3D = null) -> String:
	if _servicer(held_item) != null:
		if headroom() >= 1.0:
			return "%s: nothing to top up" % display_name
		return service_text
	# A broken machine still SAYS something. Going silent here would read as a prop the player
	# had misjudged, and the repair hatch is small enough to walk past.
	if is_broken():
		return "%s: %s" % [display_name, malfunction.fault_text]
	if held_item != null:
		return "%s: %s is no use here" % [display_name, held_item.name]
	if is_exhausted():
		# Naming what it wants, not just refusing. This is the only place the game tells the
		# player which canister to go and find.
		return "%s: empty — needs %s" % [display_name, accepts]
	return "%s  (%d left)" % [use_text, uses_left()]


func interact() -> void:
	if not is_enabled:
		return
	if use():
		interacted_with.emit(self)


func use_with_item(item: Node3D) -> void:
	var canister := _servicer(item)
	if canister == null:
		return
	if service(canister):
		used_with_item.emit(self, item)


func can_use_with_item(item: Node3D) -> bool:
	return _servicer(item) != null


# --- internals --------------------------------------------------------------

## The held item viewed as a canister this silo accepts, or null.
func _servicer(item: Node3D) -> Consumable:
	var canister := item as Consumable
	if canister == null or not canister.matches(accepts):
		return null
	return canister


## +1 if using it moves `level` up (a waste tank filling), -1 if down (a supply draining).
## `service()` uses the opposite, which is the whole of the supply/waste distinction.
func _use_direction() -> float:
	return 1.0 if mode == Mode.WASTE else -1.0


func _set_level(value: float) -> void:
	var was_exhausted := is_exhausted()
	level = clampf(value, 0.0, 1.0)
	# Snap the ends, so a tank emptied in ninths ends on a true zero rather than on 5e-17 and
	# `is_exhausted()` does not depend on which way the last subtraction rounded.
	if level < EPSILON:
		level = 0.0
	elif level > 1.0 - EPSILON:
		level = 1.0
	_refresh_lamp()
	level_changed.emit(self, level)
	if is_exhausted() and not was_exhausted:
		exhausted.emit(self)


## A lamp rather than a liquid level in the tank's own glass, which is what the art invites.
## CD_Silo_Base_v1 has no separate liquid mesh to drive — the level in the window is part of
## the model — so honouring it would need either a new mesh from the modeller or one built
## here and lined up by hand against geometry that is rotated inside the .blend. A lamp is
## legible from across a dark room, which is the thing that actually mattered.
##
## Built in code and unshaded, the same way BatteryCube builds its charge bars, so it works on
## an adopted decor prop as well as on a spawned one.
func _build_lamp() -> void:
	var lamp := MeshInstance3D.new()
	lamp.name = "StatusLamp"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.16, 0.16, 0.16)
	lamp.mesh = mesh
	_lamp_material = StandardMaterial3D.new()
	_lamp_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp.material_override = _lamp_material
	lamp.position = lamp_offset
	add_child(lamp)


## Green unless there is something to do about it, and only two things ever are:
##
##   RED     out of order — a spare part or the hammer
##   ORANGE  empty        — a canister or a crate
##   GREEN   fine
##
## Three states and no gradient. An amber "getting low" tier used to sit in here and it was
## the wrong shape for a lamp across a room: the useful question is "do I need to bring
## something", which has a yes and a no. How URGENT it is belongs on the HUD row, which has
## room for a number.
func _refresh_lamp() -> void:
	if _lamp_material == null:
		return
	var color := LAMP_OK
	if is_broken():
		color = LAMP_CRIT
	elif is_exhausted():
		color = LAMP_WARN
	_lamp_material.albedo_color = color
	_lamp_material.emission_enabled = true
	_lamp_material.emission = color
