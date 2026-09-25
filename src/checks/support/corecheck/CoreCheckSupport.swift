import Foundation
import PorydawCoreCheckNative

public typealias PdcCheckCallback = @convention(c) (
    UnsafeMutableRawPointer?, Int32, UnsafePointer<CChar>?, UnsafePointer<CChar>?
) -> Void


/// Same-thread synchronous handoff of a CheckReport into MainActor-isolated
/// suites; see pdcSuiteRun.
private final class ReportBox: @unchecked Sendable {
    let report: CheckReport
    init(_ report: CheckReport) { self.report = report }
}
struct CheckReport {
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

    init(callback: PdcCheckCallback?, context: UnsafeMutableRawPointer?) {
        state = State(callback: callback, context: context)
    }

    var assertionCount: Int { state.assertionCount }

    /// Green-run identity contract: each distinct cppId + row/what emits one
    /// pass callback line. Only duplicate assertions for that same row are
    /// suppressed; `assertionCount` still counts every assertion.
    func pass(_ cppID: String, row: String = "suite-complete") {
        state.assertionCount += 1
        let identity = "\(cppID)\u{1F}\(row)"
        guard state.reportedRows.insert(identity).inserted else { return }
        invoke(failed: false, cppID: cppID, message: "\(row): passed")
    }

    func fail(_ cppID: String, _ message: String) {
        state.assertionCount += 1
        invoke(failed: true, cppID: cppID, message: message)
    }

    func expect(_ condition: @autoclosure () -> Bool, cppID: String, message: String) {
        if condition() {
            pass(cppID, row: message)
        } else {
            fail(cppID, message)
        }
    }

    func expectEqual<T: Equatable>(expected: T, actual: T, cppID: String,
                                    what: String) {
        if expected == actual {
            pass(cppID, row: what)
        } else {
            fail(cppID, "\(what): expected=\(expected) actual=\(actual)")
        }
    }

    /// Scoped view that fixes the cppID prefix so call sites stop carrying
    /// cppID-prefixing helpers. Forwards byte-identically to the unscoped
    /// methods with the same cppID string.
    func scoped(cppID: String) -> Scoped {
        Scoped(report: self, cppID: cppID)
    }

    struct Scoped {
        private let report: CheckReport
        private let cppID: String

        init(report: CheckReport, cppID: String) {
            self.report = report
            self.cppID = cppID
        }

        func pass(row: String = "suite-complete") {
            report.pass(cppID, row: row)
        }

        func fail(_ message: String) {
            report.fail(cppID, message)
        }

        func expect(_ condition: @autoclosure () -> Bool, message: String) {
            report.expect(condition(), cppID: cppID, message: message)
        }

        func expectEqual<T: Equatable>(expected: T, actual: T, what: String) {
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

enum CheckEnvironment {
    static let fixtureRoot: String? = {
        guard let pointer = pdc_check_fixture_root() else { return nil }
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
        let boxedMidi = ReportBox(report)
        MainActor.assumeIsolated {
            runMidiCodecSuite(boxedMidi.report)
        }
    case 2:
        let boxedSemantics = ReportBox(report)
        MainActor.assumeIsolated {
            runMusicalSemanticsSuite(boxedSemantics.report)
        }
    case 3:
        runPlaybackSuite(report)
        let boxedAudio = ReportBox(report)
        MainActor.assumeIsolated {
            runAudioControllerChecks(boxedAudio.report)
        }
        runAudioAuditionChecks(report)
        runResonanceSuppressionChecks(report)
    case 4:
        // The envelope invokes this cdecl on the Qt main thread; the suite
        // runs synchronously there, so the unchecked box states the
        // same-thread reality the region checker cannot see.
        let boxed = ReportBox(report)
        MainActor.assumeIsolated {
            coreEditCorpusLoadCheck(boxed.report)
            runNoteEditsSuite(boxed.report)
        }
    case 5:
        let boxedHistory = ReportBox(report)
        MainActor.assumeIsolated {
            runDocumentHistorySuite(boxedHistory.report)
        }
    case 6:
        let boxedEvents = ReportBox(report)
        MainActor.assumeIsolated {
            runEventEditsSuite(boxedEvents.report)
        }
    case 7:
        let boxedXcmd = ReportBox(report)
        MainActor.assumeIsolated {
            runXcmdEditsSuite(boxedXcmd.report)
        }
    case 8:
        runMidiImportSuite(report)
    case 9:
        let boxedTime = ReportBox(report)
        MainActor.assumeIsolated {
            runTimeEditsSuite(boxedTime.report)
        }
    case 10:
        let boxedSession = ReportBox(report)
        MainActor.assumeIsolated {
            runProjectSessionSuite(boxedSession.report)
        }
    case 11:
        let boxedBank = ReportBox(report)
        MainActor.assumeIsolated {
            runBankHistorySuite(boxedBank.report)
        }
    case 12:
        runProjectIdentitySuite(report)
    case 13:
        runSongModelSuite(report)
    case 14:
        runMidiCfgSuite(report)
    case 15:
        runSongsMkSuite(report)
    case 16:
        runSongCatalogSuite(report)
    case 17:
        runSynthCatalogSuite(report)
    case 18:
        runVoicegroupValueSuite(report)
    case 19:
        runSaveCoreSuite(report)
    case 20:
        runVoicegroupEditingSuite(report)
    case 21:
        runVoicegroupCatalogAbsentSuite(report)
    case 22:
        runVoicegroupEditingSuite(report)
        runSaveCoreSuite(report)
    case 23:
        runVoicegroupContextSuite(report)
    case 24:
        runVoicegroupBankLogicSuite(report)
    case 25:
        runProjectStoreActorSuite(report)
    case 26:
        runProjectStoreOpenSuite(report)
    case 27:
        runProjectStoreReadSuite(report)
    case 28:
        runProjectStoreLoadBankSuite(report)
    case 29:
        runProjectStoreEditSuite(report)
    case 30:
        runProjectStoreSaveSuite(report)
    case 31:
        let boxedBankLeases = ReportBox(report)
        MainActor.assumeIsolated {
            runBankLeasesSuite(boxedBankLeases.report)
        }
    case 32:
        let boxedExport = ReportBox(report)
        MainActor.assumeIsolated {
            runExportChecks(boxedExport.report)
        }
    case 33:
        let boxedTheme = ReportBox(report)
        MainActor.assumeIsolated {
            runThemeColorChecks(boxedTheme.report)
        }
        let boxedPolyphony = ReportBox(report)
        MainActor.assumeIsolated {
            runPolyphonyPanelChecks(boxedPolyphony.report)
        }
        let boxedSettings = ReportBox(report)
        MainActor.assumeIsolated {
            runEngineSettingsChecks(boxedSettings.report)
        }
    default:
        report.fail("swiftcore/suite-selection", "unknown suite \(suite)")
    }
    if report.assertionCount == 0 {
        report.fail("swiftcore/suite-selection", "suite \(suite) executed zero assertions")
    }
}
