#include "core/songdocument.h"
#include "ui/playheadoverlay.h"
#include "ui/timelinesurface.h"
#include "ui/velocityarea.h"
#include "ui/editordrawer.h"
#include "ui/songview.h"

#include <QCoreApplication>
#include <QFileInfo>
#include <QPainter>
#include <QMouseEvent>
#include <QPixmap>
#include <QWidget>
#include <cstdio>
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


} // namespace

int runRenderingPlayheadCheck(const QString &scratchProject, const QString &songLabel,
                              const QString &screenshotPath)
{
    int failures = 0;
    const auto check = [&failures, &songLabel](bool condition, const char *message) {
        if (!condition) {
            std::fprintf(stderr, "rendering-playhead: FAIL %s: %s\n",
                         qUtf8Printable(songLabel), message);
            ++failures;
        }
    };

    check(QFileInfo(scratchProject).isDir(), "scratch project does not exist");
    check(!songLabel.isEmpty(), "song label is empty");
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

    check(roll.diagnostics() == rollBefore,
          "steady ticks invalidated or rebuilt roll content");
    check(lanes.diagnostics() == lanesBefore,
          "steady ticks invalidated or rebuilt lane content");
    check(roll.diagnostics().contentInvalidationCount ==
              rollBefore.contentInvalidationCount &&
              lanes.diagnostics().contentInvalidationCount ==
                  lanesBefore.contentInvalidationCount,
          "steady ticks crossed a content invalidation boundary");

    roll.invalidateContent();
    QCoreApplication::processEvents();
    check(roll.diagnostics().contentInvalidationCount ==
              rollBefore.contentInvalidationCount + 1,
          "explicit roll invalidation did not advance its diagnostic");
    check(lanes.diagnostics().contentInvalidationCount ==
              lanesBefore.contentInvalidationCount,
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
    EditorPageLiveState live;
    live.documentRevision = document.revision();
    live.timeZoom = 48.0;
    velocity.refreshLiveState(live);
    velocity.show();
    QCoreApplication::processEvents();
    const uint64_t revisionBeforePan = document.revision();
    const int undoBeforePan = document.undoStack()->count();
    const QPointF panPoint(24.0, 48.0);
    QMouseEvent commitPress(QEvent::MouseButtonPress, panPoint, Qt::MiddleButton,
                            Qt::MiddleButton, Qt::NoModifier);
    QCoreApplication::sendEvent(&velocity, &commitPress);
    QMouseEvent commitRelease(QEvent::MouseButtonRelease, panPoint, Qt::MiddleButton,
                              Qt::NoButton, Qt::NoModifier);
    QCoreApplication::sendEvent(&velocity, &commitRelease);
    check(document.revision() == revisionBeforePan
              && document.undoStack()->count() == undoBeforePan,
          "concrete velocity owner should leave the document untouched while panning");

    QMouseEvent cancelPress(QEvent::MouseButtonPress, panPoint, Qt::MiddleButton,
                            Qt::MiddleButton, Qt::NoModifier);
    QCoreApplication::sendEvent(&velocity, &cancelPress);
    velocity.cancelInteraction();
    check(document.revision() == revisionBeforePan
              && document.undoStack()->count() == undoBeforePan,
          "concrete velocity owner should cancel panning without document changes");

    if (!screenshotPath.isEmpty())
        check(owner.grab().save(screenshotPath), "could not save screenshot");

    if (failures) {
        std::fprintf(stderr, "rendering-playhead: %d failure(s)\n", failures);
        return 1;
    }
    std::fprintf(stdout, "rendering-playhead: PASS %s: upstream surface overlay ticks\n",
                 qUtf8Printable(songLabel));
    return 0;
}
