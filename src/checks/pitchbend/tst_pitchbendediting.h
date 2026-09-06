#pragma once

#include <cstdint>
#include <memory>
#include <vector>

#include <QByteArray>
#include <QObject>
#include <QPoint>
#include <QPointF>
#include <QPointer>
#include <QString>
#include <QStringList>

#include <QQuickWindow>

#include "core/songdocument.h"
#include "ui/pitchbendeditor.hpp"
#include "ui/pitchbendgraph.hpp"
#include "ui/songtab.h"
#include "ui/songview/quick/timelineinputitem.h"

class PitchBendFixture final
{
  public:
    bool setUp(bool unterminated = false, bool duplicateNote = false);
    void tearDown();

    SongTab &tab() const;
    SongView &view() const;
    SongDocument &document() const;
    QQuickWindow &timelineWindow() const;
    songview::TimelineInputItem &rollInput() const;
    const DocNote &note() const;
    uint64_t endTick() const;
    QPoint notePoint() const;

    songview::PitchBendEditor *openPopup();
    songview::PitchBendEditor *popup() const;
    songview::PitchBendGraph *graph(const QString &objectName) const;
    QQuickItem *item(const QString &objectName) const;
    void closePopupViaEscape();
    void drainDeferredDeletes();

    QPoint windowPoint(const QQuickItem &item, QPointF local) const;
    bool stroke(songview::PitchBendGraph &graph, QPoint start, QPoint finish,
                Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    bool wheel(songview::PitchBendGraph &graph, QPoint point, QPoint angleDelta);
    bool scrub(QQuickItem &field, int steps, Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    bool click(QQuickItem &item);
    bool sendUndo();
    void assertNoteSelection() const;
    bool hasLanePoint(uint8_t cc, uint64_t tick, int value) const;
    int effectiveLaneValue(uint8_t cc, uint64_t tick, int fallback) const;
    std::vector<DocLanePoint> interiorPoints(uint8_t cc) const;
    QByteArray smf() const;

  private:
    LoadedVoiceGroup m_bank = {};
    std::unique_ptr<SongTab> m_tab;
    QPointer<QQuickWindow> m_timelineWindow;
    QPointer<songview::TimelineInputItem> m_rollInput;
    DocNote m_note;
    uint64_t m_endTick = 0;
};

class PitchBendEditingTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(PitchBendEditingTest)
  public:
    PitchBendEditingTest() = default;

  private slots:
    void init();
    void cleanup();

    void bendrFixtureUndoPreservation();
    void shiftDragDrawsLinearRamp();
    void freehandStrokePushesSingleUndoCommand();
    void standardUndoShortcutRestoresCurve();
    void navigationKeysDoNotModifyCurve_data();
    void navigationKeysDoNotModifyCurve();
    void stackedStrokesPushIndependentUndoCommands();
    void freehandStrokeConfinedToNoteSpan();
    void pitchWheelSerializesValidSmfEvents();
    void duplicateNoteAtSameTickDoesNotAnchorStaleNote();
    void activeGesturePreservesPreviewAcrossExternalEdit();
    void vertexCreation_data();
    void vertexCreation();
    void vertexHitTestAndSelection_data();
    void vertexHitTestAndSelection();
    void vertexAltDragMovesPoint_data();
    void vertexAltDragMovesPoint();
    void vertexDeleteRemovesInteriorPoint_data();
    void vertexDeleteRemovesInteriorPoint();
    void vertexEndpointDeletionIsRejected_data();
    void vertexEndpointDeletionIsRejected();
    void modWheelFreehandStrokeAndUndo();
    void altDragCreatesFineGridRamp();
    void strokeAcrossSignatureBoundaryAlignsToDynamicGrid();
    void modWheelResetZeroesLane();

    void wheelScrollConfinesBendRangeToNoteSpan_data();
    void wheelScrollConfinesBendRangeToNoteSpan();
    void controllerInputsAdvertiseScrubCursor();
    void bendRangeScrubWritesNoteBoundedCC14();
    void lfoSpeedShiftScrubWritesNoteBoundedCC15();
    void controllerStationaryClickFocusesAndSelectsText();
    void controllerUndoChainingPreservesPopupSession();
    void resetButtonZeroesCurveAndRestoresEndValue();
    void spaceAuditionsNoteFromStartTick();
    void soloAndMuteKeyArbitration();

    void keyGAnchorsPopupToSelectedNoteWithinWindowBounds();
    void popupDescriptionReflectsActiveBendr();
    void idleMouseMovementPreservesPopup();
    void enterKeyDoesNotDismissPopup();
    void internalEditsAndRefreshesKeepPopupOpen();
    void externalNoteMutationDismissesPopup();
    void escapeKeyDismissesPopupRetainingNoteSelection();
    void rollClickDismissesPopupAndPreservesSelection();
    void rollCursorTracksAfterDismissal();
    void reopeningPopupRestoresActiveGraphFocus();
    void dismissalRestoresRollEdgeCursor();
    void insideClickRetainedOutsideClickDismisses();
    void popupDismissalReturnsFocusToRollInputItem();
    void applicationDeactivateCommitsWithoutFocusRestore();
    void unterminatedNoteSpanRejectsEditing();

  private:
    bool drawPitchCurve(songview::PitchBendGraph &graph);
    bool drawModCurve(songview::PitchBendGraph &graph);
    songview::PitchBendGraph *pitchGraph();
    songview::PitchBendGraph *modGraph();
    songview::PitchBendEditor *popup();
    PitchBendFixture m_fixture;
};

class PitchBendRasterTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(PitchBendRasterTest)

  public:
    PitchBendRasterTest() = default;

  private slots:
    void init();
    void cleanup();
    void popupSurfaceIsOpaqueAndUsesWindowBackground();
    void shiftCurvePaintsDiagonal();
    void altRampPaintsDiagonalAfterReopen();
    void noteEdgeCursorPixmapAndArrowRestore();

  private:
    PitchBendFixture m_fixture;
};

int runPitchBendEditingCheck(const QStringList &qtArguments);
int runPitchBendRasterCheck(const QStringList &qtArguments);
