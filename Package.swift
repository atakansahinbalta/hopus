// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hopus",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "HopusCore", targets: ["HopusCore"]),
        .executable(name: "Hopus", targets: ["HopusApp"]),
        .executable(name: "hopus-cli", targets: ["HopusCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "HopusCore", resources: [.copy("Resources")]),
        // The frozen XPC wire protocol stays at its sealed source path. It is compiled
        // into the renamed module without changing its Objective-C identity.
        .target(name: "HopusUpdates", dependencies: [.product(name: "Sparkle", package: "Sparkle")], path: "Sources", exclude: ["HopusApp", "HopusCore", "HopusCLI", "UpdateCredentialBroker"], sources: ["HopusUpdates", "TangerineUpdates/UpdateCredentialBrokerProtocol.swift"]),
        .executableTarget(name: "HopusApp", dependencies: ["HopusCore", "HopusUpdates"], resources: [.process("Resources")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "HopusCLI", dependencies: ["HopusCore"]),
        .testTarget(name: "HopusCoreTests", dependencies: ["HopusCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "HopusUpdatesTests", dependencies: ["HopusUpdates"])
    ],
    swiftLanguageModes: [.v5]
)
