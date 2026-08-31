#pragma once

#include "ui/timelinesurface.h"

class QEvent;
class QMouseEvent;
class QPainter;
class SongView;

namespace songview {

class TimelineQuickScene;
class TimelineQuickView;

class OtherStrip : public TimelineSurface
{
  private:
    struct Geometry {
        int plotOrigin;
        int otherEventHitSlop;
        int otherEventMarkerHalfWidth;
        int otherEventMarkerHalfHeight;

        static Geometry resolve();
    };

    void refreshGeometry();

  public:
    explicit OtherStrip(SongView *sv);

  protected:
    void paintContent(QPainter &p) override;
    bool event(QEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;

  private:
    friend class TimelineQuickView;
    void rebuildQuickScene(TimelineQuickScene &scene);
    void requestQuickUpdate();
    SongView *m_sv;
    Geometry m_geometry;
};

} // namespace songview
