import QtBridge

/// Publish changed rows without resetting model identity or rewriting matches;
/// a shared prefix and suffix stay put, so one inserted row moves no delegate.
@MainActor
func syncModel<Element: QVariantGettable>(
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
