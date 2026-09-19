#include "tst_swiftrollgated.h"

#include "checks/selectionkey/session.h"
#include "core/songdocument.h"
#include "project/decompproject.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/quick/swiftgrid/swift_roll_band.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/theme/themeruntime.h"
#include "ui/workspaceui.h"

#include <QColor>
#include <QCoreApplication>
#include <QMouseEvent>
#include <QPoint>
#include <QQuickItem>
#include <QQuickWindow>
#include <QUndoStack>
#include <QWheelEvent>
#include <QtTest/QTest>
#include <algorithm>

SwiftRollGatedTest::SwiftRollGatedTest(QString projectRoot, QString songA, QString songB)
    : m_projectRoot(std::move(projectRoot))
    , m_songA(std::move(songA))
    , m_songB(std::move(songB))
{}

void SwiftRollGatedTest::initTestCase()
{
    qputenv("PORYDAW_AUDIO_BACKEND", "null");
    qputenv("PORYDAW_SWIFT_ROLL", "1");
}

void SwiftRollGatedTest::cleanupTestCase()
{
    qunsetenv("PORYDAW_SWIFT_ROLL");
}

void SwiftRollGatedTest::testInitialRenderWithoutEdit()
{
    selectionkey::WindowSession session;
    QString error;
    QVERIFY2(selectionkey::openWindowSession(session, m_projectRoot, error), qUtf8Printable(error));

    SongTab *const tab = selectionkey::openSongTab(session, m_songA, false, error);
    QVERIFY2(tab != nullptr, qUtf8Printable(error));

    SongView &view = tab->view();
    const SongDocument &document = tab->document();

    songview::TimelineQuickView *const quickView = view.quickView();
    QVERIFY(quickView != nullptr);

    QQuickWindow *const quickWin = quickView->quickWindow();
    QVERIFY(quickWin != nullptr);

    auto *const overlay = quickWin->findChild<QQuickItem *>(QStringLiteral("swiftRollOverlay"));
    QVERIFY2(overlay != nullptr,
             "Swift roll overlay must be mounted when PORYDAW_SWIFT_ROLL is set");
    QVERIFY(overlay->isVisible());
    QVERIFY(overlay->width() > 0 && overlay->height() > 0);

    auto *const gridModel = quickWin->findChild<QObject *>(QStringLiteral("swiftGridModel"));
    QVERIFY2(gridModel != nullptr, "swiftGridModel must exist in overlay QML");
    // Wave 4: the mounted roll binds the writable seams, so readOnly clears
    // once editingBound flips; gestures commit through sgc_ intents.
    QVERIFY2(overlay->property("editingBound").toBool(),
             "mounted roll must bind the writable seams when PORYDAW_SWIFT_ROLL is set");
    QVERIFY(!gridModel->property("readOnly").toBool());

    const int noteCount = overlay->property("noteCount").toInt();
    QVERIFY2(noteCount > 0, "Initial render must populate notes without requiring an edit");

    const int primaryTrack = view.selectionModel().primaryTrack();
    QCOMPARE(overlay->property("selectedTrack").toInt(), primaryTrack);
    QCOMPARE(noteCount, static_cast<int>(document.notesForTrack(primaryTrack).size()));

    const QString revText = overlay->property("appliedRevisionText").toString();
    QCOMPARE(revText, QString::number(document.revision()));

    QVERIFY(!overlay->hasActiveFocus());

    auto *const viewport = overlay->findChild<QQuickItem *>(QStringLiteral("swiftRollViewport"));
    QVERIFY(viewport != nullptr);
    QVERIFY2(viewport->property("contentY").toReal() > 0.0,
             "Overlay must scroll to the note range, not the empty high keys");
    QCOMPARE(overlay->property("centeredOnNotes").toBool(), true);
    auto *const background =
        overlay->findChild<QQuickItem *>(QStringLiteral("swiftRollBackground"));
    QVERIFY(background != nullptr);
    QCOMPARE(background->property("color").value<QColor>(),
             themes::color(themes::Role::song_view_piano_roll_background));
}

void SwiftRollGatedTest::testTrackFollow()
{
    selectionkey::WindowSession session;
    QString error;
    QVERIFY2(selectionkey::openWindowSession(session, m_projectRoot, error), qUtf8Printable(error));

    SongTab *const tab = selectionkey::openSongTab(session, m_songA, false, error);
    QVERIFY2(tab != nullptr, qUtf8Printable(error));

    SongView &view = tab->view();
    const SongDocument &document = tab->document();

    QQuickWindow *const quickWin = view.quickView()->quickWindow();
    auto *const overlay = quickWin->findChild<QQuickItem *>(QStringLiteral("swiftRollOverlay"));
    QVERIFY(overlay != nullptr);

    const int track0Notes = static_cast<int>(document.notesForTrack(0).size());
    QCOMPARE(overlay->property("noteCount").toInt(), track0Notes);

    view.selectTrack(1);
    selectionkey::settle();

    QCOMPARE(overlay->property("selectedTrack").toInt(), 1);
    const int track1Notes = static_cast<int>(document.notesForTrack(1).size());
    QCOMPARE(overlay->property("noteCount").toInt(), track1Notes);

    view.selectTrack(0);
    selectionkey::settle();

    QCOMPARE(overlay->property("selectedTrack").toInt(), 0);
    QCOMPARE(overlay->property("noteCount").toInt(), track0Notes);
}

void SwiftRollGatedTest::testEditUndoRedoRefresh()
{
    selectionkey::WindowSession session;
    QString error;
    QVERIFY2(selectionkey::openWindowSession(session, m_projectRoot, error), qUtf8Printable(error));

    SongTab *const tab = selectionkey::openSongTab(session, m_songA, false, error);
    QVERIFY2(tab != nullptr, qUtf8Printable(error));

    SongView &view = tab->view();
    SongDocument &document = tab->document();

    QQuickWindow *const quickWin = view.quickView()->quickWindow();
    auto *const overlay = quickWin->findChild<QQuickItem *>(QStringLiteral("swiftRollOverlay"));
    QVERIFY(overlay != nullptr);

    const uint64_t baseRev = document.revision();
    const int baseCount = overlay->property("noteCount").toInt();

    document.addNote(0, 960, 60, 240, 100);
    selectionkey::settle();

    QVERIFY(document.revision() > baseRev);
    QCOMPARE(overlay->property("appliedRevisionText").toString(),
             QString::number(document.revision()));
    QCOMPARE(overlay->property("noteCount").toInt(), baseCount + 1);

    document.undoStack()->undo();
    selectionkey::settle();

    QCOMPARE(overlay->property("appliedRevisionText").toString(),
             QString::number(document.revision()));
    QCOMPARE(overlay->property("noteCount").toInt(), baseCount);

    document.undoStack()->redo();
    selectionkey::settle();

    QCOMPARE(overlay->property("appliedRevisionText").toString(),
             QString::number(document.revision()));
    QCOMPARE(overlay->property("noteCount").toInt(), baseCount + 1);

    document.undoStack()->undo();
    selectionkey::settle();

    QVERIFY(selectionkey::undoTabToClean(*session.workspace, document,
                                         QStringLiteral("cleaning edit test"), &error));
}
void SwiftRollGatedTest::testNon24AndSignatureGeometry()
{
    selectionkey::WindowSession session;
    QString error;
    QVERIFY2(selectionkey::openWindowSession(session, m_projectRoot, error), qUtf8Printable(error));

    SongTab *const tab = selectionkey::openSongTab(session, m_songA, false, error);
    QVERIFY2(tab != nullptr, qUtf8Printable(error));

    SongView &view = tab->view();
    SongDocument &document = tab->document();

    QQuickWindow *const quickWin = view.quickView()->quickWindow();
    QVERIFY(quickWin != nullptr);

    auto *const overlay = quickWin->findChild<QQuickItem *>(QStringLiteral("swiftRollOverlay"));
    auto *const gridModel = quickWin->findChild<QObject *>(QStringLiteral("swiftGridModel"));
    QVERIFY(overlay != nullptr && gridModel != nullptr);

    // 1. Initial timebase: verify document ticksPerBeat on the mounted surface
    const int initialTpb = static_cast<int>(document.smf().division);
    QCOMPARE(gridModel->property("ticksPerBeat").toInt(), initialTpb);

    // 2. Signature edits: add time signatures (e.g. 3/4 at tick 48, 7/8 at tick 192)
    const uint64_t revBeforeSig = document.revision();
    document.setTimeSig(48, 3, 2);
    selectionkey::settle();

    QVERIFY(document.revision() > revBeforeSig);
    QCOMPARE(overlay->property("appliedRevisionText").toString(),
             QString::number(document.revision()));

    document.setTimeSig(192, 7, 3);
    selectionkey::settle();

    QCOMPARE(overlay->property("appliedRevisionText").toString(),
             QString::number(document.revision()));

    // Undo signature mutations and verify overlay refresh
    document.undoStack()->undo();
    selectionkey::settle();
    QCOMPARE(overlay->property("appliedRevisionText").toString(),
             QString::number(document.revision()));

    document.undoStack()->undo();
    selectionkey::settle();
    QCOMPARE(overlay->property("appliedRevisionText").toString(),
             QString::number(document.revision()));

    // 3. Non-24 timebase and raw signature fields per Spec S3:
    SongInfo songInfo;
    songInfo.label = document.label();
    songInfo.cfg = document.cfg();
    songInfo.midPath = document.midPath();
    songInfo.hasCfg = true;

    SmfFile non24Smf = document.smf();
    non24Smf.division = 960;
    if (!non24Smf.tracks.empty()) {
        SmfEvent sig1;
        sig1.tick = 0;
        sig1.status = 0xff;
        sig1.metaType = 0x58;
        sig1.blob = QByteArray::fromHex("07031808");
        non24Smf.tracks[0].events.push_back(sig1);

        SmfEvent sig2;
        sig2.tick = 960;
        sig2.status = 0xff;
        sig2.metaType = 0x58;
        sig2.blob = QByteArray::fromHex("051f1808");
        non24Smf.tracks[0].events.push_back(sig2);

        SmfEvent sig3;
        sig3.tick = 1920;
        sig3.status = 0xff;
        sig3.metaType = 0x58;
        sig3.blob = QByteArray::fromHex("00ff1808");
        non24Smf.tracks[0].events.push_back(sig3);
    }

    QVERIFY(document.adoptSmf(std::move(non24Smf), songInfo, &error));
    selectionkey::settle();

    // Verify non-24 ticksPerBeat and revision on the mounted surface
    QCOMPARE(gridModel->property("ticksPerBeat").toInt(), 960);
    QCOMPARE(overlay->property("appliedRevisionText").toString(),
             QString::number(document.revision()));
    QVERIFY(overlay->isVisible());

    // Also verify 48 TPQN
    SmfFile smf48 = document.smf();
    smf48.division = 48;
    QVERIFY(document.adoptSmf(std::move(smf48), songInfo, &error));
    selectionkey::settle();

    QCOMPARE(gridModel->property("ticksPerBeat").toInt(), 48);
    QCOMPARE(overlay->property("appliedRevisionText").toString(),
             QString::number(document.revision()));

    // Clean teardown of this tab
    session.workspace->requestCloseSelectedTab();
    selectionkey::settle();
}

void SwiftRollGatedTest::testTwoDocumentsInterleaved()
{
    selectionkey::WindowSession session;
    QString error;
    QVERIFY2(selectionkey::openWindowSession(session, m_projectRoot, error), qUtf8Printable(error));

    SongTab *const tabA = selectionkey::openSongTab(session, m_songA, false, error);
    QVERIFY2(tabA != nullptr, qUtf8Printable(error));

    QQuickWindow *const quickWinA = tabA->view().quickView()->quickWindow();
    auto *const overlayA = quickWinA->findChild<QQuickItem *>(QStringLiteral("swiftRollOverlay"));
    auto *const modelA = quickWinA->findChild<QObject *>(QStringLiteral("swiftGridModel"));
    QVERIFY(overlayA != nullptr && modelA != nullptr);

    const QString tokenA = modelA->property("documentToken").toString();
    QVERIFY(!tokenA.isEmpty());

    SongTab *const tabB = selectionkey::openSongTab(session, m_songB, true, error);
    QVERIFY2(tabB != nullptr, qUtf8Printable(error));

    QQuickWindow *const quickWinB = tabB->view().quickView()->quickWindow();
    auto *const overlayB = quickWinB->findChild<QQuickItem *>(QStringLiteral("swiftRollOverlay"));
    auto *const modelB = quickWinB->findChild<QObject *>(QStringLiteral("swiftGridModel"));
    QVERIFY(overlayB != nullptr && modelB != nullptr);

    const QString tokenB = modelB->property("documentToken").toString();
    QVERIFY(!tokenB.isEmpty());
    QVERIFY2(tokenA != tokenB, "Each document feed must have a unique nonzero token");

    SongDocument &docA = tabA->document();
    SongDocument &docB = tabB->document();

    const uint64_t revABefore = docA.revision();
    const int countABefore = overlayA->property("noteCount").toInt();
    const int countBBefore = overlayB->property("noteCount").toInt();

    docB.addNote(0, 480, 62, 240, 90);
    selectionkey::settle();

    QCOMPARE(overlayB->property("appliedRevisionText").toString(),
             QString::number(docB.revision()));
    QCOMPARE(overlayB->property("noteCount").toInt(), countBBefore + 1);
    QCOMPARE(overlayA->property("appliedRevisionText").toString(), QString::number(revABefore));
    QCOMPARE(overlayA->property("noteCount").toInt(), countABefore);

    docA.addNote(0, 480, 64, 240, 90);
    selectionkey::settle();

    QCOMPARE(overlayA->property("appliedRevisionText").toString(),
             QString::number(docA.revision()));
    QCOMPARE(overlayA->property("noteCount").toInt(), countABefore + 1);

    docB.undoStack()->undo();
    docA.undoStack()->undo();
    selectionkey::settle();

    session.workspace->selectSongTab(tabB);
    session.workspace->requestCloseSelectedTab();
    selectionkey::settle();

    QCOMPARE(overlayA->property("appliedRevisionText").toString(),
             QString::number(docA.revision()));
    QCOMPARE(overlayA->property("noteCount").toInt(), countABefore);

    docA.addNote(0, 480, 65, 240, 90);
    selectionkey::settle();
    QCOMPARE(overlayA->property("noteCount").toInt(), countABefore + 1);

    docA.undoStack()->undo();
    selectionkey::settle();
    QVERIFY(selectionkey::undoTabToClean(*session.workspace, docA, QStringLiteral("cleaning tab A"),
                                         &error));
}

void SwiftRollGatedTest::testRemountFreshToken()
{
    selectionkey::WindowSession session;
    QString error;
    QVERIFY2(selectionkey::openWindowSession(session, m_projectRoot, error), qUtf8Printable(error));

    SongTab *tab = selectionkey::openSongTab(session, m_songA, false, error);
    QVERIFY2(tab != nullptr, qUtf8Printable(error));

    QQuickWindow *quickWin = tab->view().quickView()->quickWindow();
    auto *model1 = quickWin->findChild<QObject *>(QStringLiteral("swiftGridModel"));
    QVERIFY(model1 != nullptr);
    const QString token1 = model1->property("documentToken").toString();
    QVERIFY(!token1.isEmpty());

    session.workspace->requestCloseSelectedTab();
    selectionkey::settle();

    tab = selectionkey::openSongTab(session, m_songA, false, error);
    QVERIFY2(tab != nullptr, qUtf8Printable(error));

    quickWin = tab->view().quickView()->quickWindow();
    auto *model2 = quickWin->findChild<QObject *>(QStringLiteral("swiftGridModel"));
    QVERIFY(model2 != nullptr);
    const QString token2 = model2->property("documentToken").toString();
    QVERIFY(!token2.isEmpty());

    QVERIFY2(token1 != token2, "Reopening a song must mint a fresh document token");
}

void SwiftRollGatedTest::testBandEditWithoutFocusChange()
{
    selectionkey::WindowSession session;
    QString error;
    QVERIFY2(selectionkey::openWindowSession(session, m_projectRoot, error), qUtf8Printable(error));

    SongTab *const tab = selectionkey::openSongTab(session, m_songA, false, error);
    QVERIFY2(tab != nullptr, qUtf8Printable(error));

    SongView &view = tab->view();
    SongDocument &document = tab->document();
    QQuickWindow *const quickWin = view.quickView()->quickWindow();

    auto *const overlay = quickWin->findChild<QQuickItem *>(QStringLiteral("swiftRollOverlay"));
    QVERIFY(overlay != nullptr);

    auto *const swiftRollInput =
        quickWin->findChild<QQuickItem *>(QStringLiteral("timelineRollInput"));
    QVERIFY(swiftRollInput != nullptr);

    const uint64_t beforeRev = document.revision();
    const auto beforeNotes = document.notesForTrack(0);
    const int undoBase = document.undoStack()->count();
    const QPoint center(static_cast<int>(swiftRollInput->width() / 2),
                        static_cast<int>(swiftRollInput->height() / 2));
    const QPointF scenePos = swiftRollInput->mapToScene(QPointF(center));
    const QPoint globalPos = quickWin->mapToGlobal(scenePos.toPoint());
    // A full beat of drag guarantees a nonzero snapped delta whether the
    // press lands on a note (move) or empty space (draw).
    auto *const gridModel = quickWin->findChild<QObject *>(QStringLiteral("swiftGridModel"));
    QVERIFY(gridModel != nullptr);
    const int drag = qMax(50, qRound(gridModel->property("beatWidth").toDouble()));
    const QPointF movedPos = scenePos + QPointF(drag, 0);
    const QPoint globalMoved = quickWin->mapToGlobal(movedPos.toPoint());

    QMouseEvent press(QEvent::MouseButtonPress, scenePos, globalPos, Qt::LeftButton, Qt::LeftButton,
                      Qt::NoModifier);
    QCoreApplication::sendEvent(quickWin, &press);

    QMouseEvent move(QEvent::MouseMove, movedPos, globalMoved, Qt::LeftButton, Qt::LeftButton,
                     Qt::NoModifier);
    QCoreApplication::sendEvent(quickWin, &move);

    QMouseEvent release(QEvent::MouseButtonRelease, movedPos, globalMoved, Qt::LeftButton,
                        Qt::NoButton, Qt::NoModifier);
    QCoreApplication::sendEvent(quickWin, &release);
    selectionkey::settle();

    // With the writable seams bound the same gesture now commits through
    // the band as one intent = one undo entry; the overlay still never
    // takes focus.
    QCOMPARE(document.undoStack()->count(), undoBase + 1);
    QVERIFY(document.revision() > beforeRev);

    QVERIFY(quickWin->activeFocusItem() != overlay);
    QVERIFY(quickWin->activeFocusItem() != swiftRollInput);

    document.undoStack()->undo();
    selectionkey::settle();
    QCOMPARE(document.notesForTrack(0).size(), beforeNotes.size());
}

void SwiftRollGatedTest::testBandEditUndoRedoRerender()
{
    selectionkey::WindowSession session;
    QString error;
    QVERIFY2(selectionkey::openWindowSession(session, m_projectRoot, error), qUtf8Printable(error));

    SongTab *const tab = selectionkey::openSongTab(session, m_songA, false, error);
    QVERIFY2(tab != nullptr, qUtf8Printable(error));

    SongView &view = tab->view();
    SongDocument &document = tab->document();
    QQuickWindow *const quickWin = view.quickView()->quickWindow();

    auto *const overlay = quickWin->findChild<QQuickItem *>(QStringLiteral("swiftRollOverlay"));
    QVERIFY(overlay != nullptr);
    QVERIFY2(overlay->property("editingBound").toBool(),
             "mounted roll must bind the writable seams when PORYDAW_SWIFT_ROLL is set");
    auto *const gridModel = quickWin->findChild<QObject *>(QStringLiteral("swiftGridModel"));
    QVERIFY(gridModel != nullptr);
    QVERIFY(!gridModel->property("readOnly").toBool());

    // The band input item sits under the disabled overlay MouseArea; presses
    // reach it and forward through the sgb_ surface as tick/key facts.
    auto *const rollInput = quickWin->findChild<QQuickItem *>(QStringLiteral("timelineRollInput"));
    QVERIFY2(rollInput != nullptr, "roll band input item must exist under the overlay");

    const auto notes0 = document.notesForTrack(0);
    QVERIFY(!notes0.empty());
    const DocNote target = notes0.front();
    const int undoBase = document.undoStack()->count();
    const uint64_t revBase = document.revision();

    // Drain queued QtBridge metric notifications before sampling coordinates.
    // Settling after sampling can combine old row sizes with the new camera.
    selectionkey::settle();
    // Note center in content coordinates, then to the input item's scene.
    const double beatWidth = gridModel->property("beatWidth").toDouble();
    const double rowHeight = gridModel->property("rowHeight").toDouble();
    const double leadPad = gridModel->property("leadPadWidth").toDouble();
    const int ticksPerBeat = gridModel->property("ticksPerBeat").toInt();
    QVERIFY(beatWidth > 0 && rowHeight > 0 && ticksPerBeat > 0);
    auto *const surface = overlay->findChild<QQuickItem *>(QStringLiteral("pianoGridSurface"));
    QVERIFY(surface != nullptr);
    const auto contentPoint = [&](double tick, int key) {
        return QPointF(leadPad + tick * beatWidth / ticksPerBeat, (127.0 - key + 0.5) * rowHeight);
    };
    const QPointF centerScene =
        surface->mapToScene(contentPoint(target.tick + target.duration / 2, target.key));
    const QPointF movedScene = surface->mapToScene(
        contentPoint(target.tick + target.duration / 2 + ticksPerBeat, target.key));
    const QPoint globalCenter = quickWin->mapToGlobal(centerScene.toPoint());
    const QPoint globalMoved = quickWin->mapToGlobal(movedScene.toPoint());

    QMouseEvent press(QEvent::MouseButtonPress, centerScene, globalCenter, Qt::LeftButton,
                      Qt::LeftButton, Qt::NoModifier);
    QCoreApplication::sendEvent(quickWin, &press);
    QMouseEvent move(QEvent::MouseMove, movedScene, globalMoved, Qt::LeftButton, Qt::LeftButton,
                     Qt::NoModifier);
    QCoreApplication::sendEvent(quickWin, &move);
    // The live drag is a Swift-side preview: no document mutation yet.
    QCOMPARE(document.revision(), revBase);
    QMouseEvent release(QEvent::MouseButtonRelease, movedScene, globalMoved, Qt::LeftButton,
                        Qt::NoButton, Qt::NoModifier);
    QCoreApplication::sendEvent(quickWin, &release);
    const auto moved = document.notesForTrack(0);
    QCOMPARE(moved.size(), notes0.size());
    // One gesture = one intent = one undo entry (S-3).
    QCOMPARE(document.undoStack()->count(), undoBase + 1);
    QVERIFY(document.revision() > revBase);
    bool foundMoved = false;
    for (const DocNote &note : moved)
        if (note.noteId == target.noteId && note.tick != target.tick)
            foundMoved = true;
    QVERIFY2(foundMoved, "drag release did not move the note through an sgc_ intent");

    // sgd_ re-render: the overlay reflects the post-edit snapshot.
    // QtBridge queues property notifications; the document commit is
    // synchronous, but the QML binding observes it on the next event turn.
    selectionkey::settle();
    QCOMPARE(overlay->property("appliedRevisionText").toString(),
             QString::number(document.revision()));

    document.undoStack()->undo();
    selectionkey::settle();
    QCOMPARE(overlay->property("appliedRevisionText").toString(),
             QString::number(document.revision()));
    const auto undone = document.notesForTrack(0);
    bool foundRestored = false;
    for (const DocNote &note : undone)
        if (note.noteId == target.noteId && note.tick == target.tick)
            foundRestored = true;
    QVERIFY2(foundRestored, "production undo did not restore the moved note");

    document.undoStack()->redo();
    selectionkey::settle();
    QCOMPARE(overlay->property("appliedRevisionText").toString(),
             QString::number(document.revision()));
    QVERIFY(selectionkey::undoTabToClean(*session.workspace, document,
                                         QStringLiteral("cleaning band edit test"), &error));
}

void SwiftRollGatedTest::testEscapeMidDragZeroEffect()
{
    selectionkey::WindowSession session;
    QString error;
    QVERIFY2(selectionkey::openWindowSession(session, m_projectRoot, error), qUtf8Printable(error));

    SongTab *const tab = selectionkey::openSongTab(session, m_songA, false, error);
    QVERIFY2(tab != nullptr, qUtf8Printable(error));

    SongView &view = tab->view();
    SongDocument &document = tab->document();
    QQuickWindow *const quickWin = view.quickView()->quickWindow();

    auto *const overlay = quickWin->findChild<QQuickItem *>(QStringLiteral("swiftRollOverlay"));
    QVERIFY(overlay != nullptr);
    QVERIFY(overlay->property("editingBound").toBool());
    auto *const gridModel = quickWin->findChild<QObject *>(QStringLiteral("swiftGridModel"));
    QVERIFY(gridModel != nullptr);

    const auto notes0 = document.notesForTrack(0);
    QVERIFY(!notes0.empty());
    const DocNote target = notes0.front();
    const int undoBase = document.undoStack()->count();
    const uint64_t revBase = document.revision();

    const double beatWidth = gridModel->property("beatWidth").toDouble();
    const double rowHeight = gridModel->property("rowHeight").toDouble();
    const double leadPad = gridModel->property("leadPadWidth").toDouble();
    const int ticksPerBeat = gridModel->property("ticksPerBeat").toInt();
    auto *const surface = overlay->findChild<QQuickItem *>(QStringLiteral("pianoGridSurface"));
    QVERIFY(surface != nullptr);
    const QPointF centerScene = surface->mapToScene(
        QPointF(leadPad + (target.tick + target.duration / 2.0) * beatWidth / ticksPerBeat,
                (127.0 - target.key + 0.5) * rowHeight));
    const QPointF movedScene = centerScene + QPointF(beatWidth, 0);
    const QPoint globalCenter = quickWin->mapToGlobal(centerScene.toPoint());
    const QPoint globalMoved = quickWin->mapToGlobal(movedScene.toPoint());

    QMouseEvent press(QEvent::MouseButtonPress, centerScene, globalCenter, Qt::LeftButton,
                      Qt::LeftButton, Qt::NoModifier);
    QCoreApplication::sendEvent(quickWin, &press);
    QMouseEvent move(QEvent::MouseMove, movedScene, globalMoved, Qt::LeftButton, Qt::LeftButton,
                     Qt::NoModifier);
    QCoreApplication::sendEvent(quickWin, &move);

    // Escape mid-drag: the host arbiter cancels the gesture through the
    // band's cancel path — the preview drops with zero document effect.
    QTest::keyClick(quickWin, Qt::Key_Escape);
    selectionkey::settle();

    QCOMPARE(document.revision(), revBase);
    QCOMPARE(document.undoStack()->count(), undoBase);
    const auto after = document.notesForTrack(0);
    QCOMPARE(after.size(), notes0.size());
    bool unchanged = false;
    for (const DocNote &note : after)
        if (note.noteId == target.noteId && note.tick == target.tick && note.key == target.key &&
            note.duration == target.duration)
            unchanged = true;
    QVERIFY2(unchanged, "Escape mid-drag mutated the document");

    // The cancelled gesture released the band: a trailing release is a
    // no-op, not a commit.
    QMouseEvent release(QEvent::MouseButtonRelease, movedScene, globalMoved, Qt::LeftButton,
                        Qt::NoButton, Qt::NoModifier);
    QCoreApplication::sendEvent(quickWin, &release);
    selectionkey::settle();
    QCOMPARE(document.revision(), revBase);
    QCOMPARE(document.undoStack()->count(), undoBase);
}

// Spec §5 deviation (S-3): a leading resize shifts every selected note's
// start by +d and its duration by -d, which the frozen §2 vocabulary carries
// only as separate intents — two undo entries against one gesture = one
// entry. The editing lane declines a left-grip press instead: the real
// mounted band must open no gesture, cross no intent, and leave the undo
// stack, the document, and the host selection untouched.
void SwiftRollGatedTest::testBandLeadingGripDecline()
{
    selectionkey::WindowSession session;
    QString error;
    QVERIFY2(selectionkey::openWindowSession(session, m_projectRoot, error), qUtf8Printable(error));

    SongTab *const tab = selectionkey::openSongTab(session, m_songA, false, error);
    QVERIFY2(tab != nullptr, qUtf8Printable(error));

    SongView &view = tab->view();
    SongDocument &document = tab->document();
    QQuickWindow *const quickWin = view.quickView()->quickWindow();
    QVERIFY(quickWin != nullptr);

    auto *const overlay = quickWin->findChild<QQuickItem *>(QStringLiteral("swiftRollOverlay"));
    QVERIFY(overlay != nullptr);
    QVERIFY2(overlay->property("editingBound").toBool(),
             "mounted roll must bind the writable seams when PORYDAW_SWIFT_ROLL is set");
    auto *const gridModel = quickWin->findChild<QObject *>(QStringLiteral("swiftGridModel"));
    QVERIFY(gridModel != nullptr);
    QVERIFY(!gridModel->property("readOnly").toBool());
    songview::SwiftRollBand *const band = view.quickView()->swiftRollBand();
    QVERIFY2(band != nullptr, "the Swift roll band must be attached behind PORYDAW_SWIFT_ROLL");

    const auto notes0 = document.notesForTrack(0);
    QVERIFY(!notes0.empty());
    const DocNote target = notes0.front();
    const int undoBase = document.undoStack()->count();
    const uint64_t revBase = document.revision();

    // Drain queued QtBridge metric notifications before sampling coordinates.
    selectionkey::settle();
    const double beatWidth = gridModel->property("beatWidth").toDouble();
    const double rowHeight = gridModel->property("rowHeight").toDouble();
    const double leadPad = gridModel->property("leadPadWidth").toDouble();
    const int ticksPerBeat = gridModel->property("ticksPerBeat").toInt();
    QVERIFY(beatWidth > 0 && rowHeight > 0 && ticksPerBeat > 0);
    auto *const surface = overlay->findChild<QQuickItem *>(QStringLiteral("pianoGridSurface"));
    QVERIFY(surface != nullptr);
    const QPointF leftEdge = surface->mapToScene(QPointF(
        leadPad + target.tick * beatWidth / ticksPerBeat, (127.0 - target.key + 0.5) * rowHeight));
    const QPointF dragged = leftEdge + QPointF(beatWidth, 0.0);
    const auto sendMouse = [&](QEvent::Type type, const QPointF &scene) {
        const QPoint global = quickWin->mapToGlobal(scene.toPoint());
        QMouseEvent event(type, scene, global, Qt::LeftButton,
                          type == QEvent::MouseButtonRelease ? Qt::NoButton : Qt::LeftButton,
                          Qt::NoModifier);
        QCoreApplication::sendEvent(quickWin, &event);
    };

    // Positive control: the note body opens a move gesture and takes the host
    // selection at these coordinates, so the declined press below is the
    // grip's doing rather than a miss. A zero-delta release commits nothing.
    const QPointF body = surface->mapToScene(
        QPointF(leadPad + (target.tick + target.duration / 2.0) * beatWidth / ticksPerBeat,
                (127.0 - target.key + 0.5) * rowHeight));
    sendMouse(QEvent::MouseButtonPress, body);
    selectionkey::settle();
    QVERIFY2(band->gestureActive(), "the grip rows never reached the note body");
    QVERIFY2(view.selectionModel().isNoteSelected(target.noteId),
             "the grip rows never reached the note body (selection did not follow the press)");
    sendMouse(QEvent::MouseButtonRelease, body);
    selectionkey::settle();
    QCOMPARE(document.undoStack()->count(), undoBase);
    const auto selectionBefore = view.selectionModel().noteSelection();

    sendMouse(QEvent::MouseButtonPress, leftEdge);
    selectionkey::settle();

    QVERIFY2(!band->gestureActive(), "the declined leading grip opened a band gesture");
    QCOMPARE(document.undoStack()->count(), undoBase);
    QCOMPARE(document.revision(), revBase);
    const auto selectionUnchanged = [&] {
        const auto &now = view.selectionModel().noteSelection();
        return now.size() == selectionBefore.size() &&
               std::all_of(selectionBefore.begin(), selectionBefore.end(),
                           [&](NoteId id) { return view.selectionModel().isNoteSelected(id); });
    };
    QVERIFY2(selectionUnchanged(), "the declined leading grip changed the host note selection");

    // A drag and release after the declined press still lands nothing: no
    // gesture opened, so there is no commit to land.
    sendMouse(QEvent::MouseMove, dragged);
    sendMouse(QEvent::MouseButtonRelease, dragged);
    selectionkey::settle();

    QVERIFY2(!band->gestureActive(), "the declined leading grip left a live gesture");
    QCOMPARE(document.undoStack()->count(), undoBase);
    QCOMPARE(document.revision(), revBase);
    const auto after = document.notesForTrack(0);
    QCOMPARE(after.size(), notes0.size());
    bool unchanged = false;
    for (const DocNote &note : after)
        if (note.noteId == target.noteId && note.tick == target.tick && note.key == target.key &&
            note.duration == target.duration && note.velocity == target.velocity)
            unchanged = true;
    QVERIFY2(unchanged, "the declined leading grip mutated the document");
}

// The trailing grip is the resize the frozen §2 vocabulary lands atomically:
// press, Swift-side preview, and one SGC_NOTE_RESIZE_BATCH on release — one
// gesture = one undo entry (S-3), with the note's start preserved.
void SwiftRollGatedTest::testBandTrailingGripResizeCommitOnce()
{
    selectionkey::WindowSession session;
    QString error;
    QVERIFY2(selectionkey::openWindowSession(session, m_projectRoot, error), qUtf8Printable(error));

    SongTab *const tab = selectionkey::openSongTab(session, m_songA, false, error);
    QVERIFY2(tab != nullptr, qUtf8Printable(error));

    SongView &view = tab->view();
    SongDocument &document = tab->document();
    QQuickWindow *const quickWin = view.quickView()->quickWindow();
    QVERIFY(quickWin != nullptr);

    auto *const overlay = quickWin->findChild<QQuickItem *>(QStringLiteral("swiftRollOverlay"));
    QVERIFY(overlay != nullptr);
    QVERIFY(overlay->property("editingBound").toBool());
    auto *const gridModel = quickWin->findChild<QObject *>(QStringLiteral("swiftGridModel"));
    QVERIFY(gridModel != nullptr);
    QVERIFY(!gridModel->property("readOnly").toBool());
    songview::SwiftRollBand *const band = view.quickView()->swiftRollBand();
    QVERIFY2(band != nullptr, "the Swift roll band must be attached behind PORYDAW_SWIFT_ROLL");

    const auto notes0 = document.notesForTrack(0);
    QVERIFY(!notes0.empty());
    const DocNote target = notes0.front();
    const int undoBase = document.undoStack()->count();
    const uint64_t revBase = document.revision();

    // Drain queued QtBridge metric notifications before sampling coordinates.
    selectionkey::settle();
    const double beatWidth = gridModel->property("beatWidth").toDouble();
    const double rowHeight = gridModel->property("rowHeight").toDouble();
    const double leadPad = gridModel->property("leadPadWidth").toDouble();
    const int ticksPerBeat = gridModel->property("ticksPerBeat").toInt();
    const double baseFontPx = gridModel->property("baseFontPx").toDouble();
    QVERIFY(beatWidth > 0 && rowHeight > 0 && ticksPerBeat > 0 && baseFontPx > 0);
    auto *const surface = overlay->findChild<QQuickItem *>(QStringLiteral("pianoGridSurface"));
    QVERIFY(surface != nullptr);

    // Grip band arithmetic mirrors the grid's own metrics (GridMetrics:
    // edgeGripReach = 0.25 * baseFontPx, moveZoneMinWidth = 0.5 * baseFontPx,
    // innerReach = min(reach, (width - moveZoneMinWidth) / 2)). The press sits
    // inside the inner reach, and the guard keeps the pixel round-trip from
    // sampling the note body on a fixture note too narrow for a grip.
    const double pxPerTick = beatWidth / ticksPerBeat;
    const double gripReach = 0.25 * baseFontPx;
    const double noteWidth = target.duration * pxPerTick;
    const double gripInner =
        std::min(gripReach, std::max(0.0, (noteWidth - 0.5 * baseFontPx) / 2.0));
    QVERIFY2(gripInner >= 0.5, "fixture note is too narrow for a stable trailing-grip press");
    const QPointF rightEdge =
        surface->mapToScene(QPointF(leadPad + (target.tick + target.duration) * pxPerTick,
                                    (127.0 - target.key + 0.5) * rowHeight));
    const QPointF grip = rightEdge - QPointF(std::min(1.0, gripInner / 2.0), 0.0);
    const QPointF dragged = grip + QPointF(beatWidth, 0.0);
    const auto sendMouse = [&](QEvent::Type type, const QPointF &scene) {
        const QPoint global = quickWin->mapToGlobal(scene.toPoint());
        QMouseEvent event(type, scene, global, Qt::LeftButton,
                          type == QEvent::MouseButtonRelease ? Qt::NoButton : Qt::LeftButton,
                          Qt::NoModifier);
        QCoreApplication::sendEvent(quickWin, &event);
    };

    sendMouse(QEvent::MouseButtonPress, grip);
    selectionkey::settle();
    QVERIFY2(band->gestureActive(), "the trailing-grip press opened no band gesture");

    sendMouse(QEvent::MouseMove, dragged);
    selectionkey::settle();
    // The live resize is a Swift-side preview: the document mutates once, at
    // release.
    QCOMPARE(document.revision(), revBase);
    QCOMPARE(document.undoStack()->count(), undoBase);

    sendMouse(QEvent::MouseButtonRelease, dragged);
    selectionkey::settle();

    // One gesture = one intent = one undo entry (S-3): the single
    // SGC_NOTE_RESIZE_BATCH lands as exactly one production undo step, and it
    // resizes (start preserved, end grown) rather than moves.
    QCOMPARE(document.undoStack()->count(), undoBase + 1);
    QVERIFY(document.revision() > revBase);
    const auto resized = document.notesForTrack(0);
    QCOMPARE(resized.size(), notes0.size());
    const DocNote *after = nullptr;
    for (const DocNote &note : resized)
        if (note.noteId == target.noteId)
            after = &note;
    QVERIFY2(after != nullptr, "the resized note vanished from the document");
    QCOMPARE(after->tick, target.tick);
    QCOMPARE(after->key, target.key);
    QVERIFY2(after->duration > target.duration, "the resize batch did not extend the note");

    document.undoStack()->undo();
    selectionkey::settle();
    const auto restored = document.notesForTrack(0);
    bool foundRestored = false;
    for (const DocNote &note : restored)
        if (note.noteId == target.noteId && note.tick == target.tick &&
            note.duration == target.duration)
            foundRestored = true;
    QVERIFY2(foundRestored, "production undo did not restore the resized note");
    QVERIFY(selectionkey::undoTabToClean(*session.workspace, document,
                                         QStringLiteral("cleaning trailing grip test"), &error));
}

void SwiftRollGatedTest::testViewingInputLive()
{
    selectionkey::WindowSession session;
    QString error;
    QVERIFY2(selectionkey::openWindowSession(session, m_projectRoot, error), qUtf8Printable(error));

    SongTab *const tab = selectionkey::openSongTab(session, m_songA, false, error);
    QVERIFY2(tab != nullptr, qUtf8Printable(error));

    SongView &view = tab->view();
    QQuickWindow *const quickWin = view.quickView()->quickWindow();

    auto *const overlay = quickWin->findChild<QQuickItem *>(QStringLiteral("swiftRollOverlay"));
    QVERIFY(overlay != nullptr);

    auto *const swiftRollInput = overlay->findChild<QQuickItem *>(QStringLiteral("swiftRollInput"));
    auto *const swiftRollViewport =
        overlay->findChild<QQuickItem *>(QStringLiteral("swiftRollViewport"));
    QVERIFY(swiftRollInput != nullptr && swiftRollViewport != nullptr);

    const QPointF center(swiftRollViewport->width() / 2.0, swiftRollViewport->height() / 2.0);
    const QPointF scenePos = swiftRollViewport->mapToScene(center);
    const QPoint globalPos = quickWin->mapToGlobal(scenePos.toPoint());

    QWheelEvent wheel(scenePos, globalPos, QPoint{}, QPoint(0, -240), Qt::NoButton, Qt::NoModifier,
                      Qt::NoScrollPhase, false);
    QCoreApplication::sendEvent(quickWin, &wheel);
    selectionkey::settle();

    const qreal contentY = swiftRollViewport->property("contentY").toReal();
    QVERIFY2(contentY > 0.0, "Wheel viewing input must scroll the viewport");

    QMouseEvent hover(QEvent::MouseMove, scenePos, globalPos, Qt::NoButton, Qt::NoButton,
                      Qt::NoModifier);
    QCoreApplication::sendEvent(quickWin, &hover);
    selectionkey::settle();
}

void SwiftRollGatedTest::testTransferredWindowTeardown()
{
    selectionkey::WindowSession session;
    QString error;
    QVERIFY2(selectionkey::openWindowSession(session, m_projectRoot, error), qUtf8Printable(error));

    SongTab *const tab = selectionkey::openSongTab(session, m_songA, false, error);
    QVERIFY2(tab != nullptr, qUtf8Printable(error));

    session.window.reset();
    selectionkey::settle();
}

void SwiftRollGatedTest::testFlagOffAbsence()
{
    qunsetenv("PORYDAW_SWIFT_ROLL");

    selectionkey::WindowSession session;
    QString error;
    QVERIFY2(selectionkey::openWindowSession(session, m_projectRoot, error), qUtf8Printable(error));

    SongTab *const tab = selectionkey::openSongTab(session, m_songA, false, error);
    QVERIFY2(tab != nullptr, qUtf8Printable(error));

    SongView &view = tab->view();
    QQuickWindow *const quickWin = view.quickView()->quickWindow();
    QVERIFY(quickWin != nullptr);

    auto *const overlay = quickWin->findChild<QQuickItem *>(QStringLiteral("swiftRollOverlay"));
    QVERIFY2(overlay == nullptr,
             "Swift roll overlay must NOT be mounted when PORYDAW_SWIFT_ROLL is unset");
}

int runSwiftRollGatedCheck(const QString &projectRoot, const QString &songA, const QString &songB,
                           const QStringList &qtArguments)
{
    SwiftRollGatedTest test(projectRoot, songA, songB);
    QStringList arguments = {QStringLiteral("swiftrollgated")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
