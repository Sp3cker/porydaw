// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

import Foundation
import QtBridgeCpp

/// An internal container for underlying QObject.
///
/// You don't create or use this type directly. Instances are
/// created and managed by the ``QtBridgeable()`` macro.
@MainActor
public class QObjectHolder {
    package var proxy: QObjectProxy
    internal weak var owner: (QObjectBuildable)?

    /// Creates a holder for a specified owner, which lifecycle
    /// is managed by QML.
    ///
    /// - Parameters:
    ///   - owner: The Swift object that owns this holder.
    ///   - ptr: Raw pointer where the QObject will be
    ///   created.
    ///   - deleter: Function used to release the Swift
    ///   object when QML destroys the QObject.
    ///
    /// This initializer is used by the bridging code. Don’t call it
    /// directly.
    public init(owner: QObjectBuildable,
                ptr: UnsafeMutableRawPointer,
                deleter: @escaping @convention(c) (UnsafeMutableRawPointer?) -> Void)
    {
        self.owner = owner
        self.proxy = QObjectProxy(QObjectHolder.bridge(owner), ptr, deleter)
        type(of: owner).metaObjectBuilder.setMetaObjectTo(objectHolder: self)

        if owner is QmlInstantiableStatus {
            self.proxy.registerComponentComplete(
                QObjectHolder.bridge(self),
                { (selfPtr: UnsafeMutableRawPointer?) in
                    guard let selfPtr,
                          let mySelf = QObjectHolder.bridge(selfPtr)
                    else { return }

                    mySelf.invokeComponentComplete()
                }
            )
        }
    }

    /// Creates a holder for a specified owner.
    ///
    /// - Parameters:
    ///   - owner: The Swift object that owns this holder.
    ///
    /// This initializer is used by the bridging code. Don’t call it
    /// directly.
    public init(owner: QObjectBuildable) {
        self.owner = owner
        self.proxy = QObjectProxy(QObjectHolder.bridge(owner))
        type(of: owner).metaObjectBuilder.setMetaObjectTo(objectHolder: self)
    }

    internal var qmlChildren: [QObjectBuildable] {
        var result: [QObjectBuildable] = []

        let childrenPtrs = proxy.swiftChildren()
        for i in 0..<childrenPtrs.size() {
            let ptr = childrenPtrs[i]
            guard let ptr else { continue }

            let object = Unmanaged<AnyObject>
                .fromOpaque(ptr)
                .takeUnretainedValue()

            if let buildable = object as? QObjectBuildable {
                result.append(buildable)
            }
        }

        return result
    }

    internal func getProperty(propIndex: Int) -> QVariant {
        guard let owner = owner else { return QVariant() }
        return type(of: owner).metaObjectBuilder.getProperty(propIndex: propIndex, root: owner)
    }

    internal func setProperty(propIndex: Int, value: QVariant) -> Bool {
        guard let owner = owner else { return false }
        return type(of: owner).metaObjectBuilder.setProperty(propIndex: propIndex, root: owner, value: value)
    }

    private func invokeComponentComplete() {
        guard let owner = self.owner else {
            return
        }

        if let component = owner as? QmlInstantiableStatus {
            component.componentComplete()
        }
    }

    private static func bridge<T: AnyObject>(_ obj: T) -> UnsafeMutableRawPointer {
        UnsafeMutableRawPointer(Unmanaged.passUnretained(obj).toOpaque())
    }

    private static func bridge(_ ptr: UnsafeMutableRawPointer) -> QObjectHolder? {
        return Unmanaged<QObjectHolder>.fromOpaque(ptr).takeUnretainedValue()
    }
}
