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
