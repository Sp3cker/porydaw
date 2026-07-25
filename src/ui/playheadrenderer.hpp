#pragma once

#include <QColor>
#include <QRect>
#include <QRegion>
#include <array>
#include <cstddef>
#include <memory>

class QEvent;
class QPaintEvent;
class QWidget;

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

struct PlayheadLayout {
  QRect overlayFrame;
  QRegion visibleSurfaceRegion;
  QRect playheadGeometry;
  QRect triangleClip;
  bool trianglePointsUp = false;
  qreal contentsScale = 1.0;

  bool operator==(const PlayheadLayout &other) const {
    return overlayFrame == other.overlayFrame &&
           visibleSurfaceRegion == other.visibleSurfaceRegion &&
           playheadGeometry == other.playheadGeometry &&
           triangleClip == other.triangleClip &&
           trianglePointsUp == other.trianglePointsUp &&
           contentsScale == other.contentsScale;
  }
};

struct PlayheadAppearance {
  QColor themeColor;
  bool playing = false;

  bool operator==(const PlayheadAppearance &other) const {
    return themeColor == other.themeColor && playing == other.playing;
  }
};

struct PlayheadState {
  qreal finalX = 0.0;
  bool visible = false;

  bool operator==(const PlayheadState &other) const {
    return finalX == other.finalX && visible == other.visible;
  }
};

struct PlayheadPresentation {
  PlayheadLayout layout;
  PlayheadAppearance appearance;
  PlayheadState state;

  bool operator==(const PlayheadPresentation &other) const {
    return layout == other.layout && appearance == other.appearance &&
           state == other.state;
  }
};

class PlayheadRenderer final {
public:
  explicit PlayheadRenderer(QWidget &overlay);
  ~PlayheadRenderer();

  PlayheadRenderer(const PlayheadRenderer &) = delete;
  PlayheadRenderer &operator=(const PlayheadRenderer &) = delete;

  void synchronize(const PlayheadPresentation &presentation);
  void paint(QPaintEvent *event);

private:
  class Impl;
  std::unique_ptr<Impl> m_impl;
};

} // namespace songview
