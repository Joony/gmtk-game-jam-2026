class_name ShipDisplays
extends Node3D

# The ship's readable screens that are not whole props of their own — currently one: the DECK
# PLAN on the bridge terminal bank.
#
# WHY THIS EXISTS AT ALL. `scenes/game.tscn` is locked for editing elsewhere, so the bridge
# display cannot be dragged into the scene, and the terminal bank is already dressed in there as
# decor. So this does at runtime what a scene edit would do at author time — the same route
# `ShipSupplies` takes for the silos and the vending machine, and `RoomVoice` for the tutorial cue.
#
# THE ARTIST DECIDES WHERE THE SCREEN IS. `CD_BridgeTerminals_v2` carries an empty called
# `Display`; the deck plan is parented to it with an identity local transform and inherits its
# position, height and facing. Nothing here contains a measured offset into the model, because a
# measured offset is a number that goes stale the next time the bank is re-modelled.
#
# THE READING POSE IS DERIVED, NOT AUTHORED, for the same reason: where the player stands and how
# far down they look are computed from where the screen actually ended up. See _make_view_point().

## The bank as dressed in game.tscn. v1 has no `Display` empty and v2 does, so if the scene is
## still pointing at v1 this swaps in v2 at the same transform — and when the scene is updated to
## v2, the node already there is adopted instead and nothing is swapped.
const TERMINALS_V2 := preload("res://3D-Models/CD_BridgeTerminals_v2.blend")
const DECK_PLAN := preload("res://scenes/props/deck_plan.tscn")

## The empty inside the model that says where the screen goes.
const DISPLAY_NODE := &"Display"

## Name of the node holding the bridge terminal bank, matched by PREFIX and searched for from the
## whole scene rather than from one parent. It has already moved once — it was under `Decor`, and
## is now a top-level node in `game.tscn` — and it is dressed by hand in a scene this cannot edit,
## so anything that pinned down its parent would break the next time it was rearranged. The
## prefix also means v1 and v2 both answer to it.
@export var terminals_prefix: String = "CD_BridgeTerminals"

## Width of the chart on the table, in metres before the bank's own scale. The measured top is
## 2.16 x 2.38 m, so 2.0 leaves a hand's width of bare table either side; the depth follows from
## the 1024x640 viewport so the drawing is never stretched.
@export var screen_width: float = 2.0
## How far the chart floats above the surface it lies on, in metres. Coplanar geometry z-fights,
## and a table top is exactly the case where the two surfaces are parallel and touching — the same
## reason RoomBuilder gives every door panel its own thickness.
@export var screen_lift: float = 0.004

## THE READING POSE IS AN EYE POSITION, not a standing position, and that is the whole difference
## between reading a wall screen and reading a chart on a table. You do not stand back from a map
## laid flat — you stand OVER it and look down, and at anything less than that the far edge of the
## chart is further away than the near edge and the whole thing reads at an angle.
##
## So these two put the camera above the middle of the chart and slightly aft of it: high enough to
## take the whole page in, back far enough that it is a person leaning over a table rather than a
## ceiling camera. 1.35 up and 0.50 back is about 70 degrees down.
@export var read_height: float = 1.35
@export var read_back: float = 0.50
## Camera anchor above the body origin. Same 0.65 the pod bay console's ViewPoint is measured off,
## and what turns the eye position above into the body position the glide actually moves.
@export var eye_height: float = 0.65

## The bridge display, once built. Null if the terminal bank could not be found.
var bridge_display: ComputerTerminal = null


func build() -> void:
	var host := _adopt_terminals()
	if host == null:
		push_warning("ShipDisplays: no '%s*' anywhere in the scene — no bridge display"
			% terminals_prefix)
		return
	var display := host.find_child(String(DISPLAY_NODE), true, false) as Node3D
	if display == null:
		push_warning("ShipDisplays: %s has no '%s' node — no bridge display" % [
			host.name, DISPLAY_NODE])
		return

	var plan := DECK_PLAN.instantiate()
	display.add_child(plan)
	_fit_screen(plan)

	var map := plan.get_node_or_null(^"SubViewport/StatusMap") as StatusMap
	var view := _make_view_point(display)

	# attach() rather than the NodePath exports: the path would have to name its way down through
	# an imported model, and would break the next time the model was re-exported.
	bridge_display.attach(null, map, view)


## Put the terminal bank under a `ComputerTerminal` so the interaction ray finds it. The ray hits
## the model's own StaticBody3D and `Interactor.find_interactable_in_hierarchy()` walks UP from
## there — so the whole bank becomes readable, from wherever along it the player happens to look,
## rather than only from a small collider stuck over the screen.
func _adopt_terminals() -> Node3D:
	var scene := get_parent()
	if scene == null:
		return null
	# `owned = false`, so a bank that was spawned rather than placed is found too.
	var dressed := scene.find_child("%s*" % terminals_prefix, true, false) as Node3D
	if dressed == null:
		return null
	var parent := dressed.get_parent()

	# The SCALE matters and is easy to lose: the bank is dressed at 0.99, and a display placed at
	# the model's own scale inside a rescaled parent would be the one thing on it drawn at 1:1.
	# Taking the whole transform keeps everything in proportion.
	var at := dressed.global_transform

	bridge_display = ComputerTerminal.new()
	bridge_display.name = "BridgeDisplay"
	# ONE page, so there is nothing to flip to and no automatic choice to make: this screen is the
	# deck plan and says so. The pod bay console keeps the nav plot.
	bridge_display.pages = [ComputerTerminal.Page.STATUS]
	bridge_display.interaction_text = "Read the deck plan"
	add_child(bridge_display)
	bridge_display.global_transform = at

	var host: Node3D = dressed
	if dressed.find_child(String(DISPLAY_NODE), true, false) == null:
		# An older bank with no `Display` empty. Swap in the version that has one rather than
		# guessing where the screen would have been.
		dressed.queue_free()
		host = TERMINALS_V2.instantiate() as Node3D
		bridge_display.add_child(host)
		host.transform = Transform3D.IDENTITY
	else:
		# Already the right model: take the node the scene placed, keeping exactly where it is.
		parent.remove_child(dressed)
		bridge_display.add_child(dressed)
		dressed.transform = Transform3D.IDENTITY
	return host


## Lay the chart flat on the table, size it, and lift it clear.
##
## THE ROTATION IS HERE RATHER THAN IN THE .tscn on purpose. A `.tscn` `Transform3D` literal
## stores its basis ROW-major (docs/debugging-gotchas.md), so writing one from column vectors
## produces the transpose — which for a rotation is the INVERSE. Done that way first time round,
## the quad faced down into the table and the bridge simply had no display on it. `from_euler()`
## has no such trap.
##
## -90 degrees about X puts the quad's face (+Z) up and the map's up (+Y) along -Z, which is the
## ship's heading — so the diagram agrees with the ship, and the labels read upright from the aft
## side, which is the only side of the table there is.
##
## The mesh is DUPLICATED first: a QuadMesh in a scene is a shared sub-resource, so resizing the
## one that came out of the .tscn would resize it for every other instance too. There is only one
## today, and that is exactly the kind of assumption that stops being true quietly.
func _fit_screen(plan: Node) -> void:
	var screen := plan.get_node_or_null(^"Screen") as MeshInstance3D
	if screen == null:
		return
	var quad := (screen.mesh as QuadMesh).duplicate() as QuadMesh
	quad.size = Vector2(screen_width, screen_width * 640.0 / 1024.0)
	screen.mesh = quad
	screen.transform = Transform3D(
		Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0)),
		Vector3(0.0, screen_lift, 0.0))


## Where the player stands to read the plan, and which way they look — both worked out from where
## the screen ended up rather than typed in.
##
## The pitch is the point. Every readable thing on the ship until now was a wall-mounted CRT at eye
## height, so the reading pose was a yaw and nothing else — and `Game._open_nav_screen()` passed a
## hardcoded 0.0 for the pitch, which was invisible right up until a screen sat at waist height.
## Here the camera has to look DOWN at it, by however much the geometry says.
func _make_view_point(display: Node3D) -> Node3D:
	var marker := Marker3D.new()
	marker.name = "ViewPoint"
	display.add_child(marker)

	var centre := display.global_position
	# The chart faces its own +Z once laid flat, so "aft of it" is that direction, flattened.
	var out := display.global_basis.z
	var along := Vector3(out.x, 0.0, out.z)
	if along.length() < 0.001:
		along = Vector3(0.0, 0.0, 1.0)
	along = along.normalized()

	# Where the EYE goes: above the chart, a little aft.
	var eye := centre + Vector3(0.0, read_height, 0.0) + along * read_back
	var look := centre - eye
	var pitch := 0.0
	if look.length() > 0.001:
		pitch = asin(clampf(look.normalized().y, -1.0, 1.0))
	# Yaw measured the way CameraController builds its own basis — from_euler(pitch, yaw, roll),
	# forward being -Z.
	var yaw := atan2(-look.x, -look.z)

	# ...and the body goes under it. `_glide_player()` moves the BODY and the camera anchor rides
	# 0.65 above, so the marker has to carry the body position however the eye was worked out.
	# Above the floor rather than on it, which is correct and not a bug: the player is frozen while
	# reading, the body is invisible from inside its own head, and the glide puts them back exactly
	# where they were standing.
	var stand := eye - Vector3(0.0, eye_height, 0.0)

	marker.global_transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), stand)
	return marker
