extends Node

# Gives the display font a fallback that actually ships with the build.
#
# WHY THIS EXISTS. `AbolitionTest-Regular.otf` is a trial cut and maps only 66 codepoints:
# A-Z, a-z, 0-9, space, comma, period, hyphen. Everything else is absent — `:` `%` `!` `~`
# `(` `)` `[` `]` `/` and *every* non-ASCII character, so the em dash and `·` are gone too.
#
# On desktop nobody notices, because the font is imported with `allow_system_fallback=true`
# and macOS quietly supplies the missing glyphs. **The Web export has no system fonts**, so
# on itch every one of them renders as a .notdef box: the oxygen clock reads `3▯19`, drive
# reads `100▯`, and the malfunction lines are more boxes than words. Headless tests never
# rasterize, so nothing in the suite catches it either.
#
# The fallback is `ThemeDB.fallback_font` — the engine's own default (Open Sans SemiBold),
# compiled into the export template. That matters for two reasons: it costs no new asset and
# is present on every platform including Web, and it sidesteps the trial font's licence,
# which almost certainly does not cover embedding in a distributed game.
#
# This is done in code because a fallback list lives on the Font *resource*, and the built-in
# font has no `res://` path a `.tres` could point at.
#
# Punctuation therefore renders in a normal-width sans next to condensed display letters.
# That is the deliberate trade: mismatched glyphs beat missing ones. Swapping in a condensed
# open-licensed face (Oswald, Barlow Condensed) is a drop-in change here if it grates.


func _ready() -> void:
	var theme := ThemeDB.get_project_theme()
	if theme == null:
		push_warning("[FontFallback] no project theme; display font left without a fallback")
		return

	var font := theme.default_font
	if font == null:
		push_warning("[FontFallback] project theme has no default font")
		return

	# Don't stomp a list someone set deliberately in the import dock.
	if not font.fallbacks.is_empty():
		return

	font.fallbacks = [ThemeDB.fallback_font]
