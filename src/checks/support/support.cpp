#include "checks/support/support.h"

#include "ui/songview.h"
#include "ui/songview/editactions.h"

namespace checks::support {

SongView &bindEditActionsForTest(SongView &view)
{
    auto *const editActions = new songview::EditActions(&view);
    editActions->rebind(&view);
    return view;
}

} // namespace checks::support
