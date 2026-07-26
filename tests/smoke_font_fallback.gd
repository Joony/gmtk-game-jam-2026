extends SceneTree

# The display font is a 66-glyph trial cut, and the Web export has no system fonts to cover
# what it lacks. This suite pins down that every character the UI actually prints is
# reachable — from the font itself or from the fallback FontFallback attaches at startup.
#
# WHY NOT JUST ASSERT `has_char`. On desktop `has_char` can be satisfied by the OS via
# `allow_system_fallback=true`, which is exactly the crutch the web build does not have — so
# a bare `has_char` check passes on this machine whether or not the fix works. The decisive
# assertion is that the *fallback font object* has the glyph, since that is the one shipped
# inside the export. Both are checked, in that order.

# Every character used by HUD, nav and end-screen strings that the trial font is missing.
# `·` and `—` are here because the trial cut maps zero non-ASCII codepoints.
const REQUIRED_CHARS := ":%!~()[]/·—+.,"

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	root.call_deferred("add_child", _Runner.new(self))


func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("  ok   %s" % label)
	else:
		failures.append(label)
		print("  FAIL %s" % label)


class _Runner:
	extends Node

	var suite: SceneTree


	func _init(owner_suite: SceneTree) -> void:
		suite = owner_suite


	func _ready() -> void:
		_run()


	func _run() -> void:
		_test_theme_font_has_a_fallback()
		_test_fallback_covers_every_character_we_print()
		_test_the_trial_font_still_owns_the_letterforms()

		print("-- %d checks, %d failures --" % [suite.checks, suite.failures.size()])
		for failure in suite.failures:
			print("   FAILED: %s" % failure)
		suite.quit(1 if suite.failures.size() > 0 else 0)


	func _theme_font() -> Font:
		var theme := ThemeDB.get_project_theme()
		return null if theme == null else theme.default_font


	func _test_theme_font_has_a_fallback() -> void:
		print("[the project theme's font has a shipped fallback]")
		var theme := ThemeDB.get_project_theme()
		suite.check(theme != null, "the project theme is set in project.godot")
		var font := _theme_font()
		suite.check(font != null, "and it has a default font")
		if font == null:
			return
		# The autoload runs before any scene, so by the time a test body runs it is done.
		suite.check(not font.fallbacks.is_empty(),
			"FontFallback attached a fallback (%d)" % font.fallbacks.size())

	func _test_fallback_covers_every_character_we_print() -> void:
		print("[the fallback itself carries the glyphs the trial font lacks]")
		# Not the theme font: the fallback object, so the OS cannot answer for it.
		var fallback := ThemeDB.fallback_font
		suite.check(fallback != null, "ThemeDB.fallback_font exists (engine built-in)")
		if fallback == null:
			return
		var missing := ""
		for character in REQUIRED_CHARS:
			if not fallback.has_char(character.unicode_at(0)):
				missing += character
		suite.check(missing.is_empty(),
			"the fallback has every character we print%s" % ("" if missing.is_empty() else ", missing: " + missing))

		var font := _theme_font()
		if font != null:
			var unreachable := ""
			for character in REQUIRED_CHARS:
				if not font.has_char(character.unicode_at(0)):
					unreachable += character
			suite.check(unreachable.is_empty(),
				"and the theme font resolves them%s" % ("" if unreachable.is_empty() else ", missing: " + unreachable))


	func _test_the_trial_font_still_owns_the_letterforms() -> void:
		print("[the fallback did not displace the display face]")
		var font := _theme_font()
		if font == null:
			return
		# A regression here would mean the HUD had quietly switched to Open Sans entirely.
		suite.check(font.get_font_name().to_lower().contains("abolition"),
			"the theme font is still Abolition (%s)" % font.get_font_name())
		for character in "ABCXYZ0189":
			suite.check(font.has_char(character.unicode_at(0)),
				"the display font draws '%s' itself" % character)
