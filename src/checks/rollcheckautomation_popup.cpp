#include "ui/editordrawer/automationpage.h"

#include <algorithm>
#include <cstdio>

#include <QAction>
#include <QApplication>
#include <QCoreApplication>
#include <QEvent>
#include <QMenu>
#include <QString>
#include <QTimer>

#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "core/timedefaults.h"
#include "core/xcmd.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/layout.h"
#include "ui/songview.h"

void checkAutomationLanePopupMenus(SongView &view, AutomationPage &page, SongDocument &document,
                                   const QString &songLabel,
                                   const AutomationGeometry &projectionGeometry, int lfoTop,
                                   int lfoHeight, int /*voiceTop*/, int /*voiceHeight*/,
                                   int rowsHeight, int &failures)
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
    checks::events::sendMouse(*page.canvas(), QEvent::MouseButtonPress,
                              QPoint(layout::space(layout::Space::One), lfoTop + lfoHeight / 2),
                              Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*page.canvas(), QEvent::MouseButtonRelease,
                              QPoint(layout::space(layout::Space::One), lfoTop + lfoHeight / 2),
                              Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
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
    checks::events::sendMouse(*page.canvas(), QEvent::MouseButtonPress,
                              QPoint(layout::space(layout::Space::One), rowsHeight + 1),
                              Qt::RightButton, Qt::RightButton, Qt::NoModifier);
    popupCheck(addLaneActions.contains(QStringLiteral("Show: Volume (VOL) (hidden)")),
               QStringLiteral("right-click add-lane menu lost hidden-lane label or order"));
    popupCheck(addLaneActions.contains(QStringLiteral("Hidden CC lanes")),
               QStringLiteral("right-click add-lane menu lost Hidden CC lanes heading"));
    for (const xcmd::Descriptor &descriptor : xcmd::laneDescriptors()) {
        const QString label = CCLanes::laneLabel(descriptor.laneController);
        popupCheck(addLaneActions.contains(label),
                   QStringLiteral("right-click add-lane menu did not offer every xcmd lane "
                                  "descriptor (missing %1)")
                       .arg(label));
    }
    QStringList ccLaneActions;
    QTimer::singleShot(0, [&] {
        auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
        if (!menu)
            return;
        for (QAction *action : menu->actions())
            ccLaneActions.push_back(action->text());
        menu->close();
    });
    checks::events::sendMouse(*page.canvas(), QEvent::MouseButtonPress,
                              QPoint(layout::space(layout::Space::One), lfoTop + lfoHeight / 2),
                              Qt::RightButton, Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(*page.canvas(), QEvent::MouseButtonRelease,
                              QPoint(layout::space(layout::Space::One), lfoTop + lfoHeight / 2),
                              Qt::RightButton, Qt::NoButton, Qt::NoModifier);
    popupCheck(ccLaneActions.contains(QStringLiteral("Copy CC lane")) &&
                   ccLaneActions.contains(QStringLiteral("Hide CC lane")) &&
                   ccLaneActions.contains(QStringLiteral("Delete CC lane")),
               QStringLiteral("CC lane header menu lost Copy/Hide/Delete CC lane"));
    const QRect tempoRect = page.canvas()->pinnedTempoRect();
    const QPoint tempoHeader(projectionGeometry.plotOrigin / 2, tempoRect.center().y());
    checks::events::sendMouse(*page.canvas(), QEvent::MouseButtonPress, tempoHeader, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*page.canvas(), QEvent::MouseButtonRelease, tempoHeader,
                              Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
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
    checks::events::sendMouse(*page.canvas(), QEvent::MouseButtonPress, tempoHeader,
                              Qt::RightButton, Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(*page.canvas(), QEvent::MouseButtonRelease, tempoHeader,
                              Qt::RightButton, Qt::NoButton, Qt::NoModifier);
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
    const QRect tempoBody = page.canvas()->laneBody(LaneHandle{0});
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
    checks::events::sendMouse(*page.canvas(), QEvent::MouseButtonPress, tempoNode, Qt::RightButton,
                              Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(*page.canvas(), QEvent::MouseButtonRelease, tempoNode,
                              Qt::RightButton, Qt::NoButton, Qt::NoModifier);
    popupCheck(tempoNodeActions ==
                   QStringList({QStringLiteral("Set Value"), QStringLiteral("Delete")}),
               QStringLiteral("Tempo node context menu actions were not exactly Set Value, "
                              "Delete"));
}
