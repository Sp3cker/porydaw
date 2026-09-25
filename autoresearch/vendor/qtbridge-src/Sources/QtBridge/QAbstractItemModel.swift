// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

import Foundation
import CxxStdlib
import QtBridgeCpp

@MainActor
internal class QAbstractItemModel {
    private var cppModel: QAbstractItemModelCpp!

    public init() {
        self.cppModel = QAbstractItemModelCpp.create(UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))

        cppModel.registerIndex { swiftModel, row, column, parentPtr in
            guard let swiftModel = swiftModel,
                  let parentPtr = parentPtr else { return QtBridgeCpp.QModelIndex() }
            let parent = QModelIndex(parentPtr.pointee)
            return QAbstractItemModel.bridge(swiftModel)!.index(row, column, parent).cppModel
        }

        cppModel.registerParent { swiftModel, childPtr in
            guard let swiftModel = swiftModel,
                  let childPtr = childPtr else { return QtBridgeCpp.QModelIndex() }
            let child = QModelIndex(childPtr.pointee)
            return QAbstractItemModel.bridge(swiftModel)!.parent(child).cppModel
        }

        cppModel.registerRowCount { swiftModel, idx in
            guard let swiftModel = swiftModel,
                  let idx = idx else { return 0 }
            let index = QModelIndex(idx.pointee)
            return Int32(QAbstractItemModel.bridge(swiftModel)!.rowCount(index))
        }

        cppModel.registerColumnCount { swiftModel, idx in
            guard let swiftModel = swiftModel,
                  let idx = idx else { return 0 }
            let index = QModelIndex(idx.pointee)
            return Int32(QAbstractItemModel.bridge(swiftModel)!.columnCount(index))
        }

        cppModel.registerData { swiftModel, idx, role in
            guard let swiftModel = swiftModel,
                  let idx = idx else { return QtBridgeCpp.QVariant() }
            let index = QModelIndex(idx.pointee)
            return QAbstractItemModel.bridge(swiftModel)!.data(index, role).cppVariant()
        }

        cppModel.registerSetData { swiftModel, idx, val, role in
            guard let swiftModel = swiftModel,
                  let idx = idx else { return false }
            let index = QModelIndex(idx.pointee)
            let value = QVariant(value: val.pointee)
            return QAbstractItemModel.bridge(swiftModel)!.setData(index, value, role)
        }

        cppModel.registerRoleNames { swiftModel in
            guard let swiftModel = swiftModel else { return CallbackBase.QHashIntToByteArray() }
            let roleNames = QAbstractItemModel.bridge(swiftModel)!.roleNames()
            var qhash = CallbackBase.QHashIntToByteArray()
            for (key, value) in roleNames {
                qhashInsert(&qhash, key, std.string(value))
            }
            return qhash
        }

        cppModel.registerInsertRows { swiftModel, row, count, idx in
            guard let swiftModel = swiftModel,
                  let idx = idx else { return false }
            let index =  QModelIndex(idx.pointee)
            return QAbstractItemModel.bridge(swiftModel)!.insertRows(row, count, index)
        }

        cppModel.registerMoveRows { swiftModel, srcParent, srcRow, count, dstnParent, dstnChild in
            guard let swiftModel = swiftModel,
                  let srcParent = srcParent,
                  let dstnParent = dstnParent else { return false }
            let sourceParent = QModelIndex(srcParent.pointee)
            let destinationParent = QModelIndex(dstnParent.pointee)
            return QAbstractItemModel.bridge(swiftModel)!.moveRows(sourceParent, srcRow, count, destinationParent, dstnChild)
        }

        cppModel.registerRemoveRows { swiftModel, row, count, parentPtr in
            guard let swiftModel = swiftModel,
                  let parentPtr = parentPtr else { return false }
            let parent = QModelIndex(parentPtr.pointee)
            return QAbstractItemModel.bridge(swiftModel)!.removeRows(row, count, parent)
        }
    }

    isolated deinit {
        QAbstractItemModelCpp.destroy(cppModel)
    }

    public func index(_ row: Int32, _ column: Int32, _ parent: QModelIndex = QModelIndex()) -> QModelIndex { return QModelIndex() }

    public func parent(_ child: QModelIndex) -> QModelIndex { return QModelIndex() }

    public func rowCount(_ parent: QModelIndex) -> Int32 { return 0 }

    public func columnCount(_ parent: QModelIndex) -> Int32 { return 0 }

    public func data(_ index: QModelIndex, _ role: Int32) -> QVariant { return QVariant() }

    public func setData(_ index: QModelIndex, _ value: QVariant, _ role: Int32) -> Bool { return false }

    public func roleNames() -> [Int32: String] { return [:] }

    public func insertRows(_ row: Int32, _ count: Int32, _ index: QModelIndex) -> Bool { return false }

    public func moveRows(_ sourceParent: QModelIndex, _ sourceRow: Int32, _ count: Int32,
                         _ destinationParent: QModelIndex, _ destinationChild: Int32) -> Bool { return false }

    public func removeRows(_ row: Int32, _ count: Int32, _ parent: QModelIndex) -> Bool { return false }

    public func createIndex(_ row: Int32, _ column: Int32, _ id: UInt64) -> QModelIndex {
        return QModelIndex(getCppModel().createIndex(row, column, id))
    }

    public func beginInsertRows(_ parent: QModelIndex, _ first: Int32, _ last: Int32) {
        getCppModel().beginInsertRows(parent.cppModel, first, last)
    }

    public func endInsertRows() { getCppModel().endInsertRows() }

    public func beginRemoveRows(_ parent: QModelIndex, _ first: Int32, _ last: Int32) {
        getCppModel().beginRemoveRows(parent.cppModel, first, last)
    }

    public func endRemoveRows() { getCppModel().endRemoveRows() }

    public func beginMoveRows(_ sourceParent: QModelIndex, _ sourceFirst: Int32, _ sourceLast: Int32,
                              _ destinationParent: QModelIndex, _ destinationRow: Int32) -> Bool
    {
        return getCppModel().beginMoveRows(sourceParent.cppModel, sourceFirst, sourceLast,
                                           destinationParent.cppModel, destinationRow)
    }

    public func endMoveRows() { getCppModel().endMoveRows() }

    public func beginInsertColumns(_ parent: QModelIndex, _ first: Int32, _ last: Int32) {
        getCppModel().beginInsertColumns(parent.cppModel, first, last)
    }

    public func endInsertColumns() { getCppModel().endInsertColumns() }

    public func beginRemoveColumns(_ parent: QModelIndex, _ first: Int32, _ last: Int32) {
        getCppModel().beginRemoveColumns(parent.cppModel, first, last)
    }

    public func endRemoveColumns() { getCppModel().endRemoveColumns() }

    public func beginMoveColumns(_ sourceParent: QModelIndex, _ sourceFirst: Int32, _ sourceLast: Int32,
                                 _ destinationParent: QModelIndex, _ destinationColumn: Int32) -> Bool {
        return getCppModel().beginMoveColumns(sourceParent.cppModel, sourceFirst, sourceLast,
                                       destinationParent.cppModel, destinationColumn)
    }

    public func endMoveColumns() { getCppModel().endMoveColumns() }

    public func beginResetModel() { getCppModel().beginResetModel() }

    public func endResetModel() { getCppModel().endResetModel() }

    public func getCppModel() -> QAbstractItemModelCpp { return cppModel! }

    public static func bridge(_ swiftModel: UnsafeMutableRawPointer) -> QAbstractItemModel? {
        return Unmanaged<QAbstractItemModel>.fromOpaque(swiftModel).takeUnretainedValue()
    }
}
