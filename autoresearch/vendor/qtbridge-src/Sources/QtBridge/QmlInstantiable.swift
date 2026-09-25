// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

/// A protocol that allows a conforming type to be instantiated
/// and composed directly from QML.
///
/// Types conforming to this protocol must also be registered in
/// ``QApp/instantiableTypes`` and annotated with the
/// ``QtBridgeable()`` macro to become available in QML.
///
/// Once registered, the type is available under its Swift module
/// name and can be instantiated by its type name. Its QML child
/// objects are automatically available in Swift via ``qmlChildren``:
///
/// ```qml
/// QmlType {
///     QmlType1 {}
///     QmlType2 {}
/// }
/// ```
///
/// ```swift
/// @QtBridgeable
/// class QmlType: QmlInstantiable {
///     required init() {}
///
///     func countChildren() {
///         for child in qmlChildren {
///             if child is QmlType1 { type1Count += 1 }
///             if child is QmlType2 { type2Count += 1 }
///         }
///     }
/// }
/// ```
/// - Note: Only Swift types appear in ``qmlChildren``, plain QML objects
/// are not included.
public protocol QmlInstantiable: QObjectBuildable {
    init()
}

extension QmlInstantiable {
    /// The Swift child objects nested inside this instance
    /// in QML.
    ///
    /// Children are listed in the order they appear in the
    /// QML source and only direct children are included.
    public var qmlChildren: [QObjectBuildable] {
        return objectHolder.qmlChildren
    }
}

extension QmlInstantiable {
    public static func registerQmlElement() {
        metaObjectBuilder.registerInitializer(initFn: self.init)
        metaObjectBuilder.registerQmlElement(from: Self.self)
    }
}
