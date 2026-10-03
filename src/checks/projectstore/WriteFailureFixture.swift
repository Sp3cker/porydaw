import Foundation

private enum WriteFailureFixtureError: Error {
    case unsupportedPlatform
}

enum WriteFailureFixture {
    static func blockAtomicWrites(to path: String) throws -> () -> Void {
        #if os(macOS)
            try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: path)
            return { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: path) }
        #elseif os(Linux)
            let directory = URL(filePath: path).deletingLastPathComponent().path
            let attributes = try FileManager.default.attributesOfItem(atPath: directory)
            guard let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue else {
                throw CocoaError(.fileReadUnknown)
            }
            try FileManager.default.setAttributes(
                [.posixPermissions: permissions & ~0o222], ofItemAtPath: directory)
            return {
                try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: directory)
            }
        #else
            throw WriteFailureFixtureError.unsupportedPlatform
        #endif
    }
}
