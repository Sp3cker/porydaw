import Foundation
import QtBridge

@main
struct ___PACKAGENAME:identifier___: QApp {
    let qmlFileName: String = "___VARIABLE_qmlFileName:identifier___"
    var initialProperties: [String : QtBridge.QObjectBuildable] = [
        "___VARIABLE_modelContextName:identifier___" : ___VARIABLE_modelName:identifier___()
    ]
}
