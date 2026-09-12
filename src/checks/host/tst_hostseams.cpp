#include "checks/fwd.hpp"
#include "checks/host/hosttestsupport.h"
#include "checks/support/support.h"
#include "checks/support/timelinequickcheck.h"
#include <memory>

#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QWidget>
#include <QtTest>

#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/drawerchrome.h"
#include "ui/editordrawer/drawerpage.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/layout.h"
#include "ui/songtabquickhost.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickview.h"

namespace checks::host {
namespace {

class HostSeamsTest final : public QObject
{
    Q_OBJECT
  public:
    HostSeamsTest() = default;

    Q_DISABLE_COPY_MOVE(HostSeamsTest)

  private slots:

    void automationPlotFillsHostViewport()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        auto *drawer = host.view().editorDrawer();
        QVERIFY(drawer);
        AutomationPage *page = drawer->automationPage();
        host.view().setDrawerSectionVisible(EditorDrawerPage::Automations, true);
        host.view().setDrawerSectionHeight(EditorDrawerPage::Automations, 180);
        settle();
        QVERIFY(page);
        auto *canvas = page->canvas();
        QVERIFY(canvas);
        const int tempoIndex = checks::support::automationParameterIndex(
            *canvas, {EditorAutomationRowKind::Tempo, 0, 0});
        QVERIFY(tempoIndex >= 0);
        canvas->activateParameter(tempoIndex);
        settle();
        const auto geometry =
            host.view().timelineBandLayout().geometry(songview::TimelineBand::Automation);
        QVERIFY(geometry.has_value());
        QCOMPARE(geometry->plotRect.x(), host.view().timelineSplitX());
        QCOMPARE(page->automationViewportSize(), geometry->plotRect.size());
        QVERIFY(!page->automationViewportSize().isEmpty());
        QCOMPARE(canvas->laneBody(LaneHandle{0}), QRect(QPoint{}, page->automationViewportSize()));
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

    // One-way embedding handoff: the host adapter takes the window exactly
    // once without detaching; an explicit detach while hosted only unbinds
    // (the transferred window stays alive under its container); destroying
    // the host destroys the container and the window while the coordinator
    // is still alive; the coordinator is destroyed last.
    void embeddedWindowOwnershipTransfersToTheContainer()
    {
        QPointer<QQuickWindow> window;
        QPointer<QQuickItem> root;
        QPointer<QWidget> container;
        int detachCount = 0;
        bool detachWhileWindowValid = false;
        {
            auto view = std::make_unique<SongView>();
            checks::support::bindEditActionsForTest(*view);
            songview::TimelineQuickView *const quick = view->quickView();
            QVERIFY(quick);
            window = quick->quickWindow();
            QVERIFY(window);
            root = quick->rootObject();
            QVERIFY(root);
            // Bounded reentry: a listener may detach again while the borrow is
            // still live; the nested call must be inert, so the signal fires
            // exactly once. The detachCount == 1 bound also keeps a pre-fix
            // coordinator to one nested emission, never unbounded recursion.
            QObject::connect(quick, &songview::TimelineQuickView::windowAboutToDetach, quick,
                             [&detachCount, &detachWhileWindowValid, quick] {
                                 ++detachCount;
                                 detachWhileWindowValid = quick->quickWindow() != nullptr;
                                 if (detachCount == 1)
                                     quick->detachWindow();
                             });
            {
                QWidget owner;
                const SongTabQuickHost adapter(*quick, owner);
                container = adapter.container();
                QVERIFY(container);
                QVERIFY(!quick->takeWindowForEmbedding()); // exactly-once, one-way
                QCOMPARE(detachCount, 0);                  // the take never detaches
                QVERIFY(quick->quickWindow() == window);   // identity survives the take

                quick->detachWindow(); // hosted detach: unbind only, transfer stands
                QCOMPARE(detachCount, 1);
                QVERIFY(detachWhileWindowValid); // emitted while the window was usable
                QVERIFY(window);                 // transferred window survives the unbind
                QVERIFY(!quick->quickWindow());
                QVERIFY(!quick->rootObject());
                QVERIFY(!quick->popupSession());
            } // host dies: the container (and the window it owns) are destroyed
            QVERIFY(container.isNull());
            QVERIFY(window.isNull());
            QVERIFY(root.isNull());
            view.reset(); // coordinator destroyed last, after the adapter
        }
    }

    // Unhosted teardown: detach emits exactly once while the original window
    // is still valid, synchronously destroys the owned window and the QML
    // scene while domain objects (the voice-change area) stay alive, clears
    // the getters, and repeating it is inert.
    void unhostedDetachEmitsOnceDestroysWindowAndClearsGetters()
    {
        auto view = std::make_unique<SongView>();
        checks::support::bindEditActionsForTest(*view);
        songview::TimelineQuickView *const quick = view->quickView();
        QVERIFY(quick);
        QVERIFY(quick->rootObject());
        QVERIFY(quick->quickWindow());
        QVERIFY(quick->popupSession());
        QPointer<QQuickWindow> window = quick->quickWindow();
        QPointer<QQuickItem> root = quick->rootObject();
        QPointer<VoiceChangeArea> voice = view->editorDrawer()->voiceChangeArea();
        QVERIFY(voice);
        int detachCount = 0;
        bool detachWhileWindowValid = false;
        QObject::connect(quick, &songview::TimelineQuickView::windowAboutToDetach, quick,
                         [&detachCount, &detachWhileWindowValid, quick] {
                             ++detachCount;
                             detachWhileWindowValid = quick->quickWindow() != nullptr;
                         });
        quick->detachWindow();
        QCOMPARE(detachCount, 1);
        QVERIFY(detachWhileWindowValid); // emitted while the window was usable
        QVERIFY(window.isNull());        // owned window destroyed synchronously
        QVERIFY(root.isNull());          // QML scene unloaded and destroyed
        QVERIFY(!quick->quickWindow());
        QVERIFY(!quick->rootObject());
        QVERIFY(!quick->popupSession());
        QVERIFY(voice); // domain outlives the scene and window
        quick->detachWindow();
        QCOMPARE(detachCount, 1); // idempotent
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
