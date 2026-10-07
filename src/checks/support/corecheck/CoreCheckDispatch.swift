import Foundation
import PorydawCoreCheckNative
import SwiftCoreCheckEdit
import SwiftCoreCheckMedia
import SwiftCoreCheckPages
import SwiftCoreCheckProject
import SwiftCoreCheckRoll
import SwiftCoreCheckSupport

/// Same-thread synchronous handoff of a CheckReport into MainActor suites; see pdcSuiteRun.
private final class ReportBox: @unchecked Sendable {
    let report: CheckReport
    init(_ report: CheckReport) { self.report = report }
}

// The envelope invokes pdc_suite_run on the Qt main thread; suites run
// synchronously there, so the box states the same-thread reality the region checker cannot see.
private func onMain(_ report: CheckReport, _ body: @MainActor (CheckReport) -> Void) {
    let boxed = ReportBox(report)
    MainActor.assumeIsolated { body(boxed.report) }
}

@_cdecl("pdc_suite_run")
public func pdcSuiteRun(
    _ suite: UInt32, _ callback: PdcCheckCallback?,
    _ context: UnsafeMutableRawPointer?
) {
    let report = CheckReport(callback: callback, context: context)
    switch PdcSuite(rawValue: suite) {
    case PDC_SUITE_MIDI_CODEC: onMain(report, runMidiCodecSuite)
    case PDC_SUITE_MUSICAL_SEMANTICS: onMain(report, runMusicalSemanticsSuite)
    case PDC_SUITE_PLAYBACK: runPlaybackSuite(report)
    case PDC_SUITE_NOTE_EDITS:
        onMain(report) {
            coreEditCorpusLoadCheck($0); runNoteEditsSuite($0)
        }
    case PDC_SUITE_DOCUMENT_HISTORY: onMain(report, runDocumentHistorySuite)
    case PDC_SUITE_EVENT_EDITS: onMain(report, runEventEditsSuite)
    case PDC_SUITE_XCMD_EDITS: onMain(report, runXcmdEditsSuite)
    case PDC_SUITE_MIDI_IMPORT: runMidiImportSuite(report)
    case PDC_SUITE_TIME_EDITS: onMain(report, runTimeEditsSuite)
    case PDC_SUITE_PROJECT_SESSION: onMain(report, runProjectSessionSuite)
    case PDC_SUITE_BANK_HISTORY: onMain(report, runBankHistorySuite)
    case PDC_SUITE_PROJECT_IDENTITY: runProjectIdentitySuite(report)
    case PDC_SUITE_SONG_MODEL: runSongModelSuite(report)
    case PDC_SUITE_MIDI_CFG: runMidiCfgSuite(report)
    case PDC_SUITE_SONGS_MK: runSongsMkSuite(report)
    case PDC_SUITE_SONG_CATALOG: runSongCatalogSuite(report)
    case PDC_SUITE_SYNTH_CATALOG: runSynthCatalogSuite(report)
    case PDC_SUITE_VOICE_VALUES: runVoicegroupValueSuite(report)
    case PDC_SUITE_SAVECORE: runSaveCoreSuite(report)
    case PDC_SUITE_VOICE_EDITING: runVoicegroupEditingSuite(report)
    case PDC_SUITE_PROJECTSTORE_CHECKS:
        // Save path through the store: voice editing plus save-core persistence.
        runVoicegroupEditingSuite(report)
        runSaveCoreSuite(report)
    case PDC_SUITE_VOICE_CONTEXT: runVoicegroupContextSuite(report)
    case PDC_SUITE_VOICE_BANKLOGIC: runVoicegroupBankLogicSuite(report)
    case PDC_SUITE_PROJECTSTORE_ACTOR: runProjectStoreActorSuite(report)
    case PDC_SUITE_PROJECTSTORE_OPEN: runProjectStoreOpenSuite(report)
    case PDC_SUITE_PROJECTSTORE_READS: runProjectStoreReadSuite(report)
    case PDC_SUITE_PROJECTSTORE_LOADBANK: runProjectStoreLoadBankSuite(report)
    case PDC_SUITE_PROJECTSTORE_EDIT: runProjectStoreEditSuite(report)
    case PDC_SUITE_PROJECTSTORE_SAVE: runProjectStoreSaveSuite(report)
    case PDC_SUITE_BANK_LEASES: onMain(report, runBankLeasesSuite)
    case PDC_SUITE_EXPORT_CHECKS: onMain(report, runExportChecks)
    case PDC_SUITE_THEME_COLOR:
        onMain(report) {
            runThemeColorChecks($0)
            runPolyphonyPanelChecks($0)
            runEngineSettingsChecks($0)
        }
    case PDC_SUITE_DISPLAY_LIST: runDisplayListChecks(report)
    case PDC_SUITE_SAMPLE: onMain(report, runSampleChecks)
    case PDC_SUITE_AUDIO_CONTROLLER: onMain(report, runAudioControllerChecks)
    case PDC_SUITE_AUDIO_AUDITION: runAudioAuditionChecks(report)
    case PDC_SUITE_RESONANCE: runResonanceSuppressionChecks(report)
    case PDC_SUITE_SUPPRESSION_START_STOP: runSuppressionStartStopChecks(report)
    case PDC_SUITE_SUPPRESSION_REPLACEMENT: runSuppressionReplacementChecks(report)
    case PDC_SUITE_SAMPLE_PROCESSING: runSampleProcessingChecks(report)
    case PDC_SUITE_SAMPLE_STORAGE: runSampleStorageChecks(report)
    case PDC_SUITE_SAMPLE_EDITOR: onMain(report, runSampleEditorChecks)
    case PDC_SUITE_SAMPLE_RENDER: runRenderPipelineChecks(report)
    case PDC_SUITE_SAMPLE_ANALYSIS: runAnalysisChecks(report)
    case PDC_SUITE_SAMPLE_PITCH_33: runSamplePitchChecks(report, key: 33)
    case PDC_SUITE_SAMPLE_PITCH_45: runSamplePitchChecks(report, key: 45)
    case PDC_SUITE_SAMPLE_PITCH_57: runSamplePitchChecks(report, key: 57)
    case PDC_SUITE_SAMPLE_PITCH_69: runSamplePitchChecks(report, key: 69)
    case PDC_SUITE_SAMPLE_PITCH_81: runSamplePitchChecks(report, key: 81)
    case PDC_SUITE_SAMPLE_PITCH_93: runSamplePitchChecks(report, key: 93)
    case PDC_SUITE_VOICE_PARITY: runVoicegroupParitySuite(report)
    default:
        report.fail("swiftcore/suite-selection", "unknown suite \(suite)")
    }
    if report.assertionCount == 0 {
        report.fail("swiftcore/suite-selection", "suite \(suite) executed zero assertions")
    }
}
