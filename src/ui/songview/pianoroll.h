#pragma once

#include <QCursor>
#include <QFont>
#include <QMouseEvent>
#include <QRectF>
#include <QString>
#include <QWidget>
#include <array>
#include <cstdint>
#include <functional>
#include <optional>
#include <vector>

#include "core/songdocument.h"
#include "ui/contextmenu.h"
#include "ui/pitchprojection.h"
#include "ui/songview.h"
#include "ui/songviewmodel.h"

class QAction;
class QEvent;
class QFontMetricsF;
class QKeyEvent;
class QPixmap;
class QWheelEvent;

namespace songview {
class PianoRollQuickView;
class PitchBendEditor;
} // namespace songview

namespace songview::pianoroll_detail {

enum class NoteMenuChoice {
    None,
    Velocity,
    Copy,
    Cut,
    Delete,
};

class NoteContextMenu final : public ui::ContextMenu
{
  public:
    explicit NoteContextMenu(QWidget *parent, std::function<bool(QPointF)> onOutsideRightClick);
    void showMenuAt(QPoint globalPos, int velocity);
    NoteMenuChoice handleAction(QAction *action) const;

  private:
    QAction *m_velocityAction = nullptr;
    QAction *m_copyAction = nullptr;
    QAction *m_cutAction = nullptr;
    QAction *m_deleteAction = nullptr;
};

struct PianoRollGeometry {
    int minimumVisiblePianoRollHeight;
    int pianoKeyboardWidth;
    int midiCursorExtent;
    int pianoRollNoteMinimumWidth;
    int pianoRollNoteMinimumHeight;
    qreal pianoRollNoteEdgeGripReach;
    qreal pianoRollNoteMoveZoneMinimumWidth;
    qreal selectionRingDipWidth;
    int noteBorderDashLength;
    int noteBorderDashGap;
    int keyboardHoverChipHorizontalPadding;
    int keyboardHoverChipVerticalPadding;
    int keyboardHoverChipRightInset;
    int velocityLabelFitAllowance;
    int keyboardHoverChipCornerRadius;
    int pianoKeyboardLabelRightInset;

    static PianoRollGeometry resolve();
};

struct MidiCursors {
    qreal dpr;
    QCursor leftEdge;
    QCursor rightEdge;
};

QCursor centeredCursor(const QPixmap &pm);
MidiCursors loadMidiCursors(qreal devicePixelRatio, int cursorExtent);

} // namespace songview::pianoroll_detail

namespace songview {

class PianoRoll : public QWidget
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(PianoRoll)
  public:
    explicit PianoRoll(SongView *sv);

    bool gestureActive() const;
    void cancelPitchBendPopup();
    void cancelVelocityInteraction();
    void refreshTextLayout();
    void copySelectedNotes();
    // Routes a semantic dirty union to the retained Quick scene.
    void requestQuickUpdate(PianoRollQuickDirtySet dirty);

  protected:
    bool event(QEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseDoubleClickEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void leaveEvent(QEvent *) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void keyPressEvent(QKeyEvent *event) override;
    void keyReleaseEvent(QKeyEvent *event) override;

  private:
    friend class PianoRollQuickView;
    enum class LeftDrag {
        None,
        PendingDraw,
        PendingVelocity,
        Draw,
        Move,
        Resize,
        ResizeLeft,
        Velocity
    };
    enum class RightDrag { None, PendingMenu, Band, TimeSel };

    bool insideTimeSelection(qreal x) const;
    const std::array<qreal, PitchProjection::cMaxRows + 1> &rowEdges() const;
    QRectF pitchRowRect(int row, qreal x, qreal width) const;
    qreal keyTop(int key) const;
    qreal keyBottom(int key) const;
    QRectF keyRect(int key, qreal x, qreal width) const;
    int yToKey(qreal y) const;
    int foldDegreeDeltaForPointer(qreal y) const;
    qreal physicalPixel() const;

    struct KeyboardHoverGeometry {
        QRectF highlightRect;
        QString name;
        QFont chipFont;
        QRectF chipRect;
    };

    std::optional<KeyboardHoverGeometry> keyboardHoverGeometry(int key) const;
    void setHoverKey(int key);
    void updateHoverKey(const QMouseEvent *event);
    void panMove(const QMouseEvent *event);
    void kbdGlissandoMove(const QMouseEvent *event);
    void endPanGesture();
    void endKbdAudition();
    void stopNoteAudition();
    void auditionKey(int key, int velocity);

    bool dragLive() const;
    static bool isLiveDrag(LeftDrag drag);
    static bool isLiveDrag(RightDrag drag);
    void activateLeftDrag(LeftDrag state);
    void clearLiveDragToken();
    void abortLiveLeftDrag();
    bool resolvePendingPresses(const QMouseEvent *event);
    void beginPanGesture(const QMouseEvent *event);
    void beginKbdAudition(const QMouseEvent *event);
    std::vector<NoteId> notesOnKey(int key) const;
    void beginPendingMenu(const QMouseEvent *event, const ViewNote *hit);
    void beginLeftPress(const QMouseEvent *event);
    void pressContent(QMouseEvent *event);
    bool contentPressRejectedByScaleFold(const SongDocument *doc, const ViewNote *hit) const;
    void beginNotePress(const ViewNote &note, const QMouseEvent *event);
    void applyNotePressSelection(const ViewNote &note, bool onEdge,
                                 Qt::KeyboardModifiers modifiers);
    bool noteRequiresSelectionUpdate(const ViewNote &note) const;
    void armNoteDrag(const ViewNote &note, QPointF position);
    void beginVelocityPress(const ViewNote &note);
    void beginPendingDraw(const QMouseEvent *);
    void beginDraw();
    void resolveRightPress(const QMouseEvent *event);
    void resolveDrawPress(const QMouseEvent *event);
    bool resolveVelocityPress(const QMouseEvent *event);
    void applyVelocityDragSelection();
    void updateMoveDrag(const QMouseEvent *event);
    void auditionMovedSelection();
    void updateResizeDrag(const QMouseEvent *event);
    void updateVelocityDrag(const QMouseEvent *event);
    void updateDrawDrag(const QMouseEvent *event);
    bool isDrawableKey(int key) const;
    void drawSpanAt(double tick, uint64_t grid, uint64_t &start, int64_t &dur) const;
    void updateTimeSelDrag(const QMouseEvent *event);
    void updateBandDrag();
    void updateLeftDragMove(const QMouseEvent *event);
    void dispatchLiveDragMove(const QMouseEvent *event);
    void releaseRightPress(QMouseEvent *event);
    void releasePendingMenu(QMouseEvent *event, SongDocument *doc);
    bool releasePendingLeftPress(QMouseEvent *event);
    void releasePendingDrawClick(QMouseEvent *event);
    void releasePendingVelocityClick(QMouseEvent *);
    bool finishReleaseWithoutCommit(const QMouseEvent *event);
    void commitDrag(QMouseEvent *);
    void commitDrawDrag();
    void commitMoveDrag();
    void commitResolvedMove(SongDocument &doc, std::vector<DocNote> &notes);
    void commitResizeDrag(LeftDrag drag, SongDocument *doc);
    void commitVelocityDrag(SongView::VelocityCommitResult);
    void completeProjectionGesture();
    QRectF noteRect(qreal x0, qreal x1, int key) const;
    QRectF noteRect(const ViewNote &note) const;
    QRectF noteBox(const QRectF &rect) const;
    int velocityLabelHeight() const;
    const ViewNote *hitNote(QPointF pos) const;
    bool nearRightEdge(const ViewNote &note, QPointF pos) const;
    bool nearLeftEdge(const ViewNote &note, QPointF pos) const;
    void refreshHoverCursor(QPointF pos, Qt::KeyboardModifiers modifiers);
    void refreshHoverAtCursor();

    void openPitchBendEditor();
    std::vector<DocNote> resolveSelection() const;
    void transposeSelection(int dKey);
    void nudgeSelection(bool right);
    void copyNotes(const std::vector<DocNote> &notes);
    void pasteAtEditCursor();
    void selectAllNotes();

    bool noteNameFits(const QRectF &noteRect, int key, const QFontMetricsF &metrics) const;
    QRectF displayedNoteRect(const ViewNote &note) const;
    int displayedNoteKey(const ViewNote &note) const;

    void showNoteMenu(QPointF localPos);
    bool focusNoteUnderCursor(QPointF globalPos);
    bool moveNoteMenu(QPointF globalPos);
    void handleNoteMenuChoice(pianoroll_detail::NoteMenuChoice choice);

    void rebuildFontCache();
    void auditionBandEntrants(const QRectF &band);
    void stopBandAuditions();
    void selectBand(const QRectF &band, bool additive);

    std::optional<QFont> m_velocityLabelFont;
    std::optional<QFont> m_noteNameFont;
    std::optional<QFont> m_keyboardLabelFont;
    QFont m_fixedNoteNameFont;
    int m_fixedNoteNameOccupiedHeight = 0;
    QFont m_keyboardHoverChipFont;
    int m_keyboardHoverChipHeight = 0;
    std::array<int, 128> m_keyboardHoverNameWidths{};
    SongView *m_sv;
    pianoroll_detail::PianoRollGeometry m_geometry;
    pianoroll_detail::MidiCursors m_cursors;
    mutable std::array<qreal, PitchProjection::cMaxRows + 1> m_rowEdges{};
    mutable int m_rowEdgeCount = 0;
    mutable qreal m_rowEdgesDpr = 0.0;
    mutable qreal m_rowEdgesKeyHeight = 0.0;
    mutable qreal m_rowEdgesScrollY = 0.0;
    mutable uint64_t m_rowEdgesProjectionRevision = 0;
    mutable bool m_rowEdgesValid = false;
    LeftDrag m_leftDrag = LeftDrag::None;
    RightDrag m_rightDrag = RightDrag::None;
    QPointF m_pressPos;
    QPointF m_curPos;
    double m_pressTick = 0.0;
    int m_pressKey = 0;
    uint64_t m_gripTick = 0;     // edge tick grabbed by a resize drag
    uint64_t m_gripOpposite = 0; // the note's other edge (the pivot)
    int64_t m_dTick = 0;
    int m_dKey = 0; // semitones, or scale degrees during a Fold move
    int64_t m_dDur = 0;
    int m_dVel = 0;
    uint64_t m_drawTick = 0; // pending note of a draw gesture
    int64_t m_drawDur = 0;
    int m_drawKey = 0;               // follows the cursor vertically mid-draw
    uint64_t m_drawAnchor = 0;       // grid cell pressed; drags pivot around it
    bool m_rightShift = false;       // …with Shift: drag sweeps a time selection
    uint64_t m_rightAnchorTick = 0;  // snapped tick of the right press
    bool m_rightHit = false;         // that press landed on a note…
    NoteId m_rightHitId{};           // …this one
    std::vector<ViewNote> m_bandAud; // notes the band currently covers; entrants audition
    ViewNote m_velAnchor{};          // pressed note of a velocity drag (a copy)
    int m_velAudEff = -1;            // last effective velocity auditioned mid-drag
    Qt::KeyboardModifiers m_velModMods = Qt::NoModifier; // that press's chord
    int m_kbdKey = -1;            // key sounding from a keyboard-column press
    int m_soundingKey = -1;       // auditioned key highlighted on the keyboard
    int m_hoverKey = -1;          // key row under the cursor; -1 = no mark
    bool m_auditioned = false;    // a drag/draw preview note is sounding
    uint8_t m_lastVelocity = 100; // latches to touched/velocity-edited notes
    bool m_panning = false;       // middle-drag pan
    QPointF m_panPos;             // last pan sample, global coords
    PitchBendEditor *m_bendPopup = nullptr;
    pianoroll_detail::NoteContextMenu *m_noteMenu = nullptr;
    PianoRollQuickView *m_quickView = nullptr;
};

} // namespace songview
