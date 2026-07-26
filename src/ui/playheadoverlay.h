#pragma once

#include <QColor>
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
  return playing ? (kPlayheadLineWidth / 2.0)
                 : static_cast<qreal>(kPlayheadGlowRadius);
}

inline constexpr qreal playheadPeakAlpha(bool playing) {
  return playing ? kPlayheadPeakPlaying : kPlayheadPeakPaused;
}

class PlayheadOverlay final : public QWidget {
  class Platform;
  struct PlatformDeleter {
    void operator()(Platform *platform) const;
  };

public:
  struct Surfaces {
    QWidget *ruler = nullptr;
    int rulerOrigin = 0;
    QWidget *roll = nullptr;
    int rollOrigin = 0;
    QWidget *lanes = nullptr;
    int lanesOrigin = 0;
    QWidget *strip = nullptr;
    int stripOrigin = 0;
  };

  PlayheadOverlay(QWidget *owner, const Surfaces &surfaces);
  ~PlayheadOverlay() override;

  inline void setPlayhead(qreal timelineX, bool visible, bool playing) {
    if (m_timelineX == timelineX && m_visible == visible &&
        m_playing == playing)
      return;

    const bool playingChanged = m_playing != playing;
    m_timelineX = timelineX;
    m_visible = visible;
    m_playing = playing;

    updatePlayhead(playingChanged);
  }

protected:
  bool eventFilter(QObject *watched, QEvent *event) override;
  void changeEvent(QEvent *event) override;
  void paintEvent(QPaintEvent *event) override;

private:
  qreal finalX() const {
    return static_cast<qreal>(m_timelineOrigin) + m_timelineX;
  }

  QRect visibleSurfaceRect(const QWidget *surface, QWidget *owner,
                           int origin) const;
  void synchronizeGeometry();
  void updatePlayhead(bool playingChanged);

  void initializePlatform(QWidget &owner);
  void attachPlatformToNativeView();
  void setPlatformLayout();
  void setPlatformAppearance();
  void setPlatformPosition();

  QRegion playheadRegion() const;
  void updatePaintRegion();

  Surfaces m_surfaces;
  QColor m_color;

  std::unique_ptr<Platform, PlatformDeleter> m_platform;
  QRegion m_lastPaintedRegion;

  QRegion m_visibleSurfaceRegion;
  QRect m_playheadGeometry;
  QRect m_triangleClip;
  qreal m_timelineX = 0.0;
  int m_timelineOrigin = 0;
  bool m_visible = false;
  bool m_playing = false;

  bool m_trianglePointsUp = false;
  qreal m_devicePixelRatio = 1.0;
};

} // namespace songview
