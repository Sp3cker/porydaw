#include "ui/velocityaxis.h"
#include "ui/layout.h"

#include <algorithm>
#include <cmath>
#include <utility>

namespace songview {
namespace {

constexpr int kMinimumVelocity = 1;
constexpr int kMaximumVelocity = 127;

struct VerticalRange {
  double top;
  double bottom;
};

VerticalRange verticalRange(double height, double inset) {
  const double bottom = std::max(0.0, height - inset);
  return {std::min(inset, bottom), bottom};
}

} // namespace

VelocityAxis::VelocityAxis(double height,
                           std::optional<VelocityDetentInfo> detents)
    : m_height(height), m_verticalInset(layout::space(layout::Space::Three)),
      m_detents(std::move(detents)) {}

double VelocityAxis::velocityToY(int velocity) const {
  const VerticalRange range = verticalRange(m_height, m_verticalInset);
  return range.bottom - (velocity - kMinimumVelocity) *
                            (range.bottom - range.top) /
                            (kMaximumVelocity - kMinimumVelocity);
}

int VelocityAxis::yToVelocity(double y) const {
  const VerticalRange range = verticalRange(m_height, m_verticalInset);
  if (range.bottom <= range.top)
    return kMinimumVelocity;
  const double clampedY = std::clamp(y, range.top, range.bottom);
  return kMinimumVelocity +
         int(std::round((range.bottom - clampedY) *
                        (kMaximumVelocity - kMinimumVelocity) /
                        (range.bottom - range.top)));
}

double VelocityAxis::categoricalLevelToY(int level, int levelCount,
                                         double height, double inset) {
  const VerticalRange range = verticalRange(height, inset);
  if (levelCount <= 1)
    return range.bottom;
  return range.bottom - level * (range.bottom - range.top) / (levelCount - 1);
}

double VelocityAxis::levelToY(int level) const {
  const int count = m_detents ? int(m_detents->levels.size()) : 0;
  return categoricalLevelToY(level, count, m_height, m_verticalInset);
}

int VelocityAxis::yToLevel(double y) const {
  const VerticalRange range = verticalRange(m_height, m_verticalInset);
  const int count = m_detents ? int(m_detents->levels.size()) : 0;
  if (count <= 1 || range.bottom <= range.top)
    return 0;
  const double clampedY = std::clamp(y, range.top, range.bottom);
  return std::clamp(int(std::round((range.bottom - clampedY) * (count - 1) /
                                   (range.bottom - range.top))),
                    0, count - 1);
}

VelocityAxis::Mode VelocityAxis::mode() const {
  return m_detents ? Mode::Detented : Mode::Continuous;
}

const std::optional<VelocityDetentInfo> &VelocityAxis::detents() const {
  return m_detents;
}

bool VelocityAxis::compatibleWith(
    const std::optional<VelocityDetentInfo> &other) const {
  return m_detents && other && velocityDetentsCompatible(*m_detents, *other);
}

double velocityToY(int velocity, double height) {
  return VelocityAxis(height).velocityToY(velocity);
}

double velocityLevelToY(int level, int levelCount, double height) {
  return VelocityAxis::categoricalLevelToY(level, levelCount, height,
                                           layout::space(layout::Space::Three));
}

int yToVelocity(double y, double height) {
  return VelocityAxis(height).yToVelocity(y);
}

} // namespace songview
