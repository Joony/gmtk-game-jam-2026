class_name LostAndFound
extends Node

# Nothing the player can carry may leave the ship forever.
#
# THE BUG. The floor is a 0.2m slab and it is not too thin: tests/diag_floor_escape.gd slams
# every prop into it at up to 120 m/s and at the doorway seams without a single loss —
# `continuous_cd` on the prop scenes holds. What loses items is DEPENETRATION. A body that is
# already inside the slab when physics takes it over gets resolved to the nearest face, and past
# roughly the slab's midplane the nearest face is the underside. Measured threshold: about
# 0.15m of penetration for every prop, and less for the canister, whose collider hangs below its
# origin. Once through there is nothing below the ship at all, so it falls for ever.
#
# WHY A NET AND NOT ONLY A CAUSE FIX. Carry now refuses to release a body inside geometry, which
# is the cause we found. This is the backstop for the ones we did not: a physics engine will
# always find a way to put something a metre it should not be, and the cost here is not cosmetic
# — the run is balanced at thirteen spares against roughly forty-seven repairs, and the
# canisters ARE the oxygen. One canister lost under a doorway can quietly make a run
# unwinnable, with no feedback of any kind.
#
# The sweep is deliberately dumb and total: everything in the `interactables` group that is a
# RigidBody3D, once a second. That is a couple of dozen nodes and an origin comparison.

## Below this Y a body has left the ship. The floor's underside is at -0.2, and a prop resting
## in a doorway can dip a few centimetres, so this is comfortably clear of both.
const FLOOR_ESCAPE_Y := -0.5

## How high above the floor a recovered item is re-seated. Enough that the item's own collider
## clears the slab whatever its origin convention, without being a visible drop from mid-air.
const RESEAT_HEIGHT := 0.4

## Seconds between sweeps. An item that has left the ship is not coming back on its own, so
## this only decides how quickly the player sees it reappear — not whether it is caught.
@export var sweep_interval: float = 1.0

## Emitted for anything recovered, so a test can prove the net fires rather than inferring it
## from a position that might never have moved.
signal recovered(item: Node3D, from: Vector3, to: Vector3)

var _ship: RoomBuilder = null
var _player: Node3D = null
var _timer: float = 0.0
## Every recovery this run, for the log and for the tests.
var _rescues: int = 0


func bind(ship: RoomBuilder, player: Node3D) -> void:
	_ship = ship
	_player = player


func rescues() -> int:
	return _rescues


func _process(delta: float) -> void:
	_timer += delta
	if _timer < sweep_interval:
		return
	_timer = 0.0
	sweep()


## Public so tests can run it on demand rather than waiting out the interval.
func sweep() -> void:
	var held := _held_items()
	for node in get_tree().get_nodes_in_group(&"interactables"):
		var body := node as RigidBody3D
		if body == null or not is_instance_valid(body):
			continue
		if body.global_position.y >= FLOOR_ESCAPE_Y:
			continue
		# A carried item's transform is authored every render frame from the hold point, so
		# moving it here would be overwritten within the frame and fight Carry for no gain.
		# It also cannot be lost while held — the hold point rides the camera.
		if body in held:
			continue
		_recover(body)


func _held_items() -> Array:
	var out := []
	for node in get_tree().get_nodes_in_group(&"carries"):
		var carry := node as Carry
		if carry != null and carry.is_holding():
			out.append(carry.held_item())
	return out


## Put it back on the floor of the room it fell through. Ignoring Y is exactly right here —
## `room_at` answers "which room is this X/Z over", which is the question, since the item is
## below the deck by the time we are asked.
##
## An item that went through near the hull is over no room at all, and there is nowhere sensible
## to put it back; those go to the player's feet. That is the less elegant answer and the one
## that cannot fail, which for the thing standing between the player and a winnable run is the
## right trade.
func _recover(body: RigidBody3D) -> void:
	var from := body.global_position
	var to := Vector3(from.x, RESEAT_HEIGHT, from.z)
	if _ship == null or _ship.room_at(from) == "":
		if _player != null:
			to = _player.global_position + Vector3(0.0, RESEAT_HEIGHT, 0.0)
		elif _ship != null:
			# No player either (a headless fixture): the hub is somewhere real.
			to = Vector3(0.5, RESEAT_HEIGHT, 8.0)

	# Freeze before placing. A live RigidBody3D ignores a written transform — the physics server
	# owns it and puts it straight back — which is the same trap CanisterSilo._mount() hit.
	var was_frozen := body.freeze
	body.freeze = true
	body.global_position = to
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.freeze = was_frozen
	body.reset_physics_interpolation()

	_rescues += 1
	# A warning rather than silence: the player is not told (as far as they are concerned the
	# grav plating caught it), but a recovery means something upstream let a body through the
	# deck, and that should be findable in a log rather than invisible.
	push_warning("LostAndFound: recovered %s from %v to %v" % [body.name, from, to])
	recovered.emit(body, from, to)
