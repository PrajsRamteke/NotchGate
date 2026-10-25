import Compression
import Foundation
import Testing
@testable import NotchGate

@Suite("Speech model catalog")
struct SpeechModelCatalogTests {
    @Test func applesIsBuiltInAndTheRestGoSmallestFirst() {
        #expect(SpeechModel.catalog.first == .apple)
        #expect(SpeechModel.catalog.map(\.id) == ["apple", "whistle", "shruti", "underdog-bark-3.0"])
        let sizes = SpeechModel.catalog.map(\.downloadSize)
        #expect(sizes == sizes.sorted())
        #expect(SpeechModel.apple.isBuiltIn)
        #expect(Set(SpeechModel.catalog.map(\.id)).count == SpeechModel.catalog.count)
        #expect(SpeechModel.withID("underdog-bark-3.0") == .underdogBark)
        #expect(SpeechModel.withID("nope") == nil)
    }

    @Test func everyDownloadIsPinnedToACommitAndChecksummed() {
        for model in SpeechModel.catalog where !model.isBuiltIn {
            for file in model.files {
                #expect(file.url.scheme == "https")
                #expect(file.url.host == "huggingface.co")
                // resolve/<40-hex commit>/…, so the checksums can't go stale.
                #expect(file.url.path.contains(/\/resolve\/[0-9a-f]{40}\//))
                #expect(file.sha256.wholeMatch(of: /[0-9a-f]{64}/) != nil)
                #expect(file.size > 0)
            }
            #expect(Set(model.files.map(\.path)).count == model.files.count)
        }
    }

    @Test func downloadSizesMatchTheModelCards() {
        // The Neural Engine package: encoder, decoder and vocabulary.
        #expect((200_000_000...205_000_000).contains(SpeechModel.underdogBark.downloadSize))
        // whistle.cact (16.9 MB) plus the engine wheel.
        #expect((17_000_000...18_000_000).contains(SpeechModel.whistle.downloadSize))
        // shruti.cact (29.5 MB) plus the same engine wheel.
        #expect((30_000_000...30_200_000).contains(SpeechModel.shruti.downloadSize))
        #expect(SpeechModel.shruti.files.last == SpeechModel.whistle.files.last)
    }

    @Test func eachModelOffersItsOwnLanguages() {
        #expect(SpeechModel.underdogBark.languages.isEmpty)
        #expect(SpeechModel.whistle.languages.map(\.id) == ["", "en", "de", "fr", "es", "it", "nl", "pl"])
        #expect(SpeechModel.shruti.languages.map(\.id) == ["", "hi", "en"])
        #expect(SpeechModel.apple.languages.map(\.id) == VoiceLanguage.options.map(\.id))
    }
}

@Suite("Speech model choice")
@MainActor
struct SpeechModelChoiceTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "voice-models-\(UUID())") ?? .standard
    }

    private func makeFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("speech-models-\(UUID())", isDirectory: true)
    }

    /// Files of the published sizes (sparse, so nothing is really written).
    private func fakeDownload(_ model: SpeechModel, in store: SpeechModelStore, skipping prefix: String? = nil) throws {
        for file in model.files where prefix.map({ !file.path.hasPrefix($0) }) ?? true {
            let url = store.folder(for: model).appendingPathComponent(file.path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: UInt64(file.size))
            try handle.close()
        }
        store.refresh()
    }

    @Test func appleIsTheDefaultAndChoicesAreRemembered() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.voiceModel == SpeechModel.appleID)
        #expect(settings.voiceModelLanguages.isEmpty)
        settings.voiceModel = SpeechModel.whistle.id
        settings.voiceModelLanguages[SpeechModel.whistle.id] = "de"
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.voiceModel == "whistle")
        #expect(reloaded.voiceModelLanguages == ["whistle": "de"])
    }

    @Test func applesTypesUntilTheChosenModelIsDownloaded() throws {
        let store = SpeechModelStore(folder: makeFolder())
        defer { try? FileManager.default.removeItem(at: store.folder) }
        let settings = AppSettings(defaults: makeDefaults())
        let voice = VoiceDictation(settings: settings, models: store)
        settings.voiceModel = SpeechModel.underdogBark.id
        #expect(store.state(of: .underdogBark) == .notDownloaded)
        #expect(voice.speechModel == .apple)

        try fakeDownload(.underdogBark, in: store)
        #expect(store.state(of: .underdogBark) == .downloaded)
        let expected: SpeechModel = SpeechModel.underdogBark.unsupportedReason == nil ? .underdogBark : .apple
        #expect(voice.speechModel == expected)
    }

    @Test func aCompiledPackageCountsAsDownloaded() throws {
        let store = SpeechModelStore(folder: makeFolder())
        defer { try? FileManager.default.removeItem(at: store.folder) }
        try fakeDownload(.underdogBark, in: store, skipping: "BarkEncoder.mlpackage/")
        #expect(store.state(of: .underdogBark) == .notDownloaded)
        // Loading compiles the package and deletes it: the compiled copy stands in.
        try FileManager.default.createDirectory(
            at: store.folder(for: .underdogBark).appendingPathComponent("BarkEncoder.mlmodelc"), withIntermediateDirectories: true
        )
        store.refresh()
        #expect(store.state(of: .underdogBark) == .downloaded)
    }

    @Test func aWrongSizeIsNotADownload() throws {
        let store = SpeechModelStore(folder: makeFolder())
        defer { try? FileManager.default.removeItem(at: store.folder) }
        try fakeDownload(.whistle, in: store)
        #expect(store.isDownloaded(.whistle))
        let weights = store.folder(for: .whistle).appendingPathComponent("whistle.cact")
        let handle = try FileHandle(forWritingTo: weights)
        try handle.truncate(atOffset: 10)
        try handle.close()
        store.refresh()
        #expect(!store.isDownloaded(.whistle))
    }

    @Test func removingTheModelInUseSwitchesBackToApple() throws {
        let store = SpeechModelStore(folder: makeFolder())
        defer { try? FileManager.default.removeItem(at: store.folder) }
        let settings = AppSettings(defaults: makeDefaults())
        let voice = VoiceDictation(settings: settings, models: store)
        try fakeDownload(.whistle, in: store)
        voice.selectModel(.whistle)
        if SpeechModel.whistle.unsupportedReason == nil {
            #expect(settings.voiceModel == "whistle")
        }
        voice.removeModel(.whistle)
        #expect(settings.voiceModel == SpeechModel.appleID)
        #expect(!FileManager.default.fileExists(atPath: store.folder(for: .whistle).path))
        #expect(store.state(of: .whistle) == .notDownloaded)
    }

    @Test func eachModelKeepsItsOwnLanguage() {
        let settings = AppSettings(defaults: makeDefaults())
        let voice = VoiceDictation(settings: settings, models: SpeechModelStore(folder: makeFolder()))
        voice.setLanguage("en-GB", for: .apple)
        voice.setLanguage("fr", for: .whistle)
        #expect(voice.language(for: .apple) == "en-GB")
        #expect(voice.language(for: .whistle) == "fr")
        voice.setLanguage("", for: .whistle)
        #expect(voice.language(for: .whistle) == "")
        #expect(settings.voiceModelLanguages.isEmpty)
    }

    @Test func aModelThatCantBeChosenIsNotSelected() {
        let settings = AppSettings(defaults: makeDefaults())
        let voice = VoiceDictation(settings: settings, models: SpeechModelStore(folder: makeFolder()))
        voice.selectModel(.underdogBark)
        #expect(settings.voiceModel == SpeechModel.appleID)
    }

    @Test func checksumsAreSHA256() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sha-\(UUID())")
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try await SpeechModelStore.sha256(of: url) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

@Suite("Downloaded model plumbing")
struct DownloadedModelPlumbingTests {
    @Test func readsStoredAndDeflatedNumpyArrays() throws {
        let floats = try Self.npy(dtype: "<f4", shape: "(2, 2)", values: [1, -2.5, 3, 0.125] as [Float])
        let halves = try Self.npy(dtype: "<f2", shape: "(2,)", values: [UInt16(0x3C00), 0xC000])  // 1, -2
        let quantized = try Self.npy(dtype: "|i1", shape: "(2, 3)", values: [Int8(1), 2, 3, -1, -2, -3])
        let archive = try NumpyArchive(data: Self.zip([
            ("plain.npy", floats, false),
            ("weight.q.npy", quantized, true),
            ("weight.s.npy", halves, true),
        ]))
        #expect(try archive.floats("plain") == [1, -2.5, 3, 0.125])
        #expect(try archive.array("plain").shape == [2, 2])
        #expect(try archive.floats("weight.s") == [1, -2])
        // int8 rows times their scale.
        #expect(try archive.dequantized("weight") == [1, 2, 3, 2, 4, 6])
        #expect(throws: ZipArchive.ReadError.self) { try archive.floats("missing") }
    }

    @Test func notAZipIsAnError() {
        #expect(throws: ZipArchive.ReadError.self) { try ZipArchive(data: Data("hello".utf8)) }
    }

    @Test func barkPiecesAreDetokenized() {
        let vocabulary = BarkVocabulary(
            pieces: ["<unk>", "▁Hello", ",", "▁wor", "ld", "<pad>"], specialIds: [0, 5, 6], blankId: 6, vocabSize: 7,
            durations: [0, 1, 2, 3, 4], maxSymbolsPerStep: 10
        )
        #expect(vocabulary.text([1, 2, 3, 4]) == "Hello, world")
        #expect(vocabulary.text([0, 1, 5, 9]) == "Hello")
        #expect(vocabulary.text([]) == "")
    }

    @Test func theEncoderShrinksFramesEightfold() {
        #expect(BarkTranscriber.encodedLength(1500) == 188)
        #expect(BarkTranscriber.encodedLength(25) == 4)
        #expect(BarkTranscriber.maxPiece == 236_000)
    }

    @Test func featuresAreNormalizedPerBandAndZeroPastTheAudio() throws {
        let filters: [Float] = (0..<(BarkFrontend.mels * BarkFrontend.bins)).map { index in
            Float((index * 7919) % 101) / 100 + 0.01
        }
        let frontend = try BarkFrontend(melFilters: filters)
        let audio: [Float] = (0..<16_000).map { sample in
            let time = Double(sample)
            let carrier = sin(time * 0.07) * 0.3
            let wobble = sin(time * 0.31) * 0.1 * Double(sample % 400) / 400
            return Float(carrier + wobble)
        }
        let features = frontend.features(audio)
        #expect(features.frames == 101)
        #expect(features.valid == 100)
        #expect(features.values.count == 101 * BarkFrontend.mels)
        #expect(features.values.suffix(BarkFrontend.mels).allSatisfy { $0 == 0 })
        for mel in [0, 40, 127] {
            let band: [Double] = (0..<features.valid).map { frame in Double(features.values[frame * BarkFrontend.mels + mel]) }
            let mean = band.reduce(0, +) / Double(band.count)
            let squares: Double = band.map { value in (value - mean) * (value - mean) }.reduce(0, +)
            let variance = squares / Double(band.count - 1)
            #expect(abs(mean) < 1e-3)
            #expect(abs(variance - 1) < 1e-2)
        }
    }

    @Test func longAudioIsCutInsideAPause() {
        // 20 s of tone with a silent stretch from 9.0 s to 9.4 s.
        var audio = (0..<(20 * 16_000)).map { Float(sin(Double($0) * 0.05) * 0.5) }
        for index in (9 * 16_000)..<(9 * 16_000 + 6_400) { audio[index] = 0 }
        let cut = BarkSegmenter.cut(audio, from: 0)
        #expect(cut.map { (9 * 16_000)...(9 * 16_000 + 6_400) ~= $0 } == true)
        // What's left fits one piece.
        #expect(cut.flatMap { BarkSegmenter.cut(audio, from: $0) } == nil)
    }

    @Test func shortAudioIsOnePieceAndLiveCutsWaitForTheSmoothing() {
        let fits = [Float](repeating: 0.1, count: BarkTranscriber.maxPiece)
        #expect(BarkSegmenter.cut(fits, from: 0) == nil)
        let justOver = [Float](repeating: 0.1, count: BarkTranscriber.maxPiece + 800)
        #expect(BarkSegmenter.cut(justOver, from: 0) != nil)
        #expect(BarkSegmenter.cut(justOver, from: 0, isFinal: false) == nil)
    }

    @Test func readsTheNeedleEnginesReply() throws {
        let reply = #"{"text":" turn off the kitchen lights ","language":"en","ttft_ms":12.5,"decode_tps":310.0}"#
        #expect(try NeedleEngine.text(fromReply: reply) == "turn off the kitchen lights")
        #expect(try NeedleEngine.text(fromReply: #"{"text":"मेरा order कब आएगा","language":"hi"}"#) == "मेरा order कब आएगा")
        #expect(try NeedleEngine.text(fromReply: #"{"text":"","language":""}"#) == "")
        #expect(throws: VoiceError.self) { try NeedleEngine.text(fromReply: "loaded in 3 ms") }
    }

    @Test func everyModelSaysWhoItSuits() {
        for model in SpeechModel.catalog {
            #expect(model.whyPick.hasPrefix("**Pick "))
        }
    }

    @Test func piecesJoinWithSingleSpaces() {
        #expect(RecordedAudio.joined(["Hello there.", "", "  How are you? "]) == "Hello there. How are you?")
    }

    // MARK: Fixtures

    private static func npy<T>(dtype: String, shape: String, values: [T]) throws -> Data {
        var header = "{'descr': '\(dtype)', 'fortran_order': False, 'shape': \(shape), }"
        while (10 + header.utf8.count + 1) % 64 != 0 { header += " " }
        header += "\n"
        var data = Data([0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59, 1, 0])
        withUnsafeBytes(of: UInt16(header.utf8.count).littleEndian) { data.append(contentsOf: $0) }
        data.append(Data(header.utf8))
        values.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }

    /// A minimal zip: each member stored or raw-deflated (CRCs are left zero; the reader doesn't check them).
    private static func zip(_ members: [(name: String, data: Data, deflate: Bool)]) throws -> Data {
        var archive = Data()
        var directory = Data()
        func append16(_ value: Int, to data: inout Data) { withUnsafeBytes(of: UInt16(value).littleEndian) { data.append(contentsOf: $0) } }
        func append32(_ value: Int, to data: inout Data) { withUnsafeBytes(of: UInt32(value).littleEndian) { data.append(contentsOf: $0) } }
        for member in members {
            var body = member.data
            if member.deflate {
                var output = [UInt8](repeating: 0, count: member.data.count + 1024)
                let written = member.data.withUnsafeBytes { source in
                    compression_encode_buffer(&output, output.count, source.bindMemory(to: UInt8.self).baseAddress!, member.data.count, nil, COMPRESSION_ZLIB)
                }
                body = Data(output.prefix(written))
            }
            let offset = archive.count
            let name = Data(member.name.utf8)
            append32(0x0403_4B50, to: &archive)
            for value in [20, 0, member.deflate ? 8 : 0, 0, 0] { append16(value, to: &archive) }
            append32(0, to: &archive)
            append32(body.count, to: &archive)
            append32(member.data.count, to: &archive)
            append16(name.count, to: &archive)
            append16(0, to: &archive)
            archive.append(name)
            archive.append(body)

            append32(0x0201_4B50, to: &directory)
            for value in [20, 20, 0, member.deflate ? 8 : 0, 0, 0] { append16(value, to: &directory) }
            append32(0, to: &directory)
            append32(body.count, to: &directory)
            append32(member.data.count, to: &directory)
            for value in [name.count, 0, 0, 0, 0] { append16(value, to: &directory) }
            append32(0, to: &directory)
            append32(offset, to: &directory)
            directory.append(name)
        }
        let directoryOffset = archive.count
        archive.append(directory)
        append32(0x0605_4B50, to: &archive)
        for value in [0, 0, members.count, members.count] { append16(value, to: &archive) }
        append32(directory.count, to: &archive)
        append32(directoryOffset, to: &archive)
        append16(0, to: &archive)
        return archive
    }
}
