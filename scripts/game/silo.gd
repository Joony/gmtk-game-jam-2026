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
# Nothing here ticks. A silo's level changes only when the player uses or services it; the
# COUNTDOWNS belong to Need, which is a body clock, not a tank. Keeping the tank dumb is what
# stops "the beer silo evaporates while you sleep" being a thing anyone has to think about.

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

@export var use_text: String = "Use"
@export var service_text: String = "Refill it"

var _consumed: bool = false


func _ready() -> void:
	super()  # Interactable._ready: register in the interactables group
	add_to_group(GROUP_SILO)
	level = clampf(level, 0.0, 1.0)


## How much doing is left before this is in trouble, 0..1. 1 is a full supply or an empty
## waste tank; 0 is a dry supply or a brimming one. Mode-agnostic on purpose — everything
## downstream (HUD rows, warnings, the Need that draws on it) reads this and never `level`.
func headroom() -> float:
	return level if mode == Mode.SUPPLY else 1.0 - level


## How many more uses are left in it. Rounded DOWN: a silo with half a use in it has none.
func uses_left() -> int:
	if use_amount <= 0.0:
		return 0
	return int(floor(headroom() / use_amount))


func is_exhausted() -> bool:
	return headroom() <= 0.0


## Use it: breathe, drink, eat, flush. Returns false if there was nothing to use.
##
## A WASTE silo with `block_when_exhausted` off accepts the use and clamps, so the tank sits at
## full and `exhausted` has fired — the player has flushed into a tank that cannot take it, and
## that is the state the explosion countdown hangs off.
func use() -> bool:
	if use_amount <= 0.0:
		return false
	if block_when_exhausted and headroom() < use_amount:
		return false
	_set_level(level + use_amount * _use_direction())
	used.emit(self)
	return true


## Spend a carried canister on it. Returns false if the item is the wrong kind or the silo has
## no room for it — a full silo must reject the canister rather than swallowing it, or a
## mistimed press costs the player a whole trip to the cargo bay.
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
	return not is_exhausted() or not block_when_exhausted


func get_interaction_text(held_item: Node3D = null) -> String:
	if _servicer(held_item) != null:
		if headroom() >= 1.0:
			return "%s: nothing to top up" % display_name
		return service_text
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
	level_changed.emit(self, level)
	if is_exhausted() and not was_exhausted:
		exhausted.emit(self)
