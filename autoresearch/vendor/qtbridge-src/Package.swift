// swift-tools-version: 6.2
import PackageDescription
import CompilerPluginSupport
import Foundation

let useLocalQt: Bool = false
let useLocal: Bool = envVar("QTBRIDGE_USE_LOCAL_QT_PACKAGE", useLocalQt)

// This is separated to be extracted via CMake
let swiftSyntaxVersion: Version = "600.0.0"

let dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/apple/swift-syntax.git", from: swiftSyntaxVersion),

    useLocal ? .package(path: "../Qt")
    : .package(url: "https://git.qt.io/qtbridge/qtforswift.git", branch: "master"),

    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0")
]

let qtPackageName: String = useLocal ? "Qt" : "qtforswift"

let package = Package(
    name: "QtBridge",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "QtBridge", targets: ["QtBridge"])
    ],
    dependencies: dependencies,
    targets: [
        .macro(
            name: "QtBridgeMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ],
            exclude: [
                "CMakeLists.txt"
            ]
        ),
        .target(
            name: "QtBridgeCpp",
            dependencies: [
                .product(name: "QtCore", package: qtPackageName),
                .product(name: "QtCorePrivate", package: qtPackageName),
                .product(name: "QtQml", package: qtPackageName),
                .product(name: "QtGui", package: qtPackageName),
                .product(name: "QtTest", package: qtPackageName)
            ],
            exclude: [
                "CMakeLists.txt"
            ]
        ),
        .target(
            name: "QtBridge",
            dependencies: [
                "QtBridgeCpp",
                "QtBridgeMacros",
                .product(name: "QtCore", package: qtPackageName),
                .product(name: "QtQml", package: qtPackageName),
                .product(name: "QtGui", package: qtPackageName),
                .product(name: "QmlImports", package: qtPackageName)
            ],
            exclude: [
                "CMakeLists.txt"
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
            ]
        ),
        .testTarget(
            name: "QtBridgeXCTests",
            dependencies: [
                "QtBridge", "QtBridgeMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
        .testTarget(
            name: "QtQuickTests",
            dependencies: [ "QtBridge" ],
            resources: [
                .copy("Resources/qml")
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        )
    ],
    cxxLanguageStandard: .cxx17
)

func envVar(_ name: String, _ def: Bool) -> Bool {
    if let value = ProcessInfo.processInfo.environment[name] {
        return (value as NSString).boolValue
    }
    return def
}
