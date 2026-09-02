#include "ui/editordrawer/automationpage.h"

#include <algorithm>
#include <cstddef>
#include <cstdio>
#include <limits>
#include <utility>
#include <vector>

#include <QAction>
#include <QApplication>
#include <QCoreApplication>
#include <QEvent>
#include <QKeyEvent>
#include <QMenu>
#include <QString>
#include <QStringList>
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
#include "ui/songview/editorselectionmodel.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
namespace {

songview::TimelineInputItem *automationInputItem(SongView &view)
{
    auto *quickCanvas =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    return quickCanvas && quickCanvas->rootObject()
               ? quickCanvas->rootObject()->findChild<songview::TimelineInputItem *>(
                     QStringLiteral("timelineAutomationInput"))
               : nullptr;
}

// Band input delivery: the Quick input item normalizes raw events in
// viewport coordinates, so content-coordinate probes shift by the page
// scroll before each send.
struct AutomationBandInput {
    AutomationPage &page;
    songview::TimelineInputItem &item;

    void mouse(QEvent::Type type, const QPointF &contentPosition, Qt::MouseButton button,
               Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers) const
    {
        checks::events::sendMouse(item, type, contentPosition - QPointF(0.0, page.verticalScroll()),
                                  button, buttons, modifiers);
    }
};

} // namespace

void checkAutomationLanePopupMenus(SongView &view, AutomationPage &page, SongDocument &document,
                                   const QString &songLabel,
                                   const AutomationGeometry &projectionGeometry, int lfoTop,
                                   int lfoHeight, int rowsHeight, int &failures)
{
    const auto popupCheck = [&](bool condition, const QString &message) {
        if (condition)
            return;
        std::fprintf(stderr, "automation-popup-check: FAIL %s: %s\n", qUtf8Printable(songLabel),
                     qUtf8Printable(message));
        ++failures;
    };
    const auto originalTimeSelection = view.selectionModel().timeSelection();
    const bool tempoWasExpanded = !page.canvas()->laneBody(LaneHandle{0}).isEmpty();
    const std::vector<TempoPoint> originalTempo = document.tempoPoints();
    const std::vector<DocLanePoint> originalLfo = document.lanePoints(0, 21);
    const AutomationBandInput band{page, *automationInputItem(view)};
    const qreal dpr = band.item.devicePixelRatio();
    const auto assertPageParent = [&](const QMenu *menu) {
        popupCheck(menu->parentWidget() == &page,
                   QStringLiteral("automation context menu was not parented to AutomationPage"));
    };

    const auto menuAction = [&](const QPointF &position, const QString &trigger,
                                QStringList *actions) {
        bool triggered = false;
        QTimer::singleShot(0, [&, trigger] {
            auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
            if (!menu)
                return;
            assertPageParent(menu);
            QAction *selected = nullptr;
            for (QAction *action : menu->actions()) {
                if (actions)
                    actions->push_back(action->text());
                if (!trigger.isEmpty() && action->isEnabled() && action->text() == trigger)
                    selected = action;
            }
            if (!selected) {
                menu->close();
                return;
            }
            triggered = true;
            menu->setActiveAction(selected);
            QKeyEvent activate(QEvent::KeyPress, Qt::Key_Return, Qt::NoModifier);
            QCoreApplication::sendEvent(menu, &activate);
            if (QApplication::activePopupWidget() == menu) {
                const QRect actionRect = menu->actionGeometry(selected);
                if (actionRect.isValid()) {
                    checks::events::sendMouse(*menu, QEvent::MouseButtonPress, actionRect.center(),
                                              Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
                    checks::events::sendMouse(*menu, QEvent::MouseButtonRelease,
                                              actionRect.center(), Qt::LeftButton, Qt::NoButton,
                                              Qt::NoModifier);
                }
            }
            if (QApplication::activePopupWidget() == menu)
                menu->close();
        });
        band.mouse(QEvent::MouseButtonPress, position, Qt::RightButton, Qt::RightButton,
                   Qt::NoModifier);
        band.mouse(QEvent::MouseButtonRelease, position, Qt::RightButton, Qt::NoButton,
                   Qt::NoModifier);
        QCoreApplication::processEvents();
        return triggered;
    };
    const auto laneHandleFor = [&page](const EditorAutomationRowId &id) {
        const auto &rows = page.canvas()->rows();
        for (int row = 0; row < int(rows.size()); ++row) {
            if (rows[std::size_t(row)].id == id)
                return LaneHandle{row + 1};
        }
        return LaneHandle{};
    };
    bool leftGutterMenuOpened = false;
    QTimer::singleShot(0, [&] {
        if (auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget())) {
            assertPageParent(menu);
            leftGutterMenuOpened = true;
            menu->close();
        }
    });
    band.mouse(QEvent::MouseButtonPress,
               QPointF(layout::space(layout::Space::One), lfoTop + lfoHeight / 2), Qt::LeftButton,
               Qt::LeftButton, Qt::NoModifier);
    band.mouse(QEvent::MouseButtonRelease,
               QPointF(layout::space(layout::Space::One), lfoTop + lfoHeight / 2), Qt::LeftButton,
               Qt::NoButton, Qt::NoModifier);
    QCoreApplication::processEvents();
    popupCheck(!leftGutterMenuOpened,
               QStringLiteral("left click in a control-row gutter opened its menu"));
    QStringList addLaneActions;
    QTimer::singleShot(0, [&] {
        auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
        if (!menu)
            return;
        assertPageParent(menu);
        for (QAction *action : menu->actions())
            addLaneActions.push_back(action->text());
        menu->close();
    });
    band.mouse(QEvent::MouseButtonPress, QPointF(layout::space(layout::Space::One), rowsHeight + 1),
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
        assertPageParent(menu);
        for (QAction *action : menu->actions())
            ccLaneActions.push_back(action->text());
        menu->close();
    });
    band.mouse(QEvent::MouseButtonPress,
               QPointF(layout::space(layout::Space::One), lfoTop + lfoHeight / 2), Qt::RightButton,
               Qt::RightButton, Qt::NoModifier);
    band.mouse(QEvent::MouseButtonRelease,
               QPointF(layout::space(layout::Space::One), lfoTop + lfoHeight / 2), Qt::RightButton,
               Qt::NoButton, Qt::NoModifier);
    popupCheck(ccLaneActions.contains(QStringLiteral("Copy CC lane")) &&
                   ccLaneActions.contains(QStringLiteral("Hide CC lane")) &&
                   ccLaneActions.contains(QStringLiteral("Delete CC lane")),
               QStringLiteral("CC lane header menu lost Copy/Hide/Delete CC lane"));
    const QRect tempoRect = page.canvas()->pinnedTempoRect();
    const QPoint tempoHeader(projectionGeometry.plotOrigin / 2, tempoRect.center().y());
    if (!tempoWasExpanded) {
        band.mouse(QEvent::MouseButtonPress, tempoHeader, Qt::LeftButton, Qt::LeftButton,
                   Qt::NoModifier);
        band.mouse(QEvent::MouseButtonRelease, tempoHeader, Qt::LeftButton, Qt::NoButton,
                   Qt::NoModifier);
        QCoreApplication::processEvents();
    }
    QStringList tempoHeaderActions;
    QTimer::singleShot(0, [&] {
        auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
        if (!menu)
            return;
        assertPageParent(menu);
        for (QAction *action : menu->actions())
            tempoHeaderActions.push_back(action->text());
        menu->close();
    });
    band.mouse(QEvent::MouseButtonPress, tempoHeader, Qt::RightButton, Qt::RightButton,
               Qt::NoModifier);
    band.mouse(QEvent::MouseButtonRelease, tempoHeader, Qt::RightButton, Qt::NoButton,
               Qt::NoModifier);
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
    const QPointF tempoNode(view.camera().displayX(96.0, projectionGeometry.plotOrigin, dpr),
                            AutomationProjection::valueY(tempoBody, projectionGeometry,
                                                         CoreTimeDefaults::kMinTempoBpm,
                                                         CoreTimeDefaults::kMaxTempoBpm, 120));
    QStringList tempoNodeActions;
    QTimer::singleShot(0, [&] {
        auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
        if (!menu)
            return;
        assertPageParent(menu);
        for (QAction *action : menu->actions())
            tempoNodeActions.push_back(action->text());
        menu->close();
    });
    band.mouse(QEvent::MouseButtonPress, tempoNode, Qt::RightButton, Qt::RightButton,
               Qt::NoModifier);
    band.mouse(QEvent::MouseButtonRelease, tempoNode, Qt::RightButton, Qt::NoButton,
               Qt::NoModifier);
    popupCheck(tempoNodeActions ==
                   QStringList({QStringLiteral("Set Value"), QStringLiteral("Delete")}),
               QStringLiteral("Tempo node context menu actions were not exactly Set Value, "
                              "Delete"));
    const EditorAutomationRowId lfoId{EditorAutomationRowKind::ControlChange, 0, 21};
    const EditorAutomationRowId bodyRouteId{EditorAutomationRowKind::ControlChange, 0, 10};
    const LaneHandle lfoHandle = laneHandleFor(lfoId);
    const LaneHandle bodyRouteHandle = laneHandleFor(bodyRouteId);
    popupCheck(lfoHandle.valid() && bodyRouteHandle.valid(),
               QStringLiteral("popup fixture lost the expected CC row handles"));
    if (lfoHandle.valid() && bodyRouteHandle.valid()) {
        songview::EditorSelectionModel::TimeSelection mixedSelection;
        mixedSelection.startTick = 96;
        mixedSelection.endTick = 192;
        mixedSelection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
        mixedSelection.tempo = true;
        mixedSelection.lanes.push_back({0, 21});
        view.selectionModel().setTimeSelection(std::move(mixedSelection));
        QCoreApplication::processEvents();

        QStringList selectedTempoActions;
        menuAction(tempoNode, {}, &selectedTempoActions);
        popupCheck(selectedTempoActions ==
                       QStringList({QStringLiteral("Set Value"), QStringLiteral("Delete")}),
                   QStringLiteral("Tempo point menu lost precedence over a mixed selection"));

        const QRect lfoBody = page.canvas()->laneBody(lfoHandle);
        const QPointF lfoNode(
            view.camera().displayX(96.0, projectionGeometry.plotOrigin, dpr),
            AutomationProjection::valueY(lfoBody, projectionGeometry, 0, 127, 96));
        QStringList selectedCcActions;
        menuAction(lfoNode, {}, &selectedCcActions);
        popupCheck(selectedCcActions ==
                       QStringList({QStringLiteral("Set Value"), QStringLiteral("Delete")}),
                   QStringLiteral("CC point menu lost precedence over a mixed selection"));
        view.selectionModel().clearTimeSelection();
    }

    const QRect bodyRouteBody = page.canvas()->laneBody(bodyRouteHandle);
    const QPointF bodyRouteProbe(bodyRouteBody.right() - projectionGeometry.pointHitRadius - 1,
                                 bodyRouteBody.center().y());
    QStringList bodyRouteActions;
    menuAction(bodyRouteProbe, {}, &bodyRouteActions);
    popupCheck(bodyRouteActions.contains(QStringLiteral("Delete CC lane")) &&
                   bodyRouteActions.contains(QStringLiteral("Hide CC lane")),
               QStringLiteral("right-click in a CC body did not route to its lane menu"));

    TempoEdit highTempo;
    highTempo.remove = document.tempoPoints();
    highTempo.add = {{96, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(300)}};
    document.applyTempoEdit(highTempo);
    page.documentChanged();
    QCoreApplication::processEvents();
    QStringList ignoredActions;
    popupCheck(menuAction(tempoHeader, QStringLiteral("Copy"), &ignoredActions),
               QStringLiteral("Tempo lane Copy action did not trigger"));
    popupCheck(lfoHandle.valid() &&
                   menuAction(QPointF(layout::space(layout::Space::One),
                                      page.canvas()->laneBody(lfoHandle).center().y()),
                              QStringLiteral("Paste CC lane (replace)"), &ignoredActions),
               QStringLiteral("CC lane Paste action did not trigger after Tempo copy"));
    const auto clampedCc = document.lanePoints(0, 21);
    popupCheck(clampedCc.size() == 1 && clampedCc.front().tick == 96 &&
                   clampedCc.front().value == 127,
               QStringLiteral("Tempo-to-CC lane paste did not clamp to the CC range"));

    document.writeLanePoints(0, 21, 0, std::numeric_limits<uint64_t>::max(), {{144, 0}});
    page.documentChanged();
    QCoreApplication::processEvents();
    ignoredActions.clear();
    popupCheck(menuAction(QPointF(layout::space(layout::Space::One),
                                  page.canvas()->laneBody(lfoHandle).center().y()),
                          QStringLiteral("Copy CC lane"), &ignoredActions),
               QStringLiteral("CC lane Copy action did not trigger"));
    popupCheck(menuAction(tempoHeader, QStringLiteral("Paste"), &ignoredActions),
               QStringLiteral("Tempo lane Paste action did not trigger after CC copy"));
    const auto clampedTempo = document.tempoPoints();
    popupCheck(
        clampedTempo.size() == 1 && clampedTempo.front().tick == 144 &&
            clampedTempo.front().microsecondsPerQuarterNote ==
                CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(CoreTimeDefaults::kMinTempoBpm),
        QStringLiteral("CC-to-Tempo lane paste did not clamp to the Tempo range"));

    ignoredActions.clear();
    popupCheck(menuAction(tempoHeader, QStringLiteral("Clear Tempo"), &ignoredActions) &&
                   document.tempoPoints().empty(),
               QStringLiteral("Tempo lane Clear action did not clear the whole lane"));
    ignoredActions.clear();
    popupCheck(menuAction(QPointF(layout::space(layout::Space::One),
                                  page.canvas()->laneBody(lfoHandle).center().y()),
                          QStringLiteral("Clear events"), &ignoredActions) &&
                   document.lanePoints(0, 21).empty(),
               QStringLiteral("CC lane Clear action did not clear the whole lane"));
    const auto currentLfo = document.lanePoints(0, 21);
    bool lfoChanged = currentLfo.size() != originalLfo.size();
    if (!lfoChanged) {
        for (std::size_t index = 0; index < currentLfo.size(); ++index) {
            if (currentLfo[index].tick != originalLfo[index].tick ||
                currentLfo[index].value != originalLfo[index].value) {
                lfoChanged = true;
                break;
            }
        }
    }
    if (document.tempoPoints() != originalTempo) {
        TempoEdit restoreTempo;
        restoreTempo.remove = document.tempoPoints();
        restoreTempo.add = originalTempo;
        document.applyTempoEdit(restoreTempo);
    }
    if (lfoChanged) {
        std::vector<SongDocument::LanePointValue> restoreLfo;
        restoreLfo.reserve(originalLfo.size());
        for (const auto &point : originalLfo)
            restoreLfo.push_back({point.tick, point.value});
        document.writeLanePoints(0, 21, 0, std::numeric_limits<uint64_t>::max(), restoreLfo);
    }
    const bool tempoIsExpanded = !page.canvas()->laneBody(LaneHandle{0}).isEmpty();
    if (tempoIsExpanded != tempoWasExpanded) {
        band.mouse(QEvent::MouseButtonPress, tempoHeader, Qt::LeftButton, Qt::LeftButton,
                   Qt::NoModifier);
        band.mouse(QEvent::MouseButtonRelease, tempoHeader, Qt::LeftButton, Qt::NoButton,
                   Qt::NoModifier);
        QCoreApplication::processEvents();
    }
    view.selectionModel().setTimeSelection(originalTimeSelection);
    page.documentChanged();
    QCoreApplication::processEvents();
}
