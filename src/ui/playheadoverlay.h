#pragma once

#include <QColor>
#include <QImage>
#include <QRect>
#include <QRegion>
#include <QWidget>
#include <array>
#include <cstddef>
#include <memory>

class QEvent;
class QPaintEvent;

namespace songview {

constexpr int kPlayheadGlowRadius = 10;
constexpr int kPlayheadTriangleHalfWidth = 4;
constexpr int kPlayheadTriangleHeight = 8;
constexpr qreal kPlayheadLineWidth = 1.0;
constexpr qreal kPlayheadPeakPlaying = 0.13;
constexpr qreal kPlayheadPeakPaused = 0.06;

struct PlayheadGradientStop {
  qreal position;    // 0.0 to 1.0
  qreal alphaFactor; // t * t
};

constexpr std::array<PlayheadGradientStop, 9> kPlayheadGradientStops = [] {
  std::array<PlayheadGradientStop, 9> stops{};
  for (int i = 0; i <= 8; ++i) {
    const qreal t = static_cast<qreal>(i) / 8.0;
    stops[static_cast<std::size_t>(i)] = PlayheadGradientStop{t, t * t};
  }
  return stops;
}();

inline constexpr qreal playheadGlowLeftExtent(bool playing) {
  return playing ? static_cast<qreal>(kPlayheadGlowRadius - 1)
                 : static_cast<qreal>(kPlayheadGlowRadius);
}

inline constexpr qreal playheadGlowRightExtent(bool playing) {
  return playing ? 0.0 : static_cast<qreal>(kPlayheadGlowRadius);
}

inline constexpr qreal playheadPeakAlpha(bool playing) {
  return playing ? kPlayheadPeakPlaying : kPlayheadPeakPaused;
}

class PlayheadOverlay final : public QWidget {
  class Platform;

public:
  // Every timeline-aligned widget the playhead must cross, with each one's
  // content origin (the local x of timeline tick 0's column). A surface
  // missing from this list silently gets no playhead — a new timeline
  // widget in SongView must be added here.
  struct Surfaces {
    QWidget &ruler;
    int rulerOrigin;
    QWidget &roll;
    int rollOrigin;
    QWidget &lanes;
    int lanesOrigin;
    QWidget &strip;
    int stripOrigin;
  };

  PlayheadOverlay(QWidget &owner, const Surfaces &surfaces);
  ~PlayheadOverlay() override;

  void setPlayhead(qreal timelineX, bool visible, bool playing);

  qreal finalX() const {
    return static_cast<qreal>(m_timelineOrigin) + m_timelineX;
  }

protected:
  bool eventFilter(QObject *watched, QEvent *event) override;
  void changeEvent(QEvent *event) override;
  void paintEvent(QPaintEvent *event) override;

private:
  QRect visibleSurfaceRect(const QWidget &surface, QWidget &owner,
                           int origin) const;
  void synchronizeGeometry();
  void updateArtwork();

  void initializePlatform();
  void synchronizePlatform();
  void paintPlatform(QPaintEvent *event);

  Surfaces m_surfaces;
  struct PlatformDeleter {
    void operator()(Platform *platform) const;
  };
  std::unique_ptr<Platform, PlatformDeleter> m_platform;

  QRegion m_visibleSurfaceRegion;
  QRect m_playheadGeometry;
  QRect m_triangleClip;
  qreal m_timelineX = 0.0;
  int m_timelineOrigin = 0;
  bool m_visible = false;
  bool m_playing = false;

  bool m_trianglePointsUp = false;
  qreal m_devicePixelRatio = 1.0;
  QColor m_themeColor;

  QImage m_bodyImage;
  qreal m_bodyImageLeftExtent = 0.0;
  QImage m_triangleImage;

  int m_cachedHeight = -1;
  bool m_cachedPlaying = false;
  bool m_cachedTrianglePointsUp = false;
  qreal m_cachedDevicePixelRatio = 0.0;
  QColor m_cachedThemeColor;
};

} // namespace songview
