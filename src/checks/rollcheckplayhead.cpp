#include "rollcheckplayhead.h"

#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"

#include <QApplication>
#include <QColor>
#include <QCoreApplication>
#include <QDeadlineTimer>
#include <QEvent>
#include <QEventLoop>
#include <QFontInfo>
#include <QImage>
#include <QObject>
#include <QPixmap>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRectF>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>

#include "core/miditimeline.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/layout.h"
#include "ui/playheadoverlay.h"
#include "ui/songview.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/timelinequickchrome.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timelinebandlayout.h"
#include "ui/songview/timeruler.h"
#include "ui/theme/themeruntime.h"

namespace {

struct ChromeCopies {
    const char *name;
    songview::TimelineChromeItem *hover = nullptr;
    songview::TimelineChromeItem *edit = nullptr;
};

std::array<ChromeCopies, 6> chromeCopies(QQuickItem &root)
{
    std::array<ChromeCopies, 6> copies{{
        {"Ruler"},
        {"Roll"},
        {"Automation"},
        {"Velocity"},
        {"VoiceChanges"},
        {"OtherEvents"},
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
    return overlay.grab();
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
    auto *viewport = page ? page->scrollViewport() : nullptr;
    if (!canvas || !viewport)
        return;
    if (!viewport->isVisibleTo(&view)) {
        failures.append("automation hover fixture did not keep the automation page visible");
        return;
    }
    QString captureError;
    QEvent leave(QEvent::Leave);
    QCoreApplication::sendEvent(canvas, &leave);
    checks::support::pumpQuick();
    const QImage baseline = checks::support::captureQuickBand(view, *viewport, &captureError);
    if (baseline.isNull()) {
        failures.append(
            QStringLiteral("automation Quick framebuffer capture failed: %1").arg(captureError));
        return;
    }
    const QPoint position(std::max(canvas->plotOrigin() + 1, canvas->width() * 2 / 3),
                          canvas->mapFrom(viewport, viewport->rect().center()).y());
    checks::events::sendMouse(*canvas, QEvent::MouseMove, position, Qt::NoButton, Qt::NoButton,
                              Qt::NoModifier);
    checks::support::pumpQuick();
    const QImage hovered = checks::support::captureQuickBand(view, *viewport, &captureError);
    if (hovered == baseline)
        failures.append("automation hover did not retain its local Quick decoration");
    QCoreApplication::sendEvent(canvas, &leave);
    checks::support::pumpQuick();
    if (checks::support::captureQuickBand(view, *viewport, &captureError) != baseline)
        failures.append("automation hover did not clear its local Quick decoration");
}

void checkFollowScroll(SongView &view, const MidiTimeline &timeline, QStringList &failures)
{
    const SongView::ViewState saved = view.viewState();
    SongView::ViewState parked = saved;
    parked.scrollPx = 0.0;
    parked.pxPerBeat = 512.0;
    view.applyViewState(parked);
    const uint64_t farTick = uint64_t(double(view.width()) * 4.0 / view.pxPerTick()) + 1;
    const uint64_t farSample = timeline.sampleForTick(farTick);
    view.setPlayheadSample(farSample, true);
    if (view.viewState().scrollPx <= 0.0)
        failures.append("follow-on playback did not scroll to the playhead");
    view.applyViewState(parked);
    view.setFollowPlayhead(false);
    view.setPlayheadSample(farSample, true);
    if (view.viewState().scrollPx != 0.0)
        failures.append("follow-off playback still scrolled the view");
    view.setFollowPlayhead(true);
    view.setPlayheadSample(farSample, true);
    if (view.viewState().scrollPx <= 0.0)
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
    auto *ruler = checks::support::findWidgetDescendant<songview::TimeRuler>(probe);
    auto *overlay = checks::support::findWidgetDescendant<songview::PlayheadOverlay>(probe);
    QQuickWindow *const quickWindow = quick ? quick->quickWindow() : nullptr;
    if (!quick || !scene || !ruler || !overlay || !quickWindow) {
        failures.append("isolated SongView did not expose its Quick and native render surfaces");
        probe.hide();
        return;
    }

    const uint64_t tick =
        uint64_t(std::max(0.0, probe.tickAtContentX(std::max<qreal>(
                                   1.0, probe.width() / 2.0 - probe.timelinePlotOrigin()))));
    probe.setPlayheadSample(timeline.sampleForTick(tick), false);
    for (int settle = 0; settle < 4; ++settle)
        checks::support::pumpQuick();

    QString captureError;
    const QImage quickPaused = checks::support::captureQuickBand(probe, *ruler, &captureError);
    probe.setPlayheadSample(timeline.sampleForTick(tick), true);
    const QImage quickPlaying = checks::support::captureQuickBand(probe, *ruler, &captureError);
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
    auto *ruler = checks::support::findWidgetDescendant<songview::TimeRuler>(view);
    auto *roll = checks::support::findWidgetDescendant<songview::PianoRoll>(view);
    auto *overlay = checks::support::findWidgetDescendant<songview::PlayheadOverlay>(view);
    auto *drawer = view.editorDrawer();
    auto *automationPage = drawer ? drawer->automationPage() : nullptr;
    auto *automationViewport = automationPage ? automationPage->scrollViewport() : nullptr;
    auto *velocity = drawer ? drawer->velocityArea() : nullptr;
    auto *voiceChanges = drawer ? drawer->voiceChangeArea() : nullptr;
    if (!quick || !root || !scene || !ruler || !roll || !overlay || !automationViewport ||
        !velocity || !voiceChanges) {
        failures.append("SongView did not expose its Quick chrome and native playhead bands");
    } else {
        if (overlay->parentWidget() != &view || overlay->geometry() != view.rect())
            failures.append("SongView playhead overlay is not one full-size direct child");

        const auto copies = chromeCopies(*root);
        if (root->findChildren<songview::TimelineChromeItem *>().size() != 12)
            failures.append("Quick timeline did not retain 12 hover/edit guides");
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
            uint64_t(std::max(0.0, view.tickAtContentX(std::max<qreal>(
                                       1.0, view.width() / 2.0 - view.timelinePlotOrigin()))));
        const uint64_t sample = timeline.sampleForTick(tick);
        view.setEditCursorTick(tick);
        view.setPlayheadSample(sample, false);
        view.publishTimelineQuickHover(songview::TimelineQuickHoverOwner::Automation, tick);
        checks::support::pumpQuick();

        const songview::TimelineBandLayout &bandLayout = view.timelineBandLayout();
        const QRect canonicalRulerRectBeforeFont =
            bandLayout.geometry(songview::TimelineBand::Ruler)
                .value_or(songview::TimelineBandGeometry{})
                .rect;
        const auto canonicalBandUnion = [&bandLayout] {
            std::optional<QRect> unionRect;
            for (const std::optional<songview::TimelineBandGeometry> &band : bandLayout.bands) {
                if (!band)
                    continue;
                unionRect = unionRect ? unionRect->united(band->rect) : band->rect;
            }
            return unionRect;
        };
        const QFont originalApplicationFont = QApplication::font();
        const QFont originalViewFont = view.font();
        QFont scaledFont = originalViewFont;
        const int currentFontPx = QFontInfo(originalViewFont).pixelSize();
        scaledFont.setPixelSize(std::max(layout::fontPx(2.0), currentFontPx + layout::fontPx(1.0)));
        songview::PlayheadOverlay *const originalOverlay = overlay;
        const QPointer<QWidget> overlayLifetime{overlay};
        QApplication::setFont(scaledFont);
        view.setFont(scaledFont);
        QEvent fontChange(QEvent::FontChange);
        QCoreApplication::sendEvent(&view, &fontChange);
        checks::support::pumpQuick();
        auto *const refreshedOverlay =
            checks::support::findWidgetDescendant<songview::PlayheadOverlay>(view);
        if (!refreshedOverlay) {
            failures.append("SongView font refresh removed its native playhead overlay");
            view.clearTimelineQuickHover(songview::TimelineQuickHoverOwner::Automation);
            view.setPlayheadSample(0, false);
            if (!viewWasVisible)
                view.hide();
            view.setAttribute(Qt::WA_DontShowOnScreen, hadDontShowOnScreen);
            return failures;
        }
        if (!overlayLifetime || refreshedOverlay != originalOverlay)
            failures.append("SongView font refresh reconstructed its native playhead overlay");
        overlay = refreshedOverlay;
        const std::optional<songview::TimelineBandGeometry> &refreshedRuler =
            bandLayout.geometry(songview::TimelineBand::Ruler);
        if (!refreshedRuler) {
            failures.append("font refresh dropped the canonical ruler entry");
        } else {
            if (quick->geometry() != canonicalBandUnion().value_or(QRect{}))
                failures.append("font refresh diverged the Quick host from the canonical union");
            if (refreshedRuler->rect != QRect(ruler->mapTo(&view, QPoint()), ruler->size()))
                failures.append(
                    "canonical ruler rectangle diverged from the ruler widget after font refresh");
        }
        overlay->setPlayhead(view.contentX(tick), true, false);
        checks::support::pumpQuick();
        if (overlay->geometry() != view.rect()) {
            failures.append("font-refreshed native playhead overlay lost owner geometry");
        } else if (expectsCapturablePlayhead()) {
            const QImage refreshedPlayhead = grabPlayhead(view, *overlay, failures).toImage();
            const QColor playheadColor = themes::color(themes::Role::song_view_playhead);
            const QRect refreshedRulerRect = checks::support::widgetRectIn(*ruler, view);
            const qreal expectedPlayheadX =
                ruler->mapTo(&view, QPoint(qRound(view.timelinePlotOrigin()), 0)).x() +
                view.contentX(tick);
            const qreal refreshedPlayheadX = playheadCenterAt(
                refreshedPlayhead, checks::support::widgetRectIn(*roll, view).center().y(),
                playheadColor);
            const int triangleTop = refreshedRulerRect.bottom() -
                                    songview::playheadTriangleHeight() + layout::singlePixel();
            const int triangleTopWidth = checks::support::playheadWidthAt(
                refreshedPlayhead, triangleTop + layout::singlePixel(), expectedPlayheadX,
                playheadColor);
            const int triangleBottomWidth = checks::support::playheadWidthAt(
                refreshedPlayhead,
                triangleTop + songview::playheadTriangleHeight() - layout::singlePixel(),
                expectedPlayheadX, playheadColor);
            if (refreshedPlayheadX < 0.0 ||
                std::abs(refreshedPlayheadX - expectedPlayheadX) > layout::singlePixel() + 0.75) {
                failures.append("font-refreshed playhead bands retained unusable geometry");
            }
            if (triangleTopWidth <= triangleBottomWidth || triangleBottomWidth == 0) {
                failures.append(
                    "font-scaled playhead triangle image did not use refreshed dimensions");
            }
        }
        QApplication::setFont(originalApplicationFont);
        view.setFont(originalViewFont);
        QEvent restoreFontChange(QEvent::FontChange);
        QCoreApplication::sendEvent(&view, &restoreFontChange);
        checks::support::pumpQuick();
        auto *const restoredOverlay =
            checks::support::findWidgetDescendant<songview::PlayheadOverlay>(view);
        if (!overlayLifetime || !restoredOverlay || restoredOverlay != originalOverlay)
            failures.append("restoring the font reconstructed the native playhead overlay");
        if (!restoredOverlay) {
            view.clearTimelineQuickHover(songview::TimelineQuickHoverOwner::Automation);
            view.setPlayheadSample(0, false);
            if (!viewWasVisible)
                view.hide();
            view.setAttribute(Qt::WA_DontShowOnScreen, hadDontShowOnScreen);
            return failures;
        }
        overlay = restoredOverlay;
        const std::optional<songview::TimelineBandGeometry> &restoredRuler =
            bandLayout.geometry(songview::TimelineBand::Ruler);
        if (!restoredRuler || restoredRuler->rect != canonicalRulerRectBeforeFont)
            failures.append("restoring the font did not return the canonical ruler rectangle");
        overlay->setPlayhead(view.contentX(tick), true, false);
        view.publishTimelineQuickHover(songview::TimelineQuickHoverOwner::Automation, tick);
        checks::support::pumpQuick();

        const auto expectedSongViewX = [&view, ruler](double chromeTick) {
            return ruler->mapTo(&view, QPoint(qRound(view.timelinePlotOrigin()), 0)).x() +
                   view.contentX(chromeTick);
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
        // Band widgets are overlays, not canonical sources: moving them must
        // not drag the Quick host, whose geometry is the canonical union.
        const QRect widgetMoveHostBefore = quick->geometry();
        // Two converted bands have no native widget to displace; the four
        // retained widget bands still must not drag the Quick host.
        const std::array<QWidget *, 4> guideBands = {
            ruler,
            roll,
            automationViewport,
            velocity,
        };
        std::array<QRect, guideBands.size()> guideBandGeometries;
        const int hostShift = layout::space(layout::Space::One);
        for (std::size_t index = 0; index < guideBands.size(); ++index) {
            guideBandGeometries[index] = guideBands[index]->geometry();
            guideBands[index]->move(guideBandGeometries[index].topLeft() + QPoint(hostShift, 0));
        }
        checks::support::pumpQuick();
        if (quick->geometry() != widgetMoveHostBefore ||
            quick->geometry() != canonicalBandUnion().value_or(QRect{})) {
            failures.append("Quick host followed a widget-only move off the canonical union");
        }
        for (std::size_t index = 0; index < guideBands.size(); ++index)
            guideBands[index]->setGeometry(guideBandGeometries[index]);
        checks::support::pumpQuick();
        // Only a parent-layout mutation may move the host: shrink the view so
        // the canonical union changes, then require host parity while the
        // retained guides retranslate into the moved host frame.
        const QRect canonicalUnionBeforeResize = canonicalBandUnion().value_or(QRect{});
        const QSize viewSizeBeforeResize = view.size();
        view.resize(view.width(), view.height() - 4 * layout::space(layout::Space::One));
        checks::support::pumpQuick();
        const std::optional<QRect> resizedUnion = canonicalBandUnion();
        if (!resizedUnion || *resizedUnion == canonicalUnionBeforeResize) {
            failures.append("canonical fixture resize did not change the canonical union");
        } else if (quick->geometry() != *resizedUnion) {
            failures.append("Quick host did not move with the canonical union after resize");
        }
        const std::optional<songview::TimelineBandGeometry> &resizedRoll =
            bandLayout.geometry(songview::TimelineBand::Roll);
        if (!resizedRoll ||
            resizedRoll->rect != QRect(roll->mapTo(&view, QPoint()), roll->size())) {
            failures.append("canonical roll rectangle went stale after the canonical resize");
        }
        if (std::abs(quick->hoverRootContentX() - quickContentX(expectedHover)) > 0.2 ||
            std::abs(quick->editRootContentX() - quickContentX(expectedEdit)) > 0.2) {
            failures.append("Quick guide coordinates did not retranslate after a canonical move");
        }
        for (const ChromeCopies &copy : copies) {
            if (!copy.hover || !copy.edit)
                continue;
            if (std::abs(checks::support::quickRootX(*copy.hover, *root) -
                         quickContentX(expectedHover)) > 0.2 ||
                std::abs(checks::support::quickRootX(*copy.edit, *root) -
                         quickContentX(expectedEdit)) > 0.2) {
                failures.append(
                    QStringLiteral("%1 guide did not retranslate after a canonical move")
                        .arg(copy.name));
            }
        }
        view.resize(viewSizeBeforeResize);
        checks::support::pumpQuick();
        if (quick->geometry() != canonicalBandUnion().value_or(QRect{}) ||
            quick->geometry() != widgetMoveHostBefore) {
            failures.append("Quick host did not restore the canonical union after resize");
        }
        const SongView::ViewState cameraState = view.viewState();
        const qreal oldEditX = quick->editRootContentX();
        view.setEditorHorizontalScroll(cameraState.scrollPx + view.pxPerBeat());
        if (view.viewState().scrollPx == cameraState.scrollPx)
            view.setEditorHorizontalScroll(cameraState.scrollPx - view.pxPerBeat());
        checks::support::pumpQuick();
        const qreal cameraEditX = expectedSongViewX(view.editCursorTick());
        if (view.viewState().scrollPx == cameraState.scrollPx) {
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
        view.publishTimelineQuickHover(songview::TimelineQuickHoverOwner::Automation, tick);

        const bool eventListWasVisible = view.eventListVisible();
        view.setEventListVisible(false);
        checks::support::pumpQuick();
        const auto canonicalRollMatchesRoll = [&] {
            const std::optional<songview::TimelineBandGeometry> &geometry =
                bandLayout.geometry(songview::TimelineBand::Roll);
            return geometry && roll->isVisibleTo(&view) &&
                   geometry->rect == QRect(roll->mapTo(&view, QPoint()), roll->size());
        };
        if (!canonicalRollMatchesRoll())
            failures.append("roll view canonical entry diverged from the piano-roll widget");
        const QColor playheadColor = themes::color(themes::Role::song_view_playhead);
        const qreal nativeX =
            ruler->mapTo(&view, QPoint(qRound(view.timelinePlotOrigin()), 0)).x() +
            view.contentX(timeline.tickForSample(sample));
        qreal renderedNativeX = nativeX;
        const QRect rollRect = checks::support::widgetRectIn(*roll, view);
        const QRect rulerRect = checks::support::widgetRectIn(*ruler, view);
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
            return ruler->mapTo(&view, QPoint(qRound(view.timelinePlotOrigin()), 0)).x() +
                   view.contentX(timeline.tickForSample(sample));
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

        const auto checkVisibleBand = [&](QWidget &band, const char *name) {
            if (!captureExpected)
                return;
            const QImage image = grabPlayhead(view, *overlay, failures).toImage();
            const qreal bandNativeX = currentNativeX();
            const QRect bandRect = checks::support::widgetRectIn(band, view);
            if (!band.isVisibleTo(&view) ||
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
        // The voice changes page renders in the Quick scene instead of a
        // native widget: its clip check probes the canonical SongView-local
        // band rectangle directly.
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
        checkVisibleBand(*velocity, "velocity");
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
        checkVisibleBand(*automationViewport, "automation viewport");
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
            lifecycleHost != canonicalBandUnion().value_or(QRect{}))
            failures.append(
                "a lifecycle event moved the canonical layout or dropped the Quick host frame");
        auto *lifecycleHandle =
            drawer->findChild<QWidget *>(QStringLiteral("velocityResizeHandle"));
        const QRegion &lifecycleMask = quick->quickWindow()->mask();
        if (!root->property("rollBandVisible").toBool() ||
            root->property("rollBandRect").toRectF() != lifecycleRollLocal ||
            !lifecycleMask.contains(lifecycleRollLocal.center().toPoint()) || !lifecycleHandle ||
            lifecycleMask.contains(lifecycleHandle->mapTo(&view, lifecycleHandle->rect().center()) -
                                   lifecycleHost.topLeft())) {
            failures.append(
                "lifecycle republish dropped the QML roll band geometry or window mask");
        }
        checkVisibleBand(*roll, "piano roll after lifecycle republish");
        checkVisibleBand(*velocity, "velocity lane after lifecycle republish");
        // Hover must be checked while the automation page is the explicitly
        // shown, active surface — before the saved editor state restores the
        // fixture defaults and hides the sibling sections again.
        checkAutomationHover(view, failures);
        view.applyEditorViewState(savedEditorState);
        view.setEventListVisible(eventListWasVisible);
        checks::support::pumpQuick();

        view.setPlayheadSample(timeline.sampleForTick(tick), true);
        checks::support::pumpQuick();
        const auto beforeMoves = checks::support::timelineQuickLayerRevisions(*scene);
        for (uint64_t move = 1; move <= 128; ++move)
            view.setPlayheadSample(timeline.sampleForTick(tick + move), true);
        checks::support::pumpQuick();
        if (checks::support::timelineQuickLayerRevisions(*scene) != beforeMoves)
            failures.append("128 position-only SongView moves rebuilt TimelineQuickLayer data");

#ifdef __APPLE__
        checkMacPlayheadLifecycle(view, *overlay, failures);
#endif
    }

    failures += quickFallbackPlayheadCheckFailures(timeline);
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
