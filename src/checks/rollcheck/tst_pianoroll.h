#pragma once

#include <QString>

#include <memory>

#include "project/voicegroupsource.h"
#include <QObject>

namespace checks {
class ProjectFixture;
class LoadedSong;
} // namespace checks

class SongTab;

namespace checks::rollcheck {
class PianoRollFixture;
}

class PianoRollTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(PianoRollTest)

  public:
    PianoRollTest(const QString &projectRoot, const QString &songLabel);
    ~PianoRollTest() override;

  private slots:
    void init();
    void cleanup();

    void duplicateNoteIdentity();
    void timelineProjection();
    void viewStateRoundTrip();
    void trackRemapMove();
    void trackRemapInsert();
    void trackRemapDuplicate();
    void trackRemapDelete();
    void trackRemapMetadata();
    void trackRemapEnginePromotion();
    void headerContextMenu();
    void headerReconciliationUnchanged();
    void headerReconciliationMute();
    void headerReconciliationStructural();
    void headerRenameCancellation();
    void pencilFractionalPlacement();
    void pencilPlacement();
    void pencilAbuttingRaster();
    void pencilGutterSelection();
    void tinyNoteBorderRaster();
    void selectedNoteFrameRaster();
    void ghostNoteRaster();
    void velocityColorRaster();
    void noteNameRaster();
    void velocityValueRaster_data();
    void velocityValueRaster();
    void velocityClickLatch();
    void velocityNoteMenuRetarget();
    void velocityDragCommit();
    void velocityCancelUngrab();
    void velocityDoubleClickDelete();
    void velocityPromptAcceptUndoLatch();
    void velocityPromptCancelStale();
    void velocityPromptBounds();
    void gestureInterlock();
    void selectionBandSweep();
    void selectionPressAudition();
    void selectionPendingDrawReadout();
    void selectionMinimumDrawDistance();
    void selectionModifierVelocity();
    void selectionNonScaleMove();
    void resizeOffGrid();
    void resizeSelection();
    void resizeMinimum();
    void resizeAbutting();
    void keyboardTranspose();
    void keyboardKeepVisible();
    void timelineRulerScope();
    void timelineOtherEventsStrip();
    void timelinePartialSelectionRepaint();
    void keyboardTimeSelectionShortcuts();
    void timelineDuplicateTime();
    void timelineInsertBlankTimeTracks();
    void timelineInsertBlankTimeLanes();
    void quickLifecycle();
    void headerPanFollow();
    void headerRename();
    void headerVoicePresentation();
    void headerSelectionPresentation();
    void headerVoiceRouting();
    void headerMuteSoloControls();
    void headerAddTrack();
    void headerReorder();
    void headerRevealNote();
    void headerKeyboardMuteSolo();
    void scaleProjectionInvariants();
    void scaleHighlightRaster();
    void scaleFoldOccupancy();
    void scaleFoldTrackScope();
    void scaleFoldUndoLifecycle();
    void scaleFoldRootInvariant();
    void scaleFoldKeyboardNudges_data();
    void scaleFoldKeyboardNudges();
    void scaleFoldMultiNoteMapping();
    void scaleFoldRepeatedPitchMapping();
    void scaleFoldExceptionNudge();
    void scaleFoldExceptionDraw();
    void scaleFoldExceptionAudition();
    void scaleFoldPointerDrag();
    void scaleFoldHorizontalException();
    void scaleFoldOutOfRange();

  private:
    QString m_projectRoot;
    QString m_songLabel;
    // The tab borrows m_bank; reverse destruction keeps the bank alive
    // through tab and Quick teardown.
    std::unique_ptr<checks::ProjectFixture> m_project;
    std::unique_ptr<LoadedVoiceGroup> m_bank;
    std::unique_ptr<SongTab> m_tab;
    std::unique_ptr<checks::rollcheck::PianoRollFixture> m_fixture;
};
