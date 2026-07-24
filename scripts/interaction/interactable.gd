class_name Interactable
extends Node3D

# Ported from GMTK 2025 (Player/Interactable.gd). The single concept for "something
# the player can look at and act on" — static panels and carryable props alike.
#
# Attach directly to the node that owns the collider the ray will hit. For a
# carryable prop that means the RigidBody3D itself (legal: RigidBody3D is a Node3D),
# and `get_item_node()` then returns that body for Carry to hold.
#
# Dropped from the 2025 version: `interaction_range` / `interaction_angle`. Detection
# is a camera ray now, so proximity and facing-cone tuning are dead weight — and the
# 2025 code had already commented its own cone check out.

enum InteractionType {
	PICKUP,
	USE_ITEM,
	ACTIVATE,
	DISABLED,
}

@export var interaction_type: InteractionType = InteractionType.ACTIVATE
@export var interaction_text: String = ""
## Shown instead of `interaction_text` when the player is holding an accepted item.
@export var interaction_text_with_item: String = ""
@export var is_enabled: bool = true
## Item names this accepts for USE_ITEM. Empty means "accepts anything".
@export var accepted_item_names: Array[String] = []

signal interacted_with(interactable: Interactable)
signal picked_up(interactable: Interactable)
signal dropped(interactable: Interactable)
signal used_with_item(interactable: Interactable, item: Node3D)


func _ready() -> void:
	add_to_group(&"interactables")


func can_interact(_held_item: Node3D = null) -> bool:
	return is_enabled


## Whether pressing interact right now would actually do something. Drives the green
## reticle: the dot promises "you can act on this", so a PICKUP you have no free hands
## for, or a socket the held item doesn't fit, stays grey while still showing its prompt.
func can_act_on(held_item: Node3D = null) -> bool:
	if not is_enabled:
		return false
	match interaction_type:
		InteractionType.PICKUP:
			return held_item == null
		InteractionType.USE_ITEM:
			return held_item != null and can_use_with_item(held_item)
		_:
			return true


# `held_item` lets a target choose its interaction from what you're carrying — e.g. the battery is
# a PICKUP empty-handed but a USE_ITEM (plug the cable in) while you hold a plug. Most interactables
# ignore it.
func get_interaction_type(_held_item: Node3D = null) -> InteractionType:
	if not is_enabled:
		return InteractionType.DISABLED
	return interaction_type


func get_interaction_text(held_item: Node3D = null) -> String:
	if held_item != null and interaction_type == InteractionType.USE_ITEM:
		if can_use_with_item(held_item):
			return interaction_text_with_item if interaction_text_with_item != "" else interaction_text
		return "Can't use %s here" % held_item.name
	if interaction_type == InteractionType.PICKUP and held_item != null:
		return "Hands full"
	return interaction_text


func can_use_with_item(item: Node3D) -> bool:
	if accepted_item_names.is_empty():
		return true
	return item.name in accepted_item_names


func interact() -> void:
	if can_interact():
		interacted_with.emit(self)


func use_with_item(item: Node3D) -> void:
	if can_interact(item) and can_use_with_item(item):
		used_with_item.emit(self, item)


## Whether the item handed to the last use_with_item() was used up by it. Overridden by
## things that fit a part permanently (see RepairPoint); Interactor checks this instead
## of guessing, so an item is only ever destroyed by a use that genuinely succeeded.
func consumed_last_item() -> bool:
	return false


func on_pickup() -> void:
	picked_up.emit(self)
	# Stop the ray re-targeting the thing already in your hands.
	is_enabled = false


func on_drop() -> void:
	is_enabled = true
	dropped.emit(self)


## Override when the physics body differs from the node holding this script.
func get_item_node() -> Node3D:
	return self
