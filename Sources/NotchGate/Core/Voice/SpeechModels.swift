import Foundation

/// A speech-to-text model Notch Voice can listen with: Apple's, built into macOS, or a
/// free open-source one downloaded once from Hugging Face. Every one of them runs on
/// this Mac, with no account or API key, and audio never leaves it.
///
/// To offer another model, add it to `catalog` with its files pinned to a commit (so the
/// checksums never go stale) and give its engine a `DictationSession`.
struct SpeechModel: Identifiable, Equatable, Sendable {
    enum Engine: Equatable, Sendable {
        /// Apple's on-device recognizer (see `SpeechRecognizerProvider`).
        case apple
        /// Underdog Bark: a Core ML encoder on the Neural Engine, the decoder on the CPU (see `BarkTranscriber`).
        case bark
        /// A model for Cactus's needle engine (Whistle, and Shruti built on it), from its model file (see `NeedleEngine`).
        case needle(weights: String)
    }

    /// One file to download, checked against its published size and SHA-256.
    struct File: Equatable, Sendable {
        /// Where it goes in the model's folder.
        let path: String
        let url: URL
        let size: Int64
        let sha256: String
    }

    let id: String
    let name: String
    let maker: String
    /// A few words on why you'd pick it, for the settings.
    let summary: String
    /// Who it suits, shown when the pointer rests on its row.
    let whyPick: String
    /// More about it (and the credit its license asks for), for the settings' ⓘ.
    let about: String
    /// What the model understands, for the settings.
    let languageSummary: String
    /// The language choices it offers, by code; empty when there's nothing to choose.
    /// An empty code means "work it out" (the Mac's English for Apple, detection for others).
    let languages: [(id: String, title: String)]
    let license: String
    let page: URL
    let engine: Engine
    let files: [File]

    var isBuiltIn: Bool { files.isEmpty }
    var downloadSize: Int64 { files.reduce(0) { $0 + $1.size } }

    static func == (lhs: SpeechModel, rhs: SpeechModel) -> Bool { lhs.id == rhs.id }

    /// Why this Mac can't run the model, if it can't.
    var unsupportedReason: String? {
        switch engine {
        case .apple:
            return nil
        case .bark:
            guard Self.isAppleSilicon else { return "Needs a Mac with Apple silicon." }
            let sequoia = OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
            return ProcessInfo.processInfo.isOperatingSystemAtLeast(sequoia) ? nil : "Needs macOS 15 or later."
        case .needle:
            return Self.isAppleSilicon ? nil : "Needs a Mac with Apple silicon."
        }
    }

    private static var isAppleSilicon: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }
}

// MARK: Catalog

extension SpeechModel {
    static let appleID = "apple"

    /// Every model on offer: Apple's, then the downloads from smallest to largest.
    static let catalog: [SpeechModel] = [apple, whistle, shruti, underdogBark]

    static func withID(_ id: String) -> SpeechModel? {
        catalog.first { $0.id == id }
    }

    static let apple = SpeechModel(
        id: appleID,
        name: "Apple",
        maker: "Apple",
        summary: "Built into macOS",
        whyPick: "**Pick Apple** to start right away: there's nothing to download, and you can match it to your English accent (US, UK, India and more) under **Language**.",
        about: "Apple's on-device speech recognition, built into macOS. Pick the English that matches your accent under **Language**: it's the biggest accuracy win.",
        languageSummary: "English, 9 accents",
        languages: VoiceLanguage.options,
        license: "Part of macOS",
        page: URL(string: "https://developer.apple.com/documentation/speech")!,
        engine: .apple,
        files: []
    )

    /// 4.94 % average word error on the Open ASR Leaderboard's English sets, from a 0.6B
    /// Parakeet TDT post-trained and compressed by Conway Research. NotchGate downloads its
    /// Neural Engine package: the encoder as Core ML, the small decoder and vocabulary beside it.
    static let underdogBark = SpeechModel(
        id: "underdog-bark-3.0",
        name: "Underdog Bark 3.0",
        maker: "Conway Research",
        summary: "Most accurate",
        whyPick: "**Pick Underdog Bark** for the most accurate English here, names and technical words included. Worth its 202 MB download if you dictate a lot in English.",
        about: "**Underdog Bark 3.0** by Conway Research: a 0.6B English model, post-trained from NVIDIA's Parakeet TDT 0.6B v3, that averages 4.94 % word error on the Open ASR Leaderboard's English sets. It runs on the Neural Engine; the first load after downloading takes a few minutes while macOS optimizes it.\n\nFree and open source (CC-BY-4.0), downloaded once from Hugging Face. Needs Apple silicon and macOS 15 or later.",
        languageSummary: "English",
        languages: [],
        license: "CC-BY-4.0, based on NVIDIA Parakeet",
        page: URL(string: "https://huggingface.co/ConwayResearch/Underdog-Bark-3.0")!,
        engine: .bark,
        files: [
            barkFile("BarkEncoder.mlpackage/Manifest.json", size: 617,
                     sha256: "d37c121561b99da49b9bf1e28c00152c14c56a943815fa83008ee0691b8f1149"),
            barkFile("BarkEncoder.mlpackage/Data/com.apple.CoreML/model.mlmodel", size: 1_784_701,
                     sha256: "7c3f1c1612ba21bcc4d8efff1b32154b39cb3e1e2f10020117793acc5c96fcdf"),
            barkFile("BarkEncoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin", size: 189_133_632,
                     sha256: "98979e5dd731486ddfb2c312f80a3038205c058aac9fe0f403ba26e1a158d385"),
            barkFile("decoder.npz", size: 11_168_286,
                     sha256: "1ce79071f54c3dcec9aa9bb1d488486766f1fdbb3fd988b776da3f4da8024665"),
            barkFile("vocab.json", size: 115_878,
                     sha256: "eee86951e9f74921342fdc60ba26711eb70f7188e8784d98d2aecfc525b72270"),
        ]
    )

    /// A 16.9 MB model in seven languages from Cactus Compute. It runs on Cactus's needle
    /// engine, which comes as a Python wheel: NotchGate takes the engine library out of it.
    static let whistle = SpeechModel(
        id: "whistle",
        name: "Whistle",
        maker: "Cactus Compute",
        summary: "Tiny and fast",
        whyPick: "**Pick Whistle** if you speak German, French, Spanish, Italian, Dutch or Polish, or want the smallest download (17 MB).",
        about: "**Whistle** by Cactus Compute: a 16.9 MB model for English, German, French, Spanish, Italian, Dutch and Polish that detects the language by itself. It runs on the CPU with Cactus's needle engine, which downloads with it.\n\nFree and open source (Apache 2.0), downloaded once from Hugging Face. Needs Apple silicon.",
        languageSummary: "7 languages",
        languages: [
            ("", "Detect automatically"),
            ("en", "English"),
            ("de", "German"),
            ("fr", "French"),
            ("es", "Spanish"),
            ("it", "Italian"),
            ("nl", "Dutch"),
            ("pl", "Polish"),
        ],
        license: "Apache 2.0",
        page: URL(string: "https://huggingface.co/Cactus-Compute/whistle")!,
        engine: .needle(weights: "whistle.cact"),
        files: [
            huggingFace("Cactus-Compute/whistle", revision: "741118687e1f008f06d1351a402a731274789790",
                        "whistle.cact", to: "whistle.cact", size: 16_919_407,
                        sha256: "b6e02f048568ac5d01a2042556c658061e699acbc0aa2a1439f52f3d461dffeb"),
            needleEngine,
        ]
    )

    /// Whistle retrained by Udgam Labs on 2,732 hours of Indian speech, with Devanagari added:
    /// Hindi comes out in Devanagari and English words stay in Latin letters, as people type
    /// Hinglish. Same needle engine as Whistle.
    static let shruti = SpeechModel(
        id: "shruti",
        name: "Shruti",
        maker: "Udgam Labs",
        summary: "Hinglish",
        whyPick: "**Pick Shruti** if you speak Hindi or mix Hindi and English (Hinglish): Hindi is written in Devanagari and English words stay in English, like “मेरा order कब आएगा”. Just 30 MB.",
        about: "**Shruti** by Udgam Labs: Cactus Whistle retrained on 2,732 hours of Indian speech, for Hindi, English and Hinglish (5.95 % word error on LibriSpeech English, 35 % on Hinglish lectures). English words come out in lowercase. It runs on the CPU with Cactus's needle engine, which downloads with it.\n\nFree and open source (Apache 2.0, a modified version of Cactus Whistle), downloaded once from Hugging Face. Needs Apple silicon.",
        languageSummary: "Hindi, English",
        languages: [
            ("", "Detect automatically"),
            ("hi", "Hindi or Hinglish"),
            ("en", "English only"),
        ],
        license: "Apache 2.0, based on Cactus Whistle",
        page: URL(string: "https://huggingface.co/udgamlabs/Shruti")!,
        engine: .needle(weights: "shruti.cact"),
        files: [
            huggingFace("udgamlabs/Shruti", revision: "ebf52e614065ce20e56affdab641f749a04511a5",
                        "shruti.cact", to: "shruti.cact", size: 29_546_527,
                        sha256: "b189e954aaed4a9fd41acbad3ac05e486381e96325b22a4c695b9ea5153d7065"),
            needleEngine,
        ]
    )

    /// Cactus's needle engine for Apple silicon, as their Python wheel ships it (see `NeedleEngine`).
    private static let needleEngine = huggingFace(
        "Cactus-Compute/needle3", revision: "d6c7d6a2e9655505e0f8e23339356dd1705900eb",
        "python/cactus_needle-3.3.3-py3-none-macosx_11_0_arm64.whl", to: "engine.whl", size: 544_605,
        sha256: "c5538e045fb26f0b6f911102516582d4434fbfa38aa28e5c2f3eb990b92aaf8d"
    )

    private static func barkFile(_ path: String, size: Int64, sha256: String) -> File {
        huggingFace("ConwayResearch/Underdog-Bark-3.0", revision: "85db2ad18ab41e534a222ee253c29191d77ed919",
                    "coreml/ane/\(path)", to: path, size: size, sha256: sha256)
    }

    private static func huggingFace(
        _ repo: String, revision: String, _ remotePath: String, to path: String, size: Int64, sha256: String
    ) -> File {
        File(
            path: path,
            url: URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(remotePath)")!,
            size: size,
            sha256: sha256
        )
    }
}
