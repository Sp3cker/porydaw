#pragma once

#include <cstdint>

#include <memory>
#include <optional>

#include <QByteArray>
#include <QObject>
#include <QPoint>
#include <QPointF>
#include <QPointer>
#include <QQuickWindow>

#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/songtab.h"
#include "ui/songview/quick/timelineinputitem.h"

class AutomationPage;

namespace songview {
class TimelineQuickScene;
}

class AutomationEditingTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(AutomationEditingTest)

  public:
    AutomationEditingTest() = default;

  private slots:
    void init();
    void cleanup();
    void ccDragCommitsOnce();
    void escapeCancelsCcDrag();
    void releaseWithoutActivationDoesNotCommit();

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

    void arrangeCcLane();
    LaneHandle ccLaneHandle() const;
    QPointF ccPoint(uint64_t tick, int value) const;
    QPoint windowPoint(const QPointF &contentPoint) const;
    std::optional<ArmedCcDrag> armCcDrag(songview::TimelineQuickScene *quickScene);
    FrozenDocumentState frozenDocumentState(int documentChanges, int edits) const;
    void mousePress(Qt::MouseButton button, const QPoint &windowPos,
                    Qt::KeyboardModifiers modifiers);
    void mouseMove(const QPoint &windowPos, Qt::KeyboardModifiers modifiers);
    void mouseRelease(Qt::MouseButton button, const QPoint &windowPos,
                      Qt::KeyboardModifiers modifiers);
    void focusAutomationBand();
    int laneValue(uint64_t tick) const;
    int timelineCcValue(uint64_t tick) const;

    // The tab borrows this bank, so it must outlive m_tab.
    LoadedVoiceGroup m_bank = {};
    std::unique_ptr<SongTab> m_tab;
    QPointer<AutomationPage> m_page;
    QPointer<songview::TimelineInputItem> m_automationInput;
    QPointer<QQuickWindow> m_quickWindow;
    // Escape cancels the gesture but deliberately does not clear this record;
    // cleanup still releases the originally held button before tab destruction.
    Qt::MouseButton m_heldButton = Qt::NoButton;
    QPoint m_lastWindowPos;
};
