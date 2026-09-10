#include "checks/automation/hover/hoverfixture.h"

#include <QtTest>

#include <algorithm>
#include <cmath>
#include <limits>
#include <utility>
#include <vector>

#include <QAbstractItemModel>
#include <QColor>
#include <QCoreApplication>
#include <QEnterEvent>
#include <QQuickItem>
#include <QQuickWindow>

#include "checks/support/eventsynth.h"

#include "core/smf.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/nodelane/hover.h"
#include "ui/editordrawer/tempolane.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/theme/themeruntime.h"

namespace automation_hover {
namespace {

constexpr uint8_t kPanController = 10;
constexpr uint8_t kLfoController = 21;
constexpr uint64_t kHeldTick = 0;
constexpr uint64_t kProbeTick = 96;
constexpr uint64_t kNodeTick = 144;
constexpr uint64_t kEndTick = 192;

SmfEvent programChange(uint64_t tick, uint8_t program)
{
    SmfEvent event;
    event.status = 0xC0;
    event.tick = tick;
    event.data0 = program;
    return event;
}

SmfFile hoverSmf()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    SmfTrack track;
    track.events = {programChange(0, 0)};
    track.endTick = kEndTick;
    smf.tracks.push_back(std::move(track));
    return smf;
}

int valueAtFraction(int minimum, int maximum, double fractionFromBottom)
{
    return minimum + int(std::lround(double(maximum - minimum) * fractionFromBottom));
}

// Stable production row identities for the fixture's two lane kinds; the
// parameter index itself comes only from AutomationCanvas::parameterIndex.
EditorAutomationRowId laneRow(LaneKind kind)
{
    if (kind == LaneKind::Tempo)
        return {EditorAutomationRowKind::Tempo, 0, 0};
    return {EditorAutomationRowKind::ControlChange, 0, kPanController};
}

songview::TimelineInputItem *input(const Fixture &fixture, const QString &name)
{
    QQuickItem *const root = fixture.rig ? fixture.rig->quickRoot() : nullptr;
    return root ? root->findChild<songview::TimelineInputItem *>(name) : nullptr;
}

// QObject::findChild misses visually reparented Quick delegates, so the
// selector label seam walks the visual childItems tree instead of object
// ownership.
QQuickItem *visualDescendant(QQuickItem *root, const QString &objectName)
{
    if (!root || root->objectName() == objectName)
        return root;
    for (QQuickItem *const child : root->childItems())
        if (QQuickItem *const found = visualDescendant(child, objectName))
            return found;
    return nullptr;
}

bool hasAnnulusAt(const songview::TimelineQuickLayerData &layer, const QPointF &center,
                  qreal radius, qreal width)
{
    const qreal inner = std::max<qreal>(0.0, radius - width / 2.0);
    const qreal outer = radius + width / 2.0;
    const qreal tolerance = layout::singlePixel();
    const auto nearRadius = [&center, tolerance](const QPointF &point, qreal expected) {
        return std::abs(std::hypot(point.x() - center.x(), point.y() - center.y()) - expected) <=
               tolerance;
    };
    bool left = false;
    bool right = false;
    bool top = false;
    bool bottom = false;
    bool hasRingTriangle = false;
    const auto markOuterQuadrant = [&center, &left, &right, &top, &bottom](const QPointF &point) {
        const QPointF delta = point - center;
        if (std::abs(delta.x()) >= std::abs(delta.y())) {
            if (delta.x() < 0.0)
                left = true;
            else
                right = true;
        } else if (delta.y() < 0.0) {
            top = true;
        } else {
            bottom = true;
        }
    };
    for (const songview::TimelineQuickTriangle &triangle : layer.triangles) {
        const int outerVertices = int(nearRadius(triangle.first, outer)) +
                                  int(nearRadius(triangle.second, outer)) +
                                  int(nearRadius(triangle.third, outer));
        const int innerVertices = int(nearRadius(triangle.first, inner)) +
                                  int(nearRadius(triangle.second, inner)) +
                                  int(nearRadius(triangle.third, inner));
        hasRingTriangle = hasRingTriangle || (outerVertices >= 2 && innerVertices >= 1);
        if (nearRadius(triangle.first, outer))
            markOuterQuadrant(triangle.first);
        if (nearRadius(triangle.second, outer))
            markOuterQuadrant(triangle.second);
        if (nearRadius(triangle.third, outer))
            markOuterQuadrant(triangle.third);
    }
    return hasRingTriangle && left && right && top && bottom;
}

QString expectedValueText(Fixture &fixture, const PreparedLane &lane, int value)
{
    if (lane.kind == LaneKind::Tempo)
        return TempoLane(fixture.document).valueText(value);
    return CCLaneAdapter(fixture.document, 0, kPanController).valueText(value);
}

} // namespace

bool create(Fixture &fixture, QString &error)
{
    error.clear();
    if (!fixture.directory.isValid()) {
        error = QStringLiteral("could not create Automation hover fixture directory");
        return false;
    }
    SongInfo song;
    song.label = QStringLiteral("automation-hover");
    song.midPath = fixture.directory.filePath(QStringLiteral("automation-hover.mid"));
    song.hasMid = true;
    if (!hoverSmf().writeFile(song.midPath, &error) || !fixture.document.load(song, &error)) {
        error = QStringLiteral("could not load Automation hover fixture: %1").arg(error);
        return false;
    }
    fixture.document.writeLanePoints(0, kPanController, 0, std::numeric_limits<uint64_t>::max(),
                                     {{kHeldTick, 32}, {kNodeTick, 96}});
    fixture.document.writeLanePoints(0, kLfoController, 0, std::numeric_limits<uint64_t>::max(),
                                     {{kHeldTick, 32}, {kProbeTick, 96}});
    fixture.bank.voices[0].type = VOICE_DIRECTSOUND;
    fixture.bank.voices[1].type = VOICE_SQUARE_1;
    fixture.bank.voices[2].type = VOICE_PROGRAMMABLE_WAVE;
    fixture.bank.voices[3].type = VOICE_NOISE;
    checks::EditorRigConfig config;
    config.voicegroup = &fixture.bank;
    config.track = 0;
    config.activePage = EditorDrawerPage::Automations;
    config.sections = {{EditorDrawerPage::Automations, 320}};
    config.timeZoom = 96.0;
    fixture.rig = checks::EditorRig::create(fixture.document, config, error);
    if (!fixture.rig)
        return false;

    QQuickWindow *const window = quickWindow(fixture);
    songview::TimelineInputItem *const plot = plotInput(fixture);
    songview::TimelineInputItem *const gutter = gutterInput(fixture);
    if (!window || !plot || !gutter || !fixture.rig->quickScene()) {
        error = QStringLiteral(
            "Automation hover fixture did not expose its Quick window, scene, and inputs");
        return false;
    }
    if (!QTest::qWaitFor([window, plot, gutter] {
            return window->isVisible() && window->isExposed() && !plot->bounds().isEmpty() &&
                   !gutter->bounds().isEmpty() && plot->window() == window &&
                   gutter->window() == window;
        })) {
        error =
            QStringLiteral("Automation hover Quick window and input geometry did not become ready");
        return false;
    }
    return true;
}

AutomationPage *page(const Fixture &fixture)
{
    EditorDrawer *const drawer = fixture.rig ? fixture.rig->view().editorDrawer() : nullptr;
    return drawer ? drawer->automationPage() : nullptr;
}

AutomationCanvas *canvas(const Fixture &fixture)
{
    AutomationPage *const automationPage = page(fixture);
    return automationPage ? automationPage->canvas() : nullptr;
}

songview::TimelineInputItem *plotInput(const Fixture &fixture)
{
    return input(fixture, QStringLiteral("timelineAutomationInput"));
}

songview::TimelineInputItem *gutterInput(const Fixture &fixture)
{
    return input(fixture, QStringLiteral("timelineAutomationGutterInput"));
}

QQuickWindow *quickWindow(const Fixture &fixture)
{
    songview::TimelineQuickView *const quick =
        fixture.rig ? fixture.rig->view().quickView() : nullptr;
    return quick ? quick->quickWindow() : nullptr;
}

DocumentState documentState(Fixture &fixture)
{
    return {
        .smf = fixture.document.smf().write(),
        .revision = fixture.document.revision(),
        .undoCount = fixture.document.undoStack()->count(),
        .undoIndex = fixture.document.undoStack()->index(),
    };
}

LaneHandle findHandle(const AutomationCanvas &canvas, const EditorAutomationRowId &id)
{
    const auto &rows = canvas.rows();
    for (int index = 0; index < int(rows.size()); ++index) {
        if (rows[std::size_t(index)].id == id)
            return {index + 1};
    }
    return {};
}

bool rowMatches(const AutomationCanvas &canvas, LaneHandle handle, const EditorAutomationRowId &id)
{
    const auto &rows = canvas.rows();
    const int row = handle.index - 1;
    return handle.index > 0 && row >= 0 && row < int(rows.size()) &&
           rows[std::size_t(row)].id == id;
}

QPoint windowPoint(const Fixture &fixture, QPointF viewportPoint)
{
    const songview::TimelineInputItem *const plot = plotInput(fixture);
    return plot ? plot->mapToScene(viewportPoint).toPoint() : QPoint{};
}

void mouseMove(Fixture &fixture, QPoint position, bool primeTarget)
{
    QQuickWindow *const window = quickWindow(fixture);
    if (!window)
        return;
    fixture.lastWindowPosition = position;
    if (!fixture.windowEntered) {
        const QPointF windowPosition(position);
        QEnterEvent enter(windowPosition, windowPosition, QPointF(window->mapToGlobal(position)));
        QCoreApplication::sendEvent(window, &enter);
        fixture.windowEntered = true;
    }
    if (primeTarget) {
        songview::TimelineInputItem *const plot = plotInput(fixture);
        const bool primed = plot && checks::events::primeMouseMove(*window, *plot, position);
        if (!primed) {
            songview::TimelineInputItem *const gutter = gutterInput(fixture);
            if (gutter)
                checks::events::primeMouseMove(*window, *gutter, position);
        }
    }
    QTest::mouseEvent(QTest::MouseMove, window, Qt::NoButton, Qt::NoModifier, position);
}

void mousePress(Fixture &fixture, QPoint position)
{
    automation_hover::mouseMove(fixture, position);
    QTest::mousePress(quickWindow(fixture), Qt::LeftButton, Qt::NoModifier, position);
    fixture.heldButton = Qt::LeftButton;
}

void mouseRelease(Fixture &fixture, QPoint position)
{
    fixture.lastWindowPosition = position;
    QTest::mouseRelease(quickWindow(fixture), Qt::LeftButton, Qt::NoModifier, position);
    fixture.heldButton = Qt::NoButton;
}

bool leavePlot(Fixture &fixture)
{
    songview::TimelineInputItem *const gutter = gutterInput(fixture);
    if (!gutter || !quickWindow(fixture))
        return false;
    automation_hover::mouseMove(fixture, gutter->mapToScene(gutter->bounds().center()).toPoint());
    return true;
}

bool activateParameter(Fixture &fixture, const EditorAutomationRowId &row)
{
    AutomationCanvas *const automationCanvas = canvas(fixture);
    if (!automationCanvas)
        return false;
    // The catalog position comes from the production mapping only; clicking
    // the real selector label is the same activation path a user takes.
    const int index = automationCanvas->parameterIndex(row);
    if (index < 0)
        return false;
    QQuickItem *const root = fixture.rig ? fixture.rig->view().quickView()->rootObject() : nullptr;
    if (!root)
        return false;
    QQuickItem *label = nullptr;
    if (!QTest::qWaitFor([&root, &label, index] {
            label = visualDescendant(root, QStringLiteral("automationParameterTab%1").arg(index));
            return label && label->isVisible() && label->isEnabled() && label->width() > 0.0 &&
                   label->height() > 0.0 && label->window();
        })) {
        return false;
    }
    QQuickWindow *const window = label->window();
    QQuickItem *const content = window ? window->contentItem() : nullptr;
    if (!content)
        return false;
    const QPointF point = content->mapFromScene(
        label->mapToScene(QPointF(label->width() / 2.0, label->height() / 2.0)));
    if (!content->boundingRect().contains(point))
        return false;
    QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, point.toPoint());
    return QTest::qWaitFor(
        [automationCanvas, index] { return automationCanvas->activeParameter() == index; });
}

HoverObservation observe(const Fixture &fixture)
{
    HoverObservation observation;
    const songview::TimelineQuickScene *const scene = fixture.rig->quickScene();
    songview::TimelineQuickView *const quick = fixture.rig->view().quickView();
    if (!scene || !quick)
        return observation;
    observation.revision = scene->layer(songview::TimelineQuickLayer::AutomationHover).revision;
    AutomationPage *const automationPage = page(fixture);
    if (!automationPage)
        return observation;
    QQuickItem *const root = quick->rootObject();
    QQuickItem *const chrome =
        root ? root->findChild<QQuickItem *>(QStringLiteral("timelineQuickAutomationHoverChrome"))
             : nullptr;
    observation.chromeVisible = chrome && chrome->isVisible();
    observation.guidePublished = quick->hoverVisible();
    observation.guideRootX = quick->hoverRootContentX();
    const QRectF viewportRect(QPointF{}, QSizeF(automationPage->automationViewportSize()));
    const QAbstractItemModel *const model = scene->automationHoverTextModel();
    observation.textRows = model->rowCount();
    for (int row = 0; row < observation.textRows; ++row) {
        const QModelIndex index = model->index(row, 0);
        const QString text =
            model->data(index, songview::TimelineQuickTextModel::TextRole).toString();
        if (text.isEmpty())
            continue;
        ++observation.valueTextRows;
        observation.text = text;
        observation.color =
            model->data(index, songview::TimelineQuickTextModel::ColorRole).value<QColor>();
        observation.rect = model->data(index, songview::TimelineQuickTextModel::RectRole).toRectF();
        observation.clip =
            model->data(index, songview::TimelineQuickTextModel::ClipRectRole).toRectF();
        if (!observation.rect.isEmpty() && !observation.clip.isEmpty() &&
            observation.rect.intersects(observation.clip))
            ++observation.drawableValueTextRows;
        if (viewportRect.contains(observation.clip))
            ++observation.viewportValueTextRows;
    }
    return observation;
}

bool hasValueText(const Fixture &fixture, const HoverObservation &observation)
{
    const songview::TimelineQuickScene *const scene = fixture.rig->quickScene();
    return scene && observation.valueTextRows == 1 && observation.drawableValueTextRows == 1 &&
           observation.viewportValueTextRows == 1 &&
           observation.color == themes::color(themes::Role::song_view_primary_text) &&
           !scene->layer(songview::TimelineQuickLayer::AutomationHover).rects.empty();
}

bool isClear(const Fixture &fixture)
{
    const songview::TimelineQuickScene *const scene = fixture.rig->quickScene();
    const HoverObservation observation = observe(fixture);
    if (!scene)
        return false;
    const auto &layer = scene->layer(songview::TimelineQuickLayer::AutomationHover);
    return layer.rects.empty() && layer.triangles.empty() && observation.textRows == 0 &&
           !observation.chromeVisible;
}

bool hasFilledNodeAt(const songview::TimelineQuickLayerData &layer, QPointF center)
{
    const qreal tolerance = layout::singlePixel();
    const auto nearCenter = [&center, tolerance](const QPointF &point) {
        const QPointF delta = point - center;
        return delta.x() * delta.x() + delta.y() * delta.y() <= tolerance * tolerance;
    };
    return std::any_of(layer.triangles.cbegin(), layer.triangles.cend(),
                       [&nearCenter](const songview::TimelineQuickTriangle &triangle) {
                           return nearCenter(triangle.first) || nearCenter(triangle.second) ||
                                  nearCenter(triangle.third);
                       });
}

std::optional<PreparedLane> prepareLane(Fixture &fixture, LaneKind kind)
{
    AutomationCanvas *const automationCanvas = canvas(fixture);
    AutomationPage *const automationPage = page(fixture);
    songview::TimelineInputItem *const plot = plotInput(fixture);
    if (!automationCanvas || !automationPage || !plot)
        return std::nullopt;

    const int minimum = kind == LaneKind::Tempo ? CoreTimeDefaults::kMinTempoBpm : 0;
    const int maximum = kind == LaneKind::Tempo ? CoreTimeDefaults::kMaxTempoBpm : 127;
    const int held = valueAtFraction(minimum, maximum, 0.25);
    const int node = valueAtFraction(minimum, maximum, 0.75);
    const int cursor = valueAtFraction(minimum, maximum, 0.50);
    LaneHandle handle;
    const EditorAutomationRowId row = laneRow(kind);
    if (kind == LaneKind::Tempo) {
        TempoEdit edit;
        edit.remove = fixture.document.tempoPoints();
        edit.add = {{kHeldTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(held)},
                    {kNodeTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(node)}};
        fixture.document.applyTempoEdit(edit);
        handle = {0};
    } else {
        fixture.document.writeLanePoints(0, kPanController, 0, std::numeric_limits<uint64_t>::max(),
                                         {{kHeldTick, held}, {kNodeTick, node}});
        handle = findHandle(*automationCanvas, row);
    }
    if (!activateParameter(fixture, row))
        return std::nullopt;
    QCoreApplication::processEvents();
    const QRect body = automationCanvas->laneBody(handle);
    if (!handle.valid() || body.isEmpty())
        return std::nullopt;

    const AutomationGeometry geometry = AutomationGeometry::resolve();
    const qreal dpr = plot->devicePixelRatio();
    const qreal probeX = fixture.rig->view().camera().displayX(kProbeTick, 0.0, dpr);
    const qreal nodeX = fixture.rig->view().camera().displayX(kNodeTick, 0.0, dpr);
    const qreal heldY = AutomationProjection::valueY(body, geometry, minimum, maximum, held);
    const qreal cursorY = AutomationProjection::valueY(body, geometry, minimum, maximum, cursor);
    const qreal nodeY = AutomationProjection::valueY(body, geometry, minimum, maximum, node);
    const auto quantizedViewportPoint = [&fixture, plot](const QPointF &viewportPoint) {
        const QPoint windowPosition = automation_hover::windowPoint(fixture, viewportPoint);
        return std::pair{windowPosition, plot->mapFromScene(QPointF(windowPosition))};
    };
    const auto [insertionWindowPosition, insertionPointerViewport] =
        quantizedViewportPoint({probeX, cursorY});
    const auto [nodeWindowPosition, nodePointerViewport] = quantizedViewportPoint({nodeX, nodeY});
    if (!plot->bounds().contains(insertionPointerViewport) ||
        !plot->bounds().contains(nodePointerViewport)) {
        return std::nullopt;
    }
    const AutomationProjection projection(geometry, automationPage);
    const uint64_t insertionTick =
        projection.fineSnapTick(projection.rawTickAt(insertionPointerViewport.x()));
    const qreal insertionX = projection.displayX(insertionTick, dpr);
    return PreparedLane{
        .kind = kind,
        .handle = handle,
        .insertionTick = insertionTick,
        .insertionWindowPosition = insertionWindowPosition,
        .nodeWindowPosition = nodeWindowPosition,
        .pointerViewport = insertionPointerViewport,
        .insertionViewport = {insertionX, heldY},
        .nodeViewport = {nodeX, nodeY},
        .strayGhostViewport = {nodeX, heldY},
        .nodeValue = node,
        .heldValue = held,
    };
}

Topology topologyFor(Fixture &fixture, const PreparedLane &lane, QString &error)
{
    Topology topology;
    error.clear();
    songview::TimelineQuickScene *const scene = fixture.rig->quickScene();
    songview::TimelineQuickView *const quick = fixture.rig->view().quickView();
    const songview::TimelineInputItem *const plot = plotInput(fixture);
    if (!scene || !quick || !plot) {
        error = QStringLiteral("Automation hover fixture lost its Quick scene, view, or plot");
        return topology;
    }
    if (!leavePlot(fixture) || !QTest::qWaitFor([&fixture] { return isClear(fixture); })) {
        error = QStringLiteral("could not establish a clear retained-hover baseline");
        return topology;
    }
    const DocumentState frozen = documentState(fixture);
    const HoverObservation idle = observe(fixture);
    automation_hover::mouseMove(fixture, lane.insertionWindowPosition);
    QCoreApplication::processEvents();
    const HoverObservation insertion = observe(fixture);
    const auto &insertionLayer = scene->layer(songview::TimelineQuickLayer::AutomationHover);
    const qreal expectedGuideX = fixture.rig->view().camera().contentX(lane.insertionTick);
    const qreal expectedRootX = fixture.rig->view().timelineSplitX() + expectedGuideX;
    topology.insertionGuide =
        insertion.chromeVisible && insertion.revision > idle.revision &&
        std::abs(insertion.guideRootX - expectedRootX) <= layout::singlePixel();
    if (!topology.insertionGuide && lane.kind == LaneKind::Tempo) {
        error = QStringLiteral(
                    "Tempo retained guide mismatch: handle=%1 tick=%2 window=(%3,%4) "
                    "pointerViewport=(%5,%6) expectedGuideX=%7 chromeVisible=%8 published=%9 "
                    "rootX=%10 expectedRootX=%11 textRect=[%12,%13 %14x%15] "
                    "textClip=[%16,%17 %18x%19] layerRevision=%20->%21")
                    .arg(lane.handle.index)
                    .arg(qulonglong(lane.insertionTick))
                    .arg(lane.insertionWindowPosition.x())
                    .arg(lane.insertionWindowPosition.y())
                    .arg(lane.pointerViewport.x())
                    .arg(lane.pointerViewport.y())
                    .arg(expectedGuideX)
                    .arg(insertion.chromeVisible)
                    .arg(insertion.guidePublished)
                    .arg(insertion.guideRootX)
                    .arg(expectedRootX)
                    .arg(insertion.rect.x())
                    .arg(insertion.rect.y())
                    .arg(insertion.rect.width())
                    .arg(insertion.rect.height())
                    .arg(insertion.clip.x())
                    .arg(insertion.clip.y())
                    .arg(insertion.clip.width())
                    .arg(insertion.clip.height())
                    .arg(idle.revision)
                    .arg(insertion.revision);
    }
    topology.heldGhost = hasFilledNodeAt(insertionLayer, lane.insertionViewport) &&
                         !hasFilledNodeAt(insertionLayer, lane.pointerViewport);
    topology.insertionText = hasValueText(fixture, insertion) &&
                             insertion.text == expectedValueText(fixture, lane, lane.heldValue);

    automation_hover::mouseMove(fixture, lane.insertionWindowPosition, false);
    QCoreApplication::processEvents();
    const HoverObservation repeated = observe(fixture);
    topology.repeatDoesNotChurn = repeated == insertion;

    automation_hover::mouseMove(fixture, lane.nodeWindowPosition);
    QCoreApplication::processEvents();
    const HoverObservation node = observe(fixture);
    const auto &nodeLayer = scene->layer(songview::TimelineQuickLayer::AutomationHover);
    topology.nodeRing = node.revision > insertion.revision &&
                        hasAnnulusAt(nodeLayer, lane.nodeViewport,
                                     nodelane::hoverRingRadius(AutomationGeometry::resolve()),
                                     2 * layout::singlePixel());
    topology.nodeText = hasValueText(fixture, node) &&
                        node.text == expectedValueText(fixture, lane, lane.nodeValue);
    topology.suppressesInsertionGhost = !hasFilledNodeAt(nodeLayer, lane.strayGhostViewport);

    if (!leavePlot(fixture)) {
        error = QStringLiteral("could not deliver a real Quick pointer leave");
        return topology;
    }
    const bool transitionCleared = QTest::qWaitFor([&fixture] { return isClear(fixture); });
    if (!leavePlot(fixture)) {
        error = QStringLiteral("could not deliver the repeated Quick pointer leave");
        return topology;
    }
    const bool finalCleared = QTest::qWaitFor([&fixture] { return isClear(fixture); });
    topology.leaveCleared = transitionCleared && finalCleared && isClear(fixture);
    // Away/back parameter activation: hovering the origin under the away
    // parameter fills the retained hover, the switch back must clear it, and
    // the re-hover must show the reactivated parameter's held value — never
    // the away parameter's stale cache. The away lane must carry written
    // events (Pan for the Tempo run, LFO for the CC run): a lane without
    // points publishes no origin hover text at all.
    const EditorAutomationRowId awayRow =
        lane.kind == LaneKind::Tempo
            ? EditorAutomationRowId{EditorAutomationRowKind::ControlChange, 0, kPanController}
            : EditorAutomationRowId{EditorAutomationRowKind::ControlChange, 0, kLfoController};
    if (!activateParameter(fixture, awayRow)) {
        error = QStringLiteral("could not activate the away parameter after passive hover");
        return topology;
    }
    automation_hover::mouseMove(fixture, lane.insertionWindowPosition);
    if (!QTest::qWaitFor([&fixture] { return hasValueText(fixture, observe(fixture)); })) {
        error = QStringLiteral("away parameter hover showed no origin value text");
        return topology;
    }
    if (!activateParameter(fixture, laneRow(lane.kind))) {
        error = QStringLiteral("could not reactivate the origin parameter after switching");
        return topology;
    }
    if (!QTest::qWaitFor([&fixture] { return isClear(fixture); })) {
        error = QStringLiteral("parameter switching kept a stale retained hover");
        return topology;
    }
    automation_hover::mouseMove(fixture, lane.insertionWindowPosition);
    QCoreApplication::processEvents();
    const HoverObservation reactivated = observe(fixture);
    topology.reactivatedHeldText =
        hasValueText(fixture, reactivated) &&
        reactivated.text == expectedValueText(fixture, lane, lane.heldValue);
    if (!(documentState(fixture) == frozen))
        error = QStringLiteral("passive hover or parameter switching mutated the document");
    return topology;
}

} // namespace automation_hover
