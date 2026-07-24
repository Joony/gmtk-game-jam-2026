class_name WallSocket
extends Interactable

# A wall-mounted CableSocket you plug a held cable into by looking at it and pressing E — the same
# USE_ITEM interaction as the battery, minus the pickup. A child Port (CableSocket) does the actual
# socketing and shows the receptacle model; this script just presents the interaction.
#
# Attach to a StaticBody3D so the camera ray can hit it. The Port's mount_body() then resolves to
# that body, so a seated plug collision-excepts it (the plug overlaps the socket by design) — and
# because it is STATIC, a seated end is an infinite-mass anchor (no tension), exactly like a wall.

## A source socket is always powered and feeds whatever is plugged in; a sink starts dead and is
## fed only through a powered cable.
@export var is_power_source: bool = false
@export var port_path: NodePath = NodePath("Port")

var _port: CableSocket = null


func _ready() -> void:
	super()  # Interactable._ready: register in the interactables group
	interaction_type = InteractionType.USE_ITEM
	_port = get_node_or_null(port_path) as CableSocket
	if _port == null:
		push_error("WallSocket.port_path did not resolve to a CableSocket")
		return
	# Drive it live AFTER the socket's own _ready (set_source updates powered + announces), rather
	# than relying on the port node's exported flag.
	if is_power_source:
		_port.set_source(true)


func _holding_plug(item: Node3D) -> bool:
	return item != null and item.has_method("plug_into")


# USE_ITEM only while you hold a plug; otherwise there is nothing to do here (you can't pick up a
# wall fixture), so it reads as DISABLED and the reticle stays grey with no prompt.
func get_interaction_type(held_item: Node3D = null) -> InteractionType:
	if not is_enabled:
		return InteractionType.DISABLED
	return InteractionType.USE_ITEM if _holding_plug(held_item) else InteractionType.DISABLED


func can_act_on(held_item: Node3D = null) -> bool:
	return is_enabled and _holding_plug(held_item) and _port != null and _port.can_accept(held_item)


func get_interaction_text(held_item: Node3D = null) -> String:
	if _holding_plug(held_item):
		if _port != null and _port.can_accept(held_item):
			return "Plug in cable"
		return "Socket in use"
	return ""


func can_use_with_item(item: Node3D) -> bool:
	return _holding_plug(item) and _port != null and _port.can_accept(item)


func use_with_item(item: Node3D) -> void:
	if not can_use_with_item(item):
		return
	var plug := item as CablePlug
	if plug != null and plug.plug_into(_port):
		used_with_item.emit(self, item)
