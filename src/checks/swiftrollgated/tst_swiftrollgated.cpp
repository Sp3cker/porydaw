#include "tst_swiftrollgated.h"

#include "checks/selectionkey/session.h"
#include "core/songdocument.h"
#include "project/decompproject.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/workspaceui.h"

#include <QCoreApplication>
#include <QMouseEvent>
#include <QPoint>
#include <QQuickItem>
#include <QQuickWindow>
#include <QUndoStack>
#include <QWheelEvent>
#include <QtTest/QTest>

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
    QVERIFY(gridModel->property("readOnly").toBool());

    const int noteCount = overlay->property("noteCount").toInt();
    QVERIFY2(noteCount > 0, "Initial render must populate notes without requiring an edit");

    const int primaryTrack = view.selectionModel().primaryTrack();
    QCOMPARE(overlay->property("selectedTrack").toInt(), primaryTrack);
    QCOMPARE(noteCount, static_cast<int>(document.notesForTrack(primaryTrack).size()));

    const QString revText = overlay->property("appliedRevisionText").toString();
    QCOMPARE(revText, QString::number(document.revision()));

    QVERIFY(!overlay->hasActiveFocus());
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

void SwiftRollGatedTest::testPointerEditingBlockedWithoutFocusChange()
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

    auto *const swiftRollInput = overlay->findChild<QQuickItem *>(QStringLiteral("swiftRollInput"));
    QVERIFY(swiftRollInput != nullptr);

    const uint64_t beforeRev = document.revision();
    const auto beforeNotes = document.notesForTrack(0);

    const QPoint center(static_cast<int>(swiftRollInput->width() / 2),
                        static_cast<int>(swiftRollInput->height() / 2));
    const QPointF scenePos = swiftRollInput->mapToScene(QPointF(center));
    const QPoint globalPos = quickWin->mapToGlobal(scenePos.toPoint());

    QMouseEvent press(QEvent::MouseButtonPress, scenePos, globalPos, Qt::LeftButton, Qt::LeftButton,
                      Qt::NoModifier);
    QCoreApplication::sendEvent(quickWin, &press);

    QMouseEvent move(QEvent::MouseMove, scenePos + QPointF(50, 0), globalPos + QPoint(50, 0),
                     Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    QCoreApplication::sendEvent(quickWin, &move);

    QMouseEvent release(QEvent::MouseButtonRelease, scenePos + QPointF(50, 0),
                        globalPos + QPoint(50, 0), Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    QCoreApplication::sendEvent(quickWin, &release);
    selectionkey::settle();

    QCOMPARE(document.revision(), beforeRev);
    QCOMPARE(document.notesForTrack(0).size(), beforeNotes.size());

    QVERIFY(quickWin->activeFocusItem() != overlay);
    QVERIFY(quickWin->activeFocusItem() != swiftRollInput);
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
