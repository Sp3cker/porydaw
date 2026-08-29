#pragma once

#include <QColor>
#include <QObject>
#include <QPointer>
#include <memory>
#include <span>
#include <vector>

#include "ui/activity/trackactivity.h"
#include "ui/activity/trackactivityrender.h"

class QEvent;
class QWidget;

namespace track_activity_detail {
class Backend;
}

class TrackActivityPresentation final : public QObject
{
    Q_DISABLE_COPY_MOVE(TrackActivityPresentation)

  public:
    struct TrackDefinition {
        int track;
        QColor identityColor;
    };

    explicit TrackActivityPresentation(QWidget &owner);
    ~TrackActivityPresentation() override;

    // Reconfigures rows and geometry only. The last presented activity/playing
    // state is cached here and reapplied to the backend immediately, so a
    // track/geometry reset redraws the current state without a follow-up
    // present() from the owner.
    void setTracks(std::span<const TrackDefinition> tracks,
                   track_activity_render::RowGeometry geometry);
    void present(const TrackActivity &activity, bool playing);

  private:
    bool eventFilter(QObject *watched, QEvent *event) override;
    void observeOwnerGeometry();
    void removeObservedChainFilters();

    QWidget &m_owner;
    std::unique_ptr<track_activity_detail::Backend> m_backend;
    TrackActivity m_activity;
    bool m_playing = false;
    std::vector<QPointer<QWidget>> m_observedChain;
};
