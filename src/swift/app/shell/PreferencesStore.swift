import CoreFoundation
import Foundation
import QtBridge

@MainActor
@QtBridgeable
public final class PreferencesStore: QmlInstantiableStatus {
    private static var applicationID: CFString = cfString("com.sp3cker.porydaw")
    private static var isStaged = false
    private static var stagedPlistPath: String?

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
        applicationID = cfString(path)
        stagedPlistPath = path
        isStaged = true
    }

    public static func configureShared(applicationName: String) {
        guard !isStaged else { return }
        applicationID = cfString("com.sp3cker." + applicationName)
    }

    private func value(_ key: String) -> Any? {
        let value = CFPreferencesCopyAppValue(Self.cfString(key), Self.applicationID)
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

    public func hasValue(key: String) -> Bool { value(key) != nil }

    public func setString(key: String, value: String) {
        set(key, value as CFPropertyList)
    }

    public func setInt(key: String, value: Int) {
        set(key, value as CFPropertyList)
    }

    public func setDouble(key: String, value: Double) {
        set(key, value as CFPropertyList)
    }

    public func setBool(key: String, value: Bool) {
        set(key, value ? kCFBooleanTrue : kCFBooleanFalse)
    }

    public func remove(key: String) { set(key, nil) }

    public func resetPreferences() -> Bool {
        guard CFPreferencesAppSynchronize(Self.applicationID) else { return false }
        let keys: [String]
        if let path = Self.stagedPlistPath {
            if FileManager.default.fileExists(atPath: path) {
                guard let data = FileManager.default.contents(atPath: path),
                      let entries = try? PropertyListSerialization.propertyList(
                          from: data, options: 0, format: nil) as? [String: Any] else {
                    return false
                }
                keys = Array(entries.keys)
            } else {
                keys = []
            }
        } else {
            keys = CFPreferencesCopyKeyList(Self.applicationID, kCFPreferencesCurrentUser,
                                            kCFPreferencesAnyHost) as? [String] ?? []
        }
        for key in keys { remove(key: key) }
        return CFPreferencesAppSynchronize(Self.applicationID)
    }

    public func synchronize() { _ = CFPreferencesAppSynchronize(Self.applicationID) }

    func strings(_ key: String) -> [String]? { value(key) as? [String] }

    func setStrings(_ key: String, _ strings: [String]?) {
        guard let strings else { remove(key: key); return }
        set(key, strings as CFPropertyList)
    }

    func data(_ key: String) -> Data? { value(key) as? Data }

    func setData(_ key: String, _ bytes: Data) {
        let data = bytes.withUnsafeBytes { buffer in
            CFDataCreate(kCFAllocatorDefault, buffer.bindMemory(to: UInt8.self).baseAddress,
                         bytes.count)
        }
        set(key, data)
    }

    private func set(_ key: String, _ value: CFPropertyList?) {
        CFPreferencesSetAppValue(Self.cfString(key), value, Self.applicationID)
    }

    private static func cfString(_ text: String) -> CFString {
        guard let result = text.withCString({
            CFStringCreateWithCString(kCFAllocatorDefault, $0, CFStringBuiltInEncodings.UTF8.rawValue)
        }) else { preconditionFailure("Preferences identifier could not be encoded") }
        return result
    }
}
