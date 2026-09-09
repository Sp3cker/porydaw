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
#include <QEventLoop>
#include <QGuiApplication>
#include <QPointF>
#include <QPointer>
#include <QQuickItem>
#include <QQuickItemGrabResult>
#include <QQuickView>
#include <QQuickWindow>
#include <QTimer>
#include <QtTest>

#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/drawerchrome.h"
#include "ui/editordrawer/drawerpage.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/layout.h"
#include "ui/songview/quick/quickwindowinput.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timeruler.h"

namespace checks::host {
namespace {

QImage grabItemIcon(QQuickItem *icon, bool *ok, QString *error)
{
    *ok = false;
    error->clear();
    const QSharedPointer<QQuickItemGrabResult> result = icon->grabToImage();
    if (!result) {
        *error = QStringLiteral("the icon item could not start an image grab");
        return {};
    }
    if (result->image().isNull()) {
        QEventLoop loop;
        QObject::connect(result.data(), &QQuickItemGrabResult::ready, &loop, &QEventLoop::quit);
        QTimer::singleShot(5000, &loop, &QEventLoop::quit);
        loop.exec();
    }
    const QImage image = result->image();
    if (image.isNull()) {
        *error = QStringLiteral("the icon image grab produced no image");
        return {};
    }
    *ok = true;
    return image;
}

bool hasIconInk(const QImage &image)
{
    for (int y = 0; y < image.height(); ++y) {
        for (int x = 0; x < image.width(); ++x) {
            if (qAlpha(image.pixel(x, y)) >= 32)
                return true;
        }
    }
    return false;
}

// RAII scene detach: a failing return inside a check must still detach the
// coordinator scene while every test-owned window and engine is alive —
// never during host-window destruction, and never only on the success path.
// Declare after an attachScene() call so the guard destroys before that
// attachment's host windows; a repeat detach after an explicit one is an
// inert no-op.
class SceneDetachGuard final
{
  public:
    explicit SceneDetachGuard(songview::TimelineQuickView &quick) : m_quick(&quick) {}
    ~SceneDetachGuard()
    {
        if (m_quick)
            m_quick->detachScene();
    }
    SceneDetachGuard(const SceneDetachGuard &) = delete;
    SceneDetachGuard &operator=(const SceneDetachGuard &) = delete;

  private:
    QPointer<songview::TimelineQuickView> m_quick;
};

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
        songview::QuickWindowInput::forWindow(sharedHost.window()).setSelectedScene(secondQuick);
        secondQuick->setPageSelected(true);
        sharedHost.window().show();
        settle();

        QPointer<QObject> firstRoot{firstQuick->rootObject()};
        QPointer<QObject> secondRoot{secondQuick->rootObject()};
        QVERIFY(firstRoot);
        QVERIFY(secondRoot);
        QVERIFY(firstRoot != secondRoot);
        QCOMPARE(secondQuick->quickWindow(), &sharedHost.window());

        // Visible drawer icon proof while both page contexts live: A's
        // velocity toggle renders the checked icon variant, B's the
        // unchecked one, each rasterized by its own scene's provider. Both
        // toggles are staged explicitly through the public section API: the
        // fixture default leaves the velocity section hidden. Icon tints
        // come from the staged palette (WindowText for unchecked,
        // HighlightedText for checked), so both scenes are refreshed
        // through the public appearance path with deterministically
        // distinct known colors; the checked/unchecked comparison below
        // cannot depend on the host application/theme palette.
        firstView->setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
        QVERIFY(firstView->editorDrawer()->chrome().velocityChecked());
        secondView->setDrawerSectionVisible(EditorDrawerPage::Velocity, false);
        QPalette stagedPalette = QGuiApplication::palette();
        stagedPalette.setColor(QPalette::WindowText, QColor{0x12, 0x34, 0x56, 0xFF});
        stagedPalette.setColor(QPalette::HighlightedText, QColor{0xE0, 0x40, 0x10, 0xFF});
        firstView->editorDrawer()->refreshAppearance(stagedPalette);
        secondView->editorDrawer()->refreshAppearance(stagedPalette);
        settle();
        QVERIFY(firstView->editorDrawer()->chrome().velocityChecked());
        QVERIFY(!secondView->editorDrawer()->chrome().velocityChecked());
        auto *const firstToggle = firstQuick->rootObject()->findChild<QQuickItem *>(
            QStringLiteral("drawerVelocityToggle"));
        auto *const secondToggle = secondQuick->rootObject()->findChild<QQuickItem *>(
            QStringLiteral("drawerVelocityToggle"));
        QVERIFY(firstToggle);
        QVERIFY(secondToggle);
        const auto iconChild = [](QQuickItem *toggle) {
            for (QQuickItem *child : toggle->childItems()) {
                if (child->metaObject()->className() == QByteArray("QQuickImage"))
                    return child;
            }
            return static_cast<QQuickItem *>(nullptr);
        };
        QPointer<QQuickItem> firstIcon{iconChild(firstToggle)};
        QPointer<QQuickItem> secondIcon{iconChild(secondToggle)};
        QVERIFY(firstIcon);
        QVERIFY(secondIcon);
        bool grabbed = false;
        QString grabError;
        const QImage firstCheckedIcon = grabItemIcon(firstIcon, &grabbed, &grabError);
        QVERIFY2(grabbed, qPrintable(grabError));
        QVERIFY(hasIconInk(firstCheckedIcon));
        const QImage secondUncheckedIcon = grabItemIcon(secondIcon, &grabbed, &grabError);
        QVERIFY2(grabbed, qPrintable(grabError));
        QVERIFY(hasIconInk(secondUncheckedIcon));
        QVERIFY(firstCheckedIcon != secondUncheckedIcon);
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

        // Refresh B's theme through the public drawer appearance path with
        // a deterministically different unchecked tint (B's toggle is
        // unchecked, so WindowText drives its visible icon): the icon
        // revision reloads and the surviving scene's re-grabbed Image
        // pixels observably update while still rendering icon ink.
        const int revisionBeforeRefresh = secondView->editorDrawer()->chrome().iconRevision();
        QPalette refreshedPalette = stagedPalette;
        refreshedPalette.setColor(QPalette::WindowText, QColor{0x2E, 0x7D, 0x32, 0xFF});
        secondView->editorDrawer()->refreshAppearance(refreshedPalette);
        settle();
        QVERIFY(secondIcon);
        QVERIFY(secondView->editorDrawer()->chrome().iconRevision() > revisionBeforeRefresh);
        const QImage refreshedIcon = grabItemIcon(secondIcon, &grabbed, &grabError);
        QVERIFY2(grabbed, qPrintable(grabError));
        QVERIFY(hasIconInk(refreshedIcon));
        QVERIFY(refreshedIcon != secondUncheckedIcon);
        QCOMPARE(firstFixture.document().smf().write(), firstSong);
    }

    // After the canvas viewport reassociates to a new host window, the
    // rebuilt popup session delivers real popup interaction through that
    // window: a ruler right-press opens the shared ruler menu bound to the
    // new window, the Set loop start row commits one undoable document
    // command through a real row click, and undo restores the document.
    // Window-loss teardown guards stay observable: the old session is
    // destroyed at retarget and the final detach clears every borrow.
    void reassociationDeliversPopupEditsThroughNewWindow()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        SongView &view = host.view();
        auto *quick = view.quickView();
        QVERIFY(quick);
        quick->detachScene(); // release the rig's own host scene

        QQuickView windowA;
        windowA.resize(QSize(640, 480));
        // Declared before the guard so the guard (declared last below)
        // destroys first and detaches while BOTH windows are still alive on
        // every return path; windowB is only shown and adopted at the move.
        QQuickView windowB;
        windowB.resize(QSize(640, 480));
        auto *viewport = new QQuickItem(windowA.contentItem());
        viewport->setSize(QSizeF(640, 480));
        quick->attachScene(*windowA.engine(), *viewport);
        SceneDetachGuard sceneDetach(*quick);
        // Direct attachment selects explicitly: this scene becomes the
        // window arbiter's selected page in windowA.
        songview::QuickWindowInput::forWindow(windowA).setSelectedScene(quick);
        quick->setPageSelected(true);
        windowA.show();
        settle();
        QVERIFY(quick->rootObject());
        QVERIFY(quick->popupSession());

        QPointer<songview::QuickPopupSession> firstSession(quick->popupSession());
        viewport->setParentItem(windowB.contentItem());
        windowB.show();
        settle();
        // Reassociation alone never selects: the host reselects in the new
        // window before input continues there.
        songview::QuickWindowInput::forWindow(windowB).setSelectedScene(quick);
        QCOMPARE(quick->quickWindow(), static_cast<QQuickWindow *>(&windowB));
        QVERIFY(quick->popupSession());
        QCOMPARE(quick->popupSession()->window(), static_cast<QQuickWindow *>(&windowB));
        QVERIFY(!firstSession);

        auto *rulerInput = quick->rootObject()->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineRulerInput"));
        QVERIFY(rulerInput);
        QTRY_VERIFY(rulerInput->width() > 0.0);
        QTRY_VERIFY(rulerInput->height() > 0.0);

        SongDocument &doc = host.document();
        doc.setLoopTick(false, -1);
        doc.setLoopTick(true, -1);
        settle();
        QCOMPARE(doc.loopTick(false), UINT64_MAX);
        QCOMPARE(doc.loopTick(true), UINT64_MAX);

        // ticksPerBeat is a fixed document property; the timeline projection
        // itself is frozen in this fixture (EditorRig never rebuilds it on
        // document change), so the edit oracle reads the document and a
        // fresh projection instead.
        const uint64_t tick = host.timeline().ticksPerBeat * 4;
        QVERIFY2(view.grid().snapTick(double(tick)) == tick,
                 "the reassociation fixture tick is not snap-aligned");
        const QPointF local(
            view.camera().displayX(double(tick), 0.0, rulerInput->devicePixelRatio()),
            std::max<qreal>(1.0, rulerInput->height() * 0.25));
        QVERIFY2(rulerInput->bounds().contains(local),
                 "the ruler menu press point left the live ruler input");

        {
            const quick_popup::PromptGuard guard(view);
            const int undoIndex = doc.undoStack()->index();
            checks::events::sendMouse(*rulerInput, QEvent::MouseButtonPress, local, Qt::RightButton,
                                      Qt::RightButton, Qt::NoModifier);
            checks::events::sendMouse(*rulerInput, QEvent::MouseButtonRelease, local,
                                      Qt::RightButton, Qt::NoButton, Qt::NoModifier);
            const QPointer<songview::QuickPopupSession> live(quick_popup::popupSession(view));
            QVERIFY2(QTest::qWaitFor([&live] {
                         return live && live->isOpen() && quick_popup::menuPanel(*live) &&
                                quick_popup::menuModel(*quick_popup::menuPanel(*live)) != nullptr;
                     }),
                     "the ruler right-press did not open the shared ruler menu in the new window");
            QCOMPARE(live->window(), static_cast<QQuickWindow *>(&windowB));
            QCOMPARE(live->overlayRoot()->window(), static_cast<QQuickWindow *>(&windowB));

            const int setStartRow = quick_popup::menuModel(*quick_popup::menuPanel(*live))
                                        ->rowForId(int(songview::RulerMenuAction::SetLoopStart));
            QVERIFY2(setStartRow >= 0, "the ruler menu has no Set loop start row");
            QVERIFY2(quick_popup::clickMenuRow(*live, setStartRow),
                     "the Set loop start row did not receive a real click through the new window");
            QCoreApplication::processEvents();
            QVERIFY2(!live->isOpen(), "the Set loop start activation left the ruler menu open");
            QTRY_COMPARE(doc.loopTick(false), tick);
            QCOMPARE(doc.undoStack()->index(), undoIndex + 1);
            // The document-to-timeline projection carries the marker, like
            // the landed host-adapter loop pattern.
            std::unique_ptr<MidiTimeline> projected = doc.buildTimeline(48000.0);
            QVERIFY(projected);
            QCOMPARE(projected->loopStartTick, tick);

            doc.undoStack()->undo();
            settle();
            QTRY_VERIFY2(doc.loopTick(false) == UINT64_MAX,
                         "undo did not restore the cleared loop state");
            QCOMPARE(doc.undoStack()->index(), undoIndex);
        }

        quick->detachScene();
        QVERIFY(!quick->quickWindow());
        QVERIFY(!quick->rootObject());
        QVERIFY(!quick->popupSession());
    }

    // Losing the host window and engine without a detach destroys the
    // coordinator-owned canvas by observation; the deferred detach then
    // completes safely. The recovered scene on a fresh engine then delivers
    // a real double-click note gesture through the new window: one undoable
    // document command lands, and undo restores the document byte-identically.
    void engineLossRecoverySupportsNoteEditingAndUndo()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        auto *quick = host.view().quickView();
        QVERIFY(quick);
        quick->detachScene(); // release the rig's own host scene

        auto window = std::make_unique<QQuickView>();
        window->resize(QSize(640, 480));
        auto *viewport = new QQuickItem(window->contentItem());
        viewport->setSize(QSizeF(640, 480));
        quick->attachScene(*window->engine(), *viewport);
        SceneDetachGuard sceneDetach(*quick);
        settle();
        QVERIFY(quick->popupSession());

        // Direct attachment selects explicitly; readiness and selection
        // make the page input-eligible in this window.
        songview::QuickWindowInput::forWindow(*window).setSelectedScene(quick);
        quick->setPageSelected(true);
        window->show();
        settle();
        QPointer<QQuickItem> canvas(quick->rootObject());
        QVERIFY(canvas);
        QVERIFY(quick->popupSession());

        window.reset();
        settle();
        QVERIFY(canvas.isNull());
        QVERIFY(!quick->rootObject());
        QVERIFY(!quick->quickWindow());
        // No session-lifetime expectation here: cleanup may run in the engine
        // hook or in the deferred detach below; the contract is recovery.
        quick->detachScene();
        QVERIFY(!quick->popupSession());
        QQuickView recovered;
        recovered.resize(QSize(640, 480));
        auto *freshViewport = new QQuickItem(recovered.contentItem());
        freshViewport->setSize(QSizeF(640, 480));
        quick->attachScene(*recovered.engine(), *freshViewport);
        SceneDetachGuard recoveredSceneDetach(*quick);
        // Recovery re-selects explicitly in the fresh window.
        songview::QuickWindowInput::forWindow(recovered).setSelectedScene(quick);
        recovered.show();
        settle();
        QVERIFY(quick->rootObject());
        QCOMPARE(quick->quickWindow(), static_cast<QQuickWindow *>(&recovered));

        auto *rollInput = quick->rootObject()->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineRollInput"));
        QVERIFY(rollInput);
        QTRY_VERIFY(rollInput->width() > 0.0);
        QTRY_VERIFY(rollInput->height() > 0.0);
        const QPointF probePoint =
            rollInput->mapToScene(QPointF{rollInput->width() / 2.0, rollInput->height() / 2.0});
        SongDocument &doc = host.document();
        const int undoCountBefore = doc.undoStack()->count();
        const int undoIndexBefore = doc.undoStack()->index();
        const QByteArray songBefore = doc.smf().write();
        QTest::mouseDClick(&recovered, Qt::LeftButton, Qt::NoModifier, probePoint.toPoint());
        settle();
        QCOMPARE(doc.undoStack()->count(), undoCountBefore + 1);
        QVERIFY(doc.smf().write() != songBefore);

        doc.undoStack()->undo();
        settle();
        QCOMPARE(doc.smf().write(), songBefore);
        QCOMPARE(doc.undoStack()->index(), undoIndexBefore);
        QCOMPARE(doc.notesForTrack(0).size(), size_t{2});

        quick->detachScene();
        QVERIFY(!quick->quickWindow());
        QVERIFY(!quick->rootObject());
        QVERIFY(!quick->popupSession());
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
