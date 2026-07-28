extends Control

# A black beat between the menu and the intro video. Its only job is to be somewhere the game
# can stall without the stall looking like a fault.
#
# WHY IT EXISTS. The renderer compiles a material's shader variants the first time something
# using them is actually drawn, on the main thread, and for game.tscn that first draw costs
# about 2.1 seconds on an M1 Max (tests/probe_opening_frames.gd). Left alone it lands on the
# hard cut out of the intro, as a frozen last frame of video. Warming it on the main menu moved
# it onto the Start button, where it read as the button not responding. Here it lands on a
# black screen that has nothing else to do, which is what a load is meant to look like.
#
# HOW THE WARM WORKS. A whole copy of game.tscn is built, drawn, and thrown away. That is
# enough because roughly 1.45s of the 2.1s is shader variant compilation, which the
# RenderingServer caches for the entire PROCESS — any instance can pay it, including one binned
# a moment later. The remaining ~0.67s is per-instance GPU upload of RoomBuilder's procedural
# boxes and stays with the real scene. tests/probe_warm_reuse.gd measures the split by
# instantiating three times over: 2122ms, then 496ms, then 496ms.

const INTRO_SCENE := "res://scenes/intro.tscn"
const GAME_SCENE := "res://scenes/game.tscn"

## How long to give the throwaway copy before binning it. ShaderPrewarm sweeps 24 angles at one
## per frame and then frees itself, so this only has to outlast that.
const WARM_FRAMES := 34

## Once per PROCESS. The RenderingServer caches compiled variants for the lifetime of the game,
## so a second trip through here — quitting to the menu and pressing Start again — has nothing
## left to warm and should be a straight pass-through. Static so it survives this scene being
## freed and a fresh one built on the way back.
static var _warmed: bool = false


func _ready() -> void:
	_proceed()


func _proceed() -> void:
	await _warm_game_shaders()
	# SceneManager refuses a second change while one is still running, and the change that
	# brought us HERE is still fading back in. Without this wait the call below is silently
	# dropped and the loading screen stays up forever — which the warm's own frame count would
	# normally mask, but not on the second pass through, where there is nothing to wait for.
	while SceneManager.is_changing():
		await get_tree().process_frame
	# A hard cut, not a fade: this screen is already black and so is the first frame of the
	# video, so a fade would only add a pause between two identical blacks.
	SceneManager.change_scene(INTRO_SCENE, false)


## Build a throwaway copy of the game and draw it, so the renderer compiles its shader variants
## here rather than mid-cut. Returns once the copy has been binned.
func _warm_game_shaders() -> void:
	if _warmed:
		return
	# Nothing to compile without a rendering device, and the headless test suites would only
	# pay 34 frames and briefly gain a second Player in the tree for it.
	if DisplayServer.get_name() == "headless":
		return
	_warmed = true

	# Let this screen actually get presented first, so the stall happens behind black rather
	# than in place of it.
	await get_tree().process_frame
	await get_tree().process_frame

	var viewport := SubViewport.new()
	# Resolution has no bearing on WHICH variants get compiled, only on how many pixels get
	# shaded doing it.
	viewport.size = Vector2i(320, 180)
	# Its OWN World3D. The game scene brings a Camera3D and a WorldEnvironment with it, and in
	# the shared world those would simply take over the screen.
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	# PINNED, not just loaded. Binning the copy would otherwise drop the last reference to every
	# mesh and texture it pulled in, and the real load would re-upload the lot — measured as
	# 1012ms on the game's first drawn frame instead of 510ms. See tests/probe_boot_warm.gd.
	var warm: Node3D = SceneManager.pin(GAME_SCENE).instantiate()
	# Before add_child(), because that is what runs _ready() — see the check in game.gd.
	warm.set_meta(&"warm_only", true)
	viewport.add_child(warm)
	# Built and drawn, but inert: a second ship ticking away in the tree has nothing useful to
	# do. Rendering is unaffected by process_mode, which is the only part being warmed, and
	# ShaderPrewarm drives itself off SceneTree.process_frame rather than its own _process.
	warm.process_mode = Node.PROCESS_MODE_DISABLED

	for i in WARM_FRAMES:
		await get_tree().process_frame
		if not is_inside_tree():
			return

	viewport.queue_free()
