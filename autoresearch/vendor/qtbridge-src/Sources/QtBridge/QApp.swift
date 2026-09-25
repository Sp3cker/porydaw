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

@MainActor
internal class QMLApp {
    var qmlApp: QAppCpp

    public init() {
        self.qmlApp = QAppCpp()
    }

    public func addImportPath(path: String) {
        qmlApp.addImportPath(path)
    }

    public func setPluginsPath(path: String) {
        qmlApp.setPluginsPath(path)
    }

    public func addInitialProperty(name: String, value: QVariant) {
        qmlApp.addInitialProperty(name, value.cppVariant())
    }

    public func setRootQml(path: String) {
        qmlApp.setRootQml(path)
    }

    public func run(argc: Int32, argv: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>!) {
        qmlApp.run(argc, argv)
    }
}

/// The entry point for a Qt Bridge application.
///
/// Conform to the `QApp` protocol to define your application's
/// configuration. A type that adopts `QApp` specifies the
/// QML file to load when the application starts and the Swift
/// objects that should be exposed to QML. Only Swift types
/// annotated with the ``QtBridgeable()`` macro are supported.
///
/// Declare a structure that conforms to `QApp` and mark it with
/// the `@main` attribute:
///
/// ```swift
/// @main
/// struct MyApp: QApp {
///     let qmlFileName: String = "main"
///     var initialProperties: [String: QObjectBuildable] = [
///         "myModel": MyModel()
///     ]
///     var instantiableTypes: [QmlInstantiable.Type] = [
///         MyType.self
///     ]
/// }
/// ```
///
/// The objects returned in ``initialProperties`` are exposed
/// to QML and can be accessed from QML using the provided keys:
///
/// ```qml
/// ApplicationWindow {
///     required property QtObject myModel
/// }
///```
///
/// The types returned in ``instantiableTypes`` can be instantiated
/// directly from QML as if they were native QML components. The type
/// will be available under the QML module whose name matches the Swift
/// module name and any nesting context.
///
/// ```qml
/// import MyApp // Swift module where MyType is defined
///
/// MyType {
///     id: mytype
/// }
/// ```
@MainActor public protocol QApp {
    /// Creates the application instance.
    init()

    /// The name of the QML file that is loaded when the
    /// application starts.
    ///
    /// Provide the file name **without the `.qml` extension**.
    /// For example, if the file is `Main.qml`, return `"Main"`.
    /// The bridge locates this file in the bundle specified by
    /// ``bundle`` and loads it as the initial user interface of
    /// the application.
    var qmlFileName: String { get }

    /// The bundle that contains the QML resources.
    ///
    /// The default implementation returns `Bundle.main`.
    ///
    /// Override this property if QML files are located in a
    /// different bundle. For example, when resources are
    /// provided by Swift Package Manager, you may need to
    /// return `Bundle.module`.
    ///
    /// The bundle's resource path is automatically added to
    /// the QML engine's import paths, so any QML modules
    /// inside the bundle can be imported by module name.
    var bundle: Bundle { get }

    /// Swift objects that should be exposed to QML.
    ///
    /// The keys of this dictionary define the names under which
    /// the objects become available in QML. Each value must be
    /// an object whose type is annotated with the
    /// ``QtBridgeable()`` macro.
    var initialProperties: [String: QObjectBuildable] { get }

    /// Swift types that can be instantiated from QML.
    ///
    /// Register types here to make them available as QML
    /// components. The type will be available under the
    /// QML module whose name matches the Swift module
    /// name and any nesting context for this type.
    ///
    /// Each type must conform to ``QmlInstantiable``
    /// and be annotated with the ``QtBridgeable()`` macro.
    var instantiableTypes: [QmlInstantiable.Type] { get }
}

@MainActor public extension QApp {
    var bundle: Bundle { .main }
    var initialProperties: [String: QObjectBuildable] { [:] }
    var instantiableTypes: [QmlInstantiable.Type] { [] }

    /// Starts the application.
    ///
    /// This method initializes the Qt Bridge application
    /// environment and begins the event loop. You don't call
    /// this method directly. It is invoked automatically by the
    /// Swift runtime for the type marked with `@main`.
    static func main() {
        let qApp = Self()
        let app = QMLApp()

        #if !QT_IS_CMAKE_BUILD
        // For SPM builds `QmlImports` exposes `Bundle.qmlImports` containing
        // the QML files and bundled plugins. For CMake builds the equivalent
        // resources come from the system Qt installation so this is skipped
        // when using CMake.
        app.addImportPath(path: Bundle.qmlImports.url(forResource: "qml", withExtension: nil)!.path)
        app.setPluginsPath(path: Bundle.qmlImports.url(forResource: "plugins", withExtension: nil)!.path)
        #endif // !QT_IS_CMAKE_BUILD

        if let bundlePath = qApp.bundle.resourceURL?.path {
            app.addImportPath(path: bundlePath)
        }

        for type in qApp.instantiableTypes {
            type.registerQmlElement()
        }

        for (name, property) in qApp.initialProperties {
            property.addInitialProperty(to: app, name: name)
        }

        let fileName = qApp.qmlFileName
        guard let qmlUrl = qApp.bundle.url(forResource: fileName, withExtension: "qml") else {
            fatalError("Missing QML file '\(fileName).qml' in app bundle.")
        }
        app.setRootQml(path: qmlUrl.path)
        app.run(argc: CommandLine.argc, argv: CommandLine.unsafeArgv)
    }
}
