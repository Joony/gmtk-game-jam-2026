class_name LoopingModelAnimation
extends Node3D

# Loops an imported model's animation. The models arrive with their clips set to play once,
# so a machine that should idle forever runs for two seconds and stops.
#
# DO NOT MERGE THE CLIPS. CD_Engine_v3 exports four of them — Action, CoreAction,
# Cylinder_001Action, Cylinder_002Action — and their names suggest one clip per moving part,
# which would mean playing any single one leaves the other parts dead still. They are not:
# every clip drives the SAME six tracks (rotation+scale on Outer/Middle/Inner, position on
# Core). Blender exported the whole rig once per action.
#
# So one clip already contains the entire animation, and merging them stacked four duplicate
# tracks per property. Godot applies every track, so the duplicated SCALE tracks multiplied
# together and the engine visibly squashed and stretched along one axis each cycle. Playing a
# single clip is both correct and simpler.
#
# If a future model genuinely does split parts across clips, that needs an AnimationTree with
# one input per clip — not a merge, for the same reason.

## Drop the clip's SCALE tracks before playing.
##
## For CD_Engine_v3 those tracks are not really scale: `Inner`'s keys pin X at 0.667 for all 74
## of them while Y and Z counter-oscillate and swap values, with sqrt(y^2+z^2) near constant —
## the signature of a ROTATION baked into scale. glTF stores only translate/rotate/scale, and a
## child rotating inside a non-uniformly scaled parent (`Middle` is 1.65 x 0.404 x 0.667) needs
## shear to express, so the exporter approximates it this way. The result is the visible squash
## and stretch.
##
## Dropping them makes the part rigid, but it does NOT reproduce the intended proportions —
## measured world axis lengths change a lot. This is a stopgap; the real fix is to give the
## parents uniform scale in Blender so the rotation exports as a rotation.
@export var drop_scale_tracks: bool = false

## Which clip to play. Empty means the first one the model ships.
@export var clip: String = ""
## Playback speed. The engine idles rather than races, so this is usually below 1.
@export var speed: float = 1.0
## Start playing as soon as the model is in the tree.
@export var autoplay: bool = true


func _ready() -> void:
	if autoplay:
		play()


## Loop the chosen clip forever.
func play() -> void:
	var player := _find_player()
	if player == null:
		push_warning("LoopingModelAnimation on '%s': the model ships no AnimationPlayer" % name)
		return

	var names := player.get_animation_list()
	if names.is_empty():
		push_warning("LoopingModelAnimation on '%s': the AnimationPlayer has no clips" % name)
		return

	var chosen := clip if clip != "" else String(names[0])
	if not player.has_animation(chosen):
		push_warning("LoopingModelAnimation on '%s': no clip named '%s' (has %s)"
			% [name, chosen, ", ".join(names)])
		chosen = String(names[0])

	# The imported clips are one-shot; looping is the whole job here.
	var animation := player.get_animation(chosen)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR
		if drop_scale_tracks:
			for t in range(animation.get_track_count() - 1, -1, -1):
				if animation.track_get_type(t) == Animation.TYPE_SCALE_3D:
					animation.remove_track(t)

	player.speed_scale = speed
	player.play(chosen)


func _find_player() -> AnimationPlayer:
	for child in find_children("*", "AnimationPlayer", true, false):
		return child as AnimationPlayer
	return null
