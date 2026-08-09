#include "core/miditimeline.h"
#include "ui/editordrawer/automationarea.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea.h"
#include "ui/songview.h"

#include <QApplication>

#include <QAction>
#include <QCoreApplication>
#include <QImage>
#include <QMouseEvent>
#include <QStackedWidget>
#include <QTabBar>
#include <QToolButton>

#include <algorithm>
#include <cstdio>
#include <vector>

#include "ui/layout.h"

namespace {

void sendMouse(QWidget *widget, QEvent::Type type, const QPoint &position, Qt::MouseButton button,
               Qt::MouseButtons buttons)
{
    QMouseEvent event(type, QPointF(position), QPointF(widget->mapToGlobal(position)), button,
                      buttons, Qt::NoModifier);
    QCoreApplication::sendEvent(widget, &event);
}

} // namespace

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
    auto *roll = view.findChild<QWidget *>(QStringLiteral("pianoRoll"));
    auto *automationPage = drawer ? drawer->automationPage() : nullptr;
    auto *automationCanvas = automationPage ? automationPage->area() : nullptr;
    auto *velocityCanvas = drawer ? drawer->velocityArea() : nullptr;
    check(drawer && roll && automationPage && automationCanvas && velocityCanvas,
          "concrete SongView did not expose its drawer pages");
    if (!drawer || !roll || !automationPage || !automationCanvas || !velocityCanvas)
        return 1;

    std::vector<QString> statuses;
    std::vector<EditorViewState> publishedStates;
    QObject::connect(&view, &SongView::statusMessage,
                     [&statuses](const QString &status) { statuses.push_back(status); });
    const auto observeState = [&publishedStates, &view] {
        publishedStates.push_back(view.editorViewState());
    };

    const QRect rollBefore = roll->geometry();
    const auto sections = drawer->findChildren<QWidget *>(QStringLiteral("drawerSections"));
    auto *drawerSections = drawer->findChild<QWidget *>(QStringLiteral("drawerSections"));
    auto *velocityHandle = drawer->findChild<QWidget *>(QStringLiteral("velocityResizeHandle"));
    auto *automationHandle = drawer->findChild<QWidget *>(QStringLiteral("automationResizeHandle"));
    auto *velocityToggle = drawer->findChild<QToolButton *>(QStringLiteral("velocityDrawerToggle"));
    auto *detentToggle = drawer->findChild<QToolButton *>(QStringLiteral("velocityDetentToggle"));
    check(sections.size() == 1 && drawerSections == sections.front() && drawerSections->isVisible(),
          "drawer did not create exactly one velocity section");
    check(!drawer->findChild<QTabBar *>() && !drawer->findChild<QStackedWidget *>(),
          "drawer retained legacy tab or stacked-page chrome");
    check(velocityHandle && automationHandle && velocityToggle && detentToggle,
          "drawer did not expose section handles and velocity controls");
    if (!velocityHandle || !automationHandle || !velocityToggle || !detentToggle)
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
              view.drawerActivePage() == EditorDrawerPage::Automations,
          "drawer default did not retain independent automation and velocity state");
    check(velocityToggle->isVisible(),
          "velocity toggle disappeared while the velocity pane was hidden");
    check(drawer->parentWidget() &&
              drawer->geometry().bottom() == drawer->parentWidget()->rect().bottom() &&
              roll->geometry() == rollBefore && drawer->plotOrigin() == plotOrigin &&
              drawer->plotWidth() > 0,
          "drawer overlay changed the roll geometry or plot origin");
    check(drawer->automationAction()->shortcuts().isEmpty() &&
              drawer->velocityAction()->shortcuts().isEmpty(),
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
              !view.editorViewState().velocity.height && velocityCanvas->height() > 0 &&
              !publishedStates.empty() && publishedStates.back().velocity.visible &&
              publishedStates.back().automation.visible &&
              publishedStates.back().activePage == EditorDrawerPage::Velocity &&
              !statuses.empty() && statuses.back() == QStringLiteral("Velocity lane shown"),
          "velocity action did not preserve the open automation section");
    check(velocityHandle->isVisible() && automationHandle->isVisible(),
          "both independent section handles were not visible");
    check(!detentToggle->isVisible(),
          "velocity detent toggle appeared without a selected PSG voice");
    const QPoint velocityOrigin = velocityCanvas->mapTo(drawer, QPoint());
    const QRect detentBounds(detentToggle->mapTo(drawer, QPoint()), detentToggle->size());
    const QRect trackHeaderBand(0, 0, velocityOrigin.x(), drawer->height());
    check(detentBounds.left() == velocityOrigin.x() &&
              detentBounds.right() < velocityOrigin.x() + velocityCanvas->plotOrigin() &&
              !detentBounds.intersects(trackHeaderBand),
          "velocity detent toggle left its label gutter and covered the track headers");
    velocityToggle->click();
    QCoreApplication::processEvents();
    check(!view.drawerSectionVisible(EditorDrawerPage::Velocity) && velocityToggle->isVisible(),
          "hiding velocity with its toggle made the toggle disappear");
    velocityToggle->click();
    QCoreApplication::processEvents();
    check(view.drawerSectionVisible(EditorDrawerPage::Velocity) && velocityToggle->isVisible(),
          "visible velocity toggle did not reopen the velocity pane");

    const int velocityHeightBefore = view.drawerSectionHeight(EditorDrawerPage::Velocity);
    const QPoint velocityHandleCenter = velocityHandle->rect().center();
    sendMouse(velocityHandle, QEvent::MouseButtonPress, velocityHandleCenter, Qt::RightButton,
              Qt::RightButton);
    sendMouse(velocityHandle, QEvent::MouseMove, velocityHandleCenter - QPoint(0, 40), Qt::NoButton,
              Qt::RightButton);
    sendMouse(velocityHandle, QEvent::MouseButtonRelease, velocityHandleCenter - QPoint(0, 40),
              Qt::RightButton, Qt::NoButton);
    check(view.drawerSectionHeight(EditorDrawerPage::Velocity) == velocityHeightBefore,
          "right drag resized the velocity section");

    const QRect drawerBeforeVelocityResize = drawer->geometry();
    const QPoint velocityResizeGlobal =
        velocityHandle->mapToGlobal(velocityHandleCenter - QPoint(0, 40));
    sendMouse(velocityHandle, QEvent::MouseButtonPress, velocityHandleCenter, Qt::LeftButton,
              Qt::LeftButton);
    sendMouse(velocityHandle, QEvent::MouseMove, velocityHandleCenter - QPoint(0, 40), Qt::NoButton,
              Qt::LeftButton);
    QCoreApplication::processEvents();
    check(drawer->geometry().bottom() == drawerBeforeVelocityResize.bottom() &&
              drawer->geometry().top() < drawerBeforeVelocityResize.top(),
          "velocity drawer resized downward instead of moving its top edge");
    sendMouse(velocityHandle, QEvent::MouseButtonRelease,
              velocityHandle->mapFromGlobal(velocityResizeGlobal), Qt::LeftButton, Qt::NoButton);
    QCoreApplication::processEvents();
    const int velocityHeightAfter = view.drawerSectionHeight(EditorDrawerPage::Velocity);
    check(velocityHeightAfter > 0 && velocityHeightAfter <= drawer->maximumSectionHeight() &&
              QWidget::mouseGrabber() == nullptr,
          "left velocity drag did not persist its independent height");

    const int automationHeightBefore = view.drawerSectionHeight(EditorDrawerPage::Automations);
    const QPoint automationHandleCenter = automationHandle->rect().center();
    sendMouse(automationHandle, QEvent::MouseButtonPress, automationHandleCenter, Qt::LeftButton,
              Qt::LeftButton);
    sendMouse(automationHandle, QEvent::MouseMove, automationHandleCenter - QPoint(0, 30),
              Qt::NoButton, Qt::LeftButton);
    sendMouse(automationHandle, QEvent::MouseButtonRelease, automationHandleCenter - QPoint(0, 30),
              Qt::LeftButton, Qt::NoButton);
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

    drawer->velocityAction()->trigger();
    drawer->automationAction()->trigger();
    QCoreApplication::processEvents();
    drawer->automationAction()->trigger();
    QCoreApplication::processEvents();
    check(view.drawerSectionVisible(EditorDrawerPage::Velocity) &&
              !view.drawerSectionVisible(EditorDrawerPage::Automations) &&
              view.drawerActivePage() == EditorDrawerPage::Automations,
          "active page was coupled to section visibility");

    EditorViewState restoredClose = view.editorViewState();
    restoredClose.velocity.visible = false;
    restoredClose.automation.visible = false;
    view.applyEditorViewState(restoredClose);
    observeState();
    check(!view.hasVisibleDrawerSection() &&
              view.editorViewState().velocity.height == velocityHeightAfter &&
              view.editorViewState().automation.height > automationHeightBefore,
          "state reload did not retain collapsed section heights");

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

    const QRect parentBounds = drawer->parentWidget()->rect();
    const int narrowWidth = std::max(0, drawer->plotOrigin() - layout::singlePixel());
    const QRect narrowBounds(parentBounds.left(), parentBounds.top(), narrowWidth,
                             parentBounds.height());
    const QRect rollBeforeNarrow = roll->geometry();
    drawer->setHostBounds(narrowBounds);
    QCoreApplication::processEvents();
    check(drawer->plotWidth() == 0 && roll->geometry().top() == rollBeforeNarrow.top() &&
              roll->geometry().height() == rollBeforeNarrow.height(),
          "narrow drawer changed the roll geometry");
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
        for (int height = drawer->minimumSectionHeight();
             height <= drawer->maximumSectionHeight() && !alignedGeometryFound;
             height += automationStep) {
            view.setDrawerSectionHeight(EditorDrawerPage::Automations, height);
            QCoreApplication::processEvents();
            const QRect velocityBounds(velocityCanvas->mapToGlobal(QPoint()),
                                       velocityCanvas->size());
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
                sendMouse(hit, QEvent::MouseButtonPress, hitPoint, Qt::LeftButton, Qt::LeftButton);
                sendMouse(hit, QEvent::MouseButtonRelease, hitPoint, Qt::LeftButton, Qt::NoButton);
                QCoreApplication::processEvents();
                alignedHeaderClicked = view.selectedTrack() == track;
                break;
            }
        }
    }
    check(headerRows.size() == 16, "drawer hit-test fixture did not create track headers");
    check(alignedGeometryFound, "drawer hit-test fixture did not align velocity with a header");
    check(alignedHeaderTargeted, "aligned header point did not hit its track header");
    check(alignedHeaderClicked, "track header click was blocked beside an aligned velocity lane");

    check(alignedGapUnmasked, "drawer mask still covered the aligned track-header point");
    if (!screenshotPath.isEmpty()) {
        view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
        view.setDrawerActivePage(EditorDrawerPage::Automations);
        QCoreApplication::processEvents();
        view.grab().save(screenshotPath);
    }
    std::printf("drawer: %s (%d failures)\n", failures ? "FAIL" : "PASS", failures);
    return failures == 0 ? 0 : 1;
}
