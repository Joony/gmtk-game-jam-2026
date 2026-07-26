#!/usr/bin/env python3
"""Turn timed words into a SubRip (.srt) caption file.

Reads {"words": [{"w": " word", "s": 1.23, "e": 1.45}, ...]} on stdin — the output of
tools/transcribe_speech.swift — and writes .srt to stdout.

Called by tools/make_subtitles.sh; useful on its own if you already have timings.

    tools/srt_from_words.py --duration 10.03 < words.json > CD_Whatever.srt

WHERE THE CUE BREAKS GO. A caption is a reading task with a deadline, so the split points are
chosen in this order:

  1. After sentence-ending punctuation. A cue that ends mid-sentence makes the reader hold
     half a thought while the next one loads.
  2. At a PAUSE in the delivery. The speaker already decided where the phrase ends; a gap
     between two words is that decision, recorded.
  3. After a comma or a dash, if the cue is getting long.
  4. Failing all of those, at the last word that fits.

The output satisfies the invariants tests/smoke_subtitles.gd asserts: cues are in order, never
overlap, start at the top of the clip and hold to the end of it.
"""
import argparse
import json
import sys

# Roughly two lines' worth in the caption label, and it is a limit on READING rather than on
# layout: past it the eye starts scanning instead of taking the line in at a glance.
MAX_CHARS = 56
## No caption stays up longer than this, and none flashes by faster than MIN_SECONDS.
MAX_SECONDS = 5.5
MIN_SECONDS = 0.9
## A gap between words this long is the speaker ending a phrase, and a good place to cut.
PAUSE = 0.28

SENTENCE_END = (".", "!", "?", "…")
CLAUSE_END = (",", ";", ":", "—", "–")

## Never end a caption on one of these. They are the words that point AT the next word, so a
## break after one leaves the reader holding a preposition with nothing to attach it to —
## "...until we reach / our destination" is the failure this rule exists to stop. It is the
## one piece of grammar worth teaching a splitter that has no idea what it is reading.
LINKING_WORDS = {
    "a", "an", "the", "and", "or", "but", "nor", "so", "yet",
    "of", "to", "in", "on", "at", "by", "for", "from", "with", "into", "onto", "over",
    "under", "up", "down", "off", "out", "as", "than", "that", "this", "these", "those",
    "is", "are", "was", "were", "be", "been", "am", "do", "does", "did", "will", "would",
    "can", "could", "should", "may", "might", "must", "have", "has", "had",
    "i", "you", "he", "she", "it", "we", "they", "my", "your", "his", "her", "its",
    "our", "their", "them", "us", "if", "when", "while", "until", "before", "after",
    "some", "any", "no", "not", "all", "one", "there", "here", "how", "what", "who",
}


def _text(words):
    return "".join(w["w"] for w in words).strip()


def _best_break(current, is_final=False):
    """Where to cut an over-long run of words. Returns an index to break AFTER, or None.

    Scores every candidate on the pause that follows it, punctuation, how full the resulting
    line is, and whether it would strand a linking word at the end. Cutting at whichever word
    happened to overflow is what produces "...until we reach / our destination" — grammatical
    nonsense the reader has to re-assemble, when a break two words earlier reads as a phrase.
    """
    best_index, best_score = None, 0.0
    for i in range(len(current) - 1):
        head = _text(current[:i + 1])
        if len(head) < MAX_CHARS * 0.4:
            continue  # too short to stand as a caption of its own
        if len(head) > MAX_CHARS:
            break  # everything past here is over the limit too
        word = current[i]["w"].strip()
        # A real pause outweighs everything else: the speaker is telling you where the
        # phrase ended, and no heuristic beats that.
        score = 4.0 * (current[i + 1]["s"] - current[i]["e"])
        if word.endswith(SENTENCE_END):
            score += 1.5
        elif word.endswith(CLAUSE_END):
            score += 0.8
        # Otherwise use the line, rather than breaking early and leaving half a caption.
        score += float(len(head)) / MAX_CHARS
        if word.strip(".,;:!?—–\"'").lower() in LINKING_WORDS:
            score -= 1.2
        # No orphans. Only checked on the last run of words, where what follows the break is
        # known to be the whole of the rest — mid-stream the tail is still growing, and
        # docking every candidate for it would just bias every break early.
        if is_final and 0 < len(_text(current[i + 1:])) < MAX_CHARS * 0.4:
            score -= 1.2
        if best_index is None or score > best_score:
            best_index, best_score = i, score
    return best_index


def split_cues(words):
    """Group timed words into cues. Returns [[start, end, text], ...]."""
    cues = []
    current = []

    def flush(upto=None):
        nonlocal current
        head = current if upto is None else current[:upto + 1]
        rest = [] if upto is None else current[upto + 1:]
        if _text(head):
            cues.append([head[0]["s"], head[-1]["e"], _text(head)])
        current = rest

    for i, word in enumerate(words):
        current.append(word)
        is_last = i == len(words) - 1
        length = word["e"] - current[0]["s"]

        if not is_last:
            stripped = word["w"].strip()
            gap = words[i + 1]["s"] - word["e"]
            # A sentence has landed. Only break if the cue has been up long enough to read —
            # otherwise a trailing "Okay." gets a cue of its own and blinks past.
            if stripped.endswith(SENTENCE_END) and length >= MIN_SECONDS:
                flush()
                continue
            # The speaker stopped. Trust them: they already decided where the phrase ended.
            if gap >= PAUSE and length >= MIN_SECONDS:
                flush()
                continue

        # Running long. Back up to the best break inside what we have rather than cutting at
        # the word that tipped it over. This runs on the LAST word too — skipping it there is
        # how the final sentence of a clip ends up as one unbroken caption.
        if len(_text(current)) >= MAX_CHARS or length >= MAX_SECONDS:
            flush(_best_break(current, is_last))

    flush()
    return cues


def fit(cues, duration):
    """Clamp cues into the clip and close the gaps that would strobe.

    Three fixes, each for a caption that is technically valid and visibly wrong:
    a first cue that starts a beat late (the first word is often clipped by the recogniser),
    a hairline gap between two cues that blanks the screen for a frame, and a last cue that
    vanishes while the speaker is still finishing the word.
    """
    if not cues:
        return cues
    cues[0][0] = 0.0
    for i in range(len(cues) - 1):
        # Hold each caption until the next one starts, so back-to-back speech reads as
        # continuous text rather than flickering. A real silence (over a second) is left
        # alone — a blank screen during a pause is correct.
        if cues[i + 1][0] - cues[i][1] < 1.0:
            cues[i][1] = cues[i + 1][0]
        cues[i][1] = min(cues[i][1], cues[i + 1][0])
    cues[-1][1] = duration if duration > 0.0 else cues[-1][1]
    return [c for c in cues if c[1] > c[0]]


def stamp(seconds):
    ms = int(round(max(seconds, 0.0) * 1000.0))
    h, ms = divmod(ms, 3_600_000)
    m, ms = divmod(ms, 60_000)
    s, ms = divmod(ms, 1000)
    return "%02d:%02d:%02d,%03d" % (h, m, s, ms)


def to_srt(cues):
    return "\n".join(
        "%d\n%s --> %s\n%s\n" % (i, stamp(start), stamp(end), text)
        for i, (start, end, text) in enumerate(cues, 1)
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--duration", type=float, default=0.0,
                        help="length of the audio in seconds; the last cue is held to it")
    args = parser.parse_args()

    words = json.load(sys.stdin).get("words", [])
    if not words:
        sys.stderr.write("srt_from_words: nothing was recognised\n")
        return 1
    cues = fit(split_cues(words), args.duration)
    if not cues:
        sys.stderr.write("srt_from_words: no cues survived\n")
        return 1
    sys.stdout.write(to_srt(cues))
    return 0


if __name__ == "__main__":
    sys.exit(main())
