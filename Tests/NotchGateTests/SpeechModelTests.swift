import Compression
import Foundation
import Testing
@testable import NotchGate

@Suite("Speech model catalog")
struct SpeechModelCatalogTests {
    @Test func applesIsBuiltInAndTheRestGoSmallestFirst() {
        #expect(SpeechModel.catalog.first == .apple)
        #expect(SpeechModel.catalog.map(\.id) == ["apple", "whistle", "shruti"])
        let sizes = SpeechModel.catalog.map(\.downloadSize)
        #expect(sizes == sizes.sorted())
        #expect(SpeechModel.apple.isBuiltIn)
        #expect(Set(SpeechModel.catalog.map(\.id)).count == SpeechModel.catalog.count)
        #expect(SpeechModel.withID("shruti") == .shruti)
        #expect(SpeechModel.withID("underdog-bark-3.0") == nil)
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
        // whistle.cact (16.9 MB) plus the engine wheel.
        #expect((17_000_000...18_000_000).contains(SpeechModel.whistle.downloadSize))
        // shruti.cact (29.5 MB) plus the same engine wheel.
        #expect((30_000_000...30_200_000).contains(SpeechModel.shruti.downloadSize))
        #expect(SpeechModel.shruti.files.last == SpeechModel.whistle.files.last)
    }

    @Test func eachModelOffersItsOwnLanguages() {
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
    private func fakeDownload(_ model: SpeechModel, in store: SpeechModelStore) throws {
        for file in model.files {
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
        settings.voiceModel = SpeechModel.shruti.id
        #expect(store.state(of: .shruti) == .notDownloaded)
        #expect(voice.speechModel == .apple)

        try fakeDownload(.shruti, in: store)
        #expect(store.state(of: .shruti) == .downloaded)
        let expected: SpeechModel = SpeechModel.shruti.unsupportedReason == nil ? .shruti : .apple
        #expect(voice.speechModel == expected)
    }

    @Test func aRetiredModelsFilesAreDeleted() throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let leftover = folder.appendingPathComponent("underdog-bark-3.0", isDirectory: true)
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: leftover.appendingPathComponent("vocab.json").path, contents: nil)
        _ = SpeechModelStore(folder: folder)
        #expect(!FileManager.default.fileExists(atPath: leftover.path))
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
        voice.selectModel(.shruti)
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
    @Test func readsStoredAndDeflatedZipMembers() throws {
        let text = Data(String(repeating: "needle engine ", count: 40).utf8)
        let archive = try ZipArchive(data: Self.zip([
            ("stored.txt", Data("hello".utf8), false),
            ("deflated.txt", text, true),
        ]))
        #expect(Set(archive.names) == ["stored.txt", "deflated.txt"])
        #expect(try archive.read("stored.txt") == Data("hello".utf8))
        #expect(try archive.read("deflated.txt") == text)
        #expect(throws: ZipArchive.ReadError.self) { try archive.read("missing") }
    }

    @Test func notAZipIsAnError() {
        #expect(throws: ZipArchive.ReadError.self) { try ZipArchive(data: Data("hello".utf8)) }
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
