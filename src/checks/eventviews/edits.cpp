#include "checks/eventviews/eventview_fixture.h"
#include "checks/eventviews/tst_eventviews.h"

#include <QCoreApplication>
#include <QItemSelectionModel>
#include <QMimeData>
#include <QSignalSpy>
#include <QTableView>
#include <QtTest>

#include <algorithm>
#include <iterator>
#include <memory>
#include <vector>

#include "checks/support/eventsynth.h"
#include "ui/eventlistview.h"
#include "ui/eventtabletypes.h"

using checks::eventviews::EventWidgets;
using checks::eventviews::FixtureShape;

namespace {

int indexOf(const SmfTrack &track, const SmfEvent &target)
{
    const auto found = std::find(track.events.begin(), track.events.end(), target);
    return found == track.events.end() ? -1 : int(found - track.events.begin());
}

int countMatching(const SmfTrack &track, const SmfEvent &target)
{
    return int(std::count(track.events.begin(), track.events.end(), target));
}

SmfEvent controlChange(uint64_t tick, uint8_t controller, uint8_t value)
{
    SmfEvent event;
    event.tick = tick;
    event.status = 0xb0;
    event.data0 = controller;
    event.data1 = value;
    return event;
}

} // namespace

void EventViewsEditsTest::tickEditQueued()
{
    const auto opened = checks::eventviews::openTabFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    const int row =
        checks::eventviews::rowForTickAndType(*widgets.model, 12, eventlist::TypeNoteOn);
    QVERIFY(row >= 0);

    const uint64_t originalTick =
        widgets.model
            ->data(widgets.model->index(row, eventlist::EventTableModel::ColTick), Qt::EditRole)
            .toULongLong();
    const uint64_t editedTick =
        opened.fixture->document().smf().tracks[widgets.model->chunk()].endTick + 3;
    const int beforeIndex = opened.fixture->document().undoStack()->index();
    QVERIFY(widgets.model->setData(widgets.model->index(row, eventlist::EventTableModel::ColTick),
                                   qulonglong(editedTick), Qt::EditRole));
    QTRY_VERIFY(checks::eventviews::rowForTickAndType(*widgets.model, editedTick,
                                                      eventlist::TypeNoteOn) >= 0);
    const int changedRow =
        checks::eventviews::rowForTickAndType(*widgets.model, editedTick, eventlist::TypeNoteOn);
    QCOMPARE(widgets.model
                 ->data(widgets.model->index(changedRow, eventlist::EventTableModel::ColTick),
                        Qt::EditRole)
                 .toULongLong(),
             editedTick);
    QCOMPARE(opened.fixture->document().undoStack()->index(), beforeIndex + 1);
    QVERIFY(checks::eventviews::trackIsSorted(
        opened.fixture->document().smf().tracks[widgets.model->chunk()]));

    opened.fixture->document().undoStack()->undo();
    QTRY_VERIFY(checks::eventviews::rowForTickAndType(*widgets.model, originalTick,
                                                      eventlist::TypeNoteOn) >= 0);
}

void EventViewsEditsTest::tick64BitExact()
{
    const auto opened = checks::eventviews::openTabFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    const int row =
        checks::eventviews::rowForTickAndType(*widgets.model, 12, eventlist::TypeNoteOn);
    QVERIFY(row >= 0);

    constexpr uint64_t tick = 3000000000ULL;
    const int chunk = widgets.model->chunk();
    const int beforeIndex = opened.fixture->document().undoStack()->index();
    QVERIFY(widgets.model->setData(widgets.model->index(row, eventlist::EventTableModel::ColTick),
                                   qulonglong(tick), Qt::EditRole));
    QTRY_COMPARE(opened.fixture->document().undoStack()->index(), beforeIndex + 1);
    const SmfTrack &track = opened.fixture->document().smf().tracks[chunk];
    QVERIFY(!track.events.empty());
    QCOMPARE(track.events.back().tick, tick);
    QVERIFY(checks::eventviews::trackIsSorted(track));

    opened.fixture->document().undoStack()->undo();
    QTRY_VERIFY(checks::eventviews::rowForTickAndType(*widgets.model, 12, eventlist::TypeNoteOn) >=
                0);
}

void EventViewsEditsTest::rawTempoAtomic()
{
    const auto opened = checks::eventviews::openTabFixture(FixtureShape::Tempo);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);

    SongDocument &document = opened.fixture->document();
    const auto tickZeroMeta = [](const SmfTrack &track) {
        std::vector<SmfEvent> events;
        std::copy_if(track.events.begin(), track.events.end(), std::back_inserter(events),
                     [](const SmfEvent &event) { return event.tick == 0 && event.isMeta(); });
        return events;
    };
    const std::vector<SmfEvent> originalTickZeroMeta = tickZeroMeta(document.smf().tracks[0]);
    QVERIFY(!originalTickZeroMeta.empty());
    QVERIFY(widgets.model->tempoRowForExactTick(0) >= 0);

    uint64_t conversionTick = document.smf().tracks[0].endTick;
    for (const SmfEvent &event : document.smf().tracks[0].events)
        conversionTick = std::max(conversionTick, event.tick);
    for (const TempoPoint &point : document.tempoPoints())
        conversionTick = std::max(conversionTick, point.tick);
    conversionTick++;

    SmfEvent conversionEvent;
    conversionEvent.tick = conversionTick;
    conversionEvent.status = 0xff;
    conversionEvent.metaType = 0x06;
    conversionEvent.blob = QByteArrayLiteral("eventviews conversion");
    const int beforeInsertIndex = document.undoStack()->index();
    document.insertRawEvent(0, conversionEvent);
    QCoreApplication::processEvents();
    QCOMPARE(document.undoStack()->index(), beforeInsertIndex + 1);
    int rawRow =
        checks::eventviews::rowForTickAndType(*widgets.model, conversionTick, eventlist::TypeMeta);
    QVERIFY(rawRow >= 0);

    QSignalSpy changed(&document, &SongDocument::documentChanged);
    const int initialIndex = document.undoStack()->index();
    const int initialCount = document.undoStack()->count();

    QVERIFY(
        widgets.model->setData(widgets.model->index(rawRow, eventlist::EventTableModel::ColType),
                               eventlist::TypeTempo, Qt::EditRole));
    QTRY_COMPARE(changed.count(), 1);
    QCOMPARE(document.undoStack()->index(), initialIndex + 1);
    QCOMPARE(document.undoStack()->count(), initialCount + 1);
    QCOMPARE(widgets.model->tempoRowForExactTick(conversionTick) >= 0, true);
    QVERIFY(checks::eventviews::rowForTickAndType(*widgets.model, conversionTick,
                                                  eventlist::TypeMeta) < 0);
    QVERIFY(tickZeroMeta(document.smf().tracks[0]) == originalTickZeroMeta);
    QVERIFY(widgets.model->tempoRowForExactTick(0) >= 0);

    changed.clear();
    document.undoStack()->undo();
    QTRY_COMPARE(changed.count(), 1);
    QCOMPARE(document.undoStack()->index(), initialIndex);
    QCOMPARE(document.undoStack()->count(), initialCount + 1);
    QVERIFY(checks::eventviews::rowForTickAndType(*widgets.model, conversionTick,
                                                  eventlist::TypeMeta) >= 0);
    QCOMPARE(widgets.model->tempoRowForExactTick(conversionTick), -1);

    changed.clear();
    document.undoStack()->redo();
    QTRY_COMPARE(changed.count(), 1);
    QCOMPARE(document.undoStack()->index(), initialIndex + 1);
    QCOMPARE(document.undoStack()->count(), initialCount + 1);
    QCOMPARE(widgets.model->tempoRowForExactTick(conversionTick) >= 0, true);
    QVERIFY(checks::eventviews::rowForTickAndType(*widgets.model, conversionTick,
                                                  eventlist::TypeMeta) < 0);

    changed.clear();
    const int tempoRow = widgets.model->tempoRowForExactTick(conversionTick);
    QVERIFY(tempoRow >= 0);
    QVERIFY(
        widgets.model->setData(widgets.model->index(tempoRow, eventlist::EventTableModel::ColType),
                               eventlist::TypeMeta, Qt::EditRole));
    QTRY_COMPARE(changed.count(), 1);
    QCOMPARE(document.undoStack()->index(), initialIndex + 2);
    QCOMPARE(document.undoStack()->count(), initialCount + 2);
    rawRow =
        checks::eventviews::rowForTickAndType(*widgets.model, conversionTick, eventlist::TypeMeta);
    QVERIFY(rawRow >= 0);
    QCOMPARE(widgets.model->tempoRowForExactTick(conversionTick), -1);
    QVERIFY(tickZeroMeta(document.smf().tracks[0]) == originalTickZeroMeta);
    QVERIFY(widgets.model->tempoRowForExactTick(0) >= 0);

    changed.clear();
    document.undoStack()->undo();
    QTRY_COMPARE(changed.count(), 1);
    QCOMPARE(document.undoStack()->index(), initialIndex + 1);
    QCOMPARE(document.undoStack()->count(), initialCount + 2);
    QCOMPARE(widgets.model->tempoRowForExactTick(conversionTick) >= 0, true);
    QVERIFY(checks::eventviews::rowForTickAndType(*widgets.model, conversionTick,
                                                  eventlist::TypeMeta) < 0);

    changed.clear();
    document.undoStack()->redo();
    QTRY_COMPARE(changed.count(), 1);
    QCOMPARE(document.undoStack()->index(), initialIndex + 2);
    QCOMPARE(document.undoStack()->count(), initialCount + 2);
    QVERIFY(checks::eventviews::rowForTickAndType(*widgets.model, conversionTick,
                                                  eventlist::TypeMeta) >= 0);
    QCOMPARE(widgets.model->tempoRowForExactTick(conversionTick), -1);
    QVERIFY(tickZeroMeta(document.smf().tracks[0]) == originalTickZeroMeta);
    QVERIFY(widgets.model->tempoRowForExactTick(0) >= 0);
}

void EventViewsEditsTest::insertCopy()
{
    const auto opened = checks::eventviews::openTabFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    SongDocument &document = opened.fixture->document();
    const int chunk = widgets.model->chunk();
    const SmfEvent source = document.smf().tracks[chunk].events.front();
    const int beforeMatches = countMatching(document.smf().tracks[chunk], source);
    const int beforeIndex = document.undoStack()->index();

    widgets.events->insertCopyOfRow(0);
    QTRY_COMPARE(countMatching(document.smf().tracks[chunk], source), beforeMatches + 1);
    QCOMPARE(document.undoStack()->index(), beforeIndex + 1);
    QVERIFY(checks::eventviews::trackIsSorted(document.smf().tracks[chunk]));
    document.undoStack()->undo();
    QTRY_COMPARE(countMatching(document.smf().tracks[chunk], source), beforeMatches);

    const int eotRow = widgets.model->rowCount() - 1;
    const int eotIndex = document.undoStack()->index();
    widgets.events->insertCopyOfRow(eotRow);
    QCoreApplication::processEvents();
    QCOMPARE(document.undoStack()->index(), eotIndex);
    QCOMPARE(countMatching(document.smf().tracks[chunk], source), beforeMatches);
}

void EventViewsEditsTest::sameTickReorder()
{
    const auto opened = checks::eventviews::openTabFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    SongDocument &document = opened.fixture->document();
    const int chunk = widgets.model->chunk();
    const uint64_t tick = document.smf().tracks[chunk].endTick + 100;
    const SmfEvent ccA = controlChange(tick, 7, 1);
    const SmfEvent ccB = controlChange(tick, 10, 2);
    SmfEvent noteOn;
    noteOn.tick = tick;
    noteOn.status = 0x90;
    noteOn.data0 = 60;
    noteOn.data1 = 90;
    document.insertRawEvent(chunk, ccA);
    document.insertRawEvent(chunk, ccB);
    document.insertRawEvent(chunk, noteOn);
    QCoreApplication::processEvents();

    const SmfTrack &beforeDrop = document.smf().tracks[chunk];
    const int first = indexOf(beforeDrop, ccA);
    const int second = indexOf(beforeDrop, ccB);
    const int note = indexOf(beforeDrop, noteOn);
    QVERIFY(first >= 0);
    QCOMPARE(second, first + 1);
    QCOMPARE(note, second + 1);
    std::unique_ptr<QMimeData> mime(widgets.model->mimeData({widgets.model->index(first, 0)}));
    QVERIFY(mime);
    QVERIFY(widgets.model->canDropMimeData(mime.get(), Qt::MoveAction, note, 0, QModelIndex()));
    QVERIFY(
        !widgets.model->canDropMimeData(mime.get(), Qt::MoveAction, note + 1, 0, QModelIndex()));
    QVERIFY(!widgets.model->canDropMimeData(mime.get(), Qt::MoveAction, 0, 0, QModelIndex()));
    QVERIFY(widgets.model->dropMimeData(mime.get(), Qt::MoveAction, note, 0, QModelIndex()));
    QTRY_COMPARE(indexOf(document.smf().tracks[chunk], ccB), first);
    QCOMPARE(indexOf(document.smf().tracks[chunk], ccA), second);
    QTRY_COMPARE(widgets.table->currentIndex().row(), second);

    checks::events::sendKey(*widgets.table, QEvent::KeyPress, Qt::Key_Up, Qt::AltModifier,
                            QString(), false, 1);
    QTRY_COMPARE(indexOf(document.smf().tracks[chunk], ccA), first);
    QCOMPARE(indexOf(document.smf().tracks[chunk], ccB), second);
    QTRY_COMPARE(widgets.table->currentIndex().row(), first);
    const int undoCount = document.undoStack()->count();
    checks::events::sendKey(*widgets.table, QEvent::KeyPress, Qt::Key_Up, Qt::AltModifier,
                            QString(), false, 1);
    QCOMPARE(document.undoStack()->count(), undoCount);
}

void EventViewsEditsTest::deleteMatrix()
{
    const auto opened = checks::eventviews::openTabFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    SongDocument &document = opened.fixture->document();
    const int chunk = widgets.model->chunk();
    const uint64_t tick = document.smf().tracks[chunk].endTick + 100;
    const SmfEvent firstEvent = controlChange(tick, 7, 11);
    const SmfEvent secondEvent = controlChange(tick, 10, 22);
    document.insertRawEvent(chunk, firstEvent);
    document.insertRawEvent(chunk, secondEvent);
    QCoreApplication::processEvents();
    const int first = indexOf(document.smf().tracks[chunk], firstEvent);
    const int second = indexOf(document.smf().tracks[chunk], secondEvent);
    QVERIFY(first >= 0);
    QVERIFY(second >= 0);

    QItemSelection selection;
    selection.select(widgets.model->index(first, 0),
                     widgets.model->index(first, widgets.model->columnCount() - 1));
    selection.select(widgets.model->index(second, 0),
                     widgets.model->index(second, widgets.model->columnCount() - 1));
    widgets.table->setCurrentIndex(widgets.model->index(second, 0));
    widgets.table->selectionModel()->select(selection, QItemSelectionModel::ClearAndSelect);
    checks::events::sendKey(*widgets.table, QEvent::KeyPress, Qt::Key_Delete, Qt::NoModifier,
                            QString(), false, 1);
    QTRY_COMPARE(countMatching(document.smf().tracks[chunk], firstEvent), 0);
    QCOMPARE(countMatching(document.smf().tracks[chunk], secondEvent), 0);
    QVERIFY(!widgets.table->selectionModel()->hasSelection());
    QVERIFY(!widgets.table->currentIndex().isValid());

    document.insertRawEvent(chunk, firstEvent);
    QCoreApplication::processEvents();
    const int single = indexOf(document.smf().tracks[chunk], firstEvent);
    QVERIFY(single >= 0);
    widgets.table->setCurrentIndex(widgets.model->index(single, 0));
    checks::events::sendKey(*widgets.table, QEvent::KeyPress, Qt::Key_Delete, Qt::NoModifier,
                            QString(), false, 1);
    QTRY_COMPARE(countMatching(document.smf().tracks[chunk], firstEvent), 0);
    QVERIFY(widgets.table->currentIndex().isValid());
}

int runEventViewsEditsCheck(const QStringList &qtArguments)
{
    EventViewsEditsTest test;
    QStringList arguments{QStringLiteral("eventviews-edits")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
