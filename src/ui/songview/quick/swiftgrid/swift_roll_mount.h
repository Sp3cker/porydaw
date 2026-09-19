#pragma once

#include <QObject>
#include <QPointer>
#include <cstdint>
#include <memory>
#include <optional>

class QQuickItem;
class QQuickView;
class SongView;

namespace songview {
struct TimelineBandGeometry;
}

class SwiftGridDocumentFeed;
class SwiftGridIntentExecutor;
class SwiftGridSessionFeed;

namespace songview {

// Production mount for the Swift roll overlay (spec.md §5): the document
// feed renders notes, the session feed publishes authoritative selection
// state, and the intent executor routes Swift's sgc_ submissions into the
// SongDocument undo stack. All three are constructed here (feed before
// executor, mirroring the swiftdocfeed harness) and destroyed before the
// overlay, so no submission or push can borrow a released context.
//
// The band target id is minted by the TimelineQuickView-owned
// SwiftGridKeyRouter before mount and travels into the overlay as an
// initial QML property alongside the session id; the overlay calls
// gridModel.bindEditing when both are present.
class SwiftRollMount final
{
  public:
    SwiftRollMount();
    ~SwiftRollMount();

    Q_DISABLE_COPY_MOVE(SwiftRollMount)

    bool mount(SongView &songView, QQuickView &view, uint64_t bandTargetId);
    void unmount();

    void updateBandGeometry(const std::optional<TimelineBandGeometry> &rollGeometry);
    void handleTransferredWindowDeath();
    void applyHostPalette();

    bool isMounted() const noexcept { return m_mounted; }
    QQuickItem *overlayItem() const noexcept { return m_overlayItem.data(); }

  private:
    // Destruction order is the reverse: executor unregisters first, then
    // the session and document feeds — and unmount() resets all three
    // explicitly before deleting the overlay.
    std::unique_ptr<SwiftGridDocumentFeed> m_feed;
    std::unique_ptr<SwiftGridSessionFeed> m_sessionFeed;
    std::unique_ptr<SwiftGridIntentExecutor> m_executor;
    QPointer<QQuickItem> m_overlayItem;
    QPointer<SongView> m_songView;
    QPointer<QQuickView> m_view;
    QMetaObject::Connection m_trackConnection;
    bool m_mounted = false;
};

} // namespace songview
