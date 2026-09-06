#include "checks/fwd.hpp"
#include "checks/host/hosttestsupport.h"

#include <memory>

#include <QColor>
#include <QPointer>
#include <QtTest>

#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/drawerchrome.h"
#include "ui/editordrawer/drawerpage.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/layout.h"
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
    void defaultsAreAutomationOpen()
    {
        const EditorViewState state;
        QVERIFY(!state.velocity.visible);
        QVERIFY(!state.velocity.height.has_value());
        QVERIFY(state.automation.visible);
        QVERIFY(!state.automation.height.has_value());
        QVERIFY(!state.voiceChanges.visible);
        QCOMPARE(state.activePage, EditorDrawerPage::Automations);
        QCOMPARE(state.laneHeight, 0);
        QVERIFY(state.laneHeights.empty());
        QVERIFY(state.laneRanges.empty());
        QVERIFY(state.emptyLanes.empty());
        QVERIFY(state.hiddenLanes().empty());
    }

    void cosmeticStateComparesByValue()
    {
        const EditorAutomationRowId lane{EditorAutomationRowKind::ControlChange, 2, 1};
        EditorViewState changed;
        changed.velocity = {false, 144};
        changed.automation = {true, 96};
        changed.activePage = EditorDrawerPage::Velocity;
        changed.laneHeight = 96;
        changed.laneHeights.emplace(lane, 112);
        changed.laneRanges.emplace(lane, 91);
        changed.emptyLanes.emplace(lane);
        changed.hideLane(lane);
        QVERIFY(changed != EditorViewState{});
    }

    void drawerPagesExistWithoutWidgetShells()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        auto *drawer = host.view().editorDrawer();
        QVERIFY(drawer);
        QVERIFY(drawer->automationPage());
        QVERIFY(drawer->velocityArea());
        QVERIFY(drawer->voiceChangeArea());
        QVERIFY(!qobject_cast<QWidget *>(drawer));
        QVERIFY(!qobject_cast<QWidget *>(drawer->automationPage()));
        QVERIFY(drawer->parent() == &host.view());
    }

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
        QCOMPARE(drawer->chrome().scrollbarWidth(), layout::space(layout::Space::Two));
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

    void liveStateRefreshReachesEveryDrawerPage()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        SongView &view = host.view();
        auto *drawer = view.editorDrawer();
        QVERIFY(drawer);
        DrawerPageLiveState live;
        live.documentRevision = host.document().revision();
        live.timeZoom = view.camera().pxPerBeat();
        live.horizontalScroll = view.camera().scrollX();
        live.editCursorTick = 12;
        live.trackColor = QColor{10, 20, 30};
        live.playback = {12.0, true};
        drawer->automationPage()->refreshLiveState(live);
        drawer->velocityArea()->refreshLiveState(live);
        drawer->voiceChangeArea()->refreshLiveState(live);
        QVERIFY(!drawer->automationPage()->canvas()->rows().empty());
        QCOMPARE(drawer->velocityArea()->axis().mode(), VelocityAxis::Mode::Intrinsic);
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

    void quickHostDetachesBeforeVoiceAreaDies()
    {
        auto view = std::make_unique<SongView>();
        auto *quick = view->findChild<songview::TimelineQuickView *>(
            QStringLiteral("timelineQuickCanvas"), Qt::FindDirectChildrenOnly);
        QPointer<VoiceChangeArea> voice = view->editorDrawer()->voiceChangeArea();
        QVERIFY(quick);
        QVERIFY(voice);
        QCOMPARE(voice->parent(), view.get());
        bool quickDestroyed = false;
        bool voiceAliveAtQuickDestruction = false;
        QObject::connect(quick, &QObject::destroyed, [&](QObject *) {
            quickDestroyed = true;
            voiceAliveAtQuickDestruction = !voice.isNull();
        });
        view.reset();
        QVERIFY(quickDestroyed);
        QVERIFY(voiceAliveAtQuickDestruction);
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
