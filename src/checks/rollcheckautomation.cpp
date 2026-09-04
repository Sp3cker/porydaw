#include "ui/editordrawer/automationpage.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <memory>
#include <optional>
#include <vector>

#include <QAbstractItemModel>
#include <QAction>
#include <QApplication>
#include <QCoreApplication>
#include <QDialog>
#include <QEvent>
#include <QEventLoop>
#include <QImage>
#include <QInputDialog>
#include <QMenu>
#include <QPoint>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRectF>
#include <QStringList>
#include <QTimer>
#include <QVariant>

#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/editordrawer/drawerchrome.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/nodelane/gesture.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"

void checkAutomationNodePaint(SongView &view, AutomationPage &page, SongDocument &document,
                              DrawerPageLiveState &live, int &failures);
void checkAutomationLanePopupMenus(SongView &view, AutomationPage &page, SongDocument &document,
                                   const QString &songLabel,
                                   const AutomationGeometry &projectionGeometry, int lfoTop,
                                   int lfoHeight, int rowsHeight, int &failures);
void checkAutomationTempoGeometry(SongView &view, AutomationPage &page,
                                  const std::vector<AutomationRow> &rows, const QString &songLabel,
                                  int &failures);

namespace {

uint64_t drawerContextTick(double tick)
{
    return static_cast<uint64_t>(std::floor(std::max(0.0, tick) + 0.5));
}

bool rowExists(const std::vector<AutomationRow> &rows, const EditorAutomationRowId &id)
{
    return std::any_of(rows.cbegin(), rows.cend(),
                       [&id](const AutomationRow &row) { return row.id == id; });
}
bool rowsHaveUniqueIds(const std::vector<AutomationRow> &rows)
{
    for (auto row = rows.cbegin(); row != rows.cend(); ++row) {
        if (std::find_if(rows.cbegin(), row, [&row](const AutomationRow &candidate) {
                return candidate.id == row->id;
            }) != row)
            return false;
    }
    return true;
}
struct ExpectedAutomationGeometry {
    int defaultRowHeight;
    int addLaneStripHeight;
    int minimumRowHeight;
    int maximumRowHeight;
    int gridMinimumCellWidth;
    int pointHitRadius;
    int nodeDragActivationDistance;
    int pointDetailThreshold;
    int timelineMinimumPixelsPerBeat;
    int timelineMaximumPixelsPerBeat;
    int plotOrigin;
    int valuePlotPadding;
};

ExpectedAutomationGeometry expectedAutomationGeometry()
{
    return {
        layout::fontPx(4.0),
        layout::fontPx(5.0 / 3.0),
        layout::fontPx(7.0 / 3.0),
        layout::fontPx(32.0 / 3.0),
        layout::fontPx(4.0 / 3.0),
        layout::fontPx(7.0 / 12.0),
        layout::fontPx(5.0 / 12.0),
        layout::fontPx(2.0),
        layout::fontPx(1.0 / 3.0),
        layout::fontPx(160.0 / 3.0),
        layout::fontPx(17.5 + 13.0 / 3.0),
        qRound(std::max(layout::fontPxF(7.0 / 24.0) * 0.75 + layout::fontPxF(1.0 / 12.0),
                        layout::fontPxF(3.0 / 8.0) * 0.75 + layout::fontPxF(1.0 / 6.0) * 0.5)),
    };
}

int automationRowsHeight(const AutomationPage &page)
{
    const auto &state = page.automationViewState();
    const auto expected = expectedAutomationGeometry();
    const int shared = state.laneHeight > 0 ? state.laneHeight : expected.defaultRowHeight;
    int height = 0;
    for (const auto &row : page.canvas()->rows()) {
        const auto it = state.laneHeights.find(row.id);
        height += std::clamp(it == state.laneHeights.cend() ? shared : it->second,
                             expected.minimumRowHeight, expected.maximumRowHeight);
    }
    return height;
}
int automationRowTop(const AutomationPage &page, const EditorAutomationRowId &id)
{
    const auto &state = page.automationViewState();
    const auto expected = expectedAutomationGeometry();
    const int shared = state.laneHeight > 0 ? state.laneHeight : expected.defaultRowHeight;
    int top = 0;
    for (const auto &row : page.canvas()->rows()) {
        if (row.id == id)
            return top;
        const auto it = state.laneHeights.find(row.id);
        top += std::clamp(it == state.laneHeights.cend() ? shared : it->second,
                          expected.minimumRowHeight, expected.maximumRowHeight);
    }
    return -1;
}
QRect automationRowBody(const AutomationPage &page, const EditorAutomationRowId &id)
{
    const auto &rows = page.canvas()->rows();
    for (int index = 0; index < int(rows.size()); ++index) {
        if (rows[std::size_t(index)].id == id)
            return page.canvas()->laneBody(LaneHandle{index + 1});
    }
    return {};
}

void pumpQuickEvents()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents(QEventLoop::AllEvents);
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents(QEventLoop::AllEvents);
}
std::optional<QRectF> quickTextRect(QAbstractItemModel *model, const QString &text)
{
    if (!model)
        return std::nullopt;
    for (int row = 0; row < model->rowCount(); ++row) {
        const QModelIndex index = model->index(row, 0);
        if (model->data(index, songview::TimelineQuickTextModel::TextRole).toString() == text) {
            return model->data(index, songview::TimelineQuickTextModel::RectRole).toRectF();
        }
    }
    return std::nullopt;
}

songview::TimelineInputItem *automationInputItem(SongView &view)
{
    auto *quickCanvas =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    return quickCanvas && quickCanvas->rootObject()
               ? quickCanvas->rootObject()->findChild<songview::TimelineInputItem *>(
                     QStringLiteral("timelineAutomationInput"))
               : nullptr;
}

QQuickItem *quickScrollbarItem(songview::TimelineQuickView &quick)
{
    QQuickItem *root = quick.rootObject();
    return root ? root->findChild<QQuickItem *>(QStringLiteral("drawerAutomationScrollBar"))
                : nullptr;
}

// Band input delivery: the Quick input item normalizes raw events in
// viewport coordinates, so content-coordinate probes shift by the page
// scroll before each send.
struct AutomationBandInput {
    AutomationPage &page;
    songview::TimelineInputItem &item;

    void mouse(QEvent::Type type, const QPointF &contentPosition, Qt::MouseButton button,
               Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers) const
    {
        checks::events::sendMouse(item, type, contentPosition - QPointF(0.0, page.verticalScroll()),
                                  button, buttons, modifiers);
    }
    void wheel(const QPointF &contentPosition, const QPoint &pixelDelta, const QPoint &angleDelta,
               Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers, Qt::ScrollPhase phase,
               bool inverted) const
    {
        checks::events::sendWheel(item, contentPosition - QPointF(0.0, page.verticalScroll()),
                                  pixelDelta, angleDelta, buttons, modifiers, phase, inverted);
    }
    void key(QEvent::Type type, int key, Qt::KeyboardModifiers modifiers) const
    {
        checks::events::sendKey(item, type, key, modifiers, QString{}, false, ushort{1});
    }
    void leave() const { mouse(QEvent::Leave, {}, Qt::NoButton, Qt::NoButton, Qt::NoModifier); }
};
QPointF automationNodePoint(SongView &view, const AutomationPage &page, qreal dpr,
                            const AutomationGeometry &geometry, const EditorAutomationRowId &id,
                            uint64_t tick, int value)
{
    const QRect body = automationRowBody(page, id);
    return {view.camera().displayX(double(tick), geometry.plotOrigin, dpr),
            AutomationProjection::valueY(body, geometry,
                                         CoreTimeDefaults::laneValueMinimum(id.controller),
                                         CoreTimeDefaults::laneValueMaximum(id.controller), value)};
}
} // namespace

namespace {

int runAutomationCheckImpl(const QString &scratchProject, const QString &songLabel,
                           const QString &screenshotPath, bool popupMenus)
{
    QString error;
    auto loadedSong = checks::LoadedSong::load(scratchProject, songLabel, error);
    if (!loadedSong) {
        std::fprintf(stderr, "automation-check: %s\n", qUtf8Printable(error));
        return 1;
    }
    SongDocument &document = loadedSong->document();
    const QByteArray baseline = document.smf().write();
    if (document.engineTrackCount() == 0) {
        std::fprintf(stderr, "automation-check: %s has no engine tracks\n",
                     qUtf8Printable(songLabel));
        return 1;
    }
    document.addLanePoint(0, 7, 24, 32);
    document.writeLanePoints(0, 21, 96, 96, {{96, 32}, {96, 96}});
    document.addLanePoint(0, LANE_CC_BEND, 72, 8191);
    document.addLanePoint(0, DOC_CC_VOICE, 24, 3);
    auto timeline = document.buildTimeline(48000.0);
    LoadedVoiceGroup voicegroup{};
    voicegroup.voices[3].type = VOICE_NOISE;
    std::strncpy(voicegroup.voiceNames[3], "automation-voice",
                 sizeof(voicegroup.voiceNames[3]) - 1);
    SongView view;
    auto expected = expectedAutomationGeometry();
    view.resize(960, 720);
    view.setDocument(&document);
    view.setSong(timeline.get(), &voicegroup);
    EditorViewState state;
    const EditorAutomationRowId volume{EditorAutomationRowKind::ControlChange, 0, 7};
    const EditorAutomationRowId pan{EditorAutomationRowKind::ControlChange, 0, 10};
    const EditorAutomationRowId lfo{EditorAutomationRowKind::ControlChange, 0, 21};
    const EditorAutomationRowId modulation{EditorAutomationRowKind::ControlChange, 0, 20};
    state.hideLane(volume);
    state.emptyLanes.insert(pan);
    state.laneHeights[lfo] = expected.defaultRowHeight + 5;
    state.laneRanges[lfo] = 91;
    view.applyEditorViewState(state);
    view.setDrawerActivePage(EditorDrawerPage::Automations);
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, 360);
    view.show();
    pumpQuickEvents();
    auto *drawer = view.editorDrawer();
    auto *pagePtr = drawer ? drawer->automationPage() : nullptr;
    if (!pagePtr) {
        std::fprintf(stderr, "automation-check: concrete SongView did not expose AutomationPage\n");
        return 1;
    }
    auto &page = *pagePtr;
    page.songChanged();
    DrawerPageLiveState live;
    live.documentRevision = document.revision();
    live.timeZoom = 96.0;
    view.setEditorTimeZoom(live.timeZoom);
    live.horizontalScroll = view.camera().scrollX();
    view.setEditCursorTick(24);
    page.refreshLiveState(live);
    pumpQuickEvents();
    expected.plotOrigin = page.canvas()->plotOrigin();
    auto projectionGeometry = AutomationGeometry::resolve(expected.plotOrigin);

    int failures = 0;
    const auto recordFailure = [&](const QString &message) {
        std::fprintf(stderr, "%s: FAIL %s: %s\n",
                     popupMenus ? "automation-popup-check" : "automation-check",
                     qUtf8Printable(songLabel), qUtf8Printable(message));
        ++failures;
    };
    const auto check = [&](bool condition, const QString &message) {
        if (!popupMenus && !condition)
            recordFailure(message);
    };
    const auto popupCheck = [&](bool condition, const QString &message) {
        if (popupMenus && !condition)
            recordFailure(message);
    };
    const auto checkPopupParent = [&](const QWidget *popup) {
        const bool parentedToSongView = popup && popup->parentWidget() == &view;
        check(parentedToSongView, QStringLiteral("automation popup was not parented to SongView"));
        popupCheck(parentedToSongView,
                   QStringLiteral("automation popup was not parented to SongView"));
    };
    const auto automationBandRect = [&]() -> QRect {
        const auto &bandGeometry =
            view.timelineBandLayout().geometry(songview::TimelineBand::Automation);
        return bandGeometry ? bandGeometry->rect : QRect{};
    };
    check(!automationBandRect().isNull(),
          QStringLiteral("automation page did not publish its canonical band"));
    songview::TimelineInputItem *const automationInput = automationInputItem(view);
    check(automationInput != nullptr,
          QStringLiteral("automation page did not expose its Quick input item"));
    auto *quickScene = view.findChild<songview::TimelineQuickScene *>();
    check(quickScene, QStringLiteral("automation page did not expose its retained Quick scene"));
    const AutomationBandInput band{page, *automationInput};
    // Viewport positions: content probes shift up by the page's vertical scroll.
    const auto viewportPosition = [&](const QPointF &contentPosition) {
        return contentPosition - QPointF(0.0, page.verticalScroll());
    };
    const qreal dpr = automationInput->devicePixelRatio();
    const QSize automationViewportSize = page.automationViewportSize();
    const auto captureAutomationViewport = [&] {
        pumpQuickEvents();
        QString captureError;
        const QRect bandRect = automationBandRect();
        const QImage image = bandRect.isNull()
                                 ? QImage{}
                                 : checks::support::captureQuickBand(view, bandRect, &captureError);
        check(
            !image.isNull(),
            QStringLiteral("automation viewport framebuffer capture failed: %1").arg(captureError));
        return image;
    };
    const auto contentToViewport = [&](const QRect &content) {
        return QRect{viewportPosition(content.topLeft()).toPoint(), content.size()};
    };
    const auto captureAutomationContent = [&](const QRect &content) {
        const QRect viewportRect = contentToViewport(content);
        const QRect bandBounds(QPoint(0, 0), automationBandRect().size());
        check(bandBounds.contains(viewportRect),
              QStringLiteral("automation content crop is outside the automation band"));
        const QImage image = captureAutomationViewport();
        if (image.isNull() || !bandBounds.contains(viewportRect))
            return QImage{};
        const qreal imageDpr = image.devicePixelRatio();
        const int left = qRound(viewportRect.left() * imageDpr);
        const int top = qRound(viewportRect.top() * imageDpr);
        const int right = qRound((viewportRect.right() + 1) * imageDpr);
        const int bottom = qRound((viewportRect.bottom() + 1) * imageDpr);
        const QRect crop(left, top, right - left, bottom - top);
        check(image.rect().contains(crop),
              QStringLiteral("automation content crop exceeds the viewport framebuffer"));
        QImage result = image.copy(crop);
        result.setDevicePixelRatio(imageDpr);
        return result;
    };
    auto *quickHost =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    DrawerChrome &chrome = drawer->chrome();
    const QRectF scrollbarRect = chrome.automationScrollbarRect();
    check(scrollbarRect.isValid() && !scrollbarRect.isEmpty() &&
              scrollbarRect.width() == layout::space(layout::Space::Two),
          QStringLiteral("automation scrollbar must publish a valid Space::Two-wide chrome rect"));
    const auto &automationBandGeometry =
        view.timelineBandLayout().geometry(songview::TimelineBand::Automation);
    check(
        quickHost && quickHost->quickWindow() && scrollbarRect.isValid() &&
            !scrollbarRect.isEmpty() &&
            quickHost->geometry().contains(scrollbarRect.toAlignedRect()) &&
            quickHost->quickWindow()->mask().isEmpty(),
        QStringLiteral("unmasked Quick host geometry must contain the full automation scrollbar"));
    QQuickItem *scrollbarItem = quickHost ? quickScrollbarItem(*quickHost) : nullptr;
    check(scrollbarItem && scrollbarItem->isVisible(),
          QStringLiteral("automation scrollbar must be visible in the Quick scene"));
    // The bar is always on: fit the whole automation content into the drawer,
    // then resize the zero-range viewport and verify its bound QML thumb follows.
    const int scrollbarSectionHeight = view.drawerSectionHeight(EditorDrawerPage::Automations);
    const int scrollbarSectionOverhead =
        std::max(0, scrollbarSectionHeight -
                        (automationBandGeometry ? automationBandGeometry->rect.height() : 0));
    const int fittingSectionHeight =
        std::min(drawer->maximumSectionHeight(),
                 page.canvas()->minimumContentHeight() + scrollbarSectionOverhead);
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, fittingSectionHeight);
    pumpQuickEvents();
    const QRectF fitScrollbarRect = chrome.automationScrollbarRect();
    QQuickItem *fitScrollbarItem = quickHost ? quickScrollbarItem(*quickHost) : nullptr;
    const int fitViewportHeight = chrome.automationViewportHeight();
    const int fitContentHeight = chrome.automationContentHeight();
    const int fitTrackHeight = fitScrollbarItem ? qRound(fitScrollbarItem->height()) : -1;
    const int fitThumbHeight =
        fitScrollbarItem ? fitScrollbarItem->property("thumbHeight").toInt() : -1;
    check(chrome.automationMaximumScrollY() == 0 && fitScrollbarRect.isValid() &&
              !fitScrollbarRect.isEmpty() && fitScrollbarItem && fitScrollbarItem->isVisible() &&
              fitViewportHeight == fitContentHeight && fitViewportHeight == fitTrackHeight &&
              fitThumbHeight == fitTrackHeight,
          QStringLiteral("automation scrollbar must stay visible and fill its track when "
                         "maximumScrollY is zero"));

    view.setDrawerSectionHeight(EditorDrawerPage::Automations, drawer->maximumSectionHeight());
    pumpQuickEvents();
    const QRectF resizedScrollbarRect = chrome.automationScrollbarRect();
    QQuickItem *resizedScrollbarItem = quickHost ? quickScrollbarItem(*quickHost) : nullptr;
    const int resizedViewportHeight = chrome.automationViewportHeight();
    const int resizedContentHeight = chrome.automationContentHeight();
    const int resizedTrackHeight =
        resizedScrollbarItem ? qRound(resizedScrollbarItem->height()) : -1;
    const int resizedThumbHeight =
        resizedScrollbarItem ? resizedScrollbarItem->property("thumbHeight").toInt() : -1;
    const int resizedQmlContentHeight =
        resizedScrollbarItem ? resizedScrollbarItem->property("contentHeight").toInt() : -1;
    const int resizedQmlViewportHeight =
        resizedScrollbarItem ? resizedScrollbarItem->property("viewportHeight").toInt() : -1;
    check(chrome.automationMaximumScrollY() == 0 && resizedScrollbarRect.isValid() &&
              !resizedScrollbarRect.isEmpty() && resizedScrollbarItem &&
              resizedScrollbarItem->isVisible() && resizedViewportHeight > fitViewportHeight &&
              resizedContentHeight > fitContentHeight &&
              resizedContentHeight == resizedViewportHeight &&
              resizedQmlContentHeight == resizedContentHeight &&
              resizedQmlViewportHeight == resizedViewportHeight &&
              resizedViewportHeight == resizedTrackHeight &&
              resizedThumbHeight == resizedTrackHeight,
          QStringLiteral("resizing a zero-range automation viewport did not update DrawerChrome "
                         "dimensions and fill the resized TimelineScrollbar track"));
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, scrollbarSectionHeight);
    pumpQuickEvents();
    const int automationPlotStart = page.canvas()->plotOrigin();
    const QRect labelGutter = page.canvas()->labelGutter();
    const QRect automationLabelGutterInHost =
        automationBandGeometry ? QRect(labelGutter.x(), labelGutter.y(), labelGutter.width(),
                                       automationBandGeometry->rect.height())
                                     .translated(automationBandGeometry->rect.topLeft())
                               : QRect{};
    check(quickHost && quickHost->quickWindow() && automationBandGeometry &&
              !automationLabelGutterInHost.isEmpty() &&
              quickHost->geometry().contains(automationLabelGutterInHost) &&
              quickHost->quickWindow()->mask().isEmpty(),
          QStringLiteral(
              "unmasked Quick host must fully contain the automation label-gutter column"));
    // The painted header includes the label gutter's symmetric horizontal margins.
    const QRect headerRect(0, 0, labelGutter.width() + 2 * labelGutter.x(),
                           automationViewportSize.height());
    const QRect plot(automationPlotStart, 0,
                     std::max(0, automationViewportSize.width() - automationPlotStart),
                     automationViewportSize.height());
    const bool headerEndsAtPlotOrigin = headerRect.right() + 1 == automationPlotStart;
    const std::optional<songview::TimelineBandGeometry> rollBandGeometry =
        view.timelineBandLayout().geometry(songview::TimelineBand::Roll);
    const int pianoGridStartOnView =
        rollBandGeometry ? rollBandGeometry->rect.x() + rollBandGeometry->timelineOrigin : -1;
    const int automationPlotStartOnView =
        automationBandGeometry
            ? automationBandGeometry->rect.x() + automationBandGeometry->timelineOrigin
            : -1;
    check(automationBandGeometry && automationBandGeometry->timelineOrigin == automationPlotStart &&
              rollBandGeometry && automationPlotStartOnView == pianoGridStartOnView,
          QStringLiteral("editable automation lanes must start vertically inline with the piano "
                         "grid (automation %1 = %2 + %3, piano %4)")
              .arg(automationPlotStartOnView)
              .arg(automationBandGeometry ? automationBandGeometry->rect.x() : -1)
              .arg(automationPlotStart)
              .arg(pianoGridStartOnView));
    check(headerEndsAtPlotOrigin && labelGutter.left() >= headerRect.left() &&
              labelGutter.right() < automationPlotStart && plot.left() == automationPlotStart &&
              plot.width() == std::max(0, automationViewportSize.width() - automationPlotStart),
          QStringLiteral("automation header must end exactly at the editable lane start"));
    const QPointF panStart(expected.plotOrigin + 160, expected.defaultRowHeight / 2);
    const QPointF panFirstMove = panStart - QPointF(24, 0);
    const QPointF panSecondMove = panStart - QPointF(48, 0);
    constexpr uint64_t panProbeTick = 240;
    const qreal panProbeBefore =
        view.camera().displayX(double(panProbeTick), expected.plotOrigin, dpr);
    band.mouse(QEvent::MouseButtonPress, panStart, Qt::MiddleButton, Qt::MiddleButton,
               Qt::NoModifier);
    band.mouse(QEvent::MouseMove, panFirstMove, Qt::NoButton, Qt::MiddleButton, Qt::NoModifier);
    const bool panRemainedActive = automationInput->cursor().shape() == Qt::ClosedHandCursor;
    band.mouse(QEvent::MouseMove, panSecondMove, Qt::NoButton, Qt::MiddleButton, Qt::NoModifier);
    band.mouse(QEvent::MouseButtonRelease, panSecondMove, Qt::MiddleButton, Qt::NoButton,
               Qt::NoModifier);
    const qreal panProbeAfter =
        view.camera().displayX(double(panProbeTick), expected.plotOrigin, dpr);
    check(panRemainedActive && qAbs((panProbeBefore - panProbeAfter) - 48.0) < 0.5,
          QStringLiteral("middle-button automation pan stopped after its first scroll refresh"));
    view.setEditorHorizontalScroll(0.0);
    live.horizontalScroll = 0.0;
    // ---- 3 cheap-fix regression oracles (template / mappedForLane / GestureCommit) ----
    {
        // 1. Sweep template stepping: extendSweepPoints must interpolate without std::function
        SweepGesture g;
        g.lane = LaneHandle{0};
        g.current = {10, 100};
        g.previousRawTick = 0.0;
        g.previousValue = 0;
        g.points.clear();
        auto stepOne = [](uint64_t t, bool, uint64_t) -> uint64_t { return t + 1; };
        extendSweepPoints(g, 0, 10, 10.0, false, stepOne);
        bool sweepOk = g.points.size() == 11;
        for (size_t i = 0; i < g.points.size() && sweepOk; ++i) {
            if (g.points[i].tick != i || g.points[i].value != int(i) * 10)
                sweepOk = false;
        }
        check(sweepOk, QStringLiteral(
                           "Sweep extendSweepPoints template did not interpolate 0..10 -> 0..100"));
        SweepGesture g2;
        g2.lane = LaneHandle{0};
        g2.current = {0, 0};
        g2.previousRawTick = 0.0;
        g2.previousValue = 0;
        NodePoint mapped{5, 50};
        g2.update(mapped, 0, 5, 5.0, false, stepOne);
        check(g2.current.tick == 5 && g2.current.value == 50 && g2.points.size() >= 6,
              QStringLiteral("Sweep::update template did not forward to extendSweepPoints"));
        SweepGesture ramp;
        ramp.mode = SweepGesture::Mode::Ramp;
        ramp.anchor = {0, 0};
        ramp.current = {10, 100};
        std::vector<NodePoint> existing;
        auto rampCompletion =
            ramp.finish(LaneHandle{0}, document.revision(), existing, false, stepOne);
        bool rampOk = !rampCompletion.unchanged && rampCompletion.points.size() == 11 &&
                      rampCompletion.points.front().value == 0 &&
                      rampCompletion.points.back().value == 100;
        check(rampOk, QStringLiteral("Sweep ramp finish did not step via nextGridTick"));
    }
    {
        // 2. mappedForLane core: updateValuePoint with snap-value neutral snapping
        const int panTop = automationRowTop(page, pan);
        check(panTop >= 0, QStringLiteral("pan lane not found for snap-value test"));
        if (panTop >= 0) {
            const auto it = state.laneHeights.find(pan);
            const int shared = state.laneHeight > 0 ? state.laneHeight : expected.defaultRowHeight;
            const int panHeight = std::clamp(it == state.laneHeights.cend() ? shared : it->second,
                                             expected.minimumRowHeight, expected.maximumRowHeight);
            const QRect panBody(0, panTop, automationViewportSize.width(), panHeight);
            AutomationProjection proj(projectionGeometry, &page);
            CCLaneAdapter panLane(document, 0, pan.controller);
            const int span = panLane.maximumValue() - panLane.minimumValue();
            const int snapThresh =
                span * projectionGeometry.neutralSnapRadius / std::max(1, panHeight);
            int yNear = -1;
            int vNear = -1;
            for (int y = panTop; y < panTop + panHeight; ++y) {
                int v = qRound(AutomationProjection::valueAtY(panBody, projectionGeometry,
                                                              panLane.minimumValue(),
                                                              panLane.maximumValue(), qreal(y)));
                if (yNear < 0 && v != 64 && std::abs(v - 64) <= snapThresh &&
                    std::abs(v - 64) > 0) {
                    yNear = y;
                    vNear = v;
                }
            }
            check(yNear >= 0, QStringLiteral("yNear not found for snap-value test"));
            if (yNear >= 0) {
                NodePoint p;
                updateValuePoint(proj, panLane, panBody, p, yNear, 100, false,
                                 projectionGeometry.neutralSnapRadius, 64);
                const bool withoutSnapValue = p.value == vNear;
                updateValuePoint(proj, panLane, panBody, p, yNear, 100, true,
                                 projectionGeometry.neutralSnapRadius, 64);
                const bool withSnapValue = p.value == 64;
                check(withoutSnapValue && withSnapValue,
                      QStringLiteral("updateValuePoint snap-value did not snap %1->64 for pan")
                          .arg(vNear));
            }
            const qreal yAt64f = AutomationProjection::valueY(
                panBody, projectionGeometry, panLane.minimumValue(), panLane.maximumValue(), 64);
            const int yAt64 = qRound(yAt64f);
            NodePoint p;
            updateValuePoint(proj, panLane, panBody, p, yAt64, 200, true,
                             projectionGeometry.neutralSnapRadius, 64);
            check(
                p.value == 64 && p.tick == 200,
                QStringLiteral("updateValuePoint with snap-value corrupted tick/value at neutral"));
        }
    }
    {
        // 3. Domain-neutral NodeDragGesture outcomes.
        const auto laneNode = [](const DocLanePoint &point, NodePoint current) {
            return NodeDrag{LaneHandle{0}, {point.tick, point.value}, current, 0, 127};
        };
        {
            NodeDragGesture gesture;
            const NodeDragFinish finish = gesture.finish();
            check(finish.release == PointDragRelease::NoOp && !finish.changed,
                  QStringLiteral("empty NodeDragGesture should finish as unchanged NoOp"));
        }
        {
            NodeDragGesture gesture;
            const DocLanePoint original{0, 7, 24, 60};
            gesture.points = {laneNode(original, {24, 60})};
            gesture.drag.press({100.0, 100.0}, false);
            const NodeDragFinish finish = gesture.finish();
            check(finish.release == PointDragRelease::NoOp && !finish.changed,
                  QStringLiteral("Shift stationary node drag should be unchanged NoOp"));
        }
        {
            NodeDragGesture gesture;
            const DocLanePoint original{0, 7, 24, 60};
            gesture.points = {laneNode(original, {24, 60})};
            gesture.drag.press({100.0, 100.0}, true);
            const NodeDragFinish finish = gesture.finish();
            check(finish.release == PointDragRelease::StationaryDelete && !finish.changed,
                  QStringLiteral("stationary node drag did not report deletion"));
        }
        {
            NodeDragGesture gesture;
            const DocLanePoint original{0, 7, 24, 60};
            gesture.points = {laneNode(original, {24, 60})};
            gesture.drag.press({100.0, 100.0}, true);
            gesture.drag.dragSlop.markExceeded({105.0, 100.0});
            const NodeDragFinish unchanged = gesture.finish();
            check(unchanged.release == PointDragRelease::Move && !unchanged.changed,
                  QStringLiteral("unchanged dragged node should be an unchanged Move"));

            gesture.points.front().current = {30, 80};
            const NodeDragFinish moved = gesture.finish();
            check(moved.release == PointDragRelease::Move && moved.changed && moved.dTick == 6,
                  QStringLiteral("changed node drag did not report its tick delta"));
        }
        {
            NodeDragGesture gesture;
            const DocLanePoint original0{0, 7, 24, 60};
            const DocLanePoint original1{0, 7, 48, 80};
            gesture.points = {
                laneNode(original0, {30, 70}),
                laneNode(original1, {54, 90}),
            };
            gesture.selectionDrag = true;
            gesture.drag.press({100.0, 100.0}, true);
            gesture.drag.dragSlop.markExceeded({105.0, 100.0});
            const NodeDragFinish finish = gesture.finish();
            check(finish.release == PointDragRelease::Move && finish.changed && finish.dTick == 6 &&
                      finish.selectionDrag && gesture.points[0].current.tick == 30 &&
                      gesture.points[1].current.tick == 54,
                  QStringLiteral("multi-node drag outcome lost shared movement state"));
        }
        {
            const DocLanePoint original{0, 7, 24, 60};
            PhantomGesture gesture;
            gesture.point = laneNode(original, {24, 60});
            gesture.drag.press({100.0, 100.0}, false);
            gesture.update({PointDragUpdate::Phase::Reset, {}, AxisLock::None}, 127);
            check(gesture.point.current.tick == 24 && gesture.point.current.value == 60,
                  QStringLiteral("phantom reset did not restore its source point"));
            gesture.drag.dragSlop.markExceeded({100.0, 110.0});
            gesture.update({PointDragUpdate::Phase::Dragging, {}, AxisLock::None}, 200);
            const auto moved = gesture.finish();
            check(moved && moved->original.tick == moved->current.tick &&
                      moved->current.value == 127,
                  QStringLiteral("phantom drag did not stay value-only and clamp to its range"));
        }
    }
    {
        using LaneEdit = NodeLaneEdit;
        const auto target = LaneEdit::Target{LaneHandle{0}, document.revision()};
        const auto pointRange = LaneEdit(target, {{24, 64}, {48, 64}});
        const auto identical = pointRange.replacePointRange(24, 48, {{24, 64}, {48, 64}});
        check(identical.unchanged,
              QStringLiteral("identical automation point range was not unchanged"));
        const auto structurallyDifferent = pointRange.replacePointRange(24, 48, {{24, 64}});
        check(!structurallyDifferent.unchanged,
              QStringLiteral("point range used held-value equality instead of exact points"));

        const auto heldSpan = LaneEdit(target, {{0, 20}, {24, 60}, {72, 90}});
        const auto restored = heldSpan.replaceHeldSpan(24, 48, 96, 0, 127, {{24, 80}});
        check(!restored.unchanged && restored.points.size() == 2 && restored.points[0].tick == 24 &&
                  restored.points[0].value == 80 && restored.points[1].tick == 48 &&
                  restored.points[1].value == 60,
              QStringLiteral("held-span replacement did not restore its endpoint value"));
        const AutomationPencilGesture::Sample finalSample{24.0, 24.0, {24, 80}, 80.0};
        auto emptyLaneGesture = AutomationPencilGesture::start(
            target, 0, 127, 96, 24, {}, NodePoint{0, 20}, finalSample, {24, 48});
        check(emptyLaneGesture.has_value(),
              QStringLiteral("empty-lane pencil gesture did not start with its held lead-in"));
        if (emptyLaneGesture) {
            const auto completion = std::move(*emptyLaneGesture).finish();
            check(!completion.unchanged && completion.points.size() == 2 &&
                      completion.points[0].tick == 24 && completion.points[0].value == 80 &&
                      completion.points[1].tick == 48 && completion.points[1].value == 20,
                  QStringLiteral("empty-lane pencil final node did not restore its held value "
                                 "at the following cell boundary"));
        }
        auto pastLastGesture = AutomationPencilGesture::start(target, 0, 127, 96, 24, {{0, 20}},
                                                              std::nullopt, finalSample, {24, 48});
        check(pastLastGesture.has_value(),
              QStringLiteral("past-last-point pencil gesture did not start"));
        if (pastLastGesture) {
            const auto completion = std::move(*pastLastGesture).finish();
            check(!completion.unchanged && completion.points.size() == 2 &&
                      completion.points[0].tick == 24 && completion.points[0].value == 80 &&
                      completion.points[1].tick == 48 && completion.points[1].value == 20,
                  QStringLiteral("past-last-point pencil final node changed the unpainted "
                                 "held value"));
        }
        const auto flat = heldSpan.replaceHeldSpan(36, 48, 96, 0, 127, {{36, 60}});
        check(flat.unchanged && flat.points.empty(),
              QStringLiteral("flat held-span replacement was not reduced to an empty no-op"));
        const auto deletion = heldSpan.replaceHeldSpan(24, 96, 96, 0, 127, {});
        check(!deletion.unchanged && deletion.points.empty(),
              QStringLiteral("empty held-span deletion was treated as unchanged"));
    }
    const auto &rows = page.canvas()->rows();
    const bool voiceIsCcRow = std::any_of(rows.cbegin(), rows.cend(), [](const AutomationRow &row) {
        return row.id.controller == DOC_CC_VOICE;
    });
    check(!rows.empty() && !voiceIsCcRow && automationRowTop(page, rows.front().id) == 0,
          QStringLiteral("First CC row must own the canvas origin with no reserved voice inset, "
                         "and voice changes must stay out of the row stack"));
    check(!rowExists(rows, EditorAutomationRowId{EditorAutomationRowKind::Tempo, 0, 0}),
          QStringLiteral("Tempo should not be a generic automation row"));
    check(!rowExists(rows, volume), QStringLiteral("hidden lane remained visible"));
    check(rowExists(rows, pan), QStringLiteral("empty primary-track lane is missing"));
    check(rowExists(rows, lfo), QStringLiteral("visible controller lane is missing"));
    check(page.automationViewState().laneRanges.at(lfo) == 91,
          QStringLiteral("typed non-menu lane range was not retained"));
    const auto bend =
        EditorAutomationRowId{EditorAutomationRowKind::ControlChange, 0, LANE_CC_BEND};
    check(!rows.empty() && rows.back().id == bend,
          QStringLiteral("bend pseudo-controller is not ordered last"));
    const auto heightFor = [&](const EditorAutomationRowId &id) {
        const auto it = state.laneHeights.find(id);
        const int shared = state.laneHeight > 0 ? state.laneHeight : expected.defaultRowHeight;
        return std::clamp(it == state.laneHeights.cend() ? shared : it->second,
                          expected.minimumRowHeight, expected.maximumRowHeight);
    };
    if (!popupMenus)
        checkAutomationTempoGeometry(view, page, rows, songLabel, failures);
    const int lfoTop = automationRowTop(page, lfo);
    const int lfoHeight = heightFor(lfo);
    if (popupMenus)
        checkAutomationLanePopupMenus(view, page, document, songLabel, projectionGeometry, lfoTop,
                                      lfoHeight, automationRowsHeight(page), failures);
    page.canvas()->requestFullQuickUpdate();
    (void)captureAutomationViewport();
    const DrawerPageGridState meterGrid = {view.grid().gridTicksAt(48),
                                           view.grid().snapTicksAt(48)};
    check(meterGrid.gridTicks > 0 && meterGrid.snapTicks > 0,
          QStringLiteral("automation grid did not resolve through its SongView owner"));
    live.timeZoom = 96.0;
    view.setEditorTimeZoom(live.timeZoom);
    page.refreshLiveState(live);
    const uint64_t hoverSnapTick = view.grid().snapTick(30.0, false);
    const uint64_t hoverSnapSpacing = view.grid().snapTicksAt(hoverSnapTick);
    const double firstHoverTick = double(hoverSnapTick) + 0.1 * double(hoverSnapSpacing);
    const double secondHoverTick = double(hoverSnapTick) + 0.4 * double(hoverSnapSpacing);
    const double thirdHoverTick = double(hoverSnapTick) + 1.1 * double(hoverSnapSpacing);
    check(view.grid().snapTick(firstHoverTick, false) == hoverSnapTick &&
              view.grid().snapTick(secondHoverTick, false) == hoverSnapTick &&
              view.grid().snapTick(thirdHoverTick, false) != hoverSnapTick,
          QStringLiteral("automation hover fixture did not resolve its snap cells"));
    page.cancelInteraction();
    const auto waitForTimers = [](int milliseconds) {
        QEventLoop loop;
        QTimer::singleShot(milliseconds, &loop, &QEventLoop::quit);
        loop.exec();
    };
    const int panTop = automationRowTop(page, pan);
    const int panHeight = heightFor(pan);
    const int panY = panTop + panHeight / 2;
    const uint64_t clickTick = 120;
    const int clickX = qRound(view.camera().displayX(double(clickTick), expected.plotOrigin, dpr));
    const QPoint clickPoint(clickX, panY);
    const QByteArray clickMidi = document.smf().write();
    const uint64_t clickRevision = document.revision();
    const int clickUndo = document.undoStack()->index();
    band.mouse(QEvent::MouseButtonPress, clickPoint, Qt::LeftButton, Qt::LeftButton,
               Qt::NoModifier);
    band.mouse(QEvent::MouseButtonRelease, clickPoint, Qt::LeftButton, Qt::NoButton,
               Qt::NoModifier);
    check(document.smf().write() == clickMidi && document.revision() == clickRevision &&
              document.undoStack()->index() == clickUndo,
          QStringLiteral("stationary automation click did not park the edit cursor"));
    if (document.undoStack()->index() != clickUndo)
        document.undoStack()->setIndex(clickUndo);
    page.documentChanged();
    const int sweepActivationDistance = expected.nodeDragActivationDistance;
    const QPoint subThresholdMove(0, std::max(0, sweepActivationDistance - 1));
    band.mouse(QEvent::MouseButtonPress, clickPoint, Qt::LeftButton, Qt::LeftButton,
               Qt::NoModifier);
    band.mouse(QEvent::MouseMove, clickPoint + subThresholdMove, Qt::NoButton, Qt::LeftButton,
               Qt::NoModifier);
    band.mouse(QEvent::MouseButtonRelease, clickPoint + subThresholdMove, Qt::LeftButton,
               Qt::NoButton, Qt::NoModifier);
    waitForTimers(QApplication::doubleClickInterval() + 1);
    check(document.smf().write() == clickMidi && document.revision() == clickRevision &&
              document.undoStack()->index() == clickUndo,
          QStringLiteral("sub-threshold automation jitter changed MIDI or Undo"));
    if (document.undoStack()->index() != clickUndo)
        document.undoStack()->setIndex(clickUndo);
    page.documentChanged();
    const QPoint verticalThresholdMove(0, sweepActivationDistance);
    band.mouse(QEvent::MouseButtonPress, clickPoint, Qt::LeftButton, Qt::LeftButton,
               Qt::NoModifier);
    band.mouse(QEvent::MouseMove, clickPoint + verticalThresholdMove, Qt::NoButton, Qt::LeftButton,
               Qt::NoModifier);
    band.mouse(QEvent::MouseButtonRelease, clickPoint + verticalThresholdMove, Qt::LeftButton,
               Qt::NoButton, Qt::NoModifier);
    check(document.smf().write() == clickMidi && document.revision() == clickRevision &&
              document.undoStack()->index() == clickUndo,
          QStringLiteral("automation sweep applied its activation slop as movement"));
    page.documentChanged();
    const QPoint verticalDragMove = verticalThresholdMove + QPoint(0, 1);
    band.mouse(QEvent::MouseButtonPress, clickPoint, Qt::LeftButton, Qt::LeftButton,
               Qt::NoModifier);
    band.mouse(QEvent::MouseMove, clickPoint + verticalThresholdMove, Qt::NoButton, Qt::LeftButton,
               Qt::NoModifier);
    band.mouse(QEvent::MouseMove, clickPoint + verticalDragMove, Qt::NoButton, Qt::LeftButton,
               Qt::NoModifier);
    band.mouse(QEvent::MouseButtonRelease, clickPoint + verticalDragMove, Qt::LeftButton,
               Qt::NoButton, Qt::NoModifier);
    const AutomationProjection sweepProjection(projectionGeometry, &page);
    const QRect sweepBody(0, panTop, automationViewportSize.width(), panHeight);
    const uint64_t sweepTick =
        view.grid().snapTick(sweepProjection.rawTickAt(clickPoint.x()), false);
    const int sweepValue = qRound(
        AutomationProjection::valueAtY(sweepBody, projectionGeometry, 0, 127, clickPoint.y() + 1));
    DocLanePoint sweepPoint;
    check(document.findLanePoint(0, pan.controller, sweepTick, &sweepPoint) &&
              sweepPoint.value == sweepValue && document.revision() == clickRevision + 1 &&
              document.undoStack()->index() == clickUndo + 1,
          QStringLiteral("automation sweep did not start one pixel beyond its activation slop"));
    document.undoStack()->setIndex(clickUndo);
    page.documentChanged();
    const int pdBaseUndo = document.undoStack()->index();
    const auto resetDrawFixture = [&] {
        page.cancelInteraction();
        document.undoStack()->setIndex(pdBaseUndo);
        page.documentChanged();
    };
    const auto pdPointAt = [&](uint64_t tick, int value) {
        return automationNodePoint(view, page, dpr, projectionGeometry, pan, tick, value);
    };
    resetDrawFixture();
    const uint64_t normalNodeTick = view.grid().snapTickDown(120.5);
    constexpr int normalNodeValue = 64;
    document.addLanePoint(0, pan.controller, normalNodeTick, normalNodeValue);
    page.documentChanged();
    const QPointF normalNodePoint = pdPointAt(normalNodeTick, normalNodeValue);
    const auto activatePointMenuAction = [](QMenu *menu, QAction *action) {
        if (!menu || !action) {
            if (menu)
                menu->close();
            return;
        }
        menu->setActiveAction(action);
        checks::events::sendKey(*menu, QEvent::KeyPress, Qt::Key_Return, Qt::NoModifier, QString{},
                                false, 1);
        if (QApplication::activePopupWidget() == menu) {
            const QRect actionRect = menu->actionGeometry(action);
            if (actionRect.isValid()) {
                const QPoint actionPoint = actionRect.center();
                checks::events::sendMouse(*menu, QEvent::MouseButtonPress, actionPoint,
                                          Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
                checks::events::sendMouse(*menu, QEvent::MouseButtonRelease, actionPoint,
                                          Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
            }
        }
        if (QApplication::activePopupWidget() == menu)
            menu->close();
    };
    if (popupMenus) {
        const QStringList normalPointMenuExpected{QStringLiteral("Set Value"),
                                                  QStringLiteral("Delete")};
        QStringList normalPointMenuActions;
        bool normalNodeValueDialog = false;
        QTimer::singleShot(0, [&] {
            auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
            if (!menu) {
                if (auto *dialog = qobject_cast<QDialog *>(QApplication::activeModalWidget()))
                    dialog->reject();
                return;
            }
            checkPopupParent(menu);
            QAction *setValueAction = nullptr;
            QAction *deleteAction = nullptr;
            for (QAction *action : menu->actions()) {
                normalPointMenuActions.push_back(action->text());
                if (action->text() == QStringLiteral("Set Value"))
                    setValueAction = action;
                else if (action->text() == QStringLiteral("Delete"))
                    deleteAction = action;
            }
            if (!setValueAction || !deleteAction) {
                menu->close();
                return;
            }
            QTimer::singleShot(0, [&] {
                if (auto *dialog =
                        qobject_cast<QInputDialog *>(QApplication::activeModalWidget())) {
                    normalNodeValueDialog = true;
                    checkPopupParent(dialog);
                    dialog->reject();
                } else if (auto *dialog =
                               qobject_cast<QDialog *>(QApplication::activeModalWidget())) {
                    checkPopupParent(dialog);
                    dialog->reject();
                }
            });
            activatePointMenuAction(menu, setValueAction);
        });
        band.mouse(QEvent::MouseButtonPress, normalNodePoint, Qt::RightButton, Qt::RightButton,
                   Qt::NoModifier);
        band.mouse(QEvent::MouseButtonRelease, normalNodePoint, Qt::RightButton, Qt::NoButton,
                   Qt::NoModifier);
        popupCheck(normalPointMenuActions == normalPointMenuExpected,
                   QStringLiteral("normal automation point context menu actions were not exactly "
                                  "Set Value, Delete"));
        popupCheck(normalNodeValueDialog,
                   QStringLiteral("right-clicking an automation node did not open value editing"));
    }
    bool normalClickDeleteDialog = false;
    const uint64_t normalClickDeleteRevision = document.revision();
    const int normalClickDeleteUndo = document.undoStack()->index();
    const auto normalClickPointsBefore = document.lanePoints(0, pan.controller);
    QTimer::singleShot(0, [&] {
        if (auto *dialog = qobject_cast<QInputDialog *>(QApplication::activeModalWidget())) {
            normalClickDeleteDialog = true;
            checkPopupParent(dialog);
            dialog->reject();
        }
    });
    band.mouse(QEvent::MouseButtonPress, normalNodePoint, Qt::LeftButton, Qt::LeftButton,
               Qt::NoModifier);
    band.mouse(QEvent::MouseButtonRelease, normalNodePoint, Qt::LeftButton, Qt::NoButton,
               Qt::NoModifier);
    waitForTimers(0);
    const auto normalClickPointsAfter = document.lanePoints(0, pan.controller);
    check(!normalClickDeleteDialog &&
              normalClickPointsAfter.size() + 1 == normalClickPointsBefore.size() &&
              document.revision() == normalClickDeleteRevision + 1 &&
              document.undoStack()->index() == normalClickDeleteUndo + 1,
          QStringLiteral("normal single-click did not delete an automation node (dialog %1, "
                         "points %2/%3, revision %4/%5, undo %6/%7)")
              .arg(normalClickDeleteDialog)
              .arg(normalClickPointsBefore.size())
              .arg(normalClickPointsAfter.size())
              .arg(document.revision())
              .arg(normalClickDeleteRevision + 1)
              .arg(document.undoStack()->index())
              .arg(normalClickDeleteUndo + 1));
    bool normalDoubleClickDialog = false;
    const uint64_t normalDoubleClickRevision = document.revision();
    QTimer::singleShot(0, [&] {
        if (auto *dialog = qobject_cast<QInputDialog *>(QApplication::activeModalWidget())) {
            normalDoubleClickDialog = true;
            checkPopupParent(dialog);
            dialog->reject();
        }
    });
    band.mouse(QEvent::MouseButtonDblClick, normalNodePoint, Qt::LeftButton, Qt::LeftButton,
               Qt::NoModifier);
    band.mouse(QEvent::MouseButtonRelease, normalNodePoint, Qt::LeftButton, Qt::NoButton,
               Qt::NoModifier);
    waitForTimers(0);
    check(!normalDoubleClickDialog && document.revision() == normalDoubleClickRevision,
          QStringLiteral("node double-click opened value entry after single-click delete"));
    // A row resize boundary owns the primary click, so its idle affordance
    // must not advertise an insertion in either adjacent row.
    band.leave();
    QCoreApplication::processEvents();
    const QRect lfoBody = automationRowBody(page, lfo);
    const QPoint boundaryPoint(page.canvas()->plotOrigin() + 48, lfoBody.top() + lfoBody.height());
    const QImage boundaryBaseline = captureAutomationViewport();
    band.mouse(QEvent::MouseMove, boundaryPoint, Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    QCoreApplication::processEvents();
    const QImage boundaryHover = captureAutomationViewport();
    check(automationInput->cursor().shape() == Qt::SplitVCursor,
          QStringLiteral("automation row boundary did not advertise its resize action"));
    check(!boundaryBaseline.isNull() && boundaryHover == boundaryBaseline,
          QStringLiteral("automation row boundary painted an insertion preview"));
    check(document.lanePoints(0, 11).empty(),
          QStringLiteral("empty-lane fixture CC 11 already has document points"));
    pumpQuickEvents();
    QAbstractItemModel *const automationTextModel =
        quickScene ? quickScene->automationTextModel() : nullptr;
    const QString lfoTitle = CCLanes::laneLabel(lfo.controller);
    const quint64 titleGridRevision =
        quickScene ? quickScene->layer(songview::TimelineQuickLayer::AutomationGrid).revision : 0;
    const auto lfoTextBefore = quickTextRect(automationTextModel, lfoTitle);
    const QString newLaneTitle = CCLanes::laneLabel(11);
    page.addEmptyLane(0, 11);
    pumpQuickEvents();
    const auto lfoTextAfter = quickTextRect(automationTextModel, lfoTitle);
    const auto newLaneText = quickTextRect(automationTextModel, newLaneTitle);
    check(lfoTextBefore && lfoTextAfter && newLaneText,
          QStringLiteral("adding a lane did not retain the existing Quick title text or publish "
                         "the new automation lane title"));
    check(quickScene && quickScene->layer(songview::TimelineQuickLayer::AutomationGrid).revision >
                            titleGridRevision,
          QStringLiteral("adding a lane did not rebuild the retained Quick automation grid"));
    check(rowsHaveUniqueIds(page.canvas()->rows()),
          QStringLiteral("adding a lane created a duplicate automation lane"));
    resetDrawFixture();
    page.removeEmptyLane(0, 11);
    QCoreApplication::processEvents();
    if (popupMenus) {
        const uint64_t popupNodeTick = view.grid().snapTickDown(168.5);
        constexpr int popupNodeValue = 70;
        document.addLanePoint(0, pan.controller, popupNodeTick, popupNodeValue);
        page.documentChanged();
        const QPointF popupNodePoint = pdPointAt(popupNodeTick, popupNodeValue);
        const uint64_t popupNodeRevision = document.revision();
        const int popupNodeUndo = document.undoStack()->index();
        bool popupNodeDeleteActionAvailable = false;
        QTimer::singleShot(0, [&] {
            auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
            if (!menu)
                return;
            checkPopupParent(menu);
            QAction *deleteAction = nullptr;
            for (QAction *action : menu->actions())
                if (action->text() == QStringLiteral("Delete"))
                    deleteAction = action;
            popupNodeDeleteActionAvailable = deleteAction != nullptr;
            activatePointMenuAction(menu, deleteAction);
        });
        band.mouse(QEvent::MouseButtonPress, popupNodePoint, Qt::RightButton, Qt::RightButton,
                   Qt::NoModifier);
        band.mouse(QEvent::MouseButtonRelease, popupNodePoint, Qt::RightButton, Qt::NoButton,
                   Qt::NoModifier);
        waitForTimers(0);
        DocLanePoint popupNodeAfterDelete;
        popupCheck(
            popupNodeDeleteActionAvailable &&
                !document.findLanePoint(0, pan.controller, popupNodeTick, &popupNodeAfterDelete) &&
                document.revision() == popupNodeRevision + 1 &&
                document.undoStack()->index() == popupNodeUndo + 1,
            QStringLiteral("automation node right-click Delete action did not commit one edit"));
    }
    const int duplicateTop = automationRowTop(page, lfo);
    check(duplicateTop >= 0, QStringLiteral("same-tick duplicate lane is missing"));
    const QPointF duplicatePoint =
        automationNodePoint(view, page, dpr, projectionGeometry, lfo, 96, 96);
    const QPointF duplicateTarget =
        automationNodePoint(view, page, dpr, projectionGeometry, lfo, 120, 96);
    const uint64_t duplicateRevision = document.revision();
    band.mouse(QEvent::MouseButtonPress, duplicatePoint, Qt::LeftButton, Qt::LeftButton,
               Qt::NoModifier);
    {
        const int arm = expected.nodeDragActivationDistance + 2;
        band.mouse(QEvent::MouseMove, duplicatePoint + QPoint(arm, 0), Qt::NoButton, Qt::LeftButton,
                   Qt::NoModifier);
    }
    band.mouse(QEvent::MouseMove, duplicateTarget, Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
    band.mouse(QEvent::MouseButtonRelease, duplicateTarget, Qt::LeftButton, Qt::NoButton,
               Qt::NoModifier);
    check(document.revision() == duplicateRevision + 1,
          QStringLiteral("same-tick automation point drag did not commit"));
    const auto duplicateRun = document.lanePoints(0, lfo.controller);
    QStringList duplicateState;
    for (const auto &point : duplicateRun)
        duplicateState.push_back(QStringLiteral("%1:%2").arg(point.tick).arg(point.value));
    const bool groupMoved =
        duplicateRun.size() == 2 && duplicateRun[0].tick == duplicateRun[1].tick &&
        duplicateRun[0].tick != 96 && duplicateRun[0].value == 32 && duplicateRun[1].value == 96;
    check(groupMoved,
          QStringLiteral("same-tick automation point drag did not move the effective node group "
                         "(%1)")
              .arg(duplicateState.join(QLatin1Char(','))));
    document.undoStack()->setIndex(clickUndo);
    page.documentChanged();
    if (popupMenus) {
        const QStringList pointMenuExpected{QStringLiteral("Set Value"), QStringLiteral("Delete")};
        QStringList pointMenuActions;
        bool pointValueInputOpened = false;
        QTimer::singleShot(0, [&] {
            auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
            if (!menu)
                return;
            checkPopupParent(menu);
            QAction *setValueAction = nullptr;
            QAction *deleteAction = nullptr;
            for (QAction *action : menu->actions()) {
                pointMenuActions.push_back(action->text());
                if (action->text() == QStringLiteral("Set Value"))
                    setValueAction = action;
                else if (action->text() == QStringLiteral("Delete"))
                    deleteAction = action;
            }
            if (pointMenuActions != pointMenuExpected || !setValueAction || !deleteAction) {
                menu->close();
                return;
            }
            QTimer::singleShot(0, [&] {
                if (auto *dialog =
                        qobject_cast<QInputDialog *>(QApplication::activeModalWidget())) {
                    pointValueInputOpened = true;
                    checkPopupParent(dialog);
                    dialog->setIntValue(64);
                    dialog->accept();
                } else if (auto *dialog =
                               qobject_cast<QDialog *>(QApplication::activeModalWidget())) {
                    checkPopupParent(dialog);
                    dialog->reject();
                }
            });
            activatePointMenuAction(menu, setValueAction);
        });
        const uint64_t pointEditRevision = document.revision();
        const int pointEditUndo = document.undoStack()->index();
        band.mouse(QEvent::MouseButtonPress, duplicatePoint, Qt::RightButton, Qt::RightButton,
                   Qt::NoModifier);
        band.mouse(QEvent::MouseButtonRelease, duplicatePoint, Qt::RightButton, Qt::NoButton,
                   Qt::NoModifier);
        QCoreApplication::processEvents();
        const auto editedRun = document.lanePoints(0, lfo.controller);
        QStringList editedState;
        for (const auto &point : editedRun)
            editedState.push_back(QStringLiteral("%1:%2").arg(point.tick).arg(point.value));
        std::vector<DocLanePoint> editedAt96;
        for (const auto &point : editedRun) {
            if (point.tick == 96)
                editedAt96.push_back(point);
        }
        popupCheck(
            pointMenuActions == pointMenuExpected,
            QStringLiteral("automation point context menu actions were not exactly Set Value, "
                           "Delete"));
        popupCheck(pointValueInputOpened,
                   QStringLiteral("right-clicking an automation point did not open numeric input"));
        popupCheck(editedAt96.size() == 2 && editedAt96.front().value == 32 &&
                       editedAt96.back().value == 64 &&
                       document.revision() == pointEditRevision + 1 &&
                       document.undoStack()->index() == pointEditUndo + 1,
                   QStringLiteral("numeric automation point input did not update the clicked point "
                                  "(points %1, revision %2/%3, undo %4/%5)")
                       .arg(editedState.join(QLatin1Char(',')))
                       .arg(document.revision())
                       .arg(pointEditRevision + 1)
                       .arg(document.undoStack()->index())
                       .arg(pointEditUndo + 1));
        document.undoStack()->setIndex(pointEditUndo);
        page.documentChanged();
        constexpr uint64_t retargetTick = 48;
        constexpr int retargetValue = 32;
        document.addLanePoint(0, lfo.controller, retargetTick, retargetValue);
        page.documentChanged();
        const QPointF retargetNodePoint = automationNodePoint(view, page, dpr, projectionGeometry,
                                                              lfo, retargetTick, retargetValue);
        const auto retargetBeforePoints = document.lanePoints(0, lfo.controller);
        auto retargetExpectedPoints = retargetBeforePoints;
        const auto retargetPointIt = std::find_if(
            retargetExpectedPoints.cbegin(), retargetExpectedPoints.cend(),
            [](const DocLanePoint &point) { return point.tick == 48 && point.value == 32; });
        const bool retargetPointPresent = retargetPointIt != retargetExpectedPoints.cend();
        if (retargetPointPresent)
            retargetExpectedPoints.erase(retargetPointIt);
        bool retargetMenuOpened = false;
        bool retargetMenuStayedOpen = false;
        QTimer::singleShot(0, [&] {
            auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
            if (!menu) {
                if (auto *popup = QApplication::activePopupWidget())
                    popup->close();
                return;
            }
            checkPopupParent(menu);
            retargetMenuOpened = true;
            QAction *deleteAction = nullptr;
            for (QAction *action : menu->actions()) {
                if (action->text() == QStringLiteral("Delete")) {
                    deleteAction = action;
                    break;
                }
            }
            if (!deleteAction) {
                menu->close();
                return;
            }
            const QPoint pointBGlobal =
                automationInput->mapToGlobal(viewportPosition(retargetNodePoint)).toPoint();
            checks::events::sendMouse(*menu, QEvent::MouseButtonPress,
                                      menu->mapFromGlobal(pointBGlobal), Qt::RightButton,
                                      Qt::RightButton, Qt::NoModifier);
            checks::events::sendMouse(*menu, QEvent::MouseButtonRelease,
                                      menu->mapFromGlobal(pointBGlobal), Qt::RightButton,
                                      Qt::NoButton, Qt::NoModifier);
            QCoreApplication::processEvents();
            retargetMenuStayedOpen = QApplication::activePopupWidget() == menu && menu->isVisible();
            activatePointMenuAction(menu, deleteAction);
        });
        const uint64_t retargetDeleteRevision = document.revision();
        const int retargetDeleteUndo = document.undoStack()->index();
        band.mouse(QEvent::MouseButtonPress, duplicatePoint, Qt::RightButton, Qt::RightButton,
                   Qt::NoModifier);
        band.mouse(QEvent::MouseButtonRelease, duplicatePoint, Qt::RightButton, Qt::NoButton,
                   Qt::NoModifier);
        QCoreApplication::processEvents();
        const auto retargetAfterPoints = document.lanePoints(0, lfo.controller);
        const auto hasRetargetPoint = [](const std::vector<DocLanePoint> &points, uint64_t tick,
                                         int value) {
            return std::any_of(points.cbegin(), points.cend(),
                               [tick, value](const DocLanePoint &point) {
                                   return point.tick == tick && point.value == value;
                               });
        };
        const bool retargetPointsMatch =
            retargetAfterPoints.size() == retargetExpectedPoints.size() &&
            std::equal(retargetAfterPoints.cbegin(), retargetAfterPoints.cend(),
                       retargetExpectedPoints.cbegin(),
                       [](const DocLanePoint &left, const DocLanePoint &right) {
                           return left.tick == right.tick && left.value == right.value;
                       });
        popupCheck(retargetMenuOpened && retargetMenuStayedOpen,
                   QStringLiteral("outside right-click dismissed the open automation point menu"));
        popupCheck(retargetPointPresent && retargetPointsMatch &&
                       hasRetargetPoint(retargetAfterPoints, 96, 96) &&
                       hasRetargetPoint(retargetAfterPoints, 96, 32) &&
                       !hasRetargetPoint(retargetAfterPoints, retargetTick, retargetValue) &&
                       document.revision() == retargetDeleteRevision + 1 &&
                       document.undoStack()->index() == retargetDeleteUndo + 1,
                   QStringLiteral("retargeted automation Delete did not remove point B only"));
        if (auto *popup = QApplication::activePopupWidget())
            popup->close();
        QCoreApplication::processEvents();
        document.undoStack()->setIndex(pointEditUndo);
        page.documentChanged();
    }

    page.refreshLiveState(live);
    check(rowExists(page.canvas()->rows(), lfo),
          QStringLiteral("SongView selected-track refresh did not retain primary lanes"));
    const auto hasRange = [](const EditorViewState &candidate, const EditorAutomationRowId &row,
                             uint8_t expected) {
        const auto it = candidate.laneRanges.find(row);
        return it != candidate.laneRanges.cend() && it->second == expected;
    };
    const auto sameAutomationState = [](const EditorViewState &first,
                                        const EditorViewState &second) {
        return first.laneHeight == second.laneHeight && first.laneHeights == second.laneHeights &&
               first.laneRanges == second.laneRanges && first.emptyLanes == second.emptyLanes &&
               first.hiddenLanes() == second.hiddenLanes();
    };
    page.addEmptyLane(int(modulation.track), modulation.controller);
    page.setLaneRange(modulation, 64);
    const EditorViewState automationBeforeDrawer = view.editorViewState();
    check(
        automationBeforeDrawer.emptyLanes.count(modulation) == 1 &&
            hasRange(automationBeforeDrawer, modulation, 64) &&
            page.automationViewState().emptyLanes.count(modulation) == 1 &&
            hasRange(page.automationViewState(), modulation, 64),
        QStringLiteral("AutomationPage lane commands did not publish empty-lane and range state"));
    view.setDrawerActivePage(EditorDrawerPage::Velocity);
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, false);
    view.setDrawerSectionHeight(EditorDrawerPage::Velocity, 240);
    QCoreApplication::processEvents();
    check(sameAutomationState(view.editorViewState(), automationBeforeDrawer),
          QStringLiteral("drawer updates discarded automation page state"));
    view.setDrawerActivePage(EditorDrawerPage::Automations);
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, 300);
    QCoreApplication::processEvents();
    const EditorViewState drawerBeforeAutomationPublication = view.editorViewState();
    const qreal zoomAnchorContentX = 200.0;
    const QPoint zoomAnchor(expected.plotOrigin + qRound(zoomAnchorContentX),
                            expected.defaultRowHeight / 2);
    const double tickBeforeZoom = view.camera().tickAtContentX(zoomAnchorContentX);
    const double zoomBefore = view.camera().pxPerBeat();
    band.wheel(zoomAnchor, QPoint(), QPoint(0, 120), Qt::NoButton, Qt::NoModifier,
               Qt::NoScrollPhase, false);
    QCoreApplication::processEvents();
    check(view.camera().pxPerBeat() > zoomBefore,
          QStringLiteral("plain wheel did not change automation time zoom"));
    check(std::abs(view.camera().tickAtContentX(zoomAnchorContentX) - tickBeforeZoom) < 0.001,
          QStringLiteral("automation time zoom did not preserve the tick under the cursor"));
    view.setEditorTimeZoom(live.timeZoom);
    view.setEditorHorizontalScroll(live.horizontalScroll);
    page.refreshLiveState(live);
    QCoreApplication::processEvents();

    const int initialHeight = page.automationViewState().laneHeight;
    band.wheel(QPointF(QPoint(expected.plotOrigin + 20, expected.defaultRowHeight / 2)), QPoint(),
               QPoint(0, 120), Qt::NoButton, Qt::ControlModifier, Qt::NoScrollPhase, false);
    check(page.automationViewState().laneHeight > initialHeight,
          QStringLiteral("Ctrl-wheel did not publish typed row-height state"));
    const EditorViewState afterAutomationPublication = view.editorViewState();
    check(afterAutomationPublication.velocity == drawerBeforeAutomationPublication.velocity &&
              afterAutomationPublication.automation ==
                  drawerBeforeAutomationPublication.automation &&
              afterAutomationPublication.activePage == drawerBeforeAutomationPublication.activePage,
          QStringLiteral("automation publication discarded drawer state"));

    const int selectionRowY = automationRowTop(page, pan) + heightFor(pan) / 2;
    const QPoint selectionStart(expected.plotOrigin + 24, selectionRowY);
    const QPoint selectionEnd(expected.plotOrigin + 216, selectionRowY);
    const QPoint selectionContractedEnd((selectionStart.x() + selectionEnd.x()) / 2,
                                        selectionEnd.y());
    band.mouse(QEvent::MouseButtonPress, selectionStart, Qt::RightButton, Qt::RightButton,
               Qt::NoModifier);
    band.mouse(QEvent::MouseMove, selectionEnd, Qt::NoButton, Qt::RightButton, Qt::NoModifier);
    band.mouse(QEvent::MouseButtonRelease, selectionContractedEnd, Qt::RightButton, Qt::NoButton,
               Qt::NoModifier);
    const auto timeSelection = view.selectionModel().timeSelection();
    check(timeSelection.active() &&
              timeSelection.scope == songview::EditorSelectionModel::TimeSelection::Lanes &&
              timeSelection.lanes.size() == 1,
          QStringLiteral("right drag did not commit a half-open automation selection"));
    if (popupMenus) {
        QStringList selectionActions;
        QTimer::singleShot(0, [&] {
            auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
            if (!menu)
                return;
            checkPopupParent(menu);
            for (QAction *action : menu->actions())
                selectionActions.push_back(action->text());
            menu->close();
        });
        const QPoint selectionInside(expected.plotOrigin + 100, selectionRowY);
        band.mouse(QEvent::MouseButtonPress, selectionInside, Qt::RightButton, Qt::RightButton,
                   Qt::NoModifier);
        band.mouse(QEvent::MouseButtonRelease, selectionInside, Qt::RightButton, Qt::NoButton,
                   Qt::NoModifier);
        popupCheck(selectionActions.contains(QStringLiteral("Clear time selection")),
                   QStringLiteral("right click inside a time selection did not open its menu"));
    }
    const QPoint selectionOutside(expected.plotOrigin + 260, selectionRowY);
    band.mouse(QEvent::MouseButtonPress, selectionOutside, Qt::LeftButton, Qt::LeftButton,
               Qt::NoModifier);
    check(!view.selectionModel().timeSelection().active(),
          QStringLiteral("left click outside a time selection did not clear it"));
    band.mouse(QEvent::MouseButtonRelease, selectionOutside, Qt::LeftButton, Qt::NoButton,
               Qt::NoModifier);
    view.selectionModel().setTimeSelection(timeSelection);
    band.mouse(QEvent::MouseButtonPress, selectionOutside, Qt::RightButton, Qt::RightButton,
               Qt::NoModifier);
    check(!view.selectionModel().timeSelection().active(),
          QStringLiteral("right click outside a time selection did not clear it"));
    QTimer::singleShot(0, [&] {
        if (auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget())) {
            checkPopupParent(menu);
            menu->close();
        }
    });
    band.mouse(QEvent::MouseButtonRelease, selectionOutside, Qt::RightButton, Qt::NoButton,
               Qt::NoModifier);
    view.selectionModel().setTimeSelection(timeSelection);
    const QPoint laneHeader(expected.plotOrigin - layout::space(layout::Space::One), selectionRowY);
    band.mouse(QEvent::MouseButtonPress, laneHeader, Qt::LeftButton, Qt::LeftButton,
               Qt::NoModifier);
    band.mouse(QEvent::MouseButtonRelease, laneHeader, Qt::LeftButton, Qt::NoButton,
               Qt::NoModifier);
    check(!view.selectionModel().timeSelection().active(),
          QStringLiteral("left click in a lane header did not clear the time selection"));
    view.selectionModel().setTimeSelection(timeSelection);
    band.key(QEvent::KeyPress, Qt::Key_Escape, Qt::NoModifier);
    QCoreApplication::processEvents();
    check(!view.selectionModel().timeSelection().active() &&
              view.selectionModel().timeSelection().scope ==
                  songview::EditorSelectionModel::TimeSelection::Tracks &&
              view.selectionModel().timeSelection().startTick == 0 &&
              view.selectionModel().timeSelection().endTick == 0 &&
              view.selectionModel().timeSelection().lanes.empty(),
          QStringLiteral("AutomationCanvas clear did not clear SongView's canonical selection"));
    page.canvas()->rebuildRows();
    page.refreshLiveState(live);
    QCoreApplication::processEvents();
    check(!view.selectionModel().timeSelection().active() &&
              view.selectionModel().timeSelection().lanes.empty(),
          QStringLiteral("cleared automation selection was resurrected by row rebuild"));

    songview::EditorSelectionModel::TimeSelection noncontiguous;
    noncontiguous.startTick = 24;
    noncontiguous.endTick = 72;
    noncontiguous.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    noncontiguous.lanes = {{int(pan.track), pan.controller}, {int(bend.track), bend.controller}};
    view.selectionModel().setTimeSelection(noncontiguous);
    page.refreshLiveState(live);
    QCoreApplication::processEvents();
    check(view.selectionModel().timeSelection().lanes == noncontiguous.lanes,
          QStringLiteral("canonical lane selection replacement was not retained"));

    noncontiguous.lanes = {{int(lfo.track), lfo.controller}};
    view.selectionModel().setTimeSelection(noncontiguous);
    page.refreshLiveState(live);
    band.key(QEvent::KeyPress, Qt::Key_Escape, Qt::NoModifier);
    QCoreApplication::processEvents();
    check(!view.selectionModel().timeSelection().active() &&
              view.selectionModel().timeSelection().lanes.empty(),
          QStringLiteral("AutomationCanvas lane replacement clear did not reach SongView"));

    // Multi-node time selection highlights nodes like velocity, and dragging
    // one selected node moves the whole group as a single undoable edit.
    {
        page.cancelInteraction();
        live.timeZoom = 96.0;
        view.setEditorTimeZoom(live.timeZoom);
        live.horizontalScroll = 0.0;
        view.setEditorHorizontalScroll(live.horizontalScroll);
        const uint64_t groupA = view.grid().snapTick(48.0, false);
        const uint64_t groupB = view.grid().snapTick(72.0, false);
        const uint64_t groupC = view.grid().snapTick(120.0, false);
        constexpr int groupAValue = 40;
        constexpr int groupBValue = 80;
        constexpr int groupCValue = 55;
        document.writeLanePoints(
            0, pan.controller, 0, timeline->lengthTicks,
            {{groupA, groupAValue}, {groupB, groupBValue}, {groupC, groupCValue}});
        page.documentChanged();
        live.documentRevision = document.revision();
        page.refreshLiveState(live);
        QCoreApplication::processEvents();
        const QRect groupPanBody = automationRowBody(page, pan);
        const int groupPlotTop = groupPanBody.top() + expected.valuePlotPadding;
        const int groupPlotBottom = groupPanBody.bottom() + 1 - expected.valuePlotPadding;
        const auto groupPointAt = [&](uint64_t tick, int value) {
            return QPoint(qRound(view.camera().displayX(double(tick), expected.plotOrigin, dpr)),
                          groupPlotBottom - value * (groupPlotBottom - groupPlotTop) / 127);
        };
        const QPoint groupAPoint = groupPointAt(groupA, groupAValue);
        const QPoint groupBPoint = groupPointAt(groupB, groupBValue);
        const QPoint groupCPoint = groupPointAt(groupC, groupCValue);
        const auto setTrackRange = [&](uint64_t endTick) {
            songview::EditorSelectionModel::TimeSelection selection;
            selection.startTick = groupA;
            selection.endTick = endTick;
            view.selectionModel().setTimeSelection(selection);
            live.horizontalScroll = 0.0;
            view.setEditorHorizontalScroll(live.horizontalScroll);
            page.refreshLiveState(live);
            pumpQuickEvents();
        };
        const quint64 nodesRevisionBefore =
            quickScene ? quickScene->layer(songview::TimelineQuickLayer::AutomationNodes).revision
                       : 0;
        setTrackRange(groupB);
        const songview::TimelineQuickLayerData excludedNodes =
            quickScene ? quickScene->layer(songview::TimelineQuickLayer::AutomationNodes)
                       : songview::TimelineQuickLayerData{};
        const QImage excludedNodesFramebuffer = captureAutomationViewport();
        setTrackRange(groupB + 1);
        const songview::TimelineQuickLayerData includedNodes =
            quickScene ? quickScene->layer(songview::TimelineQuickLayer::AutomationNodes)
                       : songview::TimelineQuickLayerData{};
        const QImage includedNodesFramebuffer = captureAutomationViewport();
        const QColor selectionColor = automationInput->palette().highlight().color();
        const qreal ringRadius = projectionGeometry.selectedNodeRingRadius;
        const qreal ringWidth = projectionGeometry.selectedNodeRingDipWidth;
        const auto hasSelectionRing = [&](const songview::TimelineQuickLayerData &layer,
                                          const QPoint &contentPoint) {
            const QPointF center = contentToViewport(QRect(contentPoint, QSize(1, 1))).topLeft();
            const qreal tolerance = layout::singlePixel();
            const qreal inner = std::max<qreal>(0.0, ringRadius - ringWidth / 2.0 - tolerance);
            const qreal outer = ringRadius + ringWidth / 2.0 + tolerance;
            const qreal innerSquared = inner * inner;
            const qreal outerSquared = outer * outer;
            const auto onRing = [&](const QPointF &point) {
                const QPointF delta = point - center;
                const qreal distanceSquared = delta.x() * delta.x() + delta.y() * delta.y();
                return distanceSquared >= innerSquared && distanceSquared <= outerSquared;
            };
            return std::count_if(layer.triangles.cbegin(), layer.triangles.cend(),
                                 [&](const songview::TimelineQuickTriangle &triangle) {
                                     return triangle.firstColor == selectionColor &&
                                            triangle.secondColor == selectionColor &&
                                            triangle.thirdColor == selectionColor &&
                                            onRing(triangle.first) && onRing(triangle.second) &&
                                            onRing(triangle.third);
                                 }) >= 4;
        };
        const auto hasRenderedSelectionRing = [&](const QImage &framebuffer,
                                                  const QPoint &contentPoint) {
            if (framebuffer.isNull())
                return false;
            const qreal framebufferDpr = framebuffer.devicePixelRatio();
            if (framebufferDpr <= 0.0)
                return false;
            const QPointF center = contentToViewport(QRect(contentPoint, QSize(1, 1))).topLeft();
            const qreal tolerance = 2 * layout::singlePixel();
            const qreal inner = std::max<qreal>(0.0, ringRadius - ringWidth / 2.0 - tolerance);
            const qreal outer = ringRadius + ringWidth / 2.0 + tolerance;
            const qreal innerSquared = inner * inner;
            const qreal outerSquared = outer * outer;
            const int left = std::max(0, qFloor((center.x() - outer) * framebufferDpr));
            const int top = std::max(0, qFloor((center.y() - outer) * framebufferDpr));
            const int right =
                std::min(framebuffer.width() - 1, qCeil((center.x() + outer) * framebufferDpr));
            const int bottom =
                std::min(framebuffer.height() - 1, qCeil((center.y() + outer) * framebufferDpr));
            for (int y = top; y <= bottom; ++y) {
                for (int x = left; x <= right; ++x) {
                    const QPointF delta((x + 0.5) / framebufferDpr - center.x(),
                                        (y + 0.5) / framebufferDpr - center.y());
                    const qreal distanceSquared = delta.x() * delta.x() + delta.y() * delta.y();
                    const QColor pixel = framebuffer.pixelColor(x, y);
                    if (distanceSquared >= innerSquared && distanceSquared <= outerSquared &&
                        pixel.alpha() >= 32 && std::abs(pixel.red() - selectionColor.red()) <= 64 &&
                        std::abs(pixel.green() - selectionColor.green()) <= 64 &&
                        std::abs(pixel.blue() - selectionColor.blue()) <= 64) {
                        return true;
                    }
                }
            }
            return false;
        };
        check(quickScene && excludedNodes.revision > nodesRevisionBefore &&
                  includedNodes.revision > excludedNodes.revision &&
                  hasSelectionRing(excludedNodes, groupAPoint) &&
                  !hasSelectionRing(excludedNodes, groupBPoint) &&
                  !hasSelectionRing(excludedNodes, groupCPoint) &&
                  hasSelectionRing(includedNodes, groupAPoint) &&
                  hasSelectionRing(includedNodes, groupBPoint) &&
                  !hasSelectionRing(includedNodes, groupCPoint) &&
                  hasRenderedSelectionRing(excludedNodesFramebuffer, groupAPoint) &&
                  hasRenderedSelectionRing(includedNodesFramebuffer, groupAPoint) &&
                  hasRenderedSelectionRing(includedNodesFramebuffer, groupBPoint),
              QStringLiteral("track time selection did not retain or render half-open Quick node "
                             "rings in the automation nodes layer"));

        songview::EditorSelectionModel::TimeSelection groupSelection;
        groupSelection.startTick = groupA;
        groupSelection.endTick = groupB + 1;
        groupSelection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
        groupSelection.lanes = {{int(pan.track), pan.controller}};
        view.selectionModel().setTimeSelection(groupSelection);
        page.refreshLiveState(live);
        QCoreApplication::processEvents();
        const auto &selectedGroup = view.selectionModel().timeSelection();
        check(selectedGroup.active() && selectedGroup.startTick == groupA &&
                  selectedGroup.endTick == groupB + 1 &&
                  selectedGroup.scope == songview::EditorSelectionModel::TimeSelection::Lanes &&
                  selectedGroup.lanes == groupSelection.lanes,
              QStringLiteral("automation node selection did not retain its canonical lane range"));
        const uint64_t beforeGroupMove = document.revision();
        const int undoBeforeGroupMove = document.undoStack()->index();
        const int groupArm = expected.nodeDragActivationDistance + 2;
        const QPoint groupDragArm = groupAPoint + QPoint(groupArm, 0);
        const QPoint groupDragEnd = groupAPoint + QPoint(48, -18);
        band.mouse(QEvent::MouseButtonPress, groupAPoint, Qt::LeftButton, Qt::LeftButton,
                   Qt::NoModifier);
        band.mouse(QEvent::MouseMove, groupDragArm, Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
        band.mouse(QEvent::MouseMove, groupDragEnd, Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
        band.mouse(QEvent::MouseButtonRelease, groupDragEnd, Qt::LeftButton, Qt::NoButton,
                   Qt::NoModifier);
        QCoreApplication::processEvents();
        DocLanePoint stayedC{};
        const bool foundA = document.findLanePoint(0, pan.controller, groupA, nullptr);
        const bool foundB = document.findLanePoint(0, pan.controller, groupB, nullptr);
        const bool foundC = document.findLanePoint(0, pan.controller, groupC, &stayedC) &&
                            stayedC.value == groupCValue;
        const auto &afterSelection = view.selectionModel().timeSelection();
        check(document.revision() == beforeGroupMove + 1 &&
                  document.undoStack()->index() == undoBeforeGroupMove + 1 && !foundA && !foundB &&
                  foundC && afterSelection.active() &&
                  afterSelection.scope == songview::EditorSelectionModel::TimeSelection::Lanes,
              QStringLiteral("group-dragging selected automation nodes did not move as one edit"));
        std::vector<DocLanePoint> survivors;
        for (const DocLanePoint &point : document.lanePoints(0, pan.controller)) {
            if (point.tick != groupC)
                survivors.push_back(point);
        }
        check(survivors.size() == 2,
              QStringLiteral("group move did not preserve two selected nodes"));
        int64_t sharedDTick = 0;
        bool structureOk = false;
        if (survivors.size() == 2) {
            std::sort(survivors.begin(), survivors.end(),
                      [](const DocLanePoint &left, const DocLanePoint &right) {
                          return left.tick < right.tick;
                      });
            // Values clamp per lane, so only the shared tick shift is exact.
            if (int64_t(survivors[0].tick) - int64_t(groupA) ==
                    int64_t(survivors[1].tick) - int64_t(groupB) &&
                (survivors[0].tick != groupA || survivors[1].tick != groupB ||
                 survivors[0].value != groupAValue || survivors[1].value != groupBValue)) {
                sharedDTick = int64_t(survivors[0].tick) - int64_t(groupA);
                structureOk = true;
            } else if (int64_t(survivors[0].tick) - int64_t(groupB) ==
                           int64_t(survivors[1].tick) - int64_t(groupA) &&
                       (survivors[0].tick != groupB || survivors[1].tick != groupA)) {
                sharedDTick = int64_t(survivors[0].tick) - int64_t(groupB);
                structureOk = true;
            }
        }
        check(structureOk,
              QStringLiteral("selected automation nodes did not share one group-drag delta"));
        check(afterSelection.active() &&
                  afterSelection.startTick ==
                      uint64_t(
                          std::max<int64_t>(0, int64_t(groupSelection.startTick) + sharedDTick)) &&
                  afterSelection.endTick ==
                      uint64_t(std::max<int64_t>(0, int64_t(groupSelection.endTick) + sharedDTick)),
              QStringLiteral("group-drag did not carry the automation time selection"));
        document.undoStack()->undo();
        page.documentChanged();
        live.documentRevision = document.revision();
        page.refreshLiveState(live);
        QCoreApplication::processEvents();
        DocLanePoint restoredA{};
        DocLanePoint restoredB{};
        check(document.findLanePoint(0, pan.controller, groupA, &restoredA) &&
                  restoredA.value == groupAValue &&
                  document.findLanePoint(0, pan.controller, groupB, &restoredB) &&
                  restoredB.value == groupBValue &&
                  document.undoStack()->index() == undoBeforeGroupMove,
              QStringLiteral("undo did not restore the automation group move"));
        for (const int key : {Qt::Key_Delete, Qt::Key_Backspace}) {
            view.selectionModel().setTimeSelection(groupSelection);
            page.refreshLiveState(live);
            QCoreApplication::processEvents();
            const uint64_t beforeDelete = document.revision();
            const int undoBeforeDelete = document.undoStack()->index();
            band.key(QEvent::KeyPress, key, Qt::NoModifier);
            QCoreApplication::processEvents();
            DocLanePoint untouchedC{};
            check(!document.findLanePoint(0, pan.controller, groupA, nullptr) &&
                      !document.findLanePoint(0, pan.controller, groupB, nullptr) &&
                      document.findLanePoint(0, pan.controller, groupC, &untouchedC) &&
                      untouchedC.value == groupCValue && document.revision() == beforeDelete + 1 &&
                      document.undoStack()->index() == undoBeforeDelete + 1,
                  QStringLiteral("%1 did not delete selected automation nodes as one edit")
                      .arg(key == Qt::Key_Delete ? QStringLiteral("Delete")
                                                 : QStringLiteral("Backspace")));
            document.undoStack()->undo();
            page.documentChanged();
            live.documentRevision = document.revision();
            page.refreshLiveState(live);
            QCoreApplication::processEvents();
        }
        view.selectionModel().clearTimeSelection();
        page.refreshLiveState(live);
        QCoreApplication::processEvents();
    }

    // Shift+click a selected node arms axis-lock: after a short free move,
    // mostly-horizontal travel keeps values; mostly-vertical keeps ticks.
    {
        page.cancelInteraction();
        live.timeZoom = 96.0;
        view.setEditorTimeZoom(live.timeZoom);
        live.horizontalScroll = 0.0;
        view.setEditorHorizontalScroll(live.horizontalScroll);
        const uint64_t lockA = view.grid().snapTick(48.0, false);
        const uint64_t lockB = view.grid().snapTick(72.0, false);
        constexpr int lockAValue = 36;
        constexpr int lockBValue = 60;
        document.writeLanePoints(0, pan.controller, 0, timeline->lengthTicks,
                                 {{lockA, lockAValue}, {lockB, lockBValue}});
        page.documentChanged();
        live.documentRevision = document.revision();
        page.refreshLiveState(live);
        QCoreApplication::processEvents();
        const int lockPanTop = automationRowTop(page, pan);
        const int lockPanHeight = heightFor(pan);
        const int lockPlotTop = lockPanTop + expected.valuePlotPadding;
        const int lockPlotBottom = lockPanTop + lockPanHeight - expected.valuePlotPadding;
        const auto lockPointAt = [&](uint64_t tick, int value) {
            return QPoint(qRound(view.camera().displayX(double(tick), expected.plotOrigin, dpr)),
                          lockPlotBottom - value * (lockPlotBottom - lockPlotTop) / 127);
        };
        const QPoint lockAPoint = lockPointAt(lockA, lockAValue);
        songview::EditorSelectionModel::TimeSelection lockSelection;
        lockSelection.startTick = lockA;
        lockSelection.endTick = lockB + 1;
        lockSelection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
        lockSelection.lanes = {{int(pan.track), pan.controller}};
        view.selectionModel().setTimeSelection(lockSelection);
        page.refreshLiveState(live);
        QCoreApplication::processEvents();
        const int dragThreshold = expected.nodeDragActivationDistance + 8;
        const QPoint horizontalArm = lockAPoint + QPoint(dragThreshold, 0);
        const QPoint horizontalEnd = lockAPoint + QPoint(dragThreshold + 40, 4);
        const uint64_t beforeHorizontal = document.revision();
        band.mouse(QEvent::MouseButtonPress, lockAPoint, Qt::LeftButton, Qt::LeftButton,
                   Qt::ShiftModifier);
        band.mouse(QEvent::MouseMove, horizontalArm, Qt::NoButton, Qt::LeftButton,
                   Qt::ShiftModifier);
        band.mouse(QEvent::MouseMove, horizontalEnd, Qt::NoButton, Qt::LeftButton,
                   Qt::ShiftModifier);
        band.mouse(QEvent::MouseButtonRelease, horizontalEnd, Qt::LeftButton, Qt::NoButton,
                   Qt::ShiftModifier);
        QCoreApplication::processEvents();
        DocLanePoint horizontalA{};
        DocLanePoint horizontalB{};
        const bool foundLockA = document.findLanePoint(0, pan.controller, lockA, &horizontalA);
        const bool foundLockB = document.findLanePoint(0, pan.controller, lockB, &horizontalB);
        check(document.revision() == beforeHorizontal + 1 && !foundLockA && !foundLockB,
              QStringLiteral("Shift horizontal axis-lock did not move selected automation ticks"));
        bool valuesPreserved = true;
        int movedNodes = 0;
        for (const DocLanePoint &point : document.lanePoints(0, pan.controller)) {
            ++movedNodes;
            if (point.value != lockAValue && point.value != lockBValue)
                valuesPreserved = false;
        }
        check(movedNodes == 2 && valuesPreserved,
              QStringLiteral("Shift horizontal axis-lock changed automation values"));
        document.undoStack()->undo();
        page.documentChanged();
        live.documentRevision = document.revision();
        page.refreshLiveState(live);
        QCoreApplication::processEvents();
        view.selectionModel().setTimeSelection(lockSelection);
        page.refreshLiveState(live);
        QCoreApplication::processEvents();
        const QPoint verticalArm = lockAPoint + QPoint(0, -dragThreshold);
        const QPoint verticalEnd = lockAPoint + QPoint(0, -(dragThreshold + 24));
        const uint64_t beforeVertical = document.revision();
        band.mouse(QEvent::MouseButtonPress, lockAPoint, Qt::LeftButton, Qt::LeftButton,
                   Qt::ShiftModifier);
        band.mouse(QEvent::MouseMove, verticalArm, Qt::NoButton, Qt::LeftButton, Qt::ShiftModifier);
        band.mouse(QEvent::MouseMove, verticalEnd, Qt::NoButton, Qt::LeftButton, Qt::ShiftModifier);
        band.mouse(QEvent::MouseButtonRelease, verticalEnd, Qt::LeftButton, Qt::NoButton,
                   Qt::ShiftModifier);
        QCoreApplication::processEvents();
        DocLanePoint verticalA{};
        DocLanePoint verticalB{};
        const bool keptTicks = document.findLanePoint(0, pan.controller, lockA, &verticalA) &&
                               document.findLanePoint(0, pan.controller, lockB, &verticalB);
        check(document.revision() == beforeVertical + 1 && keptTicks &&
                  verticalA.value != lockAValue && verticalB.value != lockBValue &&
                  (verticalA.value - lockAValue) * (verticalB.value - lockBValue) > 0,
              QStringLiteral("Shift vertical axis-lock did not move values while keeping ticks"));
        document.undoStack()->undo();
        page.documentChanged();
        live.documentRevision = document.revision();
        view.selectionModel().clearTimeSelection();
        page.refreshLiveState(live);
        QCoreApplication::processEvents();
    }

    band.leave();

    const auto checkCancelledGesture = [&](auto cancel, const QString &route) {
        const uint64_t revision = document.revision();
        const int undoIndex = document.undoStack()->index();
        const QPoint start(expected.plotOrigin + 24,
                           automationRowTop(page, pan) + heightFor(pan) / 2);
        band.mouse(QEvent::MouseButtonPress, start, Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        band.mouse(QEvent::MouseMove, start + QPoint(80, 12), Qt::NoButton, Qt::LeftButton,
                   Qt::NoModifier);
        cancel();
        band.mouse(QEvent::MouseButtonRelease, start + QPoint(80, 12), Qt::LeftButton, Qt::NoButton,
                   Qt::NoModifier);
        check(document.revision() == revision && document.undoStack()->index() == undoIndex,
              QStringLiteral("%1 cancellation changed the document").arg(route));
    };
    checkCancelledGesture([&] { page.cancelInteraction(); }, QStringLiteral("explicit"));
    checkCancelledGesture([&] { page.documentChanged(); }, QStringLiteral("document mutation"));
    checkCancelledGesture(
        [&] {
            QEvent event(QEvent::UngrabMouse);
            QCoreApplication::sendEvent(automationInput, &event);
        },
        QStringLiteral("mouse-grab loss"));
    checkCancelledGesture(
        [&] {
            page.canvas()->inputCancelled(songview::TimelineInputCancelReason::WindowDeactivated);
        },
        QStringLiteral("window loss"));
    checkCancelledGesture([&] { band.key(QEvent::KeyPress, Qt::Key_Escape, Qt::NoModifier); },
                          QStringLiteral("Escape"));
    checkCancelledGesture(
        [&] {
            drawer->cancelVisiblePageInteraction();
            QCoreApplication::processEvents();
        },
        QStringLiteral("page hide"));

    for (const double playhead : {-3.0, 10.49, 10.5, 10.51}) {
        live.playback = {playhead, true};
        page.refreshLiveState(live);
        (void)captureAutomationViewport();
        const uint64_t contextTick = drawerContextTick(playhead);
        const auto ownerContext = view.voiceContext(contextTick);
        check(ownerContext.voice == &voicegroup.voices[0] && ownerContext.voiceSlot == 0,
              QStringLiteral("playing voice context did not follow the rounded playhead at %1")
                  .arg(playhead));
    }
    live.playback.playing = false;
    view.setEditCursorTick(24);
    page.refreshLiveState(live);
    (void)captureAutomationViewport();
    const auto stoppedVoice = view.voiceContext(24);
    check(stoppedVoice.voiceSlot == 3,
          QStringLiteral("stopped voice context did not use the edit cursor (slot %1)")
              .arg(stoppedVoice.voiceSlot));
    if (!popupMenus)
        checkAutomationNodePaint(view, page, document, live, failures);

    view.setDocument(&document);
    while (document.undoStack()->index() > 0)
        document.undoStack()->undo();
    check(document.smf().write() == baseline,
          QStringLiteral("automation check did not restore its scratch document"));
    document.undoStack()->clear();
    check(page.automationViewState().laneRanges.at(lfo) == 91 &&
              page.automationViewState().isLaneHidden(volume),
          QStringLiteral("document refresh did not retain surviving typed row state"));
    const char *checkName = popupMenus ? "automation-popup-check" : "automation-check";
    if (!screenshotPath.isEmpty()) {
        QString captureError;
        const QImage screenshot =
            checks::support::captureQuickBand(view, automationBandRect(), &captureError);
        if (screenshot.isNull())
            std::fprintf(stderr, "%s: could not capture %s: %s\n", checkName,
                         qUtf8Printable(screenshotPath), qUtf8Printable(captureError));
        else if (screenshot.save(screenshotPath))
            std::printf("%s: wrote %s\n", checkName, qUtf8Printable(screenshotPath));
        else
            std::fprintf(stderr, "%s: could not write %s\n", checkName,
                         qUtf8Printable(screenshotPath));
    }
    if (failures == 0)
        std::printf("%s: PASS %s\n", checkName, qUtf8Printable(songLabel));
    return failures == 0 ? 0 : 1;
}

} // namespace

int runAutomationCheck(const QString &scratchProject, const QString &songLabel)
{
    return runAutomationCheckImpl(scratchProject, songLabel, {}, false);
}

int runAutomationPopupMenuCheck(const QString &scratchProject, const QString &songLabel,
                                const QString &screenshotPath)
{
    return runAutomationCheckImpl(scratchProject, songLabel, screenshotPath, true);
}
