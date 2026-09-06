#pragma once

#include <QObject>
#include <QPointer>
#include <QStringList>

#include "audio/trackactivitylevel.h"
#include "core/miditimeline.h"

#include <memory>

class QQuickWindow;
class SongView;

namespace songview {
class TimelineQuickView;
class TrackHeaderModel;
} // namespace songview

class TrackActivityMeterTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(TrackActivityMeterTest)

  public:
    TrackActivityMeterTest() = default;

  private slots:
    void init();
    void cleanup();
    void roleScopedUpdatesAndPhysicalPixelBoundaries();
    void pauseRasterAndIntensityCapUseObservedDpr();
    void stereoRasterAndRebuiltTracksRetainIdentity();

  private:
    void present(const TrackActivityLevels &levels, bool playing);
    int rowForTrack(int track) const;

    std::shared_ptr<MidiTimeline> m_timeline;
    std::unique_ptr<SongView> m_view;
    QPointer<songview::TimelineQuickView> m_quick;
    QPointer<songview::TrackHeaderModel> m_model;
    QPointer<QQuickWindow> m_window;
};

int runTrackActivityMeterCheck(const QStringList &qtArguments);
