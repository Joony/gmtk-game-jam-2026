#!/usr/bin/env bash
# Export the Web build and zip it for itch.io upload.
#
# WHY A SCRIPT AND NOT `godot --export-release Web`. Three things bite a headless export:
#   1. **Godot exits 0 on a failed export.** A missing export template or a broken resource
#      prints an error and still returns success, so the exit code alone is worthless. This
#      script greps the output and then checks the artifacts really exist and are plausible.
#   2. **Assets must be imported first.** On a clean checkout (or CI) there is no .godot/
#      import cache, and the export silently produces a near-empty .pck — the game loads to
#      a black screen. `--import` runs first, always.
#   3. **build/ lives inside the project.** Godot's scanner imports the PNGs the *previous*
#      export wrote there, and then bundles them into the *next* .pck. A .gdignore in build/
#      stops that feedback loop (the file is recreated here since build/ is gitignored).
#
# The zip stores files at its root (index.html, not web/index.html) because that is what
# itch.io requires for an HTML5 project.
#
# Usage:
#   tools/export_web.sh              # release export -> build/web/ + build/<name>-web.zip
#   tools/export_web.sh --debug      # debug template (bigger, keeps the JS console noisy)
#   GODOT=/path/to/godot tools/export_web.sh

set -uo pipefail

# --- locate Godot ---
GODOT="${GODOT:-}"
if [[ -z "$GODOT" ]]; then
	for candidate in \
		"/Applications/Godot.app/Contents/MacOS/Godot" \
		"$(command -v godot 2>/dev/null || true)" \
		"$(command -v godot4 2>/dev/null || true)"; do
		if [[ -n "$candidate" && -x "$candidate" ]]; then GODOT="$candidate"; break; fi
	done
fi
if [[ -z "$GODOT" || ! -x "$GODOT" ]]; then
	echo "error: Godot binary not found. Set GODOT=/path/to/godot." >&2
	exit 1
fi

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

mode="release"
if [[ "${1:-}" == "--debug" ]]; then
	mode="debug"
elif [[ -n "${1:-}" ]]; then
	echo "error: unknown argument '$1' (expected --debug or nothing)" >&2
	exit 1
fi

preset="Web"
out_dir="build/web"
out_html="$out_dir/index.html"

# Zip name follows the project's own title so the itch upload is self-describing.
project_name="$(sed -n 's/^config\/name="\(.*\)"$/\1/p' project.godot | head -1)"
[[ -n "$project_name" ]] || project_name="game"
slug="$(printf '%s' "$project_name" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed 's/-\{2,\}/-/g; s/^-//; s/-$//')"
zip_path="build/${slug}-web.zip"

# --- 1. clean the output dir ---
# Stale files from a previous export would otherwise ride along in the zip (itch counts
# them against the 1 GB limit and they can shadow renamed assets).
rm -rf "$out_dir" "$zip_path"
mkdir -p "$out_dir"
: > build/.gdignore   # see WHY note 3 above

# --- 2. import assets ---
echo "Importing assets (this is slow on a cold cache)..."
"$GODOT" --headless --import >/dev/null 2>&1 || true

# --- 3. export ---
echo "Exporting '$preset' ($mode)..."
export_out="$("$GODOT" --headless "--export-$mode" "$preset" "$out_html" 2>&1)"
export_code=$?

# --- 4. verify, because the exit code lies (WHY note 1) ---
fatal=""
if [[ $export_code -ne 0 ]]; then
	fatal="godot exited $export_code"
elif grep -qiE "no export template found|Export templates for this platform are missing|Cannot export project with preset|Unable to open file for writing" <<<"$export_out"; then
	fatal="$(grep -iE "no export template found|templates for this platform are missing|Cannot export project|Unable to open file" <<<"$export_out" | head -1)"
elif [[ ! -s "$out_html" || ! -s "$out_dir/index.wasm" || ! -s "$out_dir/index.pck" ]]; then
	fatal="expected index.html/index.wasm/index.pck in $out_dir, but they are missing or empty"
fi

if [[ -n "$fatal" ]]; then
	printf "  \033[31mFAIL\033[0m  export: %s\n" "$fatal" >&2
	grep -E "ERROR|error:|Failed" <<<"$export_out" | head -10 | sed 's/^/          /' >&2
	exit 1
fi

# A .pck under ~1 MB means the import step did not take and the game will boot to a black
# screen. Warn loudly rather than shipping a broken build to a jam page.
pck_bytes="$(wc -c < "$out_dir/index.pck" | tr -d ' ')"
if [[ "$pck_bytes" -lt 1000000 ]]; then
	printf "  \033[33mWARN\033[0m  index.pck is only %s bytes — assets are probably missing.\n" "$pck_bytes" >&2
	printf "        Open the project in the editor once to build the import cache, then re-run.\n" >&2
fi

# Any leftover .import sidecars are editor metadata, never needed by the browser.
find "$out_dir" -name '*.import' -delete
find "$out_dir" -name '.DS_Store' -delete

# --- 5. zip with files at the archive root (itch.io requirement) ---
if ! command -v zip >/dev/null 2>&1; then
	echo "error: 'zip' not found; build is in $out_dir but was not archived." >&2
	exit 1
fi
( cd "$out_dir" && zip -q -r -X "$project_root/$zip_path" . -x '.*' ) || {
	echo "error: zip failed" >&2
	exit 1
}

# --- 6. report ---
echo
printf "  \033[32mOK\033[0m  %s\n" "$zip_path"
echo "      $(du -h "$zip_path" | cut -f1) zip, $(du -h "$out_dir/index.pck" | cut -f1) pck, $(du -h "$out_dir/index.wasm" | cut -f1) wasm"
echo "      contents: $(unzip -Z1 "$zip_path" | tr '\n' ' ')"
echo
echo "Upload $zip_path to itch.io as an HTML project (index.html is at the zip root)."
