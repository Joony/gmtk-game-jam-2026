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
# Time is scaled, not paused, in stasis: ship time runs `stasis_time_scale` faster while
# real time (and therefore nothing that drains oxygen) carries on normally. Engine.time_scale
# would have been the lazy route and would have sped the player's own movement up with it.
#
# All the balance lives in the exported values below and nowhere else.

signal distance_changed(remaining: float, total: float)
signal oxygen_changed(remaining: float, total: float)
signal stasis_changed(in_stasis: bool)
## Any change to any fault, for the HUD to re-render its list from.
signal systems_changed
## A fault breaking, separately, because this is the "wake up" beat.
signal alarm(malfunction: Malfunction, was_patch_failure: bool)
signal run_ended(won: bool, summary: Dictionary)

@export_group("Balance")
## Journey length in metres. At cruise this is total_distance / cruise_speed seconds of
## SHIP time; divide by stasis_time_scale for the real-time floor on a perfect run.
@export var total_distance: float = 54000.0
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
## Speed floor as a fraction of cruise. Faults can total more than 100%, and a ship frozen
## at exactly zero is an unwinnable run that still makes you sit through your own suffocation.
@export var min_speed_fraction: float = 0.06
## Distance at which the destination starts to become visible ahead.
@export var approach_distance: float = 12000.0
## Air remaining, in seconds, at which the HUD starts shouting.
@export var oxygen_warning: float = 60.0

@export_group("Wiring")
@export var motion_path: NodePath = NodePath("../Motion")
@export var lighting_path: NodePath = NodePath("../Lighting")

var distance_remaining: float = 0.0
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

var _motion: ShipMotion = null
var _lighting: LightingController = null
var _malfunctions: Array[Malfunction] = []


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
	_malfunctions.clear()
	for node in get_tree().get_nodes_in_group(Malfunction.GROUP_MALFUNCTION):
		var malfunction := node as Malfunction
		if malfunction == null:
			continue
		_malfunctions.append(malfunction)
		malfunction.broke.connect(_on_broke)
		malfunction.repaired.connect(_on_repaired)

	distance_remaining = total_distance
	oxygen_remaining = oxygen_total
	finished = false
	running = true
	set_process(true)
	if _motion != null:
		_motion.speed_driven_externally = true
	_update_speed()
	distance_changed.emit(distance_remaining, total_distance)
	oxygen_changed.emit(oxygen_remaining, oxygen_total)
	systems_changed.emit()


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
	var ship_delta := delta * (stasis_time_scale if in_stasis else 1.0)
	distance_remaining = maxf(distance_remaining - _speed() * ship_delta, 0.0)
	distance_changed.emit(distance_remaining, total_distance)

	for malfunction in _malfunctions:
		malfunction.advance(distance_remaining)

	_update_destination()

	if distance_remaining <= 0.0:
		_end(true)


func enter_stasis() -> void:
	if in_stasis or not running or finished:
		return
	in_stasis = true
	if _motion != null:
		_motion.time_scale = stasis_time_scale
	stasis_changed.emit(true)


func exit_stasis() -> void:
	if not in_stasis:
		return
	in_stasis = false
	if _motion != null:
		_motion.time_scale = 1.0
	stasis_changed.emit(false)


## Faults active right now, for the HUD.
func active_malfunctions() -> Array[Malfunction]:
	var out: Array[Malfunction] = []
	for malfunction in _malfunctions:
		if malfunction.is_active:
			out.append(malfunction)
	return out


func malfunctions() -> Array[Malfunction]:
	return _malfunctions


## Seconds of ship time to arrival at the current speed. INF when stopped — the honest
## answer, and the HUD renders it as "--:--" rather than a made-up number.
func eta_seconds() -> float:
	var speed := _speed()
	if speed <= 0.001:
		return INF
	return distance_remaining / speed


## 0..1, where 1 is undamaged. What the HUD's speed bar shows.
func speed_fraction() -> float:
	if _motion == null or _motion.cruise_speed <= 0.0:
		return 0.0
	return _speed() / _motion.cruise_speed


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
	}


func _speed() -> float:
	return _motion.speed if _motion != null else 0.0


func _update_speed() -> void:
	if _motion == null:
		return
	var penalty := 0.0
	for malfunction in _malfunctions:
		penalty += malfunction.active_speed_penalty()
	_motion.speed = _motion.cruise_speed * clampf(1.0 - penalty, min_speed_fraction, 1.0)


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
	if _motion != null:
		_motion.speed_driven_externally = false
	run_ended.emit(won, summary())
