#pragma once

#include <QWidget>

class QEvent;
class QMouseEvent;
class QResizeEvent;
class SongView;

namespace songview {

class TimelineQuickScene;
class TimelineQuickView;

class OtherStrip : public QWidget
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
    bool event(QEvent *event) override;
    void resizeEvent(QResizeEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;

  private:
    friend class TimelineQuickView;
    void rebuildQuickScene(TimelineQuickScene &scene);
    void requestQuickUpdate();
    SongView *m_sv;
    Geometry m_geometry;
};

} // namespace songview
