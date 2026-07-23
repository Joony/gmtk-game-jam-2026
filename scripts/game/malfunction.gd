class_name Malfunction
extends Node3D

# One ship system that can break, placed in the world at the spot you have to walk to.
# The node IS the location: its repair panels are children, so "where is the fault" and
# "where do I fix it" can never drift apart.
#
# Everything about a fault's character is DATA, not code: how much speed it costs, whether
# it makes you breathe faster, when it fires, and what each of the two repair routes costs.
# Adding a fifth system is a node in game.tscn, not a new script — the same reasoning that
# made LightingController.MODES a dictionary.
#
# The two repair routes are the whole of TODO 12d's "multiple solutions with consequences",
# and they cost nothing extra to support because Interactable already has both paths:
#
#   interact()        -> PATCH. Free, instant, but expires after `bodge_distance` and the
#                        fault comes back at the same place with the same sound.
#   use_with_item()   -> PROPER. Costs the walk to fetch a spare part, and is permanent.
#
# Consequences are also data. `bodge_oxygen_cost` is the "vent air to solve it" branch
# (smother the fire, repressurise the section); `repair_oxygen_bonus` is the scrubber
# paying out recovered reserve, which is what makes a long fetch worth considering.

## A CRITICAL fault trips the ship-wide red alert; a DEGRADING one just bleeds speed.
enum Severity { DEGRADING, CRITICAL }

## Emitted whenever the fault breaks — first time or a patch giving out.
signal broke(malfunction: Malfunction, was_patch_failure: bool)
signal repaired(malfunction: Malfunction, permanent: bool)

const GROUP_MALFUNCTION := &"malfunctions"

@export var system_name: String = "SYSTEM"
## Short line for the HUD list, e.g. "coolant loop ruptured".
@export var fault_text: String = "fault detected"
@export var severity: Severity = Severity.DEGRADING

## Fraction of cruise speed lost while this is active. Penalties add up across faults.
@export_range(0.0, 1.0) var speed_penalty: float = 0.3
## Multiplies the oxygen drain while active — the scrubber fault's whole point. 1.0 = no effect.
@export var oxygen_drain_multiplier: float = 1.0

## Distance remaining (million miles) at which this first breaks. 0 = never fires alone.
@export var fire_at_distance: float = 0.0

## How far a patch holds before it gives out, in millions of miles. Measured in DISTANCE,
## not seconds, so that time spent in stasis burns through it too — otherwise patching then
## sleeping would be strictly free and the choice would evaporate.
@export var bodge_distance: float = 25.0
## Oxygen (seconds) spent the moment you patch this. The "spend a resource" branch.
@export var bodge_oxygen_cost: float = 0.0
## Oxygen (seconds) recovered by a PROPER fix only. Rewards the fetch.
@export var repair_oxygen_bonus: float = 0.0

var is_active: bool = false
## True while running on a patch — drives the amber panel light and the HUD warning.
var is_patched: bool = false
var has_ever_fired: bool = false
## Times this fault has broken, including patch failures. For the end-of-run summary.
var break_count: int = 0

var _patch_expires_at: float = 0.0
## Last distance RunState reported. Lets a repair triggered from a panel schedule its own
## patch expiry without the panel needing to know RunState exists.
var _distance_now: float = 0.0


func _ready() -> void:
	add_to_group(GROUP_MALFUNCTION)
	for child in get_children():
		if child is RepairPoint:
			(child as RepairPoint).bind(self)
	_refresh_points()


## Break it. `distance_remaining` is only used to schedule a patch's expiry.
func break_now(was_patch_failure: bool = false) -> void:
	if is_active:
		return
	is_active = true
	is_patched = false
	has_ever_fired = true
	break_count += 1
	_patch_expires_at = 0.0
	_refresh_points()
	broke.emit(self, was_patch_failure)


## Fix it. `permanent` distinguishes a fitted spare part from a patch.
## `distance_remaining` sets when a patch will give out; ignored for a proper fix.
func repair(permanent: bool, distance_remaining: float = -1.0) -> void:
	if not is_active:
		return
	var distance := distance_remaining if distance_remaining >= 0.0 else _distance_now
	is_active = false
	is_patched = not permanent
	_patch_expires_at = maxf(distance - bodge_distance, 0.0) if is_patched else 0.0
	_refresh_points()
	repaired.emit(self, permanent)


## Called every frame by RunState. Fires the initial break and expires patches.
func advance(distance_remaining: float) -> void:
	_distance_now = distance_remaining
	if is_active:
		return
	if not has_ever_fired and fire_at_distance > 0.0 and distance_remaining <= fire_at_distance:
		break_now(false)
		return
	# A patch that runs out breaks the SAME fault at the SAME panel, deliberately: the
	# player has to be able to recognise it as their own earlier choice rather than
	# read it as fresh bad luck.
	if is_patched and distance_remaining <= _patch_expires_at:
		break_now(true)


## Speed cost right now. A patch restores full speed — the cost of patching is that it
## expires, not that it works badly. One consequence per choice is easier to read.
func active_speed_penalty() -> float:
	return speed_penalty if is_active else 0.0


func active_oxygen_multiplier() -> float:
	return oxygen_drain_multiplier if is_active else 1.0


func is_critical() -> bool:
	return is_active and severity == Severity.CRITICAL


## Distance the current patch has left, or 0 if not patched.
func patch_margin(distance_remaining: float) -> float:
	if not is_patched:
		return 0.0
	return maxf(distance_remaining - _patch_expires_at, 0.0)


func _refresh_points() -> void:
	for child in get_children():
		if child is RepairPoint:
			(child as RepairPoint).refresh()
