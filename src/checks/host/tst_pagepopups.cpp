#include "checks/host/hosttestsupport.h"
#include "checks/quickpopupguard.h"
#include "checks/support/editorrig.h"
#include "checks/support/eventsynth.h"

#include <QByteArray>
#include <QCoreApplication>
#include <QPoint>
#include <QPointer>
#include <QQuickItem>
#include <QQuickView>
#include <QQuickWindow>
#include <QRectF>
#include <QSize>
#include <QString>
#include <QtTest>
#include <memory>
#include <vector>

#include "ui/songview/quick/quickmenumodel.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timeruler.h"

namespace checks::host {
namespace {

songview::TimelineInputItem *rulerInputFor(SongView &view)
{
    auto *const quick =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    if (!quick || !quick->rootObject())
        return nullptr;
    return quick->rootObject()->findChild<songview::TimelineInputItem *>(
        QStringLiteral("timelineRulerInput"));
}

// Real shared-menu entry: right press + release through the live ruler input,
// then wait for the typed panel. A null return means the ruler or menu never
// rendered, so the caller attributes the failure.
songview::QuickPopupSession *openRulerMenuAt(SongView &view, const QPointF &rulerLocal)
{
    auto *const rulerInput = rulerInputFor(view);
    if (!rulerInput || !rulerInput->bounds().contains(rulerLocal))
        return nullptr;
    checks::events::sendMouse(*rulerInput, QEvent::MouseButtonPress, rulerLocal, Qt::RightButton,
                              Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(*rulerInput, QEvent::MouseButtonRelease, rulerLocal, Qt::RightButton,
                              Qt::NoButton, Qt::NoModifier);
    const QPointer<songview::QuickPopupSession> live(quick_popup::popupSession(view));
    if (!QTest::qWaitFor([&live] {
            return live && live->isOpen() && quick_popup::menuPanel(*live) &&
                   quick_popup::menuModel(*quick_popup::menuPanel(*live)) != nullptr;
        }))
        return nullptr;
    return live.data();
}

songview::QuickPopupSession *openRulerMenu(SongView &view)
{
    auto *const rulerInput = rulerInputFor(view);
    if (!rulerInput || rulerInput->width() <= 0.0 || rulerInput->height() <= 0.0)
        return nullptr;
    return openRulerMenuAt(view, QPointF(rulerInput->width() / 2.0, rulerInput->height() / 2.0));
}

// Real form entry: the shared ruler menu's Edit-time-signature row publishes
// the canvas prompt, and readiness waits for its focused numerator input.
songview::QuickPopupSession *openTimeSignaturePrompt(SongView &view)
{
    songview::QuickPopupSession *const menu = openRulerMenu(view);
    if (!menu)
        return nullptr;
    songview::QuickMenuModel *const model = quick_popup::menuModel(*quick_popup::menuPanel(*menu));
    if (!model)
        return nullptr;
    const int editRow = model->rowForId(int(songview::RulerMenuAction::EditTimeSig));
    if (editRow < 0 || !quick_popup::clickMenuRow(*menu, editRow))
        return nullptr;
    QQuickWindow *const window = menu->window();
    const QPointer<songview::QuickPopupSession> live(quick_popup::popupSession(view));
    if (!QTest::qWaitFor([&live, window] {
            return live && live->isOpen() && window &&
                   quick_popup::promptItem(*live, QLatin1String("timeSignaturePrompt")) &&
                   quick_popup::inputHasActiveFocus(*window,
                                                    QLatin1String("timeSignatureNumerator"));
        }))
        return nullptr;
    return live.data();
}

class PagePopupSeamsTest final : public QObject
{
    Q_OBJECT
  public:
    PagePopupSeamsTest() = default;

    Q_DISABLE_COPY_MOVE(PagePopupSeamsTest)

  private slots:

    // The outside press that dismisses a popup records its press sequence in
    // the shared window owner BEFORE the popup retires, so destroying the
    // pressed page before the paired release can never expose that release
    // to the sibling page: the orphan release must edit nothing and leave no
    // popup, and a subsequent complete click on the sibling must edit for
    // real.
    void outsidePressOnDestroyedSceneKeepsSiblingReleaseSafe()
    {
        SyntheticHost firstFixture;
        SyntheticHost secondFixture;
        QString error;
        QVERIFY2(firstFixture.prepare(&error), qPrintable(error));
        QVERIFY2(secondFixture.prepare(&error), qPrintable(error));
        // Distinct page data: B carries a note A lacks, so crossed scene
        // bindings would route input into the wrong document.
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
        auto *const firstQuick = firstView->quickView();
        auto *const secondQuick = secondView->quickView();
        QVERIFY(firstQuick);
        QVERIFY(secondQuick);

        // B lives on the right half of the shared window: a translated
        // smaller viewport, the way a workspace page slot is placed.
        QQuickItem &hostViewport = sharedHost.viewport();
        auto *const secondViewport = new QQuickItem(&hostViewport);
        secondViewport->setX(hostViewport.width() / 2.0);
        secondViewport->setWidth(hostViewport.width() / 2.0);
        secondViewport->setHeight(hostViewport.height());
        secondQuick->attachScene(sharedHost.engine(), *secondViewport);
        sharedHost.window().show();
        settle();
        QVERIFY(firstQuick->popupSession());
        QVERIFY(secondQuick->popupSession());

        songview::QuickPopupSession *const menu = openRulerMenu(*firstView);
        QVERIFY2(menu, "the ruler right-press did not open A's shared menu");
        const QPointer<songview::QuickPopupSession> aSession(menu);
        const uint64_t aRevision = firstFixture.document().revision();

        // Outside press on A's own page area (left of B's slot, far from the
        // menu frame): the page-bounded underlay dismisses the menu and the
        // press sequence moves to the window owner.
        const QPoint outsidePoint(150, sharedHost.window().height() - 60);
        QTest::mousePress(&sharedHost.window(), Qt::LeftButton, Qt::NoModifier, outsidePoint);
        settle();
        QVERIFY2(aSession && !aSession->isOpen(),
                 "the outside press on A did not dismiss its menu");

        // Destroy A while the button is still held: its scene, session, and
        // underlay all go away before the paired release arrives.
        firstQuick->detachScene();
        QVERIFY(!firstQuick->popupSession());
        firstView.reset();
        settle();

        // The swallowed release must survive explicit ownership transfer to B.
        secondQuick->setPageSelected(true);
        QVERIFY2(secondQuick->inputEligible(), "B did not become input-eligible after selection");
        auto *const bRollInput =
            secondQuick->rootObject()->findChild<songview::TimelineInputItem *>(
                QStringLiteral("timelineRollInput"));
        QVERIFY(bRollInput);
        QTRY_VERIFY(bRollInput->isVisible());
        QVERIFY2(bRollInput->isEnabled(), "B's roll input stayed disabled after selection");

        // The release lands over B's page: swallowed, so B edits nothing and
        // no popup opens there.
        const uint64_t bRevisionBefore = secondFixture.document().revision();
        const QPointF bProbe = secondViewport->mapToScene(
            QPointF(secondViewport->width() / 2.0, secondViewport->height() / 2.0));
        QTest::mouseRelease(&sharedHost.window(), Qt::LeftButton, Qt::NoModifier, bProbe.toPoint());
        settle();
        QCOMPARE(secondFixture.document().revision(), bRevisionBefore);
        songview::QuickPopupSession *const bSession = secondQuick->popupSession();
        QVERIFY2(!bSession || !bSession->isOpen(), "the orphan release opened a B popup");

        // The swallowed orphan must not block the next complete click on B.
        auto *const rollInput = secondQuick->rootObject()->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineRollInput"));
        QVERIFY(rollInput);
        QTRY_VERIFY(rollInput->width() > 0.0);
        QTRY_VERIFY(rollInput->height() > 0.0);
        const int bUndoBefore = secondFixture.document().undoStack()->count();
        const QPointF editPoint =
            rollInput->mapToScene(QPointF(rollInput->width() / 2.0, rollInput->height() / 2.0));
        QTest::mouseDClick(&sharedHost.window(), Qt::LeftButton, Qt::NoModifier,
                           editPoint.toPoint());
        settle();
        QVERIFY(secondFixture.document().revision() > bRevisionBefore);
        QCOMPARE(secondFixture.document().undoStack()->count(), bUndoBefore + 1);
        QCOMPARE(firstFixture.document().revision(), aRevision);

        secondQuick->detachScene();
        QVERIFY(!secondQuick->popupSession());
    }

    // A translated page bounds menus, shields, and prompts to its clipped viewport.
    void pageEdgePopupClampsInsideTranslatedViewport()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));

        // Attach a fresh canvas once to a translated, clipped page viewport.
        SongView pageView;
        pageView.setDocument(&host.document());
        pageView.setSong(&host.timeline(), &host.bank());
        pageView.setDrawerActivePage(EditorDrawerPage::Velocity);
        pageView.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
        pageView.setDrawerSectionHeight(EditorDrawerPage::Velocity, 200);
        pageView.setDrawerSectionVisible(EditorDrawerPage::Automations, false);
        checks::QuickSceneHost pageHost(pageView, QSize(800, 600), false);
        SongView &view = pageView;
        auto *quick = view.quickView();
        QVERIFY(quick);

        QQuickWindow &window = pageHost.window();
        // This clipping ancestor models a page slot that can resize live.
        auto *const clipItem = new QQuickItem(window.contentItem());
        clipItem->setX(200);
        clipItem->setY(150);
        clipItem->setSize(QSizeF(400, 300));
        clipItem->setClip(true);
        auto *viewport = new QQuickItem(window.contentItem());
        viewport->setParentItem(clipItem);
        viewport->setSize(QSizeF(400, 300));
        quick->attachScene(pageHost.engine(), *viewport);
        SceneDetachGuard sceneDetach(*quick);
        // Direct fixture attachment selects the page explicitly.
        quick->setPageSelected(true);
        window.show();
        settle();

        auto *const session = quick->popupSession();
        QVERIFY(session);
        const QRectF page = session->pageRectInScene();
        QCOMPARE(page, viewport->mapRectToScene(QRectF(QPointF(0, 0), viewport->size())));

        // Press hugging the page's right edge: the shared menu clamps inside
        // the translated viewport, not the window.
        auto *const quickRoot = quick->rootObject();
        QVERIFY(quickRoot);
        auto *const rulerInput = quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineRulerInput"));
        QVERIFY(rulerInput);
        songview::QuickPopupSession *const menu =
            openRulerMenuAt(view, QPointF(rulerInput->width() - 8.0, rulerInput->height() / 2.0));
        QVERIFY2(menu, "the page-edge ruler right-press did not open the shared menu");
        QQuickItem *const frame = quick_popup::menuFrame(*menu);
        QVERIFY(frame);
        const QRectF frameScene = frame->mapRectToScene(frame->boundingRect());
        QVERIFY2(page.contains(frameScene),
                 "the page-edge menu frame escaped the translated viewport");
        const QRectF content = session->contentRectInScene();
        QVERIFY(!content.isEmpty());
        QVERIFY2(page.contains(content),
                 "the reported popup content escaped the translated viewport");
        QVERIFY2(content.width() < window.width() - 1.0,
                 "the popup content reported the whole window instead of the menu frame");

        // The shield covers only the page: the window margin outside the page
        // (where a shared tab strip would live) stays interactive, and an
        // inside-page press still dismisses.
        QTest::mouseClick(&window, Qt::LeftButton, Qt::NoModifier, QPoint(80, 560));
        settle();
        QVERIFY2(menu->isOpen(), "a press outside the page dismissed the popup");
        const QPoint insidePress(static_cast<int>(page.left() + 30.0),
                                 static_cast<int>(page.bottom() - 30.0));
        QTest::mouseClick(&window, Qt::LeftButton, Qt::NoModifier, insidePress);
        settle();
        QVERIFY2(!menu->isOpen(), "a press inside the page did not dismiss the popup");

        // The form path centers and clamps inside the page too, and Escape
        // still cancels without touching the document.
        const uint64_t revision = host.document().revision();
        songview::QuickPopupSession *const prompt = openTimeSignaturePrompt(view);
        QVERIFY2(prompt, "the time-signature prompt did not open inside the translated viewport");
        const QRectF promptRect = prompt->contentRectInScene();
        QVERIFY2(page.contains(promptRect), "the prompt escaped the translated viewport");
        QVERIFY(qFuzzyCompare(promptRect.center().x(), page.center().x()));
        QVERIFY(qFuzzyCompare(promptRect.center().y(), page.center().y()));
        QTest::keyClick(&window, Qt::Key_Escape);
        settle();
        QVERIFY2(!prompt->isOpen(), "Escape did not close the time-signature prompt");
        QCOMPARE(host.document().revision(), revision);
        // Clipping-ancestor width dynamics with a stationary page: shrinking
        // the clip ancestor re-clamps the open menu into the smaller
        // intersection, and shrinking it to nothing cancels the menu without
        // touching the document. The coordinator's viewportChanged (which now
        // carries the ancestor-clipped rectangle) drives the session,
        // mirroring workspace page-slot resizes.
        songview::QuickPopupSession *const liveMenu =
            openRulerMenuAt(view, QPointF(rulerInput->width() - 8.0, rulerInput->height() / 2.0));
        QVERIFY2(liveMenu, "the re-clamp scenario menu did not open");
        clipItem->setWidth(320.0);
        QTRY_VERIFY2(session->pageRectInScene() == QRectF(200, 150, 320, 300),
                     "the visible page rect did not follow the clip ancestor");
        QVERIFY2(liveMenu->isOpen(), "re-clipping the page closed the menu");
        QQuickItem *const reclampedFrame = quick_popup::menuFrame(*liveMenu);
        QVERIFY(reclampedFrame);
        const QRectF clippedPage(200, 150, 320, 300);
        QVERIFY2(
            clippedPage.contains(reclampedFrame->mapRectToScene(reclampedFrame->boundingRect())),
            "the menu did not re-clamp into the clipped page");
        QVERIFY2(clippedPage.contains(session->contentRectInScene()),
                 "the content rect escaped the clipped page");

        clipItem->setWidth(0.0);
        QTRY_VERIFY2(!liveMenu->isOpen(), "clipping the page away left the menu open");
        QCOMPARE(host.document().revision(), revision);
    }

    // Switching away from a page (disable/hide while a prompt is open)
    // cancels the prompt without restoring outgoing focus and leaves no
    // stale edits; while the page is ineligible the typed-menu entry path
    // refuses to open anything, and it recovers as soon as the page is
    // eligible again.
    void ineligiblePageCancelsPromptAndRejectsEntry()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        SongView &view = host.view();
        auto *const quick =
            view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
        QVERIFY(quick);
        auto *const session = quick->popupSession();
        QVERIFY(session);
        QQuickWindow *const window = session->window();
        QVERIFY(window);
        QVERIFY(quick->rootObject());

        const uint64_t revision = host.document().revision();
        const int undoIndex = host.document().undoStack()->index();
        const int undoCount = host.document().undoStack()->count();
        const QByteArray song = host.document().smf().write();

        songview::QuickPopupSession *const prompt = openTimeSignaturePrompt(view);
        QVERIFY2(prompt, "the time-signature prompt did not open");
        QVERIFY(quick_popup::inputHasActiveFocus(*window, QLatin1String("timeSignatureNumerator")));

        // Switch-away simulation, part 1: a disabled page is ineligible. The
        // prompt must cancel without stranding focus: nothing may stay
        // focused inside the retired popup or the disabled page subtree, and
        // the dead prompt input must have lost active focus. Natural Qt
        // fallback focus (window content/root) is fine.
        quick->rootObject()->setEnabled(false);
        settle();
        QVERIFY2(prompt && !prompt->isOpen(), "the disabled page left the prompt open");
        QQuickItem *const focusAfter = window->activeFocusItem();
        QVERIFY2(!focusAfter || !session->owns(focusAfter),
                 "focus landed inside the retired popup after eligibility loss");
        for (const QQuickItem *walk = focusAfter; walk; walk = walk->parentItem())
            QVERIFY2(walk != quick->rootObject(), "focus stayed inside the disabled page");
        QVERIFY2(
            !quick_popup::inputHasActiveFocus(*window, QLatin1String("timeSignatureNumerator")),
            "the dead prompt input kept focus after eligibility loss");
        QCOMPARE(host.document().revision(), revision);
        QCOMPARE(host.document().undoStack()->index(), undoIndex);
        QCOMPARE(host.document().undoStack()->count(), undoCount);
        QCOMPARE(host.document().smf().write(), song);

        // While ineligible, the real typed-menu entry path refuses to open.
        songview::QuickMenuModel probeModel;
        std::vector<songview::QuickMenuItem> probeRows;
        songview::QuickMenuItem probeRow;
        probeRow.id = 1;
        probeRow.text = QStringLiteral("Probe row");
        probeRows.push_back(probeRow);
        probeModel.setItems(std::move(probeRows));
        songview::QuickMenuHost probeHost;
        probeHost.setPopupSession(session);
        probeHost.open(&probeModel, session->pageRectInScene().center());
        settle();
        QVERIFY2(!session->isOpen(), "a menu opened while its page was disabled");
        QVERIFY2(session->overlayRoot() == nullptr,
                 "the rejected entry still materialized an overlay");

        // Eligible again: the same entry path opens the menu for real.
        quick->rootObject()->setEnabled(true);
        settle();
        probeHost.open(&probeModel, session->pageRectInScene().center());
        const QPointer<songview::QuickPopupSession> live{session};
        QVERIFY2(QTest::qWaitFor(
                     [&live] { return live && live->isOpen() && quick_popup::menuPanel(*live); }),
                 "the menu did not open after the page became eligible again");
        QVERIFY(quick_popup::menuModel(*quick_popup::menuPanel(*live)) != nullptr);
        session->cancel();
        settle();

        // Switch-away simulation, part 2: a hidden page cancels too.
        songview::QuickPopupSession *const secondPrompt = openTimeSignaturePrompt(view);
        QVERIFY2(secondPrompt, "the prompt did not reopen on the restored page");
        quick->rootObject()->setVisible(false);
        settle();
        QVERIFY2(secondPrompt && !secondPrompt->isOpen(), "the hidden page left the prompt open");
        QCOMPARE(host.document().revision(), revision);
        QCOMPARE(host.document().smf().write(), song);
        quick->rootObject()->setVisible(true);
        settle();
    }
};
} // namespace
} // namespace checks::host

int runPagePopupSeamsCheck(const QStringList &qtArguments)
{
    checks::host::PagePopupSeamsTest test;
    QStringList arguments{QStringLiteral("page-popups")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "tst_pagepopups.moc"
