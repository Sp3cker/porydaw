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

songview::TimelineInputItem *automationInputItem(SongView &view, const QString &objectName)
{
    auto *quickCanvas =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    return quickCanvas && quickCanvas->rootObject()
               ? quickCanvas->rootObject()->findChild<songview::TimelineInputItem *>(objectName)
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
    const AutomationBandInput plot{
        page, *automationInputItem(view, QStringLiteral("timelineAutomationInput"))};
    const AutomationBandInput gutter{
        page, *automationInputItem(view, QStringLiteral("timelineAutomationGutterInput"))};
    const qreal dpr = plot.item.devicePixelRatio();
    const auto assertSongViewParent = [&](const QMenu *menu) {
        popupCheck(menu->parentWidget() == &view,
                   QStringLiteral("automation context menu was not parented to SongView"));
    };

    const auto menuAction = [&](const AutomationBandInput &surface, const QPointF &position,
                                const QString &trigger, QStringList *actions) {
        bool triggered = false;
        QTimer::singleShot(0, [&, trigger] {
            auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
            if (!menu)
                return;
            assertSongViewParent(menu);
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
        surface.mouse(QEvent::MouseButtonPress, position, Qt::RightButton, Qt::RightButton,
                      Qt::NoModifier);
        surface.mouse(QEvent::MouseButtonRelease, position, Qt::RightButton, Qt::NoButton,
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
    const EditorAutomationRowId lfoId{EditorAutomationRowKind::ControlChange, 0, 21};
    const EditorAutomationRowId bodyRouteId{EditorAutomationRowKind::ControlChange, 0, 10};
    const LaneHandle lfoHandle = laneHandleFor(lfoId);
    const LaneHandle bodyRouteHandle = laneHandleFor(bodyRouteId);
    const QRect lfoBody = page.canvas()->laneBody(lfoHandle);
    const QPointF lfoHeaderPoint(layout::space(layout::Space::One),
                                 lfoBody.isEmpty() ? lfoTop + lfoHeight / 2
                                                   : qreal(lfoBody.center().y()));
    bool leftGutterMenuOpened = false;
    QTimer::singleShot(0, [&] {
        if (auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget())) {
            assertSongViewParent(menu);
            leftGutterMenuOpened = true;
            menu->close();
        }
    });
    gutter.mouse(QEvent::MouseButtonPress, lfoHeaderPoint, Qt::LeftButton, Qt::LeftButton,
                 Qt::NoModifier);
    gutter.mouse(QEvent::MouseButtonRelease, lfoHeaderPoint, Qt::LeftButton, Qt::NoButton,
                 Qt::NoModifier);
    QCoreApplication::processEvents();
    popupCheck(!leftGutterMenuOpened,
               QStringLiteral("left click in a control-row gutter opened its menu"));
    QStringList addLaneActions;
    QTimer::singleShot(0, [&] {
        auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
        if (!menu)
            return;
        assertSongViewParent(menu);
        for (QAction *action : menu->actions())
            addLaneActions.push_back(action->text());
        menu->close();
    });
    gutter.mouse(QEvent::MouseButtonPress,
                 QPointF(layout::space(layout::Space::One), rowsHeight + 1), Qt::RightButton,
                 Qt::RightButton, Qt::NoModifier);
    popupCheck(addLaneActions.contains(QStringLiteral("Show: Volume (VOL) (hidden)")),
               QStringLiteral("right-click add-lane menu lost hidden-lane label or order"));
    popupCheck(addLaneActions.contains(QStringLiteral("Hidden CC lanes")),
               QStringLiteral("right-click add-lane menu lost Hidden CC lanes heading"));
    for (const xcmd::Descriptor &descriptor : xcmd::laneDescriptors()) {
        const uint8_t controller = descriptor.laneController;
        const QString label = CCLanes::laneLabel(controller);
        const EditorAutomationRowId row{EditorAutomationRowKind::ControlChange, 0, controller};
        const bool hidden = page.automationViewState().isLaneHidden(row);
        const bool occupied = page.model().findLane(0, controller) ||
                              page.automationViewState().emptyLanes.find(row) !=
                                  page.automationViewState().emptyLanes.cend();
        const QString hiddenLabel = QStringLiteral("Show: %1 (hidden)").arg(label);
        const bool exactDescriptorEntry =
            hidden     ? addLaneActions.count(hiddenLabel) == 1 && !addLaneActions.contains(label)
            : occupied ? !addLaneActions.contains(label)
                       : addLaneActions.count(label) == 1;
        popupCheck(exactDescriptorEntry,
                   QStringLiteral("right-click add-lane menu descriptor entry was not exact for "
                                  "%1")
                       .arg(label));
    }
    QStringList ccLaneActions;
    QTimer::singleShot(0, [&] {
        auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
        if (!menu)
            return;
        assertSongViewParent(menu);
        for (QAction *action : menu->actions())
            ccLaneActions.push_back(action->text());
        menu->close();
    });
    gutter.mouse(QEvent::MouseButtonPress, lfoHeaderPoint, Qt::RightButton, Qt::RightButton,
                 Qt::NoModifier);
    gutter.mouse(QEvent::MouseButtonRelease, lfoHeaderPoint, Qt::RightButton, Qt::NoButton,
                 Qt::NoModifier);
    popupCheck(ccLaneActions.contains(QStringLiteral("Copy CC lane")) &&
                   ccLaneActions.contains(QStringLiteral("Hide CC lane")) &&
                   ccLaneActions.contains(QStringLiteral("Delete CC lane")),
               QStringLiteral("CC lane header menu lost Copy/Hide/Delete CC lane"));
    const QRect tempoRect = page.canvas()->pinnedTempoRect();
    const QPoint tempoHeader(layout::space(layout::Space::One), tempoRect.center().y());
    if (!tempoWasExpanded) {
        gutter.mouse(QEvent::MouseButtonPress, tempoHeader, Qt::LeftButton, Qt::LeftButton,
                     Qt::NoModifier);
        gutter.mouse(QEvent::MouseButtonRelease, tempoHeader, Qt::LeftButton, Qt::NoButton,
                     Qt::NoModifier);
        QCoreApplication::processEvents();
    }
    QStringList tempoHeaderActions;
    QTimer::singleShot(0, [&] {
        auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
        if (!menu)
            return;
        assertSongViewParent(menu);
        for (QAction *action : menu->actions())
            tempoHeaderActions.push_back(action->text());
        menu->close();
    });
    gutter.mouse(QEvent::MouseButtonPress, tempoHeader, Qt::RightButton, Qt::RightButton,
                 Qt::NoModifier);
    gutter.mouse(QEvent::MouseButtonRelease, tempoHeader, Qt::RightButton, Qt::NoButton,
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
    const QPointF tempoNode(view.camera().displayX(96.0, 0.0, dpr),
                            AutomationProjection::valueY(tempoBody, projectionGeometry,
                                                         CoreTimeDefaults::kMinTempoBpm,
                                                         CoreTimeDefaults::kMaxTempoBpm, 120));
    QStringList tempoNodeActions;
    QTimer::singleShot(0, [&] {
        auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
        if (!menu)
            return;
        assertSongViewParent(menu);
        for (QAction *action : menu->actions())
            tempoNodeActions.push_back(action->text());
        menu->close();
    });
    plot.mouse(QEvent::MouseButtonPress, tempoNode, Qt::RightButton, Qt::RightButton,
               Qt::NoModifier);
    plot.mouse(QEvent::MouseButtonRelease, tempoNode, Qt::RightButton, Qt::NoButton,
               Qt::NoModifier);
    popupCheck(tempoNodeActions ==
                   QStringList({QStringLiteral("Set Value"), QStringLiteral("Delete")}),
               QStringLiteral("Tempo node context menu actions were not exactly Set Value, "
                              "Delete"));
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
        menuAction(plot, tempoNode, {}, &selectedTempoActions);
        popupCheck(selectedTempoActions ==
                       QStringList({QStringLiteral("Set Value"), QStringLiteral("Delete")}),
                   QStringLiteral("Tempo point menu lost precedence over a mixed selection"));

        const QRect selectedLfoBody = page.canvas()->laneBody(lfoHandle);
        const QPointF lfoNode(
            view.camera().displayX(96.0, 0.0, dpr),
            AutomationProjection::valueY(selectedLfoBody, projectionGeometry, 0, 127, 96));
        QStringList selectedCcActions;
        menuAction(plot, lfoNode, {}, &selectedCcActions);
        popupCheck(selectedCcActions ==
                       QStringList({QStringLiteral("Set Value"), QStringLiteral("Delete")}),
                   QStringLiteral("CC point menu lost precedence over a mixed selection"));
        view.selectionModel().clearTimeSelection();
    }

    const QRect bodyRouteBody = page.canvas()->laneBody(bodyRouteHandle);
    const QPointF bodyRouteProbe(layout::space(layout::Space::One), bodyRouteBody.center().y());
    QStringList bodyRouteActions;
    menuAction(gutter, bodyRouteProbe, {}, &bodyRouteActions);
    popupCheck(bodyRouteActions.contains(QStringLiteral("Delete CC lane")) &&
                   bodyRouteActions.contains(QStringLiteral("Hide CC lane")),
               QStringLiteral("right-click in a CC gutter did not route to its lane menu"));

    TempoEdit highTempo;
    highTempo.remove = document.tempoPoints();
    highTempo.add = {{96, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(300)}};
    document.applyTempoEdit(highTempo);
    page.documentChanged();
    QCoreApplication::processEvents();
    QStringList ignoredActions;
    popupCheck(menuAction(gutter, tempoHeader, QStringLiteral("Copy"), &ignoredActions),
               QStringLiteral("Tempo lane Copy action did not trigger"));
    popupCheck(lfoHandle.valid() &&
                   menuAction(gutter,
                              QPointF(layout::space(layout::Space::One),
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
    popupCheck(menuAction(gutter,
                          QPointF(layout::space(layout::Space::One),
                                  page.canvas()->laneBody(lfoHandle).center().y()),
                          QStringLiteral("Copy CC lane"), &ignoredActions),
               QStringLiteral("CC lane Copy action did not trigger"));
    popupCheck(menuAction(gutter, tempoHeader, QStringLiteral("Paste"), &ignoredActions),
               QStringLiteral("Tempo lane Paste action did not trigger after CC copy"));
    const auto clampedTempo = document.tempoPoints();
    popupCheck(
        clampedTempo.size() == 1 && clampedTempo.front().tick == 144 &&
            clampedTempo.front().microsecondsPerQuarterNote ==
                CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(CoreTimeDefaults::kMinTempoBpm),
        QStringLiteral("CC-to-Tempo lane paste did not clamp to the Tempo range"));

    ignoredActions.clear();
    popupCheck(menuAction(gutter, tempoHeader, QStringLiteral("Clear Tempo"), &ignoredActions) &&
                   document.tempoPoints().empty(),
               QStringLiteral("Tempo lane Clear action did not clear the whole lane"));
    ignoredActions.clear();
    popupCheck(menuAction(gutter,
                          QPointF(layout::space(layout::Space::One),
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
        gutter.mouse(QEvent::MouseButtonPress, tempoHeader, Qt::LeftButton, Qt::LeftButton,
                     Qt::NoModifier);
        gutter.mouse(QEvent::MouseButtonRelease, tempoHeader, Qt::LeftButton, Qt::NoButton,
                     Qt::NoModifier);
        QCoreApplication::processEvents();
    }
    view.selectionModel().setTimeSelection(originalTimeSelection);
    page.documentChanged();
    QCoreApplication::processEvents();
}
