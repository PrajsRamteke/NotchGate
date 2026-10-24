import AVFoundation
import Foundation
import Speech

// voice-accuracy: measure how well Apple's on-device speech recognition hears *your*
// voice, before building Notch Voice. Everything runs locally; no account, no network
// (apart from Apple's one-time model download).
//
//   swift run voice-accuracy record     read the sentences aloud, one clip each
//   swift run voice-accuracy test       transcribe every clip and score each engine
//
// Options: --sentences FILE  --clips DIR  --locale en-US  --vocab FILE  --compare FILE  --legacy

Disclaim.relaunchIfNeeded()

let usage = """
Usage:
  swift run voice-accuracy record [--sentences sentences.txt] [--clips clips]
  swift run voice-accuracy test   [--clips clips] [--locale en-US] [--vocab vocabulary.txt]
                                  [--compare wispr.txt] [--legacy]

record   Shows each sentence; press Enter to start and again to stop. Clips you've
         already recorded are skipped, so you can stop and carry on later.
test     Transcribes every clip with each on-device Apple engine and prints the
         word accuracy of each. --compare scores another tool's output too: one line
         per sentence, in the same order (e.g. what Wispr Flow typed for each one).
         --legacy adds the older macOS 14–15 recognizer (asks for Speech Recognition
         permission).
"""

// MARK: Arguments

let command = CommandLine.arguments.dropFirst().first ?? ""
let arguments = Array(CommandLine.arguments.dropFirst(2))

func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: "--\(name)"), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

let sentencesPath = option("sentences") ?? "sentences.txt"
let clipsDir = URL(fileURLWithPath: option("clips") ?? "clips", isDirectory: true)

func lines(of path: String) throws -> [String] {
    try String(contentsOfFile: path, encoding: .utf8)
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("✗ \(message)\n".utf8))
    exit(1)
}

func percent(_ value: Double) -> String { String(format: "%5.1f%%", value * 100) }

// MARK: record

func record() async {
    guard await AVCaptureDevice.requestAccess(for: .audio) else {
        fail("Microphone access is off. Allow voice-accuracy in System Settings → Privacy & Security → Microphone, then run this again.")
    }
    let sentences: [String]
    do { sentences = try lines(of: sentencesPath).filter { !$0.isEmpty } } catch { fail("Can't read \(sentencesPath): \(error.localizedDescription)") }
    guard !sentences.isEmpty else { fail("\(sentencesPath) has no sentences.") }
    try? FileManager.default.createDirectory(at: clipsDir, withIntermediateDirectories: true)

    print("Read each sentence the way you'd normally dictate it. Your clips stay in \(clipsDir.path).\n")
    let recorder = Recorder()

    for (index, sentence) in sentences.enumerated() {
        let name = String(format: "%02d", index + 1)
        let audioURL = clipsDir.appendingPathComponent("\(name).caf")
        let textURL = clipsDir.appendingPathComponent("\(name).txt")
        // A clip counts only once kept: audio and its sentence are saved together.
        if FileManager.default.fileExists(atPath: audioURL.path), FileManager.default.fileExists(atPath: textURL.path) {
            print("[\(name)/\(sentences.count)] already recorded (delete \(audioURL.lastPathComponent) to redo)")
            continue
        }

        // Each take goes to a scratch file and replaces the clip only when you keep it.
        let takeURL = clipsDir.appendingPathComponent("\(name).take.caf")
        defer { try? FileManager.default.removeItem(at: takeURL) }

        print("[\(name)/\(sentences.count)] Read this aloud:\n\n    “\(sentence)”\n")
        while true {
            print("  Enter = start recording · s = skip · q = quit: ", terminator: "")
            let choice = readLine()?.lowercased()
            if choice == nil || choice == "q" { print("\nStopped. Run record again to carry on."); return }
            if choice == "s" { print(); break }

            do { try recorder.start(to: takeURL) } catch { fail("Couldn't start recording: \(error)") }
            print("  ● Recording… press Enter when you've finished.", terminator: "")
            _ = readLine()
            let seconds = recorder.stop()
            if seconds < 0.5 {
                print("  That was too short (\(String(format: "%.1f", seconds)) s). Try again.")
                continue
            }
            print("  Recorded \(String(format: "%.1f", seconds)) s. Enter = keep · r = redo: ", terminator: "")
            if readLine()?.lowercased() == "r" { continue }
            do {
                _ = try? FileManager.default.removeItem(at: audioURL)
                try FileManager.default.moveItem(at: takeURL, to: audioURL)
                try sentence.write(to: textURL, atomically: true, encoding: .utf8)
            } catch { fail("Couldn't save \(audioURL.path): \(error)") }
            print("  ✓ Kept.\n")
            break
        }
    }
    print("Done. Next: swift run voice-accuracy test")
}

// MARK: test

struct Clip {
    let number: Int
    let audio: URL
    let reference: String
}

func loadClips() -> [Clip] {
    let files = (try? FileManager.default.contentsOfDirectory(at: clipsDir, includingPropertiesForKeys: nil)) ?? []
    return files
        .filter { $0.pathExtension == "caf" }
        .compactMap { audio -> Clip? in
            let name = audio.deletingPathExtension().lastPathComponent
            guard let number = Int(name),
                  let reference = try? String(contentsOf: audio.deletingPathExtension().appendingPathExtension("txt"), encoding: .utf8)
            else { return nil }
            return Clip(number: number, audio: audio, reference: reference.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        .sorted { $0.number < $1.number }
}

func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
    await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
    }
}

func csvField(_ text: String) -> String { "\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\"" }

func test() async {
    let clips = loadClips()
    guard !clips.isEmpty else { fail("No recordings in \(clipsDir.path). Run: swift run voice-accuracy record") }

    let requested = option("locale").map { Locale(identifier: $0) } ?? Locale.current
    let vocabulary: [String]
    if let path = option("vocab") {
        do { vocabulary = try lines(of: path).filter { !$0.isEmpty } } catch { fail("Can't read \(path): \(error.localizedDescription)") }
    } else {
        vocabulary = []
    }
    var compared: [Int: String] = [:]
    if let path = option("compare") {
        do {
            for (index, line) in try lines(of: path).enumerated() where !line.isEmpty { compared[index + 1] = line }
        } catch { fail("Can't read \(path): \(error.localizedDescription)") }
    }

    let includeLegacy = arguments.contains("--legacy")
    if includeLegacy, await requestSpeechAuthorization() != .authorized {
        print("! Speech Recognition access is off, so \(Engine.legacy.rawValue) will fail.")
        print("  Allow voice-accuracy in System Settings → Privacy & Security → Speech Recognition.\n")
    }

    print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    print("Locale requested: \(requested.identifier)")
    if !vocabulary.isEmpty { print("Custom vocabulary: \(vocabulary.count) phrases") }
    var engines: [(Engine, Locale)] = []
    for (engine, availability) in await Engine.availability(for: requested, includeLegacy: includeLegacy) {
        switch availability {
        case .success(let locale):
            engines.append((engine, locale))
            print("  ✓ \(engine.rawValue) (\(locale.identifier))")
        case .failure(let reason):
            print("  – \(engine.rawValue): skipped, \(reason)")
        }
    }
    guard !engines.isEmpty else { fail("No on-device engine supports \(requested.identifier). Try --locale en-US.") }
    print("\nTranscribing \(clips.count) clips…\n")

    let comparedName = "Your --compare file"
    var totals: [String: WordScore] = [:]
    var seconds: [String: Double] = [:]
    var csv = ["clip,engine,accuracy,errors,reference_words,seconds,reference,heard"]

    for clip in clips {
        print("[\(String(format: "%02d", clip.number))] \(clip.reference)")
        var rows: [(name: String, text: String, time: Double?)] = []
        for (engine, locale) in engines {
            let start = Date()
            do {
                let text = try await engine.transcribe(clip.audio, locale: locale, vocabulary: vocabulary)
                rows.append((engine.rawValue, text, Date().timeIntervalSince(start)))
            } catch {
                print("     \(engine.rawValue): failed, \(error)")
            }
        }
        if let text = compared[clip.number] { rows.append((comparedName, text, nil)) }

        for row in rows {
            let score = WordErrorRate.score(reference: clip.reference, hypothesis: row.text)
            totals[row.name] = (totals[row.name] ?? WordScore(referenceWords: 0, errors: 0)) + score
            if let time = row.time { seconds[row.name, default: 0] += time }
            let mark = score.errors == 0 ? "✓" : "✗"
            print("   \(mark) \(percent(score.accuracy))  \(row.name.padding(toLength: 28, withPad: " ", startingAt: 0))  \(row.text)")
            csv.append([
                String(clip.number), csvField(row.name), String(format: "%.4f", score.accuracy), String(score.errors),
                String(score.referenceWords), row.time.map { String(format: "%.2f", $0) } ?? "",
                csvField(clip.reference), csvField(row.text),
            ].joined(separator: ","))
        }
        print()
    }

    print("Word accuracy over \(clips.count) clips (higher is better)")
    print("  Engine                        Accuracy   Errors / words   Avg time per clip")
    let names = engines.map(\.0.rawValue) + (compared.isEmpty ? [] : [comparedName])
    for name in names.sorted(by: { (totals[$0]?.accuracy ?? 0) > (totals[$1]?.accuracy ?? 0) }) {
        guard let total = totals[name] else { continue }
        let time = seconds[name].map { String(format: "%.2f s", $0 / Double(clips.count)) } ?? "–"
        let counts = "\(total.errors) / \(total.referenceWords)"
        print("  \(name.padding(toLength: 28, withPad: " ", startingAt: 0))  \(percent(total.accuracy))   \(counts.padding(toLength: 15, withPad: " ", startingAt: 0))  \(time)")
    }
    if !compared.isEmpty, compared.count < clips.count {
        print("  (your --compare file covers \(compared.count) of \(clips.count) clips; its score uses only those)")
    }

    let csvURL = URL(fileURLWithPath: "results.csv")
    try? (csv.joined(separator: "\n") + "\n").write(to: csvURL, atomically: true, encoding: .utf8)
    print("\nEvery transcript is in \(csvURL.path).")
}

// MARK: Run

switch command {
case "record": await record()
case "test": await test()
default:
    print(usage)
    exit(command.isEmpty || command == "help" || command == "--help" ? 0 : 1)
}
