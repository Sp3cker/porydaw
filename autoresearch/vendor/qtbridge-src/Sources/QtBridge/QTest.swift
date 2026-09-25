// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

import Foundation
import QtBridgeCpp
#if !QT_IS_CMAKE_BUILD
// `QmlImports` is provided by the Swift Package `qtforswift` and exposes a
// resource bundle that contains QML files, bundled Qt plugins, and binary artifacts.
// For CMake builds, the equivalent resources come from the system Qt installation.
import QmlImports
#endif // !QT_IS_CMAKE_BUILD

/// Represents a QML module to be registered for Qt Quick tests.
///
/// Use this to expose Swift model objects to QML tests via
/// standard QML import statements.
///
/// A module defined with:
/// ```swift
/// QmlTestModule(uri: "MyTest", major: 1, minor: 0, singletons: [:])
/// ```
/// can be imported in QML as:
/// ```qml
/// import MyTest 1.0
/// ```
///
/// All enties in ``singletons`` are registered as QML singleton
/// types and become available under that import.
public struct QmlTestModule {
    /// The QML module URI (for example, "MyTests").
    public var uri: String
    /// The major version of the module exposed to QML.
    public var major: Int32
    /// The minor version of the module exposed to QML.
    public var minor: Int32
    /// A mapping of singleton names to ``QObjectBuildable``
    /// instances.
    ///
    /// Each entry is registered as a QML singleton and can be
    /// accessed from QML using the provided key.
    public var singletons: [String: QObjectBuildable]

    /// Creates a new QML test module definition.
    ///
    /// - Parameters:
    ///   - uri: The QML module URI.
    ///   - major: The major version of the module.
    ///   - minor: The minor version of the module.
    ///   - singletons: Singleton objects to expose to QML.
    public init(uri: String, major: Int32, minor: Int32,
                singletons: [String: QObjectBuildable]) {
        self.uri = uri
        self.major = major
        self.minor = minor
        self.singletons = singletons
    }
}

/// Encapsulates all configuration required to run a Qt Quick
/// test suite.
public struct QtQuickTestConfiguration {
    /// The name of the test run.
    ///
    /// Defaults to `qtbridge-autotest`.
    public var testName: String
    /// The directory containing QML test files.
    public var inputDir: URL
    /// QML modules to register before running tests.
    public var registrations: [QmlTestModule]
    /// Additional command-line arguments passed to the test runner.
    ///
    /// ## See also
    /// - [Running tests](https://doc.qt.io/qt-6.11/qtquicktest-index.html#running-tests)
    public var arguments: [String]

    /// Creates a new Qt Quick test configuration.
    ///
    /// - Parameters:
    ///   - testName: Name of the test run.
    ///   - inputDir: Directory containing QML test files.
    ///   - registrations: QML modules to register.
    ///   - arguments: Additional arguments for the test runner.
    public init(testName: String, inputDir: URL,
                registrations: [QmlTestModule],
                arguments: [String] = []) {
        self.testName = testName
        self.inputDir = inputDir
        self.registrations = registrations
        self.arguments = arguments
    }
}

/// Utility for executing Qt Quick tests using a given
/// configuration.
@MainActor
public enum QtQuickTestRunner {
    /// Runs the Qt Quick test suite defined by the provided
    /// configuration.
    ///
    /// - Parameter config: The test configuration describing how
    /// to run the tests.
    /// - Returns: The exit code from the test run.
    @discardableResult
    public static func run(config: QtQuickTestConfiguration) -> Int32 {
        var qTestApp = QTestAppCpp()
#if !QT_IS_CMAKE_BUILD
        qTestApp.setImportPath(Bundle.qmlImports.url(forResource: "qml", withExtension: nil)!.path)
        qTestApp.setPluginsPath(Bundle.qmlImports.url(forResource: "plugins", withExtension: nil)!.path)
#endif // !QT_IS_CMAKE_BUILD
        qTestApp.setInputDir(config.inputDir.path)
        qTestApp.setTestName(config.testName)

        for module in config.registrations {
            for (name, model) in module.singletons {
                qTestApp.registerQmlSingleton(module.uri, module.major,
                                              module.minor, name,
                                              model.objectHolder.proxy)
            }
        }

        let args = ["qtbridge-qmltestrunner"] + config.arguments
        var argv: [UnsafeMutablePointer<Int8>?] = args.map { strdup($0) }
        defer { argv.forEach { free($0) } }

        return qTestApp.runQtQuickTests(Int32(args.count), &argv)
    }
}
