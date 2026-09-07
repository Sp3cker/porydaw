#pragma once

// Module-internal layout engine for the quick menu (consumers of
// quickmenumodel.h never see this): converts menu rows plus the theme font
// into resolved column edges and frame geometry. Kept separate from the
// session driver so spacing and theme resolution change independently of
// menu session logic.
#include <QFont>
#include <QSizeF>
#include <QVariantMap>

class QFontMetrics;

namespace songview {

class QuickMenuModel;

/// Resolved paint numbers for one menu level; the panel is painted
/// exclusively from these values.
struct MenuMetrics {
    int rowHeight = 0;
    int separatorHeight = 1;
    int checkX = -1;
    int checkWidth = 0;
    int textX = 0;
    int textRight = 0;
    int shortcutRight = -1;
    int arrowRight = -1;
    int arrowWidth = 0;
    int menuWidth = 0;
    int menuHeight = 0;
};

/// The appearance "font" key, else the installed body font, else the
/// platform application font.
QFont resolveMenuFont(const QVariantMap &appearance);

/// One pass over the rows yields the check/text/shortcut/arrow column edges
/// and the frame size, capped to the window bounds so the view scrolls.
MenuMetrics measureMenu(const QuickMenuModel &model, const QFontMetrics &metrics,
                        const QSizeF &bounds);

} // namespace songview
