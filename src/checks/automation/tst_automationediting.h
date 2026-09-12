#pragma once

#include <cstdint>

#include <memory>
#include <optional>
#include <vector>

#include "ui/editordrawer/automationprojection.h"
#include <QByteArray>
#include <QEvent>
#include <QObject>
#include <QPoint>
#include <QPointF>
#include <QPointer>
#include <QQuickWindow>
#include <QString>

#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/songtab.h"
#include "ui/songview/quick/timelineinputitem.h"

class QAction;
class AutomationPage;
class QQuickItem;

namespace songview {
class TimelineQuickScene;
class QuickMenuModel;
class QuickPopupSession;
} // namespace songview

namespace automation_test {
QPoint windowFromContent(const AutomationPage &page, const songview::TimelineInputItem &input,
                         const QPointF &contentPoint);
QPointF contentFromWindow(const AutomationPage &page, const songview::TimelineInputItem &input,
                          const QPoint &windowPoint);
QPointF effectiveDragContent(const AutomationPage &page, const songview::TimelineInputItem &input,
                             const QPoint &press, const QPoint &activation, const QPoint &end);
} // namespace automation_test

class AutomationEditingTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(AutomationEditingTest)

  public:
    AutomationEditingTest() = default;

  private slots:
    void init();
    void cleanup();

    // Pilot coverage.
    void ccDragCommitsOnce();
    void escapeCancelsCcDrag();
    void releaseWithoutActivationDoesNotCommit();

    // Pencil transaction and stroke coverage.
    void pencilStrokeOnEmptyLaneCommitsOnce();
    void pencilPreviewDoesNotMutateUntilRelease();
    void pencilStrokeRestoresHeldEndpointValue();
    void pencilSingleClickOnTempoLaneRestoresDefaultTempoAtCellEnd();
    void pencilSingleClickOnPitchBendLaneRestoresCenterAtCellEnd();
    void pencilFlatStrokeAndRedundantClickAreNoOps();
    void pencilClickOnExcursionNodeDeletesExcursion();
    void pencilCancellationRoutesAbortGestureWithoutCommit_data();
    void pencilCancellationRoutesAbortGestureWithoutCommit();
    void pencilSubCellHorizontalJitterDoesNotAlterStroke();
    void pencilZigzagStrokePreservesDirectionalExtrema();
    void pencilVerticalMotionInSingleCellRetainsFinalValue();
    void pencilDiagonalStrokeEventDensityInvariance_data();
    void pencilDiagonalStrokeEventDensityInvariance();
    void pencilBacktrackingStrokeRetainsExtremaAndLatestRevisit();
    void pencilShiftModifierLocksValueDimension();
    void pencilControlModifierDrawsUnsnappedClockQuantizedPoints();
    void pencilMixedModifierComposesFreehandAndSnappedSegments();
    void pencilAltModifierIsIgnoredDuringStroke();

    // Retained Quick automation presentation coverage.
    void emptyTempoStorageComposesNoLeadIn();
    void firstNonzeroTempoPointComposesImplicitLeadInCurve();
    void explicitTickZeroTempoPointSuppressesLeadInCurve();
    void stepCurvesAndNodesComposed_data();
    void stepCurvesAndNodesComposed();
    void selectionRingsAndReticlesComposed_data();
    void selectionRingsAndReticlesComposed();
    void halfOpenTimeSelectionComposesNodeRings();
    void singleNodeDragPreview_data();
    void singleNodeDragPreview();
    void multiNodeDragPreview_data();
    void multiNodeDragPreview();
    void sweepPreview_data();
    void sweepPreview();
    void shiftRampPreview_data();
    void shiftRampPreview();
    void pencilPreviewAndValueLabel();
    void editCursorTracksQuickView();

    // Cross-lane selection coverage.
    void bandSelectionIsolatesTempoAndControlChangeRows();
    void multiLaneSelectionDragPreservesTempoAndCcOrder();
    void multiLaneSelectionDeleteAndEmptyDeleteNoop();
    void multiLaneSelectionDragAbortsOnDocumentRebuild();
    void multiCcLaneSelectionDragExcludesTempoAndVolume();
    void ghostToggleIsViewOnlyAndSurvivesActivation();

    // Menu and clipboard coverage.
    void contextMenuRoutingAndAvailableLanes();
    void contextMenuActionsApplyEffects();
    void laneMenuValueRangeSubmenuPickRescalesAndCloses();
    void outsidePressDismissesLaneMenuWithoutSideEffects();
    void clipboardCrossLanePasteClamps();
    void pointMenuDeleteCommitsEdit();
    void pointMenuValuePromptUpdatesOneDuplicateOccurrence();
    void pointMenuValuePromptEscapeLeavesDocumentUntouched();
    void outsideRightClickDismissesPointMenu();
    void pointMenuSyntheticDefaultDeleteDisabledAndSetValuePromotes();
    void pointMenuStaleDocumentCannotDeleteTarget();
    void pointMenuForeignTakeoverInvalidatesPendingTarget();
    void pointMenuForeignPopupPublishedDuringOpenSurvives();
    void selectionContextMenuRoutesInsideActiveSelection();

    // Voice and routed physical-input coverage.
    void voiceHorizontalPreviewCommitsAndUndoes();
    void voiceStationaryVerticalJitterAndEmptySpaceDoNotCommit();
    void voiceAltDragUsesFineSnap();
    void voiceCollisionAndStaleRevision();
    void voiceEscapeAndUngrabCancel();
    void voiceDuplicateOccurrenceMovesSingleIdentity();
    void middlePanIsolated();
    void voicePressIsolated();
    void rightBandPreviewIsolated();
    void pencilEditTargetsOnlyItsLane();
    void defaultBodyClickSetsCursorOnly();
    void firstCcRowOriginRebuildAndUndo();

    // Action, projection, and ownership coverage.
    void actionShortcutLatching();
    void actionTextInputImmunity();
    void actionRepeatImmunity();
    void actionCustomBinding();
    void actionHeldKeyGestures();
    void projectionPartialCell();
    void projectionValueBounds();
    void projectionCanvasOrigin();
    void projectionInsertionTiming();
    void pencilClickHalfOpenQuantization();
    void tracksSelectionRings();
    void tracksSelectionGroupDragUndo();
    void pencilModeChangeRetainsPencilGesture();
    void pencilModeChangeRetainsNodeGesture();
    void pencilStrokeOutsideSelectionClearsSelection();
    void detailThresholdHiddenVisibleNodePrecedence();

    // Automation canvas layout and remaining interaction coverage.
    void automationBandAndInputsExposed();
    void sectionResizeKeepsLabelsClickableWithoutScrollbarStrip();
    void layoutAlignsPlotGutterAndRollGrid();
    void middleMousePanSurvivesRefresh();
    void emptyParameterSwitchPreservesGridResolution();
    void viewStateSwitchPreservesAutomationState();
    void wheelZoomAndSectionResizePreserveDrawerState();
    void activationSlopDoesNotCommit();
    void selectionClearingAndMultilaneReplacement();
    void additionalDragCancellationRoutesLeaveDocumentUntouched_data();
    void additionalDragCancellationRoutesLeaveDocumentUntouched();
    void voiceContextFollowsPlaybackOrEditCursor();

    // Tempo/CC parity coverage.
    void hoverInsertionDoesNotMutateDocument_data();
    void hoverInsertionDoesNotMutateDocument();
    void stationaryNodeInteractions_data();
    void stationaryNodeInteractions();
    void independentDoubleClickAfterDeleteOpensValuePrompt_data();
    void independentDoubleClickAfterDeleteOpensValuePrompt();
    void doubleClickDeletesOnceWithoutValuePrompt_data();
    void doubleClickDeletesOnceWithoutValuePrompt();
    void sweepAndRampCommit_data();
    void sweepAndRampCommit();
    void pencilPreviewCommits_data();
    void pencilPreviewCommits();
    void laneBandSelectsRange_data();
    void laneBandSelectsRange();
    void blankAndSubThresholdNoOps_data();
    void blankAndSubThresholdNoOps();
    void nodeDragCommits_data();
    void nodeDragCommits();
    void nodeDragShiftAxisLocks_data();
    void nodeDragShiftAxisLocks();
    void scrolledOriginPhantomCommits_data();
    void scrolledOriginPhantomCommits();
    void selectedRangeDragAndDelete_data();
    void selectedRangeDragAndDelete();
    void escapeCancelsAdapterDrag_data();
    void escapeCancelsAdapterDrag();
    void rebuildCancelsAdapterDragAndRecovers_data();
    void rebuildCancelsAdapterDragAndRecovers();

    // CC-lane delete confirmation coverage: the Quick form that replaced the
    // legacy QMessageBox for nonempty CC-lane deletes on the shared popup
    // session.
    void ccDeletePromptAcceptDeletesOnlyTargetLaneAndUndoRestores();
    void ccDeletePromptCancelButtonLeavesDocumentUntouched();
    void ccDeletePromptEscapeLeavesDocumentUntouched();
    void ccDeletePromptOutsideRightPressClosesWithoutRetarget();
    void ccDeletePromptInitialReturnCancelsWithoutNavigation();
    void ccDeletePromptStaleDocumentCannotDeleteTarget();
    void ccDeletePromptInvalidationSparesForeignPopup();
    void ccDeletePromptSyntheticOnlyVolumeSkipsConfirmation();
    void ccDeletePromptDefaultLaneWrittenCountExcludesSynthetic();

    // Parameter tab coverage: cycling the rendered gutter labels preserves
    // the document, undo state and explicit shared selection.
    void parameterTabsPreserveDocumentAndSelection();

    // Parameter switch invalidation: a switch ends only its owned
    // provisional gestures and prompts, never commits them to the new
    // parameter, and spares foreign popups; fresh input edits the new
    // parameter only.
    void parameterSwitchInvalidatesValuePrompt();
    void parameterSwitchCancelsNodeDrag();

  private:
    struct ArmedCcDrag final {
        QPoint dragEndWindow;
        QPointF targetViewport;
        uint64_t transientRevisionBefore = 0;
    };

    struct FrozenDocumentState final {
        QByteArray smf;
        uint64_t revision = 0;
        int undoCount = 0;
        int undoIndex = 0;
        int documentChanges = 0;
        int edits = 0;

        bool operator==(const FrozenDocumentState &) const = default;
    };

    bool stage(SmfFile smf);
    bool stageSong(SmfFile smf);
    bool quiesceInput();
    LaneHandle findRow(const EditorAutomationRowId &row) const;
    QRect laneBody(LaneHandle lane) const;
    QPointF inputPoint(LaneHandle lane, double tick, int value) const;
    AutomationProjection::PointerMapping pointerMapping(LaneHandle lane,
                                                        QPointF contentPoint) const;
    QPoint windowPoint(const songview::TimelineInputItem &input, QPointF itemPoint) const;
    QPoint automationWindowPoint(QPointF contentPoint) const;
    QPoint automationGutterWindowPoint(QPointF contentPoint) const;
    QPoint voiceWindowPoint(QPointF itemPoint) const;
    QPointF voicePoint(uint64_t tick) const;
    void setPencilMode(bool enabled);
    QAction *pencilModeAction() const;
    songview::TimelineQuickScene *quickScene() const;

    SongTab &tab() noexcept;
    const SongTab &tab() const noexcept;
    AutomationPage &page() noexcept;
    const AutomationPage &page() const noexcept;
    songview::TimelineInputItem &automationInput() noexcept;
    songview::TimelineInputItem &automationGutterInput() noexcept;
    songview::TimelineInputItem &voiceChangeInput() noexcept;
    QQuickWindow &quickWindow() noexcept;

    FrozenDocumentState frozenDocumentState(int documentChanges = 0, int edits = 0) const;
    void mousePress(Qt::MouseButton button, const QPoint &windowPos,
                    Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    void mouseMove(const QPoint &windowPos, Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    void mouseRelease(Qt::MouseButton button, const QPoint &windowPos,
                      Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    void mouseDClick(Qt::MouseButton button, const QPoint &windowPos,
                     Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    void mousePress(const songview::TimelineInputItem &input, Qt::MouseButton button,
                    QPointF itemPoint, Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    void mouseMove(const songview::TimelineInputItem &input, QPointF itemPoint,
                   Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    void mouseRelease(const songview::TimelineInputItem &input, Qt::MouseButton button,
                      QPointF itemPoint, Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    void mouseDClick(const songview::TimelineInputItem &input, Qt::MouseButton button,
                     QPointF itemPoint, Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    void wheel(const songview::TimelineInputItem &input, QPointF itemPoint, QPoint angleDelta,
               Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    void sendWindowDeactivate();
    void keyEvent(QEvent::Type type, Qt::Key key, Qt::KeyboardModifiers modifiers = Qt::NoModifier,
                  bool autoRepeat = false);
    void keyPress(Qt::Key key, Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    void keyRelease(Qt::Key key, Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    void keyClick(Qt::Key key, Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    bool focusAutomationBand();

    // Activates a supported parameter through its real rendered gutter label.
    bool activateParameter(const EditorAutomationRowId &row);
    // Clicks a rendered gutter label with real event modifiers — drives the
    // canvas's modifier dispatch, unlike a direct toggle call.
    bool clickParameterTab(const EditorAutomationRowId &row,
                           Qt::KeyboardModifiers modifiers = Qt::NoModifier);

    // Pilot baseline setup retained with its original literals and assertions.
    void arrangeCcLane();
    QPointF ccPoint(uint64_t tick, int value) const;
    std::optional<ArmedCcDrag> armCcDrag(songview::TimelineQuickScene *quickScene);
    int laneValue(uint64_t tick) const;
    int timelineCcValue(uint64_t tick) const;

    // One rendered delete confirmation: the live session content plus its
    // named controls. The diagnostic explains why the form never appeared.
    struct CcDeletePrompt final {
        songview::QuickPopupSession *session = nullptr;
        QQuickItem *root = nullptr;
        QQuickItem *acceptButton = nullptr;
        QQuickItem *cancelButton = nullptr;
        QString diagnostic;
    };

    // Opens the confirmation through the real rendered gutter menu and a real
    // RemoveLane row click, then waits for the form to render.
    CcDeletePrompt openCcDeletePrompt(const EditorAutomationRowId &row, QString diagnostic);

    // One rendered node point menu: the live session, its typed row model,
    // and the located SetValue/DeleteNode rows. The diagnostic explains why
    // the menu never opened with both typed rows.
    struct NodePointMenu final {
        songview::QuickPopupSession *session = nullptr;
        songview::QuickMenuModel *model = nullptr;
        int setValueRow = -1;
        int deleteNodeRow = -1;
        QString diagnostic;
    };

    // Opens the node point menu through the real node right-press, then
    // waits for the shared Quick panel and locates both typed rows.
    NodePointMenu openNodePointMenu(LaneHandle lane, uint64_t tick, int value, QString diagnostic);

    // The tab borrows this bank, so it must outlive m_tab.
    LoadedVoiceGroup m_bank = {};
    std::unique_ptr<SongTab> m_tab;
    QPointer<AutomationPage> m_page;
    QPointer<songview::TimelineInputItem> m_automationInput;
    QPointer<songview::TimelineInputItem> m_automationGutterInput;
    QPointer<songview::TimelineInputItem> m_voiceInput;
    QPointer<QQuickWindow> m_quickWindow;
    bool m_windowEntered = false;
    Qt::MouseButtons m_heldButtons = Qt::NoButton;
    Qt::KeyboardModifiers m_lastModifiers = Qt::NoModifier;
    std::vector<Qt::Key> m_heldKeys;
    QPoint m_lastWindowPos;
};
