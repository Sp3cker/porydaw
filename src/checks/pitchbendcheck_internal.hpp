#pragma once

#include <QByteArray>
#include <QEvent>
#include <QPoint>
#include <QPointF>
#include <QPointer>
#include <QRect>
#include <QString>
#include <cstdint>
#include <vector>

#include "pitchbendcheck.hpp"

class QColor;
class QImage;

namespace songview {
class CurveGraph;
class PitchBendEditor;
} // namespace songview

namespace pitchbendcheck {

void sendMouse(QWidget *widget, QEvent::Type type, QPoint pos, Qt::MouseButton button,
               Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers = Qt::NoModifier);
void sendWheel(QWidget *widget, QPointF pos, int angleDeltaY, int pixelDeltaY = 0,
               Qt::KeyboardModifiers modifiers = Qt::ControlModifier, int pixelDeltaX = 0);
void sendKey(QWidget *widget, int key, Qt::KeyboardModifiers modifiers);
bool sendStandardUndo(QWidget *widget);
void drainPopupDeletes();
void dismissPopup(QPointer<songview::PitchBendEditor> &popup);

class PitchBendCheckContext final
{
  public:
    PitchBendCheckContext(SongDocument &document, SongView &view, QWidget *roll, int engineTrack,
                          const DocNote &note, const QPoint &noteCenter, const QString &songLabel);

    int run();

  private:
    struct RangePopupState {
        songview::PitchBendEditor *popup = nullptr;
        songview::CurveGraph *graphWidget = nullptr;
        QRect graph;
    };

    struct PersistedAltPopupState {
        songview::PitchBendEditor *popup = nullptr;
        songview::CurveGraph *graphWidget = nullptr;
        QRect graph;
    };
    struct BoundaryFixtureState {
        QByteArray beforeSmf;
        int beforeUndoIndex = 0;
        std::vector<NoteId> beforeSelection;
        SongView::ViewState beforeViewState;
        uint64_t fixtureTick = 0;
        uint64_t fixtureEndTick = 0;
        uint64_t span = 0;
        uint8_t fixtureKey = 0;
        uint64_t editingCell = 0;
        double pixelsPerTick = 0.0;
        DocNote fixtureNote;
    };

    void fail(const char *what);
    void installRangeFixture();
    RangePopupState openRangePopup();
    void verifyRangeWheelConfinement(const RangePopupState &range);
    bool driveRangeFreehand(const RangePopupState &range);
    bool verifyPopupUndo(const RangePopupState &range);
    bool verifyKeyboardControlsIgnored(const RangePopupState &range);
    void verifyStackedCurveUndo(const RangePopupState &range);
    void verifyRangeCurve();
    void verifyRangeRawPitchWheel();
    void undoRangeFreehand();
    void runDuplicateAnchor();
    void runSnapshotDuringGesture();
    void runLifecycleCancellation();
    void runRangeFreehandAndUndo();
    void runVertexEditing();
    void runVertexEditingGraph(songview::CurveGraph *graph, uint8_t cc);
    void runModWheelEditing();
    void runPointClickAndEscape();
    void runModWheelShiftLine();
    void runControllerButtons();
    void verifyShiftLinePreview(const RangePopupState &range);
    bool openPersistedAltPopup(PersistedAltPopupState *state);
    void drivePersistedAltRamp(const PersistedAltPopupState &state);
    bool reopenPersistedAltPopup(PersistedAltPopupState *state);
    bool persistedCurvePixelNear(const QImage &image, qreal dpr, QPoint logical,
                                 const QColor &curveColor);
    void verifyPersistedAltDiagonal(const PersistedAltPopupState &state);
    void restorePersistedAltCurve();
    void runPersistedAltRendering();
    void runResetAndAudition();
    void runFocusHandoff();
    void cleanupBaseFixture();
    void runActiveGridBoundary();
    void restoreBoundaryFixture(const BoundaryFixtureState &fixture);
    bool createBoundaryFixture(BoundaryFixtureState *fixture);
    songview::PitchBendEditor *openBoundaryPopup(const BoundaryFixtureState &fixture,
                                                 const char *failure);
    bool inspectBoundaryFixturePopup(BoundaryFixtureState *fixture);
    bool driveBoundaryFreehand(BoundaryFixtureState *fixture);
    void verifyBoundarySamples(const BoundaryFixtureState &fixture);

    SongDocument &m_document;
    SongView &m_view;
    QWidget *m_roll = nullptr;
    int m_engineTrack = -1;
    DocNote m_note;
    QPoint m_noteCenter;
    QString m_songLabel;
    int m_failures = 0;
    QByteArray m_beforeRange;
    QByteArray m_beforeBend;
    QByteArray m_beforeCurve;
    int m_beforeRangeUndoIndex = 0;
    int m_undoIndex = 0;
    int m_curveUndoIndex = 0;
    uint64_t m_endTick = 0;
    int m_bendAtEnd = 0;
};

} // namespace pitchbendcheck
