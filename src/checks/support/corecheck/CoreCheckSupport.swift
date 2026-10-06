import Foundation
import PorydawCoreCheckNative

public typealias PdcCheckCallback =
    @convention(c) (
        UnsafeMutableRawPointer?, Int32, UnsafePointer<CChar>?, UnsafePointer<CChar>?
    ) -> Void

public struct CheckReport {
    private final class State {
        let callback: PdcCheckCallback?
        let context: UnsafeMutableRawPointer?
        var reportedRows: Set<String> = []
        var assertionCount = 0

        init(callback: PdcCheckCallback?, context: UnsafeMutableRawPointer?) {
            self.callback = callback
            self.context = context
        }
    }

    private let state: State

    public init(callback: PdcCheckCallback?, context: UnsafeMutableRawPointer?) {
        state = State(callback: callback, context: context)
    }

    public var assertionCount: Int { state.assertionCount }

    /// Green-run identity contract: each distinct cppId + row/what emits one
    /// pass callback line. Only duplicate assertions for that same row are
    /// suppressed; `assertionCount` still counts every assertion.
    public func pass(_ cppID: String, row: String = "suite-complete") {
        state.assertionCount += 1
        let identity = "\(cppID)\u{1F}\(row)"
        guard state.reportedRows.insert(identity).inserted else { return }
        invoke(failed: false, cppID: cppID, message: "\(row): passed")
    }

    public func fail(_ cppID: String, _ message: String) {
        state.assertionCount += 1
        invoke(failed: true, cppID: cppID, message: message)
    }

    public func expect(_ condition: @autoclosure () -> Bool, cppID: String, message: String) {
        if condition() {
            pass(cppID, row: message)
        } else {
            fail(cppID, message)
        }
    }

    public func expectEqual<T: Equatable>(
        expected: T, actual: T, cppID: String,
        what: String
    ) {
        if expected == actual {
            pass(cppID, row: what)
        } else {
            fail(cppID, "\(what): expected=\(expected) actual=\(actual)")
        }
    }

    /// Scoped view that fixes the cppID prefix so call sites stop carrying
    /// cppID-prefixing helpers. Forwards byte-identically to the unscoped
    /// methods with the same cppID string.
    public func scoped(cppID: String) -> Scoped {
        Scoped(report: self, cppID: cppID)
    }

    public struct Scoped {
        private let report: CheckReport
        private let cppID: String

        public init(report: CheckReport, cppID: String) {
            self.report = report
            self.cppID = cppID
        }

        public func pass(row: String = "suite-complete") {
            report.pass(cppID, row: row)
        }

        public func fail(_ message: String) {
            report.fail(cppID, message)
        }

        public func expect(_ condition: @autoclosure () -> Bool, message: String) {
            report.expect(condition(), cppID: cppID, message: message)
        }

        public func expectEqual<T: Equatable>(expected: T, actual: T, what: String) {
            report.expectEqual(expected: expected, actual: actual, cppID: cppID, what: what)
        }
    }

    private func invoke(failed: Bool, cppID: String, message: String) {
        guard let callback = state.callback else { return }
        cppID.withCString { cppIDPointer in
            message.withCString { messagePointer in
                callback(state.context, failed ? 1 : 0, cppIDPointer, messagePointer)
            }
        }
    }
}

public enum CheckEnvironment {
    public static let fixtureRoot: String? = {
        guard let pointer = pdc_check_fixture_root() else { return nil }
        return String(cString: pointer)
    }()
    public static let sampleCorpus: String? = {
        guard let pointer = pdc_check_sample_corpus() else { return nil }
        return String(cString: pointer)
    }()

    public static func fixturePath(_ relativePath: String) -> String? {
        fixtureRoot.map { URL(fileURLWithPath: $0).appendingPathComponent(relativePath).path }
    }
}
