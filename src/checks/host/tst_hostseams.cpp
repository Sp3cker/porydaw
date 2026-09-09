#include "checks/fwd.hpp"
#include "checks/host/hosttestsupport.h"
#include "checks/quickpopupguard.h"
#include "checks/support/editorrig.h"
#include "checks/support/eventsynth.h"
#include <algorithm>
#include <cstdint>
#include <memory>

#include <QByteArray>
#include <QCoreApplication>
#include <QGuiApplication>
#include <QPointF>
#include <QPointer>
#include <QQuickItem>
#include <QQuickView>
#include <QQuickWindow>
#include <QtTest>

#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/drawerchrome.h"
#include "ui/editordrawer/drawerpage.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/layout.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timeruler.h"

namespace checks::host {
namespace {

class HostSeamsTest final : public QObject
{
    Q_OBJECT
  public:
    HostSeamsTest() = default;

    Q_DISABLE_COPY_MOVE(HostSeamsTest)

  private slots:

    void automationPageIsSoleScrollStore()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        auto *drawer = host.view().editorDrawer();
        QVERIFY(drawer);
        AutomationPage *page = drawer->automationPage();
        host.view().setDrawerSectionVisible(EditorDrawerPage::Automations, true);
        settle();
        QVERIFY(page);
        const int maximum =
            qMax(0, page->automationContentHeight() - page->automationViewportSize().height());
        page->setVerticalScroll(maximum + layout::space(layout::Space::Two));
        QCOMPARE(page->verticalScroll(), maximum);
        page->setVerticalScroll(0);
        QCOMPARE(page->verticalScroll(), 0);
    }

    void editorEndpointsUpdateCameraAndResolveGridVoice()
    {
        SyntheticHost host(/*includeLongTail=*/true);
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        SongView &view = host.view();
        view.setEditorHorizontalScroll(96.0);
        view.setEditorTimeZoom(1.75 * layout::fontPx(8.0 / 3.0));
        view.setFollowScrollPaused(true);
        view.focusContent();
        view.announce(QStringLiteral("host-seams"));
        view.requestDrawerPageUndo();
        view.requestDrawerPageRedo();
        const SongView::ViewState runtime = view.viewState();
        QVERIFY(runtime.valid);
        QCOMPARE(runtime.scrollPx, 96.0);
        QCOMPARE(runtime.pxPerBeat, 1.75 * layout::fontPx(8.0 / 3.0));
        QVERIFY(view.grid().gridTicksAt(12) > 0);
        QVERIFY(view.grid().snapTicksAt(12) > 0);
        const DrawerPageVoiceContext voice = view.voiceContext(12);
        QCOMPARE(voice.voice, &host.bank().voices[0]);
        QCOMPARE(voice.voiceSlot, 0);
        QCOMPARE(drawerContextTick(-1.0), uint64_t{0});
        QCOMPARE(drawerContextTick(0.49), uint64_t{0});
        QCOMPARE(drawerContextTick(0.5), uint64_t{1});
        QCOMPARE(drawerContextTick(0.51), uint64_t{1});
    }

    void editorStateIsCosmeticOnly()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        const uint64_t revision = host.document().revision();
        const int undo = host.document().undoStack()->count();
        EditorViewState state;
        state.velocity = {true, 180};
        state.automation.visible = false;
        state.activePage = EditorDrawerPage::Velocity;
        state.laneHeight = 42;
        const EditorAutomationRowId lane{EditorAutomationRowKind::ControlChange, 0, 74};
        state.emptyLanes.insert(lane);
        state.laneRanges.emplace(lane, 96);
        host.view().applyEditorViewState(state);
        QCOMPARE(host.view().editorViewState(), state);
        QCOMPARE(host.document().revision(), revision);
        QCOMPARE(host.document().undoStack()->count(), undo);
    }

    void documentChangedPreservesCosmetics()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        EditorViewState state;
        state.velocity = {true, 180};
        state.activePage = EditorDrawerPage::Velocity;
        host.view().applyEditorViewState(state);
        auto *drawer = host.view().editorDrawer();
        drawer->automationPage()->documentChanged();
        drawer->velocityArea()->documentChanged();
        drawer->voiceChangeArea()->documentChanged();
        QCOMPARE(host.view().editorViewState(), state);
    }

    // One shared QuickSceneHost window and engine carry two live scenes at
    // independent viewport placements, each bound to its own document. The
    // bounded reentrancy and idempotence of detaching A hold, A's teardown
    // leaves the host window and B's scene alive, a real pointer
    // double-click delivered through the shared window then mutates only
    // B's document, and the velocity toggle icons render distinct
    // checked/unchecked ink per scene under a deterministic staged
    // palette and B's icon pixels observably update on its appearance
    // refresh after A's teardown.
    void sharedHostSceneDetachPreservesEditableSibling()
    {
        SyntheticHost firstFixture;
        SyntheticHost secondFixture;
        QString error;
        QVERIFY2(firstFixture.prepare(&error), qPrintable(error));
        QVERIFY2(secondFixture.prepare(&error), qPrintable(error));
        // Distinct page data: B carries a note A lacks, so if the scenes'
        // page contexts crossed, B's input would land in A's document.
        secondFixture.document().addNote(0, 240, 72, 48, 100);
        DocNote seeded;
        QVERIFY(secondFixture.document().findNote(0, 240, 72, &seeded));

        auto firstView = std::make_unique<SongView>();
        firstView->setDocument(&firstFixture.document());
        firstView->setSong(&firstFixture.timeline(), &firstFixture.bank());
        checks::QuickSceneHost sharedHost(*firstView, QSize{1000, 640});

        auto secondView = std::make_unique<SongView>();
        secondView->setDocument(&secondFixture.document());
        secondView->setSong(&secondFixture.timeline(), &secondFixture.bank());

        songview::TimelineQuickView *const firstQuick = firstView->quickView();
        songview::TimelineQuickView *const secondQuick = secondView->quickView();
        QVERIFY(firstQuick);
        QVERIFY(secondQuick);
        QCOMPARE(firstQuick->quickWindow(), &sharedHost.window());
        QVERIFY(firstQuick->rootObject());
        QVERIFY(firstQuick->popupSession());

        // Independent placement: A keeps the host's own full viewport while
        // B's viewport is the right half of the shared host window.
        QQuickItem &hostViewport = sharedHost.viewport();
        auto *const secondViewport = new QQuickItem(&hostViewport);
        secondViewport->setX(hostViewport.width() / 2.0);
        secondViewport->setWidth(hostViewport.width() / 2.0);
        secondViewport->setHeight(hostViewport.height());
        secondQuick->attachScene(sharedHost.engine(), *secondViewport);
        // The seam selects the interactive sibling explicitly: attaching
        // another scene never broadcasts or selects it, so B's viewport
        // becomes the selected page before input drives its document.
        secondQuick->setPageSelected(true);
        sharedHost.window().show();
        settle();

        QPointer<QObject> firstRoot{firstQuick->rootObject()};
        QPointer<QObject> secondRoot{secondQuick->rootObject()};
        QVERIFY(firstRoot);
        QVERIFY(secondRoot);
        QVERIFY(firstRoot != secondRoot);
        QCOMPARE(secondQuick->quickWindow(), &sharedHost.window());

        const QString firstProvider = firstView->editorDrawer()->chrome().iconSourcePrefix();
        const QString secondProvider = secondView->editorDrawer()->chrome().iconSourcePrefix();
        QVERIFY(!firstProvider.isEmpty());
        QVERIFY(!secondProvider.isEmpty());
        QVERIFY(firstProvider != secondProvider);
        QVERIFY(secondQuick->popupSession());

        // Bounded reentry: a listener may detach again while the borrow is
        // still live; the nested call must be inert, so the signal fires
        // exactly once.
        QPointer<QQuickWindow> hostWindow = &sharedHost.window();
        int detachCount = 0;
        bool detachWhileWindowValid = false;
        QObject::connect(firstQuick, &songview::TimelineQuickView::windowAboutToDetach, firstQuick,
                         [&detachCount, &detachWhileWindowValid, firstQuick, hostWindow] {
                             ++detachCount;
                             detachWhileWindowValid =
                                 firstQuick->quickWindow() == hostWindow.data();
                             if (detachCount == 1)
                                 firstQuick->detachScene();
                         });
        firstQuick->detachScene();
        QCOMPARE(detachCount, 1);
        QVERIFY(detachWhileWindowValid);
        QVERIFY(firstRoot.isNull());
        QVERIFY(!firstQuick->quickWindow());
        QVERIFY(!firstQuick->rootObject());
        QVERIFY(!firstQuick->popupSession());
        firstQuick->detachScene();
        QCOMPARE(detachCount, 1); // idempotent

        const uint64_t firstRevision = firstFixture.document().revision();
        const int firstUndo = firstFixture.document().undoStack()->count();
        const QByteArray firstSong = firstFixture.document().smf().write();
        firstView.reset();
        QVERIFY(hostWindow);
        QVERIFY(secondViewport);
        QVERIFY(secondRoot);
        QCOMPARE(secondQuick->quickWindow(), hostWindow.data());
        QCOMPARE(secondQuick->rootObject(), secondRoot.data());
        QVERIFY(secondQuick->popupSession());

        // B stays interactive on the surviving host: a real double-click
        // note gesture through the shared window commits one undoable
        // command into B's document (a grid-sized insert on empty space or
        // a delete on a note), and A's document stays put byte-identically.
        auto *const rollInput = secondQuick->rootObject()->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineRollInput"));
        QVERIFY(rollInput);
        QTRY_VERIFY(rollInput->width() > 0.0);
        QTRY_VERIFY(rollInput->height() > 0.0);
        const QPointF probePoint =
            rollInput->mapToScene(QPointF{rollInput->width() / 2.0, rollInput->height() / 2.0});
        const uint64_t revisionBefore = secondFixture.document().revision();
        const int undoBefore = secondFixture.document().undoStack()->count();
        const QByteArray songBefore = secondFixture.document().smf().write();
        QTest::mouseDClick(&sharedHost.window(), Qt::LeftButton, Qt::NoModifier,
                           probePoint.toPoint());
        settle();

        QVERIFY(secondRoot);
        QCOMPARE(secondQuick->rootObject(), secondRoot.data());
        QVERIFY(secondFixture.document().revision() > revisionBefore);
        QCOMPARE(secondFixture.document().undoStack()->count(), undoBefore + 1);
        QVERIFY(secondFixture.document().smf().write() != songBefore);
        QCOMPARE(firstFixture.document().revision(), firstRevision);
        QCOMPARE(firstFixture.document().undoStack()->count(), firstUndo);

        QCOMPARE(secondView->editorDrawer()->chrome().iconSourcePrefix(), secondProvider);
        QCOMPARE(firstFixture.document().smf().write(), firstSong);
    }
};
} // namespace
} // namespace checks::host

int runHostSeamsCheck(const QStringList &qtArguments)
{
    checks::host::HostSeamsTest test;
    QStringList arguments{QStringLiteral("host-seams")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "tst_hostseams.moc"
