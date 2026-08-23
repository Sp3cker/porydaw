#include <algorithm>
#include <cmath>
#include <cstdio>
#include <limits>
#include <optional>
#include <vector>

#include <QCoreApplication>
#include <QEvent>
#include <QFont>
#include <QFontInfo>
#include <QFontMetrics>
#include <QImage>
#include <QRegion>
#include <QScrollArea>
#include <QScrollBar>
#include <QUndoStack>

#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/editordrawer/nodelane/paint.h"
#include "ui/editordrawer/tempolane.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/editorselectionmodel.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"

namespace {

constexpr uint64_t kHeldTick = 48;
constexpr uint64_t kNodeTick = 96;
constexpr uint64_t kSecondTick = 144;

struct CcCoverageLane {
    EditorAutomationRowId id;
    QRect body;
    QRect overlap;
};

void pump()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
}

void leaveCanvas(AutomationPage &page)
{
    QEvent leave(QEvent::Leave);
    QCoreApplication::sendEvent(page.canvas(), &leave);
    pump();
}

void refresh(AutomationPage &page, SongDocument &document, DrawerPageLiveState &live)
{
    live.documentRevision = document.revision();
    page.documentChanged();
    page.refreshLiveState(live);
    pump();
}

void setCcPoints(AutomationPage &page, SongDocument &document, DrawerPageLiveState &live,
                 int engineTrack, uint8_t controller,
                 const std::vector<SongDocument::LanePointValue> &points)
{
    document.writeLanePoints(engineTrack, controller, 0, std::numeric_limits<uint64_t>::max(),
                             points);
    refresh(page, document, live);
}

QPointF tempoHeaderPoint(const AutomationPage &page)
{
    const QRect tempo = page.canvas()->pinnedTempoRect();
    return {page.canvas()->plotOrigin() / 2.0, qreal(tempo.center().y())};
}

bool toggleTempoExpanded(AutomationPage &page, bool wantExpanded, int &failures)
{
    const bool expanded = !page.canvas()->laneBody(LaneHandle{0}).isEmpty();
    if (expanded == wantExpanded)
        return expanded;
    const QImage beforeToggle = page.canvas()->grab().toImage();
    checks::events::sendMouse(*page.canvas(), QEvent::MouseButtonPress, tempoHeaderPoint(page),
                              Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*page.canvas(), QEvent::MouseButtonRelease, tempoHeaderPoint(page),
                              Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    pump();
    if (page.canvas()->grab().toImage() == beforeToggle) {
        std::fprintf(stderr, "automation-check: FAIL paint: tempo header toggle did not repaint\n");
        ++failures;
    }
    return !page.canvas()->laneBody(LaneHandle{0}).isEmpty() == wantExpanded;
}

QRect deviceRect(const QRectF &logical, qreal dpr, const QSize &bound)
{
    const int left = std::clamp(int(std::floor(logical.left() * dpr)), 0, bound.width());
    const int top = std::clamp(int(std::floor(logical.top() * dpr)), 0, bound.height());
    const int right = std::clamp(int(std::ceil(logical.right() * dpr)), 0, bound.width());
    const int bottom = std::clamp(int(std::ceil(logical.bottom() * dpr)), 0, bound.height());
    return {left, top, std::max(0, right - left), std::max(0, bottom - top)};
}

int changedPixels(const QImage &before, const QImage &after, const QRegion &logical, qreal dpr)
{
    if (before.size() != after.size() || before.format() != after.format())
        return -1;
    int changed = 0;
    bool compared = false;
    for (const QRect &logicalRect : logical) {
        const QRect rect =
            deviceRect(QRectF(logicalRect), dpr, before.size()).intersected(before.rect());
        if (rect.isEmpty())
            continue;
        compared = true;
        for (int y = rect.top(); y <= rect.bottom(); ++y) {
            for (int x = rect.left(); x <= rect.right(); ++x) {
                if (before.pixel(x, y) != after.pixel(x, y))
                    ++changed;
            }
        }
    }
    return compared ? changed : -1;
}

bool hasColorNear(const QImage &image, const QRectF &logical, qreal dpr, const QColor &expected,
                  int tolerance)
{
    const QRect rect = deviceRect(logical, dpr, image.size()).intersected(image.rect());
    for (int y = rect.top(); y <= rect.bottom(); ++y) {
        for (int x = rect.left(); x <= rect.right(); ++x) {
            const QColor actual(image.pixel(x, y));
            if (std::abs(actual.red() - expected.red()) <= tolerance &&
                std::abs(actual.green() - expected.green()) <= tolerance &&
                std::abs(actual.blue() - expected.blue()) <= tolerance)
                return true;
        }
    }
    return false;
}

std::optional<CcCoverageLane> ccCoveredBy(const AutomationPage &page, const QRect &cover)
{
    if (cover.isEmpty())
        return std::nullopt;
    const auto &rows = page.canvas()->rows();
    for (int index = 0; index < int(rows.size()); ++index) {
        const QRect body = page.canvas()->laneBody(LaneHandle{index + 1});
        const QRect overlap = body.intersected(cover);
        if (!body.isEmpty() && !overlap.isEmpty() &&
            !QRegion(body).subtracted(QRegion(cover)).isEmpty())
            return CcCoverageLane{rows[std::size_t(index)].id, body, overlap};
    }
    return std::nullopt;
}

QRectF overlapProbe(const QRect &overlap, qreal x, qreal radius)
{
    if (overlap.isEmpty())
        return {};
    const QRectF bounds(overlap);
    const qreal half = std::min(radius, std::min(bounds.width(), bounds.height()) / 4.0);
    if (half <= 0.0)
        return {};
    const qreal probeX = std::clamp(x, bounds.left() + half, bounds.right() - half);
    return {probeX - half, bounds.center().y() - half, 2 * half, 2 * half};
}

std::optional<CcCoverageLane> scrollToCollapsedCcOverlap(AutomationPage &page, QScrollArea &scroll,
                                                         int headerHeight)
{
    QScrollBar *bar = scroll.verticalScrollBar();
    if (!bar || !scroll.viewport())
        return std::nullopt;
    const int viewportHeight = scroll.viewport()->height();
    const auto &rows = page.canvas()->rows();
    for (int index = 0; index < int(rows.size()); ++index) {
        const QRect body = page.canvas()->laneBody(LaneHandle{index + 1});
        if (body.isEmpty())
            continue;
        const int value = body.center().y() - viewportHeight + headerHeight;
        if (value < bar->minimum() || value > bar->maximum())
            continue;
        bar->setValue(value);
        pump();
        if (auto cc = ccCoveredBy(page, page.canvas()->pinnedTempoRect()))
            return cc;
    }
    return std::nullopt;
}

} // namespace

void checkAutomationTempoOcclusion(SongView &view, AutomationPage &page, SongDocument &document,
                                   DrawerPageLiveState &live, int &failures)
{
    const auto report = [&failures](bool condition, const QString &message) {
        if (condition)
            return;
        std::fprintf(stderr, "automation-check: FAIL paint: Tempo: %s\n", qUtf8Printable(message));
        ++failures;
    };
    AutomationGeometry geometry = AutomationGeometry::resolve();
    geometry.plotOrigin = page.canvas()->plotOrigin();
    const qreal dpr = page.canvas()->devicePixelRatioF();
    const qreal radius = nodelane::hoverRingRadius(geometry);
    const auto tickX = [&](uint64_t tick) {
        return view.displayX(double(tick), geometry.plotOrigin, dpr);
    };

    const int originalPageHeight = page.height();
    QScrollArea *scroll = page.findChild<QScrollArea *>(QStringLiteral("automationScroll"));
    const int originalScroll =
        scroll && scroll->verticalScrollBar() ? scroll->verticalScrollBar()->value() : 0;
    const auto originalSelection = view.selectionModel().timeSelection();
    page.resize(page.width(), 2 * geometry.rowDefaultHeight);
    pump();
    refresh(page, document, live);
    if (scroll && scroll->verticalScrollBar()) {
        scroll->verticalScrollBar()->setValue(scroll->verticalScrollBar()->minimum());
        pump();
    }

    QRect expandedTempo = page.canvas()->laneBody(LaneHandle{0});
    if (scroll && !expandedTempo.isEmpty()) {
        scrollToCollapsedCcOverlap(page, *scroll, expandedTempo.height());
        expandedTempo = page.canvas()->laneBody(LaneHandle{0});
    }
    const auto expandedCc = ccCoveredBy(page, expandedTempo);
    report(expandedCc.has_value(),
           QStringLiteral("expanded Tempo body did not overlap a visible CC lane"));
    if (expandedCc) {
        CCLaneAdapter lane(document, int(expandedCc->id.track), expandedCc->id.controller);
        std::vector<SongDocument::LanePointValue> points;
        for (const DocLanePoint &point :
             document.lanePoints(int(expandedCc->id.track), expandedCc->id.controller)) {
            points.push_back({point.tick, point.value});
        }
        const std::vector<SongDocument::LanePointValue> mutation = {
            {kHeldTick, lane.maximumValue()},
            {kNodeTick, lane.minimumValue()},
            {kSecondTick, lane.maximumValue()},
        };
        const QRegion covered(expandedCc->overlap);
        const QRegion visible = QRegion(expandedCc->body).subtracted(QRegion(expandedTempo));
        const QRectF probe = overlapProbe(expandedCc->overlap, tickX(kNodeTick), radius);
        leaveCanvas(page);
        const QImage before = page.canvas()->grab().toImage();
        setCcPoints(page, document, live, int(expandedCc->id.track), expandedCc->id.controller,
                    mutation);
        leaveCanvas(page);
        const QImage after = page.canvas()->grab().toImage();
        const int coveredChanges = changedPixels(before, after, covered, dpr);
        const int visibleChanges = changedPixels(before, after, visible, dpr);
        report(!expandedTempo.isEmpty() && !covered.isEmpty() && !visible.isEmpty() &&
                   !probe.isEmpty() && QRectF(expandedTempo).contains(probe) &&
                   QRectF(expandedCc->body).contains(probe) && coveredChanges == 0 &&
                   visibleChanges > 0,
               QStringLiteral("expanded Tempo body did not occlude CC paint"));

        songview::EditorSelectionModel::TimeSelection tempoSelection;
        tempoSelection.startTick = kNodeTick;
        tempoSelection.endTick = kNodeTick + 1;
        tempoSelection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
        tempoSelection.tempo = true;
        view.selectionModel().setTimeSelection(tempoSelection);
        refresh(page, document, live);
        leaveCanvas(page);
        const QImage reticle = page.canvas()->grab().toImage();
        report(changedPixels(after, reticle, covered, dpr) > 0,
               QStringLiteral("Tempo selection reticle did not repaint the covered body"));
        report(hasColorNear(reticle, probe, dpr,
                            themes::color(themes::Role::song_view_selection_edge), 24),
               QStringLiteral("Tempo selection reticle did not paint its selection edge"));
        view.selectionModel().clearTimeSelection();
        refresh(page, document, live);
        setCcPoints(page, document, live, int(expandedCc->id.track), expandedCc->id.controller,
                    points);
    }

    const bool tempoCollapsed = toggleTempoExpanded(page, false, failures);
    std::optional<CcCoverageLane> collapsedCc;
    if (tempoCollapsed && scroll)
        collapsedCc = scrollToCollapsedCcOverlap(page, *scroll, geometry.addLaneStripHeight);
    report(collapsedCc.has_value(),
           QStringLiteral("collapsed Tempo header did not overlap a visible CC lane"));
    if (collapsedCc) {
        const QRect header = page.canvas()->pinnedTempoRect();
        CCLaneAdapter lane(document, int(collapsedCc->id.track), collapsedCc->id.controller);
        std::vector<SongDocument::LanePointValue> points;
        for (const DocLanePoint &point :
             document.lanePoints(int(collapsedCc->id.track), collapsedCc->id.controller)) {
            points.push_back({point.tick, point.value});
        }
        const std::vector<SongDocument::LanePointValue> mutation = {
            {kHeldTick, lane.maximumValue()},
            {kNodeTick, lane.minimumValue()},
            {kSecondTick, lane.maximumValue()},
        };
        const QRegion covered(collapsedCc->overlap);
        const QRegion visible = QRegion(collapsedCc->body).subtracted(QRegion(header));
        leaveCanvas(page);
        const QImage before = page.canvas()->grab().toImage();
        setCcPoints(page, document, live, int(collapsedCc->id.track), collapsedCc->id.controller,
                    mutation);
        leaveCanvas(page);
        const QImage after = page.canvas()->grab().toImage();
        report(tempoCollapsed && !covered.isEmpty() && !visible.isEmpty() &&
                   changedPixels(before, after, covered, dpr) == 0 &&
                   changedPixels(before, after, visible, dpr) > 0,
               QStringLiteral("collapsed Tempo header did not occlude CC paint"));
        setCcPoints(page, document, live, int(collapsedCc->id.track), collapsedCc->id.controller,
                    points);
    }

    page.resize(page.width(), originalPageHeight);
    pump();
    if (scroll && scroll->verticalScrollBar()) {
        QScrollBar *bar = scroll->verticalScrollBar();
        bar->setValue(std::clamp(originalScroll, bar->minimum(), bar->maximum()));
        pump();
    }
    view.selectionModel().setTimeSelection(originalSelection);
    refresh(page, document, live);
}

void checkAutomationCanvasFontPaint(SongView &view, AutomationPage &page, SongDocument &document,
                                    DrawerPageLiveState &live, int &failures)
{
    const auto report = [&failures](bool condition, const QString &message) {
        if (condition)
            return;
        std::fprintf(stderr, "automation-check: FAIL paint: Fonts: %s\n", qUtf8Printable(message));
        ++failures;
    };
    AutomationCanvas *canvas = page.canvas();
    const QFont originalFont = canvas->font();
    const QByteArray originalSmf = document.smf().write();
    const int originalUndoIndex = document.undoStack()->index();
    const auto originalSelection = view.selectionModel().timeSelection();
    const bool originallyExpanded = !canvas->laneBody(LaneHandle{0}).isEmpty();
    const auto restore = [&] {
        typography::setUseSystemFont(false);
        canvas->setFont(originalFont);
        pump();
        document.undoStack()->setIndex(originalUndoIndex);
        view.selectionModel().setTimeSelection(originalSelection);
        refresh(page, document, live);
        toggleTempoExpanded(page, originallyExpanded, failures);
        leaveCanvas(page);
    };
    view.selectionModel().clearTimeSelection();
    const bool expanded = toggleTempoExpanded(page, true, failures);
    report(expanded, QStringLiteral("Tempo header did not expose labels for font coverage"));
    TempoEdit edit;
    edit.remove = document.tempoPoints();
    edit.add = {{kHeldTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(120)},
                {kNodeTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(180)}};
    document.applyTempoEdit(edit);
    refresh(page, document, live);
    leaveCanvas(page);

    const AutomationGeometry geometry = [&] {
        auto resolved = AutomationGeometry::resolve();
        resolved.plotOrigin = canvas->plotOrigin();
        return resolved;
    }();
    const QRect body = canvas->laneBody(LaneHandle{0});
    const qreal dpr = canvas->devicePixelRatioF();
    const auto laneLabel = [&](const QRect &laneBody, const AutomationGeometry &laneGeometry,
                               bool summary) {
        const QRect gutter = canvas->labelGutter();
        const int arrowSize = std::max(layout::fontPx(0.5), laneGeometry.addLaneStripHeight / 3);
        const int left = gutter.x() + arrowSize + layout::space(layout::Space::One);
        const int top = laneBody.top() + (summary ? laneGeometry.addLaneStripHeight : 0);
        return QRect(left, top,
                     std::max(0, gutter.width() - arrowSize - layout::space(layout::Space::One)),
                     laneGeometry.addLaneStripHeight)
            .intersected(laneBody);
    };
    const auto labelColumn = [&](const QRect &laneBody) {
        const QRect gutter = canvas->labelGutter();
        return QRect(gutter.x(), laneBody.top(), gutter.width(), laneBody.height())
            .intersected(laneBody);
    };
    const auto valueLabel = [](const QPointF &anchor, const QRect &plot, const QFont &font) {
        const QFontMetrics metrics(typography::noteName(font));
        const int gap = layout::space(layout::Space::One);
        const int width = metrics.horizontalAdvance(QStringLiteral("0000"));
        const int height = metrics.height();
        int x = qCeil(anchor.x() - gap - width);
        int y = qRound(anchor.y()) - gap - height;
        if (x < plot.left())
            x = qFloor(anchor.x() + gap);
        if (y < plot.top())
            y = qRound(anchor.y()) + gap;
        x = std::clamp(x, plot.left(), std::max(plot.left(), plot.right() - width + 1));
        y = std::clamp(y, plot.top(), std::max(plot.top(), plot.bottom() - height + 1));
        return QRect(x, y, width, height);
    };
    const QImage idle = canvas->grab().toImage();
    const QRect title = laneLabel(body, geometry, false);
    const QRect summary = laneLabel(body, geometry, true);
    const QRect ccBody = canvas->laneBody(LaneHandle{1});
    const QRect ccLabels = labelColumn(ccBody);
    report(!body.isEmpty() && !title.isEmpty() && !summary.isEmpty(),
           QStringLiteral("expanded Tempo lane has no label bounds"));
    report(hasColorNear(idle, title, dpr, themes::color(themes::Role::song_view_primary_text), 24),
           QStringLiteral("Tempo title label did not render"));
    report(
        hasColorNear(idle, summary, dpr, themes::color(themes::Role::song_view_secondary_text), 24),
        QStringLiteral("Tempo caption label did not render"));
    report(!ccLabels.isEmpty() &&
               hasColorNear(idle, ccLabels, dpr,
                            themes::color(themes::Role::song_view_primary_text), 24) &&
               hasColorNear(idle, ccLabels, dpr,
                            themes::color(themes::Role::song_view_secondary_text), 24),
           QStringLiteral("CC lane title or caption label did not render"));

    TempoLane tempoLane(document);
    const QPointF node(view.displayX(double(kNodeTick), geometry.plotOrigin, dpr),
                       nodelane::valueY(tempoLane, body, geometry, 180));
    const QRect hoverLabel = valueLabel(node, nodelane::plotRect(body, geometry), canvas->font());
    checks::events::sendMouse(*canvas, QEvent::MouseMove, node, Qt::NoButton, Qt::NoButton,
                              Qt::NoModifier);
    pump();
    const QImage hovered = canvas->grab().toImage();
    report(changedPixels(idle, hovered, QRegion(hoverLabel), dpr) > 0,
           QStringLiteral("Tempo hover value label did not render"));

    const QString systemFamily = typography::systemFontFamily();
    report(!systemFamily.isEmpty(), QStringLiteral("platform font family is unavailable"));
    typography::setUseSystemFont(true);
    const auto systemBody = typography::bodyFont();
    report(systemBody.has_value(), QStringLiteral("system Body font is unavailable"));
    if (!systemFamily.isEmpty() && systemBody) {
        canvas->setFont(*systemBody);
        pump();
        const QImage systemHover = canvas->grab().toImage();
        const AutomationGeometry systemGeometry = [&] {
            auto resolved = AutomationGeometry::resolve();
            resolved.plotOrigin = canvas->plotOrigin();
            return resolved;
        }();
        const QRect systemBody = canvas->laneBody(LaneHandle{0});
        const QPointF systemNode(view.displayX(double(kNodeTick), systemGeometry.plotOrigin, dpr),
                                 nodelane::valueY(tempoLane, systemBody, systemGeometry, 180));
        const QRect systemHoverLabel =
            valueLabel(systemNode, nodelane::plotRect(systemBody, systemGeometry), canvas->font());
        QRegion laneLabels(title);
        laneLabels += summary;
        laneLabels += ccLabels;
        laneLabels += laneLabel(systemBody, systemGeometry, false);
        laneLabels += laneLabel(systemBody, systemGeometry, true);
        laneLabels += labelColumn(canvas->laneBody(LaneHandle{1}));
        report(QFontInfo(canvas->font()).family() == systemFamily,
               QStringLiteral("AutomationCanvas did not receive the system font"));
        report(changedPixels(hovered, systemHover, laneLabels, dpr) > 0,
               QStringLiteral("FontChange did not refresh lane label geometry or pixels"));
        report(hasColorNear(systemHover, systemHoverLabel, dpr,
                            themes::color(themes::Role::song_view_primary_text), 12),
               QStringLiteral("FontChange lost the visible Tempo hover value label"));
    }

    restore();
    report(document.smf().write() == originalSmf &&
               document.undoStack()->index() == originalUndoIndex,
           QStringLiteral("font coverage did not restore the document or undo stack"));
}
