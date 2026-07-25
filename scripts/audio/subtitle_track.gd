class_name SubtitleTrack
extends RefCounted

# The captions for ONE voice line, parsed from a SubRip (.srt) file sitting beside the audio.
#
# WHY SRT AND NOT A GDSCRIPT TABLE. The text and the timings are the one part of the audio a
# non-programmer has to be able to fix: a mis-heard word, a caption that lingers, a re-recorded
# take that runs half a second longer. As a const Dictionary every one of those is a code edit
# in a file that also owns the audio buses. As .srt they are a plain text file next to the mp3,
# openable in any editor and in every subtitling tool that exists — and the format already
# solves the problem of expressing "this text, between these two moments".
#
# The parser is deliberately forgiving. It keys on the `-->` line and ignores everything it
# does not understand, so a BOM, CRLF line endings, a missing cue number, WebVTT's `.` decimal
# separator, or a stray comment block all parse rather than throwing the file away. A caption
# file is worth having even when part of it is malformed; the alternative is silence.

const ARROW := "-->"

## Sorted by start time. Each cue is {start: float, end: float, text: String}, in seconds.
var cues: Array[Dictionary] = []


## Parse the .srt at `path`. Returns null when there is no file there — a missing caption file
## is a normal state (a line recorded but not yet subtitled), not an error, and the caller
## decides whether to complain about it.
static func load_srt(path: String) -> SubtitleTrack:
	if not FileAccess.file_exists(path):
		return null
	return parse(FileAccess.get_file_as_string(path))


static func parse(source: String) -> SubtitleTrack:
	var track := SubtitleTrack.new()
	var lines := source.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	var i := 0
	while i < lines.size():
		var line := lines[i]
		i += 1
		# Cue numbers, blank lines and anything else are skipped by simply not being a
		# timing line. This is what makes a BOM on line 1 harmless.
		if not line.contains(ARROW):
			continue
		var halves := line.split(ARROW)
		if halves.size() != 2:
			continue
		var start := _seconds(halves[0])
		var end := _seconds(halves[1])
		# The text is every line up to the next blank one, kept as separate lines: an author
		# who broke a caption in two meant it, and re-flowing it is the display's business.
		var body := PackedStringArray()
		while i < lines.size() and lines[i].strip_edges() != "":
			body.append(lines[i].strip_edges())
			i += 1
		if start < 0.0 or end <= start or body.is_empty():
			continue
		track.cues.append({"start": start, "end": end, "text": "\n".join(body)})
	track.cues.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["start"] < b["start"])
	return track


## What should be on screen at `seconds` into the clip, or "" for the gaps between cues.
func text_at(seconds: float) -> String:
	var index := index_at(seconds)
	return "" if index < 0 else str(cues[index]["text"])


## Which cue covers `seconds`, or -1. Every cue is checked rather than stopping at the first
## one that starts too late: cues are sorted but a hand-edited file can overlap, and a scan of
## a handful of entries costs nothing at the once-a-frame this is called.
func index_at(seconds: float) -> int:
	for i in cues.size():
		if seconds >= float(cues[i]["start"]) and seconds < float(cues[i]["end"]):
			return i
	return -1


## When the last caption clears. Used by the tests to check a track against the real length of
## the audio it belongs to — a cue past the end of the clip never shows.
func last_end() -> float:
	var end := 0.0
	for cue in cues:
		end = maxf(end, float(cue["end"]))
	return end


## "00:01:02,500" -> 62.5. Also accepts "01:02,5" and WebVTT's "00:01:02.500", and returns
## -1.0 for anything it cannot read.
static func _seconds(stamp: String) -> float:
	var parts := stamp.strip_edges().replace(",", ".").split(":")
	if parts.is_empty() or parts.size() > 3:
		return -1.0
	var total := 0.0
	for part in parts:
		if not part.is_valid_float():
			return -1.0
		total = total * 60.0 + part.to_float()
	return total
