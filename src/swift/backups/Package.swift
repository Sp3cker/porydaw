// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PorydawBackups",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PorydawBackups", targets: ["PorydawBackups"])
    ],
    targets: [
        .target(
            name: "PorydawBackups",
            path: ".",
            exclude: ["CMakeLists.txt", "Tests"],
            sources: ["MidiBackupStore.swift"]),
        .testTarget(
            name: "PorydawBackupsTests",
            dependencies: ["PorydawBackups"],
            path: "Tests"),
    ],
    swiftLanguageModes: [.v6])
