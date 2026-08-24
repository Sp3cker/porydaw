#include "checks/support/eventsynth.h"
#include "checks/support/songfixture.h"

#include "core/songdocument.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/drawerpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/playheadoverlay.h"
#include "ui/songview.h"
#include "ui/theme/themeruntime.h"
#include "ui/timelinesurface.h"

#include <QCoreApplication>
#include <QImage>
#include <QPainter>
#include <QPixmap>
#include <QWidget>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <optional>
#include <utility>
#include <vector>

namespace {

class ProbeSurface final : public songview::TimelineSurface
{
  public:
    explicit ProbeSurface(QWidget *parent) : TimelineSurface(parent) {}

  protected:
    void paintContent(QPainter &painter) override { painter.fillRect(rect(), Qt::transparent); }
};

bool hasColorNear(const QImage &image, const QRect &bounds, const QColor &expected, int tolerance)
{
    const QRect clipped = bounds.intersected(image.rect());
    for (int y = clipped.top(); y <= clipped.bottom(); ++y) {
        for (int x = clipped.left(); x <= clipped.right(); ++x) {
            const QColor actual(image.pixel(x, y));
            if (std::abs(actual.red() - expected.red()) <= tolerance &&
                std::abs(actual.green() - expected.green()) <= tolerance &&
                std::abs(actual.blue() - expected.blue()) <= tolerance)
                return true;
        }
    }
    return false;
}

} // namespace

int runRenderingPlayheadCheck(const QString &scratchProject, const QString &songLabel,
                              const QString &screenshotPath)
{
    int failures = 0;
    const auto check = [&failures, &songLabel](bool condition, const char *message) {
        if (!condition) {
            std::fprintf(stderr, "rendering-playhead: FAIL %s: %s\n", qUtf8Printable(songLabel),
                         message);
            ++failures;
        }
    };

    if (songLabel.isEmpty()) {
        std::fprintf(stderr, "rendering-playhead: song label is empty\n");
        return 1;
    }
    QString projectError;
    const auto fixtureSong = checks::LoadedSong::load(scratchProject, songLabel, projectError);
    if (!fixtureSong) {
        std::fprintf(stderr, "rendering-playhead: could not load song %s: %s\n",
                     qUtf8Printable(songLabel), qUtf8Printable(projectError));
        return 1;
    }
    SongDocument &fixtureDocument = fixtureSong->document();
    auto fixtureTimeline = fixtureDocument.buildTimeline(48000.0);
    if (!fixtureTimeline) {
        std::fprintf(stderr, "rendering-playhead: could not build timeline for song %s\n",
                     qUtf8Printable(songLabel));
        return 1;
    }
    check(fixtureDocument.engineTrackCount() > 0, "fixture song did not produce an engine track");
    if (failures)
        return 1;
    check(fixtureTimeline->ticksPerBeat > 0 && fixtureTimeline->lengthTicks > 0,
          "fixture song did not produce a playable timeline");
    if (failures)
        return 1;

    auto owner = QWidget{};
    owner.resize(240, 180);
    auto ruler = QWidget(&owner);
    auto roll = ProbeSurface(&owner);
    auto lanes = ProbeSurface(&owner);
    auto strip = ProbeSurface(&owner);
    ruler.setGeometry(16, 0, 200, 20);
    roll.setGeometry(16, 20, 200, 60);
    lanes.setGeometry(16, 100, 200, 60);
    strip.setGeometry(16, 162, 200, 18);
    owner.show();
    QCoreApplication::processEvents();

    const std::vector<songview::TimelineBand> bands{
        {ruler, 16},
        {roll, 16},
        {lanes, 16},
        {strip, 16},
    };
    auto overlay = songview::PlayheadOverlay(&owner, bands);
    QCoreApplication::processEvents();

    check(overlay.geometry() == owner.rect(), "overlay does not cover its owner");

    const songview::TimelineSurfaceDiagnostics rollBefore = roll.diagnostics();
    const songview::TimelineSurfaceDiagnostics lanesBefore = lanes.diagnostics();
    for (int tick = 0; tick < 120; ++tick)
        overlay.setPlayhead(qreal(tick) + 0.25, true, true);
    QCoreApplication::processEvents();

    check(roll.diagnostics() == rollBefore, "steady ticks invalidated or rebuilt roll content");
    check(lanes.diagnostics() == lanesBefore, "steady ticks invalidated or rebuilt lane content");
    check(roll.diagnostics().contentInvalidationCount == rollBefore.contentInvalidationCount &&
              lanes.diagnostics().contentInvalidationCount == lanesBefore.contentInvalidationCount,
          "steady ticks crossed a content invalidation boundary");

    roll.invalidateContent();
    QCoreApplication::processEvents();
    check(roll.diagnostics().contentInvalidationCount == rollBefore.contentInvalidationCount + 1,
          "explicit roll invalidation did not advance its diagnostic");
    check(lanes.diagnostics().contentInvalidationCount == lanesBefore.contentInvalidationCount,
          "roll invalidation crossed into the lane boundary");

    auto document = SongDocument{};
    auto timeline = MidiTimeline{};
    timeline.ticksPerBeat = 24;
    auto songView = SongView{};
    songView.setDocument(&document);
    songView.setSong(&timeline, nullptr);
    auto velocity = VelocityArea(songView, &owner);
    velocity.resize(220, 120);
    velocity.songChanged();
    DrawerPageLiveState live;
    live.documentRevision = document.revision();
    live.timeZoom = 48.0;
    velocity.refreshLiveState(live);
    velocity.show();
    QCoreApplication::processEvents();
    const uint64_t revisionBeforePan = document.revision();
    const int undoBeforePan = document.undoStack()->count();
    const QPointF panPoint(24.0, 48.0);
    checks::events::sendMouse(velocity, QEvent::MouseButtonPress, panPoint, Qt::MiddleButton,
                              Qt::MiddleButton, Qt::NoModifier);
    checks::events::sendMouse(velocity, QEvent::MouseButtonRelease, panPoint, Qt::MiddleButton,
                              Qt::NoButton, Qt::NoModifier);
    check(document.revision() == revisionBeforePan &&
              document.undoStack()->count() == undoBeforePan,
          "concrete velocity owner should leave the document untouched while panning");

    checks::events::sendMouse(velocity, QEvent::MouseButtonPress, panPoint, Qt::MiddleButton,
                              Qt::MiddleButton, Qt::NoModifier);
    velocity.cancelInteraction();
    check(document.revision() == revisionBeforePan &&
              document.undoStack()->count() == undoBeforePan,
          "concrete velocity owner should cancel panning without document changes");
    std::optional<DocNote> fixtureNote;
    for (int track = 0; track < fixtureTimeline->usedTrackCount; ++track) {
        const auto notes = fixtureDocument.notesForTrack(track);
        const auto note = std::find_if(notes.begin(), notes.end(), [](const DocNote &candidate) {
            return candidate.noteId.isAssigned();
        });
        if (note != notes.end()) {
            fixtureNote = *note;
            break;
        }
    }
    bool timelineHasFixtureNote = false;
    if (fixtureNote) {
        timelineHasFixtureNote =
            std::any_of(fixtureTimeline->events.cbegin(), fixtureTimeline->events.cend(),
                        [noteId = fixtureNote->noteId](const TimelineEvent &event) {
                            return event.type == 0x9 && event.noteId == noteId;
                        });
    }
    check(!fixtureTimeline->events.empty() && fixtureNote.has_value() && timelineHasFixtureNote,
          "fixture song should contain real timeline and note data");
    if (failures)
        return 1;

    owner.hide();
    SongView fixtureView;
    fixtureView.resize(960, 720);
    fixtureView.setDocument(&fixtureDocument);
    fixtureView.setSong(fixtureTimeline.get(), nullptr);
    fixtureView.setDrawerActivePage(EditorDrawerPage::Automations);
    fixtureView.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    fixtureView.setDrawerSectionHeight(EditorDrawerPage::Automations, 320);
    fixtureView.setFollowPlayhead(false);
    fixtureView.setEditorTimeZoom(96.0);
    fixtureView.show();
    QCoreApplication::processEvents();

    auto *fixtureDrawer = fixtureView.editorDrawer();
    auto *fixturePage = fixtureDrawer ? fixtureDrawer->automationPage() : nullptr;
    auto *fixtureBand = fixturePage ? fixturePage->canvas() : nullptr;
    songview::PlayheadOverlay *fixtureOverlay = nullptr;
    for (QWidget *widget : fixtureView.findChildren<QWidget *>()) {
        if (auto *candidate = dynamic_cast<songview::PlayheadOverlay *>(widget)) {
            fixtureOverlay = candidate;
            break;
        }
    }
    check(fixtureDrawer && fixturePage && fixtureBand,
          "fixture SongView did not expose its automation drawer");
    check(fixtureBand && fixtureBand->isVisibleTo(&fixtureView) && fixtureBand->width() > 0 &&
              fixtureBand->height() > 0,
          "fixture automation band is not visible");
    check(fixtureOverlay != nullptr, "fixture SongView did not expose its playhead overlay");

    if (fixtureBand) {
        const auto smfBeforePaint = fixtureDocument.smf().write();
        const uint64_t revisionBeforePaint = fixtureDocument.revision();
        const int undoBeforePaint = fixtureDocument.undoStack()->index();
        const uint64_t firstSample = fixtureTimeline->sampleForTick(0);
        const uint64_t secondSample = fixtureTimeline->sampleForTick(fixtureTimeline->ticksPerBeat);
        fixtureView.setPlayheadSample(firstSample, false);
        QCoreApplication::processEvents();
        const QPixmap warmBand = fixtureBand->grab();
        QCoreApplication::processEvents();
        const songview::TimelineSurfaceDiagnostics beforePlayhead = fixtureBand->diagnostics();
        check(!warmBand.isNull() && beforePlayhead.contentPaintCount > 0 &&
                  beforePlayhead.contentPaintPixelCount > 0,
              "fixture automation band did not warm its content cache");

        for (const uint64_t sample : {firstSample, secondSample, firstSample, secondSample}) {
            fixtureView.setPlayheadSample(sample, true);
            QCoreApplication::processEvents();
        }
        const songview::TimelineSurfaceDiagnostics afterPlayhead = fixtureBand->diagnostics();
        check(afterPlayhead == beforePlayhead,
              "fixture playhead updates rebuilt cached automation content");
        check(fixtureBand->grab().toImage() == warmBand.toImage(),
              "fixture playhead updates changed cached automation pixels");
        check(fixtureView.playheadTick() == fixtureTimeline->tickForSample(secondSample),
              "fixture playhead did not reach its final timeline position");
        DrawerPageLiveState live;
        live.documentRevision = fixtureDocument.revision();
        live.timeZoom = 96.0;
        live.editCursorTick = 0;
        fixturePage->refreshLiveState(live);
        QCoreApplication::processEvents();
        const QImage cursorAtZero = fixtureBand->grab().toImage();
        live.editCursorTick = fixtureTimeline->ticksPerBeat;
        fixturePage->refreshLiveState(live);
        QCoreApplication::processEvents();
        const QImage cursorAtBeat = fixtureBand->grab().toImage();
        const songview::TimelineSurfaceDiagnostics afterCursor = fixtureBand->diagnostics();
        check(cursorAtZero != cursorAtBeat,
              "moving the edit cursor did not change cached automation content");
        check(afterCursor.contentPaintCount > afterPlayhead.contentPaintCount,
              "edit cursor move did not repaint automation content");
        const qreal cursorX =
            (double(fixtureBand->plotOrigin()) + 96.0) * fixtureBand->devicePixelRatioF();
        check(hasColorNear(cursorAtBeat,
                           QRect(int(cursorX) - 2, 4, 5, std::max(8, fixtureBand->height() / 4)),
                           themes::color(themes::Role::song_view_edit_cursor), 16),
              "automation canvas did not paint the edit cursor");
        check(fixtureDocument.smf().write() == smfBeforePaint &&
                  fixtureDocument.revision() == revisionBeforePaint &&
                  fixtureDocument.undoStack()->index() == undoBeforePaint,
              "automation canvas paint changed SMF, revision, or undo");
    }
    if (fixtureOverlay)
        check(fixtureOverlay->isVisible(), "fixture playhead overlay is not presenting");
    const QPixmap fixtureFrame = fixtureView.grab();
    check(!fixtureFrame.isNull() && fixtureFrame.width() > 0 && fixtureFrame.height() > 0,
          "fixture SongView did not produce a final hosted frame");

    if (!screenshotPath.isEmpty())
        check(fixtureFrame.save(screenshotPath), "could not save screenshot");

    if (failures) {
        std::fprintf(stderr, "rendering-playhead: %d failure(s)\n", failures);
        return 1;
    }
    std::fprintf(stdout, "rendering-playhead: PASS %s: upstream surface overlay ticks\n",
                 qUtf8Printable(songLabel));
    return 0;
}
