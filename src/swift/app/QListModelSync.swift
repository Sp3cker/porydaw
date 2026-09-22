import QtBridge

/// Publish changed rows without resetting model identity or rewriting matches.
@MainActor
func syncModel<Element: QVariantGettable>(
    _ model: QListModel<Element>, _ values: [Element],
    matches: (Element, Element) -> Bool
) {
    let common = min(model.count, values.count)
    for index in 0..<common where !matches(model[index], values[index]) {
        model[index] = values[index]
    }
    if model.count != values.count {
        model.replaceSubrange(common..<model.count, with: values[common...])
    }
}

/// Reconcile plain descriptors before allocating bridge rows. Unchanged common
/// rows stay untouched, changed common rows use the model subscript (and emit
/// dataChanged), and only the changed tail is inserted or removed.
@MainActor
func syncModel<Value: Equatable, Element: QVariantGettable>(
    _ model: QListModel<Element>, previous: inout [Value], _ values: [Value],
    makeRow: (Value) -> Element
) {
    let common = min(model.count, values.count)
    for index in 0..<common
    where index >= previous.count || previous[index] != values[index] {
        model[index] = makeRow(values[index])
    }
    if model.count != values.count {
        model.replaceSubrange(common..<model.count, with: values[common...].map(makeRow))
    }
    previous = values
}
