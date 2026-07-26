class_name ShaderPrewarm
extends Node

# Draw the surroundings once, off-screen, before the player can turn round.
#
# WHY. Under GL Compatibility, Godot builds a material's shader variant the first time
# something needing it is actually rasterised, on the main thread. Standing still only warms
# the variants for whatever is already in front of you, so the first time the player turns
# their head the renderer compiles the rest of the room in one go. Measured on an M1 Max at
# 1280x720: 171ms in a single frame, on the first few degrees of the first turn, against a 7ms
# median. It happens once per process and never again — which is exactly why it survives
# testing and lands squarely on someone's first launch.
#
# Diagnosed with tests/probe_turn_hitch.gd, which sweeps the camera through 360 degrees three
# times over and prints per-frame times. Passes 2 and 3 never spike. Hiding the lights, the
# starfield, the imported props or the whole built ship each leaves the spike intact — it is
# not any one subsystem's draw cost, it is first-draw cost on whatever is left. Rendering the
# views once beforehand removes it completely.
#
# Off-screen in a SubViewport rather than by spinning the real camera: the only quiet moment
# to spend on this is the opening stasis, and swinging the player's actual view through a full
# circle while they are sealed in the pod would be very hard to miss.

## Yaw is what matters — turning is the trigger. The two pitches are for the floor and the
## ceiling, which RoomBuilder emits as their own meshes with their own materials.
const YAW_STEPS := 12
const PITCHES: Array[float] = [-35.0, 10.0]
## Resolution has no bearing on WHICH variants get built, so render as few pixels as will still
## rasterise every surface. This is not a quality setting.
const SIZE := Vector2i(320, 180)


## Render the surroundings of `at` from every angle, one view per frame, then free the
## viewport and self. Fire and forget — nothing awaits this, because the whole point is that it
## overlaps a beat the player is already spending doing nothing.
func run(at: Vector3, fov: float) -> void:
	var viewport := SubViewport.new()
	viewport.size = SIZE
	# Share the real World3D. `own_world_3d` stays false, so this draws the actual ship under
	# the actual lights and therefore builds the actual variants — a private world would warm
	# nothing that the player's camera goes on to use.
	viewport.world_3d = get_viewport().find_world_3d()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var camera := Camera3D.new()
	camera.fov = fov
	viewport.add_child(camera)
	camera.current = true

	for pitch in PITCHES:
		for step in YAW_STEPS:
			var yaw := float(step) * (TAU / float(YAW_STEPS))
			camera.global_transform = Transform3D(
				Basis.from_euler(Vector3(deg_to_rad(pitch), yaw, 0.0)), at)
			# One angle per frame: UPDATE_ALWAYS draws the SubViewport once per frame, so
			# moving the camera more often than that would just skip angles unrendered.
			await get_tree().process_frame
			# The scene can be torn down mid-warm — the pause menu quits to the menu, and the
			# tests instantiate and drop the game scene repeatedly.
			if not is_inside_tree():
				return

	viewport.queue_free()
	queue_free()
