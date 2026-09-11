#include "checks/fwd.hpp"
#include "checks/host/hosttestsupport.h"
#include "checks/quickpopupguard.h"
#include "checks/rollcheck/rollcheck.h"
#include "checks/support/eventsynth.h"

#include <algorithm>
#include <array>

#include "ui/songview/quick/quickmenumodel.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timeruler.h"
#include <QAction>
#include <QApplication>
#include <QCoreApplication>
#include <QKeyCombination>
#include <QKeySequence>
#include <QMenu>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSignalSpy>
#include <QtTest>

namespace checks::host {
namespace {

// One opened ruler grid menu: the shared session, its rendered panel's typed
// row model, and a diagnostic when the asynchronous open failed.
struct RulerGridMenu {
    songview::QuickPopupSession *session = nullptr;
    songview::QuickMenuModel *model = nullptr;
    QString diagnostic = QStringLiteral("the ruler grid menu did not open");
};

// Waits for the shared canvas session to publish the typed menu panel. Callers
// still address and click its rendered rows rather than activating the model.
RulerGridMenu awaitRulerGridMenu(SongView &view, const QString &diagnostic)
{
    RulerGridMenu menu;
    const QPointer<songview::QuickPopupSession> live{quick_popup::popupSession(view)};
    if (!live) {
        menu.diagnostic = QStringLiteral("the timeline Quick canvas has no popup session");
        return menu;
    }
    if (!QTest::qWaitFor([&live] {
            if (!live || !live->isOpen())
                return false;
            QQuickItem *const panel = quick_popup::menuPanel(*live);
            return panel && quick_popup::menuModel(*panel);
        })) {
        menu.diagnostic = diagnostic;
        return menu;
    }
    QQuickItem *const panel = quick_popup::menuPanel(*live);
    songview::QuickMenuModel *const model = panel ? quick_popup::menuModel(*panel) : nullptr;
    if (!model) {
        menu.diagnostic = diagnostic;
        return menu;
    }
    menu.session = live;
    menu.model = model;
    menu.diagnostic.clear();
    return menu;
}

// Opens one grid menu through the real QML TapHandler on its rendered control.
RulerGridMenu openRulerGridMenu(SongView &view, QQuickItem &control)
{
    RulerGridMenu menu;
    songview::QuickPopupSession *const session = quick_popup::popupSession(view);
    if (!session || !session->window()) {
        menu.diagnostic = QStringLiteral("the timeline Quick canvas has no popup window");
        return menu;
    }
    const QPoint center =
        control.mapToScene(QPointF(control.width() / 2.0, control.height() / 2.0)).toPoint();
    QTest::mouseClick(session->window(), Qt::LeftButton, Qt::NoModifier, center);
    return awaitRulerGridMenu(
        view,
        QStringLiteral("clicking %1 did not open the shared grid menu").arg(control.objectName()));
}

struct RulerGridSurface {
    songview::TimelineQuickView *quick = nullptr;
    QQuickItem *division = nullptr;
    QQuickItem *feel = nullptr;
    songview::TimelineInputItem *rulerInput = nullptr;
    songview::TimeRuler *ruler = nullptr;

    bool valid() const { return quick && division && feel && rulerInput && ruler; }
};

RulerGridSurface rulerGridSurface(SongView &view)
{
    RulerGridSurface surface;
    surface.quick =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    if (!surface.quick)
        return surface;
    QQuickItem *const root = surface.quick->rootObject();
    if (!root)
        return surface;
    surface.division =
        root->findChild<QQuickItem *>(QStringLiteral("timelineRulerDivisionControl"));
    surface.feel = root->findChild<QQuickItem *>(QStringLiteral("timelineRulerFeelControl"));
    surface.rulerInput =
        root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineRulerInput"));
    surface.ruler = surface.rulerInput
                        ? dynamic_cast<songview::TimeRuler *>(surface.rulerInput->interaction())
                        : nullptr;
    return surface;
}

class RulerGridMenuTest final : public QObject
{
    Q_OBJECT
  public:
    RulerGridMenuTest() = default;

    Q_DISABLE_COPY_MOVE(RulerGridMenuTest)

  private slots:
    void rulerGridMenusOpenAsQuickRowsAndDispatchPicks()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        SongView &view = host.view();
        const RulerGridSurface surface = rulerGridSurface(view);
        QVERIFY2(surface.valid(), "could not discover the Quick ruler grid controls");
        QVERIFY(surface.division->isEnabled());
        QVERIFY(surface.feel->isEnabled());
        const quick_popup::PromptGuard guard(view);

        const SongView::ViewState initial = view.viewState();
        const RulerGridMenu divisionMenu = openRulerGridMenu(view, *surface.division);
        QVERIFY2(divisionMenu.session, qUtf8Printable(divisionMenu.diagnostic));
        QVERIFY2(!QApplication::activePopupWidget(),
                 "opening the division menu created a native popup widget");
        QVERIFY2(!QApplication::activeModalWidget(),
                 "opening the division menu created a native modal widget");
        QVERIFY2(!view.findChild<QMenu *>(),
                 "opening the division menu left a QMenu under SongView");

        static constexpr std::array<int, 5> divisionIds{0, 4, 8, 16, 32};
        QCOMPARE(divisionMenu.model->rowCount(), int(divisionIds.size()));
        int divisionChecked = 0;
        for (int row = 0; row < divisionMenu.model->rowCount(); ++row) {
            const songview::QuickMenuItem *const item = divisionMenu.model->itemAt(row);
            QVERIFY(item);
            QCOMPARE(item->id, divisionIds[std::size_t(row)]);
            QVERIFY(item->enabled);
            QVERIFY(item->checkable);
            divisionChecked += item->checked ? 1 : 0;
        }
        QCOMPARE(divisionChecked, 1);
        const int currentDivisionRow = divisionMenu.model->rowForId(initial.gridMinDenom);
        QVERIFY2(currentDivisionRow >= 0, "the division menu omitted the current grid denominator");
        const songview::QuickMenuItem *const currentDivision =
            divisionMenu.model->itemAt(currentDivisionRow);
        QVERIFY(currentDivision && currentDivision->checked);
        QCOMPARE(currentDivision->text, surface.division->property("controlText").toString());

        const int targetDivision = initial.gridMinDenom == 8 ? 16 : 8;
        const int targetDivisionRow = divisionMenu.model->rowForId(targetDivision);
        QVERIFY2(targetDivisionRow >= 0, "the division menu omitted the chosen denominator");
        const songview::QuickMenuItem *const targetDivisionItem =
            divisionMenu.model->itemAt(targetDivisionRow);
        QVERIFY(targetDivisionItem);
        const QString targetDivisionText = targetDivisionItem->text;
        QVERIFY2(quick_popup::clickMenuRow(*divisionMenu.session, targetDivisionRow),
                 "the division row did not receive a real click");
        QCoreApplication::processEvents();
        QVERIFY2(!divisionMenu.session->isOpen(), "a division pick left the shared menu open");
        QVERIFY(!QApplication::activePopupWidget());
        QVERIFY(!view.findChild<QMenu *>());
        QCOMPARE(view.viewState().gridMinDenom, targetDivision);
        QCOMPARE(surface.ruler->divisionText(), targetDivisionText);
        QCOMPARE(surface.division->property("controlText").toString(), targetDivisionText);

        const RulerGridMenu divisionReopened = openRulerGridMenu(view, *surface.division);
        QVERIFY2(divisionReopened.session, qUtf8Printable(divisionReopened.diagnostic));
        for (int row = 0; row < divisionReopened.model->rowCount(); ++row) {
            const songview::QuickMenuItem *const item = divisionReopened.model->itemAt(row);
            QVERIFY(item);
            QCOMPARE(item->checked, item->id == targetDivision);
        }
        divisionReopened.session->cancel();
        QCoreApplication::processEvents();
        QVERIFY(!divisionReopened.session->isOpen());

        const SongView::ViewState afterDivision = view.viewState();
        const RulerGridMenu feelMenu = openRulerGridMenu(view, *surface.feel);
        QVERIFY2(feelMenu.session, qUtf8Printable(feelMenu.diagnostic));
        QVERIFY2(!QApplication::activePopupWidget(),
                 "opening the feel menu created a native popup widget");
        QVERIFY2(!view.findChild<QMenu *>(), "opening the feel menu left a QMenu under SongView");

        static constexpr std::array<int, 2> feelIds{0, 1};
        QCOMPARE(feelMenu.model->rowCount(), int(feelIds.size()));
        int feelChecked = 0;
        for (int row = 0; row < feelMenu.model->rowCount(); ++row) {
            const songview::QuickMenuItem *const item = feelMenu.model->itemAt(row);
            QVERIFY(item);
            QCOMPARE(item->id, feelIds[std::size_t(row)]);
            QVERIFY(item->enabled);
            QVERIFY(item->checkable);
            feelChecked += item->checked ? 1 : 0;
        }
        QCOMPARE(feelChecked, 1);
        const int currentFeelId = afterDivision.gridTriplet ? 1 : 0;
        const int currentFeelRow = feelMenu.model->rowForId(currentFeelId);
        QVERIFY2(currentFeelRow >= 0, "the feel menu omitted the current grid feel");
        const songview::QuickMenuItem *const currentFeel = feelMenu.model->itemAt(currentFeelRow);
        QVERIFY(currentFeel && currentFeel->checked);
        QCOMPARE(currentFeel->text, surface.feel->property("controlText").toString());

        const int targetFeel = afterDivision.gridTriplet ? 0 : 1;
        const int targetFeelRow = feelMenu.model->rowForId(targetFeel);
        QVERIFY2(targetFeelRow >= 0, "the feel menu omitted the alternate grid feel");
        const songview::QuickMenuItem *const targetFeelItem = feelMenu.model->itemAt(targetFeelRow);
        QVERIFY(targetFeelItem);
        const QString targetFeelText = targetFeelItem->text;
        QVERIFY2(quick_popup::clickMenuRow(*feelMenu.session, targetFeelRow),
                 "the feel row did not receive a real click");
        QCoreApplication::processEvents();
        QVERIFY2(!feelMenu.session->isOpen(), "a feel pick left the shared menu open");
        QCOMPARE(view.viewState().gridTriplet, targetFeel == 1);
        QCOMPARE(surface.ruler->feelText(), targetFeelText);
        QCOMPARE(surface.feel->property("controlText").toString(), targetFeelText);

        const RulerGridMenu feelReopened = openRulerGridMenu(view, *surface.feel);
        QVERIFY2(feelReopened.session, qUtf8Printable(feelReopened.diagnostic));
        for (int row = 0; row < feelReopened.model->rowCount(); ++row) {
            const songview::QuickMenuItem *const item = feelReopened.model->itemAt(row);
            QVERIFY(item);
            QCOMPARE(item->checked, item->id == targetFeel);
        }
    }

    void rulerGridCheckedRowClickClosesWithoutChange()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        SongView &view = host.view();
        const RulerGridSurface surface = rulerGridSurface(view);
        QVERIFY2(surface.valid(), "could not discover the Quick ruler grid controls");
        const quick_popup::PromptGuard guard(view);

        const SongView::ViewState before = view.viewState();
        const QString divisionText = surface.division->property("controlText").toString();
        const RulerGridMenu opened = openRulerGridMenu(view, *surface.division);
        QVERIFY2(opened.session, qUtf8Printable(opened.diagnostic));
        const int checkedRow = opened.model->rowForId(before.gridMinDenom);
        QVERIFY2(checkedRow >= 0, "the division menu omitted its checked row");
        QVERIFY2(quick_popup::clickMenuRow(*opened.session, checkedRow),
                 "the checked division row did not receive a real click");
        QCoreApplication::processEvents();
        QVERIFY2(!opened.session->isOpen(), "clicking the checked division row left the menu open");
        QCOMPARE(view.viewState().gridMinDenom, before.gridMinDenom);
        QCOMPARE(view.viewState().gridTriplet, before.gridTriplet);
        QCOMPARE(surface.division->property("controlText").toString(), divisionText);

        // Ordinary activation restores the invoking QML control, even when its
        // owner setter correctly early-returns for an already-checked value.
        QTRY_VERIFY2(surface.division->hasActiveFocus(),
                     "the checked division choice did not return focus to its control");
        QTest::keyClick(opened.session->window(), Qt::Key_Return);
        const RulerGridMenu keyboardReopened = awaitRulerGridMenu(
            view, QStringLiteral("Return on the focused division control did not reopen its menu"));
        QVERIFY2(keyboardReopened.session, qUtf8Printable(keyboardReopened.diagnostic));
        QCOMPARE(keyboardReopened.model->rowCount(), 5);
        const int reopenedCheckedRow = keyboardReopened.model->rowForId(before.gridMinDenom);
        QVERIFY(reopenedCheckedRow >= 0);
        const songview::QuickMenuItem *const reopenedChecked =
            keyboardReopened.model->itemAt(reopenedCheckedRow);
        QVERIFY(reopenedChecked && reopenedChecked->checked);
        QVERIFY(!QApplication::activePopupWidget());
        QVERIFY(!view.findChild<QMenu *>());
    }

    void rulerGridMenuDismissalSwallowsOutsideClickAndEscape()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        SongView &view = host.view();
        const RulerGridSurface surface = rulerGridSurface(view);
        QVERIFY2(surface.valid(), "could not discover the Quick ruler grid controls");
        const quick_popup::PromptGuard guard(view);

        const QPointF leftLocal(surface.rulerInput->width() * 0.1,
                                surface.rulerInput->height() * 0.75);
        const QPointF rightLocal(surface.rulerInput->width() * 0.9,
                                 surface.rulerInput->height() * 0.75);
        const QPoint left = surface.rulerInput->mapToScene(leftLocal).toPoint();
        const QPoint right = surface.rulerInput->mapToScene(rightLocal).toPoint();
        QTest::mouseClick(surface.quick->quickWindow(), Qt::LeftButton, Qt::NoModifier, left);
        QCoreApplication::processEvents();
        const uint64_t leftTick = view.editCursorTick();
        QTest::mouseClick(surface.quick->quickWindow(), Qt::LeftButton, Qt::NoModifier, right);
        QCoreApplication::processEvents();
        const uint64_t rightTick = view.editCursorTick();
        QVERIFY2(leftTick != rightTick,
                 "the ruler dismissal probe did not span two distinct cursor positions");
        QTest::mouseClick(surface.quick->quickWindow(), Qt::LeftButton, Qt::NoModifier, left);
        QCoreApplication::processEvents();
        QCOMPARE(view.editCursorTick(), leftTick);

        const SongView::ViewState beforeDismissal = view.viewState();
        const RulerGridMenu divisionMenu = openRulerGridMenu(view, *surface.division);
        QVERIFY2(divisionMenu.session, qUtf8Printable(divisionMenu.diagnostic));
        // The drawn frame is the exact menu box: quickMenuFrame lives at
        // menuOrigin with menuWidth/menuHeight, its own MouseArea absorbs
        // ring presses, and only row presses activate. The full-window panel
        // root is just the wrapper, so ground the probe on the frame itself.
        QQuickItem *const frame = quick_popup::menuFrame(*divisionMenu.session);
        QVERIFY(frame);
        const QRectF frameScene = frame->mapRectToScene(frame->boundingRect());
        const QPoint probe = [&] {
            for (const qreal xFraction : {0.9, 0.5, 0.25}) {
                const QPoint candidate =
                    surface.rulerInput
                        ->mapToScene(QPointF(surface.rulerInput->width() * xFraction,
                                             surface.rulerInput->height() * 0.75))
                        .toPoint();
                if (!frameScene.contains(candidate))
                    return candidate;
            }
            return QPoint();
        }();
        QVERIFY2(!probe.isNull(), "no ruler point lies outside the division menu frame");

        QTest::mouseClick(surface.quick->quickWindow(), Qt::LeftButton, Qt::NoModifier, probe);
        QCoreApplication::processEvents();
        QVERIFY2(!divisionMenu.session->isOpen(),
                 "an outside click did not dismiss the division menu");
        QCOMPARE(view.viewState().gridMinDenom, beforeDismissal.gridMinDenom);
        QCOMPARE(view.viewState().gridTriplet, beforeDismissal.gridTriplet);
        QCOMPARE(view.editCursorTick(), leftTick);
        QVERIFY2(!surface.ruler->gestureActive(),
                 "the dismissed outside press leaked into the ruler as an active gesture");
        QVERIFY(!QApplication::activePopupWidget());
        QVERIFY(!view.findChild<QMenu *>());

        const RulerGridMenu feelMenu = openRulerGridMenu(view, *surface.feel);
        QVERIFY2(feelMenu.session, qUtf8Printable(feelMenu.diagnostic));
        QTest::keyClick(feelMenu.session->window(), Qt::Key_Escape);
        QCoreApplication::processEvents();
        QVERIFY2(!feelMenu.session->isOpen(), "Escape did not dismiss the feel menu");
        QCOMPARE(view.viewState().gridMinDenom, beforeDismissal.gridMinDenom);
        QCOMPARE(view.viewState().gridTriplet, beforeDismissal.gridTriplet);
        QCOMPARE(view.editCursorTick(), leftTick);

        // Nonvacuity: the probe point itself must act on the ruler — with the
        // menus closed, a click there has to move the edit cursor away from
        // the settled tick, so a probe that could not act fails loudly here.
        QTest::mouseClick(surface.quick->quickWindow(), Qt::LeftButton, Qt::NoModifier, probe);
        QCoreApplication::processEvents();
        QVERIFY2(view.editCursorTick() != leftTick,
                 "the dismissal probe point does not act on the ruler");
    }

    void rulerGridClosePopupsCancelsOwnedNotForeignPopups()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        SongView &view = host.view();
        const RulerGridSurface surface = rulerGridSurface(view);
        QVERIFY2(surface.valid(), "could not discover the Quick ruler grid controls");
        const quick_popup::PromptGuard guard(view);

        const SongView::ViewState before = view.viewState();
        const RulerGridMenu gridMenu = openRulerGridMenu(view, *surface.division);
        QVERIFY2(gridMenu.session, qUtf8Printable(gridMenu.diagnostic));
        surface.ruler->closePopups();
        QCoreApplication::processEvents();
        QVERIFY2(!gridMenu.session->isOpen(), "closePopups did not cancel the Quick division menu");
        QVERIFY(!QApplication::activePopupWidget());
        QVERIFY(!view.findChild<QMenu *>());
        QCOMPARE(view.viewState().gridMinDenom, before.gridMinDenom);
        QCOMPARE(view.viewState().gridTriplet, before.gridTriplet);

        // A roll-owned shared-session menu is a foreign owner: closePopups()
        // must leave it alone (the owns() guard) instead of stealing another
        // band's popup, and the grid host must stay cleanly reusable after
        // the foreign takeover and dismissal.
        auto *rollInput = surface.quick->rootObject()->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineRollInput"));
        QVERIFY(rollInput);
        // The shared time-selection menu only exists while a range is active,
        // and the roll opens it from an empty-plot release without drag
        // distance: seed a real range and right-click an unoccupied row
        // inside it, exactly like a production dismissal-adjacent gesture.
        songview::EditorSelectionModel::TimeSelection range;
        range.startTick = 0;
        range.endTick = 48;
        range.scope = songview::EditorSelectionModel::TimeSelection::Tracks;
        view.selectionModel().setTimeSelection(range);
        const checks::rollcheck::SnappedRows rows{view, *rollInput};
        int emptyKey = -1;
        for (int key = 0; key < 128 && emptyKey < 0; ++key) {
            const int y = rows.centerY(key);
            if (y < 0 || y >= rollInput->height())
                continue;
            const bool occupied =
                std::any_of(view.model().notes.cbegin(), view.model().notes.cend(),
                            [key](const ViewNote &note) {
                                return note.key == key && note.startTick <= 6 && 6 < note.endTick;
                            });
            if (!occupied)
                emptyKey = key;
        }
        QVERIFY2(emptyKey >= 0, "the fixture left no empty roll row for the foreign menu");
        const QPointF foreignMenuPoint(qRound(view.camera().displayX(6.0, 0.0, rows.dpr())),
                                       rows.centerY(emptyKey));
        checks::events::sendMouse(*rollInput, QEvent::MouseButtonPress, foreignMenuPoint,
                                  Qt::RightButton, Qt::RightButton, Qt::NoModifier);
        checks::events::sendMouse(*rollInput, QEvent::MouseButtonRelease, foreignMenuPoint,
                                  Qt::RightButton, Qt::NoButton, Qt::NoModifier);
        const RulerGridMenu foreignMenu = awaitRulerGridMenu(
            view, QStringLiteral("right-clicking empty roll space did not open a foreign menu"));
        QVERIFY2(foreignMenu.session, qUtf8Printable(foreignMenu.diagnostic));
        QVERIFY2(foreignMenu.model != gridMenu.model,
                 "the roll right-click did not replace the grid menu with a foreign one");

        surface.ruler->closePopups();
        QCoreApplication::processEvents();
        QVERIFY2(foreignMenu.session->isOpen(),
                 "closePopups cancelled a foreign-owned popup session");
        QVERIFY(quick_popup::menuPanel(*foreignMenu.session));

        QTest::keyClick(foreignMenu.session->window(), Qt::Key_Escape);
        QCoreApplication::processEvents();
        QVERIFY2(!foreignMenu.session->isOpen(), "Escape did not dismiss the foreign menu");

        const RulerGridMenu reopenedGrid = openRulerGridMenu(view, *surface.division);
        QVERIFY2(reopenedGrid.session, qUtf8Printable(reopenedGrid.diagnostic));
        QCOMPARE(reopenedGrid.model->rowCount(), 5);
        const int reusedCheckedRow = reopenedGrid.model->rowForId(before.gridMinDenom);
        QVERIFY(reusedCheckedRow >= 0);
        QVERIFY(reopenedGrid.model->itemAt(reusedCheckedRow)->checked);
        QCOMPARE(view.viewState().gridMinDenom, before.gridMinDenom);
        QCOMPARE(view.viewState().gridTriplet, before.gridTriplet);
    }
    void actionBackedQuickRowsCloseBeforeTriggerAndRetire()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        SongView &view = host.view();
        const RulerGridSurface surface = rulerGridSurface(view);
        QVERIFY2(surface.valid(), "could not discover the Quick ruler grid controls");
        const quick_popup::PromptGuard guard(view);
        view.selectionModel().clearTimeSelection();

        songview::QuickPopupSession *const session = quick_popup::popupSession(view);
        QVERIFY2(session && session->window(), "the timeline Quick canvas has no popup session");
        songview::QuickMenuHost actionHost;
        actionHost.setPopupSession(session);
        const QPointF menuPosition = surface.division->mapToScene(
            QPointF(surface.division->width() / 2.0, surface.division->height() / 2.0));
        const auto openActionMenu = [&actionHost, session,
                                     &menuPosition](songview::QuickMenuModel &model) {
            actionHost.open(&model, menuPosition);
            return QTest::qWaitFor(
                [session] { return session->isOpen() && quick_popup::menuPanel(*session); });
        };

        QAction formAction(QStringLiteral("&Insert && Time"));
        formAction.setShortcut(
            QKeySequence(QKeyCombination(Qt::ControlModifier | Qt::ShiftModifier, Qt::Key_I)));
        formAction.setCheckable(true);
        formAction.setChecked(true);
        songview::QuickMenuModel formModel;
        formModel.setItems({songview::QuickMenuItem::fromAction(formAction, 100)});
        const songview::QuickMenuItem *const formItem = formModel.itemAt(0);
        QVERIFY(formItem);
        QVERIFY(formItem->isActionBacked());
        QVERIFY(formItem->action.data() == &formAction);
        QCOMPARE(formItem->text, QStringLiteral("Insert & Time"));
        QCOMPARE(formItem->shortcutText, formAction.shortcut().toString(QKeySequence::NativeText));
        QVERIFY(formItem->enabled);
        QVERIFY(formItem->checkable);
        QVERIFY(formItem->checked);

        QSignalSpy formTriggered(&formAction, &QAction::triggered);
        QSignalSpy actionActivated(&actionHost, &songview::QuickMenuHost::actionActivated);
        QVERIFY(formTriggered.isValid());
        QVERIFY(actionActivated.isValid());
        bool menuClosedBeforeForm = false;
        bool completionFollowedTrigger = false;
        connect(&formAction, &QAction::triggered, &actionHost, [&] {
            menuClosedBeforeForm = !actionHost.isOpen() && !session->isOpen();
            view.insertTime();
        });
        connect(&actionHost, &songview::QuickMenuHost::actionActivated, &actionHost,
                [&](QAction *action) {
                    completionFollowedTrigger = formTriggered.count() == 1 && action == &formAction;
                });
        QVERIFY2(openActionMenu(formModel), "the QAction row did not render as a Quick menu");
        QVERIFY2(quick_popup::clickMenuRow(*session, 0),
                 "the rendered QAction row did not receive a real click");
        QTRY_VERIFY2(quick_popup::promptItem(*session, QLatin1String("insertTimePrompt")),
                     "triggering the QAction row did not open the Insert Time form");
        QVERIFY(menuClosedBeforeForm);
        QVERIFY(completionFollowedTrigger);
        QCOMPARE(formTriggered.count(), 1);
        QCOMPARE(actionActivated.count(), 1);
        QVERIFY(!formAction.isChecked());
        session->cancel();
        QCoreApplication::processEvents();
        QVERIFY2(!session->isOpen(), "cancelling the form left the shared popup session open");

        QAction *closeDestroyedAction = new QAction(QStringLiteral("Destroy after close"));
        songview::QuickMenuModel closeDestroyedModel;
        closeDestroyedModel.setItems(
            {songview::QuickMenuItem::fromAction(*closeDestroyedAction, 101)});
        QPointer<QAction> closeDestroyedGuard{closeDestroyedAction};
        QSignalSpy closeDestroyedTriggered(closeDestroyedAction, &QAction::triggered);
        QSignalSpy closeDestroyedActivated(&actionHost, &songview::QuickMenuHost::actionActivated);
        const QMetaObject::Connection destroyAfterClose =
            connect(&actionHost, &songview::QuickMenuHost::closed, &actionHost, [&] {
                delete closeDestroyedAction;
                closeDestroyedAction = nullptr;
            });
        QVERIFY2(openActionMenu(closeDestroyedModel),
                 "the post-close destruction row did not render as a Quick menu");
        QVERIFY2(quick_popup::clickMenuRow(*session, 0),
                 "the post-close destruction row did not receive a real click");
        QCoreApplication::processEvents();
        QVERIFY(!closeDestroyedGuard);
        QCOMPARE(closeDestroyedTriggered.count(), 0);
        QCOMPARE(closeDestroyedActivated.count(), 0);
        QObject::disconnect(destroyAfterClose);

        QAction *destroyedAction = new QAction(QStringLiteral("Destroyed"));
        songview::QuickMenuModel destroyedModel;
        destroyedModel.setItems({songview::QuickMenuItem::fromAction(*destroyedAction, 102)});
        QPointer<QAction> destroyedGuard{destroyedAction};
        QSignalSpy destroyedTriggered(destroyedAction, &QAction::triggered);
        QVERIFY2(openActionMenu(destroyedModel),
                 "the destruction-observed QAction row did not render as a Quick menu");
        delete destroyedAction;
        QCoreApplication::processEvents();
        QVERIFY(!destroyedGuard);
        QVERIFY2(!session->isOpen(), "destroying an action-backed row did not cancel its menu");
        QCOMPARE(destroyedTriggered.count(), 0);

        QAction disabledAction(QStringLiteral("Disabled"));
        disabledAction.setEnabled(false);
        songview::QuickMenuModel disabledModel;
        disabledModel.setItems({songview::QuickMenuItem::fromAction(disabledAction, 103)});
        QSignalSpy disabledTriggered(&disabledAction, &QAction::triggered);
        QVERIFY2(openActionMenu(disabledModel),
                 "the disabled QAction row did not render as a Quick menu");
        QVERIFY2(quick_popup::clickMenuRow(*session, 0),
                 "the disabled QAction row did not receive a real click");
        QCoreApplication::processEvents();
        QVERIFY2(session->isOpen(), "clicking a disabled QAction row closed its menu");
        QCOMPARE(disabledTriggered.count(), 0);
        session->cancel();
        QCoreApplication::processEvents();

        QAction submenuAction(QStringLiteral("Unopened submenu action"));
        songview::QuickMenuItem submenu;
        submenu.id = 104;
        submenu.text = QStringLiteral("Commands");
        submenu.children.push_back(songview::QuickMenuItem::fromAction(submenuAction, 105));
        songview::QuickMenuModel submenuModel;
        submenuModel.setItems({submenu});
        QVERIFY2(openActionMenu(submenuModel),
                 "the unopened-submenu QAction row did not render its root menu");
        submenuAction.setText(QStringLiteral("Changed while unopened"));
        QCoreApplication::processEvents();
        QVERIFY2(!session->isOpen(), "changing an unopened submenu action did not cancel its root");

        QVERIFY2(openActionMenu(submenuModel),
                 "the reopened submenu QAction root did not render as a Quick menu");
        QTest::keyClick(session->window(), Qt::Key_Down);
        QTest::keyClick(session->window(), Qt::Key_Right);
        QTRY_VERIFY2(actionHost.currentModel() != &submenuModel,
                     "the action-backed submenu did not open");
        QTest::keyClick(session->window(), Qt::Key_Left);
        QCOMPARE(actionHost.currentModel(), &submenuModel);
        submenuAction.setText(QStringLiteral("Changed after submenu pop"));
        QCoreApplication::processEvents();
        QVERIFY2(!session->isOpen(), "changing a popped submenu action did not cancel its root");

        QAction resetAction(QStringLiteral("Reset root"));
        songview::QuickMenuModel resetModel;
        resetModel.setItems({songview::QuickMenuItem::fromAction(resetAction, 106)});
        QVERIFY2(openActionMenu(resetModel),
                 "the action-backed reset root did not render as a Quick menu");
        resetModel.setItems({songview::QuickMenuItem::fromAction(resetAction, 106)});
        QCoreApplication::processEvents();
        QVERIFY2(!session->isOpen(), "resetting an action-backed root did not cancel its menu");

        songview::QuickMenuItem stayOpenItem;
        stayOpenItem.id = 107;
        stayOpenItem.text = QStringLiteral("Local filter");
        stayOpenItem.checkable = true;
        stayOpenItem.checked = true;
        stayOpenItem.stayOpen = true;
        songview::QuickMenuModel stayOpenModel;
        stayOpenModel.setItems({stayOpenItem});
        QSignalSpy stayOpenActivated(&stayOpenModel, &songview::QuickMenuModel::activated);
        QVERIFY2(openActionMenu(stayOpenModel),
                 "the value-only stay-open row did not render as a Quick menu");
        stayOpenModel.setItems({stayOpenItem});
        QCoreApplication::processEvents();
        QVERIFY2(session->isOpen(), "resetting a value-only root unexpectedly cancelled its menu");
        QVERIFY2(quick_popup::clickMenuRow(*session, 0),
                 "the value-only stay-open row did not receive a real click");
        QCoreApplication::processEvents();
        const songview::QuickMenuItem *const stayOpenResult = stayOpenModel.itemAt(0);
        QVERIFY(stayOpenResult);
        QVERIFY2(!stayOpenResult->checked,
                 "the value-only stay-open row did not retain its checked-state behavior");
        QCOMPARE(stayOpenActivated.count(), 1);
        QVERIFY2(session->isOpen(), "the value-only stay-open row unexpectedly closed its menu");
        session->cancel();
        QCoreApplication::processEvents();
    }
};
} // namespace
} // namespace checks::host

int runRulerGridMenuCheck(const QStringList &qtArguments)
{
    checks::host::RulerGridMenuTest test;
    QStringList arguments{QStringLiteral("ruler-grid-menu")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "tst_rulergridmenu.moc"
