class_name SocketPowerRepair
extends Node

# Bridges a CableSocket's power to a Malfunction's PERMANENT repair: the "third answer" to a fault
# (TODO 14d). This system can only be fixed by feeding it power — there is no patch panel — so the
# fix is paid in the walk to bring a feed here (run a cable the long way, or charge the battery and
# carry it), not in a spare part. The moment the inlet goes live while the fault is active, the
# system comes back for good; unplugging afterwards doesn't re-break it (the feed did its job).
#
# Deliberately the ONLY cable-to-repair coupling point, mirroring PortalPowerAdapter's role in
# Doortal: the cables addon stays free of the game's Malfunction type.

## Status colours match RepairPoint so the ship reads consistently.
const COLOR_BROKEN := Color(1.00, 0.16, 0.12)
const COLOR_FIXED := Color(0.24, 0.90, 0.40)

@export var socket_path: NodePath
@export var malfunction_path: NodePath
@export var status_light_path: NodePath

var _socket: CableSocket = null
var _malfunction: Malfunction = null
var _light_material: StandardMaterial3D = null


func _ready() -> void:
	_socket = get_node_or_null(socket_path) as CableSocket
	_malfunction = get_node_or_null(malfunction_path) as Malfunction
	if _socket == null or _malfunction == null:
		push_error("SocketPowerRepair: socket_path/malfunction_path did not resolve")
		return

	var light := get_node_or_null(status_light_path) as MeshInstance3D
	if light != null:
		# Per-instance material so every powered device shows its own state (the RepairPoint trick).
		_light_material = StandardMaterial3D.new()
		_light_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		light.material_override = _light_material

	# Fix on either edge: the inlet going live while broken, or the fault breaking while already fed.
	_socket.power_changed.connect(_on_change)
	_malfunction.broke.connect(_on_broke)
	_malfunction.repaired.connect(_on_repaired)
	# Initial paint + a deferred try (the socket announces an initial source state deferred).
	_refresh_light()
	_try_repair.call_deferred()


func _on_change(_powered: bool) -> void:
	_try_repair()
	_refresh_light()


func _on_broke(_m: Malfunction, _was_patch_failure: bool) -> void:
	_try_repair()
	_refresh_light()


func _on_repaired(_m: Malfunction, _permanent: bool) -> void:
	_refresh_light()


# Repair the moment the fault is active AND the inlet is powered.
func _try_repair() -> void:
	if _malfunction.is_active and _socket.powered:
		_malfunction.repair(true)


func _refresh_light() -> void:
	if _light_material == null:
		return
	var color := COLOR_BROKEN if _malfunction.is_active else COLOR_FIXED
	_light_material.albedo_color = color
	_light_material.emission_enabled = true
	_light_material.emission = color
