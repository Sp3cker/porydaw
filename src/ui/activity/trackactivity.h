#pragma once

#include <array>
#include <cstdint>

extern "C" {
#include "m4a_engine.h"
}

class QColor;
class QPainter;
class QRectF;

class TrackActivity
{
  public:
    void advance(const std::array<uint8_t, MAX_TRACKS> &levels, float elapsedSeconds);
    void reset();
    float intensity(int track) const;
    void paintLight(QPainter &p, int track, const QRectF &barRect, const QColor &identityColor,
                    float maximumIntensity = 1.0f) const;

  private:
    std::array<float, MAX_TRACKS> m_intensities{};
};
