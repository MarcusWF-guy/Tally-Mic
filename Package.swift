// swift-tools-version: 6.0
import PackageDescription

// With only the Command Line Tools installed, the build doesn't look in this folder for the
// plugin behind Swift Testing's #expect, so `swift test` fails without this path.
let testingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"

// SwiftPM hands the SDK to the final link as `--sysroot`, which doesn't tell the linker the SDK's
// version, so it stamped the app "built with the macOS 14 SDK" (the deployment target). macOS 27
// then gave Tally Mic the old, pre-Liquid Glass look, such as a grey Settings window. `-isysroot`
// lets it read the version from the SDK itself. MacOSX.sdk always points at the current SDK.
let currentSDK = "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"

let package = Package(
    name: "TallyMic",
    // SPEC 3: macOS 27, the only version Tally Mic has been tested on.
    platforms: [.macOS("27.0")],
    targets: [
        .executableTarget(
            name: "TallyMic",
            linkerSettings: [.unsafeFlags(["-Xclang-linker", "-isysroot", "-Xclang-linker", currentSDK])]
        ),
        .testTarget(
            name: "TallyMicTests",
            dependencies: ["TallyMic"],
            swiftSettings: [.unsafeFlags(["-plugin-path", testingPlugins])]
        ),
    ]
)
