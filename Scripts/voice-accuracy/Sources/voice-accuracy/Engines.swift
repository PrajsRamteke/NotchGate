import AVFoundation
import Speech

/// The on-device recognizers Notch Voice could use. None of them send audio off the Mac.
enum Engine: String, CaseIterable {
    /// macOS 26+ general-purpose model (SpeechAnalyzer + SpeechTranscriber).
    case speechTranscriber = "Apple SpeechTranscriber"
    /// macOS 26+ dictation-tuned model (SpeechAnalyzer + DictationTranscriber).
    case dictationTranscriber = "Apple DictationTranscriber"
    /// The older recognizer, all macOS 14–15 users would get (SFSpeechRecognizer, on-device only).
    /// Unlike the two above, it needs Speech Recognition permission, so it runs only with --legacy.
    case legacy = "Apple SFSpeechRecognizer"

    func transcribe(_ url: URL, locale: Locale, vocabulary: [String]) async throws -> String {
        switch self {
        case .speechTranscriber:
            let module = SpeechTranscriber(locale: locale, preset: .transcription)
            try await Self.installAssets(for: module, locale: locale)
            let analyzer = SpeechAnalyzer(modules: [module])
            let collect = Task {
                try await module.results.reduce(into: [String]()) { parts, result in
                    if result.isFinal { parts.append(String(result.text.characters)) }
                }
            }
            try await Self.analyze(url, with: analyzer, vocabulary: vocabulary)
            return Self.join(try await collect.value)
        case .dictationTranscriber:
            // The short presets only ever report volatile results for a whole file.
            let module = DictationTranscriber(locale: locale, preset: .longDictation)
            try await Self.installAssets(for: module, locale: locale)
            let analyzer = SpeechAnalyzer(modules: [module])
            let collect = Task {
                try await module.results.reduce(into: [String]()) { parts, result in
                    if result.isFinal { parts.append(String(result.text.characters)) }
                }
            }
            try await Self.analyze(url, with: analyzer, vocabulary: vocabulary)
            return Self.join(try await collect.value)
        case .legacy:
            return try await Self.legacyTranscribe(url, locale: locale, vocabulary: vocabulary)
        }
    }

    /// Which engines can run here, and the locale each will use, or why one can't.
    static func availability(for requested: Locale, includeLegacy: Bool) async -> [(Engine, Result<Locale, ToolError>)] {
        var out: [(Engine, Result<Locale, ToolError>)] = []

        if !SpeechTranscriber.isAvailable {
            out.append((.speechTranscriber, .failure(ToolError("not supported on this Mac"))))
        } else if let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) {
            out.append((.speechTranscriber, .success(locale)))
        } else {
            out.append((.speechTranscriber, .failure(ToolError("no model for \(requested.identifier)"))))
        }

        if let locale = await DictationTranscriber.supportedLocale(equivalentTo: requested) {
            out.append((.dictationTranscriber, .success(locale)))
        } else {
            out.append((.dictationTranscriber, .failure(ToolError("no model for \(requested.identifier)"))))
        }

        if !includeLegacy {
            return out
        } else if let recognizer = SFSpeechRecognizer(locale: requested), recognizer.supportsOnDeviceRecognition {
            out.append((.legacy, .success(recognizer.locale)))
        } else {
            out.append((.legacy, .failure(ToolError("no on-device model for \(requested.identifier)"))))
        }
        return out
    }

    // MARK: SpeechAnalyzer

    private static var installedModels: Set<String> = []

    /// Downloads Apple's speech model for the locale the first time (once per Mac).
    private static func installAssets(for module: any SpeechModule, locale: Locale) async throws {
        let key = "\(type(of: module))-\(locale.identifier)"
        guard !installedModels.contains(key) else { return }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            print("  Downloading Apple's \(locale.identifier) speech model (one time)…")
            try await request.downloadAndInstall()
        }
        installedModels.insert(key)
    }

    private static func analyze(_ url: URL, with analyzer: SpeechAnalyzer, vocabulary: [String]) async throws {
        if !vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = vocabulary
            try await analyzer.setContext(context)
        }
        let audio = try AVAudioFile(forReading: url)
        if let end = try await analyzer.analyzeSequence(from: audio) {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            await analyzer.cancelAndFinishNow()
        }
    }

    private static func join(_ parts: [String]) -> String {
        parts.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: SFSpeechRecognizer

    private static func legacyTranscribe(_ url: URL, locale: Locale, vocabulary: [String]) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw ToolError("SFSpeechRecognizer has no model for \(locale.identifier)")
        }
        recognizer.queue = OperationQueue()
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.contextualStrings = vocabulary

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !resumed else { return }
                if let result, result.isFinal {
                    resumed = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if let error {
                    resumed = true
                    // "No speech detected" is a result, not a failure.
                    if (error as NSError).code == 1110 {
                        continuation.resume(returning: "")
                    } else {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}
