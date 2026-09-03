#include "rollcheckplayhead.h"

#include "checks/support/quickframebuffer.h"
#include "checks/support/timelinequickcheck.h"

#include <QColor>
#include <QCoreApplication>
#include <QDeadlineTimer>
#include <QEvent>
#include <QEventLoop>
#include <QImage>
#include <QObject>
#include <QPixmap>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRectF>

#include <QScopeGuard>
#include <QVariant>
#include <QtGlobal>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>

#include "core/miditimeline.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/drawerchrome.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/layout.h"
#include "ui/playheadoverlay.h"
#include "ui/songview.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickchrome.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timelinebandlayout.h"
#include "ui/theme/themeruntime.h"

namespace {

struct ChromeCopies {
    const char *name;
    songview::TimelineChromeItem *hover = nullptr;
    songview::TimelineChromeItem *edit = nullptr;
};

std::array<ChromeCopies, 7> chromeCopies(QQuickItem &root)
{
    std::array<ChromeCopies, 7> copies{{
        {"Ruler"},
        {"Roll"},
        {"Automation"},
        {"Velocity"},
        {"VoiceChanges"},
        {"OtherEvents"},
        {"TrackHeaders"},
    }};
    for (ChromeCopies &copy : copies) {
        const QString prefix = QStringLiteral("timelineQuick") + QString::fromLatin1(copy.name);
        copy.hover = root.findChild<songview::TimelineChromeItem *>(prefix + "HoverChrome");
        copy.edit = root.findChild<songview::TimelineChromeItem *>(prefix + "EditChrome");
    }
    return copies;
}

qreal playheadCenterAt(const QImage &image, int logicalY, const QColor &color)
{
    int first = -1;
    int last = -1;
    const int logicalWidth = qFloor(image.deviceIndependentSize().width());
    for (int x = 0; x < logicalWidth; ++x) {
        if (!checks::support::hasPlayheadPixel(image, QRect(x, logicalY, 1, 1), color))
            continue;
        if (first < 0)
            first = x;
        last = x;
    }
    return first < 0 ? -1.0 : qreal(first + last) / 2.0;
}

QPixmap grabPlayhead(SongView &view, songview::PlayheadOverlay &overlay, QStringList &failures)
{
#ifdef __APPLE__
    if (songview::platformPlayheadRendererEnabled())
        return renderMacPlayheadOverlay(view, failures);
#else
    (void)view;
    (void)failures;
#endif
    QWidget *const fallback = overlay.fallbackWidget();
    return fallback ? fallback->grab() : QPixmap{};
}

bool expectsCapturablePlayhead()
{
#ifdef __APPLE__
    return songview::platformPlayheadRendererEnabled();
#else
    return false;
#endif
}

void checkAutomationHover(SongView &view, QStringList &failures)
{
    auto *page = view.editorDrawer() ? view.editorDrawer()->automationPage() : nullptr;
    auto *canvas = page ? page->canvas() : nullptr;
    if (!page || !canvas)
        return;

    const int selectedTrack = view.selectionModel().primaryTrack();
    if (selectedTrack < 0 || selectedTrack > 15) {
        failures.append("automation hover fixture did not have a selected track");
        return;
    }
    const EditorViewState savedEditorState = view.editorViewState();
    const int savedScroll = page->verticalScroll();
    const bool savedPencilMode = canvas->pencilMode();
    auto *quickCanvas =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    songview::TimelineInputItem *automationInput = nullptr;
    const auto clearQuickHover = [&] {
        if (!automationInput || !automationInput->interaction())
            return;
        automationInput->interaction()->pointerLeave();
        checks::support::pumpQuick();
    };
    const auto restoreState = qScopeGuard([&] {
        clearQuickHover();
        if (canvas->pencilMode() != savedPencilMode)
            canvas->setPencilMode(savedPencilMode);
        if (view.editorViewState() != savedEditorState) {
            view.applyEditorViewState(savedEditorState);
            checks::support::pumpQuick();
        }
        if (page->verticalScroll() != savedScroll)
            page->setVerticalScroll(savedScroll);
        checks::support::pumpQuick();
    });

    const EditorAutomationRowId fixtureLane{EditorAutomationRowKind::ControlChange,
                                            static_cast<uint8_t>(selectedTrack),
                                            CoreTimeDefaults::kCcModulation};
    const auto findFixtureHandle = [&] {
        const auto &rows = canvas->rows();
        for (int index = 0; index < int(rows.size()); ++index) {
            if (rows[std::size_t(index)].id == fixtureLane)
                return LaneHandle{index + 1};
        }
        return LaneHandle{};
    };
    LaneHandle fixtureHandle = findFixtureHandle();
    if (!fixtureHandle.valid()) {
        EditorViewState fixtureState = view.editorViewState();
        fixtureState.emptyLanes.insert(fixtureLane);
        fixtureState.unhideLane(fixtureLane);
        view.applyEditorViewState(fixtureState);
        checks::support::pumpQuick();
        fixtureHandle = findFixtureHandle();
    }
    if (!fixtureHandle.valid()) {
        failures.append("automation hover fixture did not expose its CC lane");
        return;
    }
    const QRect body = canvas->laneBody(fixtureHandle);
    if (body.isEmpty()) {
        failures.append("automation hover fixture did not expose a live CC body");
        return;
    }

    const std::optional<songview::TimelineBandGeometry> &automationBand =
        view.timelineBandLayout().geometry(songview::TimelineBand::Automation);
    if (!automationBand)
        return;
    const QRect automationRect = automationBand->rect;
    if (!automationRect.isValid()) {
        failures.append("automation hover fixture did not publish a valid canonical band");
        return;
    }
    automationInput = quickCanvas && quickCanvas->rootObject()
                          ? quickCanvas->rootObject()->findChild<songview::TimelineInputItem *>(
                                QStringLiteral("timelineAutomationInput"))
                          : nullptr;
    if (!automationInput) {
        failures.append("automation hover fixture did not expose the Quick automation input");
        return;
    }
    if (!automationInput->interaction() || !automationInput->window()) {
        failures.append("automation hover fixture did not bind the Quick automation input");
        return;
    }

    const QSize automationBandSize = automationRect.size();
    const int inputWidth = qFloor(automationInput->width());
    const int inputHeight = qFloor(automationInput->height());
    if (inputWidth <= 0 || inputHeight <= 0) {
        failures.append("automation hover fixture Quick input had no visible bounds");
        return;
    }

    page->setVerticalScroll(
        std::clamp(body.center().y() - inputHeight / 2, 0, page->automationContentHeight()));
    checks::support::pumpQuick();

    const int scroll = page->verticalScroll();
    const QRect liveCcBody = canvas->laneBody(fixtureHandle);
    const int plotLeft = (std::max)(liveCcBody.left(), canvas->plotOrigin() + 1);
    const int plotRight =
        (std::min)({liveCcBody.right(), automationBandSize.width() - 1, inputWidth - 1});
    if (liveCcBody.isEmpty() || plotLeft > plotRight) {
        failures.append("automation hover fixture CC body did not contain the visible plot");
        return;
    }

    const QRect inputBounds(QPoint{}, QSize(inputWidth, inputHeight));
    const int inputX = std::clamp(automationBandSize.width() * 2 / 3, plotLeft, plotRight);
    const QRect visibleCcRect = liveCcBody.translated(0, -scroll).intersected(inputBounds);
    const QRect pinnedTempoRect =
        canvas->pinnedTempoRect().translated(0, -scroll).intersected(inputBounds);
    const QRect ccInterior =
        liveCcBody.adjusted(0, layout::singlePixel() + 1, 0, -layout::singlePixel())
            .translated(0, -scroll);
    const QRect eligibleCcRect = visibleCcRect.intersected(ccInterior);
    QRect unobscuredCcColumn(inputX, eligibleCcRect.top(), 1, eligibleCcRect.height());
    if (!unobscuredCcColumn.isEmpty() && pinnedTempoRect.intersects(unobscuredCcColumn)) {
        QRect aboveTempo = unobscuredCcColumn;
        aboveTempo.setBottom(pinnedTempoRect.top() - 1);
        QRect belowTempo = unobscuredCcColumn;
        belowTempo.setTop(pinnedTempoRect.bottom() + 1);
        if (aboveTempo.isEmpty() ||
            (!belowTempo.isEmpty() && belowTempo.height() > aboveTempo.height()))
            unobscuredCcColumn = belowTempo;
        else
            unobscuredCcColumn = aboveTempo;
    }
    const auto rectSummary = [](const QRect &rect) {
        return QStringLiteral("(%1,%2 %3x%4)")
            .arg(rect.x())
            .arg(rect.y())
            .arg(rect.width())
            .arg(rect.height());
    };
    const auto geometrySummary = [&] {
        return QStringLiteral("scroll=%1, pinned-tempo-local=%2, visible-CC-local=%3, "
                              "eligible-CC-local=%4, probe-CC-local=%5")
            .arg(scroll)
            .arg(rectSummary(pinnedTempoRect))
            .arg(rectSummary(visibleCcRect))
            .arg(rectSummary(eligibleCcRect))
            .arg(rectSummary(unobscuredCcColumn));
    };
    if (visibleCcRect.isEmpty() || eligibleCcRect.isEmpty() || unobscuredCcColumn.isEmpty()) {
        failures.append(QStringLiteral("automation hover fixture had no unobscured CC plot (%1)")
                            .arg(geometrySummary()));
        return;
    }

    // Automation input positions are viewport-local; body assertions use the
    // live content-space CC body after restoring the vertical scroll offset.
    const QPoint position(inputX, unobscuredCcColumn.center().y());
    const QPoint contentPosition(position.x(), position.y() + scroll);
    const int safeBodyTop = liveCcBody.top() + layout::singlePixel() + 1;
    const int safeBodyBottom = liveCcBody.bottom() - layout::singlePixel();
    if (!inputBounds.contains(position) || !visibleCcRect.contains(position) ||
        !unobscuredCcColumn.contains(position) || !liveCcBody.contains(contentPosition) ||
        pinnedTempoRect.contains(position) || contentPosition.y() < safeBodyTop ||
        contentPosition.y() > safeBodyBottom) {
        failures.append(
            QStringLiteral("automation hover fixture CC probe was outside the unobscured live "
                           "body (%1)")
                .arg(geometrySummary()));
        return;
    }
    canvas->cancelInteraction();
    if (!canvas->pencilMode())
        canvas->setPencilMode(true);
    checks::support::pumpQuick();

    QString captureError;
    clearQuickHover();
    const QImage baseline = checks::support::captureQuickBand(view, automationRect, &captureError);
    if (baseline.isNull()) {
        failures.append(
            QStringLiteral("automation Quick framebuffer capture failed: %1").arg(captureError));
        return;
    }
    const QPointF inputPosition(position);
    const QPointF globalPosition = automationInput->mapToGlobal(inputPosition);
    const auto positionSummary = [&] {
        return QStringLiteral("lane=CC(track=%1, controller=%2, handle=%3), body=(%4,%5 %6x%7), "
                              "local=(%8,%9), %10")
            .arg(selectedTrack)
            .arg(static_cast<int>(CoreTimeDefaults::kCcModulation))
            .arg(fixtureHandle.index)
            .arg(liveCcBody.x())
            .arg(liveCcBody.y())
            .arg(liveCcBody.width())
            .arg(liveCcBody.height())
            .arg(inputPosition.x(), 0, 'f', 2)
            .arg(inputPosition.y(), 0, 'f', 2)
            .arg(geometrySummary());
    };
    const bool hoverHandled =
        automationInput->interaction()->pointerMove(songview::TimelinePointerInput{
            .position = inputPosition,
            .globalPosition = globalPosition,
            .button = Qt::NoButton,
            .buttons = Qt::NoButton,
            .modifiers = Qt::NoModifier,
        });
    if (!hoverHandled) {
        failures.append(
            QStringLiteral("automation hover interaction did not handle the local pointer move "
                           "(%1)")
                .arg(positionSummary()));
    }
    checks::support::pumpQuick();
    const QImage hovered = checks::support::captureQuickBand(view, automationRect, &captureError);
    if (hovered.isNull()) {
        failures.append(
            QStringLiteral("automation Quick framebuffer capture after hover failed: %1 (%2)")
                .arg(captureError)
                .arg(positionSummary()));
    } else if (hovered == baseline) {
        failures.append(QStringLiteral("automation hover did not render its local Quick decoration "
                                       "(%1)")
                            .arg(positionSummary()));
    }
    clearQuickHover();
    const QImage cleared = checks::support::captureQuickBand(view, automationRect, &captureError);
    if (cleared.isNull()) {
        failures.append(
            QStringLiteral("automation Quick framebuffer capture after hover leave failed: %1 "
                           "(%2)")
                .arg(captureError)
                .arg(positionSummary()));
    } else if (cleared != baseline) {
        failures.append(QStringLiteral("automation hover did not clear its local Quick decoration "
                                       "(%1)")
                            .arg(positionSummary()));
    }
}

void checkFollowScroll(SongView &view, const MidiTimeline &timeline, QStringList &failures)
{
    const SongView::ViewState saved = view.viewState();
    SongView::ViewState parked = saved;
    parked.scrollPx = 0.0;
    parked.pxPerBeat = 512.0;
    view.applyViewState(parked);
    const uint64_t farTick = uint64_t(double(view.width()) * 4.0 / view.camera().pxPerTick()) + 1;
    const uint64_t farSample = timeline.sampleForTick(farTick);
    view.setPlayheadSample(farSample, true);
    if (view.camera().scrollX() <= 0.0)
        failures.append("follow-on playback did not scroll to the playhead");
    view.applyViewState(parked);
    view.setFollowPlayhead(false);
    view.setPlayheadSample(farSample, true);
    if (view.camera().scrollX() != 0.0)
        failures.append("follow-off playback still scrolled the view");
    view.setFollowPlayhead(true);
    view.setPlayheadSample(farSample, true);
    if (view.camera().scrollX() <= 0.0)
        failures.append("re-enabled follow did not scroll to the playhead");
    view.applyViewState(saved);
}

class UpdateRequestCounter final : public QObject
{
  public:
    int count() const noexcept { return m_count; }
    void reset() noexcept { m_count = 0; }

  protected:
    bool eventFilter(QObject *, QEvent *event) override
    {
        if (event->type() == QEvent::UpdateRequest)
            ++m_count;
        return false;
    }

  private:
    int m_count = 0;
};

void drainQuickUpdateRequests(QQuickWindow &window, UpdateRequestCounter &counter)
{
    QCoreApplication::sendPostedEvents(&window, QEvent::UpdateRequest);
    QCoreApplication::processEvents(QEventLoop::AllEvents);
    QCoreApplication::sendPostedEvents(&window, QEvent::UpdateRequest);
    counter.reset();
}

bool verifyQuickUpdateRequestControl(QQuickWindow &window, UpdateRequestCounter &counter)
{
    drainQuickUpdateRequests(window, counter);
    window.update();

    QDeadlineTimer timeout{1000};
    while (counter.count() == 0 && !timeout.hasExpired()) {
        QCoreApplication::sendPostedEvents(&window, QEvent::UpdateRequest);
        QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
    }
    return counter.count() > 0;
}

void checkDevicePixelRectContract(QStringList &failures)
{
    const QRect logicalRect{3, 2, 5, 4};
    QImage dprOne{QSize{16, 10}, QImage::Format_ARGB32_Premultiplied};
    dprOne.setDevicePixelRatio(1.0);
    if (checks::support::devicePixelRect(dprOne, logicalRect) != logicalRect)
        failures.append("devicePixelRect did not preserve an exact DPR 1 rectangle");

    QImage dprTwo{QSize{32, 20}, QImage::Format_ARGB32_Premultiplied};
    dprTwo.setDevicePixelRatio(2.0);
    if (checks::support::devicePixelRect(dprTwo, logicalRect) != QRect{6, 4, 10, 8})
        failures.append("devicePixelRect did not map an exact DPR 2 rectangle");
    QImage dprOnePointFive{QSize{12, 14}, QImage::Format_ARGB32_Premultiplied};
    dprOnePointFive.setDevicePixelRatio(1.5);
    if (checks::support::devicePixelRect(dprOnePointFive, logicalRect) != QRect{4, 3, 8, 6})
        failures.append("devicePixelRect did not map an exact fractional DPR rectangle");
    if (checks::support::devicePixelRect(dprOnePointFive, QRect{1, 1, 2, 2}) != QRect{1, 1, 4, 4})
        failures.append("devicePixelRect did not round a fractional DPR rectangle outward");
}

void checkPositionOnlyQuickFrames(const MidiTimeline &timeline, QStringList &failures)
{
    SongView probe;
    const int unit = layout::space(layout::Space::One);
    probe.resize(90 * unit, 65 * unit);
    probe.setSong(&timeline, nullptr);
    probe.setFollowPlayhead(false);
    probe.show();
    for (int settle = 0; settle < 4; ++settle)
        checks::support::pumpQuick();

    auto *quick =
        probe.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    auto *scene = quick ? quick->findChild<songview::TimelineQuickScene *>() : nullptr;
    auto *overlay = probe.findChild<songview::PlayheadOverlay *>();
    QQuickWindow *const quickWindow = quick ? quick->quickWindow() : nullptr;
    const songview::TimelineBandLayout &bandLayout = probe.timelineBandLayout();
    if (!quick || !scene || !bandLayout.geometry(songview::TimelineBand::Ruler) || !overlay ||
        !quickWindow) {
        failures.append("isolated SongView did not expose its Quick and native render surfaces");
        probe.hide();
        return;
    }

    const uint64_t tick =
        uint64_t(std::max(0.0, probe.camera().tickAtContentX(std::max<qreal>(
                                   1.0, probe.width() / 2.0 - probe.timelinePlotOrigin()))));
    probe.setPlayheadSample(timeline.sampleForTick(tick), false);
    for (int settle = 0; settle < 4; ++settle)
        checks::support::pumpQuick();

    QString captureError;
    const QRect pausedRulerRect = probe.timelineBandLayout()
                                      .geometry(songview::TimelineBand::Ruler)
                                      .value_or(songview::TimelineBandGeometry{})
                                      .rect;
    const QImage quickPaused =
        checks::support::captureQuickBand(probe, pausedRulerRect, &captureError);
    probe.setPlayheadSample(timeline.sampleForTick(tick), true);
    const QRect playingRulerRect = probe.timelineBandLayout()
                                       .geometry(songview::TimelineBand::Ruler)
                                       .value_or(songview::TimelineBandGeometry{})
                                       .rect;
    const QImage quickPlaying =
        checks::support::captureQuickBand(probe, playingRulerRect, &captureError);
    if (quickPaused.isNull() || quickPlaying.isNull()) {
        failures.append(
            QStringLiteral("isolated playhead-free Quick capture failed: %1").arg(captureError));
    } else {
        const QColor playheadColor = themes::color(themes::Role::song_view_playhead);
        if (checks::support::hasPlayheadPixel(quickPaused, quickPaused.rect(), playheadColor) ||
            checks::support::hasPlayheadPixel(quickPlaying, quickPlaying.rect(), playheadColor)) {
            failures.append("isolated Quick framebuffer retained playhead-role pixels");
        }
    }

    UpdateRequestCounter updateRequests;
    quickWindow->installEventFilter(&updateRequests);
    if (!verifyQuickUpdateRequestControl(*quickWindow, updateRequests))
        failures.append("isolated Quick UpdateRequest control did not fire");
    drainQuickUpdateRequests(*quickWindow, updateRequests);

    const auto beforeMoves = checks::support::timelineQuickLayerRevisions(*scene);
    for (uint64_t move = 1; move <= 128; ++move)
        probe.setPlayheadSample(timeline.sampleForTick(tick + move), true);
    QCoreApplication::sendPostedEvents(quickWindow, QEvent::UpdateRequest);
    QCoreApplication::processEvents(QEventLoop::AllEvents);
    QCoreApplication::sendPostedEvents(quickWindow, QEvent::UpdateRequest);
    if (updateRequests.count() != 0) {
        failures.append(
            QStringLiteral("128 position-only SongView moves requested %1 Quick update(s)")
                .arg(updateRequests.count()));
    }
    if (checks::support::timelineQuickLayerRevisions(*scene) != beforeMoves)
        failures.append("128 isolated position-only moves rebuilt TimelineQuickLayer data");

    quickWindow->removeEventFilter(&updateRequests);
    probe.hide();
    checks::support::pumpQuick();
}

} // namespace

QStringList timelineChromeCheckFailures(SongView &view, const MidiTimeline &timeline)
{
    QStringList failures;
    checkDevicePixelRectContract(failures);
    const bool viewWasVisible = view.isVisible();
    const bool hadDontShowOnScreen = view.testAttribute(Qt::WA_DontShowOnScreen);
    view.setAttribute(Qt::WA_DontShowOnScreen, false);
    if (!viewWasVisible)
        view.show();
    checks::support::pumpQuick();

    auto *quick =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    auto *root = quick ? qobject_cast<QQuickItem *>(quick->rootObject()) : nullptr;
    auto *scene = quick ? quick->findChild<songview::TimelineQuickScene *>() : nullptr;
    auto *roll = view.findChild<songview::PianoRoll *>();
    auto *rollInput =
        root ? root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineRollInput"))
             : nullptr;
    const auto rollBandCenterY = [&view] {
        const std::optional<songview::TimelineBandGeometry> &band =
            view.timelineBandLayout().geometry(songview::TimelineBand::Roll);
        return band ? band->rect.center().y() : 0;
    };
    auto *drawer = view.editorDrawer();
    auto *automationPage = drawer ? drawer->automationPage() : nullptr;
    auto *velocity = drawer ? drawer->velocityArea() : nullptr;
    auto *voiceChanges = drawer ? drawer->voiceChangeArea() : nullptr;
    auto *overlay = view.findChild<songview::PlayheadOverlay *>();
    if (!quick || !root || !scene ||
        !view.timelineBandLayout().geometry(songview::TimelineBand::Ruler) || !roll || !overlay ||
        !automationPage || !velocity || !voiceChanges) {
        failures.append("SongView did not expose its Quick chrome and native playhead bands");
    } else {
        if (!overlay->fallbackWidget() && quick->playheadVisible())
            failures.append(
                "default chrome published a Quick playhead without a native fallback widget");
        const auto copies = chromeCopies(*root);
        if (root->findChildren<songview::TimelineChromeItem *>().size() != 14)
            failures.append("Quick timeline did not retain 14 hover/edit guides");
        for (const ChromeCopies &copy : copies) {
            if (!copy.hover || !copy.edit) {
                failures.append(QStringLiteral("Quick timeline is missing %1 hover/edit chrome")
                                    .arg(copy.name));
                continue;
            }
            if (copy.hover->z() != 9.0 || copy.edit->z() != 10.0) {
                failures.append(
                    QStringLiteral("%1 chrome does not stack hover below edit").arg(copy.name));
            }
        }

        const uint64_t tick =
            uint64_t(std::max(0.0, view.camera().tickAtContentX(std::max<qreal>(
                                       1.0, view.width() / 2.0 - view.timelinePlotOrigin()))));
        const uint64_t sample = timeline.sampleForTick(tick);
        view.setEditCursorTick(tick);
        view.setPlayheadSample(sample, false);
        checks::support::pumpQuick();

        const songview::TimelineBandLayout &bandLayout = view.timelineBandLayout();
        const auto canonicalHostRect = [&bandLayout, drawer] {
            const QRect rect =
                checks::support::canonicalVisibleQuickHostRect(bandLayout, &drawer->chrome());
            return rect.isEmpty() ? std::optional<QRect>{} : std::optional<QRect>{rect};
        };

        const auto expectedSongViewX = [&view, &bandLayout](double chromeTick) {
            const std::optional<songview::TimelineBandGeometry> &rulerGeometry =
                bandLayout.geometry(songview::TimelineBand::Ruler);
            return (rulerGeometry ? rulerGeometry->rect.x() + rulerGeometry->timelineOrigin
                                  : qRound(view.timelinePlotOrigin())) +
                   view.camera().contentX(chromeTick);
        };
        const auto quickContentX = [quick, &view](qreal songViewX) {
            return songViewX - quick->mapTo(&view, QPoint{}).x();
        };
        const auto chromeSongViewX = [quick, &view, root](const QQuickItem &chrome) {
            return quick->mapTo(&view, QPoint{}).x() + checks::support::quickRootX(chrome, *root);
        };
        const auto chromeVisibilityMatches = [&copies](bool hoverVisible, bool editVisible) {
            for (const ChromeCopies &copy : copies) {
                if (!copy.hover || !copy.edit)
                    continue;
                const bool bandVisible = copy.hover->parentItem()->isVisible();
                if (copy.hover->isVisible() != (hoverVisible && bandVisible) ||
                    copy.edit->isVisible() != (editVisible && bandVisible)) {
                    return false;
                }
            }
            return true;
        };
        const qreal songStartSongViewX = expectedSongViewX(0.0);
        const qreal preSongSongViewX = songStartSongViewX - layout::singlePixel();
        view.clearTimelineQuickHover(songview::TimelineQuickHoverOwner::Automation);
        quick->synchronizeGuides(view.timelinePlotOrigin(), preSongSongViewX);
        quick->publishHover(songview::TimelineQuickHoverOwner::Automation, 0, preSongSongViewX);
        checks::support::pumpQuick();
        if (quick->hoverVisible() || quick->editVisible() ||
            !chromeVisibilityMatches(false, false)) {
            failures.append("Quick guides remained visible before song tick 0");
        }
        view.clearTimelineQuickHover(songview::TimelineQuickHoverOwner::Automation);
        quick->synchronizeGuides(view.timelinePlotOrigin(), songStartSongViewX);
        checks::support::pumpQuick();
        if (!quick->editVisible() ||
            std::abs(quick->editRootContentX() - quickContentX(songStartSongViewX)) > 0.2 ||
            !chromeVisibilityMatches(false, true)) {
            failures.append("Quick edit guide did not render at song tick 0");
        }
        quick->publishHover(songview::TimelineQuickHoverOwner::Automation, 0, songStartSongViewX);
        checks::support::pumpQuick();
        if (!quick->hoverVisible() ||
            std::abs(quick->hoverRootContentX() - quickContentX(songStartSongViewX)) > 0.2 ||
            !chromeVisibilityMatches(true, false)) {
            failures.append("Quick hover guide did not render at song tick 0");
        }
        quick->synchronizeGuides(view.timelinePlotOrigin(),
                                 expectedSongViewX(view.editCursorTick()));
        quick->publishHover(songview::TimelineQuickHoverOwner::Automation, tick,
                            expectedSongViewX(tick));
        checks::support::pumpQuick();
        const qreal expectedHover = expectedSongViewX(tick);
        const qreal expectedEdit = expectedSongViewX(view.editCursorTick());
        if (std::abs(quick->hoverRootContentX() - quickContentX(expectedHover)) > 0.2 ||
            std::abs(quick->editRootContentX() - quickContentX(expectedEdit)) > 0.2) {
            failures.append(
                "Quick guide root coordinates do not account for the native host origin");
        }
        for (const ChromeCopies &copy : copies) {
            if (!copy.hover || !copy.edit)
                continue;
            const bool bandVisible = copy.hover->parentItem()->isVisible();
            if (copy.hover->isVisible() != bandVisible || copy.edit->isVisible()) {
                failures.append(
                    QStringLiteral("%1 exposed simultaneous or stale guides").arg(copy.name));
            }
        }
        for (const ChromeCopies &copy : copies) {
            if (!copy.hover || !copy.edit)
                continue;
            if (std::abs(checks::support::quickRootX(*copy.hover, *root) -
                         quickContentX(expectedHover)) > 0.2 ||
                std::abs(checks::support::quickRootX(*copy.edit, *root) -
                         quickContentX(expectedEdit)) > 0.2 ||
                std::abs(chromeSongViewX(*copy.hover) - expectedHover) > 0.2 ||
                std::abs(chromeSongViewX(*copy.edit) - expectedEdit) > 0.2) {
                failures.append(
                    QStringLiteral("%1 hover/edit chrome did not align across Quick bands")
                        .arg(copy.name));
            }
        }
        const QRect hostBeforeResize = quick->geometry();
        const QRect canonicalHostBeforeResize = canonicalHostRect().value_or(QRect{});
        const QSize viewSizeBeforeResize = view.size();
        view.clearTimelineQuickHover(songview::TimelineQuickHoverOwner::Automation);
        checks::support::pumpQuick();
        if (quick->hoverVisible() || !quick->editVisible() ||
            !chromeVisibilityMatches(false, true)) {
            failures.append(
                "clearing the synthetic Automation hover did not restore the edit guide");
        }
        view.resize(view.width(), view.height() - 4 * layout::space(layout::Space::One));
        checks::support::pumpQuick();
        const std::optional<QRect> resizedHost = canonicalHostRect();
        if (!resizedHost || *resizedHost == canonicalHostBeforeResize) {
            failures.append("canonical fixture resize did not change the canonical host envelope");
        } else if (quick->geometry() != *resizedHost) {
            failures.append("Quick host did not move with the canonical envelope after resize");
        }
        const std::optional<songview::TimelineBandGeometry> &resizedRoll =
            bandLayout.geometry(songview::TimelineBand::Roll);
        if (!resizedRoll || !rollInput ||
            QRectF(rollInput->mapToItem(root, QPointF()), rollInput->size()) !=
                QRectF(resizedRoll->rect.translated(-quick->geometry().topLeft()))) {
            failures.append("canonical roll rectangle went stale after the canonical resize");
        }
        const qreal expectedEditRootX = quickContentX(expectedEdit);
        if (std::abs(quick->editRootContentX() - expectedEditRootX) > 0.2) {
            failures.append("Quick edit guide did not retranslate after a canonical resize");
        }
        for (const ChromeCopies &copy : copies) {
            if (!copy.edit)
                continue;
            if (std::abs(checks::support::quickRootX(*copy.edit, *root) - expectedEditRootX) >
                    0.2 ||
                std::abs(chromeSongViewX(*copy.edit) - expectedEdit) > 0.2) {
                failures.append(
                    QStringLiteral("%1 edit guide did not retranslate after a canonical resize")
                        .arg(copy.name));
            }
        }
        if (quick->hoverVisible() || !quick->editVisible() ||
            !chromeVisibilityMatches(false, true)) {
            failures.append("canonical resize did not retain the edit guide after clearing the "
                            "synthetic Automation hover");
        }
        view.resize(viewSizeBeforeResize);
        checks::support::pumpQuick();
        if (quick->geometry() != canonicalHostRect().value_or(QRect{}) ||
            quick->geometry() != hostBeforeResize) {
            failures.append("Quick host did not restore the canonical envelope after resize");
        }
        const SongView::ViewState cameraState = view.viewState();
        const qreal oldEditX = quick->editRootContentX();
        view.setEditorHorizontalScroll(cameraState.scrollPx + view.camera().pxPerBeat());
        if (view.camera().scrollX() == cameraState.scrollPx)
            view.setEditorHorizontalScroll(cameraState.scrollPx - view.camera().pxPerBeat());
        checks::support::pumpQuick();
        const qreal cameraEditX = expectedSongViewX(view.editCursorTick());
        if (view.camera().scrollX() == cameraState.scrollPx) {
            failures.append("camera-motion fixture could not move within the timeline range");
        } else {
            if (std::abs(quick->editRootContentX() - quickContentX(cameraEditX)) > 0.2 ||
                quick->editRootContentX() == oldEditX) {
                failures.append("camera motion did not update retained Quick guides");
            }
            for (const ChromeCopies &copy : copies) {
                if (!copy.edit)
                    continue;
                if (std::abs(checks::support::quickRootX(*copy.edit, *root) -
                             quickContentX(cameraEditX)) > 0.2 ||
                    std::abs(chromeSongViewX(*copy.edit) - cameraEditX) > 0.2) {
                    failures.append(
                        QStringLiteral("camera motion misaligned %1 edit chrome").arg(copy.name));
                }
            }
        }
        view.applyViewState(cameraState);
        checks::support::pumpQuick();

        view.publishTimelineQuickHover(songview::TimelineQuickHoverOwner::VoiceChanges, tick + 1);
        view.clearTimelineQuickHover(songview::TimelineQuickHoverOwner::Automation);
        checks::support::pumpQuick();
        if (!quick->hoverVisible() || std::abs(quick->hoverRootContentX() -
                                               quickContentX(expectedSongViewX(tick + 1))) > 0.2) {
            failures.append("a stale hover clear hid the newer owner chrome");
        }
        view.clearTimelineQuickHover(songview::TimelineQuickHoverOwner::VoiceChanges);
        checks::support::pumpQuick();
        if (quick->hoverVisible())
            failures.append("the owning hover clear did not hide Quick chrome");
        for (const ChromeCopies &copy : copies) {
            if (!copy.hover || !copy.edit)
                continue;
            const bool bandVisible = copy.edit->parentItem()->isVisible();
            if (copy.hover->isVisible() || copy.edit->isVisible() != bandVisible) {
                failures.append(
                    QStringLiteral("%1 did not restore the edit guide after hover leave")
                        .arg(copy.name));
            }
        }

        const bool eventListWasVisible = view.eventListVisible();
        const auto canonicalRollMatchesRoll = [&] {
            const std::optional<songview::TimelineBandGeometry> &geometry =
                bandLayout.geometry(songview::TimelineBand::Roll);
            return geometry && rollInput && rollInput->isVisible() &&
                   QRectF(rollInput->mapToItem(root, QPointF()), rollInput->size()) ==
                       QRectF(geometry->rect.translated(-quick->geometry().topLeft()));
        };
        if (!canonicalRollMatchesRoll())
            failures.append("roll view canonical entry diverged from the piano-roll input item");
        const QColor playheadColor = themes::color(themes::Role::song_view_playhead);
        const std::optional<songview::TimelineBandGeometry> &rulerBand =
            bandLayout.geometry(songview::TimelineBand::Ruler);
        const qreal nativeX = (rulerBand ? rulerBand->rect.x() + rulerBand->timelineOrigin
                                         : qRound(view.timelinePlotOrigin())) +
                              view.camera().contentX(timeline.tickForSample(sample));
        qreal renderedNativeX = nativeX;
        const QRect rollRect = bandLayout.geometry(songview::TimelineBand::Roll)
                                   .value_or(songview::TimelineBandGeometry{})
                                   .rect;
        const QRect rulerRect = rulerBand.value_or(songview::TimelineBandGeometry{}).rect;
        const bool captureExpected = expectsCapturablePlayhead();
        QImage paused;
        QImage playing;
        if (captureExpected) {
            paused = grabPlayhead(view, *overlay, failures).toImage();
            view.setPlayheadSample(sample, true);
            checks::support::pumpQuick();
            playing = grabPlayhead(view, *overlay, failures).toImage();
            if (paused.isNull() || playing.isNull()) {
                failures.append("native playhead capture was empty");
            } else {
                const qreal detectedNativeX =
                    playheadCenterAt(paused, rollRect.center().y(), playheadColor);
                if (detectedNativeX < 0.0) {
                    failures.append("paused native playhead was not clipped into the piano roll");
                } else {
                    renderedNativeX = detectedNativeX;
                    if (std::abs(renderedNativeX - nativeX) > layout::singlePixel() + 0.75)
                        failures.append("native playhead did not align with the timeline position");
                }
                if (!checks::support::hasPlayheadPixel(
                        paused,
                        QRect(qRound(renderedNativeX) - songview::playheadGlowRadius(),
                              rulerRect.top(), 2 * songview::playheadGlowRadius() + 1,
                              std::max(1, rulerRect.height() - layout::singlePixel())),
                        playheadColor)) {
                    failures.append("native playhead body was not clipped into the ruler");
                }
                if (paused == playing)
                    failures.append("paused and playing native playheads rendered identically");

                const int triangleTop =
                    rulerRect.bottom() - songview::playheadTriangleHeight() + layout::singlePixel();
                const int topWidth = checks::support::playheadWidthAt(
                    paused, triangleTop + layout::singlePixel(), renderedNativeX, playheadColor);
                const int bottomWidth = checks::support::playheadWidthAt(
                    paused,
                    triangleTop + songview::playheadTriangleHeight() - layout::singlePixel(),
                    renderedNativeX, playheadColor);
                if (topWidth <= bottomWidth || triangleTop < rulerRect.top() ||
                    triangleTop + songview::playheadTriangleHeight() > rulerRect.bottom() + 1)
                    failures.append(
                        "native ruler triangle was not down and wholly inside the ruler");
            }

            overlay->setPlayhead(0.0, false, false);
            checks::support::pumpQuick();
            const QImage hidden = grabPlayhead(view, *overlay, failures).toImage();
            if (checks::support::hasPlayheadPixel(hidden, hidden.rect(), playheadColor))
                failures.append("native playhead remained painted after a hidden presentation");
            view.setPlayheadSample(sample, false);
            checks::support::pumpQuick();
        }
        const auto currentNativeX = [&] {
            const std::optional<songview::TimelineBandGeometry> &rulerGeometry =
                bandLayout.geometry(songview::TimelineBand::Ruler);
            return (rulerGeometry ? rulerGeometry->rect.x() + rulerGeometry->timelineOrigin
                                  : qRound(view.timelinePlotOrigin())) +
                   view.camera().contentX(timeline.tickForSample(sample));
        };

        const EditorViewState savedEditorState = view.editorViewState();
        view.setEventListVisible(true);
        checks::support::pumpQuick();
        if (bandLayout.geometry(songview::TimelineBand::Roll))
            failures.append("event-list view retained a canonical roll rectangle");
        const qreal eventListNativeX = currentNativeX();
        if (captureExpected) {
            const QImage eventListImage = grabPlayhead(view, *overlay, failures).toImage();
            if (checks::support::hasPlayheadPixel(
                    eventListImage,
                    QRect(qRound(eventListNativeX) - songview::playheadGlowRadius(),
                          rollRect.center().y(), 2 * songview::playheadGlowRadius() + 1,
                          layout::singlePixel()),
                    playheadColor)) {
                failures.append("hidden piano-roll playhead remained visible over the event list");
            }
            const int triangleTop =
                rulerRect.bottom() - songview::playheadTriangleHeight() + layout::singlePixel();
            const int topWidth = checks::support::playheadWidthAt(
                eventListImage, triangleTop + layout::singlePixel(), eventListNativeX,
                playheadColor);
            const int bottomWidth = checks::support::playheadWidthAt(
                eventListImage,
                triangleTop + songview::playheadTriangleHeight() - layout::singlePixel(),
                eventListNativeX, playheadColor);
            if (bottomWidth <= topWidth)
                failures.append("native ruler triangle did not flip up for the event list");
        }
        view.setEventListVisible(false);
        checks::support::pumpQuick();
        if (!canonicalRollMatchesRoll())
            failures.append("restored roll view did not republish its canonical rectangle");

        // Quick-rendered bands use canonical SongView-local rectangles for
        // their native-playhead clip checks.
        const auto checkVisibleBandRect = [&](const QRect &bandRect, const char *name) {
            if (!captureExpected)
                return;
            const QImage image = grabPlayhead(view, *overlay, failures).toImage();
            const qreal bandNativeX = currentNativeX();
            if (!bandRect.isValid() ||
                !checks::support::hasPlayheadPixel(
                    image,
                    QRect(qRound(bandNativeX) - layout::singlePixel(), bandRect.center().y(),
                          2 * layout::singlePixel() + 1, layout::singlePixel()),
                    playheadColor)) {
                failures.append(
                    QStringLiteral("native playhead was not clipped into the visible %1 band")
                        .arg(QString::fromLatin1(name)));
            }
        };

        view.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
        view.setDrawerActivePage(EditorDrawerPage::Velocity);
        checks::support::pumpQuick();
        checkVisibleBandRect(bandLayout.geometry(songview::TimelineBand::Velocity)
                                 .value_or(songview::TimelineBandGeometry{})
                                 .rect,
                             "velocity");
        view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
        view.setDrawerActivePage(EditorDrawerPage::VoiceChanges);
        checks::support::pumpQuick();
        checkVisibleBandRect(bandLayout.geometry(songview::TimelineBand::VoiceChanges)
                                 .value_or(songview::TimelineBandGeometry{})
                                 .rect,
                             "voice-change");
        view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
        view.setDrawerActivePage(EditorDrawerPage::Automations);
        checks::support::pumpQuick();
        checkVisibleBandRect(bandLayout.geometry(songview::TimelineBand::Automation)
                                 .value_or(songview::TimelineBandGeometry{})
                                 .rect,
                             "automation");
        checkVisibleBandRect(bandLayout.geometry(songview::TimelineBand::OtherEvents)
                                 .value_or(songview::TimelineBandGeometry{})
                                 .rect,
                             "other-events");
        // Equal-layout lifecycle events (Show, WinIdChange, density, screen)
        // republish the stored layout without touching the canonical value:
        // the Quick host frame, window mask, QML band geometry, and playhead
        // clipping must survive a hide/show cycle.
        const songview::TimelineBandLayout canonicalBeforeLifecycle = bandLayout;
        QEvent winIdChange(QEvent::WinIdChange);
        QCoreApplication::sendEvent(&view, &winIdChange);
        // QEvent::DevicePixelRatioChange exists only since Qt 6.6; earlier
        // Qt 6 carries the density change on the screen-change notification.
#if QT_VERSION >= QT_VERSION_CHECK(6, 6, 0)
        QEvent densityChange(QEvent::DevicePixelRatioChange);
#else
        QEvent densityChange(QEvent::ScreenChangeInternal);
#endif
        QCoreApplication::sendEvent(&view, &densityChange);
        view.hide();
        checks::support::pumpQuick();
        view.show();
        checks::support::pumpQuick();
        const QRect lifecycleHost = quick->geometry();
        const QRect lifecycleRoll = bandLayout.geometry(songview::TimelineBand::Roll)
                                        .value_or(songview::TimelineBandGeometry{})
                                        .rect;
        const QRectF lifecycleRollLocal(lifecycleRoll.translated(-lifecycleHost.topLeft()));
        if (bandLayout != canonicalBeforeLifecycle ||
            lifecycleHost != canonicalHostRect().value_or(QRect{}))
            failures.append(
                "a lifecycle event moved the canonical layout or dropped the Quick host frame");
        const DrawerChrome &lifecycleChrome = drawer->chrome();
        if (!root->property("rollBandVisible").toBool() ||
            root->property("rollBandRect").toRectF() != lifecycleRollLocal ||
            !checks::support::quickWindowIsUnmasked(*quick) ||
            lifecycleHost !=
                checks::support::canonicalVisibleQuickHostRect(bandLayout, &lifecycleChrome)) {
            failures.append("lifecycle republish dropped QML roll geometry or the unmasked Quick "
                            "host envelope");
        }
        checkVisibleBandRect(lifecycleRoll, "piano roll after lifecycle republish");
        checkVisibleBandRect(bandLayout.geometry(songview::TimelineBand::Velocity)
                                 .value_or(songview::TimelineBandGeometry{})
                                 .rect,
                             "velocity lane after lifecycle republish");
        // Hover must be checked while the automation page is the explicitly
        // shown, active surface — before the saved editor state restores the
        // fixture defaults and hides the sibling sections again.
        checkAutomationHover(view, failures);
        view.applyEditorViewState(savedEditorState);
        view.setEventListVisible(eventListWasVisible);
        checks::support::pumpQuick();

        // Keep this a position-only probe; follow-scroll camera motion legitimately rebuilds
        // the retained timeline layers.
        view.setFollowPlayhead(false);
        view.setPlayheadSample(timeline.sampleForTick(tick), true);
        checks::support::pumpQuick();
        const auto beforeMoves = checks::support::timelineQuickLayerRevisions(*scene);
        for (uint64_t move = 1; move <= 128; ++move)
            view.setPlayheadSample(timeline.sampleForTick(tick + move), true);
        checks::support::pumpQuick();
        if (checks::support::timelineQuickLayerRevisions(*scene) != beforeMoves)
            failures.append("128 position-only SongView moves rebuilt TimelineQuickLayer data");
        view.setFollowPlayhead(true);

#ifdef __APPLE__
        checkMacPlayheadLifecycle(view, *overlay, failures);
#endif
    }

    failures += quickFallbackPlayheadCheckFailures(timeline);
    failures += quickScenePlayheadCheckFailures(timeline);
    checkPositionOnlyQuickFrames(timeline, failures);

    checkFollowScroll(view, timeline, failures);
    view.clearTimelineQuickHover(songview::TimelineQuickHoverOwner::Automation);
    view.setPlayheadSample(0, false);
    checks::support::pumpQuick();
    if (!viewWasVisible)
        view.hide();
    view.setAttribute(Qt::WA_DontShowOnScreen, hadDontShowOnScreen);
    return failures;
}
