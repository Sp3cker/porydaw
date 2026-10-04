#if canImport(CoreFoundation)
    import CoreFoundation
#endif
import Foundation
import QtBridge

@MainActor
@QtBridgeable
public final class PreferencesStore: QmlInstantiableStatus {
    private static var applicationID = "com.sp3cker.porydaw"
    private static var defaults = userDefaults(for: applicationID)
    /// Check staging; corelibs Foundation has no path-backed `UserDefaults` domain.
    private static var stagedFile: StagedPreferencesFile?

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
        stagedFile = StagedPreferencesFile(path: path)
    }

    public static func configureShared(applicationName: String) {
        guard stagedFile == nil else { return }
        applicationID = "com.sp3cker." + applicationName
        defaults = userDefaults(for: applicationID)
    }

    /// The stored object exactly as persisted, for checks that inspect or poison the domain.
    func storedObject(key: String) -> Any? {
        Self.stagedFile.map { $0.values[key] } ?? Self.defaults.object(forKey: key)
    }

    func setStoredObject(_ object: Any, key: String) { set(key, object) }

    private func value(_ key: String) -> Any? {
        let value = storedObject(key: key)
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
        guard let number = value(key) as? NSNumber, Self.isBoolean(number)
        else { return nil }
        return number.boolValue
    }

    func storedPositiveInt(key: String) -> Int? {
        guard let number = value(key) as? NSNumber, !Self.isBoolean(number), number.intValue > 0,
            number.doubleValue == Double(number.intValue)
        else { return nil }
        return number.intValue
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        #if canImport(CoreFoundation)
            return CFGetTypeID(number) == CFBooleanGetTypeID()
        #else
            return String(cString: number.objCType) == String(cString: NSNumber(value: true).objCType)
        #endif
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
        if let staged = Self.stagedFile {
            staged.values.removeAll()
            return staged.synchronize()
        }
        let defaults = Self.defaults
        guard defaults.synchronize() else { return false }
        for key in (defaults.persistentDomain(forName: Self.applicationID) ?? [:]).keys {
            defaults.removeObject(forKey: key)
        }
        return defaults.synchronize()
    }

    public func synchronize() { _ = Self.stagedFile?.synchronize() ?? Self.defaults.synchronize() }

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
        if let staged = Self.stagedFile {
            staged.values[key] = value
        } else if let value {
            Self.defaults.set(value, forKey: key)
        } else {
            Self.defaults.removeObject(forKey: key)
        }
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

/// The staged domain: the whole plist in memory, written atomically on synchronize.
@MainActor
private final class StagedPreferencesFile {
    let path: String
    var values: [String: Any] = [:]

    init(path: String) { self.path = path }

    func synchronize() -> Bool {
        guard
            let data = try? PropertyListSerialization.data(
                fromPropertyList: values, format: .xml, options: 0)
        else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path), options: .atomic)) != nil
    }
}
