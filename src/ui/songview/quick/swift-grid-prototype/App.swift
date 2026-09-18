import Foundation
import NativeGridSmoke
import QtBridge

@main
struct SwiftGridApp: QApp {
    let qmlFileName: String = "Main"

    let gridModel = PianoGrid()

    var initialProperties: [String: QObjectBuildable] {
        ["gridModel": gridModel]
    }

    init() {
        installGridSmoke()
    }
}
