import Foundation
import PorydawCoreCheckNative
import SwiftCoreCheckEdit
import SwiftCoreCheckMedia
import SwiftCoreCheckPages
import SwiftCoreCheckProject
import SwiftCoreCheckRoll
import SwiftCoreCheckSupport

/// Same-thread synchronous handoff of a CheckReport into MainActor-isolated
/// suites; see pdcSuiteRun.
private final class ReportBox: @unchecked Sendable {
    let report: CheckReport
    init(_ report: CheckReport) { self.report = report }
}

@_cdecl("pdc_suite_run")
public func pdcSuiteRun(
    _ suite: UInt32, _ callback: PdcCheckCallback?,
    _ context: UnsafeMutableRawPointer?
) {
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
    case 34:
        runDisplayListChecks(report)
    case 35:
        let boxedSample = ReportBox(report)
        MainActor.assumeIsolated {
            runSampleChecks(boxedSample.report)
        }
    case 36:
        let boxedAudio = ReportBox(report)
        MainActor.assumeIsolated {
            runAudioControllerChecks(boxedAudio.report)
        }
    case 37:
        runAudioAuditionChecks(report)
    case 38:
        runResonanceSuppressionChecks(report)
    case 39:
        runSuppressionStartStopChecks(report)
    case 40:
        runSuppressionReplacementChecks(report)
    case 41:
        runSampleProcessingChecks(report)
    case 42:
        runSampleStorageChecks(report)
    case 43:
        let boxedSampleEditor = ReportBox(report)
        MainActor.assumeIsolated {
            runSampleEditorChecks(boxedSampleEditor.report)
        }
    case 44:
        runRenderPipelineChecks(report)
    case 45:
        runAnalysisChecks(report)
    case 46:
        runSamplePitchChecks(report, key: 33)
    case 47:
        runSamplePitchChecks(report, key: 45)
    case 48:
        runSamplePitchChecks(report, key: 57)
    case 49:
        runSamplePitchChecks(report, key: 69)
    case 50:
        runSamplePitchChecks(report, key: 81)
    case 51:
        runSamplePitchChecks(report, key: 93)
    default:
        report.fail("swiftcore/suite-selection", "unknown suite \(suite)")
    }
    if report.assertionCount == 0 {
        report.fail("swiftcore/suite-selection", "suite \(suite) executed zero assertions")
    }
}
