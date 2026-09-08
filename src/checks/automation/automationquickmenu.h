#pragma once

#include <QPointer>
#include <QString>
#include <QtTest>

#include "checks/quickpopupguard.h"

// Shared view of the automation canvas' Quick context menus (drawer plan
// automation-menus migration). The lane, add-lane, and time-selection menus
// publish typed rows addressed by AutomationCanvas::CanvasMenuAction ids
// through the shared Quick popup session; checks open them with the real
// gutter right-press and click rendered rows, never the model.
namespace automation_quick {

// One opened automation Quick menu: the shared session, its rendered root
// panel's typed row model, and a diagnostic when the asynchronous open failed.
struct AutomationMenu {
    songview::QuickPopupSession *session = nullptr;
    songview::QuickMenuModel *model = nullptr;
    QString diagnostic = QStringLiteral("the right-press did not open the shared menu");
};

// Waits for the shared session to publish the typed menu panel after a real
// right-press. Callers address and click rendered rows; the model is never
// activated directly.
inline AutomationMenu waitForAutomationMenu(SongView &view, QString diagnostic)
{
    AutomationMenu menu;
    menu.diagnostic = std::move(diagnostic);
    const QPointer<songview::QuickPopupSession> live{quick_popup::popupSession(view)};
    if (!QTest::qWaitFor([&live] {
            return live && live->isOpen() && quick_popup::menuPanel(*live) &&
                   quick_popup::menuModel(*quick_popup::menuPanel(*live)) != nullptr;
        }))
        return menu;
    menu.session = live;
    menu.model = quick_popup::menuModel(*quick_popup::menuPanel(*live));
    menu.diagnostic.clear();
    return menu;
}

} // namespace automation_quick
