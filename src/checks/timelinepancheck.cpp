#include <QAbstractItemModel>
#include <QCoreApplication>
#include <QElapsedTimer>
#include <QQuickItem>
#include <QQuickWindow>

#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"

#include <algorithm>
#include <cstdio>
#include <tuple>

namespace {

bool dashClippingPreservesPhase()
{
    using namespace songview;
    using namespace songview::timeline_quick;
    constexpr auto layer = TimelineQuickLayer::AutomationSelection;
    const QRectF clip(0.0, 0.0, 100.0, 60.0);
    for (const qreal start : {-1000.25, -7.5, 0.0, 17.25}) {
        for (const qreal across : {-1.0, 0.25, 30.0, 59.75, 100.25}) {
            TimelineQuickScene reference;
            TimelineQuickScene bounded;
            // The former full walk is a small pixel-geometry oracle. Fractional
            // origins and edge crossings catch a pattern shifted by clipping.
            for (qreal at = start; at < 200.0; at += 5.75) {
                addHorizontalLine(reference.layer(layer), at, std::min(at + 4.5, 200.0), across,
                                  1.0, Qt::red, clip);
                addVerticalLine(reference.layer(layer), across, at, std::min(at + 4.5, 200.0), 1.0,
                                Qt::red, clip);
            }
            addDashedHorizontal(bounded.layer(layer), start, 200.0, across, 1.0, 4.5, 1.25, Qt::red,
                                clip);
            addDashedVertical(bounded.layer(layer), across, start, 200.0, 1.0, 4.5, 1.25, Qt::red,
                              clip);
            const auto orderedRects = [layer](TimelineQuickScene &scene) {
                std::vector<QRectF> result;
                for (const auto &primitive : scene.layer(layer).rects)
                    result.push_back(primitive.rect);
                std::sort(result.begin(), result.end(), [](const QRectF &a, const QRectF &b) {
                    return std::tuple(a.x(), a.y(), a.width(), a.height()) <
                           std::tuple(b.x(), b.y(), b.width(), b.height());
                });
                return result;
            };
            if (orderedRects(reference) != orderedRects(bounded))
                return false;
        }
    }
    return true;
}

} // namespace

int runTimelinePanCheck(const QString &projectRoot, const QString &songLabel)
{
    QString error;
    auto song = checks::LoadedSong::load(projectRoot, songLabel, error);
    auto rig = checks::SongViewRig::create(std::move(song), 48000.0, error);
    if (!rig) {
        std::fprintf(stderr, "timelinepancheck: %s\n", qUtf8Printable(error));
        return 1;
    }
    auto &view = rig->view();
    view.resize(1280, 800);
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    view.setEditorTimeZoom(640.0);
    view.show();
    auto *quick = view.quickView();
    checks::support::pumpQuick();
    if (checks::support::captureQuickBand(view, quick->geometry(), &error).isNull()) {
        std::fprintf(stderr, "timelinepancheck: %s\n", qUtf8Printable(error));
        return 1;
    }
    const auto render = [&] {
        QCoreApplication::sendPostedEvents();
        QCoreApplication::processEvents();
        return quick->quickWindow()->grabWindow();
    };
    (void)render();
    (void)render();
    int failures = 0;
    const auto check = [&](bool passed, const char *message) {
        if (!passed) {
            std::fprintf(stderr, "timelinepancheck: FAIL %s\n", message);
            ++failures;
        }
    };
    check(dashClippingPreservesPhase(), "viewport clipping changed visible dash geometry");
    check(view.isVisible() && quick->quickWindow()->isExposed(), "pan window is not exposed");
    auto *input = quick->rootObject()->findChild<songview::TimelineInputItem *>(
        QStringLiteral("timelineRollInput"));
    auto *scene = quick->findChild<songview::TimelineQuickScene *>();
    if (!input || !scene)
        return 1;
    // Stationary gutter labels must survive camera updates in the real QML scene.
    int removed = 0;
    int inserted = 0;
    QObject observer;
    for (auto *model : {scene->automationTextModel(), scene->voiceChangesGutterTextModel()}) {
        check(model->rowCount() > 0, "pan probe has no gutter labels");
        QObject::connect(
            model, &QAbstractItemModel::rowsRemoved, &observer,
            [&](const QModelIndex &, int first, int last) { removed += last - first + 1; });
        QObject::connect(
            model, &QAbstractItemModel::rowsInserted, &observer,
            [&](const QModelIndex &, int first, int last) { inserted += last - first + 1; });
    }
    const auto pan = [&] {
        const double before = view.camera().scrollX();
        checks::events::sendWheel(*input, QPointF(100, 100), QPoint(-8, 0), QPoint(), Qt::NoButton,
                                  Qt::NoModifier, Qt::NoScrollPhase, false);
        check(view.camera().scrollX() == before + 8.0, "wheel did not pan the real camera");
        (void)render();
    };
    for (int i = 0; i < 8; ++i)
        pan();
    check(removed == 0 && inserted == 0, "panning destroys and recreates stationary QML labels");

    // Stress the offscreen extent, not the number of visible dashes. A long
    // selection must cost about the same to pan as a viewport-sized selection.
    const auto selectedPanTime = [&](uint64_t endTick) {
        view.selectionModel().setTimeSelection(
            {0,
             endTick,
             songview::EditorSelectionModel::TimeSelection::Lanes,
             {{view.selectionModel().primaryTrack(), 7}},
             true});
        (void)render();
        QElapsedTimer timer;
        timer.start();
        pan();
        return timer.elapsed();
    };
    const auto shortTime = selectedPanTime(4 * rig->timeline().ticksPerBeat);
    const auto longTime = selectedPanTime(65536ULL * rig->timeline().ticksPerBeat);
    std::fprintf(stderr, "timelinepancheck: short=%lldms long=%lldms removed=%d inserted=%d\n",
                 shortTime, longTime, removed, inserted);
    check(longTime < std::max<qint64>(100, shortTime * 8),
          "pan time grows with the offscreen selection extent");
    view.close();
    std::fprintf(stderr, "timelinepancheck: %s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
