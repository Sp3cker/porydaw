#include "ui/songview/quick/quickmenulayout.h"

#include "ui/layout.h"
#include "ui/songview/quick/quickmenumodel.h"
#include "ui/typography.h"

#include <QFontMetrics>
#include <QGuiApplication>
#include <algorithm>

namespace songview {

namespace {

// Resolved lazily on first menu use so layout::space() sees an initialized app.
struct MenuSpacing {
    int frameBorder = layout::singlePixel();
    int horizontalPadding = layout::space(layout::Space::Two);
    int verticalPadding = layout::space(layout::Space::Half);
    int gap = layout::space(layout::Space::One);
    int edgeMargin = layout::space(layout::Space::One);
};

const MenuSpacing &menuSpacing()
{
    static const MenuSpacing spacing;
    return spacing;
}

} // namespace

QFont resolveMenuFont(const QVariantMap &appearance)
{
    const QVariant fontVariant = appearance.value(QStringLiteral("font"));
    if (fontVariant.canConvert<QFont>())
        return fontVariant.value<QFont>();
    if (const auto body = typography::bodyFont())
        return *body;
    return QGuiApplication::font();
}

MenuMetrics measureMenu(const QuickMenuModel &model, const QFontMetrics &metrics,
                        const QSizeF &bounds)
{
    const MenuSpacing &spacing = menuSpacing();
    MenuMetrics result;
    result.rowHeight = metrics.height() + 2 * spacing.verticalPadding;
    result.separatorHeight = spacing.frameBorder;

    bool anyCheckable = false;
    bool anyShortcut = false;
    bool anySubmenu = false;
    int widestText = 0;
    int widestShortcut = 0;
    int contentHeight = 2 * spacing.frameBorder;
    for (int row = 0; row < model.rowCount(); ++row) {
        const QuickMenuItem *item = model.itemAt(row);
        if (!item)
            continue;
        contentHeight += item->separator ? result.separatorHeight : result.rowHeight;
        if (item->separator)
            continue;
        anyCheckable = item->checkable || anyCheckable;
        anySubmenu = item->hasSubmenu() || anySubmenu;
        widestText = std::max(widestText, metrics.horizontalAdvance(item->text));
        if (!item->shortcutText.isEmpty()) {
            anyShortcut = true;
            widestShortcut =
                std::max(widestShortcut, metrics.horizontalAdvance(item->shortcutText));
        }
    }

    result.checkWidth = result.rowHeight / 2;
    result.arrowWidth = result.rowHeight / 4;
    result.checkX = anyCheckable ? spacing.horizontalPadding : -1;
    result.textX = spacing.horizontalPadding + (anyCheckable ? result.checkWidth + spacing.gap : 0);

    result.menuWidth =
        2 * spacing.frameBorder + result.textX + widestText + spacing.horizontalPadding;
    if (anyShortcut)
        result.menuWidth += spacing.gap + widestShortcut;
    if (anySubmenu)
        result.menuWidth += spacing.gap + result.arrowWidth;

    int rightEdge = result.menuWidth - spacing.frameBorder - spacing.horizontalPadding;
    if (anySubmenu) {
        result.arrowRight = rightEdge;
        rightEdge -= result.arrowWidth + spacing.gap;
    }
    if (anyShortcut) {
        result.shortcutRight = rightEdge;
        rightEdge -= widestShortcut + spacing.gap;
    }
    result.textRight = rightEdge;

    const int minHeight = 2 * spacing.frameBorder + result.rowHeight;
    const int maxHeight = std::max(minHeight, int(bounds.height() - 2 * spacing.edgeMargin));
    result.menuHeight = qBound(minHeight, contentHeight, maxHeight);
    return result;
}

} // namespace songview
