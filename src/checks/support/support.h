#pragma once

#include "ui/songview/grid.h"
class SongView;

namespace checks::support {

// Creates the fixture's per-view EditActions, parents them to that view, and
// rebinds them to it. Unlike production, fixtures deliberately do not install
// window shortcuts: their input targets the view directly. This single
// construction seam keeps any bind-order or lifetime change out of every rig.
// Returns the view for call-site chaining.
SongView &bindEditActionsForTest(SongView &view);

inline int alternateGridMenuId(songview::GridSelection selection)
{
    return (selection == songview::GridSelection::musical(8) ? songview::GridSelection::musical(16)
                                                             : songview::GridSelection::musical(8))
        .toMenuId();
}

} // namespace checks::support
