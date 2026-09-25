// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

import Foundation
import CxxStdlib
import QtBridgeCpp

@MainActor
internal final class QAbstractListModel {
    private lazy var cppModel: QAbstractListModelCpp = {
        return QAbstractListModelCpp.create(
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
    }()

    private static let registerCallbacks: Void = {
        QAbstractListModelCpp.registerRowCount { swiftModel, idx in
            guard let swiftModel, let idx,
                  let bridge = QAbstractListModel.bridge(swiftModel)
            else { return 0 }
            let index = QModelIndex(idx.pointee)
            return Int32(bridge.rowCount(index))
        }

        QAbstractListModelCpp.registerData { swiftModel, idx, role in
            guard let swiftModel, let idx,
                  let bridge = QAbstractListModel.bridge(swiftModel)
            else { return QtBridgeCpp.QVariant() }
            let index = QModelIndex(idx.pointee)
            return bridge.data(index, role).cppVariant()
        }

        QAbstractListModelCpp.registerSetData { swiftModel, idx, val, role in
            guard let swiftModel, let idx,
                  let bridge = QAbstractListModel.bridge(swiftModel)
            else { return false }
            let index = QModelIndex(idx.pointee)
            let value = QVariant(value: val.pointee)
            return bridge.setData(index, value, role)
        }

        QAbstractListModelCpp.registerRoleNames { swiftModel in
            guard let swiftModel,
                  let bridge = QAbstractListModel.bridge(swiftModel)
            else { return CallbackBase.QHashIntToByteArray() }
            let roleNames = bridge.roleNames()
            var qhash = CallbackBase.QHashIntToByteArray()
            for (key, value) in roleNames {
                qhashInsert(&qhash, key, std.string(value))
            }
            return qhash
        }
    }()

    public init() {
        QAbstractListModel.registerCallbacks
        _ = self.cppModel
    }

    isolated deinit {
        QAbstractListModelCpp.destroy(cppModel)
    }

    private var count: (() -> Int)?
    private var elementAt: ((Int) -> Any)?
    private var replaceAt: ((Int, QVariant) -> Bool)?
    private let userRole: Int32 = ItemDataRole.UserRole
    private var roles: [Int32: String] = [:]

    internal func bind<Owner: AnyObject, Element>(owner: Owner,
                                                  keyPath: ReferenceWritableKeyPath<Owner, [Element]>) {
        count = { [weak owner] in
            guard let owner else { return 0 }
            return owner[keyPath: keyPath].count
        }
        elementAt = { [weak owner] idx in
            guard let owner else { return () }
            return owner[keyPath: keyPath][idx] as Any
        }

        roles.removeAll()
        roles[ItemDataRole.DisplayRole] = "display"
        // Property names as roles
        if let buildable = Element.self as? QObjectBuildable.Type {
            var propertyId = 0
            for name in buildable.metaObjectBuilder.propertyNames {
                roles[userRole + Int32(propertyId)] = name
                propertyId += 1
            }
        }
        // Basic types
        if Element.self is QVariantSettable.Type {
            replaceAt = { [weak owner] idx, variant in
                guard let owner else { return false }
                guard let T = Element.self as? QVariantSettable.Type else { return false }
                let value: Any = T.value(from: variant)
                owner[keyPath: keyPath][idx] = value as! Element
                return true
            }
        } else {
            replaceAt = nil
        }
    }

    public func rowCount(_ parent: QModelIndex) -> Int32 {
        guard parent.isValid() == false, let count = count else { return 0 }
        return Int32(count())
    }

    public func data(_ index: QModelIndex, _ role: Int32) -> QVariant {
        guard index.isValid(), let count = count, let elementAt = elementAt
        else { return QVariant() }
        let row = Int(index.row())
        guard row >= 0 && row < count() else { return QVariant() }
        let element = elementAt(row)
        if let buildable = element as? QObjectBuildable {
            if role == ItemDataRole.DisplayRole {
                return buildable.toVariant()
            }
            let propertyId = role - userRole
            return buildable.objectHolder.getProperty(propIndex: Int(propertyId))
        }
        if let gettable = element as? QVariantGettable {
            return gettable.toVariant()
        }
        return QVariant()
    }

    public func setData(_ index: QModelIndex, _ value: QVariant, _ role: Int32) -> Bool {
        guard index.isValid(), let count = count, let elementAt = elementAt else { return false }
        let row = Int(index.row())
        guard row >= 0 && row < count() else { return false }
        var didChange: Bool = false
        if let buildable = elementAt(row) as? QObjectBuildable {
            if role == ItemDataRole.DisplayRole {
                return false
            }
            let propertyId: Int32 = role - userRole
            didChange = buildable.objectHolder.setProperty(propIndex: Int(propertyId), value: value)
        } else if let replaceAt = replaceAt {
            didChange = replaceAt(row, value)
        }
        if didChange { emitDataChanged(Int32(row), Int32(row), [role]) }
        return didChange
    }

    public func roleNames() -> [Int32: String] { roles }

    internal func emitDataChanged(_ topLeft: Int32, _ bottomRight: Int32, _ roles: [Int32] = []) {
        if roles.isEmpty {
            getCppModel().emitDataChanged(topLeft, bottomRight, nil, 0)
        } else {
            roles.withUnsafeBufferPointer { buf in
                cppModel.emitDataChanged(topLeft, bottomRight, buf.baseAddress, Int32(buf.count))
            }
        }
    }

    internal func beginInsertRows(_ parent: QModelIndex, _ first: Int32, _ last: Int32) -> Void {
        return getCppModel().beginInsertRows(parent.cppModel, first, last)
    }

    internal func endInsertRows() -> Void { return getCppModel().endInsertRows() }

    @discardableResult
    internal func beginMoveRows(_ sourceParent: QModelIndex, _ sourceFirst: Int32, _ sourceLast: Int32,
                                _ destinationParent: QModelIndex, _ destinationRow: Int32) -> Bool {
        return getCppModel().beginMoveRows(sourceParent.cppModel, sourceFirst, sourceLast,
                                           destinationParent.cppModel, destinationRow)
    }

    internal func endMoveRows() { getCppModel().endMoveRows() }

    internal func beginRemoveRows(_ parent: QModelIndex, _ first: Int32, _ last: Int32) -> Void {
        return getCppModel().beginRemoveRows(parent.cppModel, first, last)
    }

    internal func endRemoveRows() -> Void { return getCppModel().endRemoveRows() }

    internal func beginResetModel() { getCppModel().beginResetModel() }

    internal func endResetModel() { getCppModel().endResetModel() }

    internal func getCppModel() -> QAbstractListModelCpp { return cppModel }

    internal static func bridge(_ swiftModel: UnsafeMutableRawPointer) -> QAbstractListModel? {
        return Unmanaged<QAbstractListModel>.fromOpaque(swiftModel).takeUnretainedValue()
    }
}

extension QAbstractListModel : QVariantGettable {
    public func toVariant() -> QVariant {
        return QVariant(model: self)
    }
    public static func metaType() -> Int32 {
        return 39
    }
}
