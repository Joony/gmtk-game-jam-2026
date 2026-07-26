class_name RunState
extends Node

# The countdown. Two of them, actually, and the game is the tension between them:
#
#   DISTANCE  ticks down toward arrival and is the win condition. It falls at the ship's
#             current speed, and every unrepaired fault slows the ship — so ignoring a
#             problem does not cost you a life, it costs you *journey*.
#   OXYGEN    ticks down only while you are out of the pod, at a flat rate, so it is
#             literally "seconds spent outside" and the player can reason about it in
#             seconds. It is one pool for the WHOLE run and it never refills from the pod.
#
# That is what makes the loop work. Stasis is free travel but the ship crawls while broken;
# fixing things costs air you can never get back. So every fault poses one question —
# "is this fix worth the air?" — and the answer genuinely differs depending on how far out
# the fault is, how much speed it costs, and how much air you have left.
#
# Time is scaled, not paused, in stasis: ship time runs up to `stasis_time_scale` faster
# while real time (and therefore nothing that drains oxygen) carries on normally.
# Engine.time_scale would have been the lazy route and would have sped the player's own
# movement up with it. The scale RAMPS rather than jumping — see _start_ramp().
#
# All the balance lives in the exported values below and nowhere else.

signal distance_changed(remaining: float, total: float)
signal oxygen_changed(remaining: float, total: float)
signal stasis_changed(in_stasis: bool)
## Any change to any fault, for the HUD to re-render its list from.
signal systems_changed
## A need starting, being satisfied, crossing its warning line or expiring — the HUD rebuilds
## its need rows off this. Separate from `systems_changed` because a need is not a fault: it
## does not slow the ship and it is not on the repair list.
signal needs_changed
## A fault breaking, separately, because this is the "wake up" beat.
signal alarm(malfunction: Malfunction, was_patch_failure: bool)
signal run_ended(won: bool, summary: Dictionary)

@export_group("Balance")
## Journey length in MILLIONS OF MILES. An interplanetary crossing, so the numbers the
## player reads are millions of miles and days, not metres and seconds.
##
## The journey has its OWN speed model, separate from ShipMotion's metres-per-second. Those
## two were one value at first and could not stay that way: the starfield needs a speed that
## looks right streaming past a window, while the voyage needs one that crosses 82 million
## miles in about a month. RunState owns the voyage and pushes only a 0..1 health fraction
## at ShipMotion, which scales its own visual speed by it.
@export var total_distance: float = 82.0
## Ship speed at full health, in millions of miles per day.
@export var cruise_speed_per_day: float = 2.6
## In-fiction days that pass per real second while awake. Multiplied by stasis_time_scale
## in the pod, so 0.011 x 24 = 0.264 days per second asleep: a 31.5-day crossing takes about
## two minutes of stasis if nothing breaks.
@export var days_per_real_second: float = 0.011
## The entire air budget for the run, in seconds outside the pod.
@export var oxygen_total: float = 240.0
@export var oxygen_drain_rate: float = 1.0
## Drain while in stasis, as a fraction of the normal rate. NOT zero, and that is a
## balance decision the simulation forced: with a free pod, the optimal play was to climb
## in, repair nothing and ride a crippled ship all the way to the destination with the
## entire air budget unspent. Nothing punished ignoring a fault, so there was no decision
## left to make. The pod slows your breathing rather than stopping it, which prices the
## JOURNEY in air too — and so makes ship speed, and therefore every repair, actually matter.
@export_range(0.0, 1.0) var stasis_oxygen_rate: float = 0.35
## Ship seconds per real second while in stasis.
@export var stasis_time_scale: float = 24.0
## Seconds the drive takes to spin up to that, and back down again. The scale used to jump
## from 1x to 24x on a single frame, which made the starfield snap from a drift to a blur
## between one frame and the next — it read as a glitch rather than as acceleration.
@export var stasis_ramp_time: float = 1.8
## Speed floor as a fraction of cruise. Faults can total more than 100%, and a ship frozen
## at exactly zero is an unwinnable run that still makes you sit through your own suffocation.
@export var min_speed_fraction: float = 0.06
## Distance (million miles) at which the destination starts to become visible ahead.
@export var approach_distance: float = 8.0
## Air remaining, in seconds, at which the HUD starts shouting.
@export var oxygen_warning: float = 60.0

@export_group("Wiring")
@export var motion_path: NodePath = NodePath("../Motion")
@export var lighting_path: NodePath = NodePath("../Lighting")

# --- needs (TODO 17) --------------------------------------------------------
#
# The needs are DECLARED HERE AND SPAWNED, rather than placed in game.tscn. That started as a
# way round the scene being locked for editing elsewhere, and it is the right shape anyway:
# `start()` already collects its faults from a GROUP rather than through exported paths, and
# the ship's own geometry is authored in code (ship_layout.gd) rather than dragged into place.
# A need has no position and no model — it is a number attached to the player's body — so
# there was never anything for the scene to hold.
#
# The SILOS are found by group, exactly like the faults, because those genuinely are objects in
# rooms. See ShipSupplies for where they come from.

## Every need this run could have, as data. Adding one is a row here.
##
## `starts_with` is temporary scaffolding: per TODO 17b the O2 SCRUBBER malfunction should stop
## attacking the drive and start the CO2 countdown instead, but that is a `vo_line`/`speed_penalty`
## edit inside game.tscn. Until the lock lifts, the need names the fault that starts it and
## `neutralise` strips the effects it is replacing — one dictionary to delete afterwards.
const NEEDS := [
	{
		"id": &"co2",
		"display_name": "CO2",
		# 150 awake seconds against a 240s air budget: long enough that one charge of the
		# scrubber covers a real excursion, short enough that ignoring it is a decision.
		"seconds": 150.0,
		"warn_at": 0.55,
		"lethal": true,
		"fatal_title": "CO2 NARCOSIS",
		"fatal_text": "You stopped being able to think straight, then you stopped.",
		"silo_id": &"life_support",
		"starts_with": "O2 SCRUBBER",
		"neutralise": {"speed_penalty": 0.0, "oxygen_drain_multiplier": 1.0},
	},
	# --- the chain (TODO 17c) ------------------------------------------------
	# Drink the beer -> you need the toilet -> the tank fills -> it will go off unless you walk
	# empties to it. The only place in the game where SOLVING a problem is what CREATES the
	# next one, which is why 17c says to cut around it rather than through it if time runs out.
	{
		"id": &"thirst",
		"display_name": "THIRST",
		"seconds": 200.0,
		"warn_at": 0.5,
		# The only need that arrives on a schedule. Six days in, so the opening of a run is
		# about the ship rather than about the player's body.
		"starts_after_days": 6.0,
		"silo_id": &"beer",
		"triggers": &"bladder",
		"movement_penalty": 0.2,
	},
	{
		"id": &"bladder",
		"display_name": "BLADDER",
		"seconds": 120.0,
		"warn_at": 0.5,
		# No schedule and no fault: this one exists ONLY because you dealt with the last one.
		"silo_id": &"crap",
		"movement_penalty": 0.35,
	},
	{
		# Hunger. Last of the six and the least novel, which is exactly why it is worth having:
		# it needed no new script, no new field and no special case — a need, a silo in a room,
		# a crate from cargo, same as every other. If it HAD needed any of those, 17a's claim
		# that this is one mechanic six times over would have been wrong.
		#
		# Longest fuse of the lot and it arrives latest, so the back half of a voyage is when
		# the ship's problems and the body's problems start landing together.
		"id": &"hunger",
		"display_name": "HUNGER",
		"seconds": 240.0,
		"warn_at": 0.45,
		"starts_after_days": 11.0,
		"silo_id": &"food",
		"movement_penalty": 0.25,
	},
	{
		"id": &"overflow",
		"display_name": "SEPTIC TANK",
		# Short, and lethal. Once the tank is full the run has a hard deadline measured in
		# walks to the cargo bay, which is the shape the whole section was aiming for.
		"seconds": 90.0,
		"warn_at": 1.0,  # on the HUD from the moment it starts — there is no gentle phase
		"lethal": true,
		"fatal_title": "SEPTIC",
		"fatal_text": "The tank let go. They will not be putting that on the plaque.",
		# Started by the tank filling rather than by a clock, and stopped again the moment
		# somebody pumps it down.
		"starts_with_silo": &"crap",
	},
]

var distance_remaining: float = 0.0
## In-fiction days since the run began. Displayed, and useful for logging a run.
var days_elapsed: float = 0.0
## Ship time per real second RIGHT NOW, somewhere between 1 and stasis_time_scale while the
## drive is spinning up or down. Read by the HUD, and pushed at ShipMotion every frame so
## the stars stretch and relax with it.
var time_scale: float = 1.0
var oxygen_remaining: float = 0.0
var in_stasis: bool = false
var running: bool = false
var finished: bool = false

# Run summary, so the end screen can show the player the shape of their own run.
var repairs_permanent: int = 0
var repairs_patched: int = 0
var patch_failures: int = 0
var air_spent_on_repairs: float = 0.0
var choices: Array[String] = []

# Ramp state. Interpolating in LOG space rather than linearly: a linear 1 -> 24 is already
# past 12x at the halfway point, so almost the whole ramp is spent at high speed and it
# still reads as a jump. Geometric interpolation is constant proportional acceleration,
# which is what a drive spinning up actually looks like.
var _ramp_progress: float = 1.0
var _ramp_from: float = 1.0
var _ramp_to: float = 1.0

var _motion: ShipMotion = null
var _lighting: LightingController = null
var _malfunctions: Array[Malfunction] = []
var _needs: Array[Need] = []
var _silos: Array[Silo] = []
## Why the run ended, for the end screen. Empty means the default "OUT OF AIR".
var _end_title: String = ""
var _end_text: String = ""


func _ready() -> void:
	_motion = get_node_or_null(motion_path) as ShipMotion
	_lighting = get_node_or_null(lighting_path) as LightingController
	distance_remaining = total_distance
	oxygen_remaining = oxygen_total
	set_process(false)


## Collect the faults and begin. Called when the player clicks START, not from _ready(),
## so the countdown cannot run down behind the start prompt.
func start() -> void:
	if running:
		return
	# FIRST, before anything is collected or spawned. _spawn_needs() below starts any need
	# whose fault is already broken, and _start_need() refuses to do anything on a finished
	# run — so leaving this until after the spawn meant a second run silently opened with its
	# opening need switched off, and only on the second run, which is the worst kind of bug.
	finished = false
	_end_title = ""
	_end_text = ""

	_malfunctions.clear()
	for node in get_tree().get_nodes_in_group(Malfunction.GROUP_MALFUNCTION):
		var malfunction := node as Malfunction
		if malfunction == null:
			continue
		_malfunctions.append(malfunction)
		# BEFORE the connects, and that ordering is the whole of `starts_broken`. Hooked up
		# first, break_now() would fire `alarm` on frame zero — a hull impact for a fault that
		# happened while the player was asleep, and the computer announcing it over a cold
		# open built to be silent — and _on_broke would call exit_stasis(), cutting the
		# opening beat short before it had begun. The fault is simply already true.
		if malfunction.starts_broken:
			malfunction.break_now(false)
		# Guarded, so start() can genuinely be called twice on the same faults. Today the run
		# restarts by reloading the scene, so this never came up — but unguarded, a second
		# start() leaves every fault wired to _on_broke TWICE, which double-counts patch
		# failures and fires the klaxon twice for one impact. Cheaper to be correct than to
		# rely on the scene always being thrown away.
		if not malfunction.broke.is_connected(_on_broke):
			malfunction.broke.connect(_on_broke)
		if not malfunction.repaired.is_connected(_on_repaired):
			malfunction.repaired.connect(_on_repaired)

	_collect_silos()
	_spawn_needs()

	distance_remaining = total_distance
	days_elapsed = 0.0
	_set_time_scale(1.0)
	oxygen_remaining = oxygen_total
	running = true
	set_process(true)
	if _motion != null:
		_motion.speed_driven_externally = true
	_update_speed()
	distance_changed.emit(distance_remaining, total_distance)
	oxygen_changed.emit(oxygen_remaining, oxygen_total)
	systems_changed.emit()
	# A fault that starts broken never went through _on_broke, so the ship-wide red alert has
	# to be brought up here or the run would open with a critical fault and white lighting.
	_update_alert()


func _process(delta: float) -> void:
	if not running or finished:
		return

	# Faults that make you breathe harder do NOT apply in the pod: it is a sealed system,
	# and the scrubber fault's pressure should be on excursions, not on sleeping through it.
	var rate := oxygen_drain_rate * (stasis_oxygen_rate if in_stasis else _oxygen_multiplier())
	oxygen_remaining = maxf(oxygen_remaining - delta * rate, 0.0)
	oxygen_changed.emit(oxygen_remaining, oxygen_total)
	if oxygen_remaining <= 0.0:
		_end(false)
		return

	# Speed before distance: a fault that fired this frame should slow this frame's travel.
	_update_speed()
	_advance_ramp(delta)
	var days := delta * days_per_real_second * time_scale
	days_elapsed += days
	distance_remaining = maxf(distance_remaining - cruise_speed_per_day * speed_fraction() * days, 0.0)
	distance_changed.emit(distance_remaining, total_distance)

	# `days`, not `delta`: a critical fault bleeds speed on the SHIP's clock, so the pod's
	# time scale carries into it and sleeping through a failing drive costs what it should.
	for malfunction in _malfunctions:
		malfunction.advance(distance_remaining, days)

	# `days` again, and deliberately: a silo that drains on its own is the ENGINE burning fuel,
	# which happens because the ship is moving. So stasis burns it at 24x, and sleeping stops
	# being the free half of the loop. Everything else in here has drain_per_day = 0.
	for silo in _silos:
		silo.advance(days)

	# Needs that arrive on a schedule do so on the SHIP's clock — the voyage is what has moved
	# on, and a day is a day whether you slept through it or not. Only the countdown itself is
	# awake-time. Outside the stasis guard, so a need can be waiting for you when you get up.
	for need in _needs:
		if not need.active and not need.has_expired and need.starts_after_days > 0.0 \
				and days_elapsed >= need.starts_after_days:
			_start_need(need)

	# `delta`, and ONLY while awake. A need is a body clock, not a ship system: it must not
	# carry the pod's 24x time scale, and it must not run at all in the pod, or sleeping
	# through a long haul — the correct play — would kill you. TODO 17e settles this.
	if not in_stasis:
		for need in _needs:
			need.advance(delta)
		if finished:
			return

	_update_destination()

	if distance_remaining <= 0.0:
		_end(true)


func enter_stasis() -> void:
	if in_stasis or not running or finished:
		return
	in_stasis = true
	# The OXYGEN rate switches instantly here and that is correct — the lid has shut, the
	# pod is sealed, the player is breathing pod air from this moment. It is only the ship's
	# clock that has to wind up.
	_start_ramp(stasis_time_scale)
	stasis_changed.emit(true)


func exit_stasis() -> void:
	if not in_stasis:
		return
	in_stasis = false
	_start_ramp(1.0)
	stasis_changed.emit(false)


## Begin winding the ship's clock toward `target`. Starts from wherever the ramp currently
## is, not from a fixed value, so climbing back into the pod part-way through a spin-down
## picks up smoothly instead of snapping back to 1x first.
func _start_ramp(target: float) -> void:
	_ramp_from = time_scale
	_ramp_to = maxf(target, 0.001)
	_ramp_progress = 0.0 if stasis_ramp_time > 0.0 else 1.0
	if _ramp_progress >= 1.0:
		_set_time_scale(_ramp_to)


func _advance_ramp(delta: float) -> void:
	if _ramp_progress >= 1.0:
		return
	_ramp_progress = minf(_ramp_progress + delta / stasis_ramp_time, 1.0)
	# Smoothstep on top of the geometric interpolation, so the ramp also eases in and out
	# at its two ends rather than starting and stopping abruptly.
	var t: float = _ramp_progress * _ramp_progress * (3.0 - 2.0 * _ramp_progress)
	_set_time_scale(exp(lerpf(log(maxf(_ramp_from, 0.001)), log(_ramp_to), t)))


func _set_time_scale(value: float) -> void:
	time_scale = value
	if _motion != null:
		_motion.time_scale = value


# --- needs and silos --------------------------------------------------------

## Build a Need per row of NEEDS as a child of this node, and wire it to the fault that starts
## it and the silo that satisfies it. Re-runnable: a second start() frees the previous set
## rather than stacking a second CO2 countdown on the first.
func _spawn_needs() -> void:
	for old in _needs:
		if is_instance_valid(old):
			old.queue_free()
	_needs.clear()

	for row in NEEDS:
		var need := Need.new()
		need.name = "Need_%s" % row["id"]
		need.id = row["id"]
		need.display_name = row.get("display_name", "NEED")
		need.seconds = row.get("seconds", 180.0)
		need.warn_at = row.get("warn_at", 0.4)
		need.lethal = row.get("lethal", false)
		need.fatal_title = row.get("fatal_title", "DEAD")
		need.fatal_text = row.get("fatal_text", "")
		need.silo_id = row.get("silo_id", &"")
		need.triggers = row.get("triggers", &"")
		need.vo_line = row.get("vo_line", &"")
		need.starts_after_days = row.get("starts_after_days", 0.0)
		need.movement_penalty = row.get("movement_penalty", 0.0)
		add_child(need)
		_needs.append(need)

		need.warned.connect(_on_need_warned)
		need.expired.connect(_on_need_expired)
		need.satisfied.connect(_on_need_satisfied)

		# The silo that clears it. `used` fires when the player breathes/drinks/eats at it, so
		# the need resets without either of them knowing the other exists.
		var silo := silo_by_id(need.silo_id)
		if silo != null:
			silo.used.connect(func(_s: Silo) -> void: need.satisfy())

		_wire_need_trigger(need, row)


## Hook a need up to whatever brings it into play. Four ways in, and between them they are the
## staggering that makes six needs fit in one run:
##
##   starts_with       a fault breaking (CO2, off the scrubber)
##   starts_with_silo  a tank filling up (the septic countdown, off the crap tank)
##   starts_after_days a point in the voyage (thirst) — handled in _advance_needs
##   triggers          another need being satisfied (bladder, off thirst) — the chain
##
## A need with none of them is in play from the off. Nothing currently is.
##
## The `starts_with`/`neutralise` halves are TEMPORARY — see the note on NEEDS. When 17i lands,
## the Malfunction carries the need's id itself and they go.
func _wire_need_trigger(need: Need, row: Dictionary) -> void:
	var silo_trigger: StringName = row.get("starts_with_silo", &"")
	if silo_trigger != &"":
		var tank := silo_by_id(silo_trigger)
		if tank != null:
			# Filling it starts the clock; pumping it back down stops it. Watching `level_changed`
			# rather than `exhausted` for the second half, because coming BACK from full is not
			# an event the silo announces — it is simply no longer in trouble.
			tank.level_changed.connect(func(s: Silo, _l: float) -> void:
				if s.is_exhausted():
					_start_need(need)
				elif need.active:
					need.stop()
					needs_changed.emit())
		return

	var trigger: String = row.get("starts_with", "")
	if trigger == "":
		# A schedule and the chain are both handled elsewhere, so a need with either is left
		# alone here. One with NEITHER has nothing to bring it in at all, and is simply live
		# from the off.
		if need.starts_after_days <= 0.0 and not _is_chained(need):
			need.start()
		return
	for malfunction in _malfunctions:
		if malfunction.system_name != trigger:
			continue
		for key in row.get("neutralise", {}):
			malfunction.set(key, row["neutralise"][key])
		malfunction.broke.connect(func(_m: Malfunction, _patch: bool) -> void:
			_start_need(need))
		malfunction.repaired.connect(func(_m: Malfunction, permanent: bool) -> void:
			# A PATCH does not put the air back — it stops the scrubber getting worse and
			# nothing more, so the countdown you are already on keeps running. Only a fitted
			# cartridge clears it, which is the same bargain every other fault offers.
			if permanent:
				need.stop())
		# A fault that starts broken never fires `broke` (see the note in start()), so a run
		# that opens on it has to pick the need up here instead.
		if malfunction.is_active:
			_start_need(need)
		return


func _start_need(need: Need) -> void:
	if need.active or finished:
		return
	need.start()
	if need.vo_line != &"":
		var audio := get_node_or_null(^"/root/Audio")
		if audio != null:
			audio.say(need.vo_line)
	needs_changed.emit()


## Is some other need's `triggers` pointing at this one? If so it is a link in the chain and
## must wait to be pulled, not start itself — a bladder that is full before you have had a
## drink is not a consequence of anything.
func _is_chained(need: Need) -> bool:
	for row in NEEDS:
		if row.get("triggers", &"") == need.id:
			return true
	return false


func need_by_id(id: StringName) -> Need:
	for need in _needs:
		if need.id == id:
			return need
	return null


## Walking speed as a fraction of normal, 1.0 when nothing is wrong. Penalties MULTIPLY rather
## than add, so two expired needs cannot between them stop the player dead — which would be an
## unwinnable run for a pair of problems that 17e settled should not be able to kill you.
func player_speed_scale() -> float:
	var scale := 1.0
	for need in _needs:
		if need.active and need.has_expired and need.movement_penalty > 0.0:
			scale *= 1.0 - need.movement_penalty
	return scale


func _collect_silos() -> void:
	_silos.clear()
	for node in get_tree().get_nodes_in_group(Silo.GROUP_SILO):
		var silo := node as Silo
		if silo == null:
			continue
		_silos.append(silo)
		if not silo.level_changed.is_connected(_on_silo_level):
			silo.level_changed.connect(_on_silo_level)
		if not silo.exhausted.is_connected(_on_silo_exhausted):
			silo.exhausted.connect(_on_silo_exhausted)


## The fuel tank running dry stops the drive, so the arrival clock has to be recomputed the
## moment it does — and the HUD row has to appear before that, while there is still time to
## walk a cell to it.
func _on_silo_level(_silo: Silo, _level: float) -> void:
	_update_speed()
	needs_changed.emit()


func _on_silo_exhausted(silo: Silo) -> void:
	if silo.vo_line != &"":
		var audio := get_node_or_null(^"/root/Audio")
		if audio != null:
			audio.say(silo.vo_line)
	# A supply runs dry; a waste tank overflows. Same signal, opposite disaster.
	choices.append("%s %s" % [
		silo.display_name, "overflowed" if silo.mode == Silo.Mode.WASTE else "ran dry"
	])
	_update_speed()
	needs_changed.emit()


## Silos in trouble, for the HUD. Same idea as pressing_needs(): a tank you have plenty of is
## not worth a line.
func pressing_silos() -> Array[Silo]:
	var out: Array[Silo] = []
	for silo in _silos:
		if silo.is_pressing():
			out.append(silo)
	return out


func silos() -> Array[Silo]:
	return _silos


func silo_by_id(id: StringName) -> Silo:
	if id == &"":
		return null
	for silo in _silos:
		if silo.silo_id == id:
			return silo
	return null


func needs() -> Array[Need]:
	return _needs


## The needs bad enough to have earned a row on the HUD. Empty for most of a good run, which
## is the point: the readout grows as things go wrong rather than shipping nine dials.
func pressing_needs() -> Array[Need]:
	var out: Array[Need] = []
	for need in _needs:
		if need.is_pressing():
			out.append(need)
	return out


## Crossing the warning line is what puts the need on the HUD — the row IS the warning.
## `Need.vo_line` is carried for a spoken warning, which is Phase 4 work.
func _on_need_warned(_need: Need) -> void:
	needs_changed.emit()


## THE CHAIN. Satisfying one need starts the next: drink the beer, and now you need the toilet.
##
## The lookup is here rather than in Need because a need has no business knowing about the
## others — it carries `triggers` as data and this pulls the link. `_start_need` is idempotent,
## which is what stops a second beer silently re-arming a bladder that is already running and
## making the second beer free.
func _on_need_satisfied(_need: Need, triggers: StringName) -> void:
	if triggers != &"":
		var next := need_by_id(triggers)
		if next != null:
			_start_need(next)
	needs_changed.emit()


func _on_need_expired(need: Need) -> void:
	needs_changed.emit()
	if not need.lethal:
		# Degrading needs land in Phase 4 (slower movement, narrowed vision). Recorded now so
		# the run summary can still tell the player it happened.
		choices.append("%s got the better of you" % need.display_name)
		return
	choices.append("%s ran out" % need.display_name)
	_end_title = need.fatal_title
	_end_text = need.fatal_text
	_end(false)


## Faults active right now, for the HUD.
func active_malfunctions() -> Array[Malfunction]:
	var out: Array[Malfunction] = []
	for malfunction in _malfunctions:
		if malfunction.is_active:
			out.append(malfunction)
	return out


func malfunctions() -> Array[Malfunction]:
	return _malfunctions


## DAYS to arrival at the current speed. INF when stopped dead — the honest answer, and
## the HUD renders it as dashes rather than inventing an arrival date it cannot promise.
func eta_days() -> float:
	var rate := cruise_speed_per_day * speed_fraction()
	if rate <= 0.00001:
		return INF
	return distance_remaining / rate


## 0..1, where 1 is undamaged. Drives both the voyage and ShipMotion's visual speed.
func speed_fraction() -> float:
	var penalty := 0.0
	for malfunction in _malfunctions:
		penalty += malfunction.active_speed_penalty()
	# An empty fuel tank is a total penalty rather than a hard zero, so it lands on the SAME
	# min_speed_fraction floor every other total does. A drive frozen at exactly nothing is an
	# unwinnable run that still makes the player sit through their own suffocation, and the
	# floor exists precisely to stop that — power should not be the one thing that dodges it.
	for silo in _silos:
		if silo.stops_the_drive and silo.is_exhausted():
			penalty += 1.0
			break
	return clampf(1.0 - penalty, min_speed_fraction, 1.0)


func summary() -> Dictionary:
	return {
		"distance_covered": total_distance - distance_remaining,
		"total_distance": total_distance,
		"air_spent": oxygen_total - oxygen_remaining,
		"air_total": oxygen_total,
		"air_left": oxygen_remaining,
		"repairs_permanent": repairs_permanent,
		"repairs_patched": repairs_patched,
		"patch_failures": patch_failures,
		"choices": choices.duplicate(),
		# Empty on a win and on running out of air, which the end screen already words for
		# itself. A need that killed you names its own death — see Need.fatal_title.
		"end_title": _end_title,
		"end_text": _end_text,
	}


func _update_speed() -> void:
	if _motion == null:
		return
	# ShipMotion keeps its own metres-per-second, tuned for how the stars should look;
	# all RunState says is how healthy the drive is.
	_motion.speed = _motion.cruise_speed * speed_fraction()


# Faults multiply the drain rather than adding to it, and only the WORST one counts.
# Stacking multipliers would make two mild faults deadlier than one severe one, which is
# both surprising and unfair to reason about mid-panic.
func _oxygen_multiplier() -> float:
	var worst := 1.0
	for malfunction in _malfunctions:
		worst = maxf(worst, malfunction.active_oxygen_multiplier())
	return worst


func _update_destination() -> void:
	if _motion == null:
		return
	if approach_distance <= 0.0:
		return
	_motion.destination_brightness = clampf(1.0 - distance_remaining / approach_distance, 0.0, 1.0)


func _on_broke(malfunction: Malfunction, was_patch_failure: bool) -> void:
	if was_patch_failure:
		patch_failures += 1
		choices.append("Your patch on %s gave out" % malfunction.system_name)
	# Being woken by the klaxon IS the loop: stasis is only ever interrupted by a fault.
	if in_stasis:
		exit_stasis()
	_update_speed()
	_update_alert()
	systems_changed.emit()
	alarm.emit(malfunction, was_patch_failure)


func _on_repaired(malfunction: Malfunction, permanent: bool) -> void:
	if permanent:
		repairs_permanent += 1
		if malfunction.repair_oxygen_bonus > 0.0:
			# Recovered reserve. The only way air ever comes back, and it costs a long walk.
			oxygen_remaining = minf(oxygen_remaining + malfunction.repair_oxygen_bonus, oxygen_total)
			oxygen_changed.emit(oxygen_remaining, oxygen_total)
			choices.append("Repaired %s properly (+%ds air recovered)" % [
				malfunction.system_name, int(round(malfunction.repair_oxygen_bonus))
			])
		else:
			choices.append("Repaired %s properly" % malfunction.system_name)
	else:
		repairs_patched += 1
		if malfunction.bodge_oxygen_cost > 0.0:
			# Venting air to solve a problem — oxygen spent as a currency in fiction,
			# not just as a clock.
			oxygen_remaining = maxf(oxygen_remaining - malfunction.bodge_oxygen_cost, 0.0)
			air_spent_on_repairs += malfunction.bodge_oxygen_cost
			oxygen_changed.emit(oxygen_remaining, oxygen_total)
			choices.append("Vented %ds of air to patch %s" % [
				int(round(malfunction.bodge_oxygen_cost)), malfunction.system_name
			])
			if oxygen_remaining <= 0.0:
				_update_speed()
				systems_changed.emit()
				_end(false)
				return
		else:
			choices.append("Patched %s (temporary)" % malfunction.system_name)

	_update_speed()
	_update_alert()
	systems_changed.emit()


func _update_alert() -> void:
	if _lighting == null:
		return
	var critical := false
	for malfunction in _malfunctions:
		if malfunction.is_critical():
			critical = true
			break
	_lighting.set_alert(critical)


func _end(won: bool) -> void:
	if finished:
		return
	finished = true
	running = false
	set_process(false)
	exit_stasis()
	# _process has stopped, so the ramp would freeze wherever it happened to be and leave
	# the starfield smeared behind the end screen.
	_ramp_progress = 1.0
	_set_time_scale(1.0)
	if _motion != null:
		_motion.speed_driven_externally = false
	run_ended.emit(won, summary())
