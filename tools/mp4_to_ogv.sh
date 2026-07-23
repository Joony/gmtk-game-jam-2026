#!/usr/bin/env bash
# Convert an MP4 (or any ffmpeg-readable video) to Ogg Theora .ogv for Godot.
#
# WHY THIS EXISTS. Godot 4's VideoStreamPlayer only plays Ogg Theora — drop an .mp4 in and
# it silently has no stream. The intro video arrived as an .mp4, so every new cut of it has
# to be transcoded. This wraps the exact ffmpeg invocation used for the shipping intro so it
# is one command, not a remembered recipe.
#
# Usage:
#   tools/mp4_to_ogv.sh <input.mp4> [output.ogv]
#
# With no output path it writes assets/video/<input-basename>.ogv, lower-cased with spaces
# turned to underscores (Godot resource paths are happier without spaces). Quality is tuned
# for a short full-screen intro; override with the VQ / AQ env vars if you need to.
#
#   VQ=8 AQ=5 tools/mp4_to_ogv.sh "New Intro.mp4"     # higher quality, bigger file
#
# Video quality VQ and audio quality AQ are ffmpeg's -q:v / -q:a, both 0..10 (higher = better).

set -euo pipefail

VQ="${VQ:-6}"
AQ="${AQ:-4}"

if ! command -v ffmpeg >/dev/null 2>&1; then
	echo "error: ffmpeg not found. Install it (e.g. 'brew install ffmpeg')." >&2
	exit 1
fi

if [[ $# -lt 1 ]]; then
	echo "usage: tools/mp4_to_ogv.sh <input.mp4> [output.ogv]" >&2
	exit 2
fi

input="$1"
if [[ ! -f "$input" ]]; then
	echo "error: input file not found: $input" >&2
	exit 1
fi

# Resolve the project root from this script's location, so the default output lands in the
# right assets/video/ no matter where the script is called from.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"

if [[ $# -ge 2 ]]; then
	output="$2"
else
	base="$(basename "$input")"
	base="${base%.*}"                        # strip extension
	slug="$(echo "$base" | tr '[:upper:] ' '[:lower:]_')"
	output="$project_root/assets/video/${slug}.ogv"
fi

mkdir -p "$(dirname "$output")"

echo "Converting:"
echo "  in : $input"
echo "  out: $output"
echo "  q  : video=$VQ audio=$AQ"

# -c:v libtheora / -c:a libvorbis are the only codecs Godot's VideoStreamPlayer accepts.
ffmpeg -y -i "$input" -c:v libtheora -q:v "$VQ" -c:a libvorbis -q:a "$AQ" "$output" \
	-loglevel error -stats

in_size=$(du -h "$input" | cut -f1)
out_size=$(du -h "$output" | cut -f1)
echo "Done. $in_size -> $out_size"
echo
echo "Next: reference it from a VideoStreamPlayer, e.g. scenes/intro.tscn's Video node."
echo "If it replaces the current intro, keep the same path so the scene needs no edit:"
echo "  assets/video/perpetual_pickle_intro.ogv"
