#include "rollcheckplayhead.h"

#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"

#include <QByteArray>
#include <QColor>
#include <QImage>
#include <QPixmap>
#include <QPoint>
#include <QWidget>
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
    auto *overlay = checks::support::findWidgetDescendant<songview::PlayheadOverlay>(probe);
    auto *roll = checks::support::findWidgetDescendant<songview::PianoRoll>(probe);
    auto *eventList = checks::support::findWidgetDescendant<EventListView>(probe);
    auto *drawer = probe.editorDrawer();
    auto *automation = drawer ? drawer->automationPage() : nullptr;
    auto *velocity = drawer ? drawer->velocityArea() : nullptr;
    auto *voiceChanges = drawer ? drawer->voiceChangeArea() : nullptr;
    const songview::TimelineBandLayout &bandLayout = probe.timelineBandLayout();
    if (!quick || !scene || !overlay || !bandLayout.geometry(songview::TimelineBand::Ruler) ||
        !roll || !eventList || !automation || !velocity || !voiceChanges) {
        failures.append("forced QWidget playhead fallback did not expose its rendering surfaces");
        probe.hide();
        return failures;
    }
    if (overlay->parentWidget() != &probe || overlay->geometry() != probe.rect())
        failures.append(
            "forced QWidget playhead fallback did not own the complete SongView surface");

    const uint64_t tick =
        uint64_t(std::max(0.0, probe.tickAtContentX(std::max<qreal>(
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
               probe.contentX(timeline.tickForSample(timeline.sampleForTick(playheadTick)));
    };

    setPlayhead(tick, false);
    const QColor color = themes::color(themes::Role::song_view_playhead);
    const auto fallbackImage = [&] { return overlay->grab().toImage(); };
    const auto checkVisibleBody = [&](QWidget &band, const char *name) {
        const QImage image = fallbackImage();
        const QRect bandRect = checks::support::widgetRectIn(band, probe);
        const QRect bodyProbe{qRound(playheadX()) - layout::singlePixel(), bandRect.center().y(),
                              2 * layout::singlePixel() + 1, layout::singlePixel()};
        if (image.isNull() || !band.isVisibleTo(&probe) ||
            !checks::support::hasPlayheadPixel(image, bodyProbe, color)) {
            failures.append(
                QStringLiteral("forced QWidget playhead body was not clipped into visible %1")
                    .arg(QString::fromLatin1(name)));
        }
    };
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
    checkVisibleBody(*roll, "piano roll");
    checkVisibleBodyRect(bandLayout.geometry(songview::TimelineBand::OtherEvents)
                             .value_or(songview::TimelineBandGeometry{})
                             .rect,
                         "other-events");
    checkRulerTriangle(fallbackImage(), false, "roll view");

    const QRect rollRect = checks::support::widgetRectIn(*roll, probe);
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
    } else if (overlay->mask().intersects(eventListProbe)) {
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
    checkVisibleBody(*velocity, "velocity");

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
    checkVisibleBody(*automation->scrollViewport(), "automation viewport");
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
    checkVisibleBody(*automation->scrollViewport(), "automation viewport after position move");

    overlay->setPlayhead(0.0, false, false);
    checks::support::pumpQuick();
    const QImage hidden = fallbackImage();
    if (checks::support::hasPlayheadPixel(hidden, hidden.rect(), color))
        failures.append("forced QWidget playhead remained painted after a hidden presentation");

    const auto canonicalRectMatches = [&](songview::TimelineBand band, const QWidget &widget) {
        const std::optional<songview::TimelineBandGeometry> &geometry = bandLayout.geometry(band);
        return geometry && widget.isVisibleTo(&probe) &&
               geometry->rect == QRect(widget.mapTo(&probe, QPoint()), widget.size());
    };
    const auto canonicalVoiceMatches = [&] {
        const std::optional<songview::TimelineBandGeometry> &geometry =
            bandLayout.geometry(songview::TimelineBand::VoiceChanges);
        return geometry && geometry->timelineOrigin == voiceChanges->plotOrigin();
    };
    if (!canonicalRectMatches(songview::TimelineBand::Velocity, *velocity) ||
        !canonicalVoiceMatches() ||
        !canonicalRectMatches(songview::TimelineBand::Automation, *automation->scrollViewport()) ||
        drawer->bodyRect(EditorDrawerPage::Velocity) !=
            std::optional<QRect>(bandLayout.geometry(songview::TimelineBand::Velocity)
                                     .value_or(songview::TimelineBandGeometry{})
                                     .rect)) {
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
    if (!canonicalRectMatches(songview::TimelineBand::Velocity, *velocity))
        failures.append("reopened velocity section did not republish its canonical rectangle");

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
