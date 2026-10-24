// swift-tools-version: 6.2
import PackageDescription

// A developer tool for measuring on-device dictation accuracy before building
// Notch Voice. Separate from the app's package, so nothing here ships.
let package = Package(
    name: "VoiceAccuracy",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "voice-accuracy",
            linkerSettings: [
                // A command-line tool has no bundle, so embed the Info.plist that
                // carries the microphone and speech usage descriptions macOS requires.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist", "-Xlinker", "\(Context.packageDirectory)/Info.plist",
                ]),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
