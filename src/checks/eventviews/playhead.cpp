#include "checks/eventviews/eventview_fixture.h"
#include "checks/eventviews/tst_eventviews.h"

#include <QCoreApplication>
#include <QQuickWindow>
#include <QSignalSpy>
#include <QtTest>

#include "ui/eventtabletypes.h"
#include "ui/songview.h"
#include "ui/songview/quick/eventlistcontroller.h"

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
    QTest::newRow("before first event") << uint64_t{1};
    QTest::newRow("same tick run") << uint64_t{60};
    QTest::newRow("past end of track") << uint64_t{130};
}

void EventViewsPlayheadTest::tintLastOfRun()
{
    QFETCH(uint64_t, tick);
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    const SmfTrack &track = opened.fixture->document().smf().tracks[widgets.controller->chunk()];
    const int expected = playheadRowOracle(track, double(tick), widgets.model->rowCount() - 1);

    widgets.controller->setPlayheadTick(double(tick), true);
    QTRY_COMPARE(widgets.model->playRow(), expected);
    QCOMPARE(onlyTintedRow(*widgets.model), expected);
    widgets.controller->setPlayheadTick(-1.0, false);
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
    widgets.controller->focusRow(eventRow);
    QTRY_COMPARE(opened.fixture->view().editCursorTick(), 70ULL);
    widgets.controller->focusRow(widgets.model->rowCount() - 1);
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

    widgets.controller->setPlayheadTick(-1.0, false);
    widgets.controller->focusRow(first);
    widgets.controller->setPlayheadTick(60.0, false);
    QTRY_COMPARE(widgets.model->playRow(), first);
    QCOMPARE(onlyTintedRow(*widgets.model), first);
    widgets.controller->setPlayheadTick(59.999, false);
    QTRY_COMPARE(widgets.model->playRow(), first);

    widgets.controller->focusRow(sibling);
    QTRY_COMPARE(widgets.model->playRow(), sibling);
    QCOMPARE(onlyTintedRow(*widgets.model), sibling);
    const int other =
        checks::eventviews::rowForTickAndType(*widgets.model, 70, eventlist::TypeNoteOn);
    QVERIFY(other >= 0);
    widgets.controller->focusRow(other);
    widgets.controller->setPlayheadTick(60.0, false);
    const SmfTrack &track = opened.fixture->document().smf().tracks[widgets.controller->chunk()];
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
    const SmfTrack &track = opened.fixture->document().smf().tracks[widgets.controller->chunk()];

    // A fresh list has no focused row (currentRow -1), so a programmatic
    // transport update must use the last event at the sample's tick.
    QCOMPARE(widgets.controller->currentRow(), -1);
    opened.fixture->view().setPlayheadSample(timeline->sampleForTick(track.endTick + 1), false);
    opened.fixture->view().setPlayheadSample(0, false);
    const int tickZero = playheadRowOracle(track, 0.0, widgets.model->rowCount() - 1);
    QTRY_COMPARE(widgets.model->playRow(), tickZero);
    QCOMPARE(onlyTintedRow(*widgets.model), tickZero);

    const int focused =
        checks::eventviews::rowForTickAndType(*widgets.model, 70, eventlist::TypeNoteOn);
    QVERIFY(focused >= 0);
    widgets.controller->focusRow(focused);
    QTRY_COMPARE(opened.fixture->view().editCursorTick(), 70ULL);
    const uint64_t cursorBefore = opened.fixture->view().editCursorTick();
    SmfEvent probe;
    probe.tick = track.endTick + 50;
    probe.status = 0xb0;
    probe.data0 = 7;
    probe.data1 = 64;
    opened.fixture->document().insertRawEvent(widgets.controller->chunk(), probe);
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
    EventListController &controller = *widgets.controller;
    QSignalSpy scrolled(&controller, &EventListController::scrollToRow);
    QVERIFY(scrolled.isValid());
    const uint64_t pastEnd =
        opened.fixture->document().smf().tracks[controller.chunk()].endTick + 10;

    // Follow scroll targets the playing row; a full pass emits at least one
    // scrollToRow for the past-end (EOT) position.
    controller.setPlayheadTick(0.0, false);
    controller.setFollowPlayhead(true);
    controller.setPlayheadTick(double(pastEnd), true);
    QTRY_VERIFY(!scrolled.isEmpty());

    // Mouse-held and in-cell-editing states must suppress auto scroll while
    // the tint keeps tracking the play row.
    scrolled.clear();
    controller.setPlayheadTick(0.0, false);
    controller.setPointerDown(true);
    controller.setPlayheadTick(double(pastEnd), true);
    QCOMPARE(scrolled.count(), 0);
    QCOMPARE(onlyTintedRow(*widgets.model), widgets.model->rowCount() - 1);
    controller.setPointerDown(false);

    // In-cell editing suppresses follow scroll the same way; the session is
    // a real editing session on the sentinel row's tick cell.
    scrolled.clear();
    controller.setPlayheadTick(0.0, false);
    QVERIFY(controller.beginEditing(widgets.model->rowCount() - 1,
                                    eventlist::EventTableModel::ColTick));
    controller.setPlayheadTick(double(pastEnd), true);
    QCOMPARE(scrolled.count(), 0);
    QCOMPARE(onlyTintedRow(*widgets.model), widgets.model->rowCount() - 1);
    controller.finishEditing(QString(), false);

    // Follow off: tint only, never a scroll request.
    scrolled.clear();
    controller.setPlayheadTick(0.0, false);
    controller.setFollowPlayhead(false);
    controller.setPlayheadTick(double(pastEnd), true);
    QCOMPARE(scrolled.count(), 0);
    QCOMPARE(onlyTintedRow(*widgets.model), widgets.model->rowCount() - 1);
    controller.setFollowPlayhead(true);
}

int runEventViewsPlayheadCheck(const QStringList &qtArguments)
{
    EventViewsPlayheadTest test;
    QStringList arguments{QStringLiteral("eventviews-playhead")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
