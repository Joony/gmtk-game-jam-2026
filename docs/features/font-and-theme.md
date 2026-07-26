# Feature: Font and UI theme

**Date:** 2026-07-22
**Status:** Done, verified

## What was done

- Font: `assets/AbolitionTest-Regular.otf` — a condensed bold display face that suits the
  industrial/sci-fi look.
- [ui/theme.tres](../../ui/theme.tres) — a Theme resource setting `default_font` and
  `default_font_size = 20`.
- Applied **project-wide** via `gui/theme/custom` in `project.godot`, so every Control picks it up
  automatically. No per-label font overrides anywhere, and new UI inherits it for free.

Existing per-node `theme_override_font_sizes` (the intro's 256px countdown, menu titles, buttons)
still apply — those override size only, not the typeface.

## How it was verified

Rendered every UI screen to PNG with [tests/capture_scene.gd](../../tests/capture_scene.gd) and
inspected each one: intro countdown, main menu, START prompt, pause menu. All render in the new
face at the right sizes and weights, with no fallback-font artifacts.

Also confirmed rendering in the exported web build.

## Missing glyphs on the web build — fixed 2026-07-26

`AbolitionTest-Regular.otf` is a **trial cut and maps only 66 codepoints**: A-Z, a-z, 0-9,
space, comma, period, hyphen. Absent: `! " # $ % & ' ( ) * + / : ; < = > ? @ [ \ ] ^ _ \` { | } ~`
and **every non-ASCII character**, so `—` and `·` are gone too.

Nobody saw this for four days because the font was imported with `allow_system_fallback=true`
and macOS quietly supplied the missing glyphs. The Web export has no system fonts, so on the
first itch-ready build the HUD read `3▯19`, `100▯`, `▯E▯ WAKE`, and the malfunction lines were
more boxes than words. Headless tests never rasterize, so the suite was green throughout.

The fix, in three parts:

- [scripts/ui/font_fallback.gd](../../scripts/ui/font_fallback.gd), autoload `FontFallback`:
  attaches `ThemeDB.fallback_font` — the engine's own Open Sans SemiBold, compiled into the
  export template — to the theme font's `fallbacks`. Costs no new asset, exists on every
  platform including Web, and does not extend the trial font's licence over anything. It has
  to be code: a fallback list lives on the Font *resource*, and the built-in font has no
  `res://` path a `.tres` could reference.
- **`allow_system_fallback=false`** in the font's `.import`. Desktop now renders exactly what
  the web build renders, so the next missing glyph shows up here instead of on itch.
- [tests/smoke_font_fallback.gd](../../tests/smoke_font_fallback.gd) asserts the fallback is
  attached and that **the fallback font object itself** carries every character the UI prints.
  Asserting on that object rather than on `has_char` is deliberate: with system fallback
  available, `has_char` can be satisfied by macOS and would pass whether or not the fix works.

### How it was verified

[tests/capture_font_glyphs.gd](../../tests/capture_font_glyphs.gd) renders the real HUD strings
with `allow_system_fallback` forced off — i.e. in the web build's font environment — and takes
`nofallback` to strip the fix and reproduce the bug. Run without `--headless`:

```
godot --path . --resolution 1100x620 -s tests/capture_font_glyphs.gd -- out.png [nofallback]
```

`nofallback` reproduces `OXYGEN 3▯19` / `DRIVE 100▯` / `▯E▯ WAKE` on the desktop machine;
without it, every string renders correctly. Open Sans's punctuation is narrow enough that it
sits beside the condensed display face better than expected.

## Notes

- Changing the game's typeface is now a one-line edit in `ui/theme.tres`.
- **Licence:** the trial cut is almost certainly not licensed for embedding in a distributed
  build, and a web export bakes it into `index.pck`. A licensed `.woff`/`.woff2` drops straight
  in — Godot 4's dynamic font importer reads both — and would retire both the licence question
  and most of the glyph gaps.
- If a second face is ever needed (e.g. a readable body font for the interaction prompts in step 8),
  add it as a named theme type in the same resource rather than overriding fonts per node.
