#include "checks/eventviews/eventview_fixture.h"
#include "checks/eventviews/tst_eventviews.h"
#include "checks/quickpopupguard.h"
#include <QCoreApplication>
#include <QFontInfo>
#include <QGuiApplication>
#include <QList>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSignalSpy>
#include <QVariant>
#include <QWheelEvent>
#include <QtTest>

#include "ui/eventtabletypes.h"
#include "ui/songview.h"
#include "ui/songview/quick/quickmenumodel.h"
#include "ui/songview/quick/quickpopupsession.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/typography.h"

using checks::eventviews::EventWidgets;
using checks::eventviews::FixtureShape;

namespace {

// One real wheel notch delivered through the Quick window at a scene point.
void wheelAt(QQuickWindow &window, const QPointF &scenePos, int notches)
{
    QWheelEvent event(scenePos, window.mapToGlobal(scenePos.toPoint()), QPoint(),
                      QPoint(0, notches * 120), Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase,
                      false);
    QCoreApplication::sendEvent(&window, &event);
}

// The row's rendered check mark — the only child carrying the tick stroke
// metric. Its visibility must mirror the model's checked role.
bool tickRenderedChecked(QQuickItem &row)
{
    for (QQuickItem *child : row.childItems()) {
        if (child->property("stroke").isValid())
            return child->isVisible();
    }
    return false;
}

} // namespace

void EventViewsChromeTest::visibilityAndTrackSelection()
{
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    QVERIFY(!opened.fixture->view().eventListVisible());

    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);

    opened.fixture->view().selectTrack(1);
    QTRY_COMPARE(widgets.controller->chunk(),
                 checks::eventviews::chunkForTrack(opened.fixture->document(), 1));
}

void EventViewsChromeTest::rowMirrorPlusEot_data()
{
    QTest::addColumn<int>("shape");
    QTest::newRow("empty chunk") << int(FixtureShape::Empty);
    QTest::newRow("single event at EOT") << int(FixtureShape::EotCoincident);
    QTest::newRow("multi-event chunk") << int(FixtureShape::Basic);
}

void EventViewsChromeTest::rowMirrorPlusEot()
{
    QFETCH(int, shape);
    const auto opened = checks::eventviews::openRigFixture(FixtureShape(shape));
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);

    const int chunk = widgets.controller->chunk();
    QVERIFY(chunk >= 0);
    const SmfTrack &track = opened.fixture->document().smf().tracks[chunk];
    const int projectedTempoRows =
        chunk == 0 ? int(opened.fixture->document().tempoPoints().size()) : 0;
    QCOMPARE(widgets.model->rowCount(), int(track.events.size()) + projectedTempoRows + 1);
    QCOMPARE(
        widgets.model->data(widgets.model->index(widgets.model->rowCount() - 1, 0), Qt::EditRole)
            .toULongLong(),
        track.endTick);
}

void EventViewsChromeTest::monoTypography()
{
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);

    const QFont expected = typography::tableMono(QGuiApplication::font());
    const QFontInfo expectedInfo(expected);
    const int rows[] = {0, widgets.model->rowCount() - 1};
    const int columns[] = {0, 2, 3, 4};
    for (const int row : rows) {
        for (const int column : columns) {
            const QModelIndex index = widgets.model->index(row, column);
            const QFont cell = widgets.model->data(index, Qt::FontRole).value<QFont>();
            QCOMPARE(QFontInfo(cell).family(), expectedInfo.family());
            QCOMPARE(cell.letterSpacingType(), QFont::AbsoluteSpacing);
            QCOMPARE(cell.letterSpacing(), -0.5);
        }
    }

    // The rendered cell editor carries the same numeric face while typing.
    QQuickItem *editor = nullptr;
    QVERIFY(checks::eventviews::openCellEditor(widgets, 0, eventlist::EventTableModel::ColTick,
                                               QStringLiteral("eventListTickEditor"), &editor));
    const QFont editorFont = editor->property("font").value<QFont>();
    QCOMPARE(QFontInfo(editorFont).family(), expectedInfo.family());
    QCOMPARE(editorFont.letterSpacingType(), QFont::AbsoluteSpacing);
    QCOMPARE(editorFont.letterSpacing(), -0.5);
    checks::eventviews::closeCellEditor(widgets);
}

// A real horizontal drag of the Type column's resize handle must widen the
// persisted column through controller.resizeColumn.
void EventViewsChromeTest::columnResizeDrag()
{
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    QQuickItem *const handle = checks::eventviews::visualItem(
        *widgets.quickWindow, QStringLiteral("eventListColumnResizeHandle1"));
    QVERIFY(handle);
    const QList<double> initial = widgets.controller->columnWidths();
    QVERIFY(initial.size() >= 2);

    const QPointF center =
        handle->mapToScene(QPointF(handle->width() / 2.0, handle->height() / 2.0));
    const QPointF target = center + QPointF(40.0, 0.0);
    QTest::mousePress(widgets.quickWindow, Qt::LeftButton, Qt::NoModifier, center.toPoint());
    const int steps = 4;
    for (int step = 1; step <= steps; ++step) {
        const QPointF waypoint = center + (target - center) * (double(step) / steps);
        QTest::mouseMove(widgets.quickWindow, waypoint.toPoint());
        QCoreApplication::processEvents();
    }
    QTest::mouseRelease(widgets.quickWindow, Qt::LeftButton, Qt::NoModifier, target.toPoint());
    QCoreApplication::processEvents();

    QTRY_VERIFY(widgets.controller->columnWidths().value(1) > initial.value(1) + 20.0);
    QCOMPARE(widgets.controller->columnWidths().size(), initial.size());
}

// The page's navigation shortcuts are gated on the event list input's active
// focus: a sibling drawer surface that owns the keyboard keeps it, and the
// event list current row stays put.
void EventViewsChromeTest::drawerFocusKeepsNavigation()
{
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    auto *drawer = widgets.quickRoot->findChild<songview::TimelineInputItem *>(
        QStringLiteral("drawerBarInput"));
    QVERIFY(drawer);
    widgets.controller->selectRow(0, Qt::NoModifier);
    QCoreApplication::processEvents();
    QCOMPARE(widgets.controller->currentRow(), 0);

    QVERIFY(checks::eventviews::focusSurface(widgets, *drawer));
    QTest::keyClick(widgets.quickWindow, Qt::Key_Down);
    QCoreApplication::processEvents();
    QCOMPARE(widgets.controller->currentRow(), 0);
    QVERIFY(drawer->hasActiveFocus());
    QTest::keyClick(widgets.quickWindow, Qt::Key_Up);
    QCoreApplication::processEvents();
    QCOMPARE(widgets.controller->currentRow(), 0);
    QVERIFY(drawer->hasActiveFocus());
}

// Wheel notches past either end must clamp to the scrollbar range instead of
// driving the content offset unbounded.
void EventViewsChromeTest::scrollbarWheelClamps()
{
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Long);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    auto *scrollbar =
        widgets.quickRoot->findChild<QQuickItem *>(QStringLiteral("eventListVerticalScrollBar"));
    QVERIFY(scrollbar);
    QQuickItem *const table = checks::eventviews::eventListTable(widgets);
    QVERIFY(table);
    QTRY_VERIFY(scrollbar->property("maximum").toReal() > 0);
    const qreal maximum = scrollbar->property("maximum").toReal();
    const QPointF center =
        scrollbar->mapToScene(QPointF(scrollbar->width() / 2.0, scrollbar->height() / 2.0));

    for (int notch = 0; notch < 600; ++notch)
        wheelAt(*widgets.quickWindow, center, -1);
    QTRY_COMPARE(table->property("contentY").toReal(), maximum);

    for (int notch = 0; notch < 1200; ++notch)
        wheelAt(*widgets.quickWindow, center, 1);
    QTRY_COMPARE(table->property("contentY").toReal(), 0.0);
}

void EventViewsChromeTest::filterMatrix_data()
{
    QTest::addColumn<QStringList>("categories");
    QTest::addColumn<int>("expectedEvents");
    // The Basic fixture deliberately authors three meta rows, four note rows,
    // and four other channel rows. These are a fixed fixture ledger, not the
    // EventTableModel filtering predicate under test.
    QTest::newRow("meta") << QStringList{QStringLiteral("Meta")} << 3;
    QTest::newRow("meta and notes")
        << QStringList{QStringLiteral("Meta"), QStringLiteral("Notes")} << 7;
    QTest::newRow("none") << QStringList{} << 0;
    QTest::newRow("all") << QStringList{QStringLiteral("Notes"),
                                        QStringLiteral("Control changes"),
                                        QStringLiteral("Program changes"),
                                        QStringLiteral("Pitch bends"),
                                        QStringLiteral("Aftertouch"),
                                        QStringLiteral("SysEx"),
                                        QStringLiteral("Meta")}
                         << 11;
}

void EventViewsChromeTest::filterMatrix()
{
    QFETCH(QStringList, categories);
    QFETCH(int, expectedEvents);
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);

    const struct {
        const char *name;
        int bit;
    } categoriesByBit[] = {
        {"Notes", eventlist::EventTableModel::FilterNotes},
        {"Control changes", eventlist::EventTableModel::FilterCc},
        {"Program changes", eventlist::EventTableModel::FilterProgram},
        {"Pitch bends", eventlist::EventTableModel::FilterBend},
        {"Aftertouch", eventlist::EventTableModel::FilterTouch},
        {"SysEx", eventlist::EventTableModel::FilterSysEx},
        {"Meta", eventlist::EventTableModel::FilterMeta},
    };
    int wantedMask = 0;
    for (const auto &category : categoriesByBit) {
        const bool wanted = categories.contains(QLatin1String(category.name));
        if (wanted)
            wantedMask |= category.bit;
        if (bool(widgets.controller->filterMask() & category.bit) != wanted)
            widgets.controller->filterToggled(category.bit);
    }
    QCOMPARE(widgets.controller->filterMask(), wantedMask);
    QCOMPARE(widgets.model->rowCount(), expectedEvents + 1);
}

void EventViewsChromeTest::viewStateRoundTrip()
{
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);

    SongView::ViewState state = opened.fixture->view().viewState();
    QVERIFY(state.eventList);
    state.eventList = false;
    opened.fixture->view().applyViewState(state);
    QVERIFY(!opened.fixture->view().eventListVisible());

    state = opened.fixture->view().viewState();
    QVERIFY(!state.eventList);
    state.eventList = true;
    opened.fixture->view().applyViewState(state);
    QVERIFY(opened.fixture->view().eventListVisible());
}

// Real rendered filter-menu session: opened through the toolbar button, tick
// rendering mirrors the checked role, a stayOpen toggle rebuilds the model
// without ending the session (highlight restored by id), the host owns keys
// while open, and Escape/outside presses cancel without activating.
void EventViewsChromeTest::filterMenuSession()
{
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    QQuickWindow &window = *widgets.quickWindow;
    EventListController &controller = *widgets.controller;

    QQuickItem *filterButton =
        checks::eventviews::visualItem(window, QStringLiteral("eventListFilter"));
    QVERIFY(filterButton);
    const QPointF buttonCenter = filterButton->mapToScene(
        QPointF(filterButton->width() / 2.0, filterButton->height() / 2.0));

    QTest::mouseClick(&window, Qt::LeftButton, Qt::NoModifier, buttonCenter.toPoint());
    QTRY_VERIFY(controller.menuOpen());
    QQuickItem *panel = checks::eventviews::activeMenuPanel(widgets);
    QVERIFY(panel);
    songview::QuickMenuModel *model = quick_popup::menuModel(*panel);
    QVERIFY(model);
    const int rows = model->rowCount();
    QCOMPARE(rows, 7); // the fixture's fixed filter-category ledger

    const auto rowChecked = [&model](int row) {
        return model->data(model->index(row, 0), songview::QuickMenuModel::CheckedRole).toBool();
    };
    const auto ticksMirrorCheckedRole = [&panel, &rows, &rowChecked] {
        for (int row = 0; row < rows; ++row) {
            QQuickItem *delegate = quick_popup::menuRowItem(*panel, row);
            QVERIFY(delegate);
            QCOMPARE(tickRenderedChecked(*delegate), rowChecked(row));
        }
    };
    ticksMirrorCheckedRole(); // FilterAll: every row renders its check

    // Menu-only type-ahead selects the actual Meta filter delegate; normal
    // text input has no role while this menu session owns the keys.
    const int metaRow = rows - 1;
    QTest::keyClick(&window, Qt::Key_M);
    QTRY_COMPARE(panel->property("highlightedRow").toInt(), metaRow);

    // Hover the Meta row, then click it: the stayOpen toggle flips the mask,
    // rebuilds the model in place, and keeps session and highlight by id.
    QTest::mouseMove(&window, quick_popup::menuRowSceneCenter(*panel, metaRow).toPoint());
    QCoreApplication::processEvents();
    QCOMPARE(panel->property("highlightedRow").toInt(), metaRow);
    QTest::mouseClick(&window, Qt::LeftButton, Qt::NoModifier,
                      quick_popup::menuRowSceneCenter(*panel, metaRow).toPoint());
    QTRY_VERIFY(!bool(controller.filterMask() & eventlist::EventTableModel::FilterMeta));
    QVERIFY(controller.menuOpen());
    panel = checks::eventviews::activeMenuPanel(widgets);
    QVERIFY(panel);
    QTRY_COMPARE(panel->property("highlightedRow").toInt(), metaRow);
    ticksMirrorCheckedRole(); // rebuilt: only Meta renders unchecked

    // The host still owns keys while open: Down wraps onto the first row and
    // Enter toggles it through the same live session.
    QTest::keyClick(&window, Qt::Key_Down);
    QCOMPARE(panel->property("highlightedRow").toInt(), 0);
    QTest::keyClick(&window, Qt::Key_Return);
    QTRY_VERIFY(!bool(controller.filterMask() & eventlist::EventTableModel::FilterNotes));
    QVERIFY(controller.menuOpen());

    // Escape cancels without activating anything.
    const int maskBeforeCancel = controller.filterMask();
    QTest::keyClick(&window, Qt::Key_Escape);
    QTRY_VERIFY(!controller.menuOpen());
    QTRY_VERIFY(!checks::eventviews::activeMenuPanel(widgets));
    QCOMPARE(controller.filterMask(), maskBeforeCancel);

    // A real press and its paired release on the current table cell stay in
    // the popup underlay. If either leaks, the event list starts an editor.
    controller.selectRow(0, Qt::NoModifier);
    QTRY_COMPARE(controller.currentRow(), 0);
    QVERIFY(!controller.isEditing());
    QTest::mouseClick(&window, Qt::LeftButton, Qt::NoModifier, buttonCenter.toPoint());
    QTRY_VERIFY(controller.menuOpen());
    const QPointF tablePoint =
        checks::eventviews::cellSceneCenter(widgets, 0, eventlist::EventTableModel::ColData);
    QVERIFY(!tablePoint.isNull());
    QTest::mouseClick(&window, Qt::LeftButton, Qt::NoModifier, tablePoint.toPoint());
    QTRY_VERIFY(!controller.menuOpen());
    QTRY_VERIFY(!checks::eventviews::activeMenuPanel(widgets));
    QCOMPARE(controller.currentRow(), 0);
    QVERIFY(!controller.isEditing());
    QCOMPARE(controller.filterMask(), maskBeforeCancel);
}

// A right-click on a table row opens the row menu; activating the rendered
// "Insert event" action closes the session first and then inserts one copy.
void EventViewsChromeTest::rowMenuActivationCloses()
{
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    QQuickWindow &window = *widgets.quickWindow;
    EventListController &controller = *widgets.controller;
    const int rowsBefore = widgets.model->rowCount();
    const int undoBefore = opened.fixture->document().undoStack()->index();

    const int row = checks::eventviews::rowForTickAndType(*widgets.model, 60, eventlist::TypeCc);
    QVERIFY(row >= 0);
    const QPointF cell =
        checks::eventviews::cellSceneCenter(widgets, row, eventlist::EventTableModel::ColData);
    QVERIFY(!cell.isNull());
    QTest::mousePress(&window, Qt::RightButton, Qt::NoModifier, cell.toPoint());
    QTest::mouseRelease(&window, Qt::RightButton, Qt::NoModifier, cell.toPoint());
    QCoreApplication::processEvents();
    QTRY_VERIFY(controller.menuOpen());
    QTRY_COMPARE(controller.currentRow(), row); // the pressed row owns the menu
    QQuickItem *panel = checks::eventviews::activeMenuPanel(widgets);
    QVERIFY(panel);

    const QPointF insertCenter = quick_popup::menuRowSceneCenter(*panel, 0);
    QVERIFY(!insertCenter.isNull());
    QTest::mouseMove(&window, insertCenter.toPoint());
    QTRY_COMPARE(panel->property("highlightedRow").toInt(), 0);
    QTest::mouseClick(&window, Qt::LeftButton, Qt::NoModifier, insertCenter.toPoint());
    QTRY_VERIFY(!controller.menuOpen());
    QTRY_VERIFY(!checks::eventviews::activeMenuPanel(widgets));
    QTRY_COMPARE(widgets.model->rowCount(), rowsBefore + 1);
    QCOMPARE(opened.fixture->document().undoStack()->index(), undoBefore + 1);
}

// An outside right press reports the dismissed menu's owner and the retarget
// position to the shared session while the popup layer owns both the press
// and its paired release. Event List has no independent retarget action, so
// the existing row-menu state must not be re-entered by that release.
void EventViewsChromeTest::outsideRightCancelsAndSwallowsRelease()
{
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    QQuickWindow &window = *widgets.quickWindow;
    EventListController &controller = *widgets.controller;

    const int sourceRow =
        checks::eventviews::rowForTickAndType(*widgets.model, 60, eventlist::TypeCc);
    QVERIFY(sourceRow >= 0);
    const QPointF source = checks::eventviews::cellSceneCenter(widgets, sourceRow,
                                                               eventlist::EventTableModel::ColData);
    QVERIFY(!source.isNull());

    QTest::mouseClick(&window, Qt::RightButton, Qt::NoModifier, source.toPoint());
    QTRY_VERIFY(controller.menuOpen());
    QTRY_COMPARE(controller.currentRow(), sourceRow);
    QSignalSpy retargeted(widgets.popupSession, &songview::QuickPopupSession::outsideRightPressed);
    QVERIFY(retargeted.isValid());
    QQuickItem *const panel = checks::eventviews::activeMenuPanel(widgets);
    QVERIFY(panel);
    QObject *const menuOwner = panel->property("host").value<QObject *>();
    QVERIFY2(menuOwner, "the open menu panel did not expose its owning host");
    QQuickItem *const frame =
        checks::eventviews::visualItem(window, QStringLiteral("quickMenuFrame"));
    QVERIFY(frame);
    QPointF target;
    int targetRow = -1;
    for (int row = 0; row < widgets.model->rowCount(); ++row) {
        if (row == sourceRow)
            continue;
        const QPointF candidate =
            checks::eventviews::cellSceneCenter(widgets, row, eventlist::EventTableModel::ColData);
        if (!candidate.isNull() && !frame->contains(frame->mapFromScene(candidate))) {
            target = candidate;
            targetRow = row;
            break;
        }
    }
    QVERIFY(targetRow >= 0);

    QTest::mousePress(&window, Qt::RightButton, Qt::NoModifier, target.toPoint());
    QTRY_COMPARE(retargeted.count(), 1);
    const QList<QVariant> arguments = retargeted.takeFirst();
    QVERIFY2(arguments.constFirst().value<QObject *>() == menuOwner,
             "the dismissed right press reported a foreign owner");
    QCOMPARE(arguments.at(1).toPointF(), QPointF(target.toPoint()));
    QTRY_VERIFY(!controller.menuOpen());
    QTRY_VERIFY(!checks::eventviews::activeMenuPanel(widgets));
    QCOMPARE(controller.currentRow(), sourceRow);

    QTest::mouseRelease(&window, Qt::RightButton, Qt::NoModifier, target.toPoint());
    QCoreApplication::processEvents();
    QVERIFY(!controller.menuOpen());
    QVERIFY(!checks::eventviews::activeMenuPanel(widgets));
    QCOMPARE(controller.currentRow(), sourceRow);
    QVERIFY(!controller.isEditing());
}

int runEventViewsChromeCheck(const QStringList &qtArguments)
{
    EventViewsChromeTest test;
    QStringList arguments{QStringLiteral("eventviews-chrome")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
