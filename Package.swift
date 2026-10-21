// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LSwitcher",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LSwitcher", targets: ["LSwitcher"])],
    targets: [
        .target(name: "LSwitcherCore", resources: [.copy("Resources/Lexicon.lzfse"), .copy("Resources/ThirdPartyNotices.txt")]),
        .executableTarget(name: "LSwitcher", dependencies: ["LSwitcherCore"]),
        .executableTarget(name: "LSwitcherUpdater", dependencies: ["LSwitcherCore"]),
        .executableTarget(name: "LSwitcherChecks", dependencies: ["LSwitcherCore"], path: "Tests/LSwitcherCoreTests")
    ]
)
