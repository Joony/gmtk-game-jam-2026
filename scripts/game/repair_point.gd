class_name RepairPoint
extends Interactable

# The panel you walk to. Child of a Malfunction, which supplies everything it needs to say.
#
# ONE node offers BOTH repair routes, which is why the patch-vs-proper choice cost almost
# no new machinery: Interactable already dispatches on what is in your hands.
#
#   holding hammer -> use_with_item() -> PATCH, hammer kept
#   holding part   -> use_with_item() -> PROPER fix, part consumed
#   empty hands    -> interact()      -> nothing, and the prompt says why
#
# So the decision is expressed purely by what you chose to bring, with no second key, no
# radial menu and no new input action. The walk to fetch the part IS the price of the
# permanent fix, and since walking costs oxygen, the price is paid in the game's currency.
#
# THE HAMMER. Patching used to be the empty-handed route, which made it free — the fallback
# you could always fall back to, from anywhere, having planned nothing. It now takes the
# hammer out of the janitor's closet, so the bodge costs a trip of its own the first time and
# a hand for the rest of the run. Unlike a spare it is not consumed: it is a tool, and one
# hammer serves the whole ship.
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
## Group a carried item must be in to bodge this shut. One hammer, kept, not consumed —
## so this is a trip you make once, unlike the per-fault hunt for a spare.
@export var tool_group: StringName = &"repair_tools"
## Optional exact instance name, for a one-off bespoke part. Empty means "any spare".
@export var required_part: String = ""
## Whether the permanent fix CONSUMES what fixed it. True for a spare part, which is welded in
## and gone — that scarcity is the whole point of the spares economy. False for something that
## is really a tool wearing a part's clothes: the oil can permanently frees a seized crawler
## and you keep the can, the same way the hammer is kept. Without this the single can would be
## spent on the first crawler and the fault could never be cleared again when it recurs.
@export var consumes_part: bool = true
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

## Where to put the indicator on a prop that carries neither an `Indicator` empty nor a
## `StatusLight` mesh, in metres from its origin.
@export var indicator_offset: Vector3 = Vector3(0.0, 0.0, 0.1)
## Off for a repair point used purely as LOGIC — the nav computer borrows one for its
## hammer-versus-part dispatch and prompt wording while showing the fault on its own screen.
## Without this the helper would hang a second light in mid-air beside the terminal.
@export var show_indicator: bool = true

var _indicator: IndicatorLight = null
var _consumed: bool = false


func _ready() -> void:
	setup()


## Everything _ready() does, callable on its own — for a repair point that is a MODEL rather
## than the panel prop. TODO 21a: when a system has geometry of its own, that geometry is the
## thing you walk up to and fix, and a panel bolted beside it is the fallback for systems with
## none. Adopting works by attaching this script to the model at runtime, and Godot does not
## re-run _ready() after set_script() on a node already in the tree.
##
## Idempotent, so calling it on a panel that came up the ordinary way is harmless.
func setup() -> void:
	add_to_group(&"interactables")  # what Interactable._ready() does
	interaction_type = InteractionType.USE_ITEM
	if required_part != "" and accepted_item_names.is_empty():
		accepted_item_names = [required_part]
	if _indicator == null:
		# Finds the model's own `Indicator` empty when there is one, and falls back to the
		# panel prop's StatusLight mesh otherwise. See IndicatorLight.
		_indicator = IndicatorLight.attach(self, indicator_offset)
	if malfunction == null and get_parent() is Malfunction:
		bind(get_parent() as Malfunction)
	refresh()


func bind(target: Malfunction) -> void:
	malfunction = target


## Repaint the status light and re-enable/disable targeting. Called by Malfunction on
## every state change, so the panel can never show a stale colour.
func refresh() -> void:
	var broken := malfunction != null and malfunction.is_active
	var patched := malfunction != null and malfunction.is_patched
	# A panel stays a ray target while PATCHED as well as while broken, because a bodge leaves
	# the system permanently down on power and fitting a spare is how you get it back. Only a
	# properly repaired panel goes quiet — otherwise the reticle would keep offering prompts on
	# the dozen systems you have already dealt with.
	is_enabled = broken or patched
	_show(broken_nodes, broken)
	_show(patched_nodes, patched)
	_show(damaged_nodes, broken or patched)
	_show(fixed_nodes, not broken and not patched)

	if _indicator == null:
		return
	var color := COLOR_FIXED
	if broken:
		color = COLOR_BROKEN
	elif patched:
		color = COLOR_PATCHED
	# A CRITICAL fault flashes. Colour alone says which of three states a system is in; the
	# flash says whether it needs dealing with now, and that is the distinction that has to
	# survive being seen out of the corner of your eye while walking past.
	_indicator.set_state(color, malfunction != null and malfunction.is_critical())


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


# A broken panel stays lit whatever is in your hands, even though empty hands can no longer
# repair it. The base class would grey the reticle out unless you were holding the right part,
# and a dead prompt is how a player concludes a panel is scenery — this is the only place the
# game ever tells them the hammer exists.
func can_act_on(_held_item: Node3D = null) -> bool:
	return is_enabled


func get_interaction_text(held_item: Node3D = null) -> String:
	if malfunction == null:
		return "%s: nominal" % _label()
	# Running on a bodge: still down on power, and a spare part is the only way to get it back.
	# Naming the number is what makes the offer worth taking — "nominal" here would have been a
	# lie, and silence would have read as a panel with nothing left to do.
	if not malfunction.is_active:
		if not malfunction.is_patched:
			return "%s: nominal" % _label()
		var lost := ""
		if malfunction.speed_decay > 0.0:
			lost = "  (-%d%% drive)" % int(round(malfunction.speed_decay * 100.0))
		if held_item != null and can_use_with_item(held_item) and not is_tool(held_item):
			return "%s  (permanent)%s" % [fit_text, lost]
		return "%s: bodged%s — needs a spare part" % [_label(), lost]
	if is_tool(held_item):
		# Say what the bodge LOCKS IN, not just that it is temporary. A critical fault keeps
		# whatever speed it has already taken, and the player cannot weigh the two routes
		# against each other without that number in front of them.
		var kept := ""
		if malfunction.speed_decay > 0.0:
			kept = "  (keeps -%d%% drive)" % int(round(malfunction.speed_decay * 100.0))
		var cost := ""
		if malfunction.bodge_oxygen_cost > 0.0:
			cost = "  (costs %ds air)" % int(round(malfunction.bodge_oxygen_cost))
		return "%s  (temporary)%s%s" % [patch_text, kept, cost]
	if held_item != null:
		if can_use_with_item(held_item):
			return "%s  (permanent)" % fit_text
		return "Wrong part for %s" % _label()
	# Empty-handed is no longer a repair route, so the prompt has to name what is missing.
	# Silence here would read as a broken panel rather than as a thing you have not fetched.
	return "%s: need a spare part, or the hammer to bodge it" % _label()


func interact() -> void:
	# Empty hands. Nothing to do — the prompt above explains why.
	pass


## True for the hammer: the thing that bodges rather than fixes.
func is_tool(item: Node3D) -> bool:
	return item != null and tool_group != &"" and item.is_in_group(tool_group)


func use_with_item(item: Node3D) -> void:
	_consumed = false
	if malfunction == null:
		return
	# A bodged system takes a spare part but not another bodge — you cannot bodge a bodge.
	if not malfunction.is_active and not malfunction.is_patched:
		return
	# The hammer bodges and is KEPT. One tool serves the whole ship, so it is never consumed
	# — losing it to the first panel would strand the player with no patch route at all.
	if is_tool(item):
		if not malfunction.is_active:
			return
		malfunction.repair(false)
		used_with_item.emit(self, item)
		return
	if not can_use_with_item(item):
		return
	malfunction.repair(true)
	# The part is welded in — it is gone from the world. That is what stops one spare
	# being walked around the ship fixing everything, and it is the seed of the
	# cannibalise branch: parts become the scarce thing.
	#
	# Unless it is a can of oil, which you keep. See `consumes_part`.
	_consumed = consumes_part
	used_with_item.emit(self, item)


## True when the last use_with_item() actually consumed the item, so Interactor knows
## to take it out of the player's hands and free it.
func consumed_last_item() -> bool:
	return _consumed


## A spare fits if it is a spare, and the hammer is always usable here — otherwise the
## reticle would grey out on a panel you are stood in front of holding the very tool for it.
## The base class matches on exact instance names, which is still honoured when
## `required_part` is set for a one-off.
func can_use_with_item(item: Node3D) -> bool:
	if is_tool(item):
		return true
	if required_part_group != &"" and not item.is_in_group(required_part_group):
		return false
	return super(item)


func _label() -> String:
	return malfunction.system_name if malfunction != null else "Panel"
