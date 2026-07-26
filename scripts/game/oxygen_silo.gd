class_name OxygenSilo
extends Interactable

# The life-support tank (TODO 21e). NOT a level you draw down — a SOCKET holding one canister,
# and swapping that canister is what puts air back in the ship.
#
# WHY THIS IS NOT A `Silo`. Every other tank on the ship is a 0..1 number with a `use()` and a
# `service()`: you take a quarter of it, you top it up. This one holds a physical object the
# player can see from the doorway, and the object is the state — full canister, spent canister,
# empty cradle. Modelling that as a float and then trying to keep a mesh in sync with it would
# be two sources of truth for the thing the player is actually looking at.
#
# It also feeds a different number. The others clear a `Need`; this one refills the RUN'S OWN
# OXYGEN — the single budget the whole game is priced in. So there is no countdown of its own
# to keep: `RunState.oxygen_remaining` is the countdown, and this is how you add to it.
#
# THE SWAP IS ONE-WAY, and it happens the instant the canister goes in. A fresh one dumps its
# air into the ship and is EMPTY from that moment — it does not sit there slowly draining. So
# what is in the cradle is always a spent canister, which is why the ship starts with one in it:
# the very first thing the player sees is the object they will be replacing, in the place they
# will be replacing it, before it matters.
#
# `fit()` refuses an empty, so a spent canister can come out but never go back. That is what
# stops the fix being free — the cargo bay holds a finite number of full ones, and every one you
# burn is gone.

## Emitted when a fresh canister goes in, carrying how much air it was worth.
signal recharged(seconds: float)

## Named empties inside CD_Silo_Base_v1.1: where the canister sits, and where the light goes.
const SOCKET_NAME := &"Socket"

## Seconds of air a full canister is worth. Generous against the 240 s budget, because the walk
## to the cargo bay and back is most of a minute of it — a canister that barely paid for its own
## fetch would make the trip pointless.
@export var seconds_per_canister: float = 150.0
## Air remaining, in seconds, below which the tank is calling for a new canister. Matches the
## HUD's own `oxygen_warning` band so the two never disagree about what "low" means.
@export var low_air_seconds: float = 60.0
## What the fitted canister looks like once it is spent.
@export var spent_kind: StringName = &"empty"
## Seconds the canister stays looking full after it goes in, before it reads as spent.
##
## The air is in the ship immediately — the HUD says so the moment you press. This is purely
## the beat that makes the transfer legible: seat a full bottle, watch it discharge, and the
## empty you are now holding responsible for is the same object you just fitted. Switching the
## model on the same frame made it look like the canister had been empty all along.
@export var discharge_seconds: float = 1.0
@export var accepts: StringName = &"o2"
@export var display_name: String = "LIFE SUPPORT"

var _run: RunState = null
var _fitted: Consumable = null
var _socket: Node3D = null
var _indicator: IndicatorLight = null


## Attach this to a silo prop already standing in the scene, then bind it. Mirrors Silo.setup()
## for the same reason: the script goes on at runtime and Godot does not re-run _ready().
func setup() -> void:
	add_to_group(&"interactables")
	interaction_type = InteractionType.USE_ITEM
	_socket = _find_named(self, SOCKET_NAME)
	if _socket == null:
		push_warning("OxygenSilo: %s has no `%s` empty to hold a canister" % [name, SOCKET_NAME])
	if _indicator == null:
		_indicator = IndicatorLight.attach(self)
	refresh()


func bind(run: RunState) -> void:
	_run = run
	if not run.oxygen_changed.is_connected(_on_oxygen_changed):
		run.oxygen_changed.connect(_on_oxygen_changed)
	refresh()


## True when the ship is low enough on air that the fitted canister has nothing left to give.
func is_low() -> bool:
	return _run != null and _run.oxygen_remaining <= low_air_seconds


func fitted() -> Consumable:
	return _fitted


## Put a canister in the cradle. Fresh ones are worth their air; a spent one is refused, which
## is what makes the swap one-way.
func fit(canister: Consumable) -> bool:
	# No run needed to HOLD a canister — only to turn one into air. ShipSupplies fits the
	# starting canister while building the ship, before RunState exists, and requiring a run
	# here left the cradle empty for the whole game.
	if canister == null or not canister.matches(accepts):
		return false
	# ONE AT A TIME, guarded here and not only in the interaction path. Blocking it in
	# `_servicer()` alone stopped the prompt but not the method, so anything calling `fit()`
	# directly still displaced what was in the cradle and dropped it on the floor behind the
	# player. The rule belongs with the thing it is a rule about.
	if _fitted != null and is_instance_valid(_fitted):
		return false
	_mount(canister)

	if _run != null:
		var was := _run.oxygen_remaining
		_run.oxygen_remaining = minf(was + seconds_per_canister, _run.oxygen_total)
		_run.oxygen_changed.emit(_run.oxygen_remaining, _run.oxygen_total)
		recharged.emit(_run.oxygen_remaining - was)
	_discharge(canister)
	refresh()
	return true


## Let the canister read as full for a beat, then switch it to the empty model.
##
## Deliberately NOT conditional on it still being in the cradle when the timer comes round: the
## air went into the ship the moment it was fitted, so a canister yanked straight back out is
## still a spent one. Anything else would be a free refill for anyone quick enough.
func _discharge(canister: Consumable) -> void:
	if discharge_seconds <= 0.0:
		canister.set_kind(spent_kind)
		return
	await get_tree().create_timer(discharge_seconds).timeout
	if is_instance_valid(canister):
		canister.set_kind(spent_kind)
		refresh()


## Put a canister in the cradle WITHOUT it being worth anything — for the spent one the ship
## starts with. Separate from `fit()` because that one is the player's action and always costs
## a full canister; this is set dressing that happens to be functional.
func install_spent(canister: Consumable) -> void:
	if canister == null:
		return
	canister.set_kind(spent_kind)
	_mount(canister)
	refresh()


## Take the spent canister out and leave it loose beside the tank. It keeps its empty model, so
## it is visibly no use — and `fit()` refuses it, so it can never go back in.
func take_out() -> Consumable:
	var out := _fitted
	_eject()
	refresh()
	return out


## The lamp only. The canister's own model is set once, when it goes in, and is never rewritten
## from here — the cradle always holds a spent one, so there is nothing to keep in step.
func refresh() -> void:
	if _indicator != null:
		_indicator.set_state(
			IndicatorLight.COLOR_WARN if is_low() else IndicatorLight.COLOR_OK, false)


# --- interaction -------------------------------------------------------------

func get_interaction_type(held_item: Node3D = null) -> InteractionType:
	if not is_enabled:
		return InteractionType.DISABLED
	return InteractionType.USE_ITEM if _servicer(held_item) != null else InteractionType.ACTIVATE


func can_act_on(held_item: Node3D = null) -> bool:
	if not is_enabled:
		return false
	# Only ever actionable with a canister in hand: the tank itself is not something you press.
	return held_item != null and _servicer(held_item) != null


func get_interaction_text(held_item: Node3D = null) -> String:
	if _servicer(held_item) != null:
		return "Fit the O2 canister"
	# Naming what is in the way. "No use here" while holding exactly the right thing would be
	# the game lying to the player.
	if held_item != null and _fitted != null and (held_item as Consumable) != null:
		return "%s: take the spent canister out first" % display_name
	if held_item != null:
		return "%s: %s is no use here" % [display_name, held_item.name]
	if _fitted == null:
		return "%s: empty cradle — fit an O2 canister" % display_name
	if is_low():
		return "%s: air low — fit a fresh O2 canister" % display_name
	return "%s: nominal" % display_name


func interact() -> void:
	# Nothing empty-handed. Taking the canister out is done by reaching for the CANISTER, which
	# is sitting right there and is its own interactable — two ways to do one thing would be
	# two prompts fighting over the same press.
	pass


func use_with_item(item: Node3D) -> void:
	var canister := _servicer(item)
	if canister == null:
		return
	if fit(canister):
		used_with_item.emit(self, item)


## FALSE, deliberately. Interactor reads this as "the item was used up", and acts on it by
## dropping AND `queue_free()`ing whatever was in your hands — which is right for a spare part
## welded into a panel and catastrophic here: the canister has just been seated in the cradle,
## and freeing it made it vanish the instant it went in.
##
## `fit()` releases the player's grip itself instead, so the canister leaves their hands and
## survives.
func consumed_last_item() -> bool:
	return false


func can_use_with_item(item: Node3D) -> bool:
	return _servicer(item) != null


# --- internals ---------------------------------------------------------------

## The held item viewed as a canister this cradle will accept — which means nothing at all
## while there is already one in it. You take the spent one out and THEN put a fresh one in;
## letting a fit displace what is already there would make "remove the old one" a step the
## player never has to think about, and quietly drop a canister on the floor behind them.
func _servicer(item: Node3D) -> Consumable:
	if _fitted != null and is_instance_valid(_fitted):
		return null
	var canister := item as Consumable
	if canister == null or not canister.matches(accepts):
		return null
	return canister


func _on_oxygen_changed(_remaining: float, _total: float) -> void:
	refresh()


## Drop whatever is in the cradle beside the tank, carryable again.
func _eject() -> void:
	if _fitted == null or not is_instance_valid(_fitted):
		_fitted = null
		return
	var body := _fitted as Node3D
	var at := body.global_position
	var parent := body.get_parent()
	if parent != null:
		parent.remove_child(body)
	get_parent().add_child(body)
	body.global_position = at + Vector3(0.0, 0.0, 0.45)
	body.scale = Vector3.ONE
	_hold(_fitted, false)
	_fitted = null


## Freeze a canister while it is in the cradle — a rigid body left simulating would fall out of
## it — but leave it INTERACTABLE. It is a thing sitting on a shelf, and reaching for it is the
## obvious way to take it: disabling it made the bottle in front of the player the one object in
## the room they could not touch, and forced the whole swap through the tank behind it.
##
## Picking it up is the removal. `picked_up` is what tells the silo the cradle is empty now, so
## there is no second "take it out" path to keep in step with this one.
func _hold(canister: Consumable, held: bool) -> void:
	canister.is_enabled = true
	var body := canister as Node
	if body is RigidBody3D:
		(body as RigidBody3D).freeze = held
	if held:
		if not canister.picked_up.is_connected(_on_fitted_picked_up):
			canister.picked_up.connect(_on_fitted_picked_up)
	elif canister.picked_up.is_connected(_on_fitted_picked_up):
		canister.picked_up.disconnect(_on_fitted_picked_up)


## The player has lifted the canister straight out of the cradle. Hand it back to the world:
## left parented to the socket it would ride the tank around and stay at the tank's dressing,
## so a 1.12 m bottle would follow the player about instead of the 0.90 m one they should have.
func _on_fitted_picked_up(_interactable: Interactable) -> void:
	var canister := _fitted
	if canister == null or not is_instance_valid(canister):
		return
	_fitted = null
	if canister.picked_up.is_connected(_on_fitted_picked_up):
		canister.picked_up.disconnect(_on_fitted_picked_up)
	var body := canister as Node3D
	var at := body.global_position
	if body.get_parent() != null:
		body.get_parent().remove_child(body)
	get_parent().add_child(body)
	body.global_transform = Transform3D(Basis.IDENTITY, at)
	refresh()


static func _find_named(node: Node, wanted: StringName) -> Node3D:
	if node.name == wanted:
		return node as Node3D
	for child in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null


## Seat a canister in the cradle, whatever it is worth.
func _mount(canister: Consumable) -> void:
	_eject()
	_fitted = canister
	if _socket == null:
		_hold(canister, true)
		return
	var body := canister as Node3D
	if body.get_parent() != null:
		body.get_parent().remove_child(body)
	_release_from_carry(body)
	_socket.add_child(body)
	# FREEZE FIRST, then place it. A canister is a RigidBody3D, and a live one ignores whatever
	# local position you hand it — the physics server owns its transform and puts it straight
	# back. That is why the first version left it sitting on the floor beside the tank instead
	# of in the cradle, however carefully the local offset was worked out.
	_hold(canister, true)
	# SAME DRESSING AS THE SILO, which is not the same thing as inheriting the silo's scale.
	# Both are .blend models dressed into the ship: the silo at 0.25, the canister prop at
	# 0.2004. Matching them means putting the CANISTER MODEL at 0.25 too — so the prop ends up
	# a little OVER its carried size, not a quarter of it.
	#
	# Letting it inherit 0.25 instead multiplied the two together and produced a 22 cm bottle;
	# cancelling the parent scale entirely produced a 90 cm one, which is the carried size and
	# reads slightly small against the tank. This is the middle answer, and it is derived rather
	# than typed, so re-dressing either prop keeps them in step.
	var factor := _dressing_factor(canister)
	body.global_transform = Transform3D(
		_socket.global_transform.basis.orthonormalized().scaled(Vector3.ONE * factor),
		_socket.global_position + Vector3.UP * _half_height(canister) * factor)
	body.reset_physics_interpolation()


## Half a canister's height, from its own collider.
static func _half_height(canister: Consumable) -> float:
	for child in (canister as Node).get_children():
		if child is CollisionShape3D:
			var shape := (child as CollisionShape3D).shape
			if shape is CylinderShape3D:
				return (shape as CylinderShape3D).height * 0.5
			if shape is BoxShape3D:
				return (shape as BoxShape3D).size.y * 0.5
	return 0.45


## Let go of it, if the player was holding it.
##
## Searched for rather than walked up to: Carry does NOT reparent what it holds — it freezes
## the body and moves it to the hold point each frame — so the canister's parent is still
## wherever it was lying, and climbing the tree from it never reaches the player. That is why
## the canister stayed glued to the player's hands after being seated.
func _release_from_carry(body: Node3D) -> void:
	var carry := _find_carry_holding(get_tree().current_scene, body)
	if carry != null:
		carry.drop(false)


static func _find_carry_holding(node: Node, body: Node3D) -> Carry:
	if node == null:
		return null
	if node is Carry and (node as Carry).held_item() == body:
		return node as Carry
	for child in node.get_children():
		var found := _find_carry_holding(child, body)
		if found != null:
			return found
	return null


## How much to scale a canister so its MODEL is dressed at the same figure the silo's is.
##
## The silo's own world scale is what the .blend is dressed at, because the script is attached
## straight to the dressed prop. A canister is a prop scene whose Model child carries its own
## scale, so the two are only comparable once that inner figure is divided out.
func _dressing_factor(canister: Consumable) -> float:
	var silo_dressing: float = maxf(global_transform.basis.get_scale().y, 0.0001)
	var model := (canister as Node).get_node_or_null(^"Air") as Node3D
	if model == null:
		for child in (canister as Node).get_children():
			if child is Node3D and child.name != "CollisionShape3D":
				model = child as Node3D
				break
	var canister_dressing: float = 0.2004
	if model != null:
		canister_dressing = maxf(model.transform.basis.get_scale().y, 0.0001)
	return silo_dressing / canister_dressing
