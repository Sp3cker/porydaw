#pragma once

#include <QObject>
#include <QStringList>

class MidiSmfTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(MidiSmfTest)

  public:
    MidiSmfTest() = default;

  private slots:
    void validFormat0ParsingAndCoercion();
    void highDataBytesKeepStreamAlignment();
    void opaqueSysExAndMetaEventsRoundTrip();
    void vlqRunningStatusResetsAcrossMeta();
    void duplicateEndOfTrackCanonicalizes();
    void automationBurstPreservesEveryChannelEvent();
    void noteLifecyclePreservesSameTickOrdering();
    void complexInterleavedNotesPairExactly();
    void unterminatedNotePairingStaysLinear();
    void programChangesRejectOutOfRangeValues();
    void noteOnsRejectOutOfRangeKeys();
    void tempoConversionSchedulesExactSamples();
    void engineTrackMappingAgreesAcrossProjections();
};

int runSmfCheck(const QStringList &qtArguments);
