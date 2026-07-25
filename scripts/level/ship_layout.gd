extends RoomBuilder

# The ship, authored in code. Deliberately hand-designed rather than randomly
# generated: the hook makes walking distance the oxygen cost, so randomising the
# geometry would randomise the difficulty. Randomise WHICH systems fail, not where
# the rooms are. (See TODO step 9.)
#
# Grid units are metres. The player starts asleep in the pod, in the pod bay.
#
# THE LAYOUT COMES FROM A DRAWING. `docs/features/ship-layout.md` records how
# room_layout_3.png decodes: one pixel is one metre, transparent is hull, a room colour is
# floor, opaque black is corridor, white is a window and grey is a door. Everything below is
# that image transcribed. If the ship needs to change, change the drawing and re-derive —
# do not hand-edit these rectangles, or the two will drift apart.
#
# Two things are deliberately unchanged from the pre-drawing ship, because the drawing
# happens to agree with them exactly: the pod bay's rect and the spine corridor's rect. Every
# prop already placed in the pod bay therefore keeps its coordinates.

func _ready() -> void:
	build_ship()


func build_ship() -> void:
	rooms.clear()
	doorways.clear()

	_add_pod_bay()
	_add_corridors()
	_add_fore_rooms()
	_add_aft_rooms()
	_add_doors()
	_add_windows()

	build()


# --- rooms ------------------------------------------------------------------

func _add_pod_bay() -> void:
	# Cryo bay — the loop anchor, and by far the biggest room on the ship: a 21x21 chamber
	# with the CryoStation furnace dead centre and four 2.7m-wide pods ringed flush against
	# it. TALL because the furnace is: at 0.9 scale it stands 9.27m to the top of its flue,
	# and the ceiling just clears it. The forward wall stays at z=-4 because the spine
	# corridor connects there, so the room runs z=-4..17 and x=-10..11 — its centre is
	# (0.5, 6.5), which also lines up with the corridor's own x=0.5 centreline.
	add_room(Rect2i(-10, -4, 21, 21), {
		"id": "pod_bay",
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

	# Spine, running forward out of the pod bay. Unchanged.
	add_room(Rect2i(-1, -12, 3, 8), corridor.merged({"id": "corridor"}, true))

	# Fore arm, running east off the spine to the kitchen. The drawing shows one L-shaped
	# corridor; it is built as two rectangles because the builder assumes rooms do not
	# overlap — two overlapping rects would each raise a wall skin through the other's
	# floor. Split at x=2 rather than at the bend's other diagonal so the spine keeps its
	# original rect exactly. The seam between them is opened out below.
	add_room(Rect2i(2, -12, 8, 3), corridor.merged({"id": "corridor_fore"}, true))

	add_room(Rect2i(-16, -1, 6, 3), corridor.merged({"id": "corridor_life"}, true))
	add_room(Rect2i(-18, 10, 8, 3), corridor.merged({"id": "corridor_engine"}, true))
	add_room(Rect2i(11, 10, 8, 3), corridor.merged({"id": "corridor_cargo"}, true))


func _add_fore_rooms() -> void:
	# Bridge. Spans the beam at the very front, and its forward wall is a 17m window looking
	# down the direction of travel — the destination appears there.
	add_room(Rect2i(-9, -22, 19, 10), {
		"id": "bridge",
		"height": 3.4,
		"floor_color": Color(0.22, 0.25, 0.30),
		"wall_color": Color(0.44, 0.49, 0.56),
		"ceiling_color": Color(0.34, 0.38, 0.44),
	})

	# Kitchen / mess, starboard.
	add_room(Rect2i(10, -17, 11, 11), {
		"id": "kitchen",
		"height": 3.0,
		"floor_color": Color(0.30, 0.27, 0.23),
		"wall_color": Color(0.52, 0.47, 0.40),
		"ceiling_color": Color(0.40, 0.37, 0.33),
	})

	# Bathroom, port of the spine. Pale and low.
	add_room(Rect2i(-8, -12, 7, 8), {
		"id": "bathroom",
		"height": 2.4,
		"floor_color": Color(0.32, 0.34, 0.35),
		"wall_color": Color(0.56, 0.58, 0.59),
		"ceiling_color": Color(0.44, 0.46, 0.47),
	})

	# Janitor's closet, starboard of the spine. Small, low and dull on purpose: it is a store
	# cupboard, and the only reason to come here is the hammer on the floor of it. Putting it
	# ON the spine rather than at either end means the detour is short but deliberate — you
	# pass the door on every walk forward, which is what makes forgetting the hammer a
	# decision rather than an ambush.
	add_room(Rect2i(2, -9, 6, 5), {
		"id": "janitor_closet",
		"height": 2.4,
		"floor_color": Color(0.22, 0.23, 0.25),
		"wall_color": Color(0.38, 0.40, 0.43),
		"ceiling_color": Color(0.32, 0.34, 0.36),
	})


func _add_aft_rooms() -> void:
	# Life support, port. Sits directly forward of the engine room and shares its z=7 wall.
	add_room(Rect2i(-29, -6, 13, 13), {
		"id": "life_support",
		"height": 3.6,
		"floor_color": Color(0.22, 0.28, 0.26),
		"wall_color": Color(0.40, 0.50, 0.46),
		"ceiling_color": Color(0.32, 0.40, 0.37),
	})

	# Engine room — where the expensive repairs live. Moved from the bow to port-aft by the
	# drawing, and grown from 12x10 to 21x21. Its only door and only window are both on the
	# east wall, which leaves the west wall (x=-39) clear as the drive wall: the thing you
	# face when you walk in, the same relationship the old forward wall had.
	add_room(Rect2i(-39, 7, 21, 21), {
		"id": "engine_room",
		"height": 4.0,
		"floor_color": Color(0.26, 0.24, 0.22),
		"wall_color": Color(0.46, 0.42, 0.38),
		"ceiling_color": Color(0.38, 0.36, 0.34),
	})

	# Cargo / docking bay — the largest floor on the ship, 21x33 down the starboard flank,
	# and the tallest apart from the pod bay.
	add_room(Rect2i(19, -1, 21, 33), {
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
	add_doorway(Vector2(0.5, -12), Doorway.Axis.X, 1.8)   # bridge <-> spine
	add_doorway(Vector2(10, -10.5), Doorway.Axis.Z, 1.8)  # kitchen <-> fore arm
	add_doorway(Vector2(-1, -6.5), Doorway.Axis.Z, 1.8)   # bathroom <-> spine
	add_doorway(Vector2(2, -6.5), Doorway.Axis.Z, 1.8)    # janitor's closet <-> spine
	add_doorway(Vector2(0.5, -4), Doorway.Axis.X, 1.8)    # pod bay <-> spine
	add_doorway(Vector2(-16, 0.5), Doorway.Axis.Z, 1.8)   # life support <-> its corridor
	add_doorway(Vector2(-10, 0.5), Doorway.Axis.Z, 1.8)   # pod bay <-> life support corridor
	add_doorway(Vector2(-18, 11.5), Doorway.Axis.Z, 1.8)  # engine room <-> its corridor
	add_doorway(Vector2(-10, 11.5), Doorway.Axis.Z, 1.8)  # pod bay <-> engine corridor
	add_doorway(Vector2(11, 11.5), Doorway.Axis.Z, 1.8)   # pod bay <-> cargo corridor
	add_doorway(Vector2(19, 11.5), Doorway.Axis.Z, 1.8)   # cargo bay <-> its corridor

	# The bend in the L, where the spine meets the fore arm. NOT a door: it is the seam left
	# by splitting one drawn corridor into two rectangles, so it has to vanish. Full 3m width
	# and `top` at the corridor ceiling, which leaves no sill below and no lintel above — the
	# wall is simply absent and the corner reads as continuous floor.
	var bend := add_doorway(Vector2(2, -10.5), Doorway.Axis.Z, 3.0)
	bend.top = 2.6
	bend.fit_door = false


func _add_windows() -> void:
	# Windows on exterior walls only — an opening onto another room would show stars through
	# the ship. Every one below was checked against the room rects: all 16 face open hull.

	# Bridge. The forward pane is the widest opening on the ship and the reason the bridge is
	# at the bow: travel is -Z, so this is the view of where you are going.
	add_window(Vector2(0.5, -22), Doorway.Axis.X, 17.0, 1.0, 2.0)
	add_window(Vector2(-9, -19.5), Doorway.Axis.Z, 3.0, 1.0, 1.3)
	add_window(Vector2(10, -19.5), Doorway.Axis.Z, 3.0, 1.0, 1.3)

	# Kitchen, forward and starboard.
	add_window(Vector2(15.5, -17), Doorway.Axis.X, 5.0, 1.0, 1.4)
	add_window(Vector2(21, -11.5), Doorway.Axis.Z, 5.0, 1.0, 1.4)

	# Bathroom, port. Sill set higher than the rest of the ship's, for the obvious reason.
	add_window(Vector2(-8, -10), Doorway.Axis.Z, 2.0, 1.2, 1.0)
	add_window(Vector2(-8, -6), Doorway.Axis.Z, 2.0, 1.2, 1.0)

	# Life support, port.
	add_window(Vector2(-29, 0.5), Doorway.Axis.Z, 3.0, 1.0, 1.3)

	# ONE wide aft window in the pod bay, not a pair, and now the room's only window. The
	# player's pod looks straight down its centre line, so this is the first thing seen on
	# every waking — two smaller panes put a strip of wall exactly where the view should be,
	# and the pod's own axis pointed at it. Widened 9m -> 19m by the drawing, which fills the
	# wall corner to corner.
	add_window(Vector2(0.5, 17), Doorway.Axis.X, 19.0, 1.0, 2.2)

	# Engine room, starboard — aft of the corridor door, looking back across open hull.
	add_window(Vector2(-18, 22.5), Doorway.Axis.Z, 3.0, 1.2, 1.6)

	# Cargo bay: one long pane to port and three to starboard down the flank.
	add_window(Vector2(19, 24.5), Doorway.Axis.Z, 13.0, 1.0, 2.0)
	add_window(Vector2(40, 6.5), Doorway.Axis.Z, 3.0, 1.0, 1.4)
	add_window(Vector2(40, 15.5), Doorway.Axis.Z, 3.0, 1.0, 1.4)
	add_window(Vector2(40, 24.5), Doorway.Axis.Z, 3.0, 1.0, 1.4)

	# Windows in the corridors themselves, in the aft wall of each aft crossing. Nothing else
	# on the ship does this: they turn the two longest walks into something other than a
	# tunnel, and they are the drawing's idea, not a port of anything.
	add_window(Vector2(-14, 13), Doorway.Axis.X, 2.0, 1.0, 1.2)
	add_window(Vector2(15, 13), Doorway.Axis.X, 2.0, 1.0, 1.2)
