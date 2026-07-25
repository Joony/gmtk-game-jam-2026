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
#   interact()        -> PATCH. Instant, but expires after `bodge_distance` and the fault
#                        comes back at the same place with the same sound. Needs the hammer.
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
## What the ship computer announces when this breaks — a key in AudioController.VOICE_LINES,
## blank for a fault it says nothing about. Data like everything else here, so giving a system
## a voice is one field in game.tscn rather than a branch in Game.
@export var vo_line: StringName = &""
@export var severity: Severity = Severity.DEGRADING

## Speed this fault costs, as a fraction of cruise. Penalties add up across faults.
##
## For a DEGRADING fault this applies the moment it breaks and lifts the moment it is dealt
## with, either way. For a CRITICAL one it is the CEILING of a ramp: see speed_decay_per_day.
@export_range(0.0, 1.0) var speed_penalty: float = 0.3
## CRITICAL faults only: how much of `speed_penalty` accrues per elapsed DAY while broken.
## 0 keeps the old behaviour — the whole penalty, instantly.
##
## Days rather than distance, and days rather than real seconds, for two separate reasons.
## Distance would be self-limiting: the drive slows, so distance accrues slower, so the decay
## slows, and the ramp asymptotes short of its own ceiling instead of biting. Real seconds
## would ignore stasis entirely, and sleeping through a failing drive is exactly the play this
## has to punish — the ship's clock runs at `stasis_time_scale` in the pod, so it does.
@export var speed_decay_per_day: float = 0.0
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
## Speed lost to this fault SO FAR, 0..speed_penalty. Only CRITICAL faults accumulate it.
##
## This is the thing a patch does and does not do: it stops the number growing, and it leaves
## it exactly where it stands. Only fitting a spare part puts it back to zero. That is the
## whole trade — bang it flat now and carry the loss for the rest of the run, or go and fetch
## the part and keep bleeding speed for the length of the walk to get it all back.
var speed_decay: float = 0.0
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
	# A patch leaves `speed_decay` standing: it stops the bleed, it does not undo it. Only a
	# fitted part gives the drive back, which is what stops the patch being the obvious answer
	# every time and makes the spare worth the walk.
	if permanent:
		speed_decay = 0.0
	_patch_expires_at = maxf(distance - bodge_distance, 0.0) if is_patched else 0.0
	_refresh_points()
	repaired.emit(self, permanent)


## Called every frame by RunState. Fires the initial break, bleeds speed away while broken,
## and expires patches. `days` is the ship time elapsed since the last call — already scaled
## by stasis, so an hour in the pod costs what an hour in the pod is worth.
func advance(distance_remaining: float, days: float = 0.0) -> void:
	_distance_now = distance_remaining
	if is_active:
		if severity == Severity.CRITICAL and speed_decay_per_day > 0.0:
			speed_decay = minf(speed_decay + speed_decay_per_day * days, speed_penalty)
		return
	if not has_ever_fired and fire_at_distance > 0.0 and distance_remaining <= fire_at_distance:
		break_now(false)
		return
	# A patch that runs out breaks the SAME fault at the SAME panel, deliberately: the
	# player has to be able to recognise it as their own earlier choice rather than
	# read it as fresh bad luck.
	if is_patched and distance_remaining <= _patch_expires_at:
		break_now(true)


## Speed cost right now, which is two different things depending on how bad the fault is.
##
## A DEGRADING fault is a flat toll while it is broken, lifted by either repair route. It is
## an annoyance you clear, and it reads as one.
##
## A CRITICAL fault BLEEDS: `speed_decay` climbs toward `speed_penalty` for as long as the
## fault stands, and it keeps whatever it has taken through a patch. So the number here does
## not depend on `is_active` at all for a critical — a patched drive is still down however far
## it had got before you hit it, and only a fitted part clears the debt.
##
## Ramping rather than applying the whole penalty at once is what puts a price on TIME. A flat
## penalty made the two routes trivial to compare: both cleared it, so the patch was free and
## the spare part was only ever for the second failure. Now the walk to fetch the part costs
## real speed while you make it, and the patch's price is that you never get that speed back.
func active_speed_penalty() -> float:
	if severity == Severity.CRITICAL and speed_decay_per_day > 0.0:
		return speed_decay
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
