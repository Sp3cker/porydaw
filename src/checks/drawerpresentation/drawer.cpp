#include "checks/drawerpresentation/tst_drawerpresentation.h"

#include <QtTest>

#include <cmath>

#include <QAction>
#include <QApplication>
#include <QMouseEvent>
#include <QPalette>
#include <QQuickItem>
#include <QQuickWindow>

#include "checks/drawerpresentation/fixtures.h"
#include "checks/support/timelinequickcheck.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/drawerchrome.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/trackheadermodel.h"

#include "ui/songview/quick/timelinequickview.h"
using namespace checks::drawerpresentation;

namespace {

DrawerFixture makeDrawerFixture()
{
    DrawerFixture fixture;
    QString error;
    if (!fixture.create(error))
        qFatal("%s", qPrintable(error));
    return fixture;
}

songview::TimelineInputItem *handleFor(const DrawerFixture &fixture, EditorDrawerPage page)
{
    switch (page) {
    case EditorDrawerPage::VoiceChanges:
        return fixture.voiceHandle;
    case EditorDrawerPage::Velocity:
        return fixture.velocityHandle;
    case EditorDrawerPage::Automations:
        return fixture.automationHandle;
    }
    return nullptr;
}

void sendWindowMouse(songview::TimelineInputItem &input, QEvent::Type type, const QPointF &position,
                     Qt::MouseButton button, Qt::MouseButtons buttons = Qt::NoButton)
{
    QQuickWindow *const window = input.window();
    Q_ASSERT(window);
    const QPointF windowPosition = input.mapToScene(position);
    QMouseEvent event(type, windowPosition, QPointF(window->mapToGlobal(windowPosition.toPoint())),
                      button, buttons, Qt::NoModifier);
    QCoreApplication::sendEvent(window, &event);
}

// The Quick window is the whole canonical viewport, so every visible
// published chrome rectangle must land inside the window: clipping — not a
// host envelope — is the only way chrome can go missing.
QRectF publishedChromeRect(const DrawerChrome &chrome)
{
    QRectF published;
    const auto add = [&published](const QRectF &rect, bool visible) {
        if (visible && !rect.isEmpty())
            published = published.isNull() ? rect : published.united(rect);
    };
    add(chrome.barRect(), true);
    add(chrome.voiceChangesToggleRect(), true);
    add(chrome.velocityToggleRect(), true);
    add(chrome.automationToggleRect(), true);
    add(chrome.voiceChangesHandleRect(), chrome.voiceChangesHandleVisible());
    add(chrome.velocityHandleRect(), chrome.velocityHandleVisible());
    add(chrome.automationHandleRect(), chrome.automationHandleVisible());
    add(chrome.detentRect(), chrome.detentVisible());
    add(chrome.automationScrollbarRect(), chrome.automationScrollbarVisible());
    return published;
}

} // namespace

void DrawerPresentationTest::drawerSurfaceAndChrome()
{
    DrawerFixture fixture = makeDrawerFixture();
    SongView &view = *fixture.view;
    EditorDrawer *const drawer = view.editorDrawer();
    DrawerChrome &chrome = fixture.chrome();
    auto *const root = fixture.quickRoot;
    auto *const roll =
        root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineRollInput"));
    auto *const automation = drawer ? drawer->automationPage() : nullptr;
    auto *const velocity = drawer ? drawer->velocityArea() : nullptr;
    auto *const voice = drawer ? drawer->voiceChangeArea() : nullptr;

    QVERIFY(drawer);
    QVERIFY(roll);
    QVERIFY(automation);
    QVERIFY(velocity);
    QVERIFY(voice);
    QVERIFY(fixture.quick->quickWindow());
    QCOMPARE(drawer->minimumSectionHeight(), layout::fontPx(17.0 / 5.0));
    QVERIFY(checks::support::quickWindowIsUnmasked(*fixture.quick));
    QVERIFY(!chrome.barRect().isEmpty());
    QVERIFY(!chrome.voiceChangesToggleRect().isEmpty());
    QVERIFY(!chrome.velocityToggleRect().isEmpty());
    QVERIFY(!chrome.automationToggleRect().isEmpty());
    QCOMPARE(chrome.barBorderWidth(), layout::singlePixel());
    QCOMPARE(chrome.toggleCheckedBackground(),
             QGuiApplication::palette().color(QPalette::Highlight));
    QCOMPARE(chrome.barBackground().alpha(), 255);
    QCOMPARE(chrome.barOutline().alpha(), 255);
    QVERIFY(chrome.iconRevision() > 0);
    QVERIFY(view.drawerSectionVisible(EditorDrawerPage::Automations));
    QVERIFY(!view.drawerSectionVisible(EditorDrawerPage::Velocity));
    QVERIFY(!view.drawerSectionVisible(EditorDrawerPage::VoiceChanges));
    QCOMPARE(view.drawerActivePage(), EditorDrawerPage::Automations);
    QVERIFY(drawer->automationAction()->shortcuts().isEmpty());
    QVERIFY(drawer->velocityAction()->shortcuts().isEmpty());
    QVERIFY(drawer->voiceChangesAction()->shortcuts().isEmpty());
}

void DrawerPresentationTest::drawerToggleTransactions_data()
{
    QTest::addColumn<EditorDrawerPage>("page");
    QTest::newRow("voice") << EditorDrawerPage::VoiceChanges;
    QTest::newRow("velocity") << EditorDrawerPage::Velocity;
    QTest::newRow("automation") << EditorDrawerPage::Automations;
}

void DrawerPresentationTest::drawerToggleTransactions()
{
    QFETCH(EditorDrawerPage, page);
    DrawerFixture fixture = makeDrawerFixture();
    SongView &view = *fixture.view;
    view.setDrawerSectionVisible(page, false);
    pump();
    std::vector<QString> statuses;
    QObject::connect(&view, &SongView::statusMessage,
                     [&statuses](const QString &message) { statuses.push_back(message); });
    const int originalHeight = view.drawerSectionHeight(page);

    fixture.clickToggle(page);
    QVERIFY(view.drawerSectionVisible(page));
    QCOMPARE(view.drawerActivePage(), page);
    QVERIFY(view.editorDrawer()->bodyRect(page).has_value());
    QVERIFY(!statuses.empty());

    fixture.clickToggle(page);
    QVERIFY(!view.drawerSectionVisible(page));
    QCOMPARE(view.drawerSectionHeight(page), originalHeight);
    QVERIFY(!statuses.empty());

    fixture.clickToggle(page);
    QVERIFY(view.drawerSectionVisible(page));
    QCOMPARE(view.drawerSectionHeight(page), originalHeight);
}

void DrawerPresentationTest::drawerZeroHeightAndShortcuts()
{
    DrawerFixture fixture = makeDrawerFixture();
    SongView &view = *fixture.view;
    view.setDrawerSectionHeight(EditorDrawerPage::Velocity, 0);
    QVERIFY(!view.editorViewState().velocity.height.has_value());

    auto *const toggle =
        fixture.quickRoot->findChild<QQuickItem *>(QStringLiteral("drawerVelocityToggle"));
    QVERIFY(toggle);
    QVERIFY(toggle->property("activeFocusOnTab").toBool());
    toggle->forceActiveFocus(Qt::TabFocusReason);
    sendKey(*toggle, Qt::Key_Space);
    pump();
    QVERIFY(view.drawerSectionVisible(EditorDrawerPage::Velocity));
    QVERIFY(view.drawerSectionVisible(EditorDrawerPage::Automations));
    QCOMPARE(view.drawerActivePage(), EditorDrawerPage::Velocity);
    QVERIFY(fixture.chrome().velocityChecked());
    QVERIFY(fixture.velocityHandle->isVisible());
    QVERIFY(!view.editorViewState().velocity.height.has_value());
}

void DrawerPresentationTest::drawerKeyboardResizeAndHover()
{
    DrawerFixture fixture = makeDrawerFixture();
    SongView &view = *fixture.view;
    fixture.clickToggle(EditorDrawerPage::VoiceChanges);
    DrawerChrome &chrome = fixture.chrome();
    const auto beforeBody = view.editorDrawer()->bodyRect(EditorDrawerPage::VoiceChanges);
    QVERIFY(beforeBody);
    int adjustmentDirection = -1;
    chrome.adjustResizeHandle(static_cast<int>(DrawerChromeTarget::VoiceChangesHandle),
                              adjustmentDirection);
    pump();
    auto afterBody = view.editorDrawer()->bodyRect(EditorDrawerPage::VoiceChanges);
    QVERIFY(afterBody);
    if (afterBody->height() == beforeBody->height()) {
        adjustmentDirection = 1;
        chrome.adjustResizeHandle(static_cast<int>(DrawerChromeTarget::VoiceChangesHandle),
                                  adjustmentDirection);
        pump();
        afterBody = view.editorDrawer()->bodyRect(EditorDrawerPage::VoiceChanges);
        QVERIFY(afterBody);
    }
    QCOMPARE(std::abs(afterBody->height() - beforeBody->height()),
             layout::space(layout::Space::Two));
    chrome.adjustResizeHandle(static_cast<int>(DrawerChromeTarget::VoiceChangesHandle),
                              -adjustmentDirection);
    pump();
    QVERIFY(view.editorDrawer()->bodyRect(EditorDrawerPage::VoiceChanges) == beforeBody);

    const QPointF probe = fixture.voiceHandle->bounds().center();
    sendMouse(*fixture.voiceHandle, QEvent::MouseMove, probe);
    pump();
    QCOMPARE(chrome.hoveredHandle(), static_cast<int>(DrawerChromeTarget::VoiceChangesHandle));
    QCOMPARE(fixture.voiceHandle->cursor().shape(), Qt::SizeVerCursor);
    sendMouse(*fixture.voiceHandle, QEvent::MouseButtonPress, probe, Qt::LeftButton,
              Qt::LeftButton);
    sendMouse(*fixture.voiceHandle, QEvent::MouseButtonRelease, probe, Qt::LeftButton);
    QVERIFY(fixture.voiceHandle->cursor().shape() != Qt::SizeVerCursor);
    sendMouse(*fixture.voiceHandle, QEvent::Leave, {});
    pump();
    QCOMPARE(chrome.hoveredHandle(), -1);
}

void DrawerPresentationTest::drawerStackAndCanonicalInputs()
{
    DrawerFixture fixture = makeDrawerFixture();
    fixture.clickToggle(EditorDrawerPage::Velocity);
    fixture.clickToggle(EditorDrawerPage::VoiceChanges);
    SongView &view = *fixture.view;
    DrawerChrome &chrome = fixture.chrome();
    const QRect voice = fixture.bandRect(songview::TimelineBand::VoiceChanges);
    const QRect velocity = fixture.bandRect(songview::TimelineBand::Velocity);
    const QRect automation = fixture.bandRect(songview::TimelineBand::Automation);
    QVERIFY(voice.y() < velocity.y());
    QVERIFY(velocity.y() < automation.y());
    QVERIFY(chrome.voiceChangesHandleRect().y() < chrome.velocityHandleRect().y());
    QVERIFY(chrome.velocityHandleRect().y() < chrome.automationHandleRect().y());
    QCOMPARE(chrome.automationToggleRect().x(), chrome.voiceChangesToggleRect().x() +
                                                    chrome.voiceChangesToggleRect().width() +
                                                    layout::space(layout::Space::One));
    QCOMPARE(chrome.velocityToggleRect().x(), chrome.automationToggleRect().x() +
                                                  chrome.automationToggleRect().width() +
                                                  layout::space(layout::Space::One));
    QVERIFY(checks::support::physicalInputsMatchCanonical(
        view.timelineBandLayout(), *fixture.quickRoot, songview::TimelineBand::Roll,
        QStringLiteral("timelineRollInput"), QStringLiteral("timelineRollGutterInput")));
    QVERIFY(checks::support::physicalInputsMatchCanonical(
        view.timelineBandLayout(), *fixture.quickRoot, songview::TimelineBand::Velocity,
        QStringLiteral("timelineVelocityInput"), QStringLiteral("timelineVelocityGutterInput")));
    QVERIFY(checks::support::physicalInputsMatchCanonical(
        view.timelineBandLayout(), *fixture.quickRoot, songview::TimelineBand::VoiceChanges,
        QStringLiteral("timelineVoiceChangesInput"),
        QStringLiteral("timelineVoiceChangesGutterInput")));
    QVERIFY(checks::support::physicalInputsMatchCanonical(
        view.timelineBandLayout(), *fixture.quickRoot, songview::TimelineBand::Automation,
        QStringLiteral("timelineAutomationInput"),
        QStringLiteral("timelineAutomationGutterInput")));
    for (const songview::TimelineBand band :
         {songview::TimelineBand::Roll, songview::TimelineBand::Velocity,
          songview::TimelineBand::VoiceChanges, songview::TimelineBand::Automation}) {
        const auto &geometry = view.timelineBandLayout().geometry(band);
        QVERIFY(geometry);
        QCOMPARE(geometry->plotRect.x(), view.timelineSplitX());
        QCOMPARE(geometry->plotRect.right(), geometry->rect.right());
        QCOMPARE(geometry->plotRect.height(), geometry->rect.height());
    }
    QVERIFY(fixture.chrome().automationScrollbarVisible());
    QCOMPARE(fixture.chrome().automationScrollbarRect().top(),
             fixture.bandRect(songview::TimelineBand::Automation).top());
    const QQuickWindow *const quickWindow = fixture.quick->quickWindow();
    QVERIFY(quickWindow);
    const QRectF published = publishedChromeRect(fixture.chrome());
    QVERIFY(!published.isEmpty());
    QVERIFY(QRectF(QPointF{}, QSizeF(quickWindow->size())).contains(published));
}

void DrawerPresentationTest::drawerResizeTransactions_data()
{
    QTest::addColumn<EditorDrawerPage>("page");
    QTest::newRow("voice") << EditorDrawerPage::VoiceChanges;
    QTest::newRow("velocity") << EditorDrawerPage::Velocity;
    QTest::newRow("automation") << EditorDrawerPage::Automations;
}

void DrawerPresentationTest::drawerResizeTransactions()
{
    QFETCH(EditorDrawerPage, page);
    DrawerFixture fixture = makeDrawerFixture();
    fixture.clickToggle(EditorDrawerPage::Velocity);
    fixture.clickToggle(EditorDrawerPage::VoiceChanges);
    SongView &view = *fixture.view;
    EditorDrawer *const drawer = view.editorDrawer();
    auto *const handle = handleFor(fixture, page);
    QVERIFY(handle);
    const int storedBefore = view.drawerSectionHeight(page);
    const auto bodyBefore = drawer->bodyRect(page);
    QVERIFY(bodyBefore);
    const QRect overlay = drawer->overlayRect();
    const QPointF start = handle->bounds().center();
    const QPointF end = start - QPointF(0.0, 32.0);

    QVERIFY(handle->window());
    sendWindowMouse(*handle, QEvent::MouseButtonPress, start, Qt::RightButton, Qt::RightButton);
    sendWindowMouse(*handle, QEvent::MouseMove, end, Qt::NoButton, Qt::RightButton);
    sendWindowMouse(*handle, QEvent::MouseButtonRelease, end, Qt::RightButton);
    QVERIFY(drawer->bodyRect(page) == bodyBefore);
    QCOMPARE(view.drawerSectionHeight(page), storedBefore);

    sendWindowMouse(*handle, QEvent::MouseButtonPress, start, Qt::LeftButton, Qt::LeftButton);
    QCOMPARE(handle->window()->mouseGrabberItem(), handle);
    sendWindowMouse(*handle, QEvent::MouseMove, end, Qt::NoButton, Qt::LeftButton);
    pump();
    const auto liveBody = drawer->bodyRect(page);
    QVERIFY(liveBody);
    QVERIFY(liveBody->height() > bodyBefore->height());
    QCOMPARE(drawer->overlayRect().bottom(), overlay.bottom());
    sendWindowMouse(*handle, QEvent::MouseButtonRelease, end, Qt::LeftButton);
    QVERIFY(!handle->window()->mouseGrabberItem());
    pump();
    QCOMPARE(view.drawerSectionHeight(page), liveBody->height());
    QVERIFY(view.drawerSectionHeight(page) > storedBefore);
    QVERIFY(view.drawerSectionHeight(page) <= drawer->maximumSectionHeight());
    QVERIFY(!fixture.chrome().detentVisible() || page == EditorDrawerPage::Velocity);
}

void DrawerPresentationTest::drawerCollapseAndActivePage()
{
    DrawerFixture fixture = makeDrawerFixture();
    SongView &view = *fixture.view;
    fixture.clickToggle(EditorDrawerPage::Velocity);
    fixture.clickToggle(EditorDrawerPage::VoiceChanges);
    const int voiceHeight = view.drawerSectionHeight(EditorDrawerPage::VoiceChanges);
    fixture.clickToggle(EditorDrawerPage::VoiceChanges);
    QVERIFY(!view.drawerSectionVisible(EditorDrawerPage::VoiceChanges));
    QCOMPARE(view.drawerSectionHeight(EditorDrawerPage::VoiceChanges), voiceHeight);
    const int collapsedVelocityHeight = view.drawerSectionHeight(EditorDrawerPage::Velocity);
    const int collapsedVoiceHeight = view.drawerSectionHeight(EditorDrawerPage::VoiceChanges);
    EditorViewState reloaded = view.editorViewState();
    reloaded.velocity.visible = false;
    reloaded.voiceChanges.visible = false;
    view.applyEditorViewState(reloaded);
    QCOMPARE(view.drawerSectionHeight(EditorDrawerPage::Velocity), collapsedVelocityHeight);
    QCOMPARE(view.drawerSectionHeight(EditorDrawerPage::VoiceChanges), collapsedVoiceHeight);
    fixture.clickToggle(EditorDrawerPage::Automations);
    QVERIFY(!view.hasVisibleDrawerSection());
    QVERIFY(!view.timelineBandLayout().geometry(songview::TimelineBand::Velocity));
    QVERIFY(!view.timelineBandLayout().geometry(songview::TimelineBand::Automation));
    QVERIFY(!view.timelineBandLayout().geometry(songview::TimelineBand::VoiceChanges));
    QVERIFY(view.timelineBandLayout().geometry(songview::TimelineBand::Roll));
    QVERIFY(view.timelineBandLayout().geometry(songview::TimelineBand::OtherEvents));

    DrawerChrome &chrome = fixture.chrome();
    chrome.activateToggle(static_cast<int>(EditorDrawerPage::Velocity));
    chrome.activateToggle(static_cast<int>(EditorDrawerPage::Automations));
    fixture.clickToggle(EditorDrawerPage::Automations);
    QVERIFY(view.drawerSectionVisible(EditorDrawerPage::Velocity));
    QVERIFY(!view.drawerSectionVisible(EditorDrawerPage::Automations));
    QCOMPARE(view.drawerActivePage(), EditorDrawerPage::Automations);
}

void DrawerPresentationTest::drawerFocusFallback()
{
    DrawerFixture fixture = makeDrawerFixture();
    SongView &view = *fixture.view;
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, false);
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, false);
    QVERIFY(view.focusTimelineBand(songview::TimelineBand::Roll, Qt::OtherFocusReason));
    QTRY_VERIFY(view.focusedTimelineBand() &&
                *view.focusedTimelineBand() == songview::TimelineBand::Roll);
    view.editorDrawer()->automationAction()->trigger();
    QTRY_VERIFY(view.focusedTimelineBand() &&
                *view.focusedTimelineBand() == songview::TimelineBand::Roll);
    view.editorDrawer()->velocityAction()->trigger();
    QTRY_VERIFY(view.focusedTimelineBand() &&
                *view.focusedTimelineBand() == songview::TimelineBand::Roll);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    QVERIFY(view.focusTimelineBand(songview::TimelineBand::VoiceChanges, Qt::OtherFocusReason));
    QTRY_VERIFY(view.focusedTimelineBand() &&
                *view.focusedTimelineBand() == songview::TimelineBand::VoiceChanges);
    fixture.clickToggle(EditorDrawerPage::VoiceChanges);
    QTRY_VERIFY(view.focusedTimelineBand() &&
                *view.focusedTimelineBand() == songview::TimelineBand::Velocity);
    fixture.clickToggle(EditorDrawerPage::Velocity);
    QTRY_VERIFY(view.focusedTimelineBand() &&
                *view.focusedTimelineBand() == songview::TimelineBand::Automation);
    fixture.clickToggle(EditorDrawerPage::Automations);
    QTRY_VERIFY(view.focusedTimelineBand() &&
                *view.focusedTimelineBand() == songview::TimelineBand::Roll);
}

void DrawerPresentationTest::drawerHostClampAndHeaderRouting()
{
    DrawerFixture fixture = makeDrawerFixture();
    SongView &view = *fixture.view;
    EditorDrawer *const drawer = view.editorDrawer();
    const QRect rollBefore = fixture.bandRect(songview::TimelineBand::Roll);
    const QRect hostBounds = rollBefore.united(drawer->overlayRect());
    const auto &rollGeometry = view.timelineBandLayout().geometry(songview::TimelineBand::Roll);
    QVERIFY(!hostBounds.isEmpty());
    QVERIFY(rollGeometry);
    const int fixedSpan = rollGeometry->plotRect.x() - rollGeometry->rect.x();
    drawer->setHostBounds(QRect(hostBounds.left(), hostBounds.top(),
                                std::max(0, fixedSpan - layout::singlePixel()),
                                hostBounds.height()));
    QCOMPARE(drawer->plotWidth(), 0);
    QCOMPARE(fixture.bandRect(songview::TimelineBand::Roll).top(), rollBefore.top());
    QCOMPARE(fixture.bandRect(songview::TimelineBand::Roll).height(), rollBefore.height());
    drawer->setHostBounds(fixture.bandRect(songview::TimelineBand::Roll));
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    pump();
    drawer->setHostBounds(QRect(hostBounds.left(), hostBounds.top(), hostBounds.width(),
                                drawer->minimumSectionHeight()));
    pump();
    const auto voice = drawer->bodyRect(EditorDrawerPage::VoiceChanges);
    const auto velocity = drawer->bodyRect(EditorDrawerPage::Velocity);
    const auto automation = drawer->bodyRect(EditorDrawerPage::Automations);
    QVERIFY(voice);
    QVERIFY(velocity);
    QVERIFY(automation);
    QVERIFY(voice->height() >= 0);
    QVERIFY(velocity->height() >= 0);
    QVERIFY(automation->height() >= 0);
    QVERIFY(voice->bottom() <= velocity->top());
    QVERIFY(velocity->bottom() <= automation->top());
    drawer->setHostBounds(hostBounds);

    auto *const headers =
        view.findChild<songview::TrackHeaderModel *>(QStringLiteral("trackHeaderModel"));
    auto *const input = fixture.quickRoot->findChild<songview::TimelineInputItem *>(
        QStringLiteral("timelineTrackHeadersInput"));
    QVERIFY(headers);
    QVERIFY(input);
    QVERIFY(input->window());
    QCOMPARE(headers->rowCount(), 16);
    const QModelIndex index = headers->index(0, 0);
    const QPointF point =
        headers->data(index, songview::TrackHeaderModel::TitleRectRole).toRectF().center();
    QVERIFY(input->bounds().contains(point));
    sendWindowMouse(*input, QEvent::MouseButtonPress, point, Qt::LeftButton, Qt::LeftButton);
    QCOMPARE(input->window()->mouseGrabberItem(), input);
    sendWindowMouse(*input, QEvent::MouseButtonRelease, point, Qt::LeftButton);
    QVERIFY(!input->window()->mouseGrabberItem());
    pump();
    QCOMPARE(view.selectionModel().primaryTrack(),
             headers->data(index, songview::TrackHeaderModel::TrackRole).toInt());
    auto *const automationGutter = fixture.quickRoot->findChild<songview::TimelineInputItem *>(
        QStringLiteral("timelineAutomationGutterInput"));
    QVERIFY(automationGutter);
    pump();
    const QRect automationBand = fixture.bandRect(songview::TimelineBand::Automation);
    QVERIFY(automationGutter->isVisible());
    QVERIFY(automationGutter->bounds().contains(automationGutter->bounds().center()));
    QVERIFY(automationBand.contains(QPoint(automationBand.left(), automationBand.center().y())));
    QVERIFY(checks::support::quickWindowIsUnmasked(*fixture.quick));
}

int runEditorDrawerCheck(const QStringList &qtArguments)
{
    DrawerPresentationTest test;
    QStringList arguments{QStringLiteral("editor-drawer")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
