extends RoomBuilder

# The ship, authored in code. Deliberately hand-designed rather than randomly
# generated: the hook makes walking distance the oxygen cost, so randomising the
# geometry would randomise the difficulty. Randomise WHICH systems fail, not where
# the rooms are. (See TODO step 9.)
#
# Grid units are metres. The player spawns at world (0, 4), inside the pod bay.

func _ready() -> void:
	build_ship()


func build_ship() -> void:
	rooms.clear()
	doorways.clear()

	# Cryo bay — the loop anchor, and the biggest room on the ship because it has to hold a
	# ring of five 2.7m-wide pods AND leave lanes to walk round them. At the original 10x12
	# the gap between the ring and the side walls was 12cm and the player simply could not
	# get past. Tall, too: the pods are 3.25m with a ceiling pipe reaching 4.17m, and the
	# extra headroom above that is what stops a room this wide feeling like a corridor.
	add_room(Rect2i(-7, -4, 14, 14), {
		"id": "pod_bay",
		"height": 5.0,
		"floor_color": Color(0.28, 0.30, 0.34),
		"wall_color": Color(0.50, 0.53, 0.58),
		"ceiling_color": Color(0.44, 0.46, 0.50),
	})

	# Spine corridor. Narrow and lower, so the walk between systems reads as a cost.
	add_room(Rect2i(-1, -12, 3, 8), {
		"id": "corridor",
		"height": 2.6,
		"floor_color": Color(0.24, 0.26, 0.29),
		"wall_color": Color(0.42, 0.45, 0.50),
		"ceiling_color": Color(0.38, 0.40, 0.44),
	})

	# Engine room — taller, further away, where the expensive repairs will live.
	add_room(Rect2i(-6, -22, 12, 10), {
		"id": "engine_room",
		"height": 4.0,
		"floor_color": Color(0.26, 0.24, 0.22),
		"wall_color": Color(0.46, 0.42, 0.38),
		"ceiling_color": Color(0.38, 0.36, 0.34),
	})

	add_doorway(Vector2(0.5, -4), Doorway.Axis.X, 1.8)
	add_doorway(Vector2(0.5, -12), Doorway.Axis.X, 1.8)

	# Windows on exterior walls only — an opening onto another room would show stars
	# through the ship. Sill at 1.0m so they sit at eye level.
	add_window(Vector2(-7, 3), Doorway.Axis.Z, 3.0, 1.0, 1.3)     # cryo bay, port side
	add_window(Vector2(7, 3), Doorway.Axis.Z, 3.0, 1.0, 1.3)      # cryo bay, starboard
	add_window(Vector2(-6, -17), Doorway.Axis.Z, 4.0, 1.2, 1.6)   # engine room, port

	# Fore and aft. Travel is -Z, so the engine room's far wall looks FORWARD (where
	# the destination will appear) and the pod bay's rear wall looks BACK down the wake.
	add_window(Vector2(0, -22), Doorway.Axis.X, 5.0, 1.2, 1.8)    # engine room, forward
	# ONE wide aft window, not a pair. The player's pod looks straight down its centre line,
	# so this is the first thing seen on every waking — two smaller panes put a strip of
	# wall exactly where the view should be, and the pod's own axis pointed at it.
	add_window(Vector2(0, 10), Doorway.Axis.X, 9.0, 1.0, 2.2)     # cryo bay, aft

	build()
