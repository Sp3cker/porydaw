#include "checks/eventviews/eventview_fixture.h"
#include "checks/eventviews/tst_eventviews.h"

#include <QCoreApplication>
#include <QQuickItem>
#include <QQuickWindow>
#include <QtTest>

#include <algorithm>
#include <optional>

#include <vector>

#include "ui/eventtabletypes.h"
#include "ui/keymap.h"
#include "ui/songview.h"
#include "ui/songview/quick/eventlistcontroller.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"

using checks::eventviews::EventWidgets;
using checks::eventviews::FixtureShape;

namespace {

using eventlist::EventTableModel;

int indexOf(const SmfTrack &track, const SmfEvent &target)
{
    const auto found = std::find(track.events.begin(), track.events.end(), target);
    return found == track.events.end() ? -1 : int(found - track.events.begin());
}

int countMatching(const SmfTrack &track, const SmfEvent &target)
{
    return int(std::count(track.events.begin(), track.events.end(), target));
}

SmfEvent controlChange(Tick tick, uint8_t controller, uint8_t value)
{
    SmfEvent event;
    event.tick = tick;
    event.status = 0xb0;
    event.data0 = controller;
    event.data1 = value;
    return event;
}

// Real keyboard delivery: the editor holds active focus in the Quick window,
// so every digit travels the production key path into the TextInput.
void typeDigits(QQuickWindow &window, const QString &digits)
{
    for (const QChar digit : digits) {
        QVERIFY(digit.isDigit());
        QTest::keyClick(&window, Qt::Key(int(Qt::Key_0) + digit.digitValue()));
    }
    QCoreApplication::processEvents();
}

// Pointer row drag: press inside the row, move in steps so the page sees a
// real drag gesture, release over the drop row.
bool dragRow(const EventWidgets &widgets, int fromRow, int toRow)
{
    const QPointF from =
        checks::eventviews::cellSceneCenter(widgets, fromRow, EventTableModel::ColData);
    const QPointF to =
        checks::eventviews::cellSceneCenter(widgets, toRow, EventTableModel::ColData);
    if (from.isNull() || to.isNull())
        return false;
    QQuickWindow *const window = widgets.quickWindow;
    QTest::mousePress(window, Qt::LeftButton, Qt::NoModifier, from.toPoint());
    const int steps = 6;
    for (int step = 1; step <= steps; ++step) {
        const QPointF waypoint = from + (to - from) * (double(step) / steps);
        QTest::mouseMove(window, waypoint.toPoint());
        QCoreApplication::processEvents();
    }
    QTest::mouseRelease(window, Qt::LeftButton, Qt::NoModifier, to.toPoint());
    QCoreApplication::processEvents();
    return true;
}

std::optional<QKeyCombination> firstSingleBinding(const QString &command)
{
    const QList<QKeySequence> bindings = keymap::Registry::instance().bindings(command);
    if (bindings.isEmpty() || bindings.front().count() != 1)
        return std::nullopt;
    return bindings.front()[0];
}

int undoCount(SongDocument &document)
{
    return document.undoStack()->count();
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

    const Tick originalTick =
        Tick(widgets.model->data(widgets.model->index(row, EventTableModel::ColTick), Qt::EditRole)
                 .toULongLong());
    const Tick editedTick =
        opened.fixture->document().smf().tracks[widgets.model->chunk()].endTick + 3;
    const int beforeIndex = opened.fixture->document().undoStack()->index();
    QVERIFY(widgets.controller->commitCellEdit(row, EventTableModel::ColTick,
                                               QString::number(editedTick)));
    QTRY_VERIFY(checks::eventviews::rowForTickAndType(*widgets.model, editedTick,
                                                      eventlist::TypeNoteOn) >= 0);
    const int changedRow =
        checks::eventviews::rowForTickAndType(*widgets.model, editedTick, eventlist::TypeNoteOn);
    QCOMPARE(widgets.model
                 ->data(widgets.model->index(changedRow, EventTableModel::ColTick), Qt::EditRole)
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

    constexpr Tick tick = 3000000000ULL;
    const int chunk = widgets.model->chunk();
    const int beforeIndex = opened.fixture->document().undoStack()->index();
    QVERIFY(widgets.model->setData(widgets.model->index(row, EventTableModel::ColTick),
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

// kMaxTick is the largest tick the document accepts; kNoTick is the reserved
// absent-loop sentinel and must be refused. The commit is isolated on
// purpose: one raw event on the small Basic fixture, asserted at the
// document, then undone — no dense rendering or playback.
void EventViewsEditsTest::tickHighBitExact()
{
    const auto opened = checks::eventviews::openTabFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    const int row =
        checks::eventviews::rowForTickAndType(*widgets.model, 12, eventlist::TypeNoteOn);
    QVERIFY(row >= 0);

    const int chunk = widgets.model->chunk();
    const int beforeIndex = opened.fixture->document().undoStack()->index();
    QVERIFY(!widgets.model->setData(widgets.model->index(row, EventTableModel::ColTick),
                                    QString::number(CoreTimeDefaults::kNoTick), Qt::EditRole));
    QCoreApplication::processEvents();
    QCOMPARE(opened.fixture->document().undoStack()->index(), beforeIndex);

    QVERIFY(widgets.model->setData(widgets.model->index(row, EventTableModel::ColTick),
                                   QString::number(CoreTimeDefaults::kMaxTick), Qt::EditRole));
    QTRY_COMPARE(opened.fixture->document().undoStack()->index(), beforeIndex + 1);
    const SmfTrack &track = opened.fixture->document().smf().tracks[chunk];
    QVERIFY(!track.events.empty());
    QCOMPARE(track.events.back().tick, CoreTimeDefaults::kMaxTick);
    QVERIFY(checks::eventviews::trackIsSorted(track));

    opened.fixture->document().undoStack()->undo();
    QTRY_VERIFY(checks::eventviews::rowForTickAndType(*widgets.model, 12, eventlist::TypeNoteOn) >=
                0);
}

// Same boundary through the rendered Tick TextInput: the proof that the page
// hands the editor's QString straight to the model instead of a JS Number.
void EventViewsEditsTest::tickHighBitThroughEditor()
{
    const auto opened = checks::eventviews::openTabFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    const int row =
        checks::eventviews::rowForTickAndType(*widgets.model, 12, eventlist::TypeNoteOn);
    QVERIFY(row >= 0);
    const int chunk = widgets.model->chunk();

    QQuickItem *editor = nullptr;
    QVERIFY(checks::eventviews::openCellEditor(widgets, row, EventTableModel::ColTick,
                                               QStringLiteral("eventListTickEditor"), &editor));
    QVERIFY(QMetaObject::invokeMethod(editor, "selectAll"));
    typeDigits(*widgets.quickWindow, QStringLiteral("4294967294"));
    QTest::keyClick(widgets.quickWindow, Qt::Key_Return);
    QCoreApplication::processEvents();

    QTRY_COMPARE(opened.fixture->document().smf().tracks[chunk].events.back().tick,
                 CoreTimeDefaults::kMaxTick);
    const SmfTrack &track = opened.fixture->document().smf().tracks[chunk];
    QVERIFY(!track.events.empty());
    QCOMPARE(track.events.back().tick, CoreTimeDefaults::kMaxTick);

    const int movedRow = checks::eventviews::rowForTickAndType(
        *widgets.model, CoreTimeDefaults::kMaxTick, eventlist::TypeNoteOn);
    QVERIFY(movedRow >= 0);
    QCOMPARE(widgets.model
                 ->data(widgets.model->index(movedRow, EventTableModel::ColTick),
                        EventTableModel::EventRoles::TickStringRole)
                 .toString(),
             QStringLiteral("4294967294"));
    QVERIFY(checks::eventviews::trackIsSorted(track));

    opened.fixture->document().undoStack()->undo();
    QTRY_VERIFY(checks::eventviews::rowForTickAndType(*widgets.model, 12, eventlist::TypeNoteOn) >=
                0);
}

void EventViewsEditsTest::channelAndDataConversions()
{
    const auto opened = checks::eventviews::openTabFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    SongDocument &document = opened.fixture->document();
    const int row =
        checks::eventviews::rowForTickAndType(*widgets.model, 12, eventlist::TypeNoteOn);
    QVERIFY(row >= 0);
    const int chunk = widgets.model->chunk();
    const int beforeIndex = document.undoStack()->index();

    // Channel: the value is 1..16, stored as the status nibble.
    QVERIFY(
        widgets.controller->commitCellEdit(row, EventTableModel::ColChannel, QStringLiteral("5")));
    QTRY_COMPARE(document.undoStack()->index(), beforeIndex + 1);
    int eventIndex = -1;
    const SmfTrack &moved = document.smf().tracks[chunk];
    for (int index = 0; index < int(moved.events.size()); ++index) {
        if (moved.events[index].tick == 12 && moved.events[index].isNoteOn()) {
            eventIndex = index;
            break;
        }
    }
    QVERIFY(eventIndex >= 0);
    QCOMPARE(moved.events[eventIndex].status & 0x0f, 0x04);

    // Data bytes.
    QVERIFY(
        widgets.controller->commitCellEdit(row, EventTableModel::ColData1, QStringLiteral("100")));
    QVERIFY(
        widgets.controller->commitCellEdit(row, EventTableModel::ColData2, QStringLiteral("33")));
    QTRY_COMPARE(document.undoStack()->index(), beforeIndex + 3);
    QCOMPARE(document.smf().tracks[chunk].events[eventIndex].data0, 100);
    QCOMPARE(document.smf().tracks[chunk].events[eventIndex].data1, 33);

    // Blob editing belongs to meta/SysEx rows, not channel events.
    const int blobRow =
        checks::eventviews::rowForTickAndType(*widgets.model, 0, eventlist::TypeMeta);
    QVERIFY(blobRow >= 0);
    const auto blobEventIndex = widgets.model->rawEventIndexForRow(blobRow);
    QVERIFY(blobEventIndex.has_value());
    QVERIFY(widgets.controller->commitCellEdit(blobRow, EventTableModel::ColData,
                                               QStringLiteral("\"room\"")));
    QTRY_COMPARE(document.undoStack()->index(), beforeIndex + 4);
    QCOMPARE(document.smf().tracks[chunk].events[*blobEventIndex].blob, QByteArrayLiteral("room"));

    while (document.undoStack()->index() > beforeIndex)
        document.undoStack()->undo();
    QTRY_VERIFY(checks::eventviews::rowForTickAndType(*widgets.model, 12, eventlist::TypeNoteOn) >=
                0);
    QCOMPARE(document.smf().tracks[chunk].events[eventIndex].status & 0x0f, 0x00);
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
        conversionTick = std::max(conversionTick, uint64_t(event.tick));
    for (const TempoPoint &point : document.tempoPoints())
        conversionTick = std::max(conversionTick, uint64_t(point.tick));
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

    QVERIFY(widgets.model->setData(widgets.model->index(rawRow, EventTableModel::ColType),
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
    QVERIFY(widgets.model->setData(widgets.model->index(tempoRow, EventTableModel::ColType),
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

    widgets.controller->insertCopyOfRow(0);
    QTRY_COMPARE(countMatching(document.smf().tracks[chunk], source), beforeMatches + 1);
    QCOMPARE(document.undoStack()->index(), beforeIndex + 1);
    QVERIFY(checks::eventviews::trackIsSorted(document.smf().tracks[chunk]));
    document.undoStack()->undo();
    QTRY_COMPARE(countMatching(document.smf().tracks[chunk], source), beforeMatches);

    const int eotRow = widgets.model->rowCount() - 1;
    const int eotIndex = document.undoStack()->index();
    widgets.controller->insertCopyOfRow(eotRow);
    QCoreApplication::processEvents();
    QCOMPARE(document.undoStack()->index(), eotIndex);
    QCOMPARE(countMatching(document.smf().tracks[chunk], source), beforeMatches);
}

// The reorder contract survives only if a real pointer drag moves a row
// inside the same-tick run — the page must translate the gesture into one
// document reorder, and refuse drops outside the legal range.
void EventViewsEditsTest::sameTickReorder()
{
    const auto opened = checks::eventviews::openTabFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    SongDocument &document = opened.fixture->document();
    const int chunk = widgets.model->chunk();
    const Tick tick = document.smf().tracks[chunk].endTick + 100;
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

    // Drag the first CC onto the note row: the page turns the pointer gap
    // into reorderRows(first, note), swapping the first two events.
    QVERIFY(dragRow(widgets, first, note));
    QTRY_COMPARE(indexOf(document.smf().tracks[chunk], ccB), first);
    QCOMPARE(indexOf(document.smf().tracks[chunk], ccA), second);
    QTRY_COMPARE(widgets.controller->currentRow(), second);

    // A drop before the run start is illegal and must not push undo. The
    // dragged row is the current row here: the page must consume the release
    // without falling through to click-to-edit.
    const int orderAfterDrop = undoCount(document);
    QVERIFY(dragRow(widgets, second, 0));
    QCoreApplication::processEvents();
    QCOMPARE(indexOf(document.smf().tracks[chunk], ccA), second);
    QCOMPARE(undoCount(document), orderAfterDrop);
    QVERIFY(!widgets.controller->isEditing());

    // A cross-tick drop target is illegal: the drop gap must stay inside the
    // dragged row's own same-tick run.
    const int crossTarget =
        checks::eventviews::rowForTickAndType(*widgets.model, 12, eventlist::TypeNoteOn);
    QVERIFY(crossTarget >= 0);
    QVERIFY(dragRow(widgets, note, crossTarget));
    QCoreApplication::processEvents();
    QCOMPARE(indexOf(document.smf().tracks[chunk], noteOn), note);
    QCOMPARE(undoCount(document), orderAfterDrop);
    QVERIFY(!widgets.controller->isEditing());

    // Canonical same-tick ordering pins a note-end ahead of its note-on.
    // Dragging the end after the on must remain a no-op.
    const Tick pinnedTick = document.smf().tracks[chunk].endTick + 200;
    SmfEvent pinnedOn;
    pinnedOn.tick = pinnedTick;
    pinnedOn.status = 0x90;
    pinnedOn.data0 = 61;
    pinnedOn.data1 = 88;
    SmfEvent pinnedOff;
    pinnedOff.tick = pinnedTick;
    pinnedOff.status = 0x80;
    pinnedOff.data0 = 61;
    document.insertRawEvent(chunk, pinnedOn);
    document.insertRawEvent(chunk, pinnedOff);
    QCoreApplication::processEvents();
    const int onRow =
        checks::eventviews::rowForTickAndType(*widgets.model, pinnedTick, eventlist::TypeNoteOn);
    const int offRow =
        checks::eventviews::rowForTickAndType(*widgets.model, pinnedTick, eventlist::TypeNoteOff);
    QVERIFY(offRow >= 0);
    QCOMPARE(onRow, offRow + 1);
    const int orderBeforePin = undoCount(document);
    QVERIFY(dragRow(widgets, offRow, onRow));
    QCoreApplication::processEvents();
    QCOMPARE(indexOf(document.smf().tracks[chunk], pinnedOff), offRow);
    QCOMPARE(indexOf(document.smf().tracks[chunk], pinnedOn), onRow);
    QCOMPARE(undoCount(document), orderBeforePin);
    QVERIFY(!widgets.controller->isEditing());

    // The registered move key at the run boundary is a no-op.
    QVERIFY(opened.fixture->view().quickView() != nullptr);
    opened.fixture->view().quickView()->focusEventListInput(Qt::OtherFocusReason);
    widgets.controller->selectRow(first, Qt::NoModifier);
    QCoreApplication::processEvents();
    const int orderBeforeBoundaryMove = undoCount(document);
    const auto moveUp = firstSingleBinding(QStringLiteral("eventlist.move_up"));
    if (moveUp.has_value()) {
        QTest::keyClick(widgets.quickWindow, moveUp->key(), moveUp->keyboardModifiers());
        QCoreApplication::processEvents();
        QCOMPARE(indexOf(document.smf().tracks[chunk], ccA), second);
        QCOMPARE(undoCount(document), orderBeforeBoundaryMove);
    }
}

void EventViewsEditsTest::deleteMatrix()
{
    const auto opened = checks::eventviews::openTabFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    SongDocument &document = opened.fixture->document();
    const int chunk = widgets.model->chunk();
    const Tick tick = document.smf().tracks[chunk].endTick + 100;
    const SmfEvent firstEvent = controlChange(tick, 7, 11);
    const SmfEvent secondEvent = controlChange(tick, 10, 22);
    document.insertRawEvent(chunk, firstEvent);
    document.insertRawEvent(chunk, secondEvent);
    QCoreApplication::processEvents();
    const int first = indexOf(document.smf().tracks[chunk], firstEvent);
    const int second = indexOf(document.smf().tracks[chunk], secondEvent);
    QVERIFY(first >= 0);
    QVERIFY(second >= 0);

    QVERIFY(opened.fixture->view().quickView() != nullptr);
    opened.fixture->view().quickView()->focusEventListInput(Qt::OtherFocusReason);
    widgets.controller->selectRow(first, Qt::NoModifier);
    widgets.controller->selectRow(second, Qt::ControlModifier);
    QTRY_VERIFY(widgets.controller->selectedRows().contains(first));
    QTRY_VERIFY(widgets.controller->selectedRows().contains(second));
    QTest::keyClick(widgets.quickWindow, Qt::Key_Delete);
    QCoreApplication::processEvents();
    QTRY_COMPARE(countMatching(document.smf().tracks[chunk], firstEvent), 0);
    QCOMPARE(countMatching(document.smf().tracks[chunk], secondEvent), 0);
    QTRY_VERIFY(widgets.controller->selectedRows().isEmpty());
    QCOMPARE(widgets.controller->currentRow(), -1);

    document.insertRawEvent(chunk, firstEvent);
    QCoreApplication::processEvents();
    const int single = indexOf(document.smf().tracks[chunk], firstEvent);
    QVERIFY(single >= 0);
    widgets.controller->selectRow(single, Qt::NoModifier);
    QCoreApplication::processEvents();
    QTest::keyClick(widgets.quickWindow, Qt::Key_Delete);
    QCoreApplication::processEvents();
    QTRY_COMPARE(countMatching(document.smf().tracks[chunk], firstEvent), 0);
    const int currentRow = widgets.controller->currentRow();
    QVERIFY(currentRow >= 0 && currentRow < widgets.model->rowCount());
}

// Editing then clicking a sibling drawer: the focus-loss commit must land
// without the page reclaiming focus, and Delete at drawer focus belongs to
// the drawer — never to the event rows.
void EventViewsEditsTest::drawerClickAfterEditOwnsDelete()
{
    const auto opened = checks::eventviews::openTabFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    const int row =
        checks::eventviews::rowForTickAndType(*widgets.model, 12, eventlist::TypeNoteOn);
    QVERIFY(row >= 0);
    const int chunk = widgets.model->chunk();

    QQuickItem *editor = nullptr;
    QVERIFY(checks::eventviews::openCellEditor(widgets, row, EventTableModel::ColTick,
                                               QStringLiteral("eventListTickEditor"), &editor));
    QVERIFY(QMetaObject::invokeMethod(editor, "selectAll"));
    typeDigits(*widgets.quickWindow, QStringLiteral("15"));
    const int undoBefore = opened.fixture->document().undoStack()->index();

    auto *drawer = widgets.quickWindow->findChild<songview::TimelineInputItem *>(
        QStringLiteral("drawerBarInput"));
    QVERIFY(drawer);
    QVERIFY(checks::eventviews::focusSurface(widgets, *drawer));

    QTRY_VERIFY(checks::eventviews::rowForTickAndType(*widgets.model, 15, eventlist::TypeNoteOn) >=
                0);
    QCOMPARE(opened.fixture->document().undoStack()->index(), undoBefore + 1);
    QVERIFY(!widgets.controller->isEditing());
    QVERIFY(drawer->hasActiveFocus());

    // Delete at drawer focus must not consume the event rows.
    const int rowsBefore = widgets.model->rowCount();
    const int undoBeforeDelete = opened.fixture->document().undoStack()->index();
    QTest::keyClick(widgets.quickWindow, Qt::Key_Delete);
    QCoreApplication::processEvents();
    QCOMPARE(widgets.model->rowCount(), rowsBefore);
    QCOMPARE(opened.fixture->document().undoStack()->index(), undoBeforeDelete);
    QVERIFY(drawer->hasActiveFocus());
}

int runEventViewsEditsCheck(const QStringList &qtArguments)
{
    EventViewsEditsTest test;
    QStringList arguments{QStringLiteral("eventviews-edits")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
