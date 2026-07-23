class_name RepairPoint
extends Interactable

# The panel you walk to. Child of a Malfunction, which supplies everything it needs to say.
#
# ONE node offers BOTH repair routes, which is why the patch-vs-proper choice cost almost
# no new machinery: Interactable already dispatches on whether your hands are full.
#
#   empty hands   -> Interactor._activate() -> interact()      -> patch
#   holding part  -> Interactor            -> use_with_item()  -> proper fix, part consumed
#
# So the decision is expressed purely by what you chose to bring, with no second key, no
# radial menu and no new input action. The walk to fetch the part IS the price of the
# permanent fix, and since walking costs oxygen, the price is paid in the game's currency.
#
# `interaction_type` must stay USE_ITEM for that dispatch to work — ACTIVATE would send a
# held part down the drop path instead.

## Status colours. Green is deliberately absent from the palette elsewhere, so a green
## panel across a dark engine room reads instantly as "that one's done".
const COLOR_BROKEN := Color(1.00, 0.16, 0.12)
const COLOR_PATCHED := Color(1.00, 0.62, 0.10)
const COLOR_FIXED := Color(0.24, 0.90, 0.40)

## Group a carried item must be in to count as a usable spare. Spares are deliberately
## GENERIC and scarce rather than one bespoke part per system: with a named part sitting
## ready for every fault, the permanent fix cost nothing beyond the patch and there was
## never a reason to choose the patch at all. Making spares fungible and fewer than the
## faults turns "which systems are worth a real fix?" into the run's central decision.
@export var required_part_group: StringName = &"spare_parts"
## Optional exact instance name, for a one-off bespoke part. Empty means "any spare".
@export var required_part: String = ""
## Verb shown for the patch route, e.g. "Tape the coupling".
@export var patch_text: String = "Patch it"
## Verb shown for the proper route.
@export var fit_text: String = "Fit spare part"
@export var status_light_path: NodePath = NodePath("StatusLight")

@export_group("State visuals")
## Nodes shown only while the fault is ACTIVE — the crack, the escaping gas.
@export var broken_nodes: Array[NodePath] = []
## Nodes shown only while running on a PATCH. This is what makes the two repair routes
## legible: a bodge you can see is a bodge, sitting there reminding you it will fail.
@export var patched_nodes: Array[NodePath] = []
## Nodes shown only once PERMANENTLY repaired — the intact part.
@export var fixed_nodes: Array[NodePath] = []
## Nodes shown while the system is broken OR running on a patch, i.e. anything but properly
## fixed. Needed because the vent pipe swaps between two whole models: the ruptured pipe has
## to stay visible under the tape, and a node cannot live in two of the lists above — they
## are applied in order, so the later one always wins and the node just disappears.
@export var damaged_nodes: Array[NodePath] = []

var malfunction: Malfunction = null

var _status_material: StandardMaterial3D = null
var _consumed: bool = false


func _ready() -> void:
	super()
	interaction_type = InteractionType.USE_ITEM
	if required_part != "" and accepted_item_names.is_empty():
		accepted_item_names = [required_part]

	var light := get_node_or_null(status_light_path) as MeshInstance3D
	if light != null:
		# Per-instance material: panels share a scene, so mutating the shared resource
		# would light every panel in the ship the same colour.
		_status_material = StandardMaterial3D.new()
		_status_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		light.material_override = _status_material

	if malfunction == null and get_parent() is Malfunction:
		bind(get_parent() as Malfunction)
	refresh()


func bind(target: Malfunction) -> void:
	malfunction = target


## Repaint the status light and re-enable/disable targeting. Called by Malfunction on
## every state change, so the panel can never show a stale colour.
func refresh() -> void:
	var broken := malfunction != null and malfunction.is_active
	# A working panel stops being a ray target entirely — otherwise the reticle would
	# keep offering prompts on the dozen panels you have already dealt with.
	is_enabled = broken
	var patched := malfunction != null and malfunction.is_patched
	_show(broken_nodes, broken)
	_show(patched_nodes, patched)
	_show(damaged_nodes, broken or patched)
	_show(fixed_nodes, not broken and not patched)

	if _status_material == null:
		return
	var color := COLOR_FIXED
	if broken:
		color = COLOR_BROKEN
	elif patched:
		color = COLOR_PATCHED
	_status_material.albedo_color = color
	_status_material.emission_enabled = true
	_status_material.emission = color


func _show(paths: Array[NodePath], visible_now: bool) -> void:
	for path in paths:
		var node := get_node_or_null(path)
		if node == null:
			continue
		if node is Node3D:
			(node as Node3D).visible = visible_now
		# Hiding a particle system leaves its already-spawned puffs hanging in the air
		# until they expire, so stop it emitting as well.
		if node is CPUParticles3D:
			(node as CPUParticles3D).emitting = visible_now


# Broken panels are always actionable: with empty hands you can always patch. The base
# class would grey the reticle out whenever you were not carrying the right part, which
# would hide the patch route exactly when the player most needs to know it exists.
func can_act_on(_held_item: Node3D = null) -> bool:
	return is_enabled


func get_interaction_text(held_item: Node3D = null) -> String:
	if malfunction == null or not malfunction.is_active:
		return "%s: nominal" % _label()
	if held_item != null:
		if can_use_with_item(held_item):
			return "%s  (permanent)" % fit_text
		return "Wrong part for %s" % _label()
	var cost := ""
	if malfunction.bodge_oxygen_cost > 0.0:
		cost = "  (costs %ds air)" % int(round(malfunction.bodge_oxygen_cost))
	return "%s  (temporary)%s" % [patch_text, cost]


func interact() -> void:
	# Empty-handed press: the patch route.
	if malfunction == null or not malfunction.is_active:
		return
	malfunction.repair(false)
	interacted_with.emit(self)


func use_with_item(item: Node3D) -> void:
	_consumed = false
	if malfunction == null or not malfunction.is_active:
		return
	if not can_use_with_item(item):
		return
	malfunction.repair(true)
	# The part is welded in — it is gone from the world. That is what stops one spare
	# being walked around the ship fixing everything, and it is the seed of the
	# cannibalise branch: parts become the scarce thing.
	_consumed = true
	used_with_item.emit(self, item)


## True when the last use_with_item() actually consumed the item, so Interactor knows
## to take it out of the player's hands and free it.
func consumed_last_item() -> bool:
	return _consumed


## A spare fits if it is a spare. The base class matches on exact instance names, which
## is still honoured when `required_part` is set for a one-off.
func can_use_with_item(item: Node3D) -> bool:
	if required_part_group != &"" and not item.is_in_group(required_part_group):
		return false
	return super(item)


func _label() -> String:
	return malfunction.system_name if malfunction != null else "Panel"
