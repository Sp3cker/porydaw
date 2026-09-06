#include "checks/eventviews/eventview_fixture.h"
#include "checks/eventviews/tst_eventviews.h"

#include <QCoreApplication>
#include <QItemSelectionModel>
#include <QScrollBar>
#include <QTableView>
#include <QtTest>

#include <vector>

#include "ui/eventlistview.h"
#include "ui/eventtabletypes.h"
#include "ui/songview.h"

using checks::eventviews::EventWidgets;
using checks::eventviews::FixtureShape;

namespace {

int playheadRowOracle(const SmfTrack &track, double tick, int eotRow)
{
    if (tick < 0)
        return -1;
    if (tick >= double(track.endTick))
        return eotRow;
    int row = -1;
    for (int index = 0; index < int(track.events.size()); ++index) {
        if (double(track.events[index].tick) > tick)
            break;
        row = index;
    }
    return row;
}

int onlyTintedRow(const eventlist::EventTableModel &model)
{
    int tinted = -1;
    for (int row = 0; row < model.rowCount(); ++row) {
        bool any = false;
        bool wholeRow = true;
        for (int column = 0; column < model.columnCount(); ++column) {
            const bool hasTint = model.data(model.index(row, column), Qt::BackgroundRole).isValid();
            any = any || hasTint;
            wholeRow = wholeRow && hasTint;
        }
        if (any != wholeRow || (wholeRow && tinted >= 0))
            return -2;
        if (wholeRow)
            tinted = row;
    }
    return tinted;
}

} // namespace

void EventViewsPlayheadTest::tintLastOfRun_data()
{
    QTest::addColumn<uint64_t>("tick");
    QTest::newRow("before first event") << 1ULL;
    QTest::newRow("same tick run") << 60ULL;
    QTest::newRow("past end of track") << 130ULL;
}

void EventViewsPlayheadTest::tintLastOfRun()
{
    QFETCH(uint64_t, tick);
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    const SmfTrack &track = opened.fixture->document().smf().tracks[widgets.model->chunk()];
    const int expected = playheadRowOracle(track, double(tick), widgets.model->rowCount() - 1);

    widgets.events->setPlayheadTick(double(tick), true);
    QTRY_COMPARE(widgets.model->playRow(), expected);
    QCOMPARE(onlyTintedRow(*widgets.model), expected);
    widgets.events->setPlayheadTick(-1.0, false);
    QTRY_COMPARE(widgets.model->playRow(), -1);
    QCOMPARE(onlyTintedRow(*widgets.model), -1);
}

void EventViewsPlayheadTest::focusCommitsCursor()
{
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    const int eventRow =
        checks::eventviews::rowForTickAndType(*widgets.model, 70, eventlist::TypeNoteOn);
    QVERIFY(eventRow >= 0);
    widgets.table->setCurrentIndex(widgets.model->index(eventRow, 0));
    QTRY_COMPARE(opened.fixture->view().editCursorTick(), 70ULL);
    widgets.table->setCurrentIndex(widgets.model->index(widgets.model->rowCount() - 1, 0));
    QTRY_COMPARE(opened.fixture->view().editCursorTick(), 120ULL);
}

void EventViewsPlayheadTest::focusedSiblingWins()
{
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    const int first = checks::eventviews::rowForTickAndType(*widgets.model, 60, eventlist::TypeCc);
    QVERIFY(first >= 0);
    const int sibling = first + 1;
    QCOMPARE(
        widgets.model
            ->data(widgets.model->index(sibling, eventlist::EventTableModel::ColTick), Qt::EditRole)
            .toULongLong(),
        60ULL);

    widgets.events->setPlayheadTick(-1.0, false);
    widgets.table->setCurrentIndex(widgets.model->index(first, 0));
    widgets.events->setPlayheadTick(60.0, false);
    QTRY_COMPARE(widgets.model->playRow(), first);
    QCOMPARE(onlyTintedRow(*widgets.model), first);
    widgets.events->setPlayheadTick(59.999, false);
    QTRY_COMPARE(widgets.model->playRow(), first);

    widgets.table->setCurrentIndex(widgets.model->index(sibling, 0));
    QTRY_COMPARE(widgets.model->playRow(), sibling);
    QCOMPARE(onlyTintedRow(*widgets.model), sibling);
    const int other =
        checks::eventviews::rowForTickAndType(*widgets.model, 70, eventlist::TypeNoteOn);
    QVERIFY(other >= 0);
    widgets.table->setCurrentIndex(widgets.model->index(other, 0));
    widgets.events->setPlayheadTick(60.0, false);
    const SmfTrack &track = opened.fixture->document().smf().tracks[widgets.model->chunk()];
    const int expected = playheadRowOracle(track, 60.0, widgets.model->rowCount() - 1);
    QTRY_COMPARE(widgets.model->playRow(), expected);
    QCOMPARE(onlyTintedRow(*widgets.model), expected);
}

void EventViewsPlayheadTest::samplePathAndProgrammaticRestore()
{
    const auto opened = checks::eventviews::openTabFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    const MidiTimeline *timeline = opened.fixture->view().timeline();
    QVERIFY(timeline);
    const SmfTrack &track = opened.fixture->document().smf().tracks[widgets.model->chunk()];

    // Opening the list gives its first row a current-index preference.
    // A programmatic transport update must use the last event at the sample's
    // tick when no row was explicitly focused.
    widgets.table->selectionModel()->clearCurrentIndex();
    opened.fixture->view().setPlayheadSample(timeline->sampleForTick(track.endTick + 1), false);
    opened.fixture->view().setPlayheadSample(0, false);
    const int tickZero = playheadRowOracle(track, 0.0, widgets.model->rowCount() - 1);
    QTRY_COMPARE(widgets.model->playRow(), tickZero);
    QCOMPARE(onlyTintedRow(*widgets.model), tickZero);

    const int focused =
        checks::eventviews::rowForTickAndType(*widgets.model, 70, eventlist::TypeNoteOn);
    QVERIFY(focused >= 0);
    widgets.table->setCurrentIndex(widgets.model->index(focused, 0));
    QTRY_COMPARE(opened.fixture->view().editCursorTick(), 70ULL);
    const uint64_t cursorBefore = opened.fixture->view().editCursorTick();
    SmfEvent probe;
    probe.tick = track.endTick + 50;
    probe.status = 0xb0;
    probe.data0 = 7;
    probe.data1 = 64;
    opened.fixture->document().insertRawEvent(widgets.model->chunk(), probe);
    QTRY_COMPARE(opened.fixture->view().editCursorTick(), cursorBefore);
    opened.fixture->document().undoStack()->undo();
    QTRY_COMPARE(opened.fixture->view().editCursorTick(), cursorBefore);
}

void EventViewsPlayheadTest::followScroll()
{
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Long);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    (void)opened.fixture->view().grab();
    QScrollBar *scrollbar = widgets.table->verticalScrollBar();
    QVERIFY(scrollbar);
    QVERIFY(scrollbar->maximum() > scrollbar->minimum());
    const uint64_t pastEnd =
        opened.fixture->document().smf().tracks[widgets.model->chunk()].endTick + 10;

    widgets.events->setPlayheadTick(0.0, false);
    scrollbar->setValue(scrollbar->minimum());
    widgets.events->setFollowPlayhead(true);
    widgets.events->setPlayheadTick(double(pastEnd), true);
    QTRY_VERIFY(scrollbar->value() > scrollbar->minimum());

    widgets.events->setPlayheadTick(0.0, false);
    scrollbar->setValue(scrollbar->minimum());
    widgets.events->setFollowPlayhead(false);
    widgets.events->setPlayheadTick(double(pastEnd), true);
    QTRY_COMPARE(scrollbar->value(), scrollbar->minimum());
    QCOMPARE(onlyTintedRow(*widgets.model), widgets.model->rowCount() - 1);
    widgets.events->setFollowPlayhead(true);
}

int runEventViewsPlayheadCheck(const QStringList &qtArguments)
{
    EventViewsPlayheadTest test;
    QStringList arguments{QStringLiteral("eventviews-playhead")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
