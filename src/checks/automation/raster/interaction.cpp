#include "rasterfixture.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <limits>
#include <vector>

#include <QAbstractItemModel>
#include <QByteArray>
#include <QColor>
#include <QCursor>
#include <QDeadlineTimer>
#include <QImage>
#include <QQuickItem>
#include <QString>
#include <QUndoStack>
#include <QtGlobal>

#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/nodelane/hover.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"

namespace {

enum class AdapterKind { Tempo, Cc };

struct HoverCase {
    AdapterKind kind = AdapterKind::Tempo;
    const char *name = "";
};

struct PreparedLane {
    LaneHandle handle;
    QRect body;
    QPointF insertionPos;
    QPointF nodePos;
    uint64_t insertionTick = 0;
    qreal insertionX = 0;
    qreal heldY = 0;
    qreal nodeX = 0;
    qreal nodeY = 0;
};

struct HoverObservation {
    songview::TimelineQuickLayerData layer;
    QImage framebuffer;
    int textRows = 0;
    bool chromeVisible = false;
    bool framebufferReady = false;
};

struct DocumentSnapshot {
    QByteArray smf;
    uint64_t revision = 0;
    int undoIndex = 0;
};

constexpr std::array kHoverCases{
    HoverCase{AdapterKind::Tempo, "Tempo"},
    HoverCase{AdapterKind::Cc, "CC"},
};
constexpr uint64_t kHeldTick = 0;
constexpr uint64_t kNodeTick = 144;
constexpr uint64_t kFixtureTick = 96;
constexpr double kHeldBodyFraction = 0.25;
constexpr double kNodeBodyFraction = 0.75;
constexpr double kCursorBodyFraction = 0.50;

void require(bool condition, const QString &message, int &failures)
{
    if (condition)
        return;
    std::fprintf(stderr, "automation-raster[interaction]: %s\n", qUtf8Printable(message));
    ++failures;
}

DocumentSnapshot snapshot(SongDocument &document)
{
    return {document.smf().write(), document.revision(), document.undoStack()->index()};
}

bool isUnchanged(const DocumentSnapshot &before, const DocumentSnapshot &after)
{
    return before.smf == after.smf && before.revision == after.revision &&
           before.undoIndex == after.undoIndex;
}

uint32_t tempoUsForBpm(int bpm)
{
    return CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(bpm);
}

int valueAtBodyFraction(int minimum, int maximum, double fractionFromBottom)
{
    return minimum + int(std::lround(double(maximum - minimum) * fractionFromBottom));
}

qreal valueY(const QRect &body, const AutomationGeometry &geometry, int minimum, int maximum,
             int value)
{
    return AutomationProjection::valueY(body, geometry, minimum, maximum, value);
}

void leaveCanvas(AutomationRasterFixture &fixture)
{
    fixture.automationPointerLeave();
    fixture.pump();
}

HoverObservation observeHover(AutomationRasterFixture &fixture)
{
    HoverObservation observation;
    QString captureError;
    observation.framebuffer = fixture.renderAutomationViewport(&captureError);
    observation.framebufferReady = captureError.isEmpty() && !observation.framebuffer.isNull();
    observation.layer = fixture.quickScene().layer(songview::TimelineQuickLayer::AutomationHover);
    const QAbstractItemModel *const model = fixture.quickScene().automationHoverTextModel();
    observation.textRows = model->rowCount();
    auto *quickHost = fixture.view().findChild<songview::TimelineQuickView *>(
        QStringLiteral("timelineQuickCanvas"));
    const QQuickItem *const root = quickHost ? quickHost->rootObject() : nullptr;
    const QQuickItem *const chrome =
        root ? root->findChild<QQuickItem *>(QStringLiteral("timelineQuickAutomationHoverChrome"))
             : nullptr;
    observation.chromeVisible = chrome && chrome->isVisible();
    return observation;
}

bool hasFilledNodeAt(const songview::TimelineQuickLayerData &layer, const QPointF &center)
{
    const qreal tolerance = layout::singlePixel();
    const auto nearCenter = [&](const QPointF &point) {
        const QPointF delta = point - center;
        return delta.x() * delta.x() + delta.y() * delta.y() <= tolerance * tolerance;
    };
    return std::any_of(layer.triangles.cbegin(), layer.triangles.cend(),
                       [&](const songview::TimelineQuickTriangle &triangle) {
                           return nearCenter(triangle.first) || nearCenter(triangle.second) ||
                                  nearCenter(triangle.third);
                       });
}

bool hasAnnulusPixelChanges(const QImage &before, const QImage &after, const QPointF &center,
                            qreal radius, qreal width)
{
    if (before.isNull() || after.isNull() || before.size() != after.size())
        return false;
    const qreal dpr = after.devicePixelRatio();
    if (dpr <= 0.0 || !qFuzzyCompare(before.devicePixelRatio(), dpr))
        return false;
    const qreal tolerance = 2 * layout::singlePixel();
    const qreal inner = std::max<qreal>(0.0, radius - width / 2.0 - tolerance);
    const qreal outer = radius + width / 2.0 + tolerance;
    const qreal innerSquared = inner * inner;
    const qreal outerSquared = outer * outer;
    const int left = std::max(0, qFloor((center.x() - outer) * dpr));
    const int top = std::max(0, qFloor((center.y() - outer) * dpr));
    const int right = std::min(after.width() - 1, qCeil((center.x() + outer) * dpr));
    const int bottom = std::min(after.height() - 1, qCeil((center.y() + outer) * dpr));
    int changedPixels = 0;
    for (int y = top; y <= bottom; ++y) {
        for (int x = left; x <= right; ++x) {
            const QPointF delta((x + 0.5) / dpr - center.x(), (y + 0.5) / dpr - center.y());
            const qreal distanceSquared = delta.x() * delta.x() + delta.y() * delta.y();
            if (distanceSquared < innerSquared || distanceSquared > outerSquared)
                continue;
            const QColor oldPixel = before.pixelColor(x, y);
            const QColor newPixel = after.pixelColor(x, y);
            const int difference = std::abs(newPixel.alpha() - oldPixel.alpha()) +
                                   std::abs(newPixel.red() - oldPixel.red()) +
                                   std::abs(newPixel.green() - oldPixel.green()) +
                                   std::abs(newPixel.blue() - oldPixel.blue());
            if (newPixel.alpha() >= 32 && difference >= 32 && ++changedPixels == 2)
                return true;
        }
    }
    return false;
}

bool pixelChangedAt(const QImage &before, const QImage &after, const QPointF &point)
{
    if (before.isNull() || after.isNull() || before.size() != after.size())
        return false;
    const qreal dpr = after.devicePixelRatio();
    if (dpr <= 0.0 || !qFuzzyCompare(before.devicePixelRatio(), dpr))
        return false;
    const int x = std::clamp(qRound(point.x() * dpr), 0, after.width() - 1);
    const int y = std::clamp(qRound(point.y() * dpr), 0, after.height() - 1);
    const QColor oldPixel = before.pixelColor(x, y);
    const QColor newPixel = after.pixelColor(x, y);
    return std::abs(newPixel.alpha() - oldPixel.alpha()) +
               std::abs(newPixel.red() - oldPixel.red()) +
               std::abs(newPixel.green() - oldPixel.green()) +
               std::abs(newPixel.blue() - oldPixel.blue()) >=
           32;
}

bool pixelClearedAt(const QImage &idle, const QImage &cleared, const QPointF &point)
{
    if (idle.isNull() || cleared.isNull() || idle.size() != cleared.size())
        return false;
    const qreal dpr = cleared.devicePixelRatio();
    if (dpr <= 0.0 || !qFuzzyCompare(idle.devicePixelRatio(), dpr))
        return false;
    const int x = std::clamp(qRound(point.x() * dpr), 0, cleared.width() - 1);
    const int y = std::clamp(qRound(point.y() * dpr), 0, cleared.height() - 1);
    const QColor idlePixel = idle.pixelColor(x, y);
    const QColor clearedPixel = cleared.pixelColor(x, y);
    return std::abs(clearedPixel.alpha() - idlePixel.alpha()) <= 8 &&
           std::abs(clearedPixel.red() - idlePixel.red()) <= 8 &&
           std::abs(clearedPixel.green() - idlePixel.green()) <= 8 &&
           std::abs(clearedPixel.blue() - idlePixel.blue()) <= 8;
}

bool isClear(const HoverObservation &observation)
{
    return observation.framebufferReady && observation.layer.rects.empty() &&
           observation.layer.triangles.empty() && observation.textRows == 0 &&
           !observation.chromeVisible;
}

void setTempoPoints(AutomationRasterFixture &fixture, const std::vector<TempoPoint> &points)
{
    if (fixture.document().tempoPoints() == points)
        return;
    TempoEdit edit;
    edit.remove = fixture.document().tempoPoints();
    edit.add = points;
    fixture.document().applyTempoEdit(edit);
    fixture.documentChanged();
}

void setCcPoints(AutomationRasterFixture &fixture,
                 const std::vector<SongDocument::LanePointValue> &points)
{
    fixture.document().writeLanePoints(fixture.pan.track, fixture.pan.controller, 0,
                                       std::numeric_limits<uint64_t>::max(), points);
    fixture.documentChanged();
}

std::vector<SongDocument::LanePointValue> laneValues(const std::vector<DocLanePoint> &points)
{
    std::vector<SongDocument::LanePointValue> values;
    values.reserve(points.size());
    for (const DocLanePoint &point : points)
        values.push_back({point.tick, point.value});
    return values;
}

PreparedLane prepareLane(AutomationRasterFixture &fixture, const HoverCase &row)
{
    PreparedLane lane;
    const int minimum = row.kind == AdapterKind::Tempo ? CoreTimeDefaults::kMinTempoBpm : 0;
    const int maximum = row.kind == AdapterKind::Tempo ? CoreTimeDefaults::kMaxTempoBpm : 127;
    const int held = valueAtBodyFraction(minimum, maximum, kHeldBodyFraction);
    const int node = valueAtBodyFraction(minimum, maximum, kNodeBodyFraction);
    const int cursor = valueAtBodyFraction(minimum, maximum, kCursorBodyFraction);
    if (row.kind == AdapterKind::Tempo) {
        setTempoPoints(fixture,
                       {{kHeldTick, tempoUsForBpm(held)}, {kNodeTick, tempoUsForBpm(node)}});
        lane.handle = AutomationRasterFixture::kTempoHandle;
    } else {
        lane.handle = fixture.handleFor(fixture.pan);
        if (!lane.handle.valid())
            return lane;
        setCcPoints(fixture, {{kHeldTick, held}, {kNodeTick, node}});
    }
    const auto geometry = fixture.geometry();
    const qreal dpr = fixture.automationDpr();
    const auto projection = fixture.projection();
    lane.body = fixture.bodyFor(lane.handle);
    lane.insertionPos = {projection.displayX(kFixtureTick, dpr),
                         valueY(lane.body, geometry, minimum, maximum, cursor)};
    lane.heldY = valueY(lane.body, geometry, minimum, maximum, held);
    lane.nodeY = valueY(lane.body, geometry, minimum, maximum, node);
    NodeLaneHoverState insertionProbe(fixture.view().font());
    insertionProbe.hover.lane = lane.handle;
    insertionProbe.hover.pos = lane.insertionPos;
    lane.insertionTick = uint64_t(std::max(0.0, insertionProbe.insertionTick(projection, false)));
    lane.insertionX = projection.displayX(lane.insertionTick, dpr);
    lane.nodeX = projection.displayX(kNodeTick, dpr);
    lane.nodePos = {lane.nodeX, lane.nodeY};
    return lane;
}

void runHoverPixels(AutomationRasterFixture &fixture, const HoverCase &row, int &failures)
{
    const PreparedLane lane = prepareLane(fixture, row);
    if (!lane.handle.valid() || lane.body.isEmpty()) {
        require(false,
                QStringLiteral("%1 lane body is missing from the canvas stack")
                    .arg(QLatin1String(row.name)),
                failures);
        return;
    }
    require(lane.insertionTick != kHeldTick && lane.insertionTick != kNodeTick,
            QStringLiteral("%1 inter-node insertion landed on an existing node")
                .arg(QLatin1String(row.name)),
            failures);

    leaveCanvas(fixture);
    const HoverObservation idle = observeHover(fixture);
    const DocumentSnapshot before = snapshot(fixture.document());
    const auto unchanged = [&](const char *label) {
        require(isUnchanged(before, snapshot(fixture.document())),
                QStringLiteral("%1 %2 mutated SMF, revision, or undo")
                    .arg(QLatin1String(row.name))
                    .arg(QLatin1String(label)),
                failures);
    };
    require(idle.framebufferReady,
            QStringLiteral("%1 Quick automation framebuffer was unavailable")
                .arg(QLatin1String(row.name)),
            failures);

    const auto geometry = fixture.geometry();
    const QPointF insertionCenter =
        fixture.automationContentToViewport(QPointF(lane.insertionX, lane.heldY));
    const QPointF nodeCenter = fixture.automationContentToViewport(QPointF(lane.nodeX, lane.nodeY));
    const QPointF framebufferOffset(fixture.automationGutterInput().bounds().width(), 0.0);
    const QPointF insertionFramebufferCenter = insertionCenter + framebufferOffset;
    const QPointF nodeFramebufferCenter = nodeCenter + framebufferOffset;

    fixture.automationMouseMove(lane.insertionPos);
    fixture.pump();
    const HoverObservation insertion = observeHover(fixture);
    unchanged("insertion preview");
    require(insertion.framebufferReady && insertion.layer.revision > idle.layer.revision &&
                hasFilledNodeAt(insertion.layer, insertionCenter) &&
                pixelChangedAt(idle.framebuffer, insertion.framebuffer, insertionFramebufferCenter),
            QStringLiteral("%1 inter-node hover did not retain its Quick held-value ghost")
                .arg(QLatin1String(row.name)),
            failures);

    fixture.automationMouseMove(lane.insertionPos);
    fixture.pump();
    const HoverObservation repeated = observeHover(fixture);
    unchanged("repeat hover");
    require(insertion.framebufferReady && repeated.framebufferReady &&
                insertion.framebuffer == repeated.framebuffer,
            QStringLiteral("%1 repeat hover at the same coordinate changed its framebuffer")
                .arg(QLatin1String(row.name)),
            failures);

    fixture.automationMouseMove(lane.nodePos);
    const auto awaitHoverRevision = [&](quint64 priorRevision) {
        QDeadlineTimer timeout{1000};
        HoverObservation observation = observeHover(fixture);
        while ((!observation.framebufferReady || observation.layer.revision <= priorRevision) &&
               !timeout.hasExpired()) {
            fixture.pump();
            observation = observeHover(fixture);
        }
        return observation;
    };
    const HoverObservation nodeHover = awaitHoverRevision(insertion.layer.revision);
    unchanged("node hover");
    require(nodeHover.framebufferReady && nodeHover.layer.revision > insertion.layer.revision &&
                !nodeHover.layer.triangles.empty() &&
                hasAnnulusPixelChanges(insertion.framebuffer, nodeHover.framebuffer,
                                       nodeFramebufferCenter, nodelane::hoverRingRadius(geometry),
                                       2 * layout::singlePixel()),
            QStringLiteral("%1 existing-node hover did not retain its Quick node ring")
                .arg(QLatin1String(row.name)),
            failures);

    leaveCanvas(fixture);
    const auto awaitClear = [&] {
        QDeadlineTimer timeout{1000};
        HoverObservation observation = observeHover(fixture);
        while (!isClear(observation) && !timeout.hasExpired()) {
            fixture.pump();
            observation = observeHover(fixture);
        }
        return observation;
    };
    const HoverObservation transitioned = awaitClear();
    unchanged("lane transition");
    leaveCanvas(fixture);
    const HoverObservation left = awaitClear();
    unchanged("leave");
    require(
        isClear(transitioned) && isClear(left) &&
            pixelClearedAt(idle.framebuffer, nodeHover.framebuffer, insertionFramebufferCenter) &&
            pixelClearedAt(idle.framebuffer, transitioned.framebuffer,
                           insertionFramebufferCenter) &&
            pixelClearedAt(idle.framebuffer, left.framebuffer, insertionFramebufferCenter),
        QStringLiteral("%1 lane transition or leave retained dirty Quick hover pixels")
            .arg(QLatin1String(row.name)),
        failures);
}

qreal voiceX(const AutomationRasterFixture &fixture, uint64_t tick)
{
    return fixture.view().camera().displayX(double(tick), 0.0,
                                            fixture.voiceInput().devicePixelRatio());
}

QPointF voicePoint(const AutomationRasterFixture &fixture, uint64_t tick)
{
    return {voiceX(fixture, tick), fixture.voiceInput().bounds().center().y()};
}

void seedVoice(AutomationRasterFixture &fixture,
               const std::vector<SongDocument::LanePointValue> &points)
{
    fixture.document().writeLanePoints(0, DOC_CC_VOICE, 0, std::numeric_limits<uint64_t>::max(),
                                       points);
    fixture.documentChanged();
    fixture.pump();
}

void activateVoiceDrag(AutomationRasterFixture &fixture, const QPointF &source,
                       const QPointF &destination)
{
    fixture.voiceMousePress(source);
    fixture.voiceMouseMove(destination);
    fixture.pump();
}

void runVoicePreviewPixels(AutomationRasterFixture &fixture, int &failures)
{
    fixture.canvas().cancelInteraction();
    fixture.pump();
    seedVoice(fixture, {{24, 5}, {48, 6}});
    const QPointF source = voicePoint(fixture, 24);
    const QPointF target = voicePoint(fixture, 72);
    const DocumentSnapshot before = snapshot(fixture.document());
    QString idleCaptureError;
    const QImage idleVoice = fixture.renderVoiceChanges(&idleCaptureError);
    activateVoiceDrag(fixture, source, target);
    QString previewCaptureError;
    const QImage previewVoice = fixture.renderVoiceChanges(&previewCaptureError);
    require(idleCaptureError.isEmpty() && previewCaptureError.isEmpty() &&
                isUnchanged(before, snapshot(fixture.document())) &&
                fixture.view().userGestureActive() &&
                fixture.voiceInput().cursor().shape() == Qt::SizeHorCursor && !idleVoice.isNull() &&
                idleVoice.size() == previewVoice.size() && idleVoice != previewVoice,
            QStringLiteral("Voice crossing preview capture failed (%1; %2)")
                .arg(idleCaptureError, previewCaptureError),
            failures);
    fixture.voiceMouseRelease(target);
    fixture.pump();
}

} // namespace

int runAutomationInteractionRasterCheck(const QString &project, const QString &song)
{
    QString error;
    auto fixture = AutomationRasterFixture::create(project, song, error);
    if (!fixture) {
        std::fprintf(stderr, "automation-raster[interaction]: %s\n", qUtf8Printable(error));
        return 1;
    }

    auto failures = 0;
    fixture->setAutomationZoom(96.0);
    fixture->setAutomationScroll(0.0);
    fixture->setPersistentPencil(false);
    fixture->pump();
    const bool tempoExpanded = fixture->expandTempo();
    require(tempoExpanded, QStringLiteral("Tempo header did not expose the expanded body"),
            failures);

    const auto initialTempo = fixture->document().tempoPoints();
    const auto initialPan =
        fixture->document().lanePoints(fixture->pan.track, fixture->pan.controller);
    for (const HoverCase &row : kHoverCases) {
        if (row.kind == AdapterKind::Tempo && !tempoExpanded)
            continue;
        runHoverPixels(*fixture, row, failures);
        setTempoPoints(*fixture, initialTempo);
        setCcPoints(*fixture, laneValues(initialPan));
    }

    runVoicePreviewPixels(*fixture, failures);
    return failures == 0 ? 0 : 1;
}
