#include "checks/eventviews/eventview_fixture.h"
#include "checks/eventviews/tst_eventviews.h"
#include <QCoreApplication>
#include <QFontInfo>
#include <QGuiApplication>
#include <QQuickItem>
#include <QQuickWindow>
#include <QWheelEvent>
#include <QtTest>

#include "ui/eventtabletypes.h"
#include "ui/songview.h"
#include "ui/songview/quick/quickmenumodel.h"
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

songview::QuickMenuModel *panelModel(QQuickItem &panel)
{
    return qobject_cast<songview::QuickMenuModel *>(panel.property("menuModel").value<QObject *>());
}

// Resolve through ListView.itemAtIndex in QML. Walking contentItem children
// includes retained pooling delegates after a model reset.
QQuickItem *renderedRow(QQuickItem &panel, int row)
{
    QVariant result;
    if (!QMetaObject::invokeMethod(&panel, "rowItem", Q_RETURN_ARG(QVariant, result),
                                   Q_ARG(QVariant, row)))
        return nullptr;
    return result.value<QQuickItem *>();
}

// Scene-space center of the current delegate for this model row. Panel
// creation publishes the menu-open state before ListView realizes its rows.
QPointF menuRowCenter(QQuickItem &panel, int row)
{
    QQuickItem *item = nullptr;
    if (!QTest::qWaitFor([&] {
            item = renderedRow(panel, row);
            return item && item->isVisible() && item->width() > 0 && item->height() > 0;
        }))
        return {};
    return item->mapToScene(QPointF(item->width() / 2.0, item->height() / 2.0));
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
    auto *drawer = widgets.quickWindow->findChild<songview::TimelineInputItem *>(
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
        widgets.quickWindow->findChild<QQuickItem *>(QStringLiteral("eventListVerticalScrollBar"));
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

    QQuickItem *filterButton = window.findChild<QQuickItem *>(QStringLiteral("eventListFilter"));
    QVERIFY(filterButton);
    const QPointF buttonCenter = filterButton->mapToScene(
        QPointF(filterButton->width() / 2.0, filterButton->height() / 2.0));

    QTest::mouseClick(&window, Qt::LeftButton, Qt::NoModifier, buttonCenter.toPoint());
    QTRY_VERIFY(controller.menuOpen());
    QQuickItem *panel =
        checks::eventviews::visualItem(window, QStringLiteral("quickMenuPanelRoot"));
    QVERIFY(panel);
    songview::QuickMenuModel *model = panelModel(*panel);
    QVERIFY(model);
    const int rows = model->rowCount();
    QCOMPARE(rows, 7); // the fixture's fixed filter-category ledger

    const auto rowChecked = [&model](int row) {
        return model->data(model->index(row, 0), songview::QuickMenuModel::CheckedRole).toBool();
    };
    const auto ticksMirrorCheckedRole = [&panel, &rows, &rowChecked] {
        for (int row = 0; row < rows; ++row) {
            QQuickItem *delegate = renderedRow(*panel, row);
            QVERIFY(delegate);
            QCOMPARE(tickRenderedChecked(*delegate), rowChecked(row));
        }
    };
    ticksMirrorCheckedRole(); // FilterAll: every row renders its check

    // Hover the Meta row, then click it: the stayOpen toggle flips the mask,
    // rebuilds the model in place, and keeps session and highlight by id.
    const int metaRow = rows - 1;
    QTest::mouseMove(&window, menuRowCenter(*panel, metaRow).toPoint());
    QCoreApplication::processEvents();
    QCOMPARE(panel->property("highlightedRow").toInt(), metaRow);
    QTest::mouseClick(&window, Qt::LeftButton, Qt::NoModifier,
                      menuRowCenter(*panel, metaRow).toPoint());
    QTRY_VERIFY(!bool(controller.filterMask() & eventlist::EventTableModel::FilterMeta));
    QVERIFY(controller.menuOpen());
    panel = checks::eventviews::visualItem(window, QStringLiteral("quickMenuPanelRoot"));
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
    QTRY_VERIFY(!checks::eventviews::visualItem(window, QStringLiteral("quickMenuPanelRoot")));
    QCOMPARE(controller.filterMask(), maskBeforeCancel);

    // A real press on the table outside the frame cancels the same way.
    QTest::mouseClick(&window, Qt::LeftButton, Qt::NoModifier, buttonCenter.toPoint());
    QTRY_VERIFY(controller.menuOpen());
    const QPointF tablePoint =
        checks::eventviews::cellSceneCenter(widgets, 0, eventlist::EventTableModel::ColData);
    QVERIFY(!tablePoint.isNull());
    QTest::mouseClick(&window, Qt::LeftButton, Qt::NoModifier, tablePoint.toPoint());
    QCoreApplication::processEvents();
    QTRY_VERIFY(!controller.menuOpen());
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
    QQuickItem *panel =
        checks::eventviews::visualItem(window, QStringLiteral("quickMenuPanelRoot"));
    QVERIFY(panel);
    QCOMPARE(panelModel(*panel)->rowCount(), 6); // insert, sep, move up, move down, sep, delete

    const QPointF insertCenter = menuRowCenter(*panel, 0);
    QVERIFY(!insertCenter.isNull());
    QTest::mouseMove(&window, insertCenter.toPoint());
    QTRY_COMPARE(panel->property("highlightedRow").toInt(), 0);
    QTest::mouseClick(&window, Qt::LeftButton, Qt::NoModifier, insertCenter.toPoint());
    QTRY_VERIFY(!controller.menuOpen());
    QTRY_VERIFY(!checks::eventviews::visualItem(window, QStringLiteral("quickMenuPanelRoot")));
    QTRY_COMPARE(widgets.model->rowCount(), rowsBefore + 1);
    QCOMPARE(opened.fixture->document().undoStack()->index(), undoBefore + 1);
}

int runEventViewsChromeCheck(const QStringList &qtArguments)
{
    EventViewsChromeTest test;
    QStringList arguments{QStringLiteral("eventviews-chrome")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
