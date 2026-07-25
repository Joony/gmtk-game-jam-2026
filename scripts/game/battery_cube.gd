class_name BatteryCube
extends Interactable

# A carryable power cube (new — not in Doortal). Plug a wall-powered cable into its port and it
# charges; carry it to a device that has no wall socket in reach and a cable from the cube powers
# that device until the cube runs flat. This is the third answer to "is this fix worth the air?" —
# paid in walking rather than in parts.
#
# Like CablePlug, this is an Interactable (PICKUP) script on a RigidBody3D, so body ops go through
# `_body` (self, laundered through Node — see cable_plug.gd for why). The port CableSocket lives on
# a child face and the cube is its mount_body(), so a taut cable drags the cube around by its port.
#
# POWER MODEL. The port is a CableSocket whose is_power_source the cube drives from its charge
# (source while charge > 0, dead when flat). Which way energy flows is read off the cable graph,
# NOT off the port's own feed (a port can't be both fed and sourcing):
#   * the far end of the plugged cable is an external live SOURCE (a wall socket) -> CHARGING,
#   * the far end is anything else (a device SINK the cube is powering)            -> DRAINING,
#   * nothing plugged, or flat with only a sink                                    -> IDLE.
# When the charge crosses zero the port's source flag flips and the cable re-propagates, so a
# device dies the instant the cube runs out.

enum Flow { IDLE, CHARGING, DRAINING }

## Seconds of run-time the cube holds at a full charge.
@export var capacity: float = 20.0
## Charge gained per second while plugged into a live source.
@export var charge_rate: float = 8.0
## Charge spent per second while powering a sink.
@export var drain_rate: float = 4.0
@export var port_path: NodePath = NodePath("Port")
## Number of emissive charge bars to build along the top face.
@export var bar_count: int = 5

const BAR_LIT := Color(0.24, 0.90, 0.40)
const BAR_DARK := Color(0.06, 0.09, 0.07)

var charge: float = 0.0

var _body: RigidBody3D = null
var _port: CableSocket = null
var _bar_mats: Array[StandardMaterial3D] = []
var _is_source := false


func _ready() -> void:
	super()  # Interactable._ready
	interaction_type = InteractionType.PICKUP
	var this_node: Node = self
	_body = this_node as RigidBody3D
	if _body == null:
		push_error("BatteryCube must be attached to a RigidBody3D node")
		return
	_port = get_node_or_null(port_path) as CableSocket
	if _port == null:
		push_error("BatteryCube.port_path did not resolve to a CableSocket")
		return
	_build_bars()
	_refresh_source(true)
	_update_bars()


## Charge as a 0..1 fraction — for the HUD or a device readout.
func charge_fraction() -> float:
	return 0.0 if capacity <= 0.0 else clampf(charge / capacity, 0.0, 1.0)


# --- Interaction: PICKUP empty-handed, USE_ITEM (plug the cable in) while holding a plug ---------
# Looking at the whole cube counts, not just the tiny port, so you can plug in by looking at the
# battery and pressing E — the standard use-item interaction — instead of nosing the plug into
# snap range.

func _holding_plug(item: Node3D) -> bool:
	return item != null and item.has_method("plug_into")


func get_interaction_type(held_item: Node3D = null) -> InteractionType:
	if not is_enabled:
		return InteractionType.DISABLED
	return InteractionType.USE_ITEM if _holding_plug(held_item) else InteractionType.PICKUP


func can_act_on(held_item: Node3D = null) -> bool:
	if not is_enabled:
		return false
	if _holding_plug(held_item):
		return _port != null and _port.can_accept(held_item)
	return held_item == null  # empty-handed: pick the cube up


func get_interaction_text(held_item: Node3D = null) -> String:
	if _holding_plug(held_item):
		if _port != null and _port.can_accept(held_item):
			return "Plug in cable"
		return "Port in use"
	return interaction_text


func can_use_with_item(item: Node3D) -> bool:
	return _holding_plug(item) and _port != null and _port.can_accept(item)


func use_with_item(item: Node3D) -> void:
	if not can_use_with_item(item):
		return
	var plug := item as CablePlug
	if plug != null and plug.plug_into(_port):
		used_with_item.emit(self, item)


func _physics_process(delta: float) -> void:
	if _port == null:
		return
	match _flow():
		Flow.CHARGING:
			charge = minf(capacity, charge + charge_rate * delta)
		Flow.DRAINING:
			charge = maxf(0.0, charge - drain_rate * delta)
	_refresh_source()
	_update_bars()


# Which way energy is flowing this tick, read off the cable plugged into the port.
func _flow() -> Flow:
	var cable := _plugged_cable()
	if cable == null:
		return Flow.IDLE
	var other := _far_socket(cable)
	# The far end being a powered source (a wall socket) means we're plugged into mains -> charge.
	if other != null and other != _port and other.is_power_source and other.powered:
		return Flow.CHARGING
	# Otherwise the cable runs to a sink we feed: drain while we have anything left.
	if other != null and charge > 0.0:
		return Flow.DRAINING
	return Flow.IDLE


# The Cable3D whose plug is seated in our port (via the plug's `cable` back-ref), or null.
func _plugged_cable() -> Cable3D:
	var plug := _port.occupied_by
	if plug == null or not ("cable" in plug):
		return null
	return plug.get("cable") as Cable3D


# The socket at the OTHER end of `cable` from our port.
func _far_socket(cable: Cable3D) -> CableSocket:
	if cable.socket_a == _port:
		return cable.socket_b
	if cable.socket_b == _port:
		return cable.socket_a
	return null


# Drive the port's source flag from the charge and, when it flips, re-propagate power through any
# plugged cable so a fed device turns on/off with the cube.
func _refresh_source(force: bool = false) -> void:
	var want := charge > 0.0
	if want == _is_source and not force:
		return
	_is_source = want
	_port.set_source(want)
	var cable := _plugged_cable()
	if cable != null:
		cable.refresh_power()


# A row of small emissive bars on the top face, each with its OWN StandardMaterial3D so every
# battery shows its own charge (the RepairPoint status-light trick — a shared material would tint
# every cube in the ship alike).
func _build_bars() -> void:
	var holder := Node3D.new()
	holder.name = "ChargeBars"
	add_child(holder)
	var n := maxi(bar_count, 1)
	var span := 0.28
	var bar_w := span / float(n) * 0.7
	for i in n:
		var bar := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(bar_w, 0.015, 0.06)
		bar.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bar.material_override = mat
		var x := -span * 0.5 + span * (float(i) + 0.5) / float(n)
		bar.position = Vector3(x, 0.205, 0.0)  # sit on the +Y top face (cube half-extent ~0.2)
		holder.add_child(bar)
		_bar_mats.append(mat)


func _update_bars() -> void:
	var lit := int(round(charge_fraction() * float(_bar_mats.size())))
	for i in _bar_mats.size():
		var on := i < lit
		var color := BAR_LIT if on else BAR_DARK
		_bar_mats[i].albedo_color = color
		_bar_mats[i].emission_enabled = on
		_bar_mats[i].emission = color
