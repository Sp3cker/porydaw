#pragma once

#include <QObject>
#include <QPointer>
#include <memory>
#include <optional>

class QQuickItem;
class QQuickView;
class SongView;

namespace songview {
struct TimelineBandGeometry;
}

class SwiftGridDocumentFeed;

namespace songview {

class SwiftRollMount final
{
  public:
    SwiftRollMount();
    ~SwiftRollMount();

    Q_DISABLE_COPY_MOVE(SwiftRollMount)

    bool mount(SongView &songView, QQuickView &view);
    void unmount();

    void updateBandGeometry(const std::optional<TimelineBandGeometry> &rollGeometry);
    void handleTransferredWindowDeath();

    bool isMounted() const noexcept { return m_mounted; }
    QQuickItem *overlayItem() const noexcept { return m_overlayItem.data(); }

  private:
    std::unique_ptr<SwiftGridDocumentFeed> m_feed;
    QPointer<QQuickItem> m_overlayItem;
    QPointer<SongView> m_songView;
    QPointer<QQuickView> m_view;
    QMetaObject::Connection m_trackConnection;
    bool m_mounted = false;
};

} // namespace songview
