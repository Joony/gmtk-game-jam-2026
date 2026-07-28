extends Node
# Autoload "SceneManager": changes scenes with a black fade transition.

const FADE_DURATION := 0.3

var _fade_rect: ColorRect
var _changing := false
## Scenes deliberately held in memory. A PackedScene owns references to every mesh and texture
## it pulls in, and those carry their GPU uploads with them — so dropping the last reference and
## loading the scene again re-imports and re-uploads the lot. Measured on the menu's shader warm
## (main_menu.gd): binning the warm copy without pinning left the real load paying 1012ms on its
## first drawn frame, against 510ms with it pinned. See tests/probe_boot_warm.gd.
var _pinned: Array[PackedScene] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color.BLACK
	_fade_rect.modulate.a = 0.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade_rect)


## True while a change_scene() is still running. A second call made during one is DROPPED, so
## anything that chains a change off the back of its own _ready() has to wait this out first —
## see loading.gd.
func is_changing() -> bool:
	return _changing


## Load a scene and keep it loaded for the rest of the process, returning it ready to
## instantiate. For scenes that are about to be thrown away and loaded again shortly after —
## see _pinned and main_menu.gd's shader warm.
func pin(path: String) -> PackedScene:
	var packed: PackedScene = load(path)
	if packed != null and not _pinned.has(packed):
		_pinned.append(packed)
	return packed


## Change scene, black-fading out and back in.
##
## `fade` defaults to true because most transitions want the wipe to cover a load and to give
## the player a moment. Pass FALSE for a hard cut, where the change itself is the beat and a
## fade would soften it — see intro.gd.
func change_scene(path: String, fade: bool = true) -> void:
	if _changing:
		return
	_changing = true
	# Block clicks on the outgoing scene while the transition runs.
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	if fade:
		await _fade_to(1.0)
	else:
		# A cut still has to clear the rect. It is shared, and a transition that was
		# interrupted part-way could leave it opaque — a hard cut onto a black screen is not
		# a hard cut, it is a hang.
		_fade_rect.modulate.a = 0.0
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	print("[SceneManager] changed scene to %s" % path)
	if fade:
		await _fade_to(0.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_changing = false


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_fade_rect, "modulate:a", alpha, FADE_DURATION)
	await tween.finished
