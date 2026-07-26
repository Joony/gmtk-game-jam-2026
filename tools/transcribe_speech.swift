// On-device speech recognition with word-level timings, for tools/make_subtitles.sh.
//
// Prints one JSON object to stdout: {"words": [{"w": " word", "s": 1.23, "e": 1.45}, ...]}.
// Times are seconds from the start of the file. Every word carries its own range, which is
// what lets the caption splitter put a cue boundary exactly where the speaker paused rather
// than guessing from character counts.
//
// Uses SpeechAnalyzer/SpeechTranscriber (macOS 26+), NOT the older SFSpeechRecognizer: it runs
// entirely on this machine with no network round trip and no per-request quota, and the model
// is downloaded once by AssetInventory and cached by the OS.
//
// Build and run through tools/make_subtitles.sh — it caches the compiled binary. By hand:
//   swiftc -O -parse-as-library tools/transcribe_speech.swift -o /tmp/transcribe
//   /tmp/transcribe audio.wav

import AVFoundation
import Foundation
import Speech

@main
struct TranscribeSpeech {
    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write("transcribe: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }

    static func run() async throws {
        guard CommandLine.arguments.count > 1 else {
            FileHandle.standardError.write("usage: transcribe_speech <audio-file> [locale]\n".data(using: .utf8)!)
            exit(2)
        }
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let locale = Locale(identifier: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "en-US")

        // .audioTimeRange is the whole point — without it the result is a wall of text with no
        // idea when any of it was said, and cue timings would have to be invented.
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )

        // First run on a machine downloads the model; afterwards this returns nil immediately.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            FileHandle.standardError.write("transcribe: installing the \(locale.identifier) speech model, one time only...\n".data(using: .utf8)!)
            try await request.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])

        // Results have to be consumed while the analyzer runs, not after: the stream is fed as
        // the file is read, and awaiting the analysis first would deadlock against a consumer
        // that has not started.
        let collector = Task {
            var words: [[String: Any]] = []
            for try await result in transcriber.results {
                guard result.isFinal else { continue }
                for run in result.text.runs {
                    let text = String(result.text[run.range].characters)
                    guard let range = run.audioTimeRange else { continue }
                    words.append(["w": text, "s": range.start.seconds, "e": range.end.seconds])
                }
            }
            return words
        }

        let file = try AVAudioFile(forReading: url)
        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        let words = try await collector.value
        let data = try JSONSerialization.data(withJSONObject: ["words": words])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    }
}
