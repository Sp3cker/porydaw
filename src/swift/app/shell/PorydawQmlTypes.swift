import PorydawAppPresentation
import PorydawDocument
import QtBridge

/// The QtBridge types registered by both the application and its build-time tooling.
@MainActor
public enum PorydawQmlTypes {
    /// QtBridge keys QML URIs by Swift module; presentation types belong to the app's module.
    private static let aliasedModules: Void = {
        QMetaObjectBuilder.qmlModuleAliases["PorydawAppPresentation"] = "PorydawApp"
    }()

    /// Types that QML may construct, in application registration order.
    public static var instantiable: [QmlInstantiable.Type] {
        _ = aliasedModules
        return [ShellPresenter.self, ApplicationSession.self]
    }

    /// Swift-owned types that QML may name: existing registrations, then alphabetical additions.
    public static var uncreatable: [QmlUncreatable.Type] {
        _ = aliasedModules
        return uncreatableTypes
    }

    private static let uncreatableTypes: [QmlUncreatable.Type] = [
        EngineSettingsStore.self,
        EventListPresenter.self,
        MidiImportController.self,
        NewSongController.self,
        PianoGrid.self,
        PolyphonyPanelPresenter.self,
        SampleLoopTools.self,
        SampleStudioAudition.self,
        SampleStudioPresenter.self,
        SampleStudioWorkflow.self,
        SampleWaveformModel.self,
        Sf2ZonePickerPresenter.self,
        SongDockController.self,
        TransportBarPresenter.self,
        VelocityPage.self,
        VoiceEditorController.self,
        VoiceListController.self,
        WavExportPresenter.self,
        AutomationHoverDisplay.self,
        AutomationMenuRowHandle.self,
        AutomationNodeHandle.self,
        AutomationPage.self,
        AutomationTabHandle.self,
        EditorDrawerPresenter.self,
        EditorDrawerSectionState.self,
        EventListMenuItem.self,
        EventListRowHandle.self,
        GridPalette.self,
        GridScene.self,
        GridSubdivisionMenuItem.self,
        HeaderVoicePicker.self,
        ImportControllerRow.self,
        LayoutSpaces.self,
        MouseHints.self,
        OtherEventsBandPresenter.self,
        OtherEventsMarkerHandle.self,
        PitchBendLane.self,
        PitchBendLine.self,
        PitchBendPresenter.self,
        PitchBendVertex.self,
        PlayheadGuideState.self,
        PlayheadGuidesPresenter.self,
        PolyphonyChannelRow.self,
        PolyphonyCounterRow.self,
        PolyphonyEventRow.self,
        PromptStyle.self,
        RulerMenuPresenter.self,
        RulerMenuRow.self,
        SamplePickerRow.self,
        SceneRect.self,
        SceneText.self,
        Sf2ZonePickerRow.self,
        SharedPlayheadPresenter.self,
        ShellActionState.self,
        SongListCategory.self,
        SongListPresenter.self,
        SongListRow.self,
        SongTabSession.self,
        SongTabsController.self,
        TrackHeaderMenuItem.self,
        TrackHeaderRowHandle.self,
        TrackHeadersPresenter.self,
        TypographyFonts.self,
        VelocityHandle.self,
        VoiceChangesPage.self,
        VoiceListArgChoice.self,
        VoiceListRowHandle.self,
        VoiceMarkerHandle.self,
        VoiceMenuRowHandle.self,
        VoicePickerRowHandle.self,
    ]
}

extension AutomationHoverDisplay: QmlUncreatable {}
extension AutomationMenuRowHandle: QmlUncreatable {}
extension AutomationNodeHandle: QmlUncreatable {}
extension AutomationPage: QmlUncreatable {}
extension AutomationTabHandle: QmlUncreatable {}
extension EditorDrawerPresenter: QmlUncreatable {}
extension EditorDrawerSectionState: QmlUncreatable {}
extension EventListMenuItem: QmlUncreatable {}
extension EventListRowHandle: QmlUncreatable {}
extension GridPalette: QmlUncreatable {}
extension GridScene: QmlUncreatable {}
extension GridSubdivisionMenuItem: QmlUncreatable {}
extension HeaderVoicePicker: QmlUncreatable {}
extension ImportControllerRow: QmlUncreatable {}
extension LayoutSpaces: QmlUncreatable {}
extension MouseHints: QmlUncreatable {}
extension OtherEventsBandPresenter: QmlUncreatable {}
extension OtherEventsMarkerHandle: QmlUncreatable {}
extension PitchBendLane: QmlUncreatable {}
extension PitchBendLine: QmlUncreatable {}
extension PitchBendPresenter: QmlUncreatable {}
extension PitchBendVertex: QmlUncreatable {}
extension PlayheadGuideState: QmlUncreatable {}
extension PlayheadGuidesPresenter: QmlUncreatable {}
extension PolyphonyChannelRow: QmlUncreatable {}
extension PolyphonyCounterRow: QmlUncreatable {}
extension PolyphonyEventRow: QmlUncreatable {}
extension PromptStyle: QmlUncreatable {}
extension RulerMenuPresenter: QmlUncreatable {}
extension RulerMenuRow: QmlUncreatable {}
extension SamplePickerRow: QmlUncreatable {}
extension SceneRect: QmlUncreatable {}
extension SceneText: QmlUncreatable {}
extension Sf2ZonePickerRow: QmlUncreatable {}
extension SharedPlayheadPresenter: QmlUncreatable {}
extension ShellActionState: QmlUncreatable {}
extension SongListCategory: QmlUncreatable {}
extension SongListPresenter: QmlUncreatable {}
extension SongListRow: QmlUncreatable {}
extension SongTabSession: QmlUncreatable {}
extension SongTabsController: QmlUncreatable {}
extension TrackHeaderMenuItem: QmlUncreatable {}
extension TrackHeaderRowHandle: QmlUncreatable {}
extension TrackHeadersPresenter: QmlUncreatable {}
extension TypographyFonts: QmlUncreatable {}
extension VelocityHandle: QmlUncreatable {}
extension VoiceChangesPage: QmlUncreatable {}
extension VoiceListArgChoice: QmlUncreatable {}
extension VoiceListRowHandle: QmlUncreatable {}
extension VoiceMarkerHandle: QmlUncreatable {}
extension VoiceMenuRowHandle: QmlUncreatable {}
extension VoicePickerRowHandle: QmlUncreatable {}
