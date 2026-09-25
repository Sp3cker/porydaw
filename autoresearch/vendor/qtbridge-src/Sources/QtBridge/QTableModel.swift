// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

/// A column that presents a value from each row in a table.
///
/// You create a column by providing a header and a key path that
/// identifies the value to display for each row.
///
/// ```swift
/// QTableColumn("Given Name", value: \.givenName)
/// ```
///
/// The column uses the key path to read the value from each
/// row object when the table model provides data to a QML view.
/// If the referenced property is mutable, the value can also be
/// edited from the view, updating the corresponding value in
/// the row object.
@MainActor
public struct QTableColumn<Row: QObjectBuildable> {
    /// The title displayed for the column
    public var header: String
    internal var get: ((Row) -> Any)?
    internal var set: ((Row, QVariant) -> Bool)?

    /// Creates a column that displays a value from each row
    ///
    /// - Parameters:
    ///   - header: The title displayed for the column
    ///   - value: A key path identifying the value to display
    ///   for each row.
    public init<Value: QVariantGettable>(_ header: String, value: KeyPath<Row, Value>) {
        self.header = header
        self.get = { row in
            row[keyPath: value]
        }
        self.set = nil
    }

    /// Creates a column that allows its value to be edited.
    ///
    /// - Parameters:
    ///   - header: The title displayed for the column
    ///   - value: A key path identifying the value associated
    ///   with the column.
    public init<Value: QVariantSettable>(_ header: String,
                                         value: ReferenceWritableKeyPath<Row, Value>) {
        self.header = header
        self.get = { row in
            row[keyPath: value]
        }
        self.set = { row, anyValue in
            let val = Value.value(from: anyValue)
            row[keyPath: value] = val
            return true
        }
    }
}

/// A result builder that constructs collections of ``QTableColumn``
/// instances.
///
/// ``QTableColumnBuilder`` creates table column content from
/// closures when declaring columns inside a ``QTableModel``
/// initializer.
///
/// ```swift
/// public var tableModel = QTableModel(people) {
///     if nickname {
///         QTableColumn("Nickname", value: \Person.nickname)
///     } else {
///         QTableColumn("Given Name", value: \Person.givenName)
///     }
///
///     QTableColumn("Last Name", value: \Person.lastName)
///     QTableColumn("Phone number", value: \Person.phone)
/// }
/// ```
///
/// You typically don’t use this type directly. Instead, it is
/// applied automatically to the `columns` parameter of
/// ``QTableModel`` initializers.
@resultBuilder
public struct QTableColumnBuilder<Row: QObjectBuildable> {
    /// Converts a single ``QTableColumn`` expression into the
    /// internal collection of ``QTableColumn``.
    public static func buildExpression(_ expression: QTableColumn<Row>) -> [QTableColumn<Row>] {
        [expression]
    }
    /// Combines multiple column lists produced within the builder
    /// block into a single list.
    public static func buildBlock(_ components: [QTableColumn<Row>]...) -> [QTableColumn<Row>] {
        components.flatMap { $0 }
    }
    /// Enables support for optional column content produced by
    /// conditional statements without an `else` branch.
    public static func buildOptional(_ component: [QTableColumn<Row>]?) -> [QTableColumn<Row>] {
        component ?? []
    }
    /// Handles the `true` branch of conditional statements with an `else` clause.
    public static func buildEither(first component: [QTableColumn<Row>]) -> [QTableColumn<Row>] {
        component
    }
    /// Handles the `false` branch of conditional statements with an `else` clause.
    public static func buildEither(second component: [QTableColumn<Row>]) -> [QTableColumn<Row>] {
        component
    }
    /// Enables support for `for..in` loops
    public static func buildArray(_ components: [[QTableColumn<Row>]]) -> [QTableColumn<Row>] {
        components.flatMap { $0 }
    }
}

/// A Swift container that exposes tabular data to QML views.
///
/// `QTableModel` organizes a collection of row objects and a
/// set of ``QTableColumn`` instances that determine which
/// values are displayed for each row.
///
/// You create a table model by providing a collection of rows
/// and declaring the columns that should appear in the table.
/// Row types must be classess marked with the ``QtBridgeable()``
/// macro whose properties use types supported by ``QVariant``.
/// The model then exposes those values to QML views such as
/// [TableView](https://doc.qt.io/qt-6/qml-qtquick-tableview.html).
///
/// ```swift
/// @QtBridgeable
/// public class Person {
///     var name: String
///     var age: Int
///
///     init(name: String, age: Int) {
///         self.name = name
///         self.age = age
///     }
/// }
///
/// @QtBridgeable
/// public class MyModel {
///     public var tableModel = QTableModel(people) {
///             QTableColumn("Name", value: \Person.name)
///             QTableColumn("Age", value: \Person.age)
///     }
/// }
/// ```
///
@MainActor
public final class QTableModel<Row: QObjectBuildable> {
    private var rows: [Row]
    private var columns: [QTableColumn<Row>]
    private var model: QAbstractTableModel

    public init() {
        self.rows = []
        self.columns = []
        self.model = QAbstractTableModel()
        self.model.bind(owner: self, rows: \.rows, columns: \.columns)
    }

    /// Creates a table model with the given rows and columns
    ///
    /// - Parameters:
    ///   - rows: The collection of row objects used as the
    ///   table's data
    ///   - columns: The columns of the table
    public init(_ rows: [Row], @QTableColumnBuilder<Row> columns: () -> [QTableColumn<Row>]) {
        self.rows = rows
        self.columns = columns()
        self.model = QAbstractTableModel()
        self.model.bind(owner: self, rows: \.rows, columns: \.columns)
    }

    /// Returns the value at the specified row and column.
    ///
    /// - Parameters:
    ///   - row: The index of the row.
    ///   - column: The index of the column.
    /// - Returns: The value stored at the specified position.
    public func value(row: Int, column: Int) -> Any? {
        guard row >= 0, row < rows.count, column >= 0, column < columns.count
        else { return () }
        guard let getter = columns[column].get else { return () }
        return getter(rows[row])
    }

    /// Updates the value at the specified row and column.
    ///
    /// - Parameters:
    ///   - value: The new value to assign.
    ///   - row: The index of the row.
    ///   - column: The index of the column.
    /// - Returns: `true` if the value was updated successfully.
    @discardableResult
    public func setValue<Value: QVariantSettable>(_ value: Value, row: Int, column: Int) -> Bool {
        guard row >= 0, row < rows.count, column >= 0, column < columns.count
        else { return false }
        let val = value.toVariant()
        guard let setter = columns[column].set else { return false }
        if setter(rows[row], val) {
            model.emitDataChanged(Int32(row), Int32(column), Int32(row), Int32(column), [])
            return true
        } else {
            return false
        }
    }

    /// Appends a row to the end of the table.
    ///
    /// - Parameter row: The row object to append.
    ///
    /// ## See Also
    /// - ``appendRows(_:)``
    /// - ``insertRow(_:at:)``
    /// - ``removeRow(at:)``
    public func appendRow(_ row: Row) {
        let first = Int32(rows.count)
        model.beginInsertRows(QModelIndex(), first, first)
        rows.append(row)
        model.endInsertRows()
    }

    /// Appends multiple rows to the end of the table.
    ///
    /// - Parameter newRows: Array of row objects to append.
    ///
    /// ## See Also
    /// - ``appendRow(_:)``
    /// - ``insertRows(_:at:)``
    /// - ``removeRows(in:)``
    public func appendRows(_ newRows: [Row]) {
        let first = Int32(rows.count)
        let last = first + Int32(newRows.count - 1)
        model.beginInsertRows(QModelIndex(), first, last)
        rows.append(contentsOf: newRows)
        model.endInsertRows()
    }

    /// Inserts a row at the specified index.
    ///
    /// - Parameters:
    ///   - row: The row object to insert.
    ///   - index: The position where the row should be
    ///   inserted.
    ///
    /// ## See Also
    /// - ``insertRows(_:at:)``
    /// - ``appendRows(_:)``
    /// - ``removeRows(in:)``
    public func insertRow(_ row: Row, at index: Int) {
        guard index >= 0, index <= rows.count else { return }
        let first = Int32(index)
        model.beginInsertRows(QModelIndex(), first, first)
        rows.insert(row, at: index)
        model.endInsertRows()
    }

    /// Inserts multiple rows at the specified index.
    ///
    /// - Parameters:
    ///   - newRows: Array of row objects to insert.
    ///   - index: The position where the rows should be
    ///   inserted
    ///
    /// ## See Also
    /// - ``insertRow(_:at:)``
    /// - ``appendRows(_:)``
    /// - ``removeRows(in:)``
    public func insertRows(_ newRows: [Row], at index: Int) {
        guard index >= 0, index <= rows.count else { return }
        let first = Int32(index)
        let last = first + Int32(newRows.count - 1)
        model.beginInsertRows(QModelIndex(), first, last)
        rows.insert(contentsOf: newRows, at: index)
        model.endInsertRows()
    }

    /// Moves a single row to a new position in the table.
    ///
    /// - Parameters:
    ///   - index: The index of the row to move.
    ///   - newIndex: The position where the row should be
    ///   moved.
    ///
    /// ## See Also
    /// - ``moveRows(from:to:)``
    /// - ``insertRow(_:at:)``
    /// - ``appendRow(_:)``
    public func moveRow(at index: Int, to newIndex: Int) {
        guard index >= 0, index < rows.count,
              newIndex >= 0, newIndex < rows.count,
              newIndex != index
        else { return }

        let first = Int32(index)
        let destination = newIndex > index ? newIndex + 1 : newIndex
        model.beginMoveRows(QModelIndex(), first, first, QModelIndex(), Int32(destination))
        let row = rows.remove(at: index)
        rows.insert(row, at: newIndex)
        model.endMoveRows()
    }

    /// Moves a contiguous range of rows to a new position
    /// in the table.
    ///
    /// - Parameters:
    ///   - range: The contiguous range of row indices to move.
    ///   - newIndex: The position where the rows should be
    ///   moved.
    ///
    /// ## See Also
    /// - ``moveRow(at:to:)``
    /// - ``insertRows(_:at:)``
    /// - ``appendRows(_:)``
    public func moveRows(from range: Range<Int>, to newIndex: Int) {
        let start = range.lowerBound
        let end = range.upperBound - 1
        let count = range.count

        guard count > 0, start >= 0,
              end < rows.count,
              newIndex >= 0,
              newIndex <= rows.count - count,
              newIndex < start || newIndex > end
        else { return }

        let destinationRow = newIndex > start ? newIndex + count : newIndex

        model.beginMoveRows(QModelIndex(), Int32(start), Int32(end), QModelIndex(), Int32(destinationRow))
        let movingRows = rows[range]
        rows.removeSubrange(range)
        rows.insert(contentsOf: movingRows, at: newIndex)
        model.endMoveRows()
    }

    /// Removes the row at the specified index.
    ///
    /// - Parameter index: The index of the row to remove.
    ///
    /// ## See Also
    /// - ``removeRows(in:)``
    /// - ``insertRow(_:at:)``
    /// - ``appendRow(_:)``
    public func removeRow(at index: Int) {
        guard index >= 0, index < rows.count else { return }
        let first = Int32(index)
        model.beginRemoveRows(QModelIndex(), first, first)
        rows.remove(at: index)
        model.endRemoveRows()
    }

    /// Removes rows in the specified index range.
    ///
    /// - Parameter range: The range of row indices to remove.
    ///
    /// ## See Also
    /// - ``removeRow(at:)``
    /// - ``removeColumns(in:)``
    public func removeRows(in range: Range<Int>) {
        guard !range.isEmpty,
              range.lowerBound >= 0,
              range.upperBound <= rows.count
        else { return }

        let first = Int32(range.lowerBound)
        let last = Int32(range.upperBound - 1)
        model.beginRemoveRows(QModelIndex(), first, last)
        rows.removeSubrange(range)
        model.endRemoveRows()
    }

    /// Append a column to the end of the table.
    ///
    /// - Parameter column: The column to append.
    ///
    /// ## See Also
    /// - ``appendColumns(_:)``
    /// - ``insertColumn(_:at:)``
    /// - ``removeColumn(at:)``
    public func appendColumn(_ column: QTableColumn<Row>) {
        let first = Int32(columns.count)
        model.beginInsertColumns(QModelIndex(), first, first)
        columns.append(column)
        model.endInsertColumns()
    }

    /// Appends multiple columns to the end of the table.
    ///
    /// - Parameter newColumns: Array of column objects to append.
    ///
    /// ## See Also
    /// - ``appendColumn(_:)``
    /// - ``insertColumns(_:at:)``
    /// - ``removeColumns(in:)``
    public func appendColumns(_ newColumns: [QTableColumn<Row>]) {
        let first = Int32(columns.count)
        let last = first + Int32(newColumns.count - 1)
        model.beginInsertColumns(QModelIndex(), first, last)
        columns.append(contentsOf: newColumns)
        model.endInsertColumns()
    }

    /// Inserts a column at the specified index.
    ///
    /// - Parameters:
    ///   - column: The column object to insert.
    ///   - index: The position where the column should be inserted.
    ///
    /// ## See Also
    /// - ``insertColumns(_:at:)``
    /// - ``appendColumn(_:)``
    /// - ``removeColumn(at:)``
    public func insertColumn(_ column: QTableColumn<Row>, at index: Int) {
        guard index >= 0, index <= columns.count else { return }
        let first = Int32(index)
        model.beginInsertColumns(QModelIndex(), first, first)
        columns.insert(column, at: index)
        model.endInsertColumns()
    }

    /// Inserts multiple columns at the specified index.
    ///
    /// - Parameters:
    ///   - newColumns: Array of column objects to insert.
    ///   - index: The position where the rows should be
    ///   inserted.
    ///
    /// ## See Also
    /// - ``insertColumn(_:at:)``
    /// - ``appendColumns(_:)``
    /// - ``removeColumns(in:)``
    public func insertColumns(_ newColumns: [QTableColumn<Row>], at index: Int) {
        guard index >= 0, index <= columns.count else { return }
        let first = Int32(index)
        let last = first + Int32(newColumns.count - 1)
        model.beginInsertColumns(QModelIndex(), first, last)
        columns.insert(contentsOf: newColumns, at: index)
        model.endInsertColumns()
    }

    /// Moves a single column to a new position in the table.
    ///
    /// - Parameters:
    ///   - index: The index of the column to move.
    ///   - newIndex: The position where the column should be
    ///   moved.
    ///
    /// ## See Also
    /// - ``moveColumns(from:to:)``
    /// - ``insertColumn(_:at:)``
    /// - ``appendColumn(_:)``
    public func moveColumn(at index: Int, to newIndex: Int) {
        guard index >= 0, index < columns.count,
              newIndex >= 0, newIndex < columns.count,
              newIndex != index
        else { return }

        model.layoutAboutToBeChanged()
        let column = columns.remove(at: index)
        columns.insert(column, at: newIndex)
        model.layoutChanged()
    }

    /// Moves a contiguous range of columns to a new position
    /// in the table.
    ///
    /// - Parameters:
    ///   - range: The contiguous range of column indices to move.
    ///   - newIndex: The position where the columns should be
    ///   moved.
    ///
    /// ## See Also
    /// - ``moveColumn(at:to:)``
    /// - ``insertColumns(_:at:)``
    /// - ``appendColumns(_:)``
    public func moveColumns(from range: Range<Int>, to newIndex: Int) {
        let start = range.lowerBound
        let end = range.upperBound - 1
        let count = range.count

        guard count > 0, start >= 0,
              end < columns.count,
              newIndex >= 0,
              newIndex <= columns.count - count,
              newIndex < start || newIndex > end
        else { return }

        model.layoutAboutToBeChanged()
        let movingCols = columns[range]
        columns.removeSubrange(range)
        columns.insert(contentsOf: movingCols, at: newIndex)
        model.layoutChanged()
    }

    /// Removes the column at the specified index.
    ///
    /// - Parameter index: The index of the column to remove.
    ///
    /// ## See Also
    /// - ``removeColumns(in:)``
    /// - ``insertColumn(_:at:)``
    /// - ``appendColumn(_:)``
    public func removeColumn(at index: Int) {
        guard index >= 0, index < columns.count else { return }
        let first = Int32(index)
        model.beginRemoveColumns(QModelIndex(), first, first)
        columns.remove(at: index)
        model.endRemoveColumns()
    }

    /// Removes columns in the specified index range.
    ///
    /// - Parameter range: The range of column indices to remove.
    ///
    /// ## See Also
    /// - ``removeColumns(in:)``
    /// - ``removeRow(at:)``
    public func removeColumns(in range: Range<Int>) {
        guard !range.isEmpty,
              range.lowerBound >= 0,
              range.upperBound <= columns.count
        else { return }

        let first = Int32(range.lowerBound)
        let last = Int32(range.upperBound - 1)
        model.beginRemoveColumns(QModelIndex(), first, last)
        columns.removeSubrange(range)
        model.endRemoveColumns()
    }

    /// Replaces the contents of the table with the rows and
    /// columns from another model.
    ///
    /// - Parameter newModel: The model whose contents should
    /// replace the current table.
    ///
    /// Resetting the table replaces all rows and columns at once.
    /// Connected views update their contents to reflect the new
    /// data.
    public func reset(to newModel: QTableModel) {
        model.beginResetModel()
        rows = newModel.rows
        columns = newModel.columns
        model.endResetModel()
    }

    /// Removes the contents of the table.
    ///
    /// Resetting the table removes all rows and columns at once.
    /// Connected views update their contents to reflect the new
    /// data.
    public func reset() {
        model.beginResetModel()
        rows.removeAll()
        columns.removeAll()
        model.endResetModel()
    }
}

extension QTableModel: QVariantGettable {
    public func toVariant() -> QVariant {
        return QVariant(model: self.model)
    }
    public static func metaType() -> Int32 {
        return 39
    }
}
