#include "checks/eventviews/eventview_fixture.h"
#include "checks/eventviews/tst_eventviews.h"

#include "ui/eventtabletypes.h"
#include "ui/songview.h"
#include <QComboBox>
#include <QCoreApplication>
#include <QtTest>

using checks::eventviews::EventWidgets;
using checks::eventviews::FixtureShape;

namespace {

bool signalsRespectRemapOrder(const QStringList &notifications, bool remaps)
{
    const int changed = notifications.indexOf(QStringLiteral("changed"));
    if (changed < 0)
        return false;
    const int remap = notifications.indexOf(QStringLiteral("remap"));
    return remaps ? remap >= 0 && remap < changed : remap < 0;
}

bool anchorMatches(const EventWidgets &widgets, const SongDocument &document, int expectedChunk)
{
    if (expectedChunk < 0)
        return widgets.chunkCombo->currentIndex() == -1 && widgets.model->rowCount() == 0;
    if (widgets.chunkCombo->currentData().toInt() != expectedChunk)
        return false;
    const int tempoRows = expectedChunk == 0 ? int(document.tempoPoints().size()) : 0;
    return widgets.model->rowCount() ==
           int(document.smf().tracks[expectedChunk].events.size()) + tempoRows + 1;
}

} // namespace

void EventViewsRemapTest::notifyOrder()
{
    const auto opened = checks::eventviews::openTabFixture(FixtureShape::Tempo);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    SongDocument &document = opened.fixture->document();
    opened.fixture->view().selectTrack(1);
    QTRY_COMPARE(widgets.chunkCombo->currentData().toInt(), document.smfTrackFor(1));

    QStringList notifications;
    connect(&document, &SongDocument::tracksRemapped, this, [&notifications](const TrackRemap &) {
        notifications.append(QStringLiteral("remap"));
    });
    connect(&document, &SongDocument::documentChanged, this,
            [&notifications] { notifications.append(QStringLiteral("changed")); });

    QVERIFY(document.moveTrack(1, 0));
    QTRY_VERIFY(signalsRespectRemapOrder(notifications, true));
    QTRY_VERIFY(anchorMatches(widgets, document, document.smfTrackFor(0)));
    notifications.clear();
    document.undoStack()->undo();
    QTRY_VERIFY(signalsRespectRemapOrder(notifications, true));
    QTRY_VERIFY(anchorMatches(widgets, document, document.smfTrackFor(1)));
    notifications.clear();
    document.undoStack()->redo();
    QTRY_VERIFY(signalsRespectRemapOrder(notifications, true));
    QTRY_VERIFY(anchorMatches(widgets, document, document.smfTrackFor(0)));
    document.undoStack()->undo();
    QTRY_VERIFY(anchorMatches(widgets, document, document.smfTrackFor(1)));

    notifications.clear();
    document.renameTrack(1, QStringLiteral("event view fixture rename"));
    QTRY_VERIFY(signalsRespectRemapOrder(notifications, false));
    QTRY_VERIFY(anchorMatches(widgets, document, document.smfTrackFor(1)));
    notifications.clear();
    document.undoStack()->undo();
    QTRY_VERIFY(signalsRespectRemapOrder(notifications, false));
    QTRY_VERIFY(anchorMatches(widgets, document, document.smfTrackFor(1)));
    notifications.clear();
    document.undoStack()->redo();
    QTRY_VERIFY(signalsRespectRemapOrder(notifications, false));
    QTRY_VERIFY(anchorMatches(widgets, document, document.smfTrackFor(1)));
    document.undoStack()->undo();

    QVERIFY(document.canAddTrack());
    notifications.clear();
    const int added = document.addTrack(0);
    QVERIFY(added >= 0);
    QTRY_VERIFY(signalsRespectRemapOrder(notifications, true));
    QTRY_VERIFY(anchorMatches(widgets, document, document.smfTrackFor(1)));
    notifications.clear();
    document.undoStack()->undo();
    QTRY_VERIFY(signalsRespectRemapOrder(notifications, true));
    QTRY_VERIFY(anchorMatches(widgets, document, document.smfTrackFor(1)));
    notifications.clear();
    document.undoStack()->redo();
    QTRY_VERIFY(signalsRespectRemapOrder(notifications, true));
    QTRY_VERIFY(anchorMatches(widgets, document, document.smfTrackFor(1)));
    document.undoStack()->undo();

    notifications.clear();
    const int duplicate = document.duplicateTrack(0);
    QVERIFY(duplicate >= 0);
    QTRY_VERIFY(signalsRespectRemapOrder(notifications, true));
    QTRY_VERIFY(anchorMatches(widgets, document, document.smfTrackFor(1)));
    notifications.clear();
    document.undoStack()->undo();
    QTRY_VERIFY(signalsRespectRemapOrder(notifications, true));
    QTRY_VERIFY(anchorMatches(widgets, document, document.smfTrackFor(1)));
    notifications.clear();
    document.undoStack()->redo();
    QTRY_VERIFY(signalsRespectRemapOrder(notifications, true));
    QTRY_VERIFY(anchorMatches(widgets, document, document.smfTrackFor(1)));
}

void EventViewsRemapTest::anchorFollowsMove()
{
    const auto opened = checks::eventviews::openTabFixture(FixtureShape::Tempo);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    SongDocument &document = opened.fixture->document();
    opened.fixture->view().selectTrack(1);
    QCoreApplication::processEvents();

    QVERIFY(document.moveTrack(1, 0));
    QTRY_COMPARE(widgets.chunkCombo->currentData().toInt(),
                 checks::eventviews::chunkForTrack(document, 0));
    document.undoStack()->undo();
    QTRY_COMPARE(widgets.chunkCombo->currentData().toInt(),
                 checks::eventviews::chunkForTrack(document, 1));
    document.undoStack()->redo();
    QTRY_COMPARE(widgets.chunkCombo->currentData().toInt(),
                 checks::eventviews::chunkForTrack(document, 0));
}

void EventViewsRemapTest::deletedChunkUnselects()
{
    const auto opened = checks::eventviews::openTabFixture(FixtureShape::Tempo);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    SongDocument &document = opened.fixture->document();
    opened.fixture->view().selectTrack(1);
    QCoreApplication::processEvents();
    const int removedChunk = widgets.chunkCombo->currentData().toInt();

    document.deleteTrack(1);
    QTRY_VERIFY(widgets.chunkCombo->findData(removedChunk) < 0);
    QVERIFY(anchorMatches(widgets, document, -1));
    document.undoStack()->undo();
    QTRY_VERIFY(widgets.chunkCombo->findData(removedChunk) >= 0);
    QVERIFY(anchorMatches(widgets, document, -1));
    document.undoStack()->redo();
    QTRY_VERIFY(widgets.chunkCombo->findData(removedChunk) < 0);
    QVERIFY(anchorMatches(widgets, document, -1));
}

void EventViewsRemapTest::metadataChunkTransition()
{
    const auto opened = checks::eventviews::openTabFixture(FixtureShape::Tempo);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    SongDocument &document = opened.fixture->document();
    constexpr int metadataChunk = 1;
    QVERIFY(checks::eventviews::selectChunk(*widgets.chunkCombo, metadataChunk));
    QTRY_COMPARE(widgets.model->chunk(), metadataChunk);

    int freeChannel = -1;
    for (int candidate = 0; candidate < 16 && freeChannel < 0; ++candidate) {
        bool used = false;
        for (int engine = 0; engine < document.engineTrackCount(); ++engine)
            used = used || document.channelFor(engine) == candidate;
        if (!used)
            freeChannel = candidate;
    }
    QVERIFY(freeChannel >= 0);
    SmfEvent program;
    program.status = uint8_t(0xc0 | freeChannel);
    program.data0 = 3;
    document.insertRawEvent(metadataChunk, program);
    QTRY_VERIFY(document.engineTrackCount() == 3);
    int owner = -1;
    for (int engine = 0; engine < document.engineTrackCount(); ++engine) {
        if (document.smfTrackFor(engine) == metadataChunk)
            owner = engine;
    }
    QVERIFY(owner >= 0);
    QVERIFY(checks::eventviews::rowForTickAndType(*widgets.model, 0, eventlist::TypeProgram) >= 0);

    document.undoStack()->undo();
    QTRY_COMPARE(document.engineTrackCount(), 2);
    document.undoStack()->redo();
    QTRY_COMPARE(document.engineTrackCount(), 3);
}

void EventViewsRemapTest::tempoProjectionRows()
{
    const auto opened = checks::eventviews::openTabFixture(FixtureShape::Tempo);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    QCOMPARE(widgets.model->tempoRowForExactTick(0), 0);
    opened.fixture->view().selectTrack(1);
    QTRY_COMPARE(widgets.model->tempoRowForExactTick(0), -1);
}

int runEventViewsRemapCheck(const QStringList &qtArguments)
{
    EventViewsRemapTest test;
    QStringList arguments{QStringLiteral("eventviews-remap")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
