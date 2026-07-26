#!/usr/bin/env bash
# Draft the .srt caption files that sit beside the voiceover mp3s.
#
# Transcribes each clip on this machine with Apple's Speech framework (no upload, no API key,
# no quota), splits the timed words into readable cues and writes CD_Whatever.srt next to
# CD_Whatever.mp3. The game picks them up by filename — see scripts/audio/subtitle_track.gd.
#
#   tools/make_subtitles.sh                       # every mp3 that has no .srt yet
#   tools/make_subtitles.sh assets/audio/voiceover/CD_ReturnToCryo.mp3
#   tools/make_subtitles.sh --force               # redo them all, discarding hand edits
#   tools/make_subtitles.sh --print <file.mp3>    # transcript to stdout, write nothing
#
# THE OUTPUT IS A DRAFT, NOT THE ANSWER. Speech recognition is confident and wrong in ways
# proofreading a transcript will not catch — it produced "the laugh support is failing" and
# "one of them pops in the engine room", both of which read as sentences. **Play the clip and
# read along** before committing, then hand-fix the .srt: it is the source of truth from that
# point on, which is why existing files are skipped unless you pass --force.
#
# Requires macOS 26+ (the on-device SpeechAnalyzer API), Xcode's swiftc, ffmpeg and python3.

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

VOICE_DIR="assets/audio/voiceover"
# Under build/ because it is gitignored, and rebuilt whenever the .swift is newer.
BIN="build/tools/transcribe_speech"
SRC="tools/transcribe_speech.swift"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

force=0
print_only=0
files=()
for arg in "$@"; do
	case "$arg" in
		--force) force=1 ;;
		--print) print_only=1 ;;
		-h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		-*) echo "unknown option: $arg" >&2; exit 2 ;;
		*) files+=("$arg") ;;
	esac
done

for tool in ffmpeg ffprobe python3 swiftc; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		echo "error: $tool not found." >&2
		[[ "$tool" == "swiftc" ]] && echo "  Install Xcode, then: xcode-select --install" >&2
		[[ "$tool" == ffmpeg || "$tool" == ffprobe ]] && echo "  brew install ffmpeg" >&2
		exit 1
	fi
done

# Compile once and cache. The first run of the BINARY may also download the speech model,
# which the Swift tool reports on stderr.
if [[ ! -x "$BIN" || "$SRC" -nt "$BIN" ]]; then
	echo "Building $BIN..."
	mkdir -p "$(dirname "$BIN")"
	swiftc -O -parse-as-library "$SRC" -o "$BIN"
fi

if [[ ${#files[@]} -eq 0 ]]; then
	while IFS= read -r mp3; do files+=("$mp3"); done < <(find "$VOICE_DIR" -name '*.mp3' | sort)
fi

written=0
skipped=0
for mp3 in "${files[@]}"; do
	if [[ ! -f "$mp3" ]]; then
		echo "  no such file: $mp3" >&2
		exit 1
	fi
	srt="${mp3%.*}.srt"
	name="$(basename "$mp3")"

	if [[ $print_only -eq 0 && -f "$srt" && $force -eq 0 ]]; then
		printf "  skip   %-34s (already has captions; --force to redo)\n" "$name"
		skipped=$((skipped + 1))
		continue
	fi

	# 16 kHz mono is what the recogniser wants; handing it the mp3 directly works but makes
	# it resample every clip itself.
	wav="$WORK/$(basename "${mp3%.*}").wav"
	ffmpeg -v error -y -i "$mp3" -ar 16000 -ac 1 "$wav"
	duration="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$mp3")"

	if ! "$BIN" "$wav" > "$WORK/words.json"; then
		echo "  FAILED to transcribe $name" >&2
		exit 1
	fi

	if [[ $print_only -eq 1 ]]; then
		echo "--- $name (${duration}s)"
		python3 -c 'import json,sys; print("".join(w["w"] for w in json.load(sys.stdin)["words"]).strip())' \
			< "$WORK/words.json"
		continue
	fi

	python3 tools/srt_from_words.py --duration "$duration" < "$WORK/words.json" > "$srt"
	cues="$(grep -c -- '-->' "$srt")"
	printf "  wrote  %-34s %s cues, %.2fs\n" "$(basename "$srt")" "$cues" "$duration"
	written=$((written + 1))
done

if [[ $print_only -eq 1 ]]; then
	exit 0
fi

echo
echo "=== $written written, $skipped skipped ==="
if [[ $written -gt 0 ]]; then
	echo "These are DRAFTS. Play each clip, read along, and fix the .srt before committing:"
	echo "  tools/run_tests.sh subtitles     # checks every line is captioned and in range"
fi
