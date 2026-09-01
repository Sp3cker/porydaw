#include "rollcheckplayhead.h"

#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"

#include <QCoreApplication>
#include <QEvent>
#include <QImage>
#include <QQuickItem>
#include <QQuickWidget>
#include <QScrollArea>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>

#include "core/miditimeline.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/drawerpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickchrome.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timeruler.h"

namespace {
template <typename T>
T *findWidgetDescendant(QWidget &root)
{
    for (QWidget *widget : root.findChildren<QWidget *>()) {
        if (auto *typed = dynamic_cast<T *>(widget))
            return typed;
    }
    return nullptr;
}

void pumpQuick()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
}

struct ChromeCopies {
    const char *name;
    songview::TimelineChromeItem *hover = nullptr;
    songview::TimelineChromeItem *edit = nullptr;
    songview::TimelineChromeItem *playhead = nullptr;
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
        copy.playhead = root.findChild<songview::TimelineChromeItem *>(prefix + "PlayheadChrome");
    }
    return copies;
}

qreal rootX(const QQuickItem &item, QQuickItem &root)
{
    return item.mapToItem(&root, QPointF{}).x();
}

std::array<quint64, static_cast<std::size_t>(songview::TimelineQuickLayer::Count)>
layerRevisions(const songview::TimelineQuickScene &scene)
{
    std::array<quint64, static_cast<std::size_t>(songview::TimelineQuickLayer::Count)> revisions{};
    for (std::size_t index = 0; index < revisions.size(); ++index)
        revisions[index] = scene.layer(static_cast<songview::TimelineQuickLayer>(index)).revision;
    return revisions;
}

void checkAutomationHover(SongView &view, QStringList &failures)
{
    auto *page = view.editorDrawer() ? view.editorDrawer()->automationPage() : nullptr;
    auto *canvas = page ? page->canvas() : nullptr;
    auto *viewport = page ? page->scrollViewport() : nullptr;
    if (!canvas || !viewport)
        return;
    QString captureError;
    QEvent leave(QEvent::Leave);
    QCoreApplication::sendEvent(canvas, &leave);
    pumpQuick();
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
    pumpQuick();
    const QImage hovered = checks::support::captureQuickBand(view, *viewport, &captureError);
    if (hovered == baseline)
        failures.append("automation hover did not retain its local Quick decoration");
    QCoreApplication::sendEvent(canvas, &leave);
    pumpQuick();
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

} // namespace

QStringList timelineChromeCheckFailures(SongView &view, const MidiTimeline &timeline)
{
    QStringList failures;
    const bool viewWasVisible = view.isVisible();
    const bool hadDontShowOnScreen = view.testAttribute(Qt::WA_DontShowOnScreen);
    if (!viewWasVisible) {
        view.setAttribute(Qt::WA_DontShowOnScreen);
        view.show();
    }
    pumpQuick();

    auto *quick =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    auto *root = quick ? qobject_cast<QQuickItem *>(quick->rootObject()) : nullptr;
    auto *scene = quick ? quick->findChild<songview::TimelineQuickScene *>() : nullptr;
    auto *ruler = findWidgetDescendant<songview::TimeRuler>(view);
    if (!quick || !root || !scene || !ruler) {
        failures.append("SongView did not expose its retained Quick timeline chrome");
    } else {
        const auto copies = chromeCopies(*root);
        if (root->findChildren<songview::TimelineChromeItem *>().size() != 18)
            failures.append("Quick timeline did not retain exactly three chrome copies per band");
        for (const ChromeCopies &copy : copies) {
            if (!copy.hover || !copy.edit || !copy.playhead) {
                failures.append(
                    QStringLiteral("Quick timeline is missing %1 chrome").arg(copy.name));
                continue;
            }
            if (copy.hover->z() != 9.0 || copy.edit->z() != 10.0 || copy.playhead->z() != 11.0) {
                failures.append(QStringLiteral("%1 chrome does not stack hover, edit, playhead")
                                    .arg(copy.name));
            }
        }

        const uint64_t tick =
            uint64_t(std::max(0.0, view.tickAtContentX(std::max<qreal>(
                                       1.0, view.width() / 2.0 - view.timelinePlotOrigin()))));
        const uint64_t sample = timeline.sampleForTick(tick);
        view.setEditCursorTick(tick);
        view.setPlayheadSample(sample, false);
        view.publishTimelineQuickHover(songview::TimelineQuickHoverOwner::Automation, tick);
        pumpQuick();

        const auto expected = [&view](double chromeTick) {
            return view.timelinePlotOrigin() + view.contentX(chromeTick);
        };
        const qreal expectedHover = expected(tick);
        const qreal expectedEdit = expected(view.editCursorTick());
        const qreal expectedPlayhead = expected(timeline.tickForSample(sample));
        if (std::abs(quick->hoverRootContentX() - expectedHover) > 0.2 ||
            std::abs(quick->editRootContentX() - expectedEdit) > 0.2 ||
            std::abs(quick->playheadRootContentX() - expectedPlayhead) > 0.2) {
            failures.append("Quick chrome root coordinates do not follow SongView content x");
        }
        if (expectedPlayhead < view.timelinePlotOrigin())
            failures.append("playhead chrome escaped into the timeline gutter");
        for (const ChromeCopies &copy : copies) {
            if (!copy.hover || !copy.edit || !copy.playhead)
                continue;
            if (std::abs(rootX(*copy.hover, *root) - expectedHover) > 0.2 ||
                std::abs(rootX(*copy.edit, *root) - expectedEdit) > 0.2 ||
                std::abs(rootX(*copy.playhead, *root) - expectedPlayhead) > 0.2) {
                failures.append(
                    QStringLiteral("%1 chrome did not align across Quick bands").arg(copy.name));
            }
        }

        const qreal oldPlayheadX = quick->playheadRootContentX();
        view.setEditorHorizontalScroll(view.viewState().scrollPx + view.pxPerBeat());
        pumpQuick();
        const qreal cameraPlayheadX = expected(view.playheadTick());
        if (std::abs(quick->playheadRootContentX() - cameraPlayheadX) > 0.2 ||
            (cameraPlayheadX != oldPlayheadX && quick->playheadRootContentX() == oldPlayheadX)) {
            failures.append("camera motion did not update retained Quick chrome");
        }

        view.publishTimelineQuickHover(songview::TimelineQuickHoverOwner::VoiceChanges, tick + 1);
        view.clearTimelineQuickHover(songview::TimelineQuickHoverOwner::Automation);
        pumpQuick();
        if (!quick->hoverVisible() ||
            std::abs(quick->hoverRootContentX() - expected(tick + 1)) > 0.2)
            failures.append("a stale hover clear hid the newer owner chrome");
        view.clearTimelineQuickHover(songview::TimelineQuickHoverOwner::VoiceChanges);
        if (quick->hoverVisible())
            failures.append("the owning hover clear did not hide Quick chrome");
        view.publishTimelineQuickHover(songview::TimelineQuickHoverOwner::Automation, tick);

        view.setEventListVisible(true);
        pumpQuick();
        if (copies[1].playhead && copies[1].playhead->isVisible())
            failures.append("hidden piano-roll chrome remained visible over the event list");
        if (copies[0].playhead && !copies[0].playhead->isVisible())
            failures.append("event-list replacement hid ruler chrome");
        if (copies[0].playhead && copies[0].playhead->rulerTriangle() !=
                                      songview::TimelineChromeItem::RulerTriangle::Up) {
            failures.append("ruler triangle did not flip up when the roll was hidden");
        }
        view.setEventListVisible(false);
        pumpQuick();
        if (copies[0].playhead && copies[0].playhead->rulerTriangle() !=
                                      songview::TimelineChromeItem::RulerTriangle::Down) {
            failures.append("ruler triangle did not point down above the roll");
        }

        const SongView::ViewState savedState = view.viewState();
        view.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
        view.setDrawerActivePage(EditorDrawerPage::Velocity);
        pumpQuick();
        if (copies[3].playhead && !copies[3].playhead->isVisible())
            failures.append("velocity drawer did not expose clipped Quick chrome");
        view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
        view.setDrawerActivePage(EditorDrawerPage::VoiceChanges);
        pumpQuick();
        if (copies[4].playhead && !copies[4].playhead->isVisible())
            failures.append("voice-change drawer did not expose clipped Quick chrome");
        view.applyViewState(savedState);
        pumpQuick();

        const auto beforeMoves = layerRevisions(*scene);
        const uint64_t laterSample = timeline.sampleForTick(tick + 256);
        for (uint64_t move = 0; move < 128; ++move)
            view.setPlayheadSample(sample + (laterSample - sample) * move / 127, false);
        pumpQuick();
        if (layerRevisions(*scene) != beforeMoves)
            failures.append("120 retained playhead moves rebuilt TimelineQuickLayer data");

        const uint64_t fractionalEnd = timeline.sampleForTick(tick + 2);
        uint64_t fractionalSample = sample;
        for (uint64_t candidate = sample + 1; candidate < fractionalEnd; ++candidate) {
            const qreal candidateX = expected(timeline.tickForSample(candidate));
            if (std::abs(candidateX - std::round(candidateX)) > 0.1) {
                fractionalSample = candidate;
                break;
            }
        }
        view.setPlayheadSample(fractionalSample, false);
        pumpQuick();
        if (std::abs(quick->playheadRootContentX() -
                     expected(timeline.tickForSample(fractionalSample))) > 0.2) {
            failures.append("fractional Quick playhead placement exceeded 0.2 pixels");
        }

        QString captureError;
        const QImage paused = checks::support::captureQuickBand(view, *ruler, &captureError);
        view.setPlayheadSample(fractionalSample, true);
        pumpQuick();
        const QImage playing = checks::support::captureQuickBand(view, *ruler, &captureError);
        if (paused.isNull() || playing.isNull()) {
            failures.append(
                QStringLiteral("playhead Quick framebuffer capture failed: %1").arg(captureError));
        } else if (paused == playing) {
            failures.append("paused and playing retained Quick playheads rendered identically");
        }

        checkAutomationHover(view, failures);
    }

    checkFollowScroll(view, timeline, failures);
    view.clearTimelineQuickHover(songview::TimelineQuickHoverOwner::Automation);
    view.setPlayheadSample(0, false);
    pumpQuick();
    if (!viewWasVisible)
        view.hide();
    view.setAttribute(Qt::WA_DontShowOnScreen, hadDontShowOnScreen);
    return failures;
}
