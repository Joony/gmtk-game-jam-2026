class_name Cable3D
extends Node3D
## Authored verlet rope stretched between two endpoint plugs/anchors, rendered
## as a tube (ADR 0046 — supersedes the rigid-link chain of ADR 0044/0045,
## reviving the ADR 0039/0040/0043 sim core).
##
## Ported into GMTK Game Jam 2026 from Doortal with all portal handling removed:
## the original stored every point in its own room with a parallel `side[]`
## array and mapped constraints/rendering through a CablePortalLink isometry.
## With no portals, every point lives in one world frame, the cross-room maps
## collapse to identity, and the two-real-room renderer becomes a single tube.
##
## Simulation is pure kinematics in _physics_process (no rigid bodies — the
## rope reacts to the world via space queries but never pushes anything):
##   1. verlet-integrate interior points (damping + gravity),
##   2. pin the endpoints to the anchors,
##   3. stretch-only distance constraint passes (rope resists tension, not
##      compression) + a bend pass, re-asserting the pins each pass,
##   4. per-point collision: a prev->cur ray as a tunnel guard, then sphere
##      rest-info depenetration — ejecting back TOWARD the point's previous
##      position when the nearest face disagrees, capped per tick, so a thin
##      fast mover (a kinematically carried cube) can never squeeze a point
##      out the wrong side (the sole ADR 0044 motivation, fixed in verlet).
## Bodies in `exclude_groups` (default: "cable_ignore" — the Player belongs
## there) are excluded from all queries via RID lists (ADR 0040); both plugs
## additionally collision-except those bodies so a tension-pulled plug never
## shoves the player.
##
## Three endpoint mechanisms layer on top of the rope (ADR 0046):
##   TENSION — past rest_length, each endpoint whose body is FREE and dynamic
##   (a loose plug, or the cube a seated plug is mounted on) is pulled toward
##   its neighbour rope point, so a dragged cube follows the rope. A
##   held/seated/carried body gets no force — the carry system authors it.
##   BREAKAWAY — sustained overstretch past BREAKAWAY_RATIO releases whichever
##   end can give (the endpoint's break_connection decides): a seated end pops
##   out of its socket, a held end drops from the player's hands — with an
##   elastic recoil along the rope. A bolted-in (fixed) end never releases.
##   POWER — ADR 0041's event-driven one-hop power via set_endpoint_socket.

## Preferred endpoint sources: bodies exposing cable_pin()/cable_render_pin().
@export var plug_a_path: NodePath
@export var plug_b_path: NodePath
## Fallback endpoint sources: any Node3D, pinned at its origin.
@export var anchor_a_path: NodePath
@export var anchor_b_path: NodePath
@export var rest_length := 4.0
@export var segment_length := 0.15
@export var radius := 0.03
@export var iterations := 8
## Velocity retained per tick. Lower = calmer rope that settles fast instead of
## swinging; 1.0 = undamped.
@export_range(0.9, 1.0, 0.001) var damping := 0.975
## Resistance to folding, via second-neighbor constraints. 0 = limp string,
## 1 = second neighbors held rigidly at two segment lengths apart.
@export_range(0.0, 1.0, 0.05) var bend_stiffness := 0.6
@export var exclude_groups: Array[StringName] = [&"cable_ignore"]

const MIN_POINTS := 20
const MAX_POINTS := 96
const TUBE_SIDES := 6
## Rendered ring subdivisions per sim segment (Catmull-Rom through the sim
## points), so the tube reads as a curve rather than straight pieces.
const TUBE_SUBDIV := 3
## A point that moved less than this since last tick skips the tunnel-guard
## ray (depenetration always runs — the world can move into a resting rope).
const MOVE_EPSILON := 1e-4
## Depenetrate every this-many constraint iterations, so constraints and
## collision converge together instead of fighting across ticks.
const COLLIDE_INTERVAL := 4
## Per-tick depenetration cap (x _eff_segment): a correction longer than this
## is truncated, so a point deeply embedded in a thin mover can never be
## teleported across it to the wrong face in one tick (ADR 0046's verlet form
## of the wrong-face fix — paired with ejecting toward the previous position).
const DEPEN_CAP_RATIO := 0.9
## Ticks the deep-squeeze bias (_deep) stays armed after a deep correction
## with no new deep event: an active pinch re-arms every tick; a one-off
## squeeze (a throw whipping rope against an edge) expires and the point
## returns to plain nearest-face depenetration.
const DEEP_PINCH_TICKS := 30
## Ticks after which a point's last-known-free reference (_last_free) is too
## STALE to redirect corrections toward (see _safe_correction's caller): the
## reference refreshes whenever the point ends a tick essentially free, so a
## fresh reference means "the point was demonstrably out of geometry within
## the last half second" — the transient squeeze the wrong-face redirect
## exists for (a cube swept over the rope, a drag pinching it under a floor
## edge). A point whose corrections have exceeded the refresh bound for
## LONGER than this is in a sustained loaded press (rope hauled taut against
## a doorframe pillar — observed), where the frozen reference points at a
## long-gone pose and redirecting toward it PINNED the point against the
## pillar's back; past the bound the redirect falls back to the same-tick
## `back` reference, which for a near-still pressed point is degenerate and
## yields plain nearest-face ejection — the behaviour that lets the rope slide
## along the face and around the frame.
const FREE_STALE_TICKS := 30
## Measured-length ratio past rest above which the rope counts as LOADED for
## the bend pass's grounded-fold gate (see _taut_prev): under it a resting or
## just-landed pile keeps the gate (goes truly still); over it the rope keeps
## full bend everywhere (unfolding work). Sits between a landing's impact
## stretch (~1%, decaying) and any real drag load (a taut pull measures 5-30%
## over).
const BEND_TAUT_RATIO := 1.02

## Contact response (verlet-native, via prev_points): fraction of a contacting
## point's TANGENTIAL implied velocity removed per contact tick (the normal
## component into the surface is always removed — inelastic, no bounce).
## Without this, depenetration is pure position ejection: the ejection itself
## injects outward velocity and gravity re-penetrates next tick, so a draped
## rope micro-jitters forever ("floaty") and a dragged rope oscillates in and
## out of thin obstacles (play report).
const CONTACT_FRICTION := 0.4

## Speed-ramped settle damping (see _integrate): below this implied speed
## (m per 60 Hz tick; 0.006 = 0.36 m/s) the damping retention ramps from
## `damping` down to SLOW_DAMP_FACTOR at zero speed.
const SLOW_DAMP_SPEED := 0.006
const SLOW_DAMP_FACTOR := 0.85
## Implied velocity (m per 60 Hz tick) below which a contacting point's
## carried-over velocity is zeroed entirely, so a settled rope goes truly
## still. Must exceed the per-tick gravity injection (9.8/60^2 ~ 0.0027) or
## rest is unreachable.
const CONTACT_REST_SPEED := 0.004

## Per-point rest snap: a CONTACTING point whose net displacement over the
## whole tick is below this (m/tick) has its start-of-tick position restored.
## The stretch/bend/depenetrate passes sustain a stable ~2 mm/tick limit cycle
## on a settled pile (measured: worst point 0.12-0.2 m/s forever) — velocity
## damping cannot end it because the solver moves POSITIONS each pass. The
## snap vetoes sub-jitter proposals; real motion (a 3 m/s drag is ~50 mm/tick)
## is far above it, and slow constraint-driven motion ratchets through in a
## couple of ticks once corrections accumulate past the threshold.
const REST_SNAP := 0.012
## The rest snap is skipped when the point's accumulated depenetration
## corrections this tick exceed this (m): corrections that large mean the
## WORLD moved into the point (a carried cube at walking speed ejects points
## centimetres per tick) and restoring the old position would re-embed it.
## Must sit above the resting gravity dip-and-eject cycle (~0.0027/tick,
## sometimes re-corrected within the tick) or the snap never engages.
const REST_SNAP_MAX_DEPEN := 0.008
## Rest-snap per-segment stretch gate (see _rest_snap): a point whose any
## nearby segment is stretched past the gate is never frozen. Phantom-taut
## measurement from frozen residue is excluded at the source instead: see
## _snapped.
const REST_SNAP_SLACK_STRETCH := 1.04
## Polyline length past rest_length * this ratio raises `overstretched`.
const OVERSTRETCH_RATIO := 1.6
## Endpoint tension (ADR 0046 mechanism 2): newtons per metre of polyline
## excess past rest_length x TENSION_START_RATIO, damped along the pull axis,
## hard-capped. The shape of the formula and the constants encode three
## play/test-proven lessons:
## - Damping applies OUTSIDE the stiffness clamp — f = clamp(min(K*excess,
##   F_MAX) - C*closing, 0, F_MAX) — the ADR 0045 bridge lesson: with the
##   damping inside the clamp a saturated spring keeps pulling at F_MAX until
##   the body chases at K*excess/C, an UNBOUNDED terminal speed (a dragged
##   cube slingshot past the player at ~7 m/s — observed). Outside, the
##   saturated pursuit speed is bounded to F_MAX/C ~ 1.9 m/s: a brisk follow
##   that can never become a wrecking ball.
## - The STIFFNESS is high so the pull saturates within ~a percent of
##   measured stretch: a drag only ever stretches the geometry a few percent
##   past rest, and every ratio-point of onset lag is rope the dragged cube
##   never yields — at K=60 the whole pull sat below the cube's floor friction.
## - The CAP is modest (vs ~10 N of friction under a 1 kg cube) so the
##   follow lags a walking player slightly: with a 25 N cap the dragged cube
##   kept closing until the rope was fully slack and parked ~2 m along the
##   pull line.
const TENSION_STIFFNESS := 220.0
const TENSION_DAMPING := 8.0
const TENSION_MAX_FORCE := 15.0
## Contact-aware tension clamp (see _tension_end): while the receiver PLUG
## reports contact with any foreign RigidBody3D, the pull is clamped to this.
## The full 15 N acting THROUGH a plug->cube contact fed the contact solve
## energy every tick: a reeled 0.5 kg plug arriving at ~2 m/s knocked a 1 kg
## cube to 4.07 m/s — 3x the perfectly-elastic momentum bound (observed) —
## and at rest the sustained push ground the cube across the floor. 4 N sits
## below a scene cube's floor friction (~8.8 N), so a sustained clamped push
## can never bulldoze one; a brief impact still transfers momentum bounded by
## the plug's arrival speed. Detection uses contact_monitor on the plugs
## (CablePlug._ready); a CUBE receiver (a mounted socket's tow) has no contact
## monitor, reports no bodies and is never clamped — the tow keeps full force.
const TENSION_CONTACT_SOFT := 4.0
## Inextensible tow for a FREE loose plug end (see _tow_free_end) — you carry one plug and the far
## plug hangs off nothing. The endpoint SPRING (capped at TENSION_MAX_FORCE) lets a walked free plug
## lag until the rope rubber-bands, and simply stiffening it whips a light body (an under-damped
## spring pumps energy). Instead a velocity constraint: while the free plug is past rest_length from
## the driving pin, its OUTWARD velocity is removed and the overshoot is reeled in at a bounded
## speed, so a dragged loose cable reads as an inextensible line. Stable (velocity-level, no energy
## added) and physical (no teleport — the plug still collides with walls). BETA is the fraction of
## the current overshoot corrected per tick; REEL_MAX caps the inward speed so a hard yank doesn't
## rocket the plug through the player.
const FREE_TOW_REEL_BETA := 0.5
const FREE_TOW_REEL_MAX := 8.0
## Free-free pull budget (ticks): when NEITHER end is externally driven (held,
## seated, or a bare static anchor — i.e. both tension receivers are live free
## bodies), the spring may act only while pulling is making PROGRESS — the
## measured length decreasing. A real reel shortens the rope every tick (budget
## continuously renewed, expiring exactly when relieved); the phantom-taut pile
## crawl moves the plugs while the measurement stays flat (no work done), so the
## budget expires and the crawl dies. A rope with an external authority (a
## carrier towing, a wall anchor) keeps the classic behaviour.
const TENSION_PULL_BUDGET := 30
const TENSION_PROGRESS_EPS := 0.001
## Ticks the soft clamp lingers after the last reported contact: the contact
## list flickers off for a tick or two during a sustained press (solver
## noise, observed), and each flicker un-clamped tick re-fed the full 15 N.
## Debouncing the clamp keeps the press at the soft force through the flicker;
## a plug that genuinely slips clear resumes full reel a third of a second later.
const TENSION_CONTACT_LINGER := 45
## Ratio the polyline must exceed before the tension SPRING drives (between
## 1.0 and this, only the extension-braking damping acts — see
## _apply_endpoint_tension). With _polyline_length discounting per-segment
## solver residue (SOLVER_STRETCH_TOLERANCE), a physically slack rope
## measures AT or under rest, so the spring can start almost at rest_length.
## The harsher measurement transients (the seed relaxing at ready, a hard-
## authored pin jump) are covered by the warm-up blackout below.
const TENSION_START_RATIO := 1.005
## Yaw-alignment torque tuning (see _tension_end): gain scales the vertical
## component of the pin-lever torque, the damping term bleeds yaw rate so the
## swing settles onto the pull instead of orbiting it.
const TENSION_YAW_GAIN := 3.0
const TENSION_YAW_DAMPING := 0.5
## Per-segment overstretch fraction discounted by _polyline_length as solver
## residue (see that function's doc).
const SOLVER_STRETCH_TOLERANCE := 0.005
## Ticks during which tension and breakaway are OFF while the rope re-settles:
## at ready, the seed zigzag is a construction artifact and the bend pass
## explodes it outward on the first tick — the measured polyline spikes ~25%
## over rest for a tick or two before the pile relaxes, which fired tension and
## kicked both free plugs a decimetre before the scene even settled (observed).
## The same blackout re-arms on an authored/unexplained endpoint-pin teleport
## (see PIN_RESETTLE_JUMP).
const TENSION_WARMUP_TICKS := 10
## An endpoint pin moving farther than this in ONE tick was hard-authored (a
## test/script reset, a seat authoring, a missed hook): re-arm the warm-up
## blackout above. Real pin motion tops out ~0.12 m/tick at the player's 7 m/s;
## throws and breakaway recoils stay under 0.2.
const PIN_RESETTLE_JUMP := 0.5
## Elastic breakaway (ADR 0046 mechanism 3): sustained stretch past
## BREAKAWAY_RATIO for BREAKAWAY_TIME pops the non-held seated end, recoiling
## along the rope by IMPULSE_PER_METER x excess, clamped to [MIN, MAX].
## (The freed plug's re-seat cooldown lives in CablePlug.RESEAT_COOLDOWN.)
const BREAKAWAY_RATIO := 1.2
const BREAKAWAY_TIME := 0.25
const BREAKAWAY_IMPULSE_PER_METER := 1.5
const BREAKAWAY_IMPULSE_MIN := 0.5
const BREAKAWAY_IMPULSE_MAX := 3.0
## Tube emission while the cable carries power (warm glow), 0 when dead.
const POWERED_EMISSION_ENERGY := 2.0
const POWERED_EMISSION_COLOR := Color(1.0, 0.72, 0.3)

## True while the polyline is stretched past rest_length * OVERSTRETCH_RATIO.
var overstretched := false

## One-hop power (no junction chaining v1): true while a seated end's socket is
## a power source. Drives set_fed on the non-source seated socket + tube glow.
var powered := false
## The sockets the endpoint plugs are currently seated in (null while free).
## Maintained via set_endpoint_socket, called by the endpoint plugs.
var socket_a: CableSocket = null
var socket_b: CableSocket = null

var points := PackedVector3Array()
var prev_points := PackedVector3Array()
## Snapshot of `points` at the start of the current physics tick, used as the
## render-interpolation source, the ray origin for the tunnel guard, and the
## eject-back reference for the wrong-face depenetration fix.
var _points_prev_tick := PackedVector3Array()

## Endpoint pins last tick, used to detect a hard-authored pin jump and re-arm
## the tension/breakaway warm-up (see _update_endpoint_pins).
var _prev_pin_a := Vector3.ZERO
var _prev_pin_b := Vector3.ZERO
## Seconds the rope has continuously measured past BREAKAWAY_RATIO.
var _breakaway_time := 0.0
var _pull_budget := TENSION_PULL_BUDGET
var _tension_len_prev := 0.0
## Remaining seed-relaxation ticks (see TENSION_WARMUP_TICKS).
var _warmup_ticks := TENSION_WARMUP_TICKS
## Per-endpoint remaining contact-clamp linger ticks (TENSION_CONTACT_LINGER).
var _contact_linger_a := 0
var _contact_linger_b := 0

var _anchor_a: Node3D = null
var _anchor_b: Node3D = null
## Effective inter-point rest distance. Derived from rest_length and the actual
## (clamped) point count so the MIN/MAX_POINTS clamp can never silently change
## the rope's total length; segment_length only chooses the resolution.
var _eff_segment := 0.15
var _exclude_rids: Array[RID] = []
## `exclude_groups` bodies the endpoint plugs are currently collision-excepted
## against, tracked so refresh_exclusions can remove stale ones on a re-call.
var _excepted: Array[PhysicsBody3D] = []
var _sphere := SphereShape3D.new()
## Per-point contact flag + accumulated depenetration correction, both reset
## each tick — inputs to the rest snap (see REST_SNAP).
var _in_contact := PackedByteArray()
## Previous tick's _in_contact, snapshotted before the per-tick reset: the
## bend pass runs before this tick's collision has marked anything, so its
## grounded-pair gate (see _bend_pass) reads last tick's contact state.
var _contact_prev := PackedByteArray()
## True while last tick's measured polyline exceeded rest_length by more
## than BEND_TAUT_RATIO. The bend pass's grounded-fold gate applies only to
## a rope that is not meaningfully loaded (see _bend_pass): a loaded rope's
## bend jiggle is real unfolding work. The 2% margin keeps a just-landed
## rope's impact-stretch transient GATED.
var _taut_prev := false
## Points the rest snap held still this tick. A segment whose BOTH endpoints
## the sim itself declared at-rest cannot be transmitting stretch — its
## measured stretch is frozen solver residue, and counting it gave a
## physically slack pile a phantom-taut measurement that drove an endless
## endpoint-tension crawl (the play-reported floor wriggle). _polyline_length
## caps such segments at _eff_segment instead; live segments count fully.
var _snapped := PackedByteArray()
var _depen_moved := PackedFloat32Array()
## Per-point tunnel-guard ray hit this tick (reset each tick): together with
## _in_contact it defines "this point ended the tick free of geometry", which
## is when _last_free may be refreshed.
var _ray_hit := PackedByteArray()
## Per-point LAST-KNOWN-FREE position: the reference a deeply embedded point is
## ejected TOWARD when the nearest face disagrees with where it came from. The
## previous-position reference alone is blind to the squeezed-under-a-drag case:
## under lateral drag `back` is horizontal (dot ~ 0), the nearest face past a
## thin floor's midplane is its BOTTOM, and depenetration parked rope under the
## floor at underside-minus-radius. A point dragged along a floor always has its
## last free position ABOVE it, so ejecting toward it can never tunnel down.
var _last_free := PackedVector3Array()
## Per-point deep-squeeze countdown: armed to DEEP_PINCH_TICKS when a point
## takes a correction deeper than its radius (or a tunnel-guard ray starts
## INSIDE a solid), cleared early when the point ends a tick free of geometry
## (the _last_free refresh), otherwise decremented each tick. While armed,
## even SHALLOW corrections opposing the free reference are redirected toward
## it: in a pinch with no valid pose (rope squeezed into the gap under a
## resting cube) the depenetration ping-pongs between the cube's bottom face (a
## shallow DOWNWARD eject, straight into the floor) and the floor top, parking
## the point fully inside the floor. With the bias, every anti-free correction
## walks the point back toward the gap mouth instead. The COUNTDOWN lets a
## chronic-but-shallow press shed the bias.
var _deep := PackedByteArray()
## Ticks since each point's _last_free was refreshed (see FREE_STALE_TICKS).
var _free_age := PackedInt32Array()
var _gravity := Vector3(0, -9.8, 0)

var _tube: MeshInstance3D = null
var _tube_mesh: ImmediateMesh = null
var _material: ShaderMaterial = null


func _ready() -> void:
	process_priority = 150
	_anchor_a = _resolve_endpoint(plug_a_path, anchor_a_path)
	_anchor_b = _resolve_endpoint(plug_b_path, anchor_b_path)
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var g_vec: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3.DOWN)
	_gravity = g_vec * g
	_sphere.radius = radius
	_init_points()
	_init_tube()
	refresh_exclusions()


## Resolve an endpoint node: the plug path wins, the anchor path is the
## fallback. A node exposing a `cable` property gets this cable back-referenced
## into it (duck-typed — the addon never names the game's plug class).
func _resolve_endpoint(plug_path: NodePath, anchor_path: NodePath) -> Node3D:
	var node := get_node_or_null(plug_path) as Node3D
	if node == null:
		node = get_node_or_null(anchor_path) as Node3D
	if node == null:
		return null
	if "cable" in node:
		node.set("cable", self)
	return node


## The endpoint's PHYSICS pin (a plug reports cable_pin(); a bare Node3D
## anchor pins at its origin).
func _endpoint_pin(node: Node3D) -> Vector3:
	if node.has_method("cable_pin"):
		return node.cable_pin()
	return node.global_position


## The endpoint's RENDER pin: where the rope endpoint should be DRAWN this
## frame (a held plug's body is authored per render frame, ahead of its physics).
func _endpoint_render_pin(node: Node3D) -> Vector3:
	if node.has_method("cable_render_pin"):
		return node.cable_render_pin()
	return node.global_position


## Rebuild the cached exclude-RID list from `exclude_groups` plus both endpoint
## bodies (the rope must never collide with its own plugs) plus each seated
## end's MOUNT body (a plug seated on a cube is one assembly with it: colliding
## the rope against its own mount forced the rope to WRAP the cube, and a
## socket whose straight line to the far end passes through its own mount then
## measured permanently taut — phantom tension on a resting cube, observed),
## AND the plug<->group collision EXCEPTIONS: a tension-pulled or recoiling
## plug resting against the player's capsule must never shove the player.
## Previously excepted bodies are un-excepted first, so runtime group changes
## can re-call this. Re-called on every seat/unseat (set_endpoint_socket) so
## the mount exclusion tracks the seat.
func refresh_exclusions() -> void:
	var plugs: Array[PhysicsBody3D] = []
	for endpoint in [_anchor_a, _anchor_b]:
		var body := endpoint as PhysicsBody3D
		if body != null:
			plugs.append(body)
	for old in _excepted:
		if not is_instance_valid(old):
			continue
		for plug in plugs:
			plug.remove_collision_exception_with(old)
	_excepted.clear()
	_exclude_rids.clear()
	for group in exclude_groups:
		for node in get_tree().get_nodes_in_group(group):
			var obj := node as CollisionObject3D
			if obj == null:
				continue
			_exclude_rids.append(obj.get_rid())
			var other := obj as PhysicsBody3D
			if other == null:
				continue
			for plug in plugs:
				if plug != other:
					plug.add_collision_exception_with(other)
			_excepted.append(other)
	for plug in plugs:
		_exclude_rids.append(plug.get_rid())
	for socket: CableSocket in [socket_a, socket_b]:
		if socket == null:
			continue
		var mount: PhysicsBody3D = socket.mount_body()
		if mount != null:
			_exclude_rids.append(mount.get_rid())


## Endpoint seat/unseat notification, called by an endpoint plug (`socket` is
## null on unseat). Event-driven power recompute: the cable is powered while
## any seated end's socket is a power source; non-source seated sockets are fed
## accordingly, and the socket an end just left is unfed.
func set_endpoint_socket(plug: Node3D, socket: CableSocket) -> void:
	var old: CableSocket = null
	if plug == _anchor_a:
		if socket_a == socket:
			return
		old = socket_a
		socket_a = socket
	elif plug == _anchor_b:
		if socket_b == socket:
			return
		old = socket_b
		socket_b = socket
	else:
		return
	if old != null:
		old.set_fed(false)
	refresh_exclusions()  # the seated-mount query exclusion tracks the seat
	_recompute_power()


## Re-run the one-hop power propagation. Public hook for a dynamic source (a battery whose port
## stops sourcing when it runs flat) to push its new state through to the far socket.
func refresh_power() -> void:
	_recompute_power()


func _recompute_power() -> void:
	var source_a := socket_a != null and socket_a.is_power_source
	var source_b := socket_b != null and socket_b.is_power_source
	var now := source_a or source_b
	# Feed every seated NON-source socket (set_fed is idempotent and a source
	# socket ignores the feed anyway — it is always powered).
	if socket_a != null and not source_a:
		socket_a.set_fed(now)
	if socket_b != null and not source_b:
		socket_b.set_fed(now)
	if now == powered:
		return
	powered = now
	if _material != null:
		_material.set_shader_parameter("emission_energy", POWERED_EMISSION_ENERGY if powered else 0.0)


## Seed the rope between the endpoint pins AT ITS NATURAL LENGTH: slack
## (anchors closer than rest_length) folds into a small perpendicular zigzag
## along the line — every consecutive pair exactly _eff_segment apart — the
## shape slack rope piles into anyway. A plain straight-lerp seed is heavily
## COMPRESSED, and the bend pass explodes it outward on the first ticks,
## spiking the measured polyline past the tension threshold and nudging both
## free plugs before the scene even settles (observed). Anchors farther apart
## than rest_length seed straight (the rope spawns strained; overstretch
## reports it).
func _init_points() -> void:
	var count := clampi(int(ceilf(rest_length / segment_length)) + 1, MIN_POINTS, MAX_POINTS)
	_eff_segment = rest_length / float(count - 1)
	var a := _endpoint_pin(_anchor_a) if _anchor_a != null else global_position
	var b := _endpoint_pin(_anchor_b) if _anchor_b != null else global_position
	points.resize(count)
	prev_points.resize(count)
	var span := b - a
	var sep := span.length()
	var dir := span / sep if sep > 1e-6 else Vector3.DOWN
	# Along-line point spacing, and the perpendicular tooth height that makes
	# every zigzag segment exactly _eff_segment long.
	var d := sep / float(count - 1)
	var h := sqrt(_eff_segment * _eff_segment - d * d) if d < _eff_segment else 0.0
	var perp := dir.cross(Vector3.UP)
	if perp.length_squared() < 1e-6:
		perp = dir.cross(Vector3.RIGHT)
	perp = perp.normalized()
	for i in count:
		var p := a + dir * (d * float(i))
		if i > 0 and i < count - 1 and (i & 1) == 1:
			p += perp * h
		points[i] = p
		prev_points[i] = p
	_points_prev_tick = points.duplicate()
	_last_free = points.duplicate()
	_in_contact.resize(count)
	_snapped.resize(count)
	_depen_moved.resize(count)
	_ray_hit.resize(count)
	_deep.resize(count)
	_deep.fill(0)
	_free_age.resize(count)
	_free_age.fill(0)
	_prev_pin_a = a
	_prev_pin_b = b


func _init_tube() -> void:
	_tube_mesh = ImmediateMesh.new()
	_tube = MeshInstance3D.new()
	_tube.name = "TubeMesh"
	_tube.mesh = _tube_mesh
	_tube.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tube.top_level = true
	_material = ShaderMaterial.new()
	_material.shader = load("res://addons/cables/materials/cable_clip.gdshader") as Shader
	_material.set_shader_parameter("emission_color", POWERED_EMISSION_COLOR)
	_material.set_shader_parameter("emission_energy", 0.0)
	_tube.material_override = _material
	add_child(_tube)
	_tube.global_transform = Transform3D.IDENTITY


func _physics_process(delta: float) -> void:
	if _anchor_a == null or _anchor_b == null or points.size() < 2:
		return
	_points_prev_tick = points.duplicate()
	_contact_prev = _in_contact.duplicate()
	_in_contact.fill(0)
	_snapped.fill(0)
	_depen_moved.fill(0.0)
	_ray_hit.fill(0)
	_integrate(delta)
	_update_endpoint_pins()
	_pin_endpoints()
	for i in iterations:
		# Bend BEFORE stretch, so every iteration (and the tick) ends with a
		# stretch pass: the bend pass inflates a folded pile (it pushes second
		# neighbours apart), and ending an iteration on it left the measured
		# polyline a few percent over rest at rest — phantom tension.
		if bend_stiffness > 0.0:
			_bend_pass()
		# Alternating direction converges far faster near the pinned ends than
		# forward-only Gauss-Seidel, which is what keeps the rope unstretchy.
		_constrain_pass(i % 2 == 1)
		_pin_endpoints()
		# Interleaved depenetration: without it, the passes above drag points
		# back into geometry and nothing re-resolves until next tick, so a taut
		# rope pulled across a corner sinks in.
		if (i + 1) % COLLIDE_INTERVAL == 0:
			_depenetrate_all()
	_collide()
	# Final stretch-only settle AFTER collision, so the measured polyline is
	# honest: the bend pass fights a folded pile every tick and the depenetration
	# in _collide moves points too, leaving a physically SLACK rope measuring a
	# couple percent over rest at equilibrium. Everything the endpoint mechanisms
	# decide — tension onset, braking, breakaway — keys off this measurement, so
	# noise here is phantom force.
	for i in 6:
		_constrain_pass(i % 2 == 1)
	_pin_endpoints()
	# End the tick OUT of geometry: the settle passes above drag contact points
	# a few mm back into surfaces, and that state both renders and seeds the
	# next tick's re-entry (the play-reported "glitching through items" was
	# this millimetre oscillation). One final depenetration (with contact
	# response) makes the rendered state the resolved one.
	_depenetrate_all()
	_rest_snap()
	_containment_clamp()
	# Refresh each point's last-known-free position: a point that ended this
	# tick with no tunnel-guard hit and at most SHALLOW depenetration (a
	# resting/sliding contact's mm-scale correction ends the tick at the
	# surface, demonstrably out of geometry) keeps its reference fresh — a
	# point sliding metres along a floor must not carry a reference from the
	# start of the drag. Deep corrections (a squeeze in progress) freeze the
	# reference at the pre-squeeze position, which is the whole idea.
	for i in points.size():
		if _ray_hit[i] == 0 and _depen_moved[i] <= REST_SNAP_MAX_DEPEN:
			_last_free[i] = points[i]
			_deep[i] = 0
			_free_age[i] = 0
		else:
			if _deep[i] > 0:
				_deep[i] -= 1
			_free_age[i] += 1
	var length := _polyline_length()
	_taut_prev = length > rest_length * BEND_TAUT_RATIO
	_contact_linger_a = maxi(_contact_linger_a - 1, 0)
	_contact_linger_b = maxi(_contact_linger_b - 1, 0)
	if _warmup_ticks > 0:
		_warmup_ticks -= 1
	else:
		_apply_endpoint_tension(length)
		_tow_free_ends(delta)
		_update_breakaway(delta, length)
	overstretched = length > rest_length * OVERSTRETCH_RATIO


func _integrate(delta: float) -> void:
	var accel := _gravity * delta * delta
	for i in range(1, points.size() - 1):
		var cur := points[i]
		var raw := cur - prev_points[i]
		var vel := raw * damping
		# Speed-ramped extra damping: below SLOW_DAMP_SPEED the retention
		# ramps toward SLOW_DAMP_FACTOR, so a hanging section's low-amplitude
		# pendulum swing (which plain 0.975/tick air drag sustains for
		# seconds — the play-reported "floaty" tail) dies in a fraction of a
		# second, while anything the player can actually see move (falls,
		# drags, throws — all far faster) keeps the calibrated damping.
		var speed := raw.length()
		if speed < SLOW_DAMP_SPEED:
			vel *= lerpf(SLOW_DAMP_FACTOR, 1.0, speed / SLOW_DAMP_SPEED)
		prev_points[i] = cur
		points[i] = cur + vel + accel


func _pin_endpoints() -> void:
	var last := points.size() - 1
	points[0] = _endpoint_pin(_anchor_a)
	prev_points[0] = points[0]
	points[last] = _endpoint_pin(_anchor_b)
	prev_points[last] = points[last]
	_pin_exit(_anchor_a, 0, 1)
	_pin_exit(_anchor_b, last, last - 1)


## If an endpoint exposes a cable exit direction (a plug reports the way out of its back), pin the
## adjacent interior point one segment along it, so the rope leaves the plug IN LINE with it — out
## the back — instead of pivoting at the attach point like a loose joint. Endpoints without the
## method (a bare anchor) are left free.
func _pin_exit(node: Node3D, end_i: int, next_i: int) -> void:
	if node == null or not node.has_method("cable_exit_dir"):
		return
	if next_i < 0 or next_i > points.size() - 1:
		return
	var dir: Vector3 = node.cable_exit_dir()
	if dir.length_squared() < 1e-6:
		return
	points[next_i] = points[end_i] + dir.normalized() * _eff_segment
	prev_points[next_i] = points[next_i]


## One stretch-only distance-constraint pass. Endpoints have weight 0 (pinned);
## interior neighbors split the correction evenly.
func _constrain_pass(reverse: bool = false) -> void:
	var last := points.size() - 1
	for k in last:
		var i := last - 1 - k if reverse else k
		var a := points[i]
		var b := points[i + 1]
		var delta_ab := b - a
		var dist := delta_ab.length()
		if dist <= _eff_segment or dist < 1e-9:
			continue
		var correction := delta_ab * ((dist - _eff_segment) / dist)
		var a_pinned := i == 0
		var b_pinned := i + 1 == last
		if a_pinned and b_pinned:
			continue
		if a_pinned:
			b -= correction
		elif b_pinned:
			points[i] = a + correction
			continue
		else:
			points[i] = a + correction * 0.5
			b -= correction * 0.5
		points[i + 1] = b


## One bend pass: second neighbors resist coming closer than two segment
## lengths (folding), scaled by bend_stiffness. Compression-only — the mirror
## image of the stretch-only pass above.
func _bend_pass() -> void:
	var last := points.size() - 1
	var rest := _eff_segment * 2.0
	var gated := not _taut_prev and _contact_prev.size() == points.size()
	for i in last - 1:
		# Grounded-fold gate, SLACK rope only: a pair whose three points all
		# ended last tick in contact is a fold the WORLD is holding (a pile on
		# the floor, rope lying over a cube) — bend resistance there is pure
		# energy injection: it re-inflates the fold every tick faster than the
		# stretch passes re-converge, sustaining frozen segment strain whose
		# rest-snap live windows then micro-cycle FOREVER (the floor-wriggle
		# residue). A TAUT rope (_taut_prev) keeps full bend even grounded: its
		# bend jiggle is real unfolding work that feeds a loaded drape. Airborne
		# rope always keeps full bend — the catenary/drape feel is untouched.
		if gated and _contact_prev[i] == 1 and _contact_prev[i + 1] == 1 \
				and _contact_prev[i + 2] == 1:
			continue
		var a := points[i]
		var b := points[i + 2]
		var delta_ab := b - a
		var dist := delta_ab.length()
		if dist >= rest or dist < 1e-9:
			continue
		var correction := delta_ab * ((dist - rest) / dist) * bend_stiffness
		var a_pinned := i == 0
		var b_pinned := i + 2 == last
		if a_pinned and b_pinned:
			continue
		if a_pinned:
			b -= correction
		elif b_pinned:
			points[i] = a + correction
			continue
		else:
			points[i] = a + correction * 0.5
			b -= correction * 0.5
		points[i + 2] = b


func _collide() -> void:
	var space := get_world_3d().direct_space_state
	for i in range(1, points.size() - 1):
		var from := _points_prev_tick[i]
		var to := points[i]
		# Tunnel guard: a fast point whose motion segment crossed a surface is
		# pulled back to the impact, so the sphere check below can't miss it.
		# Only meaningful for a point that actually moved.
		if from.distance_to(to) >= MOVE_EPSILON:
			var ray := PhysicsRayQueryParameters3D.create(from, to)
			ray.exclude = _exclude_rids
			# Report from inside a solid too (position == from, normal ZERO):
			# without it the guard is blind exactly when the point has already
			# been squeezed into geometry — the case it exists for.
			ray.hit_from_inside = true
			var hit := space.intersect_ray(ray)
			if not hit.is_empty():
				var normal := hit["normal"] as Vector3
				if normal.length_squared() < 1e-9:
					# Inside-start: eject toward the last-known-free position
					# (the nearest face is untrustworthy from in here), capped
					# like any depenetration step.
					_deep[i] = DEEP_PINCH_TICKS
					var out := _last_free[i] - from
					var out_len := out.length()
					if out_len > 1e-6:
						points[i] = from + out \
								* (minf(out_len, DEPEN_CAP_RATIO * _eff_segment) / out_len)
					else:
						points[i] = from
				else:
					points[i] = (hit["position"] as Vector3) + normal * radius
				_ray_hit[i] = 1
		# Depenetration runs unconditionally: the rope may be perfectly still
		# while the WORLD moves into it (a carried cube, a moving socket mount),
		# so a resting point can be as overlapped as a moving one.
		_depenetrate(space, i)
	_collide_midpoints(space)


## Sphere depenetration of one point, with the ADR 0046 wrong-face fix (see
## _safe_correction).
func _depenetrate(space: PhysicsDirectSpaceState3D, i: int) -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _sphere
	query.transform = Transform3D(Basis.IDENTITY, points[i])
	query.exclude = _exclude_rids
	var rest := space.get_rest_info(query)
	if not rest.is_empty():
		var normal := rest["normal"] as Vector3
		var corr := (rest["point"] as Vector3) + normal * radius - points[i]
		if corr.length() > radius:
			_deep[i] = DEEP_PINCH_TICKS
		# A stale free reference (see FREE_STALE_TICKS) is passed as ZERO so
		# _safe_correction falls through to the same-tick `back` reference.
		var to_free := _last_free[i] - points[i] \
				if _free_age[i] <= FREE_STALE_TICKS else Vector3.ZERO
		var applied := _safe_correction(corr, _points_prev_tick[i] - points[i],
				to_free, _deep[i] > 0)
		points[i] += applied
		_in_contact[i] = 1
		_depen_moved[i] += applied.length()
		_contact_response(i, normal)


## Verlet-native contact response: rewrite prev_points so the implied velocity
## (points - prev_points) loses its normal component (inelastic contact — the
## position ejection above must not read as outward velocity, and any residual
## into-surface velocity must not re-penetrate next tick) and its tangential
## component is friction-damped. Near-rest contact velocity is zeroed entirely
## so a settled rope goes truly still instead of micro-jittering on gravity.
func _contact_response(i: int, normal: Vector3) -> void:
	var v := points[i] - prev_points[i]
	if v.length() < CONTACT_REST_SPEED:
		prev_points[i] = points[i]
		return
	var vt := v - normal * v.dot(normal)
	prev_points[i] = points[i] - vt * (1.0 - CONTACT_FRICTION)


## End-of-tick rest snap (see REST_SNAP): a contacting point whose whole-tick
## net displacement is sub-jitter gets its start-of-tick position restored,
## terminating the solver's standing limit cycle so a settled rope is truly
## still. Skipped when the world moved into the point this tick
## (REST_SNAP_MAX_DEPEN — restoring would re-embed it), and when either adjacent
## segment is stretched > 4% (restoring would undo the settle passes' stretch
## relief and freeze strain in). The stretch gate is also what keeps a LOADED
## rope live without any tension-aware exemption: taut regions exceed it and
## never freeze, while the frozen slack drape behind them acts as a RATCHET
## during a drag.
func _rest_snap() -> void:
	var last := points.size() - 1
	var seg_ok := _eff_segment * REST_SNAP_SLACK_STRETCH
	for i in range(1, last):
		if _in_contact[i] == 0 or _depen_moved[i] > REST_SNAP_MAX_DEPEN:
			continue
		# A stretched segment must keep its NEIGHBOURHOOD live, not just its
		# two endpoints: freezing the points on either side of a stretched
		# pair pins the strain between frozen anchors, and the one live point
		# micro-cycles forever. A +/-4 segment window lets slack migrate far
		# enough for global relief.
		var stretched := false
		for j in range(maxi(i - 4, 0), mini(i + 4, last)):
			if points[j].distance_to(points[j + 1]) > seg_ok:
				stretched = true
				break
		if stretched:
			continue
		if points[i].distance_to(_points_prev_tick[i]) < REST_SNAP:
			points[i] = _points_prev_tick[i]
			prev_points[i] = points[i]
			_snapped[i] = 1


## The ADR 0046 wrong-face fix, applied to every depenetration correction:
## `back` is the vector from the point to its start-of-tick position, `to_free`
## the vector from the point to its LAST-KNOWN-FREE position (_last_free).
## When the point is DEEPLY embedded (deeper than its own radius — a
## kinematically carried cube swept past it, or a walking-speed drag squeezed
## it under the floor) and the nearest-face correction points AWAY from where
## it came from, the nearest face is the WRONG face — redirect the correction
## back the way the point came. The `back` check alone misses the
## squeezed-under-a-drag case; the `to_free` fallback catches it: the last free
## position of a floor-dragged point is always ABOVE the floor, so an ejection
## that opposes it is redirected up and can never tunnel down. Shallow grazing
## contacts always take the true nearest face. In all cases the applied
## magnitude is capped to DEPEN_CAP_RATIO x _eff_segment per tick. `deep_bias`
## (the sticky _deep flag) extends the redirect to SHALLOW corrections too, for
## a point known to be mid-squeeze — see _deep for the pinch it resolves.
func _safe_correction(corr: Vector3, back: Vector3, to_free: Vector3,
		deep_bias: bool = false) -> Vector3:
	var mag := corr.length()
	if mag < 1e-9:
		return Vector3.ZERO
	if mag > radius or deep_bias:
		# The free reference is primary: it subsumes the previous-position
		# check (a pinched point's last free position IS where it came from)
		# and stays trustworthy mid-climb-out, where `back` points DEEPER.
		# `back` is only the fallback while the free reference is degenerate
		# (a resting point's _last_free is its own position).
		if to_free.length() >= MOVE_EPSILON:
			if corr.dot(to_free) < 0.0:
				corr = to_free.normalized() * mag
		elif back.length() >= MOVE_EPSILON and corr.dot(back) < 0.0:
			corr = back.normalized() * mag
	var cap := DEPEN_CAP_RATIO * _eff_segment
	if mag > cap:
		corr = corr * (cap / mag)
	return corr


func _depenetrate_all() -> void:
	var space := get_world_3d().direct_space_state
	for i in range(1, points.size() - 1):
		_depenetrate(space, i)


## End-of-tick containment clamp, for _deep points only: a sphere FULLY
## contained inside a collider (a thick floor swallows the whole 4 cm sphere
## once the centre passes -radius) reports NO rest info, so the final
## _depenetrate_all is blind exactly where it matters most, and the settle
## passes' pull (a taut pinched run) re-embeds whatever the interleaved
## passes ejected — the tick then ENDS embedded and renders there. The clamp
## closes the hole without any world knowledge: the segment from the point's
## last-known-free position to the point must not cross a surface — if it does,
## the point is beyond that surface, and it is parked AT the crossing (plus
## radius), i.e. the mouth of whatever gap swallowed it, which is where a real
## rope piles up. prev_points is matched (the park is authored, not a velocity).
func _containment_clamp() -> void:
	var space := get_world_3d().direct_space_state
	var last := points.size() - 1
	for i in range(1, last):
		if _deep[i] == 0:
			continue
		var from := _last_free[i]
		var to := points[i]
		if from.distance_to(to) < MOVE_EPSILON:
			continue
		# The clamp is for a point whose CENTRE is inside a collider (the
		# swallowed state rest-info under-reports). A deep point that is merely
		# PRESSED against geometry — rope wrapped taut around a frame pillar,
		# with the pillar standing between the point and its stale _last_free —
		# must not be parked back on the reference's side. "Inside" is asked
		# directly: a ray STARTING at the point reports the hit_from_inside
		# signature (zero normal) iff the centre is within a solid; a
		# beside-the-pillar point reports a real face instead and keeps freedom.
		var inside_ray := PhysicsRayQueryParameters3D.create(to, from)
		inside_ray.exclude = _exclude_rids
		inside_ray.hit_from_inside = true
		var inside_hit := space.intersect_ray(inside_ray)
		if inside_hit.is_empty() \
				or (inside_hit["normal"] as Vector3).length_squared() > 1e-9:
			continue
		var ray := PhysicsRayQueryParameters3D.create(from, to)
		ray.exclude = _exclude_rids
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			continue
		points[i] = (hit["position"] as Vector3) + (hit["normal"] as Vector3) * radius
		prev_points[i] = points[i]


## Anything thinner than a segment can slip between two point spheres, so also
## depenetrate at each segment's midpoint, splitting the correction between the
## segment's ends. The correction goes through the same wrong-face redirect +
## per-tick cap as _depenetrate, referenced against the midpoint's
## start-of-tick position.
func _collide_midpoints(space: PhysicsDirectSpaceState3D) -> void:
	var last := points.size() - 1
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _sphere
	query.exclude = _exclude_rids
	for i in last:
		var mid := (points[i] + points[i + 1]) * 0.5
		query.transform = Transform3D(Basis.IDENTITY, mid)
		var rest := space.get_rest_info(query)
		if rest.is_empty():
			continue
		var raw := (rest["point"] as Vector3) + (rest["normal"] as Vector3) * radius - mid
		var prev_mid := (_points_prev_tick[i] + _points_prev_tick[i + 1]) * 0.5
		var free_mid := (_last_free[i] + _last_free[i + 1]) * 0.5
		var to_free := free_mid - mid \
				if maxi(_free_age[i], _free_age[i + 1]) <= FREE_STALE_TICKS \
				else Vector3.ZERO
		var corr := _safe_correction(raw, prev_mid - mid, to_free,
				_deep[i] > 0 or _deep[i + 1] > 0)
		var a_pinned := i == 0
		var b_pinned := i + 1 == last
		if a_pinned and b_pinned:
			continue
		if a_pinned:
			points[i + 1] += corr
		elif b_pinned:
			points[i] += corr
		else:
			points[i] += corr * 0.5
			points[i + 1] += corr * 0.5


## Re-arm the tension/breakaway warm-up blackout after a HARD-AUTHORED endpoint
## jump (a test/script reset, a seat authoring, a missed hook): the rope
## measures the STALE drape plus the jump until the constraints reel it in, and
## a force computed from that phantom length would drag a hard-reset body off
## its authored pose (see TENSION_WARMUP_TICKS).
func _update_endpoint_pins() -> void:
	_prev_pin_a = _resettle_check(_anchor_a, _prev_pin_a)
	_prev_pin_b = _resettle_check(_anchor_b, _prev_pin_b)


func _resettle_check(node: Node3D, prev_pin: Vector3) -> Vector3:
	var pin := _endpoint_pin(node)
	if pin.distance_to(prev_pin) > PIN_RESETTLE_JUMP:
		_warmup_ticks = maxi(_warmup_ticks, TENSION_WARMUP_TICKS)
	return pin


## Polyline length. Each segment's first SOLVER_STRETCH_TOLERANCE of overstretch
## past _eff_segment is NOT counted: the alternating Gauss-Seidel passes leave
## every pair of a resting pile hovering a fraction over its rest spacing, so
## the raw sum reported a physically SLACK rope ~1% over rest — phantom tautness
## that every consumer of this measurement (tension onset, breakaway, tests'
## taut gates) acted on. With the band discounted, a slack pile measures AT or
## under rest exactly, while genuine stretch still registers.
func _polyline_length() -> float:
	var total := 0.0
	var band := _eff_segment * SOLVER_STRETCH_TOLERANCE
	for i in points.size() - 1:
		var dist := points[i].distance_to(points[i + 1])
		# Both endpoints held by the rest snap: measured stretch here is
		# frozen solver residue, not transmitted tension (see _snapped).
		if _snapped[i] == 1 and _snapped[i + 1] == 1:
			dist = minf(dist, _eff_segment)
		elif dist > _eff_segment:
			dist = maxf(dist - band, _eff_segment)
		total += dist
	return total


## Endpoint tension (ADR 0046 mechanism 2): past rest_length, each end whose
## receiver is a FREE dynamic body is pulled toward that end's neighbour rope
## point — the local direction is what makes a dragged cube follow the rope
## instead of a straight line through a wall.
func _apply_endpoint_tension(length: float) -> void:
	# Free-free pull budget (see TENSION_PULL_BUDGET): renewed by an external
	# drive on either end or by real progress (measured length decreasing).
	if _tension_receiver(_anchor_a, socket_a) == null \
			or _tension_receiver(_anchor_b, socket_b) == null \
			or length < _tension_len_prev - TENSION_PROGRESS_EPS:
		_pull_budget = TENSION_PULL_BUDGET
	elif _pull_budget > 0:
		_pull_budget -= 1
	_tension_len_prev = length
	if length <= rest_length:
		return
	if _pull_budget <= 0:
		return
	# Spring drive engages above TENSION_START_RATIO; in the noise band
	# between rest_length and that threshold, `excess` is zero and only the
	# damping term acts — a rope at full measured extension resists its
	# endpoint moving FURTHER away (pure braking, zero force on a resting body).
	var excess := maxf(length - rest_length * TENSION_START_RATIO, 0.0)
	var last := points.size() - 1
	_tension_end(_anchor_a, socket_a, points[0], points[1], excess)
	_tension_end(_anchor_b, socket_b, points[last], points[last - 1], excess)


func _tension_end(endpoint: Node3D, socket: CableSocket, end_p: Vector3,
		neighbor: Vector3, excess: float) -> bool:
	var receiver := _tension_receiver(endpoint, socket)
	if receiver == null:
		return false
	var dir := neighbor - end_p
	if dir.length_squared() < 1e-12:
		return false
	var n := dir.normalized()
	# Spring-damper: stiffness clamped FIRST, damping applied outside (bounded
	# pursuit speed — see the constants), never negative. Damping reads the
	# PIN's velocity (centre + rotational contribution): the rope damps its
	# attachment point, which also quiets the alignment torque's ringing.
	var lever := end_p - receiver.global_position
	var pin_vel := receiver.linear_velocity + receiver.angular_velocity.cross(lever)
	var pull := clampf(minf(TENSION_STIFFNESS * excess, TENSION_MAX_FORCE) \
			- pin_vel.dot(n) * TENSION_DAMPING, 0.0, TENSION_MAX_FORCE)
	if pull <= 0.0:
		return false
	# Contact-aware clamp (see TENSION_CONTACT_SOFT): tension must not act at
	# full strength THROUGH a contact with another dynamic body. The clamp
	# lingers TENSION_CONTACT_LINGER ticks past the last reported contact
	# (decremented in _physics_process) so solver contact flicker cannot
	# re-feed the full force mid-press.
	var is_a := endpoint == _anchor_a
	if _receiver_touching_dynamic(receiver):
		if is_a:
			_contact_linger_a = TENSION_CONTACT_LINGER
		else:
			_contact_linger_b = TENSION_CONTACT_LINGER
	if (_contact_linger_a if is_a else _contact_linger_b) > 0:
		pull = minf(pull, TENSION_CONTACT_SOFT)
	receiver.sleeping = false
	# Linear pull applied CENTRALLY (0045's play-proven lesson: offset forces
	# destabilise light bodies — and a full-lever pull TIPS a dragged cube
	# into tumbling), PLUS the YAW component only of the true pin-lever torque:
	# a real cable dragging a box by a face attachment swings the box around
	# until the attachment leads the pull — but only about the vertical axis.
	# The pitch/roll components are exactly the tip-over moment, so they are
	# dropped: the floor constrains them in the intended interaction anyway.
	receiver.apply_central_force(n * pull)
	# Yaw gain hurries the swing so the socket comes around within a few ticks
	# of a new pull direction; the omega term damps the swing so it settles
	# instead of ringing. SPRING band only: in the braking band the pulsing
	# damping force fed through this torque set up a self-excited rock that
	# kept a parked cube jittering indefinitely.
	if excess > 0.0:
		var yaw := TENSION_YAW_GAIN * lever.cross(n * pull).y \
				- TENSION_YAW_DAMPING * receiver.angular_velocity.y
		if absf(yaw) > 1e-6:
			receiver.apply_torque(Vector3(0.0, yaw, 0.0))
	return true


## Inextensible tow for a FREE loose plug end (see FREE_TOW_REEL_BETA). Called each tick after the
## endpoint spring: for a free plug whose FAR end DRIVES the rope (held, seated, or a static anchor),
## keep the plug from lagging past rest_length — remove any velocity taking it further out and reel
## the overshoot in at a bounded speed. This is what makes a carried loose cable drag like a line
## instead of a rubber band, without the whip a stiffened spring gives a light body.
func _tow_free_ends(delta: float) -> void:
	_tow_free_end(_anchor_a, socket_a, _anchor_b, socket_b, delta)
	_tow_free_end(_anchor_b, socket_b, _anchor_a, socket_a, delta)


func _tow_free_end(endpoint: Node3D, socket: CableSocket, far_endpoint: Node3D,
		far_socket: CableSocket, delta: float) -> void:
	# Only a bare free plug (unsocketed, dynamic, not carried) is towed by this constraint.
	if endpoint == null or far_endpoint == null or socket != null or delta <= 0.0:
		return
	if endpoint.has_method("is_held") and endpoint.is_held():
		return
	var body := endpoint as RigidBody3D
	if body == null or body.freeze:
		return
	# The far end must ANCHOR the rope (held/seated/static — no tension receiver). If it is itself a
	# loose free body, neither end is authored and clamping both would fight; let the spring settle.
	if _tension_receiver(far_endpoint, far_socket) != null:
		return
	var far_pin := _endpoint_pin(far_endpoint)
	var to_end := body.global_position - far_pin
	var gap := to_end.length()
	if gap <= rest_length or gap < 1e-4:
		return
	var n := to_end / gap  # unit vector pointing OUTWARD, from the anchoring pin toward the plug
	# Reel the overshoot in over a few ticks (BETA), capped so a big yank can't rocket the plug.
	var reel := minf((gap - rest_length) * FREE_TOW_REEL_BETA / delta, FREE_TOW_REEL_MAX)
	var v_out := body.linear_velocity.dot(n)  # + = drifting further from the anchor
	# Target inward speed -reel: if the plug is moving out (or in slower than the reel), correct it.
	if v_out > -reel:
		body.sleeping = false
		body.linear_velocity += n * (-reel - v_out)


## True while `receiver` reports a contact with a foreign RigidBody3D — the
## cable's own plug bodies and any seated end's mount don't count (a plug
## resting against its own assembly is not a shove target). Requires the
## receiver to have contact_monitor enabled (the plugs do, CablePlug._ready);
## a receiver without it (a cube mount) reports no bodies and is simply never
## clamped, which is the intended tow behaviour. Static floors/walls are
## filtered by the RigidBody3D cast.
func _receiver_touching_dynamic(receiver: RigidBody3D) -> bool:
	if not receiver.contact_monitor:
		return false
	for body in receiver.get_colliding_bodies():
		var rb := body as RigidBody3D
		if rb == null or rb == _anchor_a or rb == _anchor_b:
			continue
		if socket_a != null and rb == socket_a.mount_body():
			continue
		if socket_b != null and rb == socket_b.mount_body():
			continue
		return true
	return false


## The RigidBody3D an endpoint's tension force lands on, or null when the end
## must be left alone (the ADR 0046 state table):
##   HELD          plug carried on the hold beam        -> null (player-authored)
##   SEATED        plug in a static-mounted socket      -> null (infinite-mass anchor)
##   ATTACHED-held plug on a cube the player is carrying-> null (cube is authored)
##   ATTACHED-free plug on a loose cube                 -> the cube (drags along)
##   FREE          loose dynamic plug                   -> the plug
func _tension_receiver(endpoint: Node3D, socket: CableSocket) -> RigidBody3D:
	if endpoint == null:
		return null
	if endpoint.has_method("is_held") and endpoint.is_held():
		return null
	if socket != null:
		var mount := socket.mount_body() as RigidBody3D
		if mount == null:
			return null
		if mount.freeze:
			return null
		if mount.has_method("is_held") and mount.is_held():
			return null
		return mount
	var body := endpoint as RigidBody3D
	if body == null or body.freeze:
		return null
	return body


## Elastic breakaway (ADR 0046 mechanism 3): the stretch ratio must hold past
## BREAKAWAY_RATIO for BREAKAWAY_TIME continuously — a momentary yank never
## pops a connection. With the free-end tow (see _tow_free_end) holding a
## FOLLOWABLE loose end well under BREAKAWAY_RATIO, reaching this threshold now
## means the cable genuinely CAN'T follow — snagged on geometry, or walked away
## from faster than it reels — so the breakaway becomes the release valve for a
## stuck cable rather than something that fires during a normal carry.
func _update_breakaway(delta: float, length: float) -> void:
	if length > rest_length * BREAKAWAY_RATIO:
		_breakaway_time += delta
		if _breakaway_time >= BREAKAWAY_TIME:
			_break_away(length)
			_breakaway_time = 0.0
	else:
		_breakaway_time = 0.0


## Break whichever end CAN give, so an overstretched pull always releases with a little elastic
## recoil instead of going dead-taut. The endpoint decides HOW it gives (its duck-typed
## break_connection): a seated plug pops out of its socket, a held plug drops from the player's
## hands, a bolted-in (fixed) end or a bare anchor gives nothing. The recoil is the same
## neighbour-point local direction the tension uses, at the freed end, so the plug whips back
## ALONG the cable toward the far end rather than through geometry; magnitude scales with the
## overstretch excess, clamped.
##
## Two passes: pass 1 (allow_held = false) sacrifices a SEATED end first, keeping the player's grip
## (so an over-pulled cable pops out of a socket/cube before it leaves your hand); only pass 2
## (allow_held = true) drops a HELD plug, for when nothing else could give — the far end is bolted
## down, OR it is a loose end the cable can no longer follow (snagged, or out-walked past the tow's
## reel). The free-end tow keeps a followable loose end under BREAKAWAY_RATIO, so reaching pass 2
## against one means it is genuinely stuck. End B is tried before A within each pass (tiebreak kept
## from the seat-preference history).
func _break_away(length: float) -> void:
	var last := points.size() - 1
	for allow_held: bool in [false, true]:
		for which: int in [1, 0]:
			var endpoint := _anchor_b if which == 1 else _anchor_a
			if endpoint == null or not endpoint.has_method("break_connection"):
				continue
			var idx := last if which == 1 else 0
			var n_idx := last - 1 if which == 1 else 1
			var dir := points[n_idx] - points[idx]
			if dir.length_squared() < 1e-12:
				continue
			var recoil := dir.normalized() * clampf(
					BREAKAWAY_IMPULSE_PER_METER * (length - rest_length),
					BREAKAWAY_IMPULSE_MIN, BREAKAWAY_IMPULSE_MAX)
			if endpoint.break_connection(recoil, allow_held):
				return


func _process(_delta: float) -> void:
	if _tube == null or points.size() < 2:
		return
	_tube_mesh.clear_surfaces()
	var line := _render_polyline()
	if line.size() >= 2:
		_add_tube_surface(_tube_mesh, _smooth(line))


## This frame's on-screen polyline: points[] interpolated toward this tick's
## positions for smooth rendering between physics ticks, with the two endpoints
## replaced by their live RENDER pins (a held plug's body is authored one frame
## ahead of the physics, so its render pin leads points[0]/points[last]).
func _render_polyline() -> PackedVector3Array:
	var count := points.size()
	var fraction := Engine.get_physics_interpolation_fraction()
	var pos := PackedVector3Array()
	pos.resize(count)
	for i in count:
		pos[i] = _points_prev_tick[i].lerp(points[i], fraction)
	if _anchor_a != null:
		pos[0] = _endpoint_render_pin(_anchor_a)
	if _anchor_b != null:
		pos[count - 1] = _endpoint_render_pin(_anchor_b)
	return pos


static func _catmull_rom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (p1 * 2.0 + (p2 - p0) * t \
			+ (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * t2 \
			+ (p1 * 3.0 - p0 - p2 * 3.0 + p3) * t3)


## Catmull-Rom subdivision of the polyline, render-only: TUBE_SUBDIV smoothed
## points per segment, endpoints kept exact. The sim stays untouched — this is
## purely what the tube is skinned over.
func _smooth(line: PackedVector3Array) -> PackedVector3Array:
	var count := line.size()
	if count < 3 or TUBE_SUBDIV < 2:
		return line
	var out := PackedVector3Array()
	out.resize((count - 1) * TUBE_SUBDIV + 1)
	var k := 0
	for i in count - 1:
		var p0 := line[maxi(i - 1, 0)]
		var p1 := line[i]
		var p2 := line[i + 1]
		var p3 := line[mini(i + 2, count - 1)]
		for j in TUBE_SUBDIV:
			var t := float(j) / float(TUBE_SUBDIV)
			out[k] = _catmull_rom(p0, p1, p2, p3, t)
			k += 1
	out[k] = line[count - 1]
	return out


## Skin one polyline run as a surface of `mesh`: TUBE_SIDES-sided rings along the
## polyline, triangles between consecutive rings, flat end caps.
func _add_tube_surface(mesh: ImmediateMesh, line: PackedVector3Array) -> void:
	var count := line.size()
	if count < 2:
		return
	var rings: Array[PackedVector3Array] = []
	var ring_normals: Array[PackedVector3Array] = []
	for i in count:
		var prev := line[maxi(i - 1, 0)]
		var next := line[mini(i + 1, count - 1)]
		var tangent := next - prev
		if tangent.length_squared() < 1e-12:
			tangent = Vector3.FORWARD
		tangent = tangent.normalized()
		var up := Vector3.UP if absf(tangent.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		var side_vec := tangent.cross(up).normalized()
		var side_up := side_vec.cross(tangent)
		var ring := PackedVector3Array()
		var norms := PackedVector3Array()
		ring.resize(TUBE_SIDES)
		norms.resize(TUBE_SIDES)
		for s in TUBE_SIDES:
			var angle := TAU * float(s) / float(TUBE_SIDES)
			var normal := side_vec * cos(angle) + side_up * sin(angle)
			ring[s] = line[i] + normal * radius
			norms[s] = normal
		rings.append(ring)
		ring_normals.append(norms)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in count - 1:
		for s in TUBE_SIDES:
			var s2 := (s + 1) % TUBE_SIDES
			_add_vertex(mesh, ring_normals[i][s], rings[i][s])
			_add_vertex(mesh, ring_normals[i + 1][s], rings[i + 1][s])
			_add_vertex(mesh, ring_normals[i][s2], rings[i][s2])
			_add_vertex(mesh, ring_normals[i][s2], rings[i][s2])
			_add_vertex(mesh, ring_normals[i + 1][s], rings[i + 1][s])
			_add_vertex(mesh, ring_normals[i + 1][s2], rings[i + 1][s2])
	_add_cap(mesh, line[0], rings[0], (line[0] - line[1]).normalized())
	_add_cap(mesh, line[count - 1], rings[count - 1],
			(line[count - 1] - line[count - 2]).normalized())
	mesh.surface_end()


func _add_cap(mesh: ImmediateMesh, center: Vector3, ring: PackedVector3Array, normal: Vector3) -> void:
	for s in TUBE_SIDES:
		var s2 := (s + 1) % TUBE_SIDES
		_add_vertex(mesh, normal, center)
		_add_vertex(mesh, normal, ring[s])
		_add_vertex(mesh, normal, ring[s2])


func _add_vertex(mesh: ImmediateMesh, normal: Vector3, vertex: Vector3) -> void:
	mesh.surface_set_normal(normal)
	mesh.surface_add_vertex(vertex)
