#pragma once

#include <cstdint>

#include <memory>
#include <vector>

#include <QObject>
#include <QPoint>
#include <QPointF>
#include <QPointer>
#include <QQuickWindow>

#include "core/noteid.h"
#include "core/songdocument.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/songtab.h"
#include "ui/songview/quick/timelineinputitem.h"

class VelocityEditingTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(VelocityEditingTest)

  public:
    VelocityEditingTest() = default;

  private slots:
    void init();
    void cleanup();
    void dragCommitsOnce();
    void escapeCancelsDrag();
    void releaseWithoutMoveIsNoop();
    void pointerUngrabCancelsProvisionalSelection();
    void bandSelectionExpandsAndContracts();
    void bandUngrabRestoresSelection();
    void selectedCircleWinsOverStem();
    void unselectedCircleWinsOverSelectedStem();
    void selectedStemWinsAtStackedStem();
    void movedNodeDoesNotClickThrough();
    void rightPressPreservesSelectedGroup();
    void paintCommitsOnce();
    void rampCommitsOnce();
    void blankClickDeselectsOnRelease();
    void graduationClickEditsSelectedNotes();
    void clickBelowSelectedNodeChangesOnlySelection();
    void rollDragCommitsOnce();
    void controllerCancellationStopsRollDrag();
    void escapeStopsRollDrag();
    void velocityFocusOctaveShortcutMovesSelectedNotes();
    void rulerUnlockKeepsRawVelocity_data();
    void rulerUnlockKeepsRawVelocity();
    void lockedPaintUsesDetents_data();
    void lockedPaintUsesDetents();
    void unlockedPaintKeepsRawVelocities_data();
    void unlockedPaintKeepsRawVelocities();
    void lateUnlockKeepsGestureSnapped_data();
    void lateUnlockKeepsGestureSnapped();
    void unlockedRelativeKeepsOffsets_data();
    void unlockedRelativeKeepsOffsets();
    void unlockedRampInterpolates_data();
    void unlockedRampInterpolates();

  private:
    void selectDragPair();
    QPointF nodePoint(uint8_t velocity, uint64_t tick) const;
    QPoint windowPoint(const QPointF &itemLocal) const;
    void mousePress(Qt::MouseButton button, const QPoint &windowPos,
                    Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    void mouseMove(const QPoint &windowPos, Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    void mouseRelease(Qt::MouseButton button, const QPoint &windowPos,
                      Qt::KeyboardModifiers modifiers = Qt::NoModifier);
    void focusVelocityBand();
    int documentVelocity(NoteId noteId) const;
    int timelineVelocity(NoteId noteId) const;
    bool noteSelectionIs(const std::vector<NoteId> &expected) const;

    // Value-owned bank first: the tab borrows it, so declaration order must
    // keep it alive past every tab reset below.
    LoadedVoiceGroup m_bank = {};
    std::unique_ptr<SongTab> m_tab;
    QPointer<VelocityArea> m_area;
    QPointer<songview::TimelineInputItem> m_velocityInput;
    QPointer<songview::TimelineInputItem> m_rollInput;
    QPointer<QQuickWindow> m_quickWindow;
    // The fixture's three notes, resolved once per case in init() in SMF
    // event order: the quiet duplicate, the loud duplicate, the tick-60 note.
    DocNote m_quietStacked;
    DocNote m_loudStacked;
    DocNote m_later;
    // Held-input record for the failure-safe cleanup; Escape cancels the
    // interaction but never this record.
    Qt::MouseButton m_heldButton = Qt::NoButton;
    QPoint m_lastWindowPos;
};
