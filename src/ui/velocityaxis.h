#pragma once

#include <optional>

#include "core/psgvelocitymodel.h"

namespace songview {

class VelocityAxis {
public:
  enum class Mode { Continuous, Detented };

  explicit VelocityAxis(double height,
                        std::optional<VelocityDetentInfo> detents = std::nullopt);

  double velocityToY(int velocity) const;
  int yToVelocity(double y) const;
  double levelToY(int level) const;
  int yToLevel(double y) const;

  Mode mode() const;
  const std::optional<VelocityDetentInfo> &detents() const;
  bool compatibleWith(
      const std::optional<VelocityDetentInfo> &other) const;

private:
  static double categoricalLevelToY(int level, int levelCount,
                                    double height);
  friend double velocityLevelToY(int level, int levelCount, double height);

  double m_height;
  std::optional<VelocityDetentInfo> m_detents;
};

double velocityToY(int velocity, double height);
double velocityLevelToY(int level, int levelCount, double height);
int yToVelocity(double y, double height);

} // namespace songview
