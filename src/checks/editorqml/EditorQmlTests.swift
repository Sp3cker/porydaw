import Foundation
import Synchronization
import PorydawApp
import PorydawAppAudio
import PorydawAppCommands
import PorydawCore
import QtBridge
import QtBridgeCpp

/// Hosts the production drawer lane and the isolated display-list frame check
/// with separate manifest entries and the same Qt Quick Test executable.
@main
enum EditorQmlLane {
    /// The manifest entry `tools/run_checks.ts --filter editorqml-drawer`
    /// selects.
    static let entryName = "editorqml-drawer"

    /// The drawer entry's primary suite inside `EditorQmlPaths.testDirectory`.
    static let inputFileName = "tst_EditorDrawer.qml"
    private static let suiteEnvironmentKey = "PORYDAW_EDITOR_QML_SUITE"

    static func main() {
        exit(
            MainActor.assumeIsolated {
                runLane(arguments: Array(CommandLine.arguments.dropFirst()))
            })
    }

    @MainActor
    private static func runLane(arguments: [String]) -> Int32 {
        if arguments.contains("--manifest") {
            print(manifestLine)
            return 0
        }
        let isDisplayListCheck = arguments.first == "DisplayListSameFrame"
        let laneArguments = isDisplayListCheck ? Array(arguments.dropFirst()) : arguments
        guard let scratch = laneArguments.first, !scratch.isEmpty else {
            return fail("usage: \(entryName) <scratch> [--qt <qt quick test arguments>…]")
        }
        // The same terminal separator `porydaw_checks` uses: everything after
        // `--qt` is the Qt Quick Test payload the Deno runner forwarded.
        var payload = Array(laneArguments.dropFirst())
        if let separator = payload.firstIndex(of: "--qt") {
            payload = Array(payload[(separator + 1)...])
        }
        guard !payload.contains("-input") else {
            return fail("\(entryName) owns its -input file: \(inputFileName)")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: scratch, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            return fail("scratch directory does not exist: \(scratch)")
        }
        // The bootstrap serves these staged paths to QML, so they must be
        // known before Qt Quick Test builds any QML object.
        EditorQmlBootstrap.stage(projectRoot: scratch)
        PreferencesStore.stageShared(
            plistPath: URL(fileURLWithPath: scratch, isDirectory: true)
                .appendingPathComponent("settings.plist").path)
        EditorQmlBootstrap.stageSongLabel("mus_route101")
        if isDisplayListCheck {
            return runSuite(file: "tst_DisplayListSameFrame.qml", payload: payload)
        }

        let environment = ProcessInfo.processInfo.environment
        if let profileName = environment[childEnvironmentKey] {
            guard let profile = referenceProfiles.first(where: { $0.name == profileName }),
                environment[suiteEnvironmentKey] == "tst_EditorDrawerReferenceProfiles.qml"
            else { return fail("unknown reference profile or suite: \(profileName)") }
            setenv("QT_SCALE_FACTOR", "1", 0)
            setenv("QT_SCALE_FACTOR", String(profile.dpr), 1)
            EditorQmlBootstrap.stageProfile(
                profile: profile.name, dpr: profile.dpr,
                fontPx: profile.fontPx, panes: profile.panes)
            return runSuite(
                file: "tst_EditorDrawerReferenceProfiles.qml",
                payload: [profilePencilCaseName, profileCaseName])
        }
        if environment[physicalDpr2ChildKey] != nil {
            guard environment[suiteEnvironmentKey] == "tst_EditorDrawerAutomationTransactions.qml",
                environment["QT_SCALE_FACTOR"] == "2",
                environment["QT_QPA_PLATFORM"] == "offscreen",
                payload == [physicalDpr2CaseName]
            else {
                return fail("physical DPR2 child requires only the mounted boundary case")
            }
        }
        if let suite = environment[suiteEnvironmentKey] {
            guard (try? drawerSuites())?.contains(suite) == true else {
                return fail("unknown drawer suite: \(suite)")
            }
            if environment[phaseEnvironmentKey] != nil {
                EditorQmlBootstrap.stagePhase(containerPhaseName)
            }
            return runSuite(file: suite, payload: payload)
        }
        let suites: [String]
        do { suites = try drawerSuites() } catch { return fail("could not list drawer suites: \(error)") }
        guard !suites.isEmpty else { return fail("no drawer suites") }
        let selectors = payload.filter { $0.contains("::") }
        let requested: [String]
        if selectors.isEmpty {
            requested = suites
        } else {
            let owners = selectors.map { selector in
                suiteSelectors.first { $0.value.contains(selector) }?.key
            }
            guard !owners.contains(where: { $0 == nil }) else {
                return fail("unknown drawer selector: \(selectors)")
            }
            requested = suites.filter { owners.contains($0) }
        }
        let jobs =
            requested
            .filter { selectors.isEmpty || $0 != "tst_EditorDrawerReferenceProfiles.qml" }
            .flatMap { suite -> [(suite: String, phase: String, payload: [String])] in
                let selected = selectors.filter { suiteSelectors[suite]?.contains($0) == true }
                let arguments = payload.filter { !$0.contains("::") } + selected
                return ["production", containerPhaseName].map {
                    (suite: suite, phase: $0, payload: arguments)
                }
            }
        let outcomes = Mutex(Array(repeating: Int32(1), count: jobs.count))
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = min(
            6, ProcessInfo.processInfo.activeProcessorCount,
            max(1, jobs.count))
        let operations = jobs.enumerated().map { index, job in
            BlockOperation {
                let result = runPhaseChild(
                    scratch: scratch, suite: job.suite,
                    phase: job.phase, payload: job.payload)
                outcomes.withLock { $0[index] = result }
            }
        }
        queue.addOperations(operations, waitUntilFinished: true)
        if outcomes.withLock({ $0.contains(where: { $0 != 0 }) }) { return 1 }
        if selectors.isEmpty, runPhysicalDpr2BoundaryChild(scratch: scratch) != 0 { return 1 }
        return selectors.isEmpty || requested.contains("tst_EditorDrawerReferenceProfiles.qml")
            ? runProfileChildren(scratch: scratch) : 0
    }

    /// One suite child constructs one Qt application for one explicit test file.
    @MainActor
    private static func runSuite(file: String, payload: [String]) -> Int32 {
        var qTestApp = QTestAppCpp()
        qTestApp.setInputDir(EditorQmlPaths.testDirectory)
        qTestApp.setImportPath(EditorQmlPaths.qmlImportPath)
        qTestApp.setPluginsPath(EditorQmlPaths.pluginPath)
        ApplicationSession.registerQmlElement()
        EngineSettingsStore.registerUncreatableQmlElement()
        EventListPresenter.registerUncreatableQmlElement()
        MidiImportController.registerUncreatableQmlElement()
        NewSongController.registerUncreatableQmlElement()
        PianoGrid.registerUncreatableQmlElement()
        PolyphonyPanelPresenter.registerUncreatableQmlElement()
        SampleLoopTools.registerUncreatableQmlElement()
        SampleStudioAudition.registerUncreatableQmlElement()
        SampleStudioPresenter.registerUncreatableQmlElement()
        SampleStudioWorkflow.registerUncreatableQmlElement()
        SampleWaveformModel.registerUncreatableQmlElement()
        Sf2ZonePickerPresenter.registerUncreatableQmlElement()
        SongDockController.registerUncreatableQmlElement()
        TransportBarPresenter.registerUncreatableQmlElement()
        VelocityPage.registerUncreatableQmlElement()
        VoiceEditorController.registerUncreatableQmlElement()
        VoiceListController.registerUncreatableQmlElement()
        WavExportPresenter.registerUncreatableQmlElement()
        EditorQmlBootstrap.registerQmlElement()
        PreferencesStore.registerQmlElement()
        DisplayListProbe.registerQmlElement()

        let inputFile = URL(fileURLWithPath: EditorQmlPaths.testDirectory, isDirectory: true)
            .appendingPathComponent(file).path
        let laneArguments = [CommandLine.arguments.first ?? entryName, "-input", inputFile] + payload
        var argv: [UnsafeMutablePointer<Int8>?] = laneArguments.map { strdup($0) }
        defer { argv.forEach { free($0) } }
        return qTestApp.runQtQuickTests(Int32(laneArguments.count), &argv)
    }

    private static func drawerSuites() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: EditorQmlPaths.testDirectory)
            .filter { $0 == inputFileName || ($0.hasPrefix("tst_EditorDrawer") && $0.hasSuffix(".qml")) }
            .sorted()
    }
    private static let suiteSelectors: [String: [String]] = {
        let cases: [(String, String)] = [
            ("", "noPageContributesNothing hostedChromeAndStacking"),
            ("ContainerResize", "toggleRetainsStoredHeight resizeClampAndCancellation"),
            (
                "ContainerLifecycle",
                "voiceChangesSpillAndDetach focusReturnAndPageCancellation mountedDrawerFocusFallbackWalk"
            ),
            (
                "SharedPlayhead",
                "sharedPlayheadRendersRollAndVisibleBodies sharedPlayheadHidesOutOfViewportAndReprojects sharedPlayheadSuspendsFollowForEveryInteraction"
            ),
            (
                "Chrome",
                "numericFieldWindowShortcutPriority_data numericFieldWindowShortcutPriority bundledFontsResolveInEditorLane otherEventsBandMountsBetweenDrawerAndScrollbar otherEventsProjectionHoverAndWheel drawerTypographyFromMountedSession productionDrawerBlankBarFocus"
            ),
            (
                "Headers",
                "quickSurfacePublishesAndRendersHeaders trackActivityRenderedMeterParity headerVoiceChangeAltersRetainedRaster hoveringHeadersDoesNotCreateTooltip headerCtrlScopeKeepsPrimaryAndRendersOverlay"
            ),
            (
                "VelocityRaster",
                "productionVelocityPageMountsAndRenders productionVelocityMountedInk productionVelocityScrollAlignment productionVelocityTransientInk productionVelocityDetentRepaint"
            ),
            (
                "VelocityHitTargets",
                "productionVelocityCoincidentNodePriority productionVelocityStemGestureCancellation productionVelocityOverlapTargetsVisibleNode"
            ),
            (
                "VelocityEditing",
                "velocityHintsResumeAfterOutsideRelease productionVelocityPointerEdit productionVelocityNumericInput productionVelocityCancellation productionVelocityPlayheadPerformance productionVelocityContextIsExact"
            ),
            (
                "VelocityPrompt",
                "productionVelocityPromptTransaction productionVelocityPromptButtonsAndFocus productionVelocityPromptValidationAndDismissal productionVelocityPromptBoundedKeys"
            ),
            ("VelocitySameFrame", "velocityHandlesTrackFreshGridEveryFrame"),
            (
                "VoiceTransactions",
                "productionVoiceChangesPageMountsAndRenders productionVoiceChangesPointerAndMenuTransactions productionVoiceChangesInsertAndChangeRowPicks productionVoiceChangesMenuHoldAcrossCameraScroll productionVoiceChangesDismissalAndEscape"
            ),
            (
                "VoicePicker",
                "productionVoiceChangesPickerKeyboardAndCancellation productionVoicePickerPointerAudition productionVoiceChangesModalLayerComposition productionVoiceChangesSpacePriority"
            ),
            (
                "VoiceInputIsolation",
                "productionVoiceInputPressIsolatesAutomationAndCursor productionVoiceDragCursorDraftAndBandIsolation productionVoiceJitterAndEscapeKeepArrowAndClearBand productionVoiceCollisionAndAltCursorIsolation productionVoiceChangesCameraTransactions"
            ),
            (
                "AutomationHover",
                "productionAutomationHoverThroughInput productionAutomationEditGuideTracksCursor productionAutomationHoverTransfersBetweenWrittenNodes automationHintsRetainGrabOrigin"
            ),
            (
                "AutomationCurves",
                "productionAutomationOriginPhantomCurveRaster productionAutomationGhostCurvesDrawUnderActive productionAutomationLeadInStepAndSelectionPixels"
            ),
            (
                "AutomationPresentation",
                "automationPresentationCurveTabAndBadgePixels automationPresentationGhostAxisAndResize automationPresentationInactiveInclusionPixels"
            ),
            (
                "AutomationTabs",
                "parameterLabelsFitGutterAtDerivedMinimum_data parameterLabelsFitGutterAtDerivedMinimum productionAutomationPageMountsAndRenders productionAutomationTabSwitchAndGhosts"
            ),
            (
                "AutomationTransactions",
                "productionAutomationDomainRowsThroughInput productionAutomationPromptTransaction productionAutomationBandHalfOpenPhysicalBoundaryDpr1 productionAutomationBandHalfOpenPhysicalBoundaryDpr2"
            ),
            (
                "AutomationPointMenu",
                "productionAutomationRangeSubmenu productionAutomationOutsideRightRetarget productionAutomationPointMenuDeleteAndDismiss productionAutomationSyntheticDefaultMenuRoute"
            ),
            (
                "AutomationFocus",
                "automationModalsRetireWithPage productionAutomationSetValuePromptFocusRoute productionAutomationTempoPromptFocusRoute productionAutomationSpacePriority productionAutomationPanGuardsSharedCommands"
            ),
            (
                "AutomationLaneMenu",
                "productionAutomationMenusAndLaneCommands productionAutomationClearRowClick productionAutomationRange64RowClick productionAutomationCopyRowClick productionAutomationPasteRowClick productionAutomationBandCopyPasteIsLaneScoped"
            ),
            (
                "AutomationTempo",
                "productionAutomationTempoPromptPresentation productionAutomationCenteredPromptOffset productionAutomationTapTempoThroughInput"
            ),
            (
                "PagePlayhead",
                "productionAutomationFollowAndCancellation productionAllPagesPlayheadPerformance productionVoiceChangesPlayheadPerformance"
            ),
            (
                "AutomationCamera",
                "productionAutomationBandGeometry productionAutomationSectionResizeKeepsTabsClickable productionAutomationMiddlePanAndTrackSwitch productionAutomationEmptySwitchPreservesGrid productionAutomationViewStateAcrossDrawerPages productionAutomationWheelZoomPreservesDrawerState productionAutomationPanLifecycleFocusGrabAndInterruptions"
            ),
            (
                "AutomationPreview",
                "productionAutomationDragPreviews productionAutomationPanSelectedRingPixels productionAutomationPencilPreviewAndLabel"
            ),
            ("ReferenceProfiles", "referenceProfileBeforeCapturePencilCursorScale referenceProfileCapture"),
        ]
        return Dictionary(
            uniqueKeysWithValues: cases.map { suffix, functions in
                (
                    "tst_EditorDrawer\(suffix).qml",
                    functions.split(separator: " ").map { "EditorDrawerLane::test_\($0)" }
                )
            })
    }()

    /// Entries use the route101 fixture set from `src/checks/checkcatalog.cpp`
    /// and the same `run_checks.ts` manifest shape as the native checks.
    private static var manifestLine: String {
        let files = fixtureFiles.map { "\"" + $0 + "\"" }.joined(separator: ",")
        let entry =
            #"{"name":"\#(entryName)","argv":["{scratch}"],"binary":"checks","windowing":"offscreen","framework":"qt-test","optIn":false,"scratchKind":"existing-directory","fixtureRootKind":"decomp-project","fixtureFiles":[\#(files)]}"#
        let displayList =
            #"{"name":"DisplayListSameFrame","argv":["DisplayListSameFrame","{scratch}"],"binary":"checks","windowing":"offscreen","framework":"qt-test","optIn":false,"scratchKind":"existing-directory","fixtureRootKind":"decomp-project","fixtureFiles":[\#(files)]}"#
        return #"{"checks":[\#(entry),\#(displayList)]}"#
    }

    private static let fixtureFiles = [
        "sound/song_table.inc",
        "sound/songs/midi/midi.cfg",
        "sound/songs/midi/mus_route101.mid",
        "sound/direct_sound_data.inc",
        "sound/direct_sound_samples/fixture_bass.bin",
        "sound/direct_sound_samples/fixture_drum.bin",
        "sound/direct_sound_samples/fixture_loop.bin",
        "sound/direct_sound_samples/fixture_pluck.bin",
        "sound/programmable_wave_data.inc",
        "sound/programmable_wave_samples/fixture_pulse.pcm",
        "sound/programmable_wave_samples/fixture_saw.pcm",
        "sound/keysplit_tables.inc",
        "sound/voicegroups/fixture_rich.inc",
        "sound/voicegroups/fixture_keys.inc",
        "sound/voicegroups/fixture_bass.inc",
        "sound/voicegroups/fixture_drums_a.inc",
        "sound/voicegroups/fixture_drums_b.inc",
    ]

    static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        return 2
    }
}
