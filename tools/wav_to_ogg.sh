#!/usr/bin/env bash
# Convert WAV audio to Ogg Vorbis for Godot.
#
# WHY THIS EXISTS. Music and long effects delivered as .wav are huge — the four music tracks
# were 115 MB of WAV, which would sink the web export. Vorbis brings that to ~7 MB and loops
# with a single flag (a WAV needs sample-accurate loop points). Godot plays both, so this is
# about size, not compatibility: use it for anything long (music, ambience). Short one-shot
# SFX are fine left as WAV, or are synthesised outright (see scripts/audio/sound_forge.gd).
#
# Usage:
#   tools/wav_to_ogg.sh <in.wav> [in2.wav ...]     # convert each next to itself as .ogg
#   tools/wav_to_ogg.sh assets/audio/*.wav         # a whole folder at once
#   tools/wav_to_ogg.sh in.wav out.ogg             # explicit single output (exactly 2 args)
#   AQ=7 tools/wav_to_ogg.sh track.wav             # higher quality, bigger file
#
# AQ is ffmpeg's audio quality -q:a, 0..10 (higher = better). Default 5 (~160 kbps), a good
# balance for looping game music.
#
# The source .wav is left in place — the .ogg is what the game loads (see the music paths in
# scripts/audio/audio_controller.gd). Delete the .wav masters if you do not need them.

set -euo pipefail

AQ="${AQ:-5}"

if ! command -v ffmpeg >/dev/null 2>&1; then
	echo "error: ffmpeg not found. Install it (e.g. 'brew install ffmpeg')." >&2
	exit 1
fi

if [[ $# -lt 1 ]]; then
	echo "usage: tools/wav_to_ogg.sh <in.wav> [more.wav ...]   (or: in.wav out.ogg)" >&2
	exit 2
fi

# Two args where the second ends in .ogg is the explicit single-output form. Otherwise every
# argument is treated as an input converted next to itself.
explicit_out=""
inputs=()
if [[ $# -eq 2 && "$2" == *.ogg ]]; then
	inputs=("$1")
	explicit_out="$2"
else
	inputs=("$@")
fi

convert_one() {
	local input="$1" output="$2"
	if [[ ! -f "$input" ]]; then
		echo "  skip (not found): $input" >&2
		return 1
	fi
	# -c:a libvorbis is the codec Godot imports as AudioStreamOggVorbis.
	ffmpeg -y -i "$input" -c:a libvorbis -q:a "$AQ" "$output" -loglevel error
	local in_size out_size
	in_size=$(du -h "$input" | cut -f1)
	out_size=$(du -h "$output" | cut -f1)
	printf "  %-40s %6s -> %6s\n" "$(basename "$input")" "$in_size" "$out_size"
}

echo "Converting WAV -> OGG (q:a=$AQ):"
failed=0
for input in "${inputs[@]}"; do
	if [[ -n "$explicit_out" ]]; then
		out="$explicit_out"
	else
		out="${input%.*}.ogg"
	fi
	mkdir -p "$(dirname "$out")"
	convert_one "$input" "$out" || failed=$((failed + 1))
done

echo "Done."
echo
echo "Godot imports .ogg as AudioStreamOggVorbis. To LOOP a track, either tick Loop on its"
echo "import settings, or set it in code — AudioController._load_music() already forces"
echo "loop = true on every music stream, so a track dropped in at an existing music path"
echo "loops with no further steps."

[[ $failed -eq 0 ]]
