// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

/// A Swift collection that exposes its elements to QML views.
///
/// The elements stored in the list become accessible from QML,
/// allowing user interfaces to display and modify Swift data.
/// When you modify the model through the container operations,
/// the model emits the appropriate change notifications so the
/// views update automatically.
/// The `Element` type must be a type supported by ``QVariant``
/// or a custom type annotated with ``QtBridgeable()`` macro.
/// The model then exposes values to QML views such as
/// [ListView](https://doc.qt.io/qt-6/qml-qtquick-listview.html).
///
/// ## Simple Values
///
/// When the element type is a simple value, such as `String`,
/// the model behaves like a list of values in QML:
/// ```swift
/// @QtBridgeable
/// public class ListModel {
///     var list: QListModel<String> = ["test", "string"]
/// }
/// ```
///
/// ## Complex Types
///
/// ```swift
/// @QtBridgeable
/// public class Contact {
///     var name: String
///     var phone: Int
///
///     public init(name: String, phone: Int) {
///         self.name = name
///         self.phone = phone
///     }
/// }
///
/// @QtBridgeable
/// public class PhoneBook {
///     public var contacts: QListModel<Contact> = []
/// }
/// ```
///
/// In QML, the properties of each element can be accessed directly:
///
/// ```qml
/// required property string name
/// required property int phone
///
/// Text {
///     text: name + ": " + phone
/// }
/// ```
///
/// `QListModel` conforms to `RandomAccessCollection`,
/// `RangeReplaceableCollection` and `MutableCollection` allowing
/// elements to be accessed and modified using standard Swift
/// collection APIs.
@MainActor
public final class QListModel<Element: QVariantGettable>: @MainActor RandomAccessCollection,
                                                          @MainActor RangeReplaceableCollection,
                                                          @MainActor MutableCollection,
                                                          @MainActor ExpressibleByArrayLiteral {
    private var storage: [Element]
    private let model: QAbstractListModel

    /// Creates an empty list.
    public init() {
        self.storage = []
        self.model = QAbstractListModel()
        self.model.bind(owner: self, keyPath: \.storage)
    }

    /// Creates a list containing the elements of the
    /// given sequence.
    ///
    /// - Parameter elements: A sequence used to
    ///   populate the model.
    public convenience init<S: Sequence>(_ elements: S)
    where S.Element == Element {
        self.init()
        self.storage = Array(elements)
    }

    /// Creates a list from an array literal.
    ///
    /// This allows `QListModel` to be initialized using
    /// standard array syntax.
    public convenience init(arrayLiteral elements: Element...) {
        self.init(elements)
    }

    /// The position of the first element in the list.
    public var startIndex: Int { storage.startIndex }

    /// The position immediately after the last valid index
    /// of the list.
    public var endIndex: Int { storage.endIndex }

    /// Accesses the element at the specified position.
    public subscript(position: Int) -> Element {
        get { storage[position] }
        set {
            storage[position] = newValue
            model.emitDataChanged(Int32(position), Int32(position), [])
        }
    }

    /// Moves an element to a final index within the list.
    ///
    /// Invalid indices, identical indices, and moves rejected by
    /// the underlying Qt model leave the list unchanged.
    ///
    /// - Parameters:
    ///   - sourceIndex: The current index of the element.
    ///   - destinationIndex: The element's final index.
    public func move(from sourceIndex: Int, to destinationIndex: Int) {
        guard storage.indices.contains(sourceIndex),
              storage.indices.contains(destinationIndex),
              sourceIndex != destinationIndex
        else { return }

        let sourceRow = Int32(sourceIndex)
        let destinationChild = Int32(destinationIndex > sourceIndex
                                     ? destinationIndex + 1
                                     : destinationIndex)
        guard model.beginMoveRows(QModelIndex(), sourceRow, sourceRow,
                                  QModelIndex(), destinationChild)
        else { return }

        let element = storage.remove(at: sourceIndex)
        storage.insert(element, at: destinationIndex)
        model.endMoveRows()
    }

    /// Inserts, removes or replaces elements within
    /// the specified range.
    ///
    /// This method underlies most mutation operations defined
    /// by `RangeReplaceableCollection`, including `append`,
    /// `insert` and `remove`. Changes to the list are
    /// automatically propagated to the QML model, ensuring
    /// that bound views update to reflect the modified data.
    ///
    /// - Parameters:
    ///   - subrange: The range of elements to modify.
    ///   - newElements: The elements to insert at the specified
    ///     range.
    public func replaceSubrange<C: Collection>(_ subrange: Range<Int>, with newElements: C)
    where C.Element == Element {
        let oldCount = subrange.count
        let newCount = newElements.count

        if oldCount == 0 && newCount == 0 { return }
        let first = Int32(subrange.lowerBound)

        switch (oldCount, newCount) {
        // Insert
        case (0, let newItems) where newItems > 0:
            let last = Int32(subrange.lowerBound + newItems - 1)
            model.beginInsertRows(QModelIndex(), first, last)
            storage.replaceSubrange(subrange, with: newElements)
            model.endInsertRows()
        // Remove
        case (let oldItems, 0) where oldItems > 0:
            let last = Int32(subrange.upperBound - 1)
            model.beginRemoveRows(QModelIndex(), first, last)
            storage.replaceSubrange(subrange, with: newElements)
            model.endRemoveRows()
        // Replace
        default:
            if oldCount > 0 {
                let lastRem = Int32(subrange.upperBound - 1)
                model.beginRemoveRows(QModelIndex(), first, lastRem)
                storage.removeSubrange(subrange)
                model.endRemoveRows()
            }
            if newCount > 0 {
                let lastIns = Int32(subrange.lowerBound + newCount - 1)
                model.beginInsertRows(QModelIndex(), first, lastIns)
                storage.insert(contentsOf: newElements, at: subrange.lowerBound)
                model.endInsertRows()
            }
        }
    }

    /// Replaces the entire contents of the list with new
    /// elements in a single operation.
    ///
    /// - Parameter newElements: The elements that will
    ///   become the new contents of the list. If omitted,
    ///   the list becomes empty.
    public func reset(to newElements: [Element] = []) {
        model.beginResetModel()
        storage = newElements
        model.endResetModel()
    }

    /// Returns the contents of the list as a Swift array.
    public var asArray: [Element] { storage }
}

extension QListModel: QVariantGettable {
    public func toVariant() -> QVariant {
        return QVariant(model: self.model)
    }
    public static func metaType() -> Int32 {
        return 39
    }
}
