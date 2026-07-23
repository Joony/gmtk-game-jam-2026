extends CanvasLayer

# Shows a tuning value for a moment when a debug control changes it, then fades out.
# Deliberately transient: it is for dialling in the look, not part of the game HUD.

const HOLD := 1.6
const FADE := 0.5

@onready var _label: Label = %Label

var _tween: Tween


func _ready() -> void:
	_label.modulate.a = 0.0


func bind(motion: ShipMotion) -> void:
	motion.speed_changed.connect(func(_s: float) -> void: _show(motion))
	motion.settings_changed.connect(func() -> void: _show(motion))


func _show(motion: ShipMotion) -> void:
	var ratio := motion.speed_ratio()
	# Percentages stop being readable once you are 30x cruise.
	var rate := "%.0f%% cruise" % (ratio * 100.0) if ratio < 2.0 else "x%.1f cruise" % ratio
	_label.text = "SPEED %.0f m/s  (%s)      STARS %.0f%%" % [
		motion.speed, rate, motion.star_density * 100.0
	]
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_label.modulate.a = 1.0
	_tween = create_tween()
	_tween.tween_interval(HOLD)
	_tween.tween_property(_label, "modulate:a", 0.0, FADE)
