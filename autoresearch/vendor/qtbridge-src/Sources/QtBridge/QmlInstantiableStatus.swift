// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

/// A protocol that extends ``QmlInstantiable`` with a method that
/// is called when the QML component has finished instantiation.
///
/// The bridge calls ``componentComplete()`` after the QML engine
/// has finished instantiating the object and all its children. Override this
/// method to perform any additional setup.
///
/// ```swift
/// @QtBridgeable
/// class RestService: QmlInstantiableStatus {
///     private let api: ServiceApi = ServiceApi()
///     required init() {}
///
///     func componentComplete() {
///         for child in qmlChildren {
///             if let resource = child as? AbstractResource {
///                 resource.api = api
///             }
///         }
///     }
/// }
/// ```
public protocol QmlInstantiableStatus : QmlInstantiable {
    /// Called when the QML component and all its children
    /// have finished instantiation.
    func componentComplete()
}
