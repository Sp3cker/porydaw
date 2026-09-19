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

    var initialProperties: [String: QObjectBuildable] {
        ["songTabs": songTabs]
    }

    init() {
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
