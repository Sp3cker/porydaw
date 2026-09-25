// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

import QtBridgeCpp

@MainActor
internal final class QAbstractTableModel {
    private lazy var cppModel: QAbstractTableModelCpp = {
        return QAbstractTableModelCpp.create(
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
    }()

    private static let registerCallbacks: Void = {
        QAbstractTableModelCpp.registerRowCount { swiftModel, idx in
            guard let swiftModel, let idx,
                  let bridge = QAbstractTableModel.bridge(swiftModel)
            else { return 0 }
            let index = QModelIndex(idx.pointee)
            return Int32(bridge.rowCount(index))
        }

        QAbstractTableModelCpp.registerColumnCount { swiftModel, idx in
            guard let swiftModel, let idx,
                  let bridge = QAbstractTableModel.bridge(swiftModel)
            else { return 0 }
            let index = QModelIndex(idx.pointee)
            return Int32(bridge.columnCount(index))
        }

        QAbstractTableModelCpp.registerData { swiftModel, idx, role in
            guard let swiftModel, let idx,
                  let bridge = QAbstractTableModel.bridge(swiftModel)
            else { return QtBridgeCpp.QVariant() }
            let index = QModelIndex(idx.pointee)
            return bridge.data(index, role).cppVariant()
        }

        QAbstractTableModelCpp.registerSetData { swiftModel, idx, val, role in
            guard let swiftModel, let idx,
                  let bridge = QAbstractTableModel.bridge(swiftModel)
            else { return false }
            let index = QModelIndex(idx.pointee)
            let value = QVariant(value: val.pointee)
            return bridge.setData(index, value, role)
        }

        QAbstractTableModelCpp.registerHeaderData { swiftModel, section, orientation, role in
            guard let swiftModel,
                  let bridge = QAbstractTableModel.bridge(swiftModel)
            else { return QtBridgeCpp.QVariant() }
            let headers = bridge.headerData(Int(section), orientation, role).cppVariant()
            return headers
        }
    }()

    public init() {
        QAbstractTableModel.registerCallbacks
        _ = self.cppModel
    }

    isolated deinit {
        QAbstractTableModelCpp.destroy(cppModel)
    }

    private var rowCount: (() -> Int)?
    private var columnCount: (() -> Int)?
    private var getValue: ((Int, Int) -> Any)?
    private var setValue: ((Int, Int, QVariant) -> Bool)?
    private var header: ((Int) -> String)?

    internal func bind<Owner: AnyObject, Row>(owner: Owner,
                                              rows: ReferenceWritableKeyPath<Owner, [Row]>,
                                              columns: ReferenceWritableKeyPath<Owner, [QTableColumn<Row>]>) {
        rowCount = { [weak owner] in
            guard let owner else { return 0 }
            return owner[keyPath: rows].count
        }
        columnCount = { [weak owner] in
            guard let owner else { return 0 }
            return owner[keyPath: columns].count
        }
        getValue = { [weak owner] row, col in
            guard let owner else { return QVariant() }
            let rows = owner[keyPath: rows]
            let cols = owner[keyPath: columns]
            guard row >= 0 && row < rows.count else { return QVariant() }
            guard col >= 0 && col < cols.count else { return QVariant() }
            guard let getter = cols[col].get else { return QVariant() }
            return getter(rows[row])
        }
        setValue = { [weak owner] row, col, variant in
            guard let owner else { return false }
            guard col >= 0 && col < owner[keyPath: columns].count else { return false }
            guard row >= 0 && row < owner[keyPath: rows].count else { return false }
            guard let setter = owner[keyPath: columns][col].set else { return false }
            return setter(owner[keyPath: rows][row], variant)
        }
        header = { [weak owner] section in
            guard let owner else { return "" }
            return owner[keyPath: columns][section].header
        }
    }

    public func rowCount(_ parent: QModelIndex) -> Int32 {
        guard parent.isValid() == false, let count = rowCount else { return 0 }
        return Int32(count())
    }

    public func columnCount(_ parent: QModelIndex) -> Int32 {
        guard parent.isValid() == false, let count = columnCount else { return 0 }
        return Int32(count())
    }

    public func data(_ index: QModelIndex, _ role: Int32) -> QVariant {
        guard index.isValid(),
                let colsCount = columnCount,
                let rowsCount = rowCount,
                let getValue = getValue
        else { return QVariant() }

        let row = Int(index.row())
        let col = Int(index.column())
        guard row >= 0, row < rowsCount(), col >= 0, col < colsCount()
        else { return QVariant() }

        guard role == ItemDataRole.DisplayRole
                || role == ItemDataRole.EditRole
        else { return QVariant() }

        let element = getValue(row, col)
        if let buildable = element as? QObjectBuildable {
            return buildable.toVariant()
        }

        if let gettable = element as? QVariantGettable {
            return gettable.toVariant()
        }
        return QVariant()
    }

    public func setData(_ index: QModelIndex, _ value: QVariant, _ role: Int32) -> Bool {
        guard index.isValid(),
                let rowCount = rowCount,
                let columnCount = columnCount,
                let getValue = getValue,
                let setValue = setValue
        else { return false }

        let row = Int(index.row())
        let col = Int(index.column())
        guard row >= 0, row < rowCount(), col >= 0, col < columnCount()
        else { return false }

        guard role == ItemDataRole.EditRole else { return false }

        var didChange: Bool = false
        let element = getValue(row, col)
        if element is QObjectBuildable || element is QVariantSettable {
            didChange = setValue(row, col, value)
        }

        if didChange { emitDataChanged(Int32(row), Int32(col), Int32(row), Int32(col), []) }
        return didChange
    }

    public func headerData(_ section: Int, _ orientation: Qt.Orientation, _ role: Int32) -> QVariant {
        switch orientation {
        case Qt.Horizontal:
            guard let columnCount = columnCount,
                  let header,
                  section >= 0, section < columnCount()
            else { return QVariant() }

            return header(section).toVariant()
        case Qt.Vertical:
            guard let rowCount = rowCount,
                  section >= 0, section < rowCount()
            else { return QVariant() }

            return QVariant(value: section + 1)
        default:
            return QVariant()
        }
    }

    internal func emitDataChanged(_ topRow: Int32, _ leftColumn: Int32, _ bottomRow: Int32,
                                  _ rightColumn: Int32, _ roles: [Int32] = []) {
        if roles.isEmpty {
            getCppModel().emitDataChanged(topRow, leftColumn, bottomRow, rightColumn, nil, 0)
        } else {
            roles.withUnsafeBufferPointer { buf in
                cppModel.emitDataChanged(topRow, leftColumn, bottomRow, rightColumn,
                                         buf.baseAddress, Int32(buf.count))
            }
        }
    }

    internal func beginInsertRows(_ parent: QModelIndex, _ first: Int32, _ last: Int32) {
        getCppModel().beginInsertRows(parent.cppModel, first, last)
    }

    internal func endInsertRows() { getCppModel().endInsertRows() }

    @discardableResult
    internal func beginMoveRows(_ sourceParent: QModelIndex, _ sourceFirst: Int32, _ sourceLast: Int32,
                                _ destinationParent: QModelIndex, _ destinationRow: Int32) -> Bool {
        return getCppModel().beginMoveRows(sourceParent.cppModel, sourceFirst, sourceLast,
                                           destinationParent.cppModel, destinationRow)
    }

    internal func endMoveRows() { getCppModel().endMoveRows() }

    internal func beginRemoveRows(_ parent: QModelIndex, _ first: Int32, _ last: Int32) {
        getCppModel().beginRemoveRows(parent.cppModel, first, last)
    }

    internal func endRemoveRows() { getCppModel().endRemoveRows() }

    internal func beginInsertColumns(_ parent: QModelIndex, _ first: Int32, _ last: Int32) {
        getCppModel().beginInsertColumns(parent.cppModel, first, last)
    }

    internal func endInsertColumns() { getCppModel().endInsertColumns() }

    internal func beginRemoveColumns(_ parent: QModelIndex, _ first: Int32, _ last: Int32) {
        getCppModel().beginRemoveColumns(parent.cppModel, first, last)
    }

    internal func endRemoveColumns() { getCppModel().endRemoveColumns() }

    internal func beginResetModel() { getCppModel().beginResetModel() }

    internal func endResetModel() { getCppModel().endResetModel() }

    internal func layoutChanged() { getCppModel().layoutChanged() }

    internal func layoutAboutToBeChanged() { getCppModel().layoutAboutToBeChanged() }

    internal func getCppModel() -> QAbstractTableModelCpp { return cppModel }

    internal static func bridge(_ swiftModel: UnsafeMutableRawPointer) -> QAbstractTableModel? {
        return Unmanaged<QAbstractTableModel>.fromOpaque(swiftModel).takeUnretainedValue()
    }
}

extension QAbstractTableModel: QVariantGettable {
    public func toVariant() -> QVariant {
        return QVariant(model: self)
    }
    public static func metaType() -> Int32 {
        return 39
    }
}
