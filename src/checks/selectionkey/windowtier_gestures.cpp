// Selection keyboard routing, window tier: pointer-gesture protection. A live
// drawer resize drag or automation scrollbar thumb drag owns the surface, so
// shared editing keys are a consumed no-op while it holds the pointer; the
// first Escape cancels only the gesture and keeps the selection, and the next
// idle Escape clears it (plan 6). The press lands on the reachable grip/thumb
// without moving focus, so the gesture is not cancelled before the
// mid-gesture keys are delivered, and every press is recorded for the
// failure-safe case cleanup to release.

#include "checks/selectionkey/tst_windowtier.h"

#include "checks/support/eventsynth.h"

#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/songview/timelinebandlayout.h"

#include <QEvent>
#include <QGuiApplication>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRect>
#include <QStyleHints>

namespace {

constexpr int kTrack = 0;
constexpr uint8_t kController = 10;
constexpr uint8_t kSecondController = 74;
constexpr int kGestureTick = 2400;

// Bounded wait for both layers of Quick focus to finish: the requested band
// must own the scene's active item, and Qt's native focus object/window must
// have caught up with that internal selection. focusBand() can satisfy only
// the first condition while QWindowContainer's FocusIn is still pending.
bool automationBandHasCompletedNativeFocus(songview::TimelineQuickView *quick)
{
    QQuickWindow *const window = quick ? quick->quickWindow() : nullptr;
    QQuickItem *const activeItem = window ? window->activeFocusItem() : nullptr;
    return quick && quick->focusedBand() == songview::TimelineBand::Automation && activeItem &&
           QGuiApplication::focusObject() == activeItem && QGuiApplication::focusWindow() == window;
}

bool automationBandOwnsFocus(songview::TimelineQuickView *quick)
{
    return checks::async_wait::waitUntil(
               [] { return true; },
               [quick] { return automationBandHasCompletedNativeFocus(quick); }, 5000,
               10) == checks::async_wait::Result::Ready;
}

QString quickFocusState(songview::TimelineQuickView *quick)
{
    QQuickWindow *const window = quick ? quick->quickWindow() : nullptr;
    QQuickItem *const activeItem = window ? window->activeFocusItem() : nullptr;
    return QStringLiteral("active=%1 QWidget=%2 QGui-object=%3 QGui-window=%4 quick-window=%5")
        .arg(selectionkey::focusObjectIdentity(activeItem))
        .arg(selectionkey::focusObjectIdentity(QApplication::focusWidget()))
        .arg(selectionkey::focusObjectIdentity(QGuiApplication::focusObject()))
        .arg(selectionkey::focusObjectIdentity(QGuiApplication::focusWindow()))
        .arg(selectionkey::focusObjectIdentity(window));
}

// Real pointer delivery onto a chrome control: hover priming (the proven
// automation-fixture pattern), press, drag-distance activation step, then the
// actual drag move. Pressing never changes focus, so a focused band keeps
// owning the keys delivered during the gesture. Returns false when the hover
// priming could not be delivered, before anything was pressed.
bool pressAndDrag(QQuickWindow *window, QQuickItem &surface, const QPointF &pressPoint,
                  const QPointF &dragPoint)
{
    if (!checks::events::primeMouseMove(*window, surface, pressPoint.toPoint()))
        return false;
    selectionkey::sendMouseEvent(*window, QEvent::MouseButtonPress, pressPoint, Qt::LeftButton);
    selectionkey::settle();
    const qreal activation = QGuiApplication::styleHints()->startDragDistance() + 1.0;
    const qreal activationStep = dragPoint.y() >= pressPoint.y() ? activation : -activation;
    selectionkey::sendMouseEvent(*window, QEvent::MouseMove,
                                 pressPoint + QPointF(0.0, activationStep), Qt::NoButton);
    selectionkey::settle();
    selectionkey::sendMouseEvent(*window, QEvent::MouseMove, dragPoint, Qt::NoButton);
    selectionkey::settle();
    return true;
}

QPointer<QQuickItem> findItem(songview::TimelineQuickView *quick, const QString &name)
{
    QQuickItem *const root = quick ? quick->rootObject() : nullptr;
    return QPointer<QQuickItem>(root ? root->findChild<QQuickItem *>(name) : nullptr);
}

QPointF itemCenter(const QPointer<QQuickItem> &item)
{
    return item ? item->mapToScene(item->boundingRect().center()) : QPointF{};
}

} // namespace

void SelectionWindowTierTest::resizeDragProtectsSelectedNotes()
{
    SongView &view = this->view();
    SongDocument &document = this->document();
    const selectionkey::ScenarioRollback rollback(view, document);
    const bool velocityWasVisible = view.drawerSectionVisible(EditorDrawerPage::Velocity);
    const bool voiceChangesWasVisible = view.drawerSectionVisible(EditorDrawerPage::VoiceChanges);
    // Isolate the automation body from the host-height allocation consumed by
    // unrelated open drawers. The resize assertion below uses the canonical
    // body rectangle, not merely the requested/stored section height.
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, false);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, 200);
    view.selectTrack(kTrack);
    const std::optional<NotePair> pair = addNotePair(document, kTrack, kGestureTick);
    QVERIFY2(pair.has_value(),
             "the reserved tick-2400 note pair could not be inserted and resolved");
    songview::TimelineQuickView *const quick = selectionkey::quickCanvas(view);
    QQuickWindow *const quickWindow = quick ? quick->quickWindow() : nullptr;
    QVERIFY2(quickWindow && quick->rootObject(),
             "the Quick surface is missing for pointer gesture checks");
    EditorDrawer *const drawer = view.editorDrawer();
    AutomationPage *const automationPage = drawer ? drawer->automationPage() : nullptr;
    const QRect quickBounds(QPoint(0, 0), quickWindow->size());
    const auto mapsIntoWindow = [&quickBounds](QQuickItem *item) {
        return item && item->isVisible() &&
               quickBounds.contains(
                   item->mapToScene(QPointF{item->width() / 2.0, item->height() / 2.0}).toPoint());
    };
    const auto nudge = selectionkey::firstBinding(QStringLiteral("roll.nudge_right"));
    const auto remove = selectionkey::firstBinding(QStringLiteral("roll.delete"));
    QVERIFY2(nudge.has_value() && remove.has_value(),
             "nudge Right/Delete have no single-key bindings");
    const std::vector<NoteId> selected{pair->ids[0], pair->ids[1]};
    const auto selectionKept = [&view, &selected] {
        return view.selectionModel().noteSelection() == selected;
    };
    const auto releaseAt = [&](const QPointF &point) {
        selectionkey::sendMouseEvent(*quickWindow, QEvent::MouseButtonRelease, point,
                                     Qt::LeftButton);
        selectionkey::settle();
        trackRelease();
    };

    // Live resize grip drag: the pressed grip resizes and owns the surface;
    // editing keys cannot mutate the notes until Escape cancels the drag. The
    // chrome snapshot and the mapped grip geometry must both be live before
    // the press, or the press lands on nothing and the drag never starts.
    QPointer<QQuickItem> grip = findItem(quick, QStringLiteral("drawerAutomationHandleInput"));
    const bool gripReady =
        grip && grip->width() > 0 && grip->height() > 0 && drawer != nullptr &&
        drawer->chrome().automationHandleVisible() &&
        checks::async_wait::waitUntil([] { return true; }, [&] { return mapsIntoWindow(grip); },
                                      2000, 10) == checks::async_wait::Result::Ready;
    QVERIFY2(gripReady,
             "the automation resize grip input is missing or never mapped into the window");
    QVERIFY2(focusAutomationBand(view), "could not focus the automation band");
    QVERIFY2(automationBandOwnsFocus(quick),
             qPrintable(QStringLiteral("the automation band never completed native focus "
                                       "before the gesture (%1)")
                            .arg(quickFocusState(quick))));
    view.selectionModel().setNoteSelection(selected);
    const std::optional<DocNote> secondBeforeGrip = selectionkey::noteById(document, pair->ids[1]);
    QVERIFY2(secondBeforeGrip.has_value(),
             "the second selected note vanished before the resize gesture baseline");
    const QByteArray beforeGrip = document.smf().write();
    const auto actualAutomationHeight = [drawer] {
        const std::optional<QRect> body = drawer->bodyRect(EditorDrawerPage::Automations);
        return body ? body->height() : -1;
    };
    const int requestedHeightBeforeDrag = view.drawerSectionHeight(EditorDrawerPage::Automations);
    const int actualHeightBeforeDrag = actualAutomationHeight();
    const int minimumHeight = drawer->minimumSectionHeight();
    constexpr int dragDistance = 40;
    QVERIFY2(actualHeightBeforeDrag == requestedHeightBeforeDrag &&
                 actualHeightBeforeDrag >= minimumHeight + dragDistance,
             qPrintable(QStringLiteral("the automation resize baseline is not an unclamped "
                                       "canonical body with room to shrink (requested %1, "
                                       "actual %2, minimum %3, drag distance %4)")
                            .arg(requestedHeightBeforeDrag)
                            .arg(actualHeightBeforeDrag)
                            .arg(minimumHeight)
                            .arg(dragDistance)));
    const QPointF gripPoint = itemCenter(grip);
    const QPointF dragPoint = gripPoint + QPointF(0.0, dragDistance);
    QVERIFY2(pressAndDrag(quickWindow, *grip, gripPoint, dragPoint),
             "could not deliver the press and drag onto the automation resize grip");
    trackPointer(dragPoint.toPoint());
    QVERIFY2(automationBandHasCompletedNativeFocus(quick),
             qPrintable(QStringLiteral("the grip press disturbed completed native Quick focus (%1)")
                            .arg(quickFocusState(quick))));
    const bool resizeGestureActive = quick->gestureActive();
    const bool resizeLive =
        checks::async_wait::waitUntil(
            [] { return true; }, [&] { return actualAutomationHeight() < actualHeightBeforeDrag; },
            2000, 10) == checks::async_wait::Result::Ready;
    const int requestedHeightAfterDrag = view.drawerSectionHeight(EditorDrawerPage::Automations);
    const int actualHeightAfterDrag = actualAutomationHeight();
    if (!resizeLive)
        releaseAt(dragPoint);
    QVERIFY2(resizeLive,
             qPrintable(QStringLiteral("the pressed grip did not shrink the live canonical "
                                       "body (requested before %1, actual before %2, minimum "
                                       "%3, press %4,%5, endpoint %6,%7, requested after %8, "
                                       "actual after %9, gesture active %10, focus %11)")
                            .arg(requestedHeightBeforeDrag)
                            .arg(actualHeightBeforeDrag)
                            .arg(minimumHeight)
                            .arg(gripPoint.x())
                            .arg(gripPoint.y())
                            .arg(dragPoint.x())
                            .arg(dragPoint.y())
                            .arg(requestedHeightAfterDrag)
                            .arg(actualHeightAfterDrag)
                            .arg(resizeGestureActive ? QStringLiteral("yes") : QStringLiteral("no"))
                            .arg(quickFocusState(quick))));
    QVERIFY2(document.smf().write() == beforeGrip && selectionKept(),
             "the live resize drag mutated the document or dropped the selection");
    selectionkey::deliverKey(quickWindow, nudge->key(), nudge->keyboardModifiers());
    selectionkey::deliverKey(quickWindow, remove->key(), remove->keyboardModifiers());
    QVERIFY2(document.smf().write() == beforeGrip && selectionKept(),
             "Right/Delete during the live resize drag mutated the notes or dropped the selection");
    selectionkey::deliverKey(quickWindow, Qt::Key_Escape);
    QVERIFY2(selectionKept(),
             "gesture Escape cleared the selection instead of canceling the resize drag");
    const int heightAfterCancel = view.drawerSectionHeight(EditorDrawerPage::Automations);
    selectionkey::sendMouseEvent(*quickWindow, QEvent::MouseMove, gripPoint, Qt::NoButton);
    selectionkey::settle();
    QCOMPARE(view.drawerSectionHeight(EditorDrawerPage::Automations), heightAfterCancel);
    releaseAt(gripPoint);
    selectionkey::deliverKey(quickWindow, nudge->key(), nudge->keyboardModifiers());
    DocNote resumed;
    QVERIFY2(document.findNote(pair->ids[1], &resumed) && resumed.tick != secondBeforeGrip->tick,
             "Right after the Escape cancellation did not resume note editing");
    selectionkey::deliverKey(quickWindow, Qt::Key_Escape);
    QVERIFY2(view.selectionModel().noteSelection().empty(),
             "the second idle Escape did not clear the selection after the resize drag");
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, 200);
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, velocityWasVisible);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, voiceChangesWasVisible);
    selectionkey::settle();
}

void SelectionWindowTierTest::scrollbarThumbDragProtectsSelectedNotes()
{
    SongView &view = this->view();
    SongDocument &document = this->document();
    const selectionkey::ScenarioRollback rollback(view, document);
    const bool velocityWasVisible = view.drawerSectionVisible(EditorDrawerPage::Velocity);
    const bool voiceChangesWasVisible = view.drawerSectionVisible(EditorDrawerPage::VoiceChanges);
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, false);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    view.selectTrack(kTrack);
    // Two controller lanes guarantee the automation content overflows the
    // short viewport, so the thumb drag exercises a live, draggable scrollbar.
    document.addLanePoint(kTrack, kController, 48, 32);
    document.addLanePoint(kTrack, kController, 96, 64);
    document.addLanePoint(kTrack, kSecondController, 48, 96);
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, 90);
    const std::optional<NotePair> pair = addNotePair(document, kTrack, kGestureTick);
    QVERIFY2(pair.has_value(),
             "the reserved tick-2400 note pair could not be inserted and resolved");
    songview::TimelineQuickView *const quick = selectionkey::quickCanvas(view);
    QQuickWindow *const quickWindow = quick ? quick->quickWindow() : nullptr;
    QVERIFY2(quickWindow && quick->rootObject(),
             "the Quick surface is missing for pointer gesture checks");
    EditorDrawer *const drawer = view.editorDrawer();
    AutomationPage *const automationPage = drawer ? drawer->automationPage() : nullptr;
    const auto nudge = selectionkey::firstBinding(QStringLiteral("roll.nudge_right"));
    const auto remove = selectionkey::firstBinding(QStringLiteral("roll.delete"));
    QVERIFY2(nudge.has_value() && remove.has_value(),
             "nudge Right/Delete have no single-key bindings");
    const std::vector<NoteId> selected{pair->ids[0], pair->ids[1]};
    const auto selectionKept = [&view, &selected] {
        return view.selectionModel().noteSelection() == selected;
    };
    const auto releaseAt = [&](const QPointF &point) {
        selectionkey::sendMouseEvent(*quickWindow, QEvent::MouseButtonRelease, point,
                                     Qt::LeftButton);
        selectionkey::settle();
        trackRelease();
    };

    // Live scrollbar thumb drag: the same protection on QML-only drag state.
    if (automationPage) {
        automationPage->setVerticalScroll(0);
        selectionkey::settle();
    }
    QPointer<QQuickItem> scrollbar = findItem(quick, QStringLiteral("drawerAutomationScrollBar"));
    QPointer<QQuickItem> thumb = findItem(quick, QStringLiteral("drawerAutomationScrollThumb"));
    const bool thumbReady =
        checks::async_wait::waitUntil(
            [&] { return bool(quick); },
            [&] {
                if (!scrollbar)
                    scrollbar = findItem(quick, QStringLiteral("drawerAutomationScrollBar"));
                if (!thumb)
                    thumb = findItem(quick, QStringLiteral("drawerAutomationScrollThumb"));
                return scrollbar && thumb && thumb->isVisible() && automationPage != nullptr &&
                       automationPage->automationContentHeight() >
                           automationPage->automationViewportSize().height();
            },
            2000, 10) == checks::async_wait::Result::Ready;
    QVERIFY2(thumbReady,
             "the automation scrollbar thumb is missing or not scrollable in this fixture");
    QVERIFY2(focusAutomationBand(view), "could not focus the automation band");
    QVERIFY2(automationBandOwnsFocus(quick),
             qPrintable(QStringLiteral("the automation band never completed native focus "
                                       "before the scrollbar gesture (%1)")
                            .arg(quickFocusState(quick))));
    view.selectionModel().setNoteSelection(selected);
    const std::optional<DocNote> secondBeforeThumb = selectionkey::noteById(document, pair->ids[1]);
    QVERIFY2(secondBeforeThumb.has_value(),
             "the second selected note vanished before the scrollbar gesture baseline");
    const QByteArray beforeThumb = document.smf().write();
    const int scrollBeforeDrag = automationPage->verticalScroll();
    const QPointF thumbPoint = itemCenter(thumb);
    const QPointF thumbDragPoint = thumbPoint + QPointF(0.0, 60.0);
    QVERIFY2(thumb, "the automation scrollbar thumb vanished before its drag");
    QVERIFY2(pressAndDrag(quickWindow, *thumb, thumbPoint, thumbDragPoint),
             "could not deliver the press and drag onto the automation scrollbar thumb");
    trackPointer(thumbDragPoint.toPoint());
    QVERIFY2(
        automationBandHasCompletedNativeFocus(quick),
        qPrintable(QStringLiteral("the thumb press disturbed completed native Quick focus (%1)")
                       .arg(quickFocusState(quick))));
    const bool dragLive = checks::async_wait::waitUntil(
                              [] { return true; },
                              [&] { return automationPage->verticalScroll() > scrollBeforeDrag; },
                              2000, 10) == checks::async_wait::Result::Ready;
    if (!dragLive)
        releaseAt(thumbDragPoint);
    QVERIFY2(dragLive, "the pressed scrollbar thumb did not begin a live drag");
    QVERIFY2(document.smf().write() == beforeThumb && selectionKept(),
             "the live scrollbar drag mutated the document or dropped the selection");
    selectionkey::deliverKey(quickWindow, nudge->key(), nudge->keyboardModifiers());
    selectionkey::deliverKey(quickWindow, remove->key(), remove->keyboardModifiers());
    QVERIFY2(
        document.smf().write() == beforeThumb && selectionKept(),
        "Right/Delete during the live scrollbar drag mutated the notes or dropped the selection");
    selectionkey::deliverKey(quickWindow, Qt::Key_Escape);
    QVERIFY2(selectionKept(),
             "gesture Escape cleared the selection instead of canceling the scrollbar drag");
    releaseAt(thumbPoint);
    selectionkey::deliverKey(quickWindow, nudge->key(), nudge->keyboardModifiers());
    DocNote resumed;
    QVERIFY2(document.findNote(pair->ids[1], &resumed) && resumed.tick != secondBeforeThumb->tick,
             "Right after the Escape cancellation did not resume note editing");
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, 200);
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, velocityWasVisible);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, voiceChangesWasVisible);
    selectionkey::settle();
}
