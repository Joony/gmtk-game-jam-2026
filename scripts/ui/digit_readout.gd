class_name DigitReadout
extends HBoxContainer

# A numeric display whose characters never shift sideways.
#
# The UI font is proportional, so a plain Label showing a live clock twitches every time a
# 1 replaces a 0 — the whole string reflows several times a second, right where the player
# is trying to read it under pressure. There is no monospaced font in the project, so this
# gives every character its own fixed-width slot instead: each glyph is centred in a box of
# constant width, and only the glyph inside a box ever changes.
#
# Digits and separators get different widths, because a colon padded to digit width leaves
# an ugly gap. Keeping the STRING LENGTH constant is still the caller's job — pad numbers
# with leading zeros (`%05.1f`), or the whole block will still jump when 9.9 becomes 10.0.

## Characters that get the narrow slot. Everything else gets `digit_width`.
const NARROW := ":.,+- "

@export var font_size: int = 76:
	set(value):
		font_size = value
		_restyle()
@export var digit_width: float = 44.0:
	set(value):
		digit_width = value
		_relayout()
@export var separator_width: float = 20.0:
	set(value):
		separator_width = value
		_relayout()
@export var font_color: Color = Color(0.78, 0.86, 0.94):
	set(value):
		font_color = value
		_restyle()
@export var outline_size: int = 10
## Backed by `_text` rather than assigned directly: a setter that writes to its own
## property re-enters itself forever.
@export var text: String = "":
	set(value):
		_text = value
		_rebuild()
	get:
		return _text

var _text: String = ""
var _slots: Array[Label] = []


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	_rebuild()


func set_value(value: String) -> void:
	if value == _text and not _slots.is_empty():
		return
	_text = value
	_rebuild()


## Labels are reused rather than rebuilt: this updates on every frame the oxygen changes,
## and churning a dozen nodes per frame to redraw four characters would be absurd.
func _rebuild() -> void:
	if not is_inside_tree():
		return
	var value := _text
	while _slots.size() < value.length():
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		_slots.append(label)
		_style(label)

	for i in _slots.size():
		var label := _slots[i]
		if i >= value.length():
			label.visible = false
			continue
		label.visible = true
		var character := value[i]
		if label.text != character:
			label.text = character
			_size(label, character)


func _size(label: Label, character: String) -> void:
	label.custom_minimum_size.x = separator_width if character in NARROW else digit_width


func _style(label: Label) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", outline_size)


func _restyle() -> void:
	for label in _slots:
		_style(label)


func _relayout() -> void:
	for label in _slots:
		if label.text != "":
			_size(label, label.text)


## Recolour without rebuilding — the air gauge does this as it runs low.
func set_color(color: Color) -> void:
	font_color = color
