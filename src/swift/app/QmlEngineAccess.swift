import PorydawBankLease
import QtBridge
import QtBridgeCpp

@MainActor
public enum QmlEngineAccess {
    public static var isAvailable: Bool { pd_qml_engine() != nil }
    nonisolated public static var moduleResourcePrefix: String {
        String(cString: pd_qml_module_prefix())
    }

    public static func addImportPath(_ path: String) -> Bool {
        pd_qml_add_import_path(path)
    }
}
