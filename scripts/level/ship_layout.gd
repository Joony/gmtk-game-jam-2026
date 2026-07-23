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

	# Pod bay — the loop anchor. Big enough to move around the stasis pod.
	add_room(Rect2i(-5, -4, 10, 12), {
		"id": "pod_bay",
		"height": 3.0,
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
	add_window(Vector2(-5, 2), Doorway.Axis.Z, 3.0, 1.0, 1.3)     # pod bay, port side
	add_window(Vector2(5, 2), Doorway.Axis.Z, 3.0, 1.0, 1.3)      # pod bay, starboard
	add_window(Vector2(-6, -17), Doorway.Axis.Z, 4.0, 1.2, 1.6)   # engine room, port

	build()
