#include "ui/velocityaxis.h"

#include <algorithm>
#include <cmath>
#include <utility>

namespace songview {
namespace {

constexpr double kVelocityVerticalInset = 6.0;
constexpr int kMinimumVelocity = 1;
constexpr int kMaximumVelocity = 127;
constexpr double kDetentTopInset = 28.0;
constexpr double kDetentBottomInset = 10.0;

bool structurallyEqual(const VelocityDetentInfo &left,
                       const VelocityDetentInfo &right) {
  if (left.voiceType != right.voiceType ||
      left.levels.size() != right.levels.size())
    return false;
  return std::equal(
      left.levels.begin(), left.levels.end(), right.levels.begin(),
      [](const VelocityDetentLevel &a, const VelocityDetentLevel &b) {
        return a.velocity == b.velocity && a.audible == b.audible;
      });
}

} // namespace

VelocityAxis::VelocityAxis(double height,
                           std::optional<VelocityDetentInfo> detents)
    : m_height(height), m_detents(std::move(detents)) {}

double VelocityAxis::velocityToY(int velocity) const {
  const double top = kVelocityVerticalInset;
  const double bottom = m_height - kVelocityVerticalInset;
  return bottom - (velocity - kMinimumVelocity) * (bottom - top) /
                      (kMaximumVelocity - kMinimumVelocity);
}

int VelocityAxis::yToVelocity(double y) const {
  const double top = kVelocityVerticalInset;
  const double bottom = m_height - kVelocityVerticalInset;
  const double clampedY = std::clamp(y, top, bottom);
  return kMinimumVelocity +
         int(std::round((bottom - clampedY) *
                        (kMaximumVelocity - kMinimumVelocity) /
                        (bottom - top)));
}

double VelocityAxis::categoricalLevelToY(int level, int levelCount,
                                         double height) {
  const double bottom = std::max(0.0, height - kDetentBottomInset);
  const double top = std::min(kDetentTopInset, bottom);
  if (levelCount <= 1)
    return bottom;
  return bottom - level * (bottom - top) / (levelCount - 1);
}

double VelocityAxis::levelToY(int level) const {
  const int count = m_detents ? int(m_detents->levels.size()) : 0;
  return categoricalLevelToY(level, count, m_height);
}

int VelocityAxis::yToLevel(double y) const {
  const double bottom = std::max(0.0, m_height - kDetentBottomInset);
  const double top = std::min(kDetentTopInset, bottom);
  const int count = m_detents ? int(m_detents->levels.size()) : 0;
  if (count <= 1 || bottom <= top)
    return 0;
  const double clampedY = std::clamp(y, top, bottom);
  return std::clamp(
      int(std::round((bottom - clampedY) * (count - 1) / (bottom - top))),
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
  return m_detents && other && structurallyEqual(*m_detents, *other);
}

double velocityToY(int velocity, double height) {
  return VelocityAxis(height).velocityToY(velocity);
}

double velocityLevelToY(int level, int levelCount, double height) {
  return VelocityAxis::categoricalLevelToY(level, levelCount, height);
}

int yToVelocity(double y, double height) {
  return VelocityAxis(height).yToVelocity(y);
}

} // namespace songview
