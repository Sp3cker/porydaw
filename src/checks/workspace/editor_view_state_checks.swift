import Foundation
import CoreFoundation
import PorydawApp
import PorydawCoreCheckNative

@MainActor
func runEditorViewStateChecks(_ report: CheckReport) {
    let codec = "workspace/EditorViewStateCodec::laneBlob"
    let defaults = EditorViewStateCodec.decodeLanes(Data())
    report.expectEqual(expected: EditorLaneState(), actual: defaults, cppID: codec,
                       what: "empty lane blob defaults without touching drawer chrome")
    for malformed in ["not JSON", "[]", "null", "\"text\""] {
        report.expectEqual(expected: EditorLaneState(),
                           actual: EditorViewStateCodec.decodeLanes(Data(malformed.utf8)),
                           cppID: codec, what: "non-object or invalid JSON defaults lane fields")
    }

    let minimum = Int((AutomationPagePolicy.seedBaseFontPx * 7 / 3).rounded())
    let maximum = Int((AutomationPagePolicy.seedBaseFontPx * 32 / 3).rounded())
    let source = """
    {"laneHeight":5,"laneHeights":{"tempo":\(minimum + 2),"cc:0:74":5,"cc:0:80":99999999,
     "cc:00:7":12,"voice:0:5":12,"cc:16:7":12,"cc:0:300":12},
     "laneRanges":{"tempo":90,"cc:1:7":64,"cc:2:3":128,"cc:3:4":-1},
     "emptyLanes":[{"track":0,"cc":1},{"track":16,"cc":1},{"track":2,"cc":300},"bad"],
     "hiddenLanes":[{"track":1,"cc":7},{"track":0,"cc":74},{"track":1,"cc":7}],
     "unheardOf":true}
    """
    let decoded = EditorViewStateCodec.decodeLanes(Data(source.utf8))
    report.expectEqual(expected: minimum, actual: decoded.laneHeight, cppID: codec,
                       what: "stored lane height clamps to font-derived floor")
    report.expectEqual(expected: ["tempo": minimum + 2, "cc:0:74": minimum, "cc:0:80": maximum],
                       actual: decoded.laneHeights, cppID: codec,
                       what: "row heights clamp at both bounds and reject bad grammar")
    report.expectEqual(expected: ["tempo": 90, "cc:1:7": 64], actual: decoded.laneRanges,
                       cppID: codec, what: "valid ranges survive and out-of-range values drop")
    report.expectEqual(expected: 0,
                       actual: EditorViewStateCodec.decodeLanes(Data("{\"laneHeight\":0}".utf8)).laneHeight,
                       cppID: codec, what: "zero lane height keeps the layout default")
    report.expectEqual(expected: maximum,
                       actual: EditorViewStateCodec.decodeLanes(Data("{\"laneHeight\":99999999}".utf8))
                           .laneHeight, cppID: codec,
                       what: "large lane height clamps to font-derived ceiling")
    report.expectEqual(expected: Set([EditorLaneState.Lane(track: 0, controller: 1)]),
                       actual: decoded.emptyLanes, cppID: codec,
                       what: "invalid and repeated empty lanes do not create extra lanes")
    report.expectEqual(expected: [.init(track: 1, controller: 7), .init(track: 0, controller: 74)],
                       actual: decoded.hiddenLanes, cppID: codec,
                       what: "hidden-lane order survives without duplicates")
    if let encoded = EditorViewStateCodec.encodeLanes(decoded) {
        report.expect(!encoded.contains(10), cppID: codec,
                      message: "the saved lane blob is compact JSON without line breaks")
        report.expectEqual(expected: decoded, actual: EditorViewStateCodec.decodeLanes(encoded), cppID: codec,
                           what: "canonical lane blob round-trips every supported member")
    } else {
        report.fail(codec, "valid lane state must encode")
    }

    let order = "workspace/WorkspaceTabRecipe::restore"
    let recipe = WorkspaceTabRecipe(projectPath: "/music", orderedSongs: ["A", "gone", "B", "A"],
                                    selectedSong: "gone")
    report.expectEqual(expected: ["A", "B"], actual: recipe.normalized(available: ["A", "B"]).orderedSongs,
                       cppID: order, what: "missing and repeated songs are skipped in strip order")
    report.expectEqual(expected: "A", actual: recipe.normalized(available: ["A", "B"]).selectedSong,
                       cppID: order, what: "missing selection chooses first restored song")

    func cfString(_ text: String) -> CFString {
        guard let value = text.withCString({
            CFStringCreateWithCString(kCFAllocatorDefault, $0, CFStringBuiltInEncodings.UTF8.rawValue)
        }) else { preconditionFailure("Settings test key could not be encoded") }
        return value
    }
    let domainName = "workspace-codec-check-\(UUID().uuidString)"
    let domainID = cfString("com.sp3cker." + domainName)
    defer {
        for key in ["lastProjectDir", "lastOpenSongs", "lastSongLabel",
                    "editorDrawer.automationLanes"] {
            CFPreferencesSetAppValue(cfString(key), nil, domainID)
        }
        _ = CFPreferencesAppSynchronize(domainID)
    }
    let restored = recipe.normalized(available: ["A", "B"])
    EditorViewStateCodec.saveTabs(restored, applicationName: domainName)
    report.expectEqual(expected: restored, actual: EditorViewStateCodec.loadTabs(applicationName: domainName),
                       cppID: order, what: "application preferences retain tab order and selection")
    EditorViewStateCodec.saveLanes(decoded, applicationName: domainName)
    report.expectEqual(expected: decoded, actual: EditorViewStateCodec.loadLanes(applicationName: domainName),
                       cppID: codec, what: "application preferences retain one lane blob")
}
