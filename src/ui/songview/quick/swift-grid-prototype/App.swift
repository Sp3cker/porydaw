import Foundation
import NativeGridSmoke
import NativeGridWindowCancel
import QtBridge

private func deliverWindowCancel(_ reason: Int32, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let grid = Unmanaged<PianoGrid>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        grid.inputCancelled(reason: Int(reason))
    }
}

@main
struct SwiftGridApp: QApp {
    let qmlFileName: String = "Main"

    let gridModel = PianoGrid()

    var initialProperties: [String: QObjectBuildable] {
        ["gridModel": gridModel]
    }

    init() {
        runMathSelftestIfRequested()
        runPolicySelftestIfRequested()
        sgw_installWindowCancelHost(
            deliverWindowCancel, Unmanaged.passUnretained(gridModel).toOpaque())
        installGridSmoke()
    }
}
