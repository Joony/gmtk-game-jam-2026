extends SceneTree
# Dev utility: render the punctuation the HUD prints, with system fallback DISABLED, so the
# web condition can be eyeballed on a desktop machine.
#
# WHY THE SWITCH MATTERS. The display font is a 66-glyph trial cut and is imported with
# `allow_system_fallback=true`, so on macOS the OS quietly supplies `:` `%` `[` `]` `—` and
# the rest. The Web export has no system fonts, so there the same strings render as .notdef
# boxes. Turning system fallback off here reproduces the web build's font environment
# exactly — what this PNG shows is what itch.io would show.
#
# Run WITHOUT --headless (needs a real renderer):
#   godot --path . --resolution 1100x620 -s tests/capture_font_glyphs.gd -- <out.png> [nofallback]
#
# Pass `nofallback` as the second argument to also strip the Font.fallbacks list, i.e. to see
# the bug rather than the fix.

const SAMPLES := [
	"OXYGEN 3:19",
	"DRIVE 100%",
	"[E] WAKE",
	"! DRIVE REGULATOR — STUCK OPEN",
	"~ OXYGEN SILO — 40%, needs SEAL",
	"0.25 DAYS PER SECOND  ·  [E] WAKE",
	"(-12% drive, falling to -30%)",
	"ABCDEFGHIJKLM 0123456789",
]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://font_glyphs.png"
	var strip_fallbacks := args.size() > 1 and args[1] == "nofallback"

	var theme: Theme = ThemeDB.get_project_theme()
	var font: Font = theme.default_font

	if strip_fallbacks:
		font.fallbacks = []
	# This is the whole point of the capture — see the header note.
	if font is FontFile:
		(font as FontFile).allow_system_fallback = false

	var background := ColorRect.new()
	background.color = Color(0.05, 0.05, 0.06)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 24.0
	column.offset_top = 16.0
	column.add_theme_constant_override("separation", 14)
	background.add_child(column)

	var heading := Label.new()
	heading.text = "system fallback OFF — %s" % (
		"fallbacks stripped (the bug)" if strip_fallbacks else "Font.fallbacks active (the fix)"
	)
	heading.add_theme_font_size_override("font_size", 26)
	heading.modulate = Color(0.6, 0.65, 0.7)
	column.add_child(heading)

	for sample in SAMPLES:
		var label := Label.new()
		label.text = sample
		label.add_theme_font_size_override("font_size", 44)
		column.add_child(label)

	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw

	var image := get_root().get_texture().get_image()
	image.save_png(out_path)
	print("wrote %s" % out_path)
	quit()
