class_name Need
extends Node

# A countdown on the PLAYER rather than on the ship: CO2 in your blood, hunger, thirst,
# bladder. Hits zero and something happens — narcosis, or a stagger, or an indignity.
#
# The ship's own countdowns already exist and are not this. Distance and oxygen live in
# RunState; a fault's decay lives in Malfunction. What is new here is that satisfying one of
# these can START another (see `triggers`), which is TODO 17c's chain and the reason the
# section is worth building at all: drink the beer, and now you need the toilet.
#
# TIME IS AWAKE SECONDS, and that is the single most important decision in this file.
#
#   * Not real seconds — a need that ticks in the pod kills a player who did the correct thing
#     and slept through a long haul, and 17e settles that it must not.
#   * Not ship days, unlike Malfunction.speed_decay. A fault degrades on the ship's clock
#     because a drive keeps failing while you sleep; a body does not get hungry in stasis.
#
# So the unit is the same one oxygen uses, which means the player can compare them directly:
# "180 seconds of CO2" and "240 seconds of air" are the same kind of number, and budgeting one
# trip against the other is arithmetic they can actually do.
#
# NOT EVERY NEED RUNS. `active` is false by default, and RunState turns on only the one or two
# a given run is going to use (TODO 17d: stagger, don't stack). Six needs at once do not fit in
# 240 seconds of air — measured, not guessed — so the staggering is not polish, it is the thing
# that makes the section shippable.

## Emitted every tick, for the HUD row.
signal changed(need: Need, remaining: float, total: float)
## Emitted once, the first time this drops past `warn_at`. What puts the row on the HUD:
## the readout grows as things get bad rather than shipping nine dials from the start (17e).
signal warned(need: Need)
## Emitted when it hits zero. `lethal` says whether the caller should end the run over it.
signal expired(need: Need)
## Emitted when it is satisfied, carrying `triggers` so the owner can start the next link in
## the chain. Need does NOT look that need up itself — it has no business knowing about the
## others, and the set that owns them does.
signal satisfied(need: Need, triggers: StringName)

const GROUP_NEED := &"needs"

@export var id: StringName = &"co2"
## Shown on the HUD row. Short — it sits next to OXYGEN and ARRIVAL.
@export var display_name: String = "CO2"
## Line the ship computer says when this starts, or &"" for silence. Data, exactly like
## Malfunction.vo_line, so giving a need a voice is a field and not a branch.
@export var vo_line: StringName = &""

## The full fuse, in AWAKE seconds. Long by default: 17d chose long fuses precisely so one
## supply run services a need for a good while instead of becoming a treadmill.
@export var seconds: float = 180.0
## Fraction remaining at which `warned` fires and the HUD row appears.
@export_range(0.0, 1.0) var warn_at: float = 0.4
## Does reaching zero end the run? Only CO2 narcosis and the crap silo explode-you (17e) —
## everything else degrades, because nine countdowns each able to kill is a bad ending screen.
@export var lethal: bool = false
## What the end screen calls it when this is what killed you. The need knows what its own
## death is named; RunState should not carry a table of them.
@export var fatal_title: String = "DEAD"
@export var fatal_text: String = ""

## `Silo.silo_id` of the silo that services this. Looked up by id rather than NodePath so the
## wiring survives the scene being rearranged — the same reason Malfunction uses a group.
@export var silo_id: StringName = &""
## `id` of the need that satisfying THIS one starts. The chain: thirst -> bladder.
@export var triggers: StringName = &""

## Whether this need is in play at all this run. Off by default — see the staggering note above.
var active: bool = false
var remaining: float = 0.0
var has_expired: bool = false

var _warned: bool = false


func _ready() -> void:
	add_to_group(GROUP_NEED)
	remaining = seconds


## Put it in play, full. Idempotent, so the chain can fire `start()` on a bladder that is
## already running without resetting it and quietly making the beer free.
func start() -> void:
	if active:
		return
	active = true
	has_expired = false
	_warned = false
	remaining = seconds
	changed.emit(self, remaining, seconds)


## Take it out of play entirely, e.g. a need this run is not using.
func stop() -> void:
	active = false


## Reset the fuse — ate the food, drank the beer, used the toilet, breathed clean air.
## Emits `satisfied` carrying `triggers`, which is where the chain is picked up.
func satisfy() -> void:
	remaining = seconds
	has_expired = false
	_warned = false
	changed.emit(self, remaining, seconds)
	satisfied.emit(self, triggers)


## Run the clock down. Called by RunState with the frame delta, and ONLY while awake — the
## guard lives with the caller, which already knows about `in_stasis`, rather than being a
## RunState reference reached back through from here.
func advance(delta: float) -> void:
	if not active or has_expired or delta <= 0.0:
		return
	remaining = maxf(remaining - delta, 0.0)
	changed.emit(self, remaining, seconds)
	if not _warned and fraction() <= warn_at:
		_warned = true
		warned.emit(self)
	if remaining <= 0.0:
		has_expired = true
		expired.emit(self)


## 0..1 left on the clock. 1 is fine, 0 is out of time.
func fraction() -> float:
	if seconds <= 0.0:
		return 0.0
	return clampf(remaining / seconds, 0.0, 1.0)


## Should this have a row on the HUD yet? False until it has gone past `warn_at`, so the
## readout starts clean and fills up as the run goes wrong.
func is_pressing() -> bool:
	return active and _warned
