import Foundation
import NativeGridSmoke
import NativeGridWindowCancel
import QtBridge

@main
struct SwiftGridApp: QApp {
    let qmlFileName: String = "Main"

    let gridModel = PianoGrid()

    var initialProperties: [String: QObjectBuildable] {
        ["gridModel": gridModel]
    }

    init() {
        runMathSelftestIfRequested()
        sgw_installWindowCancelFilter()
        installGridSmoke()
    }
}
