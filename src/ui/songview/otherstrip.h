#pragma once

#include "ui/songview/quick/timelineinput.h"

#include <QObject>
class SongView;

namespace songview {

class TimeCamera;
class TimelineQuickScene;
class TimelineQuickView;

class OtherStrip final : public QObject, public TimelineBandInteraction
{
    Q_OBJECT
  private:
    struct Geometry {
        int otherEventHitSlop;
        int otherEventMarkerHalfWidth;
        int otherEventMarkerHalfHeight;

        static Geometry resolve();
    };

    void refreshGeometry();

  public:
    explicit OtherStrip(SongView &owner, QObject *parent = nullptr);

    void attachInputHost(TimelineInputHost &host) override;
    void detachInputHost(TimelineInputHost &host) override;
    bool pointerMove(const TimelinePointerInput &input) override;
    void pointerLeave() override;
    void inputCancelled(TimelineInputCancelReason reason) override;
    void hostAppearanceChanged() override;

  private:
    friend class TimelineQuickView;
    void rebuildQuickScene(TimelineQuickScene &scene);
    void requestQuickUpdate();
    SongView &m_owner;
    const songview::TimeCamera &m_camera;
    TimelineInputHost *m_inputHost = nullptr;
    Geometry m_geometry;
};

} // namespace songview
