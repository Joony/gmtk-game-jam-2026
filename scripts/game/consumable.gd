class_name Consumable
extends Interactable

# A carryable you fetch and spend on a Silo. The supply half of TODO 17: air canisters, beer,
# food, batteries, and the empties you pump the crap silo into.
#
# Like BatteryCube and CablePlug this is an Interactable (PICKUP) script sitting on the
# RigidBody3D itself, so `get_item_node()` returns the body and Carry can hold it.
#
# WHY A `kind` STRING RATHER THAN SIX SCRIPTS. Every one of these is the same object with a
# different label on it, and the whole point of 17a is that the six systems are one mechanic
# configured six ways. A Silo matches on `kind` and nothing else, so adding a seventh supply is
# a prop scene, never a new script — the same reasoning that made Malfunction's character data.
#
# WHAT MAKES THIS MORE THAN A LABEL: `becomes`. Spending a canister does not have to destroy
# it. An air canister you have emptied into life support is now an EMPTY canister, and an empty
# canister is exactly what the crap silo needs pumping into — after which it is a canister full
# of crap, and your problem. So the supply chain closes on itself:
#
#   o2 --(fill life support)--> empty --(pump out the toilet)--> shit --> (get rid of it)
#
# That is one exported dictionary, and it is why the four canister models in 3D-Models
# (CD_Canister_Air / _Empty / _Shit / _Beer) can be one prop scene rather than four. It is also
# the cheapest possible version of the tone this game is going for: solving one problem hands
# you the next one, as an object, in your hands.

## Emitted when this is spent on a silo. `became` is &"" if it was used up entirely.
signal spent(was: StringName, became: StringName)
## Emitted whenever `kind` changes, so a scene can swap which model is showing.
signal kind_changed(kind: StringName)

## Every consumable is in this group, so a silo (or a test) can find them without paths.
const GROUP_CONSUMABLE := &"consumables"

## What this currently is. The ONLY thing a Silo matches on. Free-form by design — a new
## supply type is a new string, not an enum edit and a recompile.
@export var kind: StringName = &"o2"

## How much of a silo's 0..1 level one of these is worth. Canisters are deliberately worth
## less than a full silo: the interesting question is "how many trips is this worth?", and a
## one-canister-fills-it silo never asks it.
@export var amount: float = 0.5

## kind -> what this turns into once spent as that kind. A kind missing from the table (or
## mapped to &"") is used up entirely and leaves the world — food, and a spare part.
##
## Held on the item rather than on the silo because it is a property of the OBJECT: an empty
## canister is an empty canister whichever silo emptied it.
@export var becomes: Dictionary = {}

## kind -> NodePath of the model to show for it. Same technique as RepairPoint's state visuals,
## for the same reason: one scene that looks like four things beats four near-identical scenes.
@export var kind_models: Dictionary = {}

## Set once this has been used up entirely and is waiting to be freed.
var is_spent: bool = false


func _ready() -> void:
	super()  # Interactable._ready: register in the interactables group
	add_to_group(GROUP_CONSUMABLE)
	interaction_type = InteractionType.PICKUP
	if interaction_text == "":
		interaction_text = "Pick up %s" % kind
	_refresh_model()


## Does this service a silo asking for `wanted`?
func matches(wanted: StringName) -> bool:
	return not is_spent and wanted != &"" and kind == wanted


## Spend one use of this on a silo. Returns TRUE if the item survives (it turned into something
## else and is still in the player's hands), FALSE if it was used up and should be freed.
##
## The caller decides what to do with a `false` — Silo reports it through
## `Interactable.consumed_last_item()`, which is the hook Interactor already uses to take a
## fitted spare part out of the player's hands.
func spend() -> bool:
	if is_spent:
		return false
	var was := kind
	var next: StringName = becomes.get(kind, &"")
	if next == &"":
		is_spent = true
		is_enabled = false
		spent.emit(was, &"")
		return false
	kind = next
	interaction_text = "Pick up %s" % kind
	_refresh_model()
	spent.emit(was, next)
	kind_changed.emit(kind)
	return true


## Force this to be a different thing. For spawning one canister scene as any of its kinds.
func set_kind(new_kind: StringName) -> void:
	if kind == new_kind:
		return
	kind = new_kind
	interaction_text = "Pick up %s" % kind
	_refresh_model()
	kind_changed.emit(kind)


## Show the model for the current kind and hide the rest. A scene with no `kind_models` (one
## model, one kind) is left alone rather than blanked.
func _refresh_model() -> void:
	if kind_models.is_empty():
		return
	for key in kind_models:
		var node := get_node_or_null(kind_models[key]) as Node3D
		if node != null:
			node.visible = key == kind
