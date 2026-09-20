import Foundation
import NativeGridSmoke
import NativeGridWindowCancel
import QtBridge

private func deliverWindowCancel(_ reason: Int32, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let songTabs = Unmanaged<SongTabsController>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        songTabs.selectedGrid?.inputCancelled(reason: Int(reason))
    }
}

@main
struct SwiftGridApp: QApp {
    let qmlFileName: String = "Main"

    let songTabs = SongTabsController()
    let widgetInterop = WidgetInteropController()
    let newSongWizard: NewSongWizardController
    let newSongResult: NewSongDemoResult

    var initialProperties: [String: QObjectBuildable] {
        [
            "songTabs": songTabs, "widgetInterop": widgetInterop,
            "newSongWizard": newSongWizard, "newSongResult": newSongResult,
        ]
    }

    init() {
        let result = NewSongDemoResult()
        newSongResult = result
        newSongWizard = NewSongWizardController(catalog: newSongDemoCatalog()) {
            result.record($0)
        }
        runMathSelftestIfRequested()
        runPolicySelftestIfRequested()
        let initialTabId = songTabs.selectedId
        songTabs.openTab()
        songTabs.openTab()
        songTabs.selectTab(tabId: initialTabId)
        // Demo-lane machinery (charter demo-lane row): seeds fixture grids;
        // retires with the standalone lane's gate.
        for grid in songTabs.grids {
            grid.audio.initializeDemo()
            grid.resetDemo()
        }
        sgw_installWindowCancelHost(
            deliverWindowCancel, Unmanaged.passUnretained(songTabs).toOpaque())
        installGridSmoke()
    }
}
