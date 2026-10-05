import Foundation
import PorydawDocument
import PorydawProject

extension EditorViewStateCodec {
    private static let lanesKey = "editorDrawer.automationLanes"
    private static let chromePrefix = "editorDrawer."

    @MainActor
    public static func load(store: PreferencesStore) -> EditorViewState {
        var state = EditorViewState()
        state.chrome = loadChrome(store: store)
        state.lanes = loadLanes(store: store)
        return state
    }

    @MainActor
    public static func save(_ state: EditorViewState, store: PreferencesStore) {
        writeChrome(state.chrome, store: store)
        writeLanes(state.lanes, store: store)
        store.synchronize()
    }

    @MainActor
    public static func loadChrome(store: PreferencesStore) -> EditorDrawerChromeState {
        var state = EditorDrawerChromeState()
        state.velocity = loadSection("velocity", defaultVisible: state.velocity.visible, store: store)
        state.automation = loadSection("automation", defaultVisible: state.automation.visible, store: store)
        state.voiceChanges = loadSection("voiceChanges", defaultVisible: state.voiceChanges.visible, store: store)
        switch store.string(key: chromePrefix + "activePage", fallback: "") {
        case "velocity": state.activePage = .velocity
        case "voiceChanges": state.activePage = .voiceChanges
        case "automations": state.activePage = .automation
        default: break
        }
        return state
    }

    @MainActor
    private static func loadSection(
        _ name: String, defaultVisible: Bool,
        store: PreferencesStore
    ) -> DrawerChromeSection {
        DrawerChromeSection(
            visible: store.storedBool(key: chromePrefix + name + "Visible") ?? defaultVisible,
            height: store.storedPositiveInt(key: chromePrefix + name + "Height"))
    }

    @MainActor
    public static func saveChrome(_ state: EditorDrawerChromeState, store: PreferencesStore) {
        writeChrome(state, store: store)
        store.synchronize()
    }

    @MainActor
    private static func writeChrome(_ state: EditorDrawerChromeState, store: PreferencesStore) {
        for (name, section) in [
            ("velocity", state.velocity),
            ("automation", state.automation),
            ("voiceChanges", state.voiceChanges),
        ] {
            store.setBool(key: chromePrefix + name + "Visible", value: section.visible)
            let heightKey = chromePrefix + name + "Height"
            if let height = section.height, height > 0 {
                store.setInt(key: heightKey, value: height)
            } else {
                store.remove(key: heightKey)
            }
        }
        store.setString(key: chromePrefix + "activePage", value: state.activePage.name)
    }

    @MainActor
    public static func loadTabs(store: PreferencesStore) -> WorkspaceTabRecipe {
        let selected = store.string(key: "lastSongLabel", fallback: "")
        let saved = normalizeSavedRecipe(
            projectPath: store.string(key: "lastProjectDir", fallback: ""),
            labels: store.strings("lastOpenSongs") ?? [], selected: selected)
        return WorkspaceTabRecipe(
            projectPath: saved.projectPath,
            orderedSongs: saved.orderedSongs.map(\.value),
            selectedSong: saved.selected?.value ?? "")
    }

    @MainActor
    public static func saveTabs(_ recipe: WorkspaceTabRecipe, store: PreferencesStore) {
        store.setString(key: "lastProjectDir", value: recipe.projectPath)
        store.setStrings("lastOpenSongs", recipe.orderedSongs.isEmpty ? nil : recipe.orderedSongs)
        if recipe.orderedSongs.isEmpty {
            store.remove(key: "lastSongLabel")
        } else {
            store.setString(key: "lastSongLabel", value: recipe.selectedSong)
        }
        store.synchronize()
    }

    @MainActor
    public static func loadLanes(store: PreferencesStore) -> EditorLaneState {
        guard let bytes = store.data(lanesKey) else { return EditorLaneState() }
        return decodeLanes(bytes)
    }

    @MainActor
    public static func saveLanes(_ state: EditorLaneState, store: PreferencesStore) {
        writeLanes(state, store: store)
        store.synchronize()
    }

    @MainActor
    private static func writeLanes(_ state: EditorLaneState, store: PreferencesStore) {
        guard let bytes = encodeLanes(state) else { return }
        store.setData(lanesKey, bytes)
    }
}
