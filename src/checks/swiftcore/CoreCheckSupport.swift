import Foundation
import PorydawCoreCheckNative

public typealias PdcCheckCallback = @convention(c) (
    UnsafeMutableRawPointer?, Int32, UnsafePointer<CChar>?, UnsafePointer<CChar>?
) -> Void

struct CheckReport {
    private final class State {
        let callback: PdcCheckCallback?
        let context: UnsafeMutableRawPointer?
        var reportedPasses: Set<String> = []
        var assertionCount = 0

        init(callback: PdcCheckCallback?, context: UnsafeMutableRawPointer?) {
            self.callback = callback
            self.context = context
        }
    }

    private let state: State

    init(callback: PdcCheckCallback?, context: UnsafeMutableRawPointer?) {
        state = State(callback: callback, context: context)
    }

    var assertionCount: Int { state.assertionCount }

    func pass(_ cppID: String) {
        state.assertionCount += 1
        guard state.reportedPasses.insert(cppID).inserted else { return }
        invoke(failed: false, cppID: cppID, message: "passed")
    }

    func fail(_ cppID: String, _ message: String) {
        state.assertionCount += 1
        invoke(failed: true, cppID: cppID, message: message)
    }

    func expect(_ condition: @autoclosure () -> Bool, cppID: String, message: String) {
        if condition() {
            pass(cppID)
        } else {
            fail(cppID, message)
        }
    }

    func expectEqual<T: Equatable>(_ expected: T, _ actual: T, cppID: String,
                                    what: String) {
        if expected == actual {
            pass(cppID)
        } else {
            fail(cppID, "\(what): expected=\(expected) actual=\(actual)")
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

enum CheckEnvironment {
    static let fixtureRoot: String? = {
        guard let pointer = oracle_check_fixture_root() else { return nil }
        return String(cString: pointer)
    }()

    static func fixturePath(_ relativePath: String) -> String? {
        fixtureRoot.map { URL(fileURLWithPath: $0).appendingPathComponent(relativePath).path }
    }
}

@_cdecl("pdc_suite_run")
public func pdcSuiteRun(_ suite: UInt32, _ callback: PdcCheckCallback?,
                        _ context: UnsafeMutableRawPointer?) {
    let report = CheckReport(callback: callback, context: context)
    switch suite {
    case 1:
        runMidiCodecSuite(report)
    case 2:
        runMusicalSemanticsSuite(report)
    case 3:
        runPlaybackSuite(report)
    default:
        report.fail("swiftcore/suite-selection", "unknown suite \(suite)")
    }
    if report.assertionCount == 0 {
        report.fail("swiftcore/suite-selection", "suite \(suite) executed zero assertions")
    }
}
