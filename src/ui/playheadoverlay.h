#pragma once

#include <QColor>
#include <QRect>
#include <QRegion>
#include <QString>
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

struct PlayheadFrame {
  QSize overlaySize;
  QRegion bodyClip;
  QRect triangleClip;
  QRect playheadGeometry;
  QColor color;
  qreal x;
  qreal devicePixelRatio;
  quint64 staticGeneration;
  bool visible;
  bool playing;
  bool trianglePointsUp;
};

enum class PlayheadSyncState { Applied, Deferred, Failed };
struct PlayheadSyncResult {
  PlayheadSyncState state;
  QString error;
};

class PlayheadBackend {
public:
  virtual ~PlayheadBackend() = default;
  virtual PlayheadSyncResult synchronize(const PlayheadFrame &frame) = 0;
};

std::unique_ptr<PlayheadBackend> createPlayheadBackend(QWidget &owner);

class PlayheadOverlay final : public QWidget {
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

    m_timelineX = timelineX;
    m_visible = visible;
    m_playing = playing;

    updatePlayhead();
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
  void observeSurfaceGeometry();
  void synchronizeGeometry();
  void synchronizeBackend();
  void updatePlayhead();

  QRegion playheadRegion() const;
  void updatePaintRegion();

  Surfaces m_surfaces;
  QColor m_color;

  std::unique_ptr<PlayheadBackend> m_backend;
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
  quint64 m_staticGeneration = 0;
  bool m_backendAttempted = false;
  bool m_backendApplied = false;
  bool m_backendSyncing = false;
  bool m_backendSyncPending = false;
};

} // namespace songview
