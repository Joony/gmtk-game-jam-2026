extends RefCounted
# Shared by every suite that loads game.tscn and then needs the player on their feet.
#
# The run opens with the player already asleep in the stasis pod (Game._pose_in_pod), so a test
# that instantiates the scene and immediately reaches for the player finds them frozen inside a
# sealed shell: no physics, no camera, no interactor, no reticle. Eleven suites broke on exactly
# that when the opening changed, all of them for the same reason and none of them about the pod.
#
# `wake()` skips the beat the same way the player can — [E] calls RunState.exit_stasis() — and
# then rides the ordinary wake out. It deliberately does NOT shortcut to Game._finish_exit():
# a suite that set up its world by performing a wake the game itself never performs would go on
# passing over an opening that strands the player sealed in.
#
# Suites that are ABOUT the opening should not use this. See smoke_opening_stasis.gd.

## Long enough for the door and the ride out (~1.6s) with room to spare; short enough that a
## pod which never opens fails the suite instead of hanging the test run.
const TIMEOUT_FRAMES := 900


## Wake the player early and wait until control is genuinely theirs again.
## Returns false if the pod never let go, so callers can assert on it.
static func wake(tree: SceneTree, game: Node) -> bool:
	game._run.exit_stasis()
	for _i in TIMEOUT_FRAMES:
		await tree.process_frame
		if game._pod_phase == game.PodPhase.OUT:
			return true
	return false
