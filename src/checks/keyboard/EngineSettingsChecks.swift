import PorydawApp
import PorydawCore
import PorydawPlaybackNative

@MainActor
internal func runEngineSettingsChecks(_ report: CheckReport) {
    let saved = EngineSettings(mixer: "sappy", maxPcmChannels: "8",
                               mixRate: "21024", analogFilter: "true")
    report.expectEqual("sappy", saved.mixer,
                       cppID: "keyboard/SettingsDialogCheckTest::engineMixerPersistsAndRejectsInvalidValue",
                       what: "saved Sappy mixer restores without changing its identity")
    report.expectEqual(8, saved.maxPcmChannels,
                       cppID: "keyboard/SettingsDialogCheckTest::configuredSettingsRoundTrip",
                       what: "configured PCM channel limit survives a store round trip")
    let invalid = EngineSettings(mixer: "invalid", maxPcmChannels: "999",
                                 mixRate: "-1", analogFilter: "false")
    report.expectEqual("ipatix", invalid.mixer,
                       cppID: "keyboard/SettingsDialogCheckTest::engineMixerPersistsAndRejectsInvalidValue",
                       what: "invalid mixer recovers the default Ipatix implementation")
    report.expectEqual(Int(MAX_PCM_CHANNELS), invalid.maxPcmChannels,
                       cppID: "keyboard/SettingsDialogCheckTest::configuredSettingsRoundTrip",
                       what: "persisted polyphony cannot exceed the engine channel capacity")
    report.expectEqual(13_379, invalid.mixRate,
                       cppID: "keyboard/SettingsDialogCheckTest::configuredSettingsRoundTrip",
                       what: "negative persisted mix rate recovers the GBA default")
}
