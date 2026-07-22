extends CanvasLayer

# Centre dot + interaction prompt. Grey normally, green when the ray is on something
# interactable. Tweened rather than snapped so sweeping across a room doesn't strobe.

const COLOR_IDLE := Color(0.78, 0.80, 0.84, 0.55)
const COLOR_ACTIVE := Color(0.35, 0.95, 0.45, 1.0)
const FADE_TIME := 0.1

@onready var _dot: Panel = %Dot
@onready var _prompt: Label = %Prompt

var _color_tween: Tween


func _ready() -> void:
	_dot.modulate = COLOR_IDLE
	_prompt.text = ""
	_prompt.modulate.a = 0.0


## Subscribe to an Interactor. Called by game.gd once the scene is assembled.
func bind(interactor: Interactor) -> void:
	interactor.focus_changed.connect(_on_focus_changed)
	_on_focus_changed(interactor.current, interactor.get_prompt(), interactor.is_actionable())


# Green means "pressing E does something", not merely "something is there" — so a
# pickup you have no free hands for still shows its prompt but keeps the dot grey.
func _on_focus_changed(_interactable: Interactable, prompt: String, actionable: bool) -> void:
	if _color_tween != null and _color_tween.is_valid():
		_color_tween.kill()
	_color_tween = create_tween()
	_color_tween.set_parallel(true)
	_color_tween.tween_property(_dot, "modulate", COLOR_ACTIVE if actionable else COLOR_IDLE, FADE_TIME)
	_color_tween.tween_property(_prompt, "modulate:a", 1.0 if prompt != "" else 0.0, FADE_TIME)
	if prompt != "":
		_prompt.text = prompt
