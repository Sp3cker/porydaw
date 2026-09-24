import PorydawBankLease
import QtBridge
import QtBridgeCpp

@MainActor
public enum QmlEngineAccess {
    // The running QQmlApplicationEngine while QAppCpp::run() is in exec();
    // nil before the root document loads and after shutdown. C++ callers
    // can use pd_qml_engine() directly for the raw pointer.
    public static var isAvailable: Bool { pd_qml_engine() != nil }

    public static func addImportPath(_ path: String) -> Bool {
        pd_qml_add_import_path(path)
    }

    public static func setContextProperty(_ name: String, _ value: QtBridge.QVariant) -> Bool {
        pd_qml_set_context_property(name, value.cppVariant())
    }

    public static func clearComponentCache() -> Bool {
        pd_qml_clear_component_cache()
    }
}
