@tool
extends RoomBuilder

# The ship, authored in code. Deliberately hand-designed rather than randomly
# generated: the hook makes walking distance the oxygen cost, so randomising the
# geometry would randomise the difficulty. Randomise WHICH systems fail, not where
# the rooms are. (See TODO step 9.)
#
# Grid units are metres. The player starts asleep in the pod, in the cryo bay.
#
# THE LAYOUT COMES FROM A DRAWING. `docs/features/ship-layout.md` records how
# room_layout_5.png decodes: one pixel is one metre, transparent is hull, a room colour is
# floor, opaque black is corridor, white is a window and grey is a door. Everything below is
# that image transcribed. If the ship needs to change, change the drawing and re-derive —
# do not hand-edit these rectangles, or the two will drift apart.
#
# The anchor (grid = pixel - (42, 41)) has survived three redraws now: it is picked so the
# spine corridor lands on Rect2i(-1, -12, 3, 8), which is the rect it has had since the ship
# was first built, and so the cryo bay keeps its forward wall at z=-4 and its centreline at
# x=0.5.
#
# SHAPE. The bridge is the hub: the cryo bay has exactly ONE door, up the spine to the
# bridge, and every other room hangs off the bridge or off a corridor that does. That makes
# every trip out pass through the bridge, which is what the long walks below are made of.

## Tick to rebuild now. The layout is code, so after editing a rectangle above this is how the
## viewport catches up without leaving the editor. Resets itself immediately — it is a button,
## not a setting.
@export var rebuild: bool = false:
	set(value):
		rebuild = false
		if is_inside_tree():
			build_ship()


# Runs in the editor too (see the @tool at the top): the ship is authored in code, so without
# this the viewport shows an empty Node3D and the only way to look at a room is to play the
# game. Everything build() makes is left UNOWNED, which is what keeps it out of game.tscn —
# Godot only serialises nodes with an owner. See RoomBuilder.build().
func _ready() -> void:
	build_ship()


func build_ship() -> void:
	rooms.clear()
	doorways.clear()

	_add_cryo_bay()
	_add_corridors()
	_add_fore_rooms()
	_add_flank_rooms()
	_add_doors()
	_add_windows()

	build()


# --- rooms ------------------------------------------------------------------

func _add_cryo_bay() -> void:
	# Cryo bay — the loop anchor and the biggest room on the ship: a 19x19 chamber with the
	# CryoStation furnace dead centre and four 2.7m-wide pods ringed flush against it. TALL
	# because the furnace is: at 0.9 scale it stands 9.27m to the top of its flue, and the
	# ceiling just clears it. The forward wall stays at z=-4 because the spine connects there,
	# so the room runs z=-4..15 and x=-9..10 — its centre is (0.5, 5.5), which lines up with
	# the spine's own x=0.5 centreline and with the aft window the pod looks down.
	add_room(Rect2i(-9, -4, 19, 19), {
		"id": "cryo_bay",
		"height": 9.3,
		"floor_color": Color(0.28, 0.30, 0.34),
		"wall_color": Color(0.50, 0.53, 0.58),
		"ceiling_color": Color(0.44, 0.46, 0.50),
	})


func _add_corridors() -> void:
	# Every corridor is 3m wide and 2.6m high — narrow and low, so the walk between systems
	# reads as a cost against the oxygen budget. The drawing draws them 1m wide; 3m is the
	# width the spine has always been, and it is what these are built at.
	var corridor := {
		"height": 2.6,
		"floor_color": Color(0.24, 0.26, 0.29),
		"wall_color": Color(0.42, 0.45, 0.50),
		"ceiling_color": Color(0.38, 0.40, 0.44),
	}

	# The spine, running forward out of the cryo bay to the bridge. Unchanged since the ship
	# was first built. Hull on both sides — the bathroom and the closet stop a metre short of
	# it — which is why it can carry a window.
	add_room(Rect2i(-1, -12, 3, 8), corridor.merged({"id": "corridor"}, true))

	# Port and starboard arms off the bridge, to the kitchen and to life support.
	add_room(Rect2i(-15, -16, 8, 3), corridor.merged({"id": "corridor_port"}, true))
	add_room(Rect2i(8, -16, 8, 3), corridor.merged({"id": "corridor_stbd"}, true))

	# ...and on down the flanks to the engine room and the cargo bay.
	add_room(Rect2i(-21, -10, 3, 8), corridor.merged({"id": "corridor_engine"}, true))
	add_room(Rect2i(19, -10, 3, 8), corridor.merged({"id": "corridor_cargo"}, true))


func _add_fore_rooms() -> void:
	# Bridge. Spans the middle of the bow and is the junction of the whole ship: five doors,
	# more than any other room. Its forward wall is a 13m window looking down the direction of
	# travel — the destination appears there.
	add_room(Rect2i(-7, -21, 15, 9), {
		"id": "bridge",
		"height": 3.4,
		"floor_color": Color(0.22, 0.25, 0.30),
		"wall_color": Color(0.44, 0.49, 0.56),
		"ceiling_color": Color(0.34, 0.38, 0.44),
	})

	# Bathroom and janitor's closet, hung off the bridge's aft wall either side of the spine
	# and stopping a metre short of it, so all three have hull between them.
	add_room(Rect2i(-9, -12, 7, 7), {
		"id": "bathroom",
		"height": 2.4,
		"floor_color": Color(0.32, 0.34, 0.35),
		"wall_color": Color(0.56, 0.58, 0.59),
		"ceiling_color": Color(0.44, 0.46, 0.47),
	})

	# Small, low and dull on purpose: it is a store cupboard, and the only reason to come here
	# is the hammer on the floor of it. At 3x3 it is the smallest room on the ship, and the
	# door is the full width of one wall.
	add_room(Rect2i(3, -12, 3, 3), {
		"id": "janitor_closet",
		"height": 2.4,
		"floor_color": Color(0.22, 0.23, 0.25),
		"wall_color": Color(0.38, 0.40, 0.43),
		"ceiling_color": Color(0.32, 0.34, 0.36),
	})


func _add_flank_rooms() -> void:
	# Kitchen/mess and life support mirror each other across the bow.
	add_room(Rect2i(-24, -19, 9, 9), {
		"id": "kitchen",
		"height": 3.0,
		"floor_color": Color(0.30, 0.27, 0.23),
		"wall_color": Color(0.52, 0.47, 0.40),
		"ceiling_color": Color(0.40, 0.37, 0.33),
	})

	add_room(Rect2i(16, -19, 9, 9), {
		"id": "life_support",
		"height": 3.6,
		"floor_color": Color(0.22, 0.28, 0.26),
		"wall_color": Color(0.40, 0.50, 0.46),
		"ceiling_color": Color(0.32, 0.40, 0.37),
	})

	# Engine room — where the expensive repairs live, and the furthest point on the ship from
	# the pod. Entered from its FORE wall, so the drive wall is the aft one opposite.
	add_room(Rect2i(-24, -2, 9, 9), {
		"id": "engine_room",
		"height": 4.0,
		"floor_color": Color(0.26, 0.24, 0.22),
		"wall_color": Color(0.46, 0.42, 0.38),
		"ceiling_color": Color(0.38, 0.36, 0.34),
	})

	add_room(Rect2i(13, -2, 15, 16), {
		"id": "cargo_bay",
		"height": 6.0,
		"floor_color": Color(0.24, 0.24, 0.26),
		"wall_color": Color(0.44, 0.44, 0.47),
		"ceiling_color": Color(0.34, 0.34, 0.37),
	})


# --- openings ---------------------------------------------------------------

func _add_doors() -> void:
	# The drawing marks doors one pixel wide. They are built at 1.8m, the width every door on
	# this ship has always been, centred on the mark.
	#
	# Twelve doors and no unsealed seams: unlike the previous drawing, every corridor here is
	# a single rectangle, so nothing needs the full-height opening trick.
	add_doorway(Vector2(-15, -14.5), Doorway.Axis.Z, 1.8)  # kitchen <-> port arm
	add_doorway(Vector2(-7, -14.5), Doorway.Axis.Z, 1.8)   # port arm <-> bridge
	add_doorway(Vector2(8, -14.5), Doorway.Axis.Z, 1.8)    # bridge <-> starboard arm
	add_doorway(Vector2(16, -14.5), Doorway.Axis.Z, 1.8)   # starboard arm <-> life support

	add_doorway(Vector2(-3.5, -12), Doorway.Axis.X, 1.8)   # bridge <-> bathroom
	add_doorway(Vector2(0.5, -12), Doorway.Axis.X, 1.8)    # bridge <-> spine
	add_doorway(Vector2(4.5, -12), Doorway.Axis.X, 1.8)    # bridge <-> janitor's closet

	add_doorway(Vector2(-19.5, -10), Doorway.Axis.X, 1.8)  # kitchen <-> engine corridor
	add_doorway(Vector2(20.5, -10), Doorway.Axis.X, 1.8)   # life support <-> cargo corridor

	add_doorway(Vector2(0.5, -4), Doorway.Axis.X, 1.8)     # spine <-> cryo bay
	add_doorway(Vector2(-19.5, -2), Doorway.Axis.X, 1.8)   # engine corridor <-> engine room
	add_doorway(Vector2(20.5, -2), Doorway.Axis.X, 1.8)    # cargo corridor <-> cargo bay


func _add_windows() -> void:
	# Windows on exterior walls only — an opening onto another room would show stars through
	# the ship. Every one below was checked against the room rects: all 17 face open hull.

	# Bridge. The forward pane is the widest opening on the ship and the reason the bridge is
	# at the bow: travel is -Z, so this is the view of where you are going.
	add_window(Vector2(0.5, -21), Doorway.Axis.X, 13.0, 1.0, 2.0)
	add_window(Vector2(-7, -17.5), Doorway.Axis.Z, 3.0, 1.0, 1.3)
	add_window(Vector2(8, -17.5), Doorway.Axis.Z, 3.0, 1.0, 1.3)

	# Kitchen, forward and port.
	add_window(Vector2(-19.5, -19), Doorway.Axis.X, 3.0, 1.0, 1.4)
	add_window(Vector2(-24, -14.5), Doorway.Axis.Z, 3.0, 1.0, 1.4)

	# Bathroom, port. Three narrow panes rather than one wide one, and a higher sill than the
	# rest of the ship, for the obvious reason.
	add_window(Vector2(-9, -10.5), Doorway.Axis.Z, 1.0, 1.2, 1.0)
	add_window(Vector2(-9, -8.5), Doorway.Axis.Z, 1.0, 1.2, 1.0)
	add_window(Vector2(-9, -6.5), Doorway.Axis.Z, 1.0, 1.2, 1.0)

	# ONE wide aft window in the cryo bay, and the room's only window. The player's pod looks
	# straight down its centre line, so this is the first thing seen on every waking — two
	# smaller panes would put a strip of wall exactly where the view should be, with the pod's
	# own axis pointed at it.
	add_window(Vector2(0.5, 15), Doorway.Axis.X, 17.0, 1.0, 2.2)

	# Cargo bay, aft.
	add_window(Vector2(20.5, 14), Doorway.Axis.X, 13.0, 1.0, 2.0)

	# Windows in the corridors themselves. Nothing on the ship did this before the drawings
	# asked for it: they turn the long walks into something other than a tunnel. The flank
	# corridors get one in EACH side wall, so the walk out to the engine room and the cargo
	# bay is glazed on both hands.
	add_window(Vector2(-11, -16), Doorway.Axis.X, 2.0, 1.0, 1.2)
	add_window(Vector2(12, -16), Doorway.Axis.X, 2.0, 1.0, 1.2)
	add_window(Vector2(2, -7), Doorway.Axis.Z, 2.0, 1.0, 1.2)
	add_window(Vector2(-21, -6), Doorway.Axis.Z, 2.0, 1.0, 1.2)
	add_window(Vector2(-18, -6), Doorway.Axis.Z, 2.0, 1.0, 1.2)
	add_window(Vector2(19, -6), Doorway.Axis.Z, 2.0, 1.0, 1.2)
	add_window(Vector2(22, -6), Doorway.Axis.Z, 2.0, 1.0, 1.2)
