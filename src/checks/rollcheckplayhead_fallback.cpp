#include "rollcheckplayhead.h"

#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"

#include <QByteArray>
#include <QColor>
#include <QImage>
#include <QPixmap>
#include <QPoint>
#include <QQuickItem>
#include <QtGlobal>

#include <algorithm>
#include <cstdio>
#include <memory>
#include <optional>

#include "core/miditimeline.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/eventlistview.h"
#include "ui/layout.h"
#include "ui/playheadoverlay.h"
#include "ui/songview.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timelinebandlayout.h"
#include "ui/theme/themeruntime.h"

namespace {

class EnvironmentGuard final
{
  public:
    explicit EnvironmentGuard(const char *name)
        : m_name(name)
        , m_wasSet(qEnvironmentVariableIsSet(name))
        , m_value(qgetenv(name))
    {}

    ~EnvironmentGuard()
    {
        if (m_wasSet)
            qputenv(m_name, m_value);
        else
            qunsetenv(m_name);
    }

    Q_DISABLE_COPY_MOVE(EnvironmentGuard)

  private:
    const char *m_name;
    bool m_wasSet;
    QByteArray m_value;
};

} // namespace

QStringList quickFallbackPlayheadCheckFailures(const MidiTimeline &timeline)
{
    QStringList failures;
    EnvironmentGuard forceWidgetPlayhead{"PORYDAW_FORCE_WIDGET_PLAYHEAD"};
    qputenv("PORYDAW_FORCE_WIDGET_PLAYHEAD", "1");

    SongView probe;
    const int unit = layout::space(layout::Space::One);
    probe.resize(90 * unit, 65 * unit);
    probe.setSong(&timeline, nullptr);
    probe.setFollowPlayhead(false);
    probe.show();
    checks::support::pumpQuick();

    auto *quick =
        probe.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    auto *scene = quick ? quick->findChild<songview::TimelineQuickScene *>() : nullptr;
    auto *overlay = probe.findChild<songview::PlayheadOverlay *>();
    QWidget *const fallback = overlay ? overlay->fallbackWidget() : nullptr;
    auto *roll = probe.findChild<songview::PianoRoll *>();
    const auto rollBandRect = [&probe] {
        const std::optional<songview::TimelineBandGeometry> &band =
            probe.timelineBandLayout().geometry(songview::TimelineBand::Roll);
        return band ? band->rect : QRect{};
    };
    auto *eventList = checks::support::findWidgetDescendant<EventListView>(probe);
    auto *drawer = probe.editorDrawer();
    auto *automation = drawer ? drawer->automationPage() : nullptr;
    auto *velocity = drawer ? drawer->velocityArea() : nullptr;
    auto *voiceChanges = drawer ? drawer->voiceChangeArea() : nullptr;
    const songview::TimelineBandLayout &bandLayout = probe.timelineBandLayout();
    if (!quick || !scene || !overlay || !fallback ||
        !bandLayout.geometry(songview::TimelineBand::Ruler) || !roll || !eventList || !automation ||
        !velocity || !voiceChanges) {
        failures.append("forced QWidget playhead fallback did not expose its rendering surfaces");
        probe.hide();
        return failures;
    }
    if (fallback->parentWidget() != &probe || fallback->geometry() != probe.rect())
        failures.append(
            "forced QWidget playhead fallback did not own the complete SongView surface");

    const uint64_t tick =
        uint64_t(std::max(0.0, probe.camera().tickAtContentX(std::max<qreal>(
                                   1.0, probe.width() / 2.0 - probe.timelinePlotOrigin()))));
    uint64_t playheadTick = tick;
    const auto setPlayhead = [&](uint64_t nextTick, bool playing) {
        playheadTick = nextTick;
        probe.setPlayheadSample(timeline.sampleForTick(playheadTick), playing);
        checks::support::pumpQuick();
    };
    const auto playheadX = [&] {
        const std::optional<songview::TimelineBandGeometry> &rulerGeometry =
            probe.timelineBandLayout().geometry(songview::TimelineBand::Ruler);
        return (rulerGeometry ? rulerGeometry->rect.x() + rulerGeometry->timelineOrigin
                              : qRound(probe.timelinePlotOrigin())) +
               probe.camera().contentX(
                   timeline.tickForSample(timeline.sampleForTick(playheadTick)));
    };

    setPlayhead(tick, false);
    const QColor color = themes::color(themes::Role::song_view_playhead);
    const auto fallbackImage = [&] { return fallback->grab().toImage(); };
    // Converted bands render in the Quick scene instead of native widgets;
    // their clip checks probe canonical SongView-local rectangles.
    const auto checkVisibleBodyRect = [&](const QRect &bandRect, const char *name) {
        const QImage image = fallbackImage();
        const QRect bodyProbe{qRound(playheadX()) - layout::singlePixel(), bandRect.center().y(),
                              2 * layout::singlePixel() + 1, layout::singlePixel()};
        if (image.isNull() || !bandRect.isValid() ||
            !checks::support::hasPlayheadPixel(image, bodyProbe, color)) {
            failures.append(QStringLiteral("playhead body was not clipped into visible %1")
                                .arg(QString::fromLatin1(name)));
        }
    };
    const auto checkRulerTriangle = [&](const QImage &image, bool pointsUp, const char *state) {
        const QRect rulerRect = probe.timelineBandLayout()
                                    .geometry(songview::TimelineBand::Ruler)
                                    .value_or(songview::TimelineBandGeometry{})
                                    .rect;
        const int triangleTop =
            rulerRect.bottom() - songview::playheadTriangleHeight() + layout::singlePixel();
        const int topWidth = checks::support::playheadWidthAt(
            image, triangleTop + layout::singlePixel(), playheadX(), color);
        const int bottomWidth = checks::support::playheadWidthAt(
            image, triangleTop + songview::playheadTriangleHeight() - layout::singlePixel(),
            playheadX(), color);
        const bool isInRuler =
            triangleTop >= rulerRect.top() &&
            triangleTop + songview::playheadTriangleHeight() <= rulerRect.bottom() + 1;
        if (image.isNull() || !isInRuler ||
            (pointsUp ? bottomWidth <= topWidth : topWidth <= bottomWidth)) {
            failures.append(
                QStringLiteral("forced QWidget ruler triangle was not %1 and clipped in %2")
                    .arg(QString::fromLatin1(pointsUp ? "up" : "down"),
                         QString::fromLatin1(state)));
        }
    };

    checkVisibleBodyRect(bandLayout.geometry(songview::TimelineBand::Ruler)
                             .value_or(songview::TimelineBandGeometry{})
                             .rect,
                         "ruler");
    checkVisibleBodyRect(rollBandRect(), "piano roll");
    checkVisibleBodyRect(bandLayout.geometry(songview::TimelineBand::OtherEvents)
                             .value_or(songview::TimelineBandGeometry{})
                             .rect,
                         "other-events");
    checkRulerTriangle(fallbackImage(), false, "roll view");

    const QRect rollRect = rollBandRect();
    const QRect keyboardGutterRect{0, rollRect.top(), qRound(probe.timelinePlotOrigin()),
                                   rollRect.height()};
    const SongView::ViewState savedKeyboardViewport = probe.viewState();
    SongView::ViewState keyboardViewport = savedKeyboardViewport;
    const int keyboardTargetX = keyboardGutterRect.right();
    keyboardViewport.scrollPx += playheadX() - keyboardTargetX;
    probe.applyViewState(keyboardViewport);
    setPlayhead(tick, false);
    if (!keyboardGutterRect.contains(
            QPoint{qRound(playheadX()), keyboardGutterRect.center().y()})) {
        failures.append(
            "forced QWidget keyboard/gutter clip fixture could not position the playhead");
    } else if (checks::support::hasPlayheadPixel(fallbackImage(), keyboardGutterRect, color)) {
        failures.append("forced QWidget playhead escaped into the piano keyboard or track gutter");
    }
    probe.applyViewState(savedKeyboardViewport);
    setPlayhead(tick, false);

    probe.setEventListVisible(true);
    checks::support::pumpQuick();
    const QImage eventListImage = fallbackImage();
    const QRect eventListRect = checks::support::widgetRectIn(*eventList, probe);
    const int sampleY = eventListRect.top() + 2 * layout::singlePixel();
    const QRect eventListProbe{qRound(playheadX()) - layout::singlePixel(), sampleY,
                               2 * layout::singlePixel() + 1, layout::singlePixel()};
    if (!eventList->isVisibleTo(&probe) || !eventListRect.contains(eventListProbe)) {
        failures.append("forced QWidget event-list clip fixture did not become visible");
    } else if (fallback->mask().intersects(eventListProbe)) {
        failures.append("forced QWidget playhead mask included the event-list band");
    } else if (checks::support::hasPlayheadPixel(eventListImage, eventListProbe, color)) {
        failures.append("forced QWidget masked grab retained pixels in the event-list band");
    }
    checkRulerTriangle(eventListImage, true, "event-list view");
    probe.setEventListVisible(false);
    checks::support::pumpQuick();

    probe.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    probe.setDrawerActivePage(EditorDrawerPage::Velocity);
    checks::support::pumpQuick();
    checkVisibleBodyRect(bandLayout.geometry(songview::TimelineBand::Velocity)
                             .value_or(songview::TimelineBandGeometry{})
                             .rect,
                         "velocity");

    probe.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    probe.setDrawerActivePage(EditorDrawerPage::VoiceChanges);
    checks::support::pumpQuick();
    checkVisibleBodyRect(bandLayout.geometry(songview::TimelineBand::VoiceChanges)
                             .value_or(songview::TimelineBandGeometry{})
                             .rect,
                         "voice-change");

    probe.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    probe.setDrawerActivePage(EditorDrawerPage::Automations);
    checks::support::pumpQuick();
    checkVisibleBodyRect(bandLayout.geometry(songview::TimelineBand::Automation)
                             .value_or(songview::TimelineBandGeometry{})
                             .rect,
                         "automation");
    checkVisibleBodyRect(bandLayout.geometry(songview::TimelineBand::OtherEvents)
                             .value_or(songview::TimelineBandGeometry{})
                             .rect,
                         "other-events");

    // The drawer setup above queues Quick dirty flushes and posted resize
    // events for the newly shown bodies that outlive its pump; those land in
    // later event-loop passes, not in playhead work. Settle at the observable
    // boundary — revisions unchanged across one full pump — so the loop
    // measures only revisions caused by the 128 playhead updates.
    checks::support::TimelineQuickLayerRevisions beforeMoves =
        checks::support::timelineQuickLayerRevisions(*scene);
    bool revisionsSettled = false;
    for (int settle = 0; settle < 8 && !revisionsSettled; ++settle) {
        checks::support::pumpQuick();
        const checks::support::TimelineQuickLayerRevisions settled =
            checks::support::timelineQuickLayerRevisions(*scene);
        revisionsSettled = settled == beforeMoves;
        beforeMoves = settled;
    }
    if (!revisionsSettled)
        failures.append("forced QWidget playhead fixture could not settle Quick layer "
                        "revisions before the move loop");
    for (uint64_t move = 1; move <= 128; ++move)
        setPlayhead(tick + move, true);
    if (checks::support::timelineQuickLayerRevisions(*scene) != beforeMoves)
        failures.append("128 forced QWidget playhead moves rebuilt TimelineQuickLayer data");
    checkVisibleBodyRect(bandLayout.geometry(songview::TimelineBand::Automation)
                             .value_or(songview::TimelineBandGeometry{})
                             .rect,
                         "automation after position move");

    overlay->setPlayhead(0.0, false, false);
    checks::support::pumpQuick();
    const QImage hidden = fallbackImage();
    if (checks::support::hasPlayheadPixel(hidden, hidden.rect(), color))
        failures.append("forced QWidget playhead remained painted after a hidden presentation");

    const auto canonicalAutomationMatches = [&] {
        const std::optional<songview::TimelineBandGeometry> &geometry =
            bandLayout.geometry(songview::TimelineBand::Automation);
        const std::optional<QRect> body = drawer->bodyRect(EditorDrawerPage::Automations);
        const int scrollbarWidth = layout::space(layout::Space::Two);
        return geometry && body &&
               geometry->rect == QRect{body->x() + scrollbarWidth, body->y(),
                                       std::max(0, body->width() - scrollbarWidth), body->height()};
    };
    const auto canonicalVoiceMatches = [&] {
        const std::optional<songview::TimelineBandGeometry> &geometry =
            bandLayout.geometry(songview::TimelineBand::VoiceChanges);
        return geometry && geometry->timelineOrigin == voiceChanges->plotOrigin();
    };
    const auto canonicalVelocityMatches = [&] {
        const std::optional<songview::TimelineBandGeometry> &geometry =
            bandLayout.geometry(songview::TimelineBand::Velocity);
        return geometry &&
               drawer->bodyRect(EditorDrawerPage::Velocity) == std::optional<QRect>(geometry->rect);
    };
    if (!canonicalVelocityMatches() || !canonicalVoiceMatches() || !canonicalAutomationMatches()) {
        failures.append("forced QWidget playhead view diverged from the canonical band layout");
    }

    // Collapsing every drawer section must clear the canonical and drawer
    // body entries; the remaining ruler, roll, and other-events clips keep
    // covering the timeline column.
    probe.setDrawerSectionVisible(EditorDrawerPage::Velocity, false);
    probe.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
    probe.setDrawerSectionVisible(EditorDrawerPage::Automations, false);
    checks::support::pumpQuick();
    if (bandLayout.geometry(songview::TimelineBand::Velocity) ||
        bandLayout.geometry(songview::TimelineBand::VoiceChanges) ||
        bandLayout.geometry(songview::TimelineBand::Automation) ||
        drawer->bodyRect(EditorDrawerPage::Velocity) ||
        drawer->bodyRect(EditorDrawerPage::VoiceChanges) ||
        drawer->bodyRect(EditorDrawerPage::Automations)) {
        failures.append("collapsed drawer sections retained canonical or drawer rectangles");
    }
    probe.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    probe.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    probe.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    checks::support::pumpQuick();
    if (!canonicalVelocityMatches())
        failures.append("reopened velocity section did not republish its canonical rectangle");

    probe.hide();
    checks::support::pumpQuick();
    return failures;
}

QStringList quickScenePlayheadCheckFailures(const MidiTimeline &timeline)
{
    QStringList failures;
    EnvironmentGuard forceQuickPlayhead{"PORYDAW_FORCE_QUICK_PLAYHEAD"};
    qputenv("PORYDAW_FORCE_QUICK_PLAYHEAD", "1");

    SongView probe;
    const int unit = layout::space(layout::Space::One);
    probe.resize(90 * unit, 65 * unit);
    probe.setSong(&timeline, nullptr);
    probe.setFollowPlayhead(false);
    probe.show();
    checks::support::pumpQuick();

    auto *overlay = probe.findChild<songview::PlayheadOverlay *>();
    auto *quick =
        probe.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    const songview::TimelineBandLayout &bandLayout = probe.timelineBandLayout();
    const auto rollBandRect = [&bandLayout] {
        const std::optional<songview::TimelineBandGeometry> &band =
            bandLayout.geometry(songview::TimelineBand::Roll);
        return band ? band->rect : QRect{};
    };
    const auto rollTimelineOrigin = [&bandLayout] {
        const std::optional<songview::TimelineBandGeometry> &band =
            bandLayout.geometry(songview::TimelineBand::Roll);
        return band ? band->timelineOrigin : 0;
    };
    if (!overlay || !quick || !bandLayout.geometry(songview::TimelineBand::Ruler) ||
        !rollBandRect().isValid()) {
        failures.append("forced Quick playhead scene did not expose its rendering surfaces");
        probe.hide();
        checks::support::pumpQuick();
        return failures;
    }
    if (!songview::quickPlayheadRendererEnabled())
        failures.append("PORYDAW_FORCE_QUICK_PLAYHEAD did not enable the Quick playhead renderer");
    if (songview::platformPlayheadRendererEnabled())
        failures.append("PORYDAW_FORCE_QUICK_PLAYHEAD left the native playhead renderer enabled");
    if (overlay->fallbackWidget())
        failures.append("Quick playhead scene allocated the QWidget fallback renderer");

    const uint64_t tick =
        uint64_t(std::max(0.0, probe.camera().tickAtContentX(std::max<qreal>(
                                   1.0, probe.width() / 2.0 - probe.timelinePlotOrigin()))));
    const QColor color = themes::color(themes::Role::song_view_playhead);
    const QRect rollRect = rollBandRect();
    // captureQuickBand crops are band-local logical coordinates; scan the full
    // band so the pixel proof never depends on camera-X vs QML-X agreement.
    const QRect bandLocalRect{0, 0, rollRect.width(), rollRect.height()};

    probe.setPlayheadSample(timeline.sampleForTick(tick), false);
    checks::support::pumpQuick();
    QQuickItem *body =
        quick->rootObject()->findChild<QQuickItem *>(QStringLiteral("timelineQuickRollPlayhead"));
    if (!body)
        failures.append("Quick playhead scene did not expose the timelineQuickRollPlayhead item");
    else if (!body->isVisible() || body->width() < 1 || body->height() < 1)
        failures.append(
            QStringLiteral("timelineQuickRollPlayhead item was hidden or undersized "
                           "(visible=%1 width=%2 height=%3)")
                .arg(body->isVisible() ? QStringLiteral("true") : QStringLiteral("false"))
                .arg(body->width())
                .arg(body->height()));
    QString captureError;
    const QImage rollFrame = checks::support::captureQuickBand(probe, rollRect, &captureError);
    if (!quick->playheadVisible())
        failures.append("SongView playhead sample did not publish visibility to the Quick canvas");
    if (rollFrame.isNull()) {
        failures.append(
            QStringLiteral("Quick playhead roll-band capture failed: %1").arg(captureError));
    } else if (!checks::support::hasPlayheadPixel(rollFrame, bandLocalRect, color)) {
        failures.append("Quick playhead body was not rendered into the piano roll band");
        if (body) {
            const QPointF bodyCenterInCanvas = body->mapToItem(
                quick->rootObject(), QPointF{body->width() / 2, body->height() / 2});
            failures.append(QStringLiteral("timelineQuickRollPlayhead item geometry: "
                                           "x=%1 y=%2 width=%3 height=%4 canvas-center=%5,%6")
                                .arg(body->x())
                                .arg(body->y())
                                .arg(body->width())
                                .arg(body->height())
                                .arg(bodyCenterInCanvas.x())
                                .arg(bodyCenterInCanvas.y()));
        }
    }

    // Park the playhead just inside the plot: timeline X is relative to the plot
    // origin, so 1.0 puts the core ~1px past it and the bloom would cross into
    // the gutter unless the Quick renderer clips to the plot strip.
    overlay->setPlayhead(1.0, true, true);
    checks::support::pumpQuick();
    const QImage gutterFrame = checks::support::captureQuickBand(probe, rollRect, &captureError);
    const int timelineOrigin = rollTimelineOrigin();
    if (gutterFrame.isNull()) {
        failures.append(
            QStringLiteral("Quick playhead gutter roll-band capture failed: %1").arg(captureError));
    } else {
        if (timelineOrigin > 0) {
            const QRect gutterRect{0, 0, timelineOrigin, rollRect.height()};
            if (checks::support::hasPlayheadPixel(gutterFrame, gutterRect, color))
                failures.append("Quick playhead painted into the timelineOrigin gutter");
        }
        const QRect plotStripRect{timelineOrigin, 0, rollRect.width() - timelineOrigin,
                                  rollRect.height()};
        if (!checks::support::hasPlayheadPixel(gutterFrame, plotStripRect, color))
            failures.append("Quick playhead gutter proof left no pixel in the roll plot strip");
    }
    overlay->setPlayhead(0, false, false);
    checks::support::pumpQuick();
    if (quick->playheadVisible())
        failures.append("hidden Quick playhead still reported visibility to the Quick canvas");
    const QImage hiddenFrame = checks::support::captureQuickBand(probe, rollRect, &captureError);
    if (hiddenFrame.isNull()) {
        failures.append(
            QStringLiteral("hidden Quick playhead roll-band capture failed: %1").arg(captureError));
    } else if (checks::support::hasPlayheadPixel(hiddenFrame, bandLocalRect, color)) {
        failures.append("hidden Quick playhead retained pixels in the piano roll band");
    }

    probe.hide();
    checks::support::pumpQuick();
    return failures;
}

int runRenderingPlayheadCheck(const QString &scratchProject, const QString &songLabel,
                              const QString &screenshotPath)
{
    (void)screenshotPath;

    QString error;
    auto loadedSong = checks::LoadedSong::load(scratchProject, songLabel, error);
    if (!loadedSong) {
        std::fprintf(stderr, "rendering-playhead: %s\n", qUtf8Printable(error));
        return 1;
    }
    auto rig = checks::SongViewRig::create(std::move(loadedSong), 48000.0, error);
    if (!rig) {
        std::fprintf(stderr, "rendering-playhead: %s\n", qUtf8Printable(error));
        return 1;
    }

    const QStringList failures = timelineChromeCheckFailures(rig->view(), rig->timeline());
    for (const QString &failure : failures)
        std::fprintf(stderr, "rendering-playhead: FAIL: %s\n", qUtf8Printable(failure));
    if (failures.isEmpty())
        std::fprintf(stderr, "rendering-playhead: PASS\n");
    return failures.isEmpty() ? 0 : 1;
}
