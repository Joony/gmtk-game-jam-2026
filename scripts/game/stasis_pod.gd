class_name StasisPod
extends Interactable

# The loop anchor. Climbing in stops your oxygen bleed and fast-forwards the journey
# until something goes wrong.
#
# The pod does NOT refill air — deliberately, and it is the single most important rule in
# the design. If it refuelled you, every problem would reduce to "walk back and top up",
# the air budget would stop being a budget, and the whole run would lose its spine. It is
# a stop button on the bleed, nothing more. So the air you have at minute one is the air
# you have for the entire run, and every excursion is priced at *there and back*.
#
# That also makes the pod's distance from the engine room a primary tuning knob rather
# than set dressing: moving it two rooms further away raises the price of every repair
# in the game at once.

signal entered
signal exited

@export var enter_text: String = "Enter stasis pod"

var occupied: bool = false


func _ready() -> void:
	super()
	interaction_type = InteractionType.ACTIVATE
	interaction_text = enter_text


func get_interaction_text(_held_item: Node3D = null) -> String:
	# You cannot look at the pod from inside it, so there is no "exit" prompt here —
	# leaving is driven by the stasis overlay.
	return enter_text


# Climbing into a pod with a crate under your arm should not silently eat the crate,
# and mid-repair is exactly when a player might wander back. Let them in regardless;
# Game drops what they are carrying.
func can_act_on(_held_item: Node3D = null) -> bool:
	return is_enabled and not occupied


func set_occupied(value: bool) -> void:
	if occupied == value:
		return
	occupied = value
	if occupied:
		entered.emit()
	else:
		exited.emit()
