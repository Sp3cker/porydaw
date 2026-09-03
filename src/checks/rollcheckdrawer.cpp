#include "core/miditimeline.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/drawerchrome.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timelinebandlayout.h"
#include "ui/songview/trackheadermodel.h"

#include <QAction>
#include <QApplication>
#include <QCoreApplication>
#include <QEvent>
#include <QMouseEvent>
#include <QPalette>
#include <QQuickItem>
#include <QQuickWindow>
#include <QWidget>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <optional>
#include <vector>

#include "checks/rollcheckvoicechange.h"
#include "checks/support/eventsynth.h"
#include "checks/support/timelinequickcheck.h"
#include "ui/layout.h"

int runEditorDrawerCheck(const QString &screenshotPath)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        if (!condition) {
            std::fprintf(stderr, "drawer: FAIL: %s\n", message);
            ++failures;
        }
    };

    SongView view;
    MidiTimeline headerTimeline;
    for (TimelineTrack &track : headerTimeline.tracks)
        track.used = true;
    headerTimeline.usedTrackCount = 16;
    view.setSong(&headerTimeline, nullptr);
    const int plotOrigin = layout::fontPx(17.5 + 13.0 / 3.0);
    view.setObjectName(QStringLiteral("drawerCheckHost"));
    view.resize(std::max(plotOrigin * 2, 640), 480);
    view.show();
    QCoreApplication::processEvents();

    auto *drawer = view.editorDrawer();
    auto *roll = view.findChild<songview::PianoRoll *>();
    const auto rollBandRect = [&view] {
        const std::optional<songview::TimelineBandGeometry> &band =
            view.timelineBandLayout().geometry(songview::TimelineBand::Roll);
        return band ? band->rect : QRect{};
    };
    auto *automationPage = drawer ? drawer->automationPage() : nullptr;
    auto *automationCanvas = automationPage ? automationPage->canvas() : nullptr;
    auto *velocityCanvas = drawer ? drawer->velocityArea() : nullptr;
    auto *voiceCanvas = drawer ? drawer->voiceChangeArea() : nullptr;
    auto *quick = view.findChild<songview::TimelineQuickView *>();
    const songview::TimelineBandLayout &bandLayout = view.timelineBandLayout();
    check(drawer && roll && automationPage && automationCanvas && velocityCanvas && voiceCanvas &&
              quick,
          "concrete SongView did not expose its drawer pages and Quick host");
    if (!drawer || !roll || !automationPage || !automationCanvas || !velocityCanvas ||
        !voiceCanvas || !quick)
        return 1;
    check(drawer->minimumSectionHeight() == layout::fontPx(17.0 / 5.0),
          "drawer minimum body height did not use the compact sizing contract");

    std::vector<QString> statuses;
    std::vector<EditorViewState> publishedStates;
    QObject::connect(&view, &SongView::statusMessage,
                     [&statuses](const QString &status) { statuses.push_back(status); });
    const auto observeState = [&publishedStates, &view] {
        publishedStates.push_back(view.editorViewState());
    };

    const QRect rollBefore = rollBandRect();
    DrawerChrome &chrome = drawer->chrome();
    QQuickItem *const quickRoot = quick->rootObject();
    auto *const voiceHandleInput = quickRoot ? quickRoot->findChild<songview::TimelineInputItem *>(
                                                   QStringLiteral("drawerVoiceChangesHandleInput"))
                                             : nullptr;
    auto *const velocityHandleInput = quickRoot
                                          ? quickRoot->findChild<songview::TimelineInputItem *>(
                                                QStringLiteral("drawerVelocityHandleInput"))
                                          : nullptr;
    auto *const automationHandleInput = quickRoot
                                            ? quickRoot->findChild<songview::TimelineInputItem *>(
                                                  QStringLiteral("drawerAutomationHandleInput"))
                                            : nullptr;
    auto *const voiceResizeHandle =
        quickRoot ? quickRoot->findChild<QQuickItem *>(QStringLiteral("drawerVoiceChangesHandle"))
                  : nullptr;
    auto *const barInput =
        quickRoot
            ? quickRoot->findChild<songview::TimelineInputItem *>(QStringLiteral("drawerBarInput"))
            : nullptr;
    auto *const detentInput = quickRoot ? quickRoot->findChild<songview::TimelineInputItem *>(
                                              QStringLiteral("drawerDetentInput"))
                                        : nullptr;
    auto *const velocityToggle =
        quickRoot ? quickRoot->findChild<QQuickItem *>(QStringLiteral("drawerVelocityToggle"))
                  : nullptr;
    check(quickRoot && quick->quickWindow() && voiceHandleInput && velocityHandleInput &&
              automationHandleInput && voiceResizeHandle && barInput && detentInput &&
              velocityToggle,
          "Quick root did not expose every drawer chrome input and keyboard control");
    if (!quickRoot || !quick->quickWindow() || !voiceHandleInput || !velocityHandleInput ||
        !automationHandleInput || !voiceResizeHandle || !barInput || !detentInput ||
        !velocityToggle)
        return 1;

    auto *const headers = view.findChild<songview::TrackHeaderModel *>(
        QStringLiteral("trackHeaderModel"), Qt::FindDirectChildrenOnly);
    auto *const rulerControls =
        quickRoot->findChild<QQuickItem *>(QStringLiteral("timelineRulerControls"));
    auto *const divisionControl =
        quickRoot->findChild<QQuickItem *>(QStringLiteral("timelineRulerDivisionControl"));
    auto *const feelControl =
        quickRoot->findChild<QQuickItem *>(QStringLiteral("timelineRulerFeelControl"));
    auto *const headerBand =
        quickRoot->findChild<QQuickItem *>(QStringLiteral("timelineQuickTrackHeaders"));
    auto *const headerInput = quickRoot->findChild<songview::TimelineInputItem *>(
        QStringLiteral("timelineTrackHeadersInput"));
    QObject *const headerRows =
        quickRoot->findChild<QObject *>(QStringLiteral("timelineTrackHeaderRows"));
    check(headers && rulerControls && divisionControl && feelControl && headerBand && headerInput &&
              headerRows && checks::support::quickWindowIsUnmasked(*quick),
          "Quick host did not expose TrackHeaders, ruler controls, and an unmasked window");
    if (!headers || !rulerControls || !divisionControl || !feelControl || !headerBand ||
        !headerInput || !headerRows)
        return 1;
    check(view.findChild<QWidget *>(QStringLiteral("timeRulerControls"),
                                    Qt::FindDirectChildrenOnly) == nullptr,
          "ruler controls must not retain a native widget shell");

    const auto chromeInputMatches = [&](songview::TimelineInputItem *input,
                                        const QRectF &songViewRect, bool visible,
                                        DrawerChromeTarget target) {
        return input && input->interaction() == &chrome.interaction(target) &&
               input->isVisible() == visible &&
               input->bounds() == QRectF(QPointF{}, songViewRect.size()) &&
               QRectF(input->mapToItem(quickRoot, QPointF()), input->size()) ==
                   songViewRect.translated(-QPointF(quick->geometry().topLeft()));
    };
    const auto canonicalUnionRect = [&bandLayout, &chrome] {
        return checks::support::canonicalVisibleQuickHostRect(bandLayout, &chrome);
    };

    const auto clickBarToggle = [&](const QRectF &toggleRect) {
        const QPointF localCenter = toggleRect.center() - chrome.barRect().topLeft();
        checks::events::sendMouse(*barInput, QEvent::MouseButtonPress, localCenter, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*barInput, QEvent::MouseButtonRelease, localCenter,
                                  Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    };
    const auto sendKeyStroke = [](QObject &target, int key) {
        checks::events::sendKey(target, QEvent::KeyPress, key, Qt::NoModifier, QString(), false, 1);
        checks::events::sendKey(target, QEvent::KeyRelease, key, Qt::NoModifier, QString(), false,
                                1);
    };
    // Converted drawer bands own no widget: both the canonical rectangle and
    // the Quick input item bounds live in the one host envelope.
    const auto bandInputMatchesCanonical = [&](songview::TimelineBand band, const QString &name) {
        const std::optional<songview::TimelineBandGeometry> &geometry = bandLayout.geometry(band);
        auto *input =
            quickRoot ? quickRoot->findChild<songview::TimelineInputItem *>(name) : nullptr;
        return geometry && input && input->isVisible() &&
               input->bounds() ==
                   QRectF(QPointF{}, QSizeF(geometry->rect.width(), geometry->rect.height())) &&
               QRectF(input->mapToItem(quickRoot, QPointF()), input->size()) ==
                   QRectF(geometry->rect.translated(-quick->geometry().topLeft()));
    };

    check(!chrome.barRect().isEmpty() && !chrome.voiceChangesToggleRect().isEmpty() &&
              !chrome.automationToggleRect().isEmpty() && !chrome.velocityToggleRect().isEmpty() &&
              chrome.barRect().contains(chrome.voiceChangesToggleRect()) &&
              chrome.barRect().contains(chrome.automationToggleRect()) &&
              chrome.barRect().contains(chrome.velocityToggleRect()) &&
              chrome.barBorderWidth() == layout::singlePixel() &&
              chrome.toggleCheckedBackground() == view.palette().color(QPalette::Highlight) &&
              chrome.barBackground().alpha() == 255 && chrome.barOutline().alpha() == 255 &&
              chrome.iconRevision() > 0,
          "drawer chrome snapshot did not publish the Quick bar, toggles, and appearance");
    check(
        chrome.automationHandleVisible() && !chrome.velocityHandleVisible() &&
            !chrome.voiceChangesHandleVisible() && chrome.automationChecked() &&
            !chrome.velocityChecked() && !chrome.voiceChangesChecked() &&
            chromeInputMatches(automationHandleInput, chrome.automationHandleRect(), true,
                               DrawerChromeTarget::AutomationHandle) &&
            chromeInputMatches(barInput, chrome.barRect(), true, DrawerChromeTarget::Bar) &&
            chromeInputMatches(detentInput, chrome.detentRect(), false, DrawerChromeTarget::Detent),
        "drawer Quick chrome inputs did not match the initial snapshot");
    check(view.drawerSectionVisible(EditorDrawerPage::Automations) &&
              !view.drawerSectionVisible(EditorDrawerPage::Velocity) &&
              !view.drawerSectionVisible(EditorDrawerPage::VoiceChanges) &&
              view.drawerActivePage() == EditorDrawerPage::Automations,
          "drawer default did not retain independent automation and velocity state");
    check(drawer->overlayRect().bottom() >= 0 && rollBandRect() == rollBefore &&
              drawer->plotOrigin() == plotOrigin && drawer->plotWidth() > 0,
          "drawer overlay changed the roll geometry or plot origin");
    check(drawer->automationAction()->shortcuts().isEmpty() &&
              drawer->velocityAction()->shortcuts().isEmpty() &&
              drawer->voiceChangesAction()->shortcuts().isEmpty(),
          "drawer actions compete with the window A/V shortcuts");

    view.setDrawerSectionHeight(EditorDrawerPage::Velocity, 0);
    check(!view.editorViewState().velocity.height,
          "zero drawer height did not retain the layout default");

    velocityToggle->forceActiveFocus(Qt::TabFocusReason);
    sendKeyStroke(*velocityToggle, Qt::Key_Space);
    QCoreApplication::processEvents();
    observeState();
    check(view.drawerSectionVisible(EditorDrawerPage::Velocity) &&
              view.drawerSectionVisible(EditorDrawerPage::Automations) &&
              view.drawerActivePage() == EditorDrawerPage::Velocity &&
              !view.editorViewState().velocity.height &&
              bandLayout.geometry(songview::TimelineBand::Velocity) &&
              bandLayout.geometry(songview::TimelineBand::Velocity)->rect.height() > 0 &&
              !publishedStates.empty() && publishedStates.back().velocity.visible &&
              publishedStates.back().automation.visible &&
              publishedStates.back().activePage == EditorDrawerPage::Velocity &&
              !statuses.empty() && statuses.back() == QStringLiteral("Velocity lane shown") &&
              chrome.velocityChecked() &&
              chromeInputMatches(velocityHandleInput, chrome.velocityHandleRect(), true,
                                 DrawerChromeTarget::VelocityHandle),
          "velocity chrome toggle did not preserve the open automation section");
    check(chrome.velocityHandleVisible() && chrome.automationHandleVisible() &&
              !chrome.detentVisible() && chrome.detentRect().isEmpty(),
          "drawer chrome did not expose independent handles or hid the direct-sound detent");
    const std::optional<QRect> velocityBody = drawer->bodyRect(EditorDrawerPage::Velocity);
    check(velocityBody.has_value(), "visible velocity drawer did not publish a SongView body rect");
    if (!velocityBody)
        return 1;
    clickBarToggle(chrome.velocityToggleRect());
    QCoreApplication::processEvents();
    check(!view.drawerSectionVisible(EditorDrawerPage::Velocity) && !chrome.velocityChecked(),
          "hiding velocity with its Quick toggle did not update the chrome snapshot");
    clickBarToggle(chrome.velocityToggleRect());
    QCoreApplication::processEvents();
    check(view.drawerSectionVisible(EditorDrawerPage::Velocity) && chrome.velocityChecked(),
          "visible Quick velocity toggle did not reopen the velocity pane");
    // The third page: the Quick bar toggles only Voice Changes, keeps the
    // other two open, and announces through the same status surface.
    clickBarToggle(chrome.voiceChangesToggleRect());
    QCoreApplication::processEvents();
    observeState();
    check(view.drawerSectionVisible(EditorDrawerPage::VoiceChanges) &&
              view.drawerSectionVisible(EditorDrawerPage::Velocity) &&
              view.drawerSectionVisible(EditorDrawerPage::Automations) &&
              view.drawerActivePage() == EditorDrawerPage::VoiceChanges &&
              bandLayout.geometry(songview::TimelineBand::VoiceChanges).has_value() &&
              publishedStates.back().voiceChanges.visible &&
              publishedStates.back().activePage == EditorDrawerPage::VoiceChanges &&
              !statuses.empty() && statuses.back() == QStringLiteral("Voice changes shown") &&
              chrome.voiceChangesChecked(),
          "voice changes chrome toggle did not preserve the open automation and velocity sections");
    check(chrome.voiceChangesHandleVisible() && chrome.velocityHandleVisible() &&
              chrome.automationHandleVisible() &&
              chromeInputMatches(voiceHandleInput, chrome.voiceChangesHandleRect(), true,
                                 DrawerChromeTarget::VoiceChangesHandle) &&
              chromeInputMatches(velocityHandleInput, chrome.velocityHandleRect(), true,
                                 DrawerChromeTarget::VelocityHandle) &&
              chromeInputMatches(automationHandleInput, chrome.automationHandleRect(), true,
                                 DrawerChromeTarget::AutomationHandle) &&
              chromeInputMatches(barInput, chrome.barRect(), true, DrawerChromeTarget::Bar),
          "all three drawer handles did not follow the Quick chrome snapshot");
    check(bandInputMatchesCanonical(songview::TimelineBand::VoiceChanges,
                                    QStringLiteral("timelineVoiceChangesInput")),
          "voice changes input item did not fill its canonical Quick band");
    QCoreApplication::processEvents();
    check(checks::support::quickWindowIsUnmasked(*quick) &&
              quick->geometry() == canonicalUnionRect(),
          "the unmasked Quick window did not frame the canonical drawer host envelope");
    check(chrome.handleColor().alpha() == 255 && chrome.handleHoverColor().alpha() == 255 &&
              chrome.handleColor() != chrome.handleHoverColor() && chrome.iconRevision() > 0,
          "drawer chrome snapshot lost its opaque handle colors or icons");

    const std::optional<int> storedVoiceHeightBeforeAdjustment =
        view.editorViewState().voiceChanges.height;
    const int voiceHeightBeforeAdjustment =
        drawer->bodyRect(EditorDrawerPage::VoiceChanges)->height();
    check(voiceResizeHandle->property("activeFocusOnTab").toBool(),
          "voice resize grip was not reachable from the keyboard focus chain");
    chrome.adjustResizeHandle(static_cast<int>(DrawerChromeTarget::VoiceChangesHandle), -1);
    QCoreApplication::processEvents();
    int adjustmentDirection = -1;
    int voiceHeightAfterAdjustment = drawer->bodyRect(EditorDrawerPage::VoiceChanges)->height();
    if (voiceHeightAfterAdjustment == voiceHeightBeforeAdjustment) {
        adjustmentDirection = 1;
        chrome.adjustResizeHandle(static_cast<int>(DrawerChromeTarget::VoiceChangesHandle), 1);
        QCoreApplication::processEvents();
        voiceHeightAfterAdjustment = drawer->bodyRect(EditorDrawerPage::VoiceChanges)->height();
    }
    check(std::abs(voiceHeightAfterAdjustment - voiceHeightBeforeAdjustment) ==
              layout::space(layout::Space::Two),
          "accessible resize adjustment did not move the voice section by one keyboard step");
    chrome.adjustResizeHandle(static_cast<int>(DrawerChromeTarget::VoiceChangesHandle),
                              -adjustmentDirection);
    QCoreApplication::processEvents();
    check(drawer->bodyRect(EditorDrawerPage::VoiceChanges)->height() == voiceHeightBeforeAdjustment,
          "opposite accessible resize adjustment did not restore the voice section");
    view.setDrawerSectionHeight(EditorDrawerPage::VoiceChanges, storedVoiceHeightBeforeAdjustment);
    QCoreApplication::processEvents();

    const QPointF voiceHandleProbe = voiceHandleInput->bounds().center();
    checks::events::sendMouse(*voiceHandleInput, QEvent::MouseMove, voiceHandleProbe, Qt::NoButton,
                              Qt::NoButton, Qt::NoModifier);
    QCoreApplication::processEvents();
    check(chrome.hoveredHandle() == static_cast<int>(DrawerChromeTarget::VoiceChangesHandle) &&
              voiceHandleInput->cursor().shape() == Qt::SizeVerCursor,
          "Quick resize handle did not expose its resize cursor and hover state");
    checks::events::sendMouse(*voiceHandleInput, QEvent::MouseButtonPress, voiceHandleProbe,
                              Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*voiceHandleInput, QEvent::MouseButtonRelease, voiceHandleProbe,
                              Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    check(voiceHandleInput->cursor().shape() != Qt::SizeVerCursor,
          "Quick resize handle retained its resize cursor after a click");
    checks::events::sendMouse(*voiceHandleInput, QEvent::Leave, QPointF{}, Qt::NoButton,
                              Qt::NoButton, Qt::NoModifier);
    check(chrome.hoveredHandle() == -1 && voiceHandleInput->cursor().shape() != Qt::SizeVerCursor,
          "Quick resize handle did not restore its inherited cursor after hover");
    check(!chrome.detentVisible() && chrome.detentRect().isEmpty(),
          "showing voice changes exposed the direct-sound velocity detent");

    // Stack order: voice handle/body above velocity above automation; the
    // full toggle row reads VoiceChanges, Automations, Velocity left to right
    // and remains centered in the Velocity piano-key region.
    const QRectF voiceToggleBounds = chrome.voiceChangesToggleRect();
    const QRectF automationToggleBounds = chrome.automationToggleRect();
    const QRectF velocityToggleBounds = chrome.velocityToggleRect();
    const QRectF toggleGroup =
        voiceToggleBounds.united(automationToggleBounds).united(velocityToggleBounds);
    const int pianoKeysCenter = velocityBody->x() + velocityCanvas->plotOrigin() / 2;
    check(bandLayout.geometry(songview::TimelineBand::VoiceChanges)->rect.y() <
                  bandLayout.geometry(songview::TimelineBand::Velocity)->rect.y() &&
              bandLayout.geometry(songview::TimelineBand::Velocity)->rect.y() <
                  bandLayout.geometry(songview::TimelineBand::Automation)->rect.y(),
          "drawer stack did not order voice changes above velocity above automation");
    check(chrome.voiceChangesHandleRect().y() < chrome.velocityHandleRect().y() &&
              chrome.velocityHandleRect().y() < chrome.automationHandleRect().y(),
          "Quick resize handles did not follow the voice/velocity/automation stack order");
    check(voiceToggleBounds.x() + voiceToggleBounds.width() + layout::space(layout::Space::One) ==
                  automationToggleBounds.x() &&
              automationToggleBounds.x() + automationToggleBounds.width() +
                      layout::space(layout::Space::One) ==
                  velocityToggleBounds.x() &&
              voiceToggleBounds.y() == automationToggleBounds.y() &&
              automationToggleBounds.y() == velocityToggleBounds.y() &&
              std::abs(toggleGroup.center().x() - pianoKeysCenter) <= 1,
          "drawer Quick toggle row was not centered voice changes, automations, velocity");

    const int voiceHeightBefore = view.drawerSectionHeight(EditorDrawerPage::VoiceChanges);
    const int voiceBodyHeightBefore =
        bandLayout.geometry(songview::TimelineBand::VoiceChanges)->rect.height();
    const int velocityHeightAtVoice = view.drawerSectionHeight(EditorDrawerPage::Velocity);
    const int automationHeightAtVoice = view.drawerSectionHeight(EditorDrawerPage::Automations);
    const QPointF voiceHandleCenter = voiceHandleInput->bounds().center();
    checks::events::sendMouse(*voiceHandleInput, QEvent::MouseButtonPress, voiceHandleCenter,
                              Qt::RightButton, Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(*voiceHandleInput, QEvent::MouseMove,
                              voiceHandleCenter - QPointF(0.0, 40.0), Qt::NoButton, Qt::RightButton,
                              Qt::NoModifier);
    checks::events::sendMouse(*voiceHandleInput, QEvent::MouseButtonRelease,
                              voiceHandleCenter - QPointF(0.0, 40.0), Qt::RightButton, Qt::NoButton,
                              Qt::NoModifier);
    check(view.drawerSectionHeight(EditorDrawerPage::VoiceChanges) == voiceHeightBefore,
          "right drag resized the voice changes section");
    const int overlayBottomBeforeVoiceResize = drawer->overlayRect().bottom();
    const QPointF voiceResizeGlobal =
        voiceHandleInput->mapToGlobal(voiceHandleCenter - QPointF(0.0, 40.0));
    checks::events::sendMouse(*voiceHandleInput, QEvent::MouseButtonPress, voiceHandleCenter,
                              Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*voiceHandleInput, QEvent::MouseMove,
                              voiceHandleCenter - QPointF(0.0, 40.0), Qt::NoButton, Qt::LeftButton,
                              Qt::NoModifier);
    QCoreApplication::processEvents();
    const int voiceBodyHeightAfterMove =
        bandLayout.geometry(songview::TimelineBand::VoiceChanges)->rect.height();
    check(voiceBodyHeightAfterMove > voiceBodyHeightBefore,
          "voice changes drag did not grow the live section");
    checks::events::sendMouse(*voiceHandleInput, QEvent::MouseButtonRelease,
                              voiceHandleInput->mapFromGlobal(voiceResizeGlobal), Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    QCoreApplication::processEvents();
    check(voiceHandleInput->cursor().shape() != Qt::SizeVerCursor,
          "Quick resize handle retained its cursor after an outside release");
    const int voiceHeightAfter = view.drawerSectionHeight(EditorDrawerPage::VoiceChanges);
    check(voiceHeightAfter == voiceBodyHeightAfterMove &&
              voiceHeightAfter <= drawer->maximumSectionHeight() &&
              view.drawerSectionHeight(EditorDrawerPage::Velocity) == velocityHeightAtVoice &&
              view.drawerSectionHeight(EditorDrawerPage::Automations) == automationHeightAtVoice &&
              drawer->overlayRect().bottom() == overlayBottomBeforeVoiceResize,
          "voice changes drag did not persist its height with the overlay bottom pinned");
    check(bandLayout.geometry(songview::TimelineBand::VoiceChanges)->rect.y() <
                  bandLayout.geometry(songview::TimelineBand::Velocity)->rect.y() &&
              bandLayout.geometry(songview::TimelineBand::VoiceChanges)->rect.height() > 0,
          "voice changes resize broke the drawer stack geometry");
    check(!chrome.detentVisible(), "resizing voice changes exposed the velocity detent");
    const auto canonicalAutomationMatches = [&] {
        const std::optional<songview::TimelineBandGeometry> &geometry =
            bandLayout.geometry(songview::TimelineBand::Automation);
        const std::optional<QRect> body = drawer->bodyRect(EditorDrawerPage::Automations);
        const int scrollbarWidth = layout::space(layout::Space::Two);
        return geometry && body &&
               geometry->rect == QRect(body->x() + scrollbarWidth, body->y(),
                                       std::max(0, body->width() - scrollbarWidth), body->height());
    };
    const std::optional<QRect> voiceBody = drawer->bodyRect(EditorDrawerPage::VoiceChanges);
    check(voiceBody && bandLayout.geometry(songview::TimelineBand::VoiceChanges) &&
              *voiceBody == bandLayout.geometry(songview::TimelineBand::VoiceChanges)->rect,
          "drawer body rectangle did not stay SongView-local after the resize");
    check(bandInputMatchesCanonical(songview::TimelineBand::Roll,
                                    QStringLiteral("timelineRollInput")) &&
              bandInputMatchesCanonical(songview::TimelineBand::Velocity,
                                        QStringLiteral("timelineVelocityInput")) &&
              canonicalAutomationMatches() &&
              bandInputMatchesCanonical(songview::TimelineBand::Automation,
                                        QStringLiteral("timelineAutomationInput")) &&
              bandInputMatchesCanonical(songview::TimelineBand::VoiceChanges,
                                        QStringLiteral("timelineVoiceChangesInput")),
          "canonical layout should track the resized drawer section rectangles");
    check(bandLayout.geometry(songview::TimelineBand::VoiceChanges) &&
              bandLayout.geometry(songview::TimelineBand::VoiceChanges)->timelineOrigin ==
                  voiceCanvas->plotOrigin() &&
              bandLayout.geometry(songview::TimelineBand::Velocity) &&
              bandLayout.geometry(songview::TimelineBand::Velocity)->timelineOrigin ==
                  velocityCanvas->plotOrigin(),
          "canonical drawer entries should carry the drawer plot origins");
    // After a resize drag the unmasked Quick host still frames the union of
    // canonical bands and chrome rectangles.
    check(quick->geometry() == canonicalUnionRect() &&
              checks::support::quickWindowIsUnmasked(*quick),
          "drawer resize did not keep the unmasked Quick host frame current");

    clickBarToggle(chrome.voiceChangesToggleRect());
    QCoreApplication::processEvents();
    observeState();
    check(!view.drawerSectionVisible(EditorDrawerPage::VoiceChanges) &&
              view.drawerSectionVisible(EditorDrawerPage::Velocity) &&
              view.drawerSectionVisible(EditorDrawerPage::Automations) &&
              view.drawerActivePage() == EditorDrawerPage::VoiceChanges &&
              !chrome.voiceChangesChecked() &&
              view.editorViewState().voiceChanges.height == voiceHeightAfter && !statuses.empty() &&
              statuses.back() == QStringLiteral("Voice changes hidden"),
          "hiding voice changes changed the other sections or lost its retained height");
    clickBarToggle(chrome.voiceChangesToggleRect());
    QCoreApplication::processEvents();
    check(view.drawerSectionVisible(EditorDrawerPage::VoiceChanges) &&
              chrome.voiceChangesChecked() &&
              view.drawerSectionHeight(EditorDrawerPage::VoiceChanges) == voiceHeightAfter,
          "voice changes Quick toggle did not reopen with its retained height");
    clickBarToggle(chrome.voiceChangesToggleRect());
    QCoreApplication::processEvents();
    check(!view.drawerSectionVisible(EditorDrawerPage::VoiceChanges) &&
              !chrome.voiceChangesChecked(),
          "voice changes Quick toggle did not close its own section");

    const int velocityHeightBefore = view.drawerSectionHeight(EditorDrawerPage::Velocity);
    const QPointF velocityHandleCenter = velocityHandleInput->bounds().center();
    checks::events::sendMouse(*velocityHandleInput, QEvent::MouseButtonPress, velocityHandleCenter,
                              Qt::RightButton, Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(*velocityHandleInput, QEvent::MouseMove,
                              velocityHandleCenter - QPointF(0.0, 40.0), Qt::NoButton,
                              Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(*velocityHandleInput, QEvent::MouseButtonRelease,
                              velocityHandleCenter - QPointF(0.0, 40.0), Qt::RightButton,
                              Qt::NoButton, Qt::NoModifier);
    check(view.drawerSectionHeight(EditorDrawerPage::Velocity) == velocityHeightBefore,
          "right drag resized the velocity section");

    const QRect overlayBeforeVelocityResize = drawer->overlayRect();
    const QPointF velocityResizeGlobal =
        velocityHandleInput->mapToGlobal(velocityHandleCenter - QPointF(0.0, 40.0));
    checks::events::sendMouse(*velocityHandleInput, QEvent::MouseButtonPress, velocityHandleCenter,
                              Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*velocityHandleInput, QEvent::MouseMove,
                              velocityHandleCenter - QPointF(0.0, 40.0), Qt::NoButton,
                              Qt::LeftButton, Qt::NoModifier);
    QCoreApplication::processEvents();
    check(drawer->overlayRect().bottom() == overlayBeforeVelocityResize.bottom() &&
              drawer->overlayRect().top() < overlayBeforeVelocityResize.top(),
          "velocity drawer resized downward instead of moving its top edge");
    checks::events::sendMouse(*velocityHandleInput, QEvent::MouseButtonRelease,
                              velocityHandleInput->mapFromGlobal(velocityResizeGlobal),
                              Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    QCoreApplication::processEvents();
    const int velocityHeightAfter = view.drawerSectionHeight(EditorDrawerPage::Velocity);
    check(velocityHeightAfter > 0 && velocityHeightAfter <= drawer->maximumSectionHeight(),
          "left velocity drag did not persist its independent height");

    const int automationHeightBefore = view.drawerSectionHeight(EditorDrawerPage::Automations);
    const QPointF automationHandleCenter = automationHandleInput->bounds().center();
    const QPointF automationResizeGlobal =
        automationHandleInput->mapToGlobal(automationHandleCenter - QPointF(0.0, 30.0));
    checks::events::sendMouse(*automationHandleInput, QEvent::MouseButtonPress,
                              automationHandleCenter, Qt::LeftButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(*automationHandleInput, QEvent::MouseMove,
                              automationHandleCenter - QPointF(0.0, 30.0), Qt::NoButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*automationHandleInput, QEvent::MouseButtonRelease,
                              automationHandleInput->mapFromGlobal(automationResizeGlobal),
                              Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    QCoreApplication::processEvents();
    check(view.drawerSectionHeight(EditorDrawerPage::Automations) > automationHeightBefore &&
              view.drawerSectionHeight(EditorDrawerPage::Velocity) == velocityHeightAfter,
          "automation drag did not preserve the independent velocity height");

    clickBarToggle(chrome.velocityToggleRect());
    QCoreApplication::processEvents();
    observeState();
    check(!view.drawerSectionVisible(EditorDrawerPage::Velocity) &&
              view.drawerSectionVisible(EditorDrawerPage::Automations) &&
              view.drawerActivePage() == EditorDrawerPage::Velocity && !chrome.velocityChecked() &&
              publishedStates.back().automation.visible && !statuses.empty() &&
              statuses.back() == QStringLiteral("Velocity lane hidden"),
          "collapsing velocity changed automation or the chrome active-page state");

    clickBarToggle(chrome.automationToggleRect());
    QCoreApplication::processEvents();
    observeState();
    check(!view.hasVisibleDrawerSection() &&
              view.drawerActivePage() == EditorDrawerPage::Automations && !statuses.empty() &&
              statuses.back() == QStringLiteral("Automation lanes hidden") &&
              !chrome.velocityChecked() && !chrome.automationChecked() &&
              !chrome.voiceChangesChecked() && !chrome.velocityHandleVisible() &&
              !chrome.automationHandleVisible() && !chrome.voiceChangesHandleVisible(),
          "automation chrome toggle did not collapse every drawer surface");
    check(!bandLayout.geometry(songview::TimelineBand::Velocity) &&
              !bandLayout.geometry(songview::TimelineBand::Automation) &&
              !bandLayout.geometry(songview::TimelineBand::VoiceChanges) &&
              !drawer->bodyRect(EditorDrawerPage::Velocity) &&
              !drawer->bodyRect(EditorDrawerPage::Automations) &&
              !drawer->bodyRect(EditorDrawerPage::VoiceChanges) &&
              bandLayout.geometry(songview::TimelineBand::Ruler) &&
              bandLayout.geometry(songview::TimelineBand::Roll) &&
              bandLayout.geometry(songview::TimelineBand::OtherEvents),
          "a fully collapsed drawer must clear every canonical drawer entry");

    chrome.activateToggle(static_cast<int>(EditorDrawerPage::Velocity));
    chrome.activateToggle(static_cast<int>(EditorDrawerPage::Automations));
    QCoreApplication::processEvents();
    clickBarToggle(chrome.automationToggleRect());
    QCoreApplication::processEvents();
    check(view.drawerSectionVisible(EditorDrawerPage::Velocity) &&
              !view.drawerSectionVisible(EditorDrawerPage::Automations) &&
              view.drawerActivePage() == EditorDrawerPage::Automations &&
              chrome.velocityChecked() && !chrome.automationChecked(),
          "DrawerChrome toggle API coupled active page to section visibility");
    check(bandInputMatchesCanonical(songview::TimelineBand::Velocity,
                                    QStringLiteral("timelineVelocityInput")) &&
              !bandLayout.geometry(songview::TimelineBand::Automation),
          "reopening a drawer section must republish only its canonical rectangle");
    check(quick->geometry() == canonicalUnionRect() &&
              checks::support::quickWindowIsUnmasked(*quick),
          "reopening a drawer section did not keep the unmasked Quick host frame current");

    EditorViewState restoredClose = view.editorViewState();
    restoredClose.velocity.visible = false;
    restoredClose.automation.visible = false;
    view.applyEditorViewState(restoredClose);
    observeState();
    check(!view.hasVisibleDrawerSection() &&
              view.editorViewState().velocity.height == velocityHeightAfter &&
              view.editorViewState().automation.height > automationHeightBefore,
          "state reload did not retain collapsed section heights");

    view.activateWindow();
    // Direct Quick focus requests need deterministic widget-window activation
    // in this synthetic top-level SongView harness.
    QT_WARNING_PUSH
    QT_WARNING_DISABLE_DEPRECATED
    QApplication::setActiveWindow(&view);
    QT_WARNING_POP
    view.focusContent();
    QCoreApplication::processEvents();
    QWidget *contentFocus = QApplication::focusWidget();
    drawer->automationAction()->trigger();
    QCoreApplication::processEvents();
    check(contentFocus && QApplication::focusWidget() == contentFocus,
          "opening automation moved focus away from the editor hotkey surface");
    drawer->automationAction()->trigger();
    drawer->velocityAction()->trigger();
    QCoreApplication::processEvents();
    check(QApplication::focusWidget() == contentFocus,
          "opening velocity moved focus away from the editor hotkey surface");
    // Focus fallback walks the visual order VoiceChanges, Velocity,
    // Automations when the focused page hides, and returns to content when
    // the last page goes.
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    QCoreApplication::processEvents();
    view.focusTimelineBand(songview::TimelineBand::VoiceChanges, Qt::MouseFocusReason);
    // Quick delivers activation asynchronously: let one event turn run
    // before reading the live active-focus band.
    QCoreApplication::processEvents();
    check(view.focusedTimelineBand() == songview::TimelineBand::VoiceChanges,
          "voice changes focus bridge did not focus the Quick input item");
    drawer->voiceChangesAction()->trigger();
    QCoreApplication::processEvents();
    check(!view.drawerSectionVisible(EditorDrawerPage::VoiceChanges) &&
              view.focusedTimelineBand() == songview::TimelineBand::Velocity,
          "hiding the focused voice page did not focus the velocity page");
    view.focusTimelineBand(songview::TimelineBand::Velocity, Qt::MouseFocusReason);
    QCoreApplication::processEvents();
    drawer->velocityAction()->trigger();
    QCoreApplication::processEvents();
    check(!view.drawerSectionVisible(EditorDrawerPage::Velocity) &&
              view.focusedTimelineBand() == songview::TimelineBand::Automation,
          "hiding the focused velocity page did not focus the automation page");
    drawer->automationAction()->trigger();
    QCoreApplication::processEvents();
    QWidget *contentFallback = QApplication::focusWidget();
    check(!view.hasVisibleDrawerSection() &&
              view.focusedTimelineBand() == songview::TimelineBand::Roll && contentFallback &&
              (contentFallback == &view || view.isAncestorOf(contentFallback)),
          "hiding the last drawer page did not return focus to content");

    const QRect rollBeforeNarrow = rollBandRect();
    const QRect hostBounds = rollBeforeNarrow.united(drawer->overlayRect());
    check(!hostBounds.isEmpty(), "drawer did not retain a SongView-local host bounds rectangle");
    const int narrowWidth = std::max(0, drawer->plotOrigin() - layout::singlePixel());
    const QRect narrowBounds(hostBounds.left(), hostBounds.top(), narrowWidth, hostBounds.height());
    drawer->setHostBounds(narrowBounds);
    check(drawer->plotWidth() == 0 && rollBandRect().top() == rollBeforeNarrow.top() &&
              rollBandRect().height() == rollBeforeNarrow.height(),
          "narrow drawer changed the roll geometry");
    // Vertical host clamp: with all three pages open, a too-short host must
    // never produce negative geometry and must keep the stack order.
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    QCoreApplication::processEvents();
    const QRect shortBounds(hostBounds.left(), hostBounds.top(), hostBounds.width(),
                            drawer->minimumSectionHeight());
    drawer->setHostBounds(shortBounds);
    QCoreApplication::processEvents();
    const std::optional<QRect> shortVoiceBody = drawer->bodyRect(EditorDrawerPage::VoiceChanges);
    const std::optional<QRect> shortVelocityBody = drawer->bodyRect(EditorDrawerPage::Velocity);
    const std::optional<QRect> shortAutomationBody =
        drawer->bodyRect(EditorDrawerPage::Automations);
    check(shortVoiceBody && shortVelocityBody && shortAutomationBody &&
              shortVoiceBody->height() >= 0 && shortVelocityBody->height() >= 0 &&
              shortAutomationBody->height() >= 0 && shortVoiceBody->y() <= shortVelocityBody->y() &&
              shortVelocityBody->y() <= shortAutomationBody->y(),
          "short host clamp produced negative or unordered drawer geometry");
    drawer->useParentBounds();
    QCoreApplication::processEvents();
    const std::optional<songview::TimelineBandGeometry> &headerGeometry =
        bandLayout.geometry(songview::TimelineBand::TrackHeaders);
    const std::optional<songview::TimelineBandGeometry> &rollGeometry =
        bandLayout.geometry(songview::TimelineBand::Roll);
    const std::optional<QRect> automationBody = drawer->bodyRect(EditorDrawerPage::Automations);
    const bool headerQuickGeometry =
        headerGeometry && headerBand->isVisible() && headerInput->isVisible() &&
        headerInput->interaction() == headers &&
        QRectF(headerBand->mapToItem(quickRoot, QPointF()), headerBand->size()) ==
            QRectF(headerGeometry->rect.translated(-quick->geometry().topLeft())) &&
        headerInput->width() + headers->scrollbarWidth() == headerGeometry->rect.width() &&
        headerInput->height() == headerGeometry->rect.height() &&
        headerRows->property("count").toInt() == headers->rowCount();
    check(headerQuickGeometry,
          "TrackHeaders did not publish the canonical model-backed Quick geometry");

    int targetRow = -1;
    int targetTrack = -1;
    int previousTrack = -1;
    int addRows = 0;
    bool orderedHeaderRows = headers->rowCount() == 16;
    for (int row = 0; row < headers->rowCount(); ++row) {
        const QModelIndex index = headers->index(row, 0);
        const bool isAdd =
            headers->data(index, songview::TrackHeaderModel::IsAddTrackRole).toBool();
        if (isAdd) {
            ++addRows;
            orderedHeaderRows &= row == headers->rowCount() - 1;
            continue;
        }
        const int track = headers->data(index, songview::TrackHeaderModel::TrackRole).toInt();
        orderedHeaderRows &= addRows == 0 && track > previousTrack;
        previousTrack = track;
        if (targetRow < 0) {
            targetRow = row;
            targetTrack = track;
        }
    }
    orderedHeaderRows &= addRows == 0 && targetTrack >= 0;
    check(orderedHeaderRows,
          "document-less drawer fixture should expose 16 ordered TrackHeaderModel rows without "
          "an add row; document-backed host/windowing checks own add-row ordering coverage");

    bool headerPointInOwningBand = false;
    bool headerPointAlignedWithRoll = false;
    bool rollHeaderInputGrabbed = false;
    bool rollHeaderClicked = false;
    if (headerQuickGeometry && targetRow >= 0 && targetTrack >= 0) {
        view.selectTrack(targetTrack == 0 ? 1 : 0);
        headers->setScrollY(qreal(targetRow * headers->rowHeight()));
        QCoreApplication::processEvents();
        const QModelIndex targetIndex = headers->index(targetRow, 0);
        const QRectF titleRect =
            headers->data(targetIndex, songview::TrackHeaderModel::TitleRectRole).toRectF();
        const QPointF headerPosition =
            titleRect.center() +
            QPointF(0.0, targetRow * headers->rowHeight() - headers->scrollY());
        const QPointF rootPosition = headerInput->mapToItem(quickRoot, headerPosition);
        const QPoint songViewPosition = quick->geometry().topLeft() + rootPosition.toPoint();
        headerPointInOwningBand = headerGeometry && headerGeometry->rect.contains(songViewPosition);
        headerPointAlignedWithRoll = rollGeometry &&
                                     songViewPosition.y() >= rollGeometry->rect.top() &&
                                     songViewPosition.y() <= rollGeometry->rect.bottom();
        if (titleRect.isEmpty() || !headerInput->bounds().contains(headerPosition)) {
            check(false, "TrackHeaderModel did not publish a clickable Quick title region");
        } else {
            QQuickWindow *const window = quick->quickWindow();
            const auto sendHeaderWindowMouse = [&](QEvent::Type type, const QPointF &position,
                                                   Qt::MouseButton button,
                                                   Qt::MouseButtons buttons) {
                const QPointF windowPosition = headerInput->mapToScene(position);
                QMouseEvent event(type, windowPosition,
                                  QPointF(window->mapToGlobal(windowPosition.toPoint())), button,
                                  buttons, Qt::NoModifier);
                QCoreApplication::sendEvent(window, &event);
            };
            sendHeaderWindowMouse(QEvent::MouseButtonPress, headerPosition, Qt::LeftButton,
                                  Qt::LeftButton);
            rollHeaderInputGrabbed = window->mouseGrabberItem() == headerInput;
            sendHeaderWindowMouse(QEvent::MouseButtonRelease, headerPosition, Qt::LeftButton,
                                  Qt::NoButton);
            QCoreApplication::processEvents();
            rollHeaderClicked = view.selectionModel().primaryTrack() == targetTrack;
        }
    }
    check(rollGeometry.has_value(),
          "drawer hit-test fixture did not expose the canonical Roll band");
    check(headerPointInOwningBand,
          "Quick TrackHeaders did not expose a clickable title point in its owning band");
    check(headerPointAlignedWithRoll,
          "Quick TrackHeaders title point was not vertically aligned with the Roll band");
    check(rollHeaderInputGrabbed,
          "real QQuickWindow input did not target the TrackHeaders input item");
    check(rollHeaderClicked, "Quick track header click did not select its model track");
    check(automationBody.has_value(),
          "drawer hit-test fixture did not expose the automation label gutter");
    const QPoint automationGutterProbe =
        automationBody && headerGeometry
            ? QPoint(headerGeometry->rect.center().x(), automationBody->center().y())
            : QPoint{};
    const bool automationGutterVisible =
        automationBody && headerGeometry && headerGeometry->rect.contains(automationGutterProbe) &&
        headerBand->isVisible() &&
        headerBand->contains(headerBand->mapFromItem(
            quickRoot, QPointF(automationGutterProbe - quick->geometry().topLeft()))) &&
        checks::support::quickWindowIsUnmasked(*quick);
    check(automationGutterVisible,
          "visible Quick TrackHeaders did not retain the automation label gutter");
    // Standalone VoiceChangeArea behavior on its own synthesized document:
    // paint/lifecycle, refresh, picker commits, hover, camera, undo labels.
    checkVoiceChangeAreaPage(failures);

    if (!screenshotPath.isEmpty()) {
        view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
        view.setDrawerActivePage(EditorDrawerPage::Automations);
        QCoreApplication::processEvents();
        view.grab().save(screenshotPath);
    }
    std::printf("drawer: %s (%d failures)\n", failures ? "FAIL" : "PASS", failures);
    return failures == 0 ? 0 : 1;
}
