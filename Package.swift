// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GRFToolMac",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "GRFToolMac", targets: ["GRFToolMac"])],
    targets: [
        .target(name: "CGRFCrypto", publicHeadersPath: "include", linkerSettings: [.linkedLibrary("z")]),
        .target(name: "GRFCore", dependencies: ["CGRFCrypto"], resources: [.process("Resources")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "GRFDesktop", dependencies: ["GRFCore"], resources: [.process("Resources")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "GRFToolMac", dependencies: ["GRFCore", "GRFDesktop"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "GRFCoreTests", dependencies: ["GRFCore", "GRFDesktop", "CGRFCrypto"], swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
