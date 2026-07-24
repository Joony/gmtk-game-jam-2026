#!/usr/bin/env bash
# Run every headless smoke suite and report a truthful pass/fail tally.
#
# WHY A SCRIPT AND NOT `for t in ...; do godot -s $t; done`. A naive loop trusts the exit
# code, and a GDScript **parse error makes `godot -s` exit 0** — so a broken test reports
# success. This runner treats a suite as green ONLY when all three hold:
#   1. exit code 0
#   2. no "Parse Error" / "SCRIPT ERROR" in the output
#   3. a positive summary line was actually printed ("TEST PASS" or "0 failures --")
# Requirement 3 is what catches the parse-error-exits-0 case: a suite that never ran prints
# no summary, so it fails here even though Godot returned 0.
#
# Usage:
#   tools/run_tests.sh              # run all tests/smoke_*.gd
#   tools/run_tests.sh run_state    # run only suites whose name contains "run_state"
#   GODOT=/path/to/godot tools/run_tests.sh
#   REIMPORT=1 tools/run_tests.sh   # (re)import assets first — needed after adding art/audio

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

if [[ "${REIMPORT:-0}" == "1" ]]; then
	echo "Reimporting assets..."
	"$GODOT" --headless --import >/dev/null 2>&1 || true
fi

filter="${1:-}"
suites=()
for f in tests/smoke_*.gd; do
	[[ -f "$f" ]] || continue
	if [[ -z "$filter" || "$f" == *"$filter"* ]]; then suites+=("$f"); fi
done

if [[ ${#suites[@]} -eq 0 ]]; then
	echo "no matching smoke suites${filter:+ for '$filter'}" >&2
	exit 1
fi

pass=0
fail=0
failed_names=()

for suite in "${suites[@]}"; do
	name="$(basename "$suite" .gd)"
	out="$("$GODOT" --headless -s "$suite" 2>&1)"
	code=$?

	reason=""
	if [[ $code -ne 0 ]]; then
		reason="exit $code"
	elif grep -q "Parse Error" <<<"$out"; then
		reason="PARSE ERROR (would have exited 0!)"
	elif grep -q "SCRIPT ERROR" <<<"$out"; then
		reason="script error"
	elif ! grep -qE "TEST PASS|0 failures --" <<<"$out"; then
		# No positive summary: either it printed failures, or it never ran.
		reason="no pass summary (failed or did not run)"
	fi

	if [[ -z "$reason" ]]; then
		printf "  \033[32mPASS\033[0m  %s\n" "$name"
		pass=$((pass + 1))
	else
		printf "  \033[31mFAIL\033[0m  %-30s %s\n" "$name" "$reason"
		# Echo the failing lines so the cause is visible without re-running.
		grep -E "FAIL|Parse Error|SCRIPT ERROR|ERROR:" <<<"$out" \
			| grep -viE "leaked|resources still in use|PagedAllocator|RID alloc|Blender" \
			| head -5 | sed 's/^/          /'
		fail=$((fail + 1))
		failed_names+=("$name")
	fi
done

echo
echo "=== $pass passed, $fail failed of $((pass + fail)) ==="
if [[ $fail -gt 0 ]]; then
	echo "failed: ${failed_names[*]}"
	exit 1
fi
