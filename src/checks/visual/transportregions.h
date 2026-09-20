#pragma once

#include "checks/visual/visualbaseline.h"

#include <QList>

class TransportBar;

// The canonical transport strip region set, shared by every suite that pins
// the bar (chrome, transport, standalone window fixtures). One definition
// keeps the region names and clip rules identical wherever the strip is
// captured, including after the surface converts to a replacement renderer.
namespace checks::visual {

/// Regions of `bar`'s controls in the captured image's logical pixels: every
/// control visible to the bar, nominal geometry clipped to the bar's rect.
/// A missing control contributes a named region with empty bounds instead of
/// being dropped, so compare() fails loud rather than losing coverage.
QList<Region> transportRegions(TransportBar &bar);

} // namespace checks::visual
