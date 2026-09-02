#include "core/miditimeline.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/drawersections.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timelinebandlayout.h"

#include <QApplication>

#include <QAction>
#include <QCoreApplication>
#include <QEvent>
#include <QImage>
#include <QMouseEvent>
#include <QStackedWidget>
#include <QTabBar>
#include <QToolButton>

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <optional>
#include <vector>

#include "checks/rollcheckvoicechange.h"
#include "checks/support/eventsynth.h"
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
    const auto sections = drawer->findChildren<QWidget *>(QStringLiteral("drawerSections"));
    auto *drawerSections = drawer->findChild<QWidget *>(QStringLiteral("drawerSections"));
    auto *typedSections = drawerSections ? dynamic_cast<DrawerSections *>(drawerSections) : nullptr;
    auto *velocityHandle = drawer->findChild<QWidget *>(QStringLiteral("velocityResizeHandle"));
    auto *automationHandle = drawer->findChild<QWidget *>(QStringLiteral("automationResizeHandle"));
    auto *voiceHandle = drawer->findChild<QWidget *>(QStringLiteral("voiceChangesResizeHandle"));
    auto *velocityToggle = drawer->findChild<QToolButton *>(QStringLiteral("velocityDrawerToggle"));
    auto *voiceToggle =
        drawer->findChild<QToolButton *>(QStringLiteral("voiceChangesDrawerToggle"));
    auto *automationToggle =
        drawer->findChild<QToolButton *>(QStringLiteral("automationDrawerToggle"));
    auto *detentToggle = drawer->findChild<QToolButton *>(QStringLiteral("velocityDetentToggle"));
    auto *automationBar = drawer->findChild<QWidget *>(QStringLiteral("automationDrawerBar"));
    check(sections.size() == 1 && drawerSections == sections.front() && drawerSections->isVisible(),
          "drawer did not create exactly one velocity section");
    check(!drawer->findChild<QTabBar *>() && !drawer->findChild<QStackedWidget *>(),
          "drawer retained legacy tab or stacked-page chrome");
    check(velocityHandle && automationHandle && voiceHandle && velocityToggle && voiceToggle &&
              automationToggle && detentToggle && automationBar,
          "drawer did not expose section handles, toggles, and bar");
    if (!velocityHandle || !automationHandle || !voiceHandle || !velocityToggle || !voiceToggle ||
        !automationToggle || !detentToggle || !automationBar)
        return 1;
    const QImage activeDetentIcon =
        detentToggle->icon().pixmap(QSize(64, 64), QIcon::Normal, QIcon::On).toImage();
    bool detentUsesHighlight = false;
    for (int y = 0; y < activeDetentIcon.height() && !detentUsesHighlight; ++y) {
        for (int x = 0; x < activeDetentIcon.width(); ++x) {
            if (activeDetentIcon.pixelColor(x, y) ==
                detentToggle->palette().color(QPalette::Highlight)) {
                detentUsesHighlight = true;
                break;
            }
        }
    }
    check(detentUsesHighlight,
          "active velocity detent icon did not use the drawer toggle highlight color");
#ifdef Q_OS_WIN
    const QImage velocityToggleImage = velocityToggle->grab().toImage();
    const int edgeX = velocityToggleImage.width() - 1;
    const int edgeY = velocityToggleImage.height() - 1;
    const QColor leftEdge = velocityToggleImage.pixelColor(0, edgeY / 2);
    check(leftEdge == velocityToggleImage.pixelColor(edgeX, edgeY / 2) &&
              leftEdge == velocityToggleImage.pixelColor(edgeX / 2, 0) &&
              leftEdge == velocityToggleImage.pixelColor(edgeX / 2, edgeY),
          "velocity toggle outline did not rasterize uniformly on Windows");
#endif
    check(view.drawerSectionVisible(EditorDrawerPage::Automations) &&
              !view.drawerSectionVisible(EditorDrawerPage::Velocity) &&
              !view.drawerSectionVisible(EditorDrawerPage::VoiceChanges) &&
              view.drawerActivePage() == EditorDrawerPage::Automations,
          "drawer default did not retain independent automation and velocity state");
    check(velocityToggle->isVisible() && voiceToggle->isVisible() && automationToggle->isVisible(),
          "velocity toggle disappeared while the velocity pane was hidden");
    check(drawer->parentWidget() &&
              drawer->geometry().bottom() == drawer->parentWidget()->rect().bottom() &&
              rollBandRect() == rollBefore && drawer->plotOrigin() == plotOrigin &&
              drawer->plotWidth() > 0,
          "drawer overlay changed the roll geometry or plot origin");
    check(drawer->automationAction()->shortcuts().isEmpty() &&
              drawer->velocityAction()->shortcuts().isEmpty() &&
              drawer->voiceChangesAction()->shortcuts().isEmpty(),
          "drawer actions compete with the window A/V shortcuts");

    view.setDrawerSectionHeight(EditorDrawerPage::Velocity, 0);
    check(!view.editorViewState().velocity.height,
          "zero drawer height did not retain the layout default");

    drawer->velocityAction()->trigger();
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
              !statuses.empty() && statuses.back() == QStringLiteral("Velocity lane shown"),
          "velocity action did not preserve the open automation section");
    check(velocityHandle->isVisible() && automationHandle->isVisible(),
          "both independent section handles were not visible");
    check(!detentToggle->isVisible(),
          "velocity detent toggle appeared without a selected PSG voice");
    const std::optional<QRect> velocityBodyLocal =
        typedSections ? typedSections->bodyRect(EditorDrawerPage::Velocity) : std::nullopt;
    const QRect detentBounds(detentToggle->mapTo(drawer, QPoint()), detentToggle->size());
    check(velocityBodyLocal && detentBounds.left() == velocityBodyLocal->x() &&
              detentBounds.right() < velocityBodyLocal->x() + velocityCanvas->plotOrigin() &&
              !detentBounds.intersects(QRect(0, 0, velocityBodyLocal->x(), drawer->height())),
          "velocity detent toggle left its label gutter and covered the track headers");
    velocityToggle->click();
    QCoreApplication::processEvents();
    check(!view.drawerSectionVisible(EditorDrawerPage::Velocity) && velocityToggle->isVisible(),
          "hiding velocity with its toggle made the toggle disappear");
    velocityToggle->click();
    QCoreApplication::processEvents();
    check(view.drawerSectionVisible(EditorDrawerPage::Velocity) && velocityToggle->isVisible(),
          "visible velocity toggle did not reopen the velocity pane");
    QQuickItem *const quickRoot = quick->rootObject();
    // Converted drawer bands own no widget: the canonical rectangle, the QML
    // band rectangle, and the timelineVelocityInput/timelineVoiceChangesInput
    // bounds must all carry the parent-owned drawer section, exposed through
    // the Quick window mask.
    const auto bandInputMatchesCanonical = [&](songview::TimelineBand band, const QString &name) {
        const std::optional<songview::TimelineBandGeometry> &geometry = bandLayout.geometry(band);
        auto *input =
            quickRoot ? quickRoot->findChild<songview::TimelineInputItem *>(name) : nullptr;
        return geometry && input && input->isVisible() &&
               input->bounds() ==
                   QRectF(QPointF{}, QSizeF(geometry->rect.width(), geometry->rect.height())) &&
               QRectF(input->mapToItem(quickRoot, QPointF()), input->size()) ==
                   QRectF(geometry->rect.translated(-quick->geometry().topLeft())) &&
               quick->quickWindow()->mask().contains(
                   geometry->rect.translated(-quick->geometry().topLeft()));
    };
    // The third page: the Voice Changes action toggles only its own section,
    // keeps the other two open, and announces through the same status surface.
    drawer->voiceChangesAction()->trigger();
    QCoreApplication::processEvents();
    observeState();
    check(view.drawerSectionVisible(EditorDrawerPage::VoiceChanges) &&
              view.drawerSectionVisible(EditorDrawerPage::Velocity) &&
              view.drawerSectionVisible(EditorDrawerPage::Automations) &&
              view.drawerActivePage() == EditorDrawerPage::VoiceChanges &&
              bandLayout.geometry(songview::TimelineBand::VoiceChanges).has_value() &&
              publishedStates.back().voiceChanges.visible &&
              publishedStates.back().activePage == EditorDrawerPage::VoiceChanges &&
              !statuses.empty() && statuses.back() == QStringLiteral("Voice changes shown"),
          "voice changes action did not preserve the open automation and velocity sections");
    check(voiceHandle->isVisible() && velocityHandle->isVisible() && automationHandle->isVisible(),
          "all three section handles were not visible while voice changes was shown");
    check(bandInputMatchesCanonical(songview::TimelineBand::VoiceChanges,
                                    QStringLiteral("timelineVoiceChangesInput")),
          "voice changes input item did not fill its canonical band inside the Quick mask");
    QCoreApplication::processEvents();
    const auto quickMaskContains = [&view, quick](const QWidget &widget) {
        const QPoint rootPoint =
            widget.mapTo(&view, widget.rect().center()) - quick->geometry().topLeft();
        return quick->quickWindow()->mask().contains(rootPoint);
    };
    check(!quick->quickWindow()->mask().isEmpty() && !quickMaskContains(*voiceHandle) &&
              !quickMaskContains(*velocityHandle) && !quickMaskContains(*automationHandle) &&
              !quickMaskContains(*automationBar),
          "Quick window mask did not expose native drawer handles and toggle bar");
    const QImage automationBarImage = automationBar->grab().toImage();
    const QPoint automationBarProbe(std::max(0, automationBarImage.width() - 2),
                                    automationBarImage.height() / 2);
    check(!automationBarImage.isNull() &&
              automationBarImage.pixelColor(automationBarProbe).alpha() == 255 &&
              !voiceToggle->icon().isNull() && !automationToggle->icon().isNull() &&
              !velocityToggle->icon().isNull(),
          "drawer toggle bar was transparent or its toggle icons were missing");

    const QPoint voiceHandleProbe = voiceHandle->rect().center();
    const QColor idleHandleColor = voiceHandle->grab().toImage().pixelColor(voiceHandleProbe);
    QEvent enterHandle(QEvent::Enter);
    QApplication::sendEvent(voiceHandle, &enterHandle);
    const QColor hoveredHandleColor = voiceHandle->grab().toImage().pixelColor(voiceHandleProbe);
    check(voiceHandle->cursor().shape() == Qt::SizeVerCursor &&
              hoveredHandleColor != idleHandleColor && hoveredHandleColor.alpha() == 255,
          "resize handle did not expose its resize cursor and opaque hover color");
    QMouseEvent pressEvent(QEvent::MouseButtonPress, QPointF(voiceHandleProbe),
                           QPointF(voiceHandleProbe), Qt::LeftButton, Qt::LeftButton,
                           Qt::NoModifier);
    QApplication::sendEvent(voiceHandle, &pressEvent);
    QMouseEvent releaseEvent(QEvent::MouseButtonRelease, QPointF(voiceHandleProbe),
                             QPointF(voiceHandleProbe), Qt::LeftButton, Qt::NoButton,
                             Qt::NoModifier);
    QApplication::sendEvent(voiceHandle, &releaseEvent);
    check(!voiceHandle->testAttribute(Qt::WA_SetCursor),
          "resize handle did not restore the inherited cursor after dragging");
    QEvent leaveHandle(QEvent::Leave);
    QApplication::sendEvent(voiceHandle, &leaveHandle);
    check(!voiceHandle->testAttribute(Qt::WA_SetCursor),
          "resize handle did not restore the inherited cursor after hover");
    check(!detentToggle->isVisible(), "showing voice changes exposed the velocity detent toggle");

    // Stack order: voice handle/body above velocity above automation; the
    // full toggle row reads VoiceChanges, Automations, Velocity left to right
    // and remains centered in the Velocity piano-key region.
    const QRect voiceToggleBounds(voiceToggle->mapTo(drawer, QPoint()), voiceToggle->size());
    const QRect automationToggleBounds(automationToggle->mapTo(drawer, QPoint()),
                                       automationToggle->size());
    const QRect velocityToggleBounds(velocityToggle->mapTo(drawer, QPoint()),
                                     velocityToggle->size());
    const QRect toggleGroup =
        voiceToggleBounds.united(automationToggleBounds).united(velocityToggleBounds);
    const int pianoKeysCenter = velocityBodyLocal->x() + velocityCanvas->plotOrigin() / 2;
    check(bandLayout.geometry(songview::TimelineBand::VoiceChanges)->rect.y() <
                  bandLayout.geometry(songview::TimelineBand::Velocity)->rect.y() &&
              bandLayout.geometry(songview::TimelineBand::Velocity)->rect.y() <
                  bandLayout.geometry(songview::TimelineBand::Automation)->rect.y(),
          "drawer stack did not order voice changes above velocity above automation");
    check(voiceHandle->mapTo(drawer, QPoint()).y() < velocityHandle->mapTo(drawer, QPoint()).y() &&
              velocityHandle->mapTo(drawer, QPoint()).y() <
                  automationHandle->mapTo(drawer, QPoint()).y(),
          "resize handles did not follow the voice/velocity/automation stack order");
    check(voiceToggleBounds.x() + voiceToggleBounds.width() + layout::space(layout::Space::One) ==
                  automationToggleBounds.x() &&
              automationToggleBounds.x() + automationToggleBounds.width() +
                      layout::space(layout::Space::One) ==
                  velocityToggleBounds.x() &&
              voiceToggleBounds.y() == automationToggleBounds.y() &&
              automationToggleBounds.y() == velocityToggleBounds.y() &&
              std::abs(toggleGroup.center().x() - pianoKeysCenter) <= 1,
          "drawer toggle row was not centered voice changes, automations, velocity");

    const int voiceHeightBefore = view.drawerSectionHeight(EditorDrawerPage::VoiceChanges);
    const int voiceBodyHeightBefore =
        bandLayout.geometry(songview::TimelineBand::VoiceChanges)->rect.height();
    const int velocityHeightAtVoice = view.drawerSectionHeight(EditorDrawerPage::Velocity);
    const int automationHeightAtVoice = view.drawerSectionHeight(EditorDrawerPage::Automations);
    const QPoint voiceHandleCenter = voiceHandle->rect().center();
    checks::events::sendMouse(*voiceHandle, QEvent::MouseButtonPress, QPointF(voiceHandleCenter),
                              Qt::RightButton, Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(*voiceHandle, QEvent::MouseMove,
                              QPointF(voiceHandleCenter - QPoint(0, 40)), Qt::NoButton,
                              Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(*voiceHandle, QEvent::MouseButtonRelease,
                              QPointF(voiceHandleCenter - QPoint(0, 40)), Qt::RightButton,
                              Qt::NoButton, Qt::NoModifier);
    check(view.drawerSectionHeight(EditorDrawerPage::VoiceChanges) == voiceHeightBefore,
          "right drag resized the voice changes section");
    checks::events::sendMouse(*voiceHandle, QEvent::MouseButtonPress, QPointF(voiceHandleCenter),
                              Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*voiceHandle, QEvent::MouseMove,
                              QPointF(voiceHandleCenter - QPoint(0, 40)), Qt::NoButton,
                              Qt::LeftButton, Qt::NoModifier);
    QCoreApplication::processEvents();
    const int voiceBodyHeightAfterMove =
        bandLayout.geometry(songview::TimelineBand::VoiceChanges)->rect.height();
    check(voiceBodyHeightAfterMove > voiceBodyHeightBefore,
          "voice changes drag did not grow the live section");
    checks::events::sendMouse(*voiceHandle, QEvent::MouseButtonRelease,
                              QPointF(voiceHandleCenter - QPoint(0, 40)), Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    QCoreApplication::processEvents();
    check(!voiceHandle->testAttribute(Qt::WA_SetCursor),
          "resize handle retained its resize cursor after an outside release");
    const int voiceHeightAfter = view.drawerSectionHeight(EditorDrawerPage::VoiceChanges);
    check(voiceHeightAfter == voiceBodyHeightAfterMove &&
              voiceHeightAfter <= drawer->maximumSectionHeight() &&
              view.drawerSectionHeight(EditorDrawerPage::Velocity) == velocityHeightAtVoice &&
              view.drawerSectionHeight(EditorDrawerPage::Automations) == automationHeightAtVoice,
          "voice changes drag did not persist only its own section height");
    check(bandLayout.geometry(songview::TimelineBand::VoiceChanges)->rect.y() <
                  bandLayout.geometry(songview::TimelineBand::Velocity)->rect.y() &&
              bandLayout.geometry(songview::TimelineBand::VoiceChanges)->rect.height() > 0,
          "voice changes resize broke the drawer stack geometry");
    check(!detentToggle->isVisible(), "resizing voice changes exposed the velocity detent toggle");
    auto *automationViewport = automationPage ? automationPage->scrollViewport() : nullptr;
    const auto canonicalRectMatches = [&](songview::TimelineBand band, const QWidget &widget) {
        const std::optional<songview::TimelineBandGeometry> &geometry = bandLayout.geometry(band);
        return geometry && widget.isVisibleTo(&view) &&
               geometry->rect == QRect(widget.mapTo(&view, QPoint()), widget.size());
    };
    const auto canonicalUnionRect = [&bandLayout] {
        std::optional<QRect> unionRect;
        for (const std::optional<songview::TimelineBandGeometry> &band : bandLayout.bands) {
            if (!band)
                continue;
            unionRect = unionRect ? unionRect->united(band->rect) : band->rect;
        }
        return unionRect;
    };
    check(typedSections && typedSections->bodyRect(EditorDrawerPage::VoiceChanges).has_value() &&
              drawer->bodyRect(EditorDrawerPage::VoiceChanges) ==
                  std::optional<QRect>(typedSections->bodyRect(EditorDrawerPage::VoiceChanges)
                                           ->translated(drawer->mapTo(&view, QPoint()))),
          "drawer body rectangle should map the section-local body into SongView coordinates");
    check(bandInputMatchesCanonical(songview::TimelineBand::Roll,
                                    QStringLiteral("timelineRollInput")) &&
              bandInputMatchesCanonical(songview::TimelineBand::Velocity,
                                        QStringLiteral("timelineVelocityInput")) &&
              canonicalRectMatches(songview::TimelineBand::Automation, *automationViewport) &&
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
    // The drawer body resync is synchronous through EditorDrawer: after a
    // resize drag the Quick host still frames the canonical union and the
    // window mask still exposes every native drawer chrome widget.
    check(quick->geometry() == canonicalUnionRect() && !quick->quickWindow()->mask().isEmpty() &&
              !quickMaskContains(*voiceHandle) && !quickMaskContains(*velocityHandle) &&
              !quickMaskContains(*automationHandle) && !quickMaskContains(*automationBar),
          "drawer resize did not keep the Quick host frame and mask on the canonical layout");

    drawer->voiceChangesAction()->trigger();
    QCoreApplication::processEvents();
    observeState();
    check(!view.drawerSectionVisible(EditorDrawerPage::VoiceChanges) &&
              view.drawerSectionVisible(EditorDrawerPage::Velocity) &&
              view.drawerSectionVisible(EditorDrawerPage::Automations) &&
              view.drawerActivePage() == EditorDrawerPage::VoiceChanges &&
              voiceToggle->isVisible() &&
              view.editorViewState().voiceChanges.height == voiceHeightAfter && !statuses.empty() &&
              statuses.back() == QStringLiteral("Voice changes hidden"),
          "hiding voice changes changed the other sections or lost its retained height");
    voiceToggle->click();
    QCoreApplication::processEvents();
    check(view.drawerSectionVisible(EditorDrawerPage::VoiceChanges) &&
              view.drawerSectionHeight(EditorDrawerPage::VoiceChanges) == voiceHeightAfter,
          "voice changes toggle did not reopen with its retained height");
    drawer->voiceChangesAction()->trigger();
    QCoreApplication::processEvents();
    check(!view.drawerSectionVisible(EditorDrawerPage::VoiceChanges),
          "voice changes action did not close its own section");

    const int velocityHeightBefore = view.drawerSectionHeight(EditorDrawerPage::Velocity);
    const QPoint velocityHandleCenter = velocityHandle->rect().center();
    checks::events::sendMouse(*velocityHandle, QEvent::MouseButtonPress,
                              QPointF(velocityHandleCenter), Qt::RightButton, Qt::RightButton,
                              Qt::NoModifier);
    checks::events::sendMouse(*velocityHandle, QEvent::MouseMove,
                              QPointF(velocityHandleCenter - QPoint(0, 40)), Qt::NoButton,
                              Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(*velocityHandle, QEvent::MouseButtonRelease,
                              QPointF(velocityHandleCenter - QPoint(0, 40)), Qt::RightButton,
                              Qt::NoButton, Qt::NoModifier);
    check(view.drawerSectionHeight(EditorDrawerPage::Velocity) == velocityHeightBefore,
          "right drag resized the velocity section");

    const QRect drawerBeforeVelocityResize = drawer->geometry();
    const QPoint velocityResizeGlobal =
        velocityHandle->mapToGlobal(velocityHandleCenter - QPoint(0, 40));
    checks::events::sendMouse(*velocityHandle, QEvent::MouseButtonPress,
                              QPointF(velocityHandleCenter), Qt::LeftButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(*velocityHandle, QEvent::MouseMove,
                              QPointF(velocityHandleCenter - QPoint(0, 40)), Qt::NoButton,
                              Qt::LeftButton, Qt::NoModifier);
    QCoreApplication::processEvents();
    check(drawer->geometry().bottom() == drawerBeforeVelocityResize.bottom() &&
              drawer->geometry().top() < drawerBeforeVelocityResize.top(),
          "velocity drawer resized downward instead of moving its top edge");
    checks::events::sendMouse(*velocityHandle, QEvent::MouseButtonRelease,
                              QPointF(velocityHandle->mapFromGlobal(velocityResizeGlobal)),
                              Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    QCoreApplication::processEvents();
    const int velocityHeightAfter = view.drawerSectionHeight(EditorDrawerPage::Velocity);
    check(velocityHeightAfter > 0 && velocityHeightAfter <= drawer->maximumSectionHeight() &&
              QWidget::mouseGrabber() == nullptr,
          "left velocity drag did not persist its independent height");

    const int automationHeightBefore = view.drawerSectionHeight(EditorDrawerPage::Automations);
    const QPoint automationHandleCenter = automationHandle->rect().center();
    checks::events::sendMouse(*automationHandle, QEvent::MouseButtonPress,
                              QPointF(automationHandleCenter), Qt::LeftButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(*automationHandle, QEvent::MouseMove,
                              QPointF(automationHandleCenter - QPoint(0, 30)), Qt::NoButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*automationHandle, QEvent::MouseButtonRelease,
                              QPointF(automationHandleCenter - QPoint(0, 30)), Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    QCoreApplication::processEvents();
    check(view.drawerSectionHeight(EditorDrawerPage::Automations) > automationHeightBefore &&
              view.drawerSectionHeight(EditorDrawerPage::Velocity) == velocityHeightAfter,
          "automation drag did not preserve the independent velocity height");

    drawer->velocityAction()->trigger();
    QCoreApplication::processEvents();
    observeState();
    check(!view.drawerSectionVisible(EditorDrawerPage::Velocity) &&
              view.drawerSectionVisible(EditorDrawerPage::Automations) &&
              view.drawerActivePage() == EditorDrawerPage::Velocity &&
              velocityToggle->isVisible() && publishedStates.back().automation.visible &&
              !statuses.empty() && statuses.back() == QStringLiteral("Velocity lane hidden"),
          "collapsing velocity hid its toggle or changed automation or active-page state");

    drawer->automationAction()->trigger();
    QCoreApplication::processEvents();
    observeState();
    check(!view.hasVisibleDrawerSection() &&
              view.drawerActivePage() == EditorDrawerPage::Automations && !statuses.empty() &&
              statuses.back() == QStringLiteral("Automation lanes hidden"),
          "automation action did not collapse its own section");
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

    drawer->velocityAction()->trigger();
    drawer->automationAction()->trigger();
    QCoreApplication::processEvents();
    drawer->automationAction()->trigger();
    QCoreApplication::processEvents();
    check(view.drawerSectionVisible(EditorDrawerPage::Velocity) &&
              !view.drawerSectionVisible(EditorDrawerPage::Automations) &&
              view.drawerActivePage() == EditorDrawerPage::Automations,
          "active page was coupled to section visibility");
    check(bandInputMatchesCanonical(songview::TimelineBand::Velocity,
                                    QStringLiteral("timelineVelocityInput")) &&
              !bandLayout.geometry(songview::TimelineBand::Automation),
          "reopening a drawer section must republish only its canonical rectangle");
    check(quick->geometry() == canonicalUnionRect() && !quick->quickWindow()->mask().isEmpty() &&
              !quickMaskContains(*velocityHandle),
          "reopening a drawer section did not keep the Quick host frame and mask current");

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
    QWidget *velocityFallback = QApplication::focusWidget();
    check(!view.drawerSectionVisible(EditorDrawerPage::Velocity) && velocityFallback &&
              !view.focusedTimelineBand() &&
              (velocityFallback == automationCanvas ||
               automationCanvas->isAncestorOf(velocityFallback)),
          "hiding the focused velocity page did not focus the automation page");
    drawer->automationAction()->trigger();
    QCoreApplication::processEvents();
    QWidget *contentFallback = QApplication::focusWidget();
    check(!view.hasVisibleDrawerSection() &&
              view.focusedTimelineBand() == songview::TimelineBand::Roll &&
              (!contentFallback || !automationCanvas->isAncestorOf(contentFallback)),
          "hiding the last drawer page did not return focus to content");

    const QRect parentBounds = drawer->parentWidget()->rect();
    const int narrowWidth = std::max(0, drawer->plotOrigin() - layout::singlePixel());
    const QRect narrowBounds(parentBounds.left(), parentBounds.top(), narrowWidth,
                             parentBounds.height());
    const QRect rollBeforeNarrow = rollBandRect();
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
    const QRect shortBounds(parentBounds.left(), parentBounds.top(), parentBounds.width(),
                            drawer->minimumSectionHeight());
    drawer->setHostBounds(shortBounds);
    QCoreApplication::processEvents();
    const std::optional<QRect> voiceBody = drawer->bodyRect(EditorDrawerPage::VoiceChanges);
    const std::optional<QRect> velocityBody = drawer->bodyRect(EditorDrawerPage::Velocity);
    const std::optional<QRect> automationBody = drawer->bodyRect(EditorDrawerPage::Automations);
    check(voiceBody && velocityBody && automationBody && voiceBody->height() >= 0 &&
              velocityBody->height() >= 0 && automationBody->height() >= 0 &&
              voiceBody->y() <= velocityBody->y() && velocityBody->y() <= automationBody->y(),
          "short host clamp produced negative or unordered drawer geometry");
    drawer->useParentBounds();
    QCoreApplication::processEvents();
    std::vector<QWidget *> headerRows;
    for (int track = 0; track < 16; ++track) {
        if (auto *row = view.findChild<QWidget *>(QStringLiteral("trackHeaderRow%1").arg(track))) {
            headerRows.push_back(row);
        }
    }
    bool alignedHeaderClicked = false;
    bool alignedHeaderTargeted = false;
    bool alignedGapUnmasked = false;
    bool alignedGeometryFound = false;
    if (headerRows.size() == 16) {
        view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
        view.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
        view.setDrawerSectionHeight(
            EditorDrawerPage::Velocity,
            std::max(drawer->minimumSectionHeight(), headerRows.front()->height() * 2));
        const int automationStep = std::max(1, headerRows.front()->height() / 2);
        const int maximumAutomationHeight = drawer->maximumSectionHeight();
        for (int height = drawer->minimumSectionHeight();
             height <= maximumAutomationHeight && !alignedGeometryFound; height += automationStep) {
            view.setDrawerSectionHeight(EditorDrawerPage::Automations, height);
            QCoreApplication::processEvents();
            const std::optional<songview::TimelineBandGeometry> &velocityGeometry =
                bandLayout.geometry(songview::TimelineBand::Velocity);
            if (!velocityGeometry)
                continue;
            const QRect velocityBounds =
                velocityGeometry->rect.translated(view.mapToGlobal(QPoint()));
            for (int track = 0; track < int(headerRows.size()); ++track) {
                QWidget *row = headerRows[track];
                const QRect rowBounds(row->mapToGlobal(QPoint()), row->size());
                const int overlapTop = std::max(rowBounds.top(), velocityBounds.top());
                const int overlapBottom = std::min(rowBounds.bottom(), velocityBounds.bottom());
                if (overlapTop > overlapBottom)
                    continue;
                alignedGeometryFound = true;
                view.selectTrack(track == 0 ? 1 : 0);
                const QPoint globalPoint(rowBounds.left() + layout::space(layout::Space::One),
                                         (overlapTop + overlapBottom) / 2);
                alignedGapUnmasked = !drawer->mask().contains(drawer->mapFromGlobal(globalPoint));
                QWidget *hit = view.window()->childAt(view.window()->mapFromGlobal(globalPoint));
                if (!hit || (hit != row && !row->isAncestorOf(hit)))
                    break;
                alignedHeaderTargeted = true;
                const QPoint hitPoint = hit->mapFromGlobal(globalPoint);
                checks::events::sendMouse(*hit, QEvent::MouseButtonPress, QPointF(hitPoint),
                                          Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
                checks::events::sendMouse(*hit, QEvent::MouseButtonRelease, QPointF(hitPoint),
                                          Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
                QCoreApplication::processEvents();
                alignedHeaderClicked = view.selectionModel().primaryTrack() == track;
                break;
            }
        }
    }
    check(headerRows.size() == 16, "drawer hit-test fixture did not create track headers");
    check(alignedGeometryFound, "drawer hit-test fixture did not align velocity with a header");
    check(alignedHeaderTargeted, "aligned header point did not hit its track header");
    check(alignedHeaderClicked, "track header click was blocked beside an aligned velocity lane");

    check(alignedGapUnmasked, "drawer mask still covered the aligned track-header point");
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
