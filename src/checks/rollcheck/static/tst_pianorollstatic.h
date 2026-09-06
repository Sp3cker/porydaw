#pragma once

#include <QString>
#include <QStringList>

#include <QObject>

namespace checks::rollcheck::staticcheck {

class PianoRollStaticTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(PianoRollStaticTest)

  public:
    PianoRollStaticTest(QString projectRoot, QString songLabel);

  private slots:
    void fallbackCamera_data();
    void fallbackCamera();
    void fallbackGrid();
    void tickCeilingDoesNotWrap();
    void preRollRulerShade();
    void fallbackRulerStemAndBars();
    void defaultBindKeepsGeometry();
    void ticksPerBeatKeepsGeometry();
    void signatureGroupingKeepsBeatsAndMovesBars();

    void freshTabStaysGated();
    void midiStageStaysGated();
    void voicegroupBoundReadiesTab();
    void gridControlsDoNotRestyleAcrossReadiness();
    void gatedAndReadyRulerScrub();
    void gatedAndReadyScrollbarWheel();
    void gatedAndReadyRollZoom();
    void tooltipFloatsBelowRuler_data();
    void tooltipFloatsBelowRuler();

    void tickRangeRejectsInvalidBounds();
    void tickRangeWalksFractionalLattice();
    void verticalCameraWheelContract();
    void horizontalCameraWheelContract();
    void affineCameraProjection_data();
    void affineCameraProjection();
    void cameraRangeAndPreRollRaster();
    void scratchSpaceDrawGrowsTimeline();
    void keyboardGutterHoverTracksRows();

  private:
    QString m_projectRoot;
    QString m_songLabel;
};

int runPianoRollStaticCheck(const QString &projectRoot, const QString &songLabel,
                            const QStringList &qtArguments);

} // namespace checks::rollcheck::staticcheck
