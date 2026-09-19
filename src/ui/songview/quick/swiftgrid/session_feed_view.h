#pragma once

#include <QObject>

#include "session_feed.h"

class SongView;

// The view outlives this GUI-thread observer. Destroy the observer before
// releasing the Swift recipient so no callback can borrow a released context.
// The feed observes SongView::selectionContextChanged plus the mask signals:
// EditorSelectionModel's observer slot is already owned by SongView itself,
// and the signal fires on exactly the transitions the observer reports.
class SwiftGridSessionFeed final : public QObject
{
  public:
    explicit SwiftGridSessionFeed(const SongView &view);
    ~SwiftGridSessionFeed() override;

    uint64_t sessionId() const { return m_sessionId; }
    const SgsDelivery *delivery() const { return &m_delivery; }
    // Harness seam for deterministic pushes; production pushes arrive via the
    // view signals on the GUI thread.
    void pushSnapshot();

  private:
    const SongView &m_view;
    const uint64_t m_sessionId;
    uint64_t m_revision = 0;
    SgsDelivery m_delivery{};
};
