#include "ui/contextmenu.h"

#include <QMouseEvent>
#include <QProxyStyle>
#include <utility>

namespace ui {
namespace {

// macOS flashes a triggered menu item for 80 ms before hiding the menu;
// suppress the flash so picking an action feels instant.
class ContextMenuStyle final : public QProxyStyle
{
  public:
    // Base the proxy on Fusion explicitly, matching the application style set
    // in main(). QApplication::style()->name() looks like it would mirror the
    // app style, but once the theme installs a stylesheet the app style is a
    // QStyleSheetStyle whose name() is empty — and QProxyStyle(QString())
    // silently falls back to the NATIVE desktop style (QWindows11Style on
    // Windows). Polishing this menu under that style calls setWindowFlags for
    // the native rounded popup, which reentrantly crashes in Qt 6.9. Naming
    // Fusion keeps the menu on the same style as the rest of the app.
    ContextMenuStyle() : QProxyStyle(QStringLiteral("Fusion")) {}

    int styleHint(StyleHint hint, const QStyleOption *option, const QWidget *widget,
                  QStyleHintReturn *returnData) const override
    {
        if (hint == SH_Menu_FlashTriggeredItem)
            return 0;
        return QProxyStyle::styleHint(hint, option, widget, returnData);
    }
};

} // namespace

ContextMenu::ContextMenu(QWidget *parent, std::function<bool(QPointF)> onOutsideRightClick)
    : QMenu(parent)
    , m_onOutsideRightClick(std::move(onOutsideRightClick))
{
    auto *menuStyle = new ContextMenuStyle;
    menuStyle->setParent(this);
    setStyle(menuStyle);
}

// A right-click on another target while the popup is open retargets the
// menu in one gesture instead of spending the click on dismissal. Only
// clicks outside the popup rectangle are offered to the handler — a click
// on the menu itself always keeps its normal item behavior.
void ContextMenu::mousePressEvent(QMouseEvent *event)
{
    m_handledRetargetPress = false;
    if (event->button() == Qt::RightButton && !QRectF(rect()).contains(event->position()) &&
        m_onOutsideRightClick && m_onOutsideRightClick(event->globalPosition())) {
        m_handledRetargetPress = true;
        event->accept();
        return;
    }
    QMenu::mousePressEvent(event);
}

// The release paired with a handled retarget press must be swallowed too:
// left to QMenu it counts as an outside release and dismisses the popup the
// press just re-aimed.
void ContextMenu::mouseReleaseEvent(QMouseEvent *event)
{
    if (event->button() == Qt::RightButton && std::exchange(m_handledRetargetPress, false)) {
        event->accept();
        return;
    }
    QMenu::mouseReleaseEvent(event);
}

} // namespace ui
