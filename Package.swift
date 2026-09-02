// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SkillzBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SkillzBar", targets: ["SkillzBar"]),
        .library(name: "SkillzBarCore", targets: ["SkillzBarCore"]),
    ],
    targets: [
        .target(name: "SkillzBarCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "SkillzBar",
            dependencies: ["SkillzBarCore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("Carbon"), .linkedFramework("ServiceManagement")]
        ),
        .testTarget(name: "SkillzBarCoreTests", dependencies: ["SkillzBarCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
