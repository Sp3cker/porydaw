import QtBridge

/// The QtBridge types registered by both the application and its build-time tooling.
@MainActor
public enum PorydawQmlTypes {
    /// Types that QML may construct, in application registration order.
    public static let instantiable: [QmlInstantiable.Type] = [ShellPresenter.self, ApplicationSession.self]

    /// Swift-owned types that QML may name, in application registration order.
    public static let uncreatable: [QmlUncreatable.Type] = [
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
    ]
}
