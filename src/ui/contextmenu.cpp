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

void ContextMenu::setOutsideRightClickHandler(std::function<bool(QPointF)> onOutsideRightClick)
{
    m_onOutsideRightClick = std::move(onOutsideRightClick);
}

void ContextMenu::mousePressEvent(QMouseEvent *event)
{
    m_handledOutsideRightPress = false;
    if (event->button() == Qt::RightButton && m_onOutsideRightClick &&
        m_onOutsideRightClick(event->globalPosition())) {
        m_handledOutsideRightPress = true;
        event->accept();
        return;
    }
    QMenu::mousePressEvent(event);
}

void ContextMenu::mouseReleaseEvent(QMouseEvent *event)
{
    if (event->button() == Qt::RightButton && std::exchange(m_handledOutsideRightPress, false)) {
        event->accept();
        return;
    }
    QMenu::mouseReleaseEvent(event);
}

} // namespace ui
