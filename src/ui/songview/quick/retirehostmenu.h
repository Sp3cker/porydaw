#pragma once

#include "ui/songview/quick/quickmenumodel.h"
#include "ui/songview/quick/quickpopupsession.h"

namespace songview {

// Cancels only an active host menu rooted at ownedRoot. Other roots sharing
// the host and unrelated content in the popup session keep their lifetime.
inline void retireHostMenu(QuickPopupSession *session, QuickMenuHost *host,
                           const QuickMenuModel *ownedRoot, bool restoreFocus)
{
    if (!session || !host || !ownedRoot || !host->isOpen() || host->rootModel() != ownedRoot ||
        !session->owns(host))
        return;
    session->cancel(restoreFocus);
}

} // namespace songview
