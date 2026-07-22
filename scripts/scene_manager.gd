extends Node
# Autoload "SceneManager": changes scenes with a black fade transition.

const FADE_DURATION := 0.3

var _fade_rect: ColorRect
var _changing := false


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


func change_scene(path: String) -> void:
	if _changing:
		return
	_changing = true
	# Block clicks on the outgoing scene while fading.
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	await _fade_to(1.0)
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	print("[SceneManager] changed scene to %s" % path)
	await _fade_to(0.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_changing = false


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_fade_rect, "modulate:a", alpha, FADE_DURATION)
	await tween.finished
