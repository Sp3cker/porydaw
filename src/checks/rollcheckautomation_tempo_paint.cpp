#include <algorithm>
#include <cstdio>
#include <limits>
#include <optional>
#include <vector>

#include <QAbstractItemModel>
#include <QColor>
#include <QCoreApplication>
#include <QEvent>
#include <QFont>
#include <QFontInfo>
#include <QPoint>
#include <QRegion>
#include <QScrollArea>
#include <QScrollBar>
#include <QUndoStack>
#include <QWidget>

#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/editordrawer/nodelane/hover.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/editordrawer/tempolane.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/editorselectionmodel.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/theme/themeruntime.h"
#include "ui/theme/trackidentitycolors.h"
#include "ui/typography.h"

namespace {

songview::TimelineInputItem *automationInputItem(SongView &view)
{
    auto *quickCanvas =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    return quickCanvas && quickCanvas->rootObject()
               ? quickCanvas->rootObject()->findChild<songview::TimelineInputItem *>(
                     QStringLiteral("timelineAutomationInput"))
               : nullptr;
}

// Band input delivery: the Quick input item normalizes raw events in
// viewport coordinates, so content-coordinate probes shift by the page
// scroll before each send.
struct AutomationBandInput {
    AutomationPage &page;
    songview::TimelineInputItem &item;

    void mouse(QEvent::Type type, const QPointF &contentPosition, Qt::MouseButton button,
               Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers) const
    {
        checks::events::sendMouse(item, type, contentPosition - QPointF(0.0, page.verticalScroll()),
                                  button, buttons, modifiers);
    }
    void leave() const { mouse(QEvent::Leave, {}, Qt::NoButton, Qt::NoButton, Qt::NoModifier); }
};

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
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
}

QPoint automationContentToViewport(const AutomationPage &page)
{
    return {0, -page.verticalScroll()};
}

void leaveCanvas(const AutomationBandInput &band)
{
    band.leave();
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

bool toggleTempoExpanded(SongView &view, AutomationPage &page, bool wantExpanded, int &)
{
    const bool expanded = !page.canvas()->laneBody(LaneHandle{0}).isEmpty();
    if (expanded == wantExpanded)
        return expanded;
    AutomationBandInput band{page, *automationInputItem(view)};
    band.mouse(QEvent::MouseButtonPress, tempoHeaderPoint(page), Qt::LeftButton, Qt::LeftButton,
               Qt::NoModifier);
    band.mouse(QEvent::MouseButtonRelease, tempoHeaderPoint(page), Qt::LeftButton, Qt::NoButton,
               Qt::NoModifier);
    pump();
    return !page.canvas()->laneBody(LaneHandle{0}).isEmpty() == wantExpanded;
}

QRectF bounds(const songview::TimelineQuickTriangle &triangle)
{
    const qreal left = std::min({triangle.first.x(), triangle.second.x(), triangle.third.x()});
    const qreal right = std::max({triangle.first.x(), triangle.second.x(), triangle.third.x()});
    const qreal top = std::min({triangle.first.y(), triangle.second.y(), triangle.third.y()});
    const qreal bottom = std::max({triangle.first.y(), triangle.second.y(), triangle.third.y()});
    return QRectF(QPointF(left, top), QPointF(right, bottom));
}

bool layerHasColorIn(const songview::TimelineQuickLayerData &layer, const QRegion &contentRegion,
                     const QPoint &contentOrigin, const QColor &color)
{
    const QRegion region = contentRegion.translated(contentOrigin);
    for (const songview::TimelineQuickRect &rect : layer.rects) {
        if (region.intersects(rect.rect.toAlignedRect()) &&
            (rect.topLeft == color || rect.topRight == color || rect.bottomRight == color ||
             rect.bottomLeft == color)) {
            return true;
        }
    }
    for (const songview::TimelineQuickTriangle &triangle : layer.triangles) {
        if (region.intersects(bounds(triangle).toAlignedRect()) &&
            (triangle.firstColor == color || triangle.secondColor == color ||
             triangle.thirdColor == color)) {
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
    const AutomationBandInput band{page, *automationInputItem(view)};
    auto *quickScene = view.findChild<songview::TimelineQuickScene *>();
    report(quickScene, QStringLiteral("retained Quick automation scene was not available"));
    if (!quickScene)
        return;
    const AutomationGeometry geometry = AutomationGeometry::resolve();

    const int originalPageHeight = page.height();
    const int originalSectionHeight = view.drawerSectionHeight(EditorDrawerPage::Automations);
    const int sectionChromeHeight = std::max(0, originalSectionHeight - originalPageHeight);
    QScrollArea *scroll = page.findChild<QScrollArea *>(QStringLiteral("automationScroll"));
    const int originalScroll =
        scroll && scroll->verticalScrollBar() ? scroll->verticalScrollBar()->value() : 0;
    const auto originalSelection = view.selectionModel().timeSelection();
    view.setDrawerSectionHeight(EditorDrawerPage::Automations,
                                2 * geometry.rowDefaultHeight + sectionChromeHeight);
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
        const QPoint expandedCaptureOrigin = automationContentToViewport(page);
        const QColor ccColor =
            themes::trackIdentityColor(expandedCc->id.track % themes::trackIdentityColorCount);
        const quint64 curvesRevision =
            quickScene ? quickScene->layer(songview::TimelineQuickLayer::AutomationCurves).revision
                       : 0;
        setCcPoints(page, document, live, int(expandedCc->id.track), expandedCc->id.controller,
                    mutation);
        leaveCanvas(band);
        const auto &curves = quickScene->layer(songview::TimelineQuickLayer::AutomationCurves);
        report(!expandedTempo.isEmpty() && !covered.isEmpty() && !visible.isEmpty() &&
                   !layerHasColorIn(curves, covered, expandedCaptureOrigin, ccColor) &&
                   layerHasColorIn(curves, visible, expandedCaptureOrigin, ccColor),
               QStringLiteral("expanded Tempo body did not clip retained Quick CC composition"));
        report(quickScene &&
                   quickScene->layer(songview::TimelineQuickLayer::AutomationCurves).revision >
                       curvesRevision,
               QStringLiteral("expanded Tempo occlusion did not rebuild the retained Quick "
                              "curve layer"));

        const quint64 selectionRevision =
            quickScene
                ? quickScene->layer(songview::TimelineQuickLayer::AutomationSelection).revision
                : 0;
        songview::EditorSelectionModel::TimeSelection tempoSelection;
        tempoSelection.startTick = kNodeTick;
        tempoSelection.endTick = kNodeTick + 1;
        tempoSelection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
        tempoSelection.tempo = true;
        view.selectionModel().setTimeSelection(tempoSelection);
        refresh(page, document, live);
        leaveCanvas(band);
        const auto &selectionLayer =
            quickScene->layer(songview::TimelineQuickLayer::AutomationSelection);
        report(layerHasColorIn(selectionLayer, covered, expandedCaptureOrigin,
                               themes::color(themes::Role::song_view_selection_edge)),
               QStringLiteral("Tempo selection reticle is missing from the retained Quick "
                              "covered body"));
        report(quickScene &&
                   quickScene->layer(songview::TimelineQuickLayer::AutomationSelection).revision >
                       selectionRevision,
               QStringLiteral("Tempo reticle did not rebuild the retained Quick selection "
                              "layer"));
        view.selectionModel().clearTimeSelection();
        refresh(page, document, live);
        setCcPoints(page, document, live, int(expandedCc->id.track), expandedCc->id.controller,
                    points);
    }

    const bool tempoCollapsed = toggleTempoExpanded(view, page, false, failures);
    std::optional<CcCoverageLane> collapsedCc;
    QScrollBar *const bar = scroll ? scroll->verticalScrollBar() : nullptr;
    if (tempoCollapsed && bar && bar->maximum() > bar->minimum()) {
        const int midpoint = bar->minimum() + (bar->maximum() - bar->minimum()) / 2;
        bar->setValue(midpoint);
        pump();
        collapsedCc = ccCoveredBy(page, page.canvas()->pinnedTempoRect());
    }
    report(collapsedCc.has_value(),
           QStringLiteral("mid-scroll collapsed Tempo header did not overlap a visible CC lane"));
    if (!collapsedCc && tempoCollapsed && scroll)
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
        const QPoint collapsedCaptureOrigin = automationContentToViewport(page);
        const QColor ccColor =
            themes::trackIdentityColor(collapsedCc->id.track % themes::trackIdentityColorCount);
        const quint64 curvesRevision =
            quickScene ? quickScene->layer(songview::TimelineQuickLayer::AutomationCurves).revision
                       : 0;
        setCcPoints(page, document, live, int(collapsedCc->id.track), collapsedCc->id.controller,
                    mutation);
        leaveCanvas(band);
        const auto &curves = quickScene->layer(songview::TimelineQuickLayer::AutomationCurves);
        report(tempoCollapsed && !covered.isEmpty() && !visible.isEmpty() &&
                   !layerHasColorIn(curves, covered, collapsedCaptureOrigin, ccColor) &&
                   layerHasColorIn(curves, visible, collapsedCaptureOrigin, ccColor),
               QStringLiteral("collapsed Tempo header did not clip retained Quick CC "
                              "composition"));
        report(quickScene &&
                   quickScene->layer(songview::TimelineQuickLayer::AutomationCurves).revision >
                       curvesRevision,
               QStringLiteral("collapsed Tempo occlusion did not rebuild the retained Quick "
                              "curve layer"));
        setCcPoints(page, document, live, int(collapsedCc->id.track), collapsedCc->id.controller,
                    points);
    }

    view.setDrawerSectionHeight(EditorDrawerPage::Automations, originalSectionHeight);
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
    const AutomationBandInput band{page, *automationInputItem(view)};
    const QFont originalFont = band.item.font();
    const QByteArray originalSmf = document.smf().write();
    const int originalUndoIndex = document.undoStack()->index();
    const auto originalSelection = view.selectionModel().timeSelection();
    const bool originallyExpanded = !canvas->laneBody(LaneHandle{0}).isEmpty();
    const int originalSectionHeight = view.drawerSectionHeight(EditorDrawerPage::Automations);
    auto *quickScene = view.findChild<songview::TimelineQuickScene *>();
    QAbstractItemModel *const automationTextModel =
        quickScene ? quickScene->automationTextModel() : nullptr;
    const auto firstTextRecord = [](QAbstractItemModel *model) -> std::optional<QRectF> {
        if (!model)
            return std::nullopt;
        for (int row = 0; row < model->rowCount(); ++row) {
            const QModelIndex index = model->index(row, 0);
            const QString text =
                model->data(index, songview::TimelineQuickTextModel::TextRole).toString();
            const QRectF rect =
                model->data(index, songview::TimelineQuickTextModel::RectRole).toRectF();
            const QColor color =
                model->data(index, songview::TimelineQuickTextModel::ColorRole).value<QColor>();
            if (!text.isEmpty() && !rect.isEmpty() && color.isValid() && color.alpha() > 0)
                return rect;
        }
        return std::nullopt;
    };
    QAbstractItemModel *const automationHoverTextModel =
        quickScene ? quickScene->automationHoverTextModel() : nullptr;
    const auto restore = [&] {
        typography::setUseSystemFont(false);
        band.item.setHostAppearance(originalFont, band.item.palette());
        band.item.notifyHostAppearanceChanged();
        pump();
        document.undoStack()->setIndex(originalUndoIndex);
        view.selectionModel().setTimeSelection(originalSelection);
        view.setDrawerSectionHeight(EditorDrawerPage::Automations, originalSectionHeight);
        pump();
        refresh(page, document, live);
        toggleTempoExpanded(view, page, originallyExpanded, failures);
        leaveCanvas(band);
    };
    view.selectionModel().clearTimeSelection();
    const bool expanded = toggleTempoExpanded(view, page, true, failures);
    report(expanded, QStringLiteral("Tempo header did not expose labels for font coverage"));
    TempoEdit edit;
    edit.remove = document.tempoPoints();
    edit.add = {{kHeldTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(120)},
                {kNodeTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(180)}};
    document.applyTempoEdit(edit);
    refresh(page, document, live);
    const AutomationGeometry sizingGeometry = AutomationGeometry::resolve();
    int laneStackBottom = 0;
    for (int index = 0; index < int(canvas->rows().size()); ++index)
        laneStackBottom =
            std::max(laneStackBottom, canvas->laneBody(LaneHandle{index + 1}).bottom() + 1);
    QWidget *const viewport = page.scrollViewport();
    const int neededViewportHeight = laneStackBottom + sizingGeometry.addLaneStripHeight +
                                     canvas->laneBody(LaneHandle{0}).height();
    if (viewport && neededViewportHeight > viewport->height()) {
        view.setDrawerSectionHeight(EditorDrawerPage::Automations, originalSectionHeight +
                                                                       neededViewportHeight -
                                                                       viewport->height());
        pump();
        refresh(page, document, live);
    }
    leaveCanvas(band);

    const AutomationGeometry geometry = [&] {
        auto resolved = AutomationGeometry::resolve();
        resolved.plotOrigin = canvas->plotOrigin();
        return resolved;
    }();
    const QRect body = canvas->laneBody(LaneHandle{0});
    const qreal dpr = band.item.devicePixelRatio();
    const QPoint captureOrigin = automationContentToViewport(page);
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
    report(automationTextModel && automationTextModel->rowCount() > 0,
           QStringLiteral("retained Quick automation text model was empty"));
    const QRect title = laneLabel(body, geometry, false);
    const QRect summary = laneLabel(body, geometry, true);
    const QSize viewportSize = viewport ? viewport->size() : QSize{};
    const QRectF viewportBounds(QPointF{}, QSizeF(viewportSize));
    const auto viewportLabelBounds = [&](const QRect &contentBounds) {
        return QRectF(contentBounds.translated(captureOrigin)).intersected(viewportBounds);
    };
    QRectF scrollableViewportBounds = viewportBounds;
    const QRectF tempoViewportBounds =
        QRectF(body.translated(captureOrigin)).intersected(viewportBounds);
    if (!tempoViewportBounds.isEmpty()) {
        scrollableViewportBounds.setBottom(
            std::min(scrollableViewportBounds.bottom(), tempoViewportBounds.top()));
    }
    const auto textRecord = [&](const QString &expectedText,
                                const QRectF &expectedBounds) -> std::optional<QRectF> {
        if (!automationTextModel)
            return std::nullopt;
        for (int row = 0; row < automationTextModel->rowCount(); ++row) {
            const QModelIndex index = automationTextModel->index(row, 0);
            const QString text =
                automationTextModel->data(index, songview::TimelineQuickTextModel::TextRole)
                    .toString();
            const QRectF rect =
                automationTextModel->data(index, songview::TimelineQuickTextModel::RectRole)
                    .toRectF();
            const QColor color =
                automationTextModel->data(index, songview::TimelineQuickTextModel::ColorRole)
                    .value<QColor>();
            if (!text.isEmpty() && color.isValid() && color.alpha() > 0 &&
                (expectedText.isEmpty() || text == expectedText) &&
                rect.intersects(expectedBounds)) {
                return rect;
            }
        }
        return std::nullopt;
    };
    const auto checkMainText = [&](const QString &label, const QString &expectedText,
                                   const QRectF &expectedBounds) {
        const auto record = textRecord(expectedText, expectedBounds);
        const bool placed = !expectedBounds.isEmpty() && record && !record->isEmpty() &&
                            viewportBounds.contains(*record) && expectedBounds.contains(*record);
        report(placed, QStringLiteral("%1 has no viewport-local retained Quick left-gutter record")
                           .arg(label));
    };
    report(!body.isEmpty() && !title.isEmpty() && !summary.isEmpty(),
           QStringLiteral("expanded Tempo lane has no label bounds"));
    checkMainText(QStringLiteral("Tempo title"), canvas->tr("Tempo (BPM)"),
                  viewportLabelBounds(title));
    checkMainText(QStringLiteral("Tempo summary"), QString{}, viewportLabelBounds(summary));
    const auto &visibleRows = canvas->rows();
    for (int index = 0; index < int(visibleRows.size()); ++index) {
        const QRectF bounds =
            viewportLabelBounds(labelColumn(canvas->laneBody(LaneHandle{index + 1})))
                .intersected(scrollableViewportBounds);
        if (bounds.isEmpty())
            continue;
        checkMainText(QStringLiteral("CC row %1 title").arg(index),
                      CCLanes::laneLabel(visibleRows[std::size_t(index)].id.controller), bounds);
    }
    const int addLaneTop = visibleRows.empty()
                               ? 0
                               : canvas->laneBody(LaneHandle{int(visibleRows.size())}).bottom() + 1;
    const QRect gutter = canvas->labelGutter();
    const QRect addLaneLabel(gutter.x(), addLaneTop, gutter.width(), geometry.addLaneStripHeight);
    checkMainText(QStringLiteral("Add automation lane"), canvas->tr("Add automation lane"),
                  viewportLabelBounds(addLaneLabel).intersected(scrollableViewportBounds));

    TempoLane tempoLane(document);
    const QPointF node(view.displayX(double(kNodeTick), geometry.plotOrigin, dpr),
                       nodelane::valueY(tempoLane, body, geometry, 180));
    band.mouse(QEvent::MouseMove, node, Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    pump();
    const auto hoverText = firstTextRecord(automationHoverTextModel);
    report(hoverText && !hoverText->isEmpty(),
           QStringLiteral("Tempo hover value label did not reach the retained Quick text model"));

    const QString systemFamily = typography::systemFontFamily();
    report(!systemFamily.isEmpty(), QStringLiteral("platform font family is unavailable"));
    typography::setUseSystemFont(true);
    const auto systemBody = typography::bodyFont();
    report(systemBody.has_value(), QStringLiteral("system Body font is unavailable"));
    if (!systemFamily.isEmpty() && systemBody) {
        band.item.setHostAppearance(*systemBody, band.item.palette());
        band.item.notifyHostAppearanceChanged();
        pump();
        const auto modelUsesFont = [](QAbstractItemModel *model, const QFont &expected) {
            if (!model || model->rowCount() == 0)
                return false;
            const QFontInfo expectedInfo(expected);
            for (int row = 0; row < model->rowCount(); ++row) {
                const QModelIndex index = model->index(row, 0);
                const QFont actual =
                    model->data(index, songview::TimelineQuickTextModel::FontRole).value<QFont>();
                const QFontInfo actualInfo(actual);
                if (actualInfo.family() != expectedInfo.family() ||
                    actualInfo.pixelSize() != expectedInfo.pixelSize()) {
                    return false;
                }
            }
            return true;
        };
        const auto modelHasOpaqueText = [](QAbstractItemModel *model) {
            if (!model || model->rowCount() == 0)
                return false;
            for (int row = 0; row < model->rowCount(); ++row) {
                const QModelIndex index = model->index(row, 0);
                const QString text =
                    model->data(index, songview::TimelineQuickTextModel::TextRole).toString();
                const QColor color =
                    model->data(index, songview::TimelineQuickTextModel::ColorRole).value<QColor>();
                if (text.isEmpty() || !color.isValid() || color.alpha() == 0)
                    return false;
            }
            return true;
        };
        const AutomationGeometry systemGeometry = [&] {
            auto resolved = AutomationGeometry::resolve();
            resolved.plotOrigin = canvas->plotOrigin();
            return resolved;
        }();
        const QRect systemBody = canvas->laneBody(LaneHandle{0});
        const QPointF systemNode(view.displayX(double(kNodeTick), systemGeometry.plotOrigin, dpr),
                                 nodelane::valueY(tempoLane, systemBody, systemGeometry, 180));
        band.mouse(QEvent::MouseMove, systemNode, Qt::NoButton, Qt::NoButton, Qt::NoModifier);
        pump();
        const QFont systemCaption = typography::caption(band.item.font());
        const QFont systemHover = typography::noteName(band.item.font());
        report(modelUsesFont(automationTextModel, systemCaption) &&
                   modelHasOpaqueText(automationTextModel) &&
                   modelUsesFont(automationHoverTextModel, systemHover) &&
                   modelHasOpaqueText(automationHoverTextModel),
               QStringLiteral("FontChange did not rebuild retained Quick text metrics and colors"));
        report(QFontInfo(band.item.font()).family() == systemFamily,
               QStringLiteral("AutomationCanvas did not receive the system font"));
        const auto systemHoverText = firstTextRecord(automationHoverTextModel);
        report(systemHoverText && !systemHoverText->isEmpty(),
               QStringLiteral("FontChange lost the retained Quick Tempo hover value label"));
    }

    restore();
    report(document.smf().write() == originalSmf &&
               document.undoStack()->index() == originalUndoIndex,
           QStringLiteral("font coverage did not restore the document or undo stack"));
}
