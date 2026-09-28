import Foundation
import PorydawCore
import QtBridge

func sceneTextDictSignature(_ dict: [String: QVariantSettable]) -> String {
    var parts: [String] = []
    parts.reserveCapacity(dict.count)
    for key in dict.keys.sorted() {
        let value = dict[key].map { "\($0)" } ?? ""
        parts.append("\(key)=\(value)")
    }
    return parts.joined(separator: ",")
}

@MainActor
extension GridScene {

    func syncText(
        _ model: QListModel<SceneText>, _ records: [SceneText],
        signatures: inout [String]
    ) {
        let next = records.map(\.signature)
        guard next != signatures else { return }
        model.update {
            let common = min(model.count, records.count)
            for i in 0..<common where signatures[i] != next[i] {
                model[i] = records[i]
            }
            if model.count > records.count {
                model.replaceSubrange(records.count..<model.count, with: [])
            } else if records.count > model.count {
                model.replaceSubrange(
                    model.count..<model.count, with: records[model.count...])
            }
        }
        signatures = next
    }

    func sync(_ model: QListModel<SceneRect>, _ rects: [SceneRect]) {
        model.update {
            let common = min(model.count, rects.count)
            for i in 0..<common where !model[i].matches(rects[i]) {
                model[i] = rects[i]
            }
            if model.count > rects.count {
                model.replaceSubrange(rects.count..<model.count, with: [])
            } else if rects.count > model.count {
                model.replaceSubrange(
                    model.count..<model.count,
                    with: rects[model.count...])
            }
        }
    }

    static func timeCovers(_ input: GridSceneInput, track: Int, tick: Int, end: Int) -> Bool {
        guard let selection = input.timeSelection, selection.isActive else { return false }
        guard case let .tracks(scope) = selection.scope else { return false }
        guard scope.contains(track), track >= 0, track < input.usedTrackCount else { return false }
        return Int(selection.range.startTick) < end && Int(selection.range.endTick) > tick
    }
}
