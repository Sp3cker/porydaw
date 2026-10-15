import Foundation
import PorydawAppAudio
@testable import PorydawSampleUI
import PorydawAppPresentation
import PorydawSample

@testable import SwiftCoreCheckLogic

@MainActor
private final class AcceptingAuditionOutput: SampleAuditionOutput {
    func auditionSample(
        samples: [Int8], frequency: UInt32, loopStart: UInt32,
        looped: Bool, key: UInt8, adsr: AudioADSR, toneKey: UInt8
    ) -> Bool { true }
    func auditionSampleOff() {}
}

@MainActor
internal func runLibraryModelChecks(_ report: CheckReport) {
    let output = AcceptingAuditionOutput()
    func makeModel(_ preferences: PreferencesStore) -> SampleLibraryModel {
        SampleLibraryModel(
            preferences: preferences, palette: GridPalette(), lane: SampleAuditionArbiter(output: output))
    }
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let library = base.appendingPathComponent("Library Ω", isDirectory: true)
    let empty = base.appendingPathComponent("Empty", isDirectory: true)
    let child = library.appendingPathComponent("Subfolder", isDirectory: true)
    let nested = child.appendingPathComponent("Nested", isDirectory: true)
    let alpha = child.appendingPathComponent("alpha", isDirectory: true)
    let zulu = child.appendingPathComponent("Zulu", isDirectory: true)
    let hidden = library.appendingPathComponent(".hidden", isDirectory: true)
    let missing = base.appendingPathComponent("Missing", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: base) }

    do {
        for directory in [library, empty, nested, alpha, zulu, hidden] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        for name in [
            "tone.wav", "tone.AIF", "tone.aiff", "tone.MP3", "tone.flac", "tone.ogg",
            "notes.txt", "font.sf2", ".concealed.wav",
        ] {
            try Data([0x12]).write(to: library.appendingPathComponent(name))
        }
        try Data([0x34]).write(to: hidden.appendingPathComponent("secret.wav"))
        var linkedDirectory = false
        do {
            try FileManager.default.createSymbolicLink(
                at: library.appendingPathComponent("linked"), withDestinationURL: empty)
            linkedDirectory = true
        } catch {
            // The filesystem may disallow links; the non-symlink tree checks still run.
        }

        PreferencesStore.stageShared(plistPath: base.appendingPathComponent("settings.plist").path)
        let preferences = PreferencesStore()
        preferences.setStrings(
            "sampleLibraryFolders",
            [
                "   ", library.appendingPathComponent(".").path, library.path,
                child.appendingPathComponent("..").path, empty.path, missing.path,
            ])
        preferences.synchronize()
        let model = makeModel(preferences)
        let roots = report.scoped(cppID: "swiftcore/SampleLibraryModel::roots")
        guard model.folders.count >= 4 else {
            roots.expect(false, message: "saved roots and first child must be available as tree rows")
            return
        }
        roots.expect(
            preferences.strings("sampleLibraryFolders") == [library.path, empty.path, missing.path],
            message: "initial preferences normalize dot paths, deduplicate and discard empty bookmarks")
        roots.expect(
            model.folders.count == 4 && model.folders[0].path == library.path
                && model.folders[0].title == "Library Ω" && model.folders[0].depth == 0
                && model.folders[0].selected && model.folders[0].expanded
                && model.folders[0].hasChildren,
            message: "first saved root is selected and expanded")
        let initialRows = (0..<model.folders.count).map { (index: Int) in
            let row = model.folders[index]
            return "\(index):\(row.path) depth=\(row.depth) selected=\(row.selected) children=\(row.hasChildren)"
        }
        roots.expect(
            model.folders[1].path == child.path && model.folders[1].depth == 1
                && !model.folders[1].selected && model.folders[1].hasChildren
                && !model.folders[2].hasChildren
                && model.folders[2].path == empty.path && model.folders[3].path == missing.path,
            message: "children under root in bookmark order; "
                + "expected paths \([library.path, child.path, empty.path, missing.path]), "
                + "actual \(initialRows)")
        if linkedDirectory {
            let paths = (0..<model.folders.count).map { (row: Int) in model.folders[row].path }
            roots.expect(
                !paths.contains(library.appendingPathComponent("linked").path),
                message: "directory symlinks cannot escape the bookmarked tree")
        }
        let persisted = makeModel(PreferencesStore())
        roots.expect(
            persisted.folders.count == model.folders.count && persisted.folders[0].path == library.path,
            message: "a fresh model reads synchronized saved bookmarks")

        let listing = report.scoped(cppID: "swiftcore/SampleLibraryModel::audioList")
        let names = (0..<model.files.count).map { (row: Int) in model.files[row].name }
        listing.expect(
            Set(names) == Set(["tone.wav", "tone.AIF", "tone.aiff", "tone.MP3", "tone.flac", "tone.ogg"])
                && names.count == 6,
            message: "six case-insensitive audio extensions list; hidden entries, SF2, text and directories do not")
        listing.expect(
            names
                == names.sorted { (lhs: String, rhs: String) -> Bool in
                    lhs.compare(rhs, options: .caseInsensitive) == .orderedAscending
                },
            message: "audio names appear in case-insensitive name order")
        listing.expect(
            model.filesVisible && model.canRemove && model.statusText.isEmpty
                && (0..<model.files.count).allSatisfy { (row: Int) -> Bool in !model.files[row].selected },
            message: "populated folder starts with a silent, unselected audio list")
        guard model.files.count >= 2 else {
            listing.expect(false, message: "the audio list needs two selectable sources")
            return
        }

        let actions = report.scoped(cppID: "swiftcore/SampleLibraryModel::selectionState")
        model.selectFile(row: 0)
        let first = model.files[0].path
        actions.expect(
            model.files[0].selected && !model.files[1].selected && model.statusText.isEmpty,
            message: "file selection highlights exactly its row without a failure readout")
        var previewed: [String] = []
        model.onPreviewRequested = { (path: String) in previewed.append(path) }
        model.clickFile(row: 1)
        let second = model.files[1].path
        actions.expect(
            !model.files[0].selected && model.files[1].selected && previewed == [second],
            message: "clicking a file selects its row and requests its preview")
        var loaded: [String] = []
        model.onLoadRequested = { (path: String) in loaded.append(path) }
        model.activateFile(row: 0)
        actions.expect(
            model.files[0].selected && loaded == [first],
            message: "double-click loads the activated file")
        var stopped = 0
        model.onPreviewStopRequested = { stopped += 1 }
        model.setPreviewingPath(path: first)
        model.togglePreview()
        actions.expect(
            stopped == 1 && previewed == [second],
            message: "toggling while previewing stops it instead of starting another")
        model.setPreviewingPath(path: "")
        model.togglePreview()
        actions.expect(
            previewed == [second, first],
            message: "toggling with a selection and no active preview requests it")
        model.clearFileSelection()
        actions.expect(
            !model.files[0].selected && !model.files[1].selected,
            message: "clearing selection unhighlights every row")

        let strip = report.scoped(cppID: "swiftcore/SampleLibraryModel::previewStrip")
        model.preview.setViewport(width: 40, height: 20)
        let blank = model.preview.displayList(list: 0)
        model.selectFile(row: 0)
        var tone = ProcessedSample()
        tone.s8 = [0, 64, -64, 32, -32, 0, 16, -16]
        tone.freq = 8 * 1024
        model.playPreview(tone, path: model.files[0].path, key: 60, toneKey: 60)
        strip.expect(
            model.previewing && model.preview.displayList(list: 0) != blank,
            message: "a sounding preview draws its waveform and reports previewing")
        model.previewPlayer.advance(bySeconds: 2)
        strip.expect(
            !model.previewing && model.preview.displayList(list: 0) != blank,
            message: "a preview sounds once; its end clears previewing but keeps the waveform")
        model.selectFile(row: 1)
        strip.expect(
            model.preview.displayList(list: 0) == blank,
            message: "selecting another file clears the previewed waveform")

        let failures = report.scoped(cppID: "swiftcore/SampleLibraryModel::failureStatus")
        model.showMessage(text: "Cannot read tone.wav.")
        failures.expect(
            model.statusText == "Cannot read tone.wav.",
            message: "a load failure reaches the failure readout")
        model.selectFile(row: 0)
        failures.expect(
            model.statusText.isEmpty,
            message: "selecting a file clears the failure readout")

        let navigation = report.scoped(cppID: "swiftcore/SampleLibraryModel::navigation")
        model.selectFolder(row: 1)
        guard model.folders.count >= 7 else {
            navigation.expect(false, message: "expanding a nested folder must reveal its child")
            return
        }
        navigation.expect(
            model.folders[1].selected && model.folders[1].expanded && model.folders[2].depth == 2
                && model.files.count == 0,
            message: "selecting a child expands its lazy descendants and navigates to an empty audio list")
        model.toggleFolder(row: 1)
        navigation.expect(
            !model.folders[1].expanded && model.folders.count == 4,
            message: "collapse hides cached grandchildren without changing selection")
        model.toggleFolder(row: 1)
        guard model.folders.count >= 7 else {
            navigation.expect(false, message: "re-expansion must restore the cached child")
            return
        }
        let expandedPaths = [model.folders[2].path, model.folders[3].path, model.folders[4].path]
        let expectedPaths = [alpha.path, nested.path, zulu.path]
        navigation.expect(
            expandedPaths == expectedPaths
                && model.folders[2].depth == 2,
            message: "re-expanding restores cached child directories in case-insensitive name order; "
                + "expected \(expectedPaths), actual \(expandedPaths), first depth \(model.folders[2].depth)")
        model.selectFolder(row: 5)
        navigation.expect(
            model.folders[5].selected && model.files.count == 0,
            message: "selecting an empty folder leaves no source load target")
        model.selectFolder(row: 6)
        navigation.expect(
            !model.filesVisible
                && model.canRemove && model.files.count == 0,
            message: "missing saved bookmark remains selectable but hides the audio list")

        let removal = report.scoped(cppID: "swiftcore/SampleLibraryModel::bookmarkRemoval")
        model.selectFolder(row: 1)
        model.removeSelectedRoot()
        guard model.folders.count >= 2 else {
            removal.expect(false, message: "removal must retain the remaining bookmarks")
            return
        }
        removal.expect(
            FileManager.default.fileExists(atPath: library.appendingPathComponent("tone.wav").path)
                && model.folders[0].path == empty.path && model.folders[0].selected
                && preferences.strings("sampleLibraryFolders") == [empty.path, missing.path],
            message: "removing a selected descendant removes only its root bookmark and selects the next first root")
        model.removeSelectedRoot()
        model.removeSelectedRoot()
        removal.expect(
            model.folders.count == 0 && !model.canRemove && !model.filesVisible
                && preferences.strings("sampleLibraryFolders") == [],
            message: "removing all bookmarks hides the list and persists an empty bookmark set")
        model.addFolder(path: library.absoluteString)
        guard model.folders.count >= 1 else {
            removal.expect(false, message: "a file URL must add a navigable bookmark")
            return
        }
        removal.expect(
            model.folders[0].path == library.path && model.folders[0].selected,
            message: "a file URL decodes spaces and Unicode before selecting its new root")
        model.addFolder(path: empty.path)
        guard model.folders.count >= 3 else {
            removal.expect(false, message: "plain paths must append a second bookmark")
            return
        }
        removal.expect(
            model.folders[2].path == empty.path && model.folders[2].selected
                && model.files.count == 0,
            message: "plain paths append and select the chosen root; expected \(empty.path), "
                + "actual \(model.folders[2].path), selected \(model.folders[2].selected), "
                + "status \(model.statusText)")
        model.addFolder(path: library.path)
        model.addFolder(path: "  ")
        removal.expect(
            model.folders.count == 3 && model.folders[0].selected
                && preferences.strings("sampleLibraryFolders") == [library.path, empty.path],
            message: "duplicate or blank additions do not create duplicate bookmarks")
        let fresh = makeModel(PreferencesStore())
        guard fresh.folders.count >= 3 else {
            removal.expect(false, message: "saved bookmarks must survive model recreation")
            return
        }
        removal.expect(
            fresh.folders[0].path == library.path && fresh.folders[2].path == empty.path,
            message: "mutated bookmark order persists across new model instances")
        if linkedDirectory {
            let alias = base.appendingPathComponent("Library alias", isDirectory: true)
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: library)
            preferences.setStrings(
                "sampleLibraryFolders",
                [alias.path, alias.appendingPathComponent("Subfolder/..").path, library.path])
            let aliased = makeModel(preferences)
            roots.expect(
                preferences.strings("sampleLibraryFolders") == [alias.path, library.path]
                    && aliased.folders.count == 3 && aliased.folders[0].path == alias.path
                    && aliased.folders[1].path == alias.appendingPathComponent("Subfolder").path
                    && aliased.folders[2].path == library.path,
                message: "lexical dot cleanup preserves an explicit symlink root distinct from its target")
            roots.expect(
                aliased.files.count == 6
                    && (0..<aliased.files.count).allSatisfy { (row: Int) -> Bool in
                        aliased.files[row].path.hasPrefix(alias.path + "/")
                    },
                message: "file identities preserve the bookmarked symlink path")
        }
    } catch {
        report.scoped(cppID: "swiftcore/SampleLibraryModel::fixture").expect(
            false, message: "library fixture could not be created: \(error)")
    }
}
