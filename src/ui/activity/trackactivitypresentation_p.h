#pragma once

#include <memory>
#include <span>

#include "ui/activity/trackactivitypresentation.h"
#include "ui/activity/trackactivityrender.h"

class QWidget;

namespace track_activity_detail {

class Backend
{
  public:
    virtual ~Backend() = default;

    virtual void setTracks(std::span<const TrackActivityPresentation::TrackDefinition> tracks,
                           track_activity_render::RowGeometry geometry) = 0;
    virtual void present(const TrackActivity &activity, bool playing) = 0;
    virtual void synchronize() = 0;
};

std::unique_ptr<Backend> makeQuickBackend(QWidget &owner);

#ifdef Q_OS_MACOS
std::unique_ptr<Backend> makeMacBackend(QWidget &owner);
#endif

} // namespace track_activity_detail
