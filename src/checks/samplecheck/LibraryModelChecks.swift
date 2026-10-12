import Foundation
import PorydawApp
import PorydawAppPresentation

@testable import SwiftCoreCheckLogic

@MainActor
internal func runLibraryModelChecks(_ report: CheckReport) {
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
        let model = SampleLibraryModel(preferences: preferences)
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
            message: "first saved root is selected, expanded and has an absolute-path tooltip")
        let initialRows = (0..<model.folders.count).map { (index: Int) in
            let row = model.folders[index]
            return "\(index):\(row.path) depth=\(row.depth) selected=\(row.selected) children=\(row.hasChildren)"
        }
        roots.expect(
            model.folders[1].path == child.standardizedFileURL.path && model.folders[1].depth == 1
                && !model.folders[1].selected && model.folders[1].hasChildren
                && !model.folders[2].hasChildren
                && model.folders[2].path == empty.path && model.folders[3].path == missing.path,
            message: "children under root in bookmark order; "
                + "expected paths \([library.path, child.standardizedFileURL.path, empty.path, missing.path]), "
                + "actual \(initialRows)")
        if linkedDirectory {
            let paths = (0..<model.folders.count).map { (row: Int) in model.folders[row].path }
            roots.expect(
                !paths.contains(library.appendingPathComponent("linked").path),
                message: "directory symlinks cannot escape the bookmarked tree")
        }
        let persisted = SampleLibraryModel(preferences: PreferencesStore())
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
            model.filesVisible && !model.canLoad && !model.canPreview && model.canRemove
                && model.statusText == "No file selected." && model.statusToolTip.isEmpty,
            message: "populated folder starts with silent, unselected audio list")
        guard model.files.count >= 2 else {
            listing.expect(false, message: "the audio list needs two selectable sources")
            return
        }

        var previewPaths: [String] = []
        var loadedPaths: [String] = []
        var stops = 0
        var opens = 0
        model.onPreviewRequested = { previewPaths.append($0) }
        model.onPreviewStopRequested = { stops += 1 }
        model.onLoadRequested = { loadedPaths.append($0) }
        model.onOpenFileRequested = { opens += 1 }
        let actions = report.scoped(cppID: "swiftcore/SampleLibraryModel::actions")
        model.showMessage(text: "Audio is unavailable.")
        model.selectFile(row: 0)
        let first = model.files[0].path
        actions.expect(
            previewPaths.isEmpty && loadedPaths.isEmpty && model.files[0].selected
                && model.statusText == "Selected: \(model.files[0].name)" && model.statusToolTip == first
                && model.canLoad && model.canPreview,
            message: "keyboard selection clears an error and enables actions without auditioning or loading")
        model.showMessage(text: "Cannot read source.")
        actions.expect(
            model.statusText == "Cannot read source." && model.statusToolTip == first,
            message: "an error overrides selected status without losing the selected-path tooltip")
        model.selectFile(row: 0)
        actions.expect(
            model.statusText.hasPrefix("Selected: ") && previewPaths.isEmpty,
            message: "reselecting clears an error but remains silent")
        model.togglePreview()
        actions.expect(previewPaths == [first], message: "preview starts from the selected absolute path")
        model.setPreviewingPath(path: first)
        actions.expect(
            model.previewText == "Preview source: \(URL(fileURLWithPath: first).lastPathComponent)"
                && model.previewToolTip == first && model.previewButtonLabel == "Stop Preview",
            message: "active preview path, tooltip and button label describe the sounding source")
        model.selectFile(row: 1)
        actions.expect(
            previewPaths == [first] && stops == 0 && model.previewToolTip == first,
            message: "moving selection while previewing does not audition or stop the active source")
        model.clickFile(row: 1)
        let second = model.files[1].path
        actions.expect(
            previewPaths == [first, second] && stops == 0 && model.files[1].selected,
            message: "pointer click requests a replacement preview while another preview is active")
        model.togglePreview()
        actions.expect(
            stops == 1 && model.canPreview, message: "active preview toggles stop without losing file selection")
        model.activateFile(row: 1)
        model.loadSelected()
        actions.expect(
            loadedPaths == [second, second] && previewPaths.count == 2,
            message: "activation and Load request the selected source without auditioning")
        model.requestOpenFile()
        actions.expect(opens == 1, message: "Open File dispatches its action")
        model.showMessage(text: "Cannot read source.")
        model.setLoadedPath(path: second)
        actions.expect(
            model.loadedText == "Loaded: \(URL(fileURLWithPath: second).lastPathComponent)"
                && model.loadedToolTip == second && model.statusText.hasPrefix("Selected: "),
            message: "loaded readout has its own path and a successful load clears the old error")
        model.clearFileSelection()
        actions.expect(
            model.statusText == "No file selected." && model.statusToolTip.isEmpty
                && !model.canLoad && model.canPreview && model.previewButtonLabel == "Stop Preview",
            message: "clearing selection recomputes status without clearing an active preview")
        model.setPreviewingPath(path: "")
        actions.expect(
            model.previewText == "Preview source: none" && model.previewToolTip.isEmpty
                && model.previewButtonLabel == "Preview" && !model.canPreview,
            message: "stopped preview resets its readout and disables Preview without selection")
        model.setLoadedPath(path: "")
        actions.expect(
            model.loadedText == "Loaded: none" && model.loadedToolTip.isEmpty,
            message: "clearing the loaded path resets its independent readout")

        let navigation = report.scoped(cppID: "swiftcore/SampleLibraryModel::navigation")
        model.selectFolder(row: 1)
        guard model.folders.count >= 7 else {
            navigation.expect(false, message: "expanding a nested folder must reveal its child")
            return
        }
        navigation.expect(
            model.folders[1].selected && model.folders[1].expanded && model.folders[2].depth == 2
                && model.files.count == 0 && model.statusText == "No supported audio files in this folder."
                && !model.canLoad,
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
        let expectedPaths = [alpha, nested, zulu].map { $0.standardizedFileURL.path }
        navigation.expect(
            expandedPaths == expectedPaths
                && model.folders[2].depth == 2,
            message: "re-expanding restores cached child directories in case-insensitive name order; "
                + "expected \(expectedPaths), actual \(expandedPaths), first depth \(model.folders[2].depth)")
        model.showMessage(text: "Temporary problem")
        model.selectFolder(row: 5)
        navigation.expect(
            model.statusText == "No supported audio files in this folder."
                && model.folders[5].selected && !model.canLoad
                && previewPaths == [first, second] && loadedPaths == [second, second],
            message: "folder selection clears a transient error without emitting audio callbacks")
        model.selectFolder(row: 6)
        navigation.expect(
            !model.filesVisible && model.statusText == "Library folder is missing: \(missing.path)"
                && model.canRemove && model.files.count == 0,
            message: "missing saved bookmark remains selectable but hides the audio list")
        model.showMessage(text: "Read failed")
        navigation.expect(
            model.statusText == "Read failed", message: "transient message overrides missing-folder state")
        model.showMessage(text: "")
        navigation.expect(
            model.statusText == "Library folder is missing: \(missing.path)",
            message: "clearing the message restores the derived missing-folder status")

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
                && model.statusText == "No library folders. Add a folder or open a file."
                && preferences.strings("sampleLibraryFolders") == [],
            message: "removing all bookmarks hides the list and restores the no-folders status")
        model.showMessage(text: "Temporary problem")
        model.clearFileSelection()
        removal.expect(model.statusText == "Temporary problem", message: "clearing selection does not erase a message")
        model.showMessage(text: "")
        removal.expect(
            model.statusText == "No library folders. Add a folder or open a file.",
            message: "empty-bookmark status wins after a message is cleared")
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
                && model.statusText == "No supported audio files in this folder.",
            message: "plain paths append and select the chosen root; expected \(empty.path), "
                + "actual \(model.folders[2].path), selected \(model.folders[2].selected), "
                + "status \(model.statusText)")
        model.addFolder(path: library.path)
        model.addFolder(path: "  ")
        removal.expect(
            model.folders.count == 3 && model.folders[0].selected
                && preferences.strings("sampleLibraryFolders") == [library.path, empty.path],
            message: "duplicate or blank additions do not create duplicate bookmarks")
        let fresh = SampleLibraryModel(preferences: PreferencesStore())
        guard fresh.folders.count >= 3 else {
            removal.expect(false, message: "saved bookmarks must survive model recreation")
            return
        }
        removal.expect(
            fresh.folders[0].path == library.path && fresh.folders[2].path == empty.path,
            message: "mutated bookmark order persists across new model instances")
    } catch {
        report.scoped(cppID: "swiftcore/SampleLibraryModel::fixture").expect(
            false, message: "library fixture could not be created: \(error)")
    }
}
