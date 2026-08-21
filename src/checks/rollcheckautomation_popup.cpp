#include "ui/editordrawer/automationpage.h"

#include <algorithm>
#include <cstdio>

#include <QAction>
#include <QApplication>
#include <QCoreApplication>
#include <QMenu>
#include <QMouseEvent>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QWidget>

#include "core/songdocument.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/layout.h"
#include "ui/songview.h"

namespace {

void sendMouse(QWidget *widget, QEvent::Type type, const QPointF &position, Qt::MouseButton button,
               Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers = Qt::NoModifier)
{
    QMouseEvent event(type, position, QPointF(widget->mapToGlobal(position.toPoint())), button,
                      buttons, modifiers);
    QCoreApplication::sendEvent(widget, &event);
}

} // namespace

void checkAutomationLanePopupMenus(SongView &view, AutomationPage &page, SongDocument &document,
                                   const QString &songLabel,
                                   const AutomationGeometry &projectionGeometry, int lfoTop,
                                   int lfoHeight, int voiceTop, int voiceHeight, int rowsHeight,
                                   int &failures)
{
    const auto popupCheck = [&](bool condition, const QString &message) {
        if (condition)
            return;
        std::fprintf(stderr, "automation-popup-check: FAIL %s: %s\n", qUtf8Printable(songLabel),
                     qUtf8Printable(message));
        ++failures;
    };
    bool leftGutterMenuOpened = false;
    QTimer::singleShot(0, [&] {
        if (auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget())) {
            leftGutterMenuOpened = true;
            menu->close();
        }
    });
    sendMouse(page.canvas(), QEvent::MouseButtonPress,
              QPoint(layout::space(layout::Space::One), lfoTop + lfoHeight / 2), Qt::LeftButton,
              Qt::LeftButton);
    sendMouse(page.canvas(), QEvent::MouseButtonRelease,
              QPoint(layout::space(layout::Space::One), lfoTop + lfoHeight / 2), Qt::LeftButton,
              Qt::NoButton);
    QCoreApplication::processEvents();
    popupCheck(!leftGutterMenuOpened,
               QStringLiteral("left click in a control-row gutter opened its menu"));
    QStringList addLaneActions;
    QTimer::singleShot(0, [&] {
        auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
        if (!menu)
            return;
        for (QAction *action : menu->actions())
            addLaneActions.push_back(action->text());
        menu->close();
    });
    sendMouse(page.canvas(), QEvent::MouseButtonPress,
              QPoint(layout::space(layout::Space::One), rowsHeight + 1), Qt::RightButton,
              Qt::RightButton);
    popupCheck(addLaneActions.contains(QStringLiteral("Show: Volume (VOL) (hidden)")),
               QStringLiteral("right-click add-lane menu lost hidden-lane label or order"));
    popupCheck(addLaneActions.contains(QStringLiteral("Hidden CC lanes")),
               QStringLiteral("right-click add-lane menu lost Hidden CC lanes heading"));
    QStringList ccLaneActions;
    QTimer::singleShot(0, [&] {
        auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
        if (!menu)
            return;
        for (QAction *action : menu->actions())
            ccLaneActions.push_back(action->text());
        menu->close();
    });
    sendMouse(page.canvas(), QEvent::MouseButtonPress,
              QPoint(layout::space(layout::Space::One), lfoTop + lfoHeight / 2), Qt::RightButton,
              Qt::RightButton);
    sendMouse(page.canvas(), QEvent::MouseButtonRelease,
              QPoint(layout::space(layout::Space::One), lfoTop + lfoHeight / 2), Qt::RightButton,
              Qt::NoButton);
    popupCheck(ccLaneActions.contains(QStringLiteral("Copy CC lane")) &&
                   ccLaneActions.contains(QStringLiteral("Hide CC lane")) &&
                   ccLaneActions.contains(QStringLiteral("Delete CC lane")),
               QStringLiteral("CC lane header menu lost Copy/Hide/Delete CC lane"));
    const QPoint tempoHeader(projectionGeometry.plotOrigin / 2, std::max(1, voiceTop / 2));
    sendMouse(page.canvas(), QEvent::MouseButtonPress, tempoHeader, Qt::LeftButton, Qt::LeftButton);
    sendMouse(page.canvas(), QEvent::MouseButtonRelease, tempoHeader, Qt::LeftButton, Qt::NoButton);
    QCoreApplication::processEvents();
    QStringList tempoHeaderActions;
    QTimer::singleShot(0, [&] {
        auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
        if (!menu)
            return;
        for (QAction *action : menu->actions())
            tempoHeaderActions.push_back(action->text());
        menu->close();
    });
    sendMouse(page.canvas(), QEvent::MouseButtonPress, tempoHeader, Qt::RightButton,
              Qt::RightButton);
    sendMouse(page.canvas(), QEvent::MouseButtonRelease, tempoHeader, Qt::RightButton,
              Qt::NoButton);
    popupCheck(tempoHeaderActions.contains(QStringLiteral("Copy")) &&
                   tempoHeaderActions.contains(QStringLiteral("Paste")) &&
                   tempoHeaderActions.contains(QStringLiteral("Clear Tempo")),
               QStringLiteral("Tempo header menu lost Copy, Paste, Clear Tempo"));
    TempoEdit tempoSeed;
    tempoSeed.remove = document.tempoPoints();
    tempoSeed.add = {{96, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(120)}};
    document.applyTempoEdit(tempoSeed);
    page.documentChanged();
    QCoreApplication::processEvents();
    const int tempoBottom = page.canvas()->contentTopInset() - voiceHeight;
    const QRect tempoBody(0, 0, page.canvas()->width(), tempoBottom);
    const QPointF tempoNode(
        view.displayX(96.0, projectionGeometry.plotOrigin, page.canvas()->devicePixelRatioF()),
        AutomationProjection::valueY(tempoBody, projectionGeometry, CoreTimeDefaults::kMinTempoBpm,
                                     CoreTimeDefaults::kMaxTempoBpm, 120));
    QStringList tempoNodeActions;
    QTimer::singleShot(0, [&] {
        auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
        if (!menu)
            return;
        for (QAction *action : menu->actions())
            tempoNodeActions.push_back(action->text());
        menu->close();
    });
    sendMouse(page.canvas(), QEvent::MouseButtonPress, tempoNode, Qt::RightButton, Qt::RightButton);
    sendMouse(page.canvas(), QEvent::MouseButtonRelease, tempoNode, Qt::RightButton, Qt::NoButton);
    popupCheck(tempoNodeActions ==
                   QStringList({QStringLiteral("Set Value"), QStringLiteral("Delete")}),
               QStringLiteral("Tempo node context menu actions were not exactly Set Value, "
                              "Delete"));
}
