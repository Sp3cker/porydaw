import QtBridge

/// Publish changed rows without resetting model identity or rewriting matches;
/// a shared prefix and suffix stay put, so one inserted row moves no delegate.
@MainActor
public func syncModel<Element: QVariantGettable>(
    _ model: QListModel<Element>, _ values: [Element],
    matches: (Element, Element) -> Bool
) {
    let oldCount = model.count
    let newCount = values.count
    var prefix = 0
    while prefix < oldCount, prefix < newCount, matches(model[prefix], values[prefix]) {
        prefix += 1
    }
    var suffix = 0
    while suffix < oldCount - prefix, suffix < newCount - prefix,
        matches(model[oldCount - 1 - suffix], values[newCount - 1 - suffix])
    {
        suffix += 1
    }
    let oldEnd = oldCount - suffix
    let newEnd = newCount - suffix
    guard prefix < oldEnd || prefix < newEnd else { return }
    model.update {
        let common = min(oldEnd, newEnd)
        for index in prefix..<common where !matches(model[index], values[index]) {
            model[index] = values[index]
        }
        if oldEnd != newEnd {
            model.replaceSubrange(common..<oldEnd, with: values[common..<newEnd])
        }
    }
}

/// Retained rows: existing row objects update in place, new values append, extras drop.
/// `update` returns whether the row changed; changed rows republish synchronously.
@MainActor
public func syncRetained<Row: QVariantGettable, Value>(
    _ model: QListModel<Row>, _ values: some Collection<Value>,
    make: (Value) -> Row, update: (Row, Value) -> Bool
) {
    model.update {
        var index = 0
        for value in values {
            if index < model.count {
                let row = model[index]
                if update(row, value) { model[index] = row }
            } else {
                model.replaceSubrange(index..<index, with: CollectionOfOne(make(value)))
            }
            index += 1
        }
        if model.count > index { model.replaceSubrange(index..<model.count, with: []) }
    }
}

extension QObjectBuildable where Self: AnyObject {
    /// Writes a published property only when it changes, naming it once.
    @MainActor
    public func publish<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<Self, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }
}

extension QmlColor {
    /// Transparent black: the seed for colours not yet published.
    public static let clear = QmlColor(red: 0, green: 0, blue: 0, alpha: 0)
}
