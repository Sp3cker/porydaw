import CoreFoundation
import Foundation
import QtBridge

@MainActor
@QtBridgeable
public final class PreferencesStore: QmlInstantiableStatus {
    private static var applicationID = "com.sp3cker.porydaw"
    private static var isStaged = false
    private static var defaults = userDefaults(for: applicationID)

    public required init() {}
    public func componentComplete() {}

    public static func stageShared(plistPath: String) {
        precondition((plistPath as NSString).isAbsolutePath)
        let path = URL(fileURLWithPath: plistPath).standardizedFileURL.path
        if FileManager.default.fileExists(atPath: path) {
            do {
                try FileManager.default.removeItem(atPath: path)
            } catch {
                preconditionFailure("Could not clear staged preferences at \(path): \(error)")
            }
        }
        applicationID = path
        isStaged = true
        defaults = userDefaults(for: path)
        defaults.removePersistentDomain(forName: path)
        _ = defaults.synchronize()
    }

    public static func configureShared(applicationName: String) {
        guard !isStaged else { return }
        applicationID = "com.sp3cker." + applicationName
        defaults = userDefaults(for: applicationID)
    }

    private func value(_ key: String) -> Any? {
        let value = Self.defaults.object(forKey: key)
        if let text = value as? String, text == "@Invalid()" { return nil }
        return value
    }

    public func string(key: String, fallback: String) -> String {
        guard let value = value(key) else { return fallback }
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return fallback
    }

    public func int(key: String, fallback: Int) -> Int {
        guard let value = value(key) else { return fallback }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? fallback }
        return fallback
    }

    public func double(key: String, fallback: Double) -> Double {
        guard let value = value(key) else { return fallback }
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) ?? fallback }
        return fallback
    }

    public func bool(key: String, fallback: Bool) -> Bool {
        guard let value = value(key) else { return fallback }
        if let number = value as? NSNumber { return number.boolValue }
        if let text = value as? String {
            switch text.lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: return fallback
            }
        }
        return fallback
    }
    func storedBool(key: String) -> Bool? {
        guard let raw = value(key), CFGetTypeID(raw as CFTypeRef) == CFBooleanGetTypeID(),
            let number = raw as? NSNumber
        else { return nil }
        return number.boolValue
    }

    func storedPositiveInt(key: String) -> Int? {
        guard let raw = value(key), CFGetTypeID(raw as CFTypeRef) == CFNumberGetTypeID(),
            let number = raw as? NSNumber, number.intValue > 0,
            number.doubleValue == Double(number.intValue)
        else { return nil }
        return number.intValue
    }

    public func hasValue(key: String) -> Bool { value(key) != nil }

    public func setString(key: String, value: String) {
        set(key, value)
    }

    public func setInt(key: String, value: Int) {
        set(key, value)
    }

    public func setDouble(key: String, value: Double) {
        set(key, value)
    }

    public func setBool(key: String, value: Bool) {
        set(key, value)
    }

    public func remove(key: String) { set(key, nil) }

    public func resetPreferences() -> Bool {
        let defaults = Self.defaults
        guard defaults.synchronize(), let keys = Self.storedKeys() else { return false }
        for key in keys { defaults.removeObject(forKey: key) }
        return defaults.synchronize()
    }

    public func synchronize() { _ = Self.defaults.synchronize() }

    func strings(_ key: String) -> [String]? { value(key) as? [String] }

    func setStrings(_ key: String, _ strings: [String]?) {
        guard let strings else {
            remove(key: key)
            return
        }
        set(key, strings)
    }

    func data(_ key: String) -> Data? { value(key) as? Data }

    func setData(_ key: String, _ bytes: Data) {
        set(key, bytes)
    }

    private func set(_ key: String, _ value: Any?) {
        if let value {
            Self.defaults.set(value, forKey: key)
        } else {
            Self.defaults.removeObject(forKey: key)
        }
    }

    /// Keys persisted in the active domain. On macOS, `persistentDomain(forName:)` for a staged
    /// path domain comes from a second in-process cache that never observes `set(_:forKey:)`,
    /// so the staged plist also contributes its keys once it exists.
    private static func storedKeys() -> Set<String>? {
        var keys = Set((defaults.persistentDomain(forName: applicationID) ?? [:]).keys)
        guard isStaged, FileManager.default.fileExists(atPath: applicationID) else { return keys }
        guard let data = FileManager.default.contents(atPath: applicationID),
            // ReadOptions is Int on macOS (C++ interop) and an OptionSet on Linux.
            let entries = try? PropertyListSerialization.propertyList(
                from: data, options: .init(), format: nil) as? [String: Any]
        else { return nil }
        keys.formUnion(entries.keys)
        return keys
    }

    /// The main bundle's own identifier is not a valid suite name (`UserDefaults(suiteName:)`
    /// returns nil); its domain is the standard defaults' application domain.
    private static func userDefaults(for applicationID: String) -> UserDefaults {
        if applicationID == Bundle.main.bundleIdentifier { return .standard }
        guard let defaults = UserDefaults(suiteName: applicationID) else {
            preconditionFailure("Could not create preferences domain \(applicationID)")
        }
        return defaults
    }
}
