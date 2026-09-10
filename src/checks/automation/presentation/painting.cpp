#include "checks/automation/presentation/tst_automationpresentation.h"

#include <algorithm>
#include <limits>

#include <QtTest>

#include <QAbstractItemModel>
#include <QColor>
#include <QCoreApplication>
#include <QImage>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRegion>
#include <QSize>

#include "checks/support/quickframebuffer.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/editordrawer/nodelane/hover.h"
#include "ui/editordrawer/tempolane.h"
#include "ui/layout.h"
#include "ui/songview/editorselectionmodel.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/theme/themeruntime.h"
#include "ui/theme/trackidentitycolors.h"

namespace {

constexpr uint64_t kHeldTick = 48;
constexpr uint64_t kNodeTick = 96;
constexpr uint64_t kSecondTick = 144;
constexpr uint8_t kNewController = 11;

QRectF triangleBounds(const songview::TimelineQuickTriangle &triangle)
{
    const qreal left = std::min({triangle.first.x(), triangle.second.x(), triangle.third.x()});
    const qreal right = std::max({triangle.first.x(), triangle.second.x(), triangle.third.x()});
    const qreal top = std::min({triangle.first.y(), triangle.second.y(), triangle.third.y()});
    const qreal bottom = std::max({triangle.first.y(), triangle.second.y(), triangle.third.y()});
    return {QPointF(left, top), QPointF(right, bottom)};
}

QRectF visibleContentBounds(const QRect &content, int verticalScroll, const QSize &viewport)
{
    return QRectF(content.translated(0, -verticalScroll))
        .intersected(QRectF(QPointF{}, QSizeF(viewport)));
}

std::optional<QRectF> findTextRecord(const QAbstractItemModel *model, const QString &text,
                                     const QRectF &bounds)
{
    if (!model || bounds.isEmpty())
        return std::nullopt;
    for (int row = 0; row < model->rowCount(); ++row) {
        const QModelIndex index = model->index(row, 0);
        const QString actual =
            model->data(index, songview::TimelineQuickTextModel::TextRole).toString();
        const QRectF rect =
            model->data(index, songview::TimelineQuickTextModel::RectRole).toRectF();
        const QColor color =
            model->data(index, songview::TimelineQuickTextModel::ColorRole).value<QColor>();
        if (actual == text && !rect.isEmpty() && color.isValid() && color.alpha() > 0 &&
            bounds.contains(rect)) {
            return rect;
        }
    }
    return std::nullopt;
}
} // namespace

bool AutomationPresentationTest::layerHasColorIn(const songview::TimelineQuickLayerData &layer,
                                                 const QRegion &contentRegion,
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
        if (region.intersects(triangleBounds(triangle).toAlignedRect()) &&
            (triangle.firstColor == color || triangle.secondColor == color ||
             triangle.thirdColor == color)) {
            return true;
        }
    }
    return false;
}

bool AutomationPresentationTest::rowsHaveUniqueIds(const std::vector<AutomationRow> &rows)
{
    for (std::size_t left = 0; left < rows.size(); ++left) {
        for (std::size_t right = left + 1; right < rows.size(); ++right) {
            if (rows[left].id == rows[right].id)
                return false;
        }
    }
    return true;
}

std::optional<AutomationPresentationTest::CoveredCcLane>
AutomationPresentationTest::ccCoveredBy(const QRect &cover) const
{
    const AutomationPage *const automationPage = page();
    if (!automationPage || cover.isEmpty())
        return std::nullopt;
    const auto &rows = automationPage->canvas()->rows();
    for (int index = 0; index < int(rows.size()); ++index) {
        const QRect body = automationPage->canvas()->laneBody({index + 1});
        const QRect overlap = body.intersected(cover);
        if (!body.isEmpty() && !overlap.isEmpty() &&
            !QRegion(body).subtracted(QRegion(cover)).isEmpty()) {
            return CoveredCcLane{rows[std::size_t(index)].id, body, overlap};
        }
    }
    return std::nullopt;
}

std::optional<AutomationPresentationTest::CoveredCcLane>
AutomationPresentationTest::scrollToCcOverlap(int coverHeight)
{
    AutomationPage *const automationPage = page();
    if (!automationPage)
        return std::nullopt;
    const int viewportHeight = automationPage->automationViewportSize().height();
    const auto &rows = automationPage->canvas()->rows();
    for (int index = 0; index < int(rows.size()); ++index) {
        const QRect body = automationPage->canvas()->laneBody({index + 1});
        const int scroll = body.center().y() - viewportHeight + coverHeight;
        if (body.isEmpty() || scroll < 0 || scroll > maximumScroll())
            continue;
        automationPage->setVerticalScroll(scroll);
        QCoreApplication::processEvents();
        if (const auto covered = ccCoveredBy(automationPage->canvas()->pinnedTempoRect()))
            return covered;
    }
    return std::nullopt;
}

void AutomationPresentationTest::refreshDocumentPresentation()
{
    AutomationPage *const automationPage = page();
    if (!automationPage)
        return;
    automationPage->documentChanged();
    automationPage->canvas()->requestFullQuickUpdate();
    QCoreApplication::processEvents();
}

void AutomationPresentationTest::setCcPoints(
    EditorAutomationRowId row, const std::vector<SongDocument::LanePointValue> &points)
{
    if (!m_document)
        return;
    m_document->writeLanePoints(int(row.track), row.controller, 0,
                                std::numeric_limits<uint64_t>::max(), points);
    refreshDocumentPresentation();
}

std::optional<QRectF> AutomationPresentationTest::textRecord(const QString &text,
                                                             const QRectF &bounds) const
{
    songview::TimelineQuickScene *const scene = quickScene();
    return findTextRecord(scene ? scene->automationTextModel() : nullptr, text, bounds);
}

std::optional<QRectF> AutomationPresentationTest::visibleHoverTextRecord(const QString &text) const
{
    songview::TimelineQuickScene *const scene = quickScene();
    const AutomationPage *const automationPage = page();
    if (!automationPage)
        return std::nullopt;
    const QRectF viewport(QPointF{}, QSizeF(automationPage->automationViewportSize()));
    return findTextRecord(scene ? scene->automationHoverTextModel() : nullptr, text, viewport);
}

void AutomationPresentationTest::expandedTempoClipsCoveredCcCurves()
{
    AutomationPage *const automationPage = page();
    songview::TimelineQuickScene *const scene = quickScene();
    QVERIFY(automationPage);
    QVERIFY(scene);
    const AutomationGeometry geometry = AutomationGeometry::resolve();
    m_rig->view().setDrawerSectionHeight(EditorDrawerPage::Automations,
                                         2 * geometry.rowDefaultHeight);
    QCoreApplication::processEvents();
    QVERIFY(setTempoExpanded(true));
    auto covered = ccCoveredBy(automationPage->canvas()->pinnedTempoRect());
    if (!covered)
        covered = scrollToCcOverlap(automationPage->canvas()->pinnedTempoRect().height());
    QVERIFY(covered.has_value());

    const quint64 revision = scene->layer(songview::TimelineQuickLayer::AutomationCurves).revision;
    CCLaneAdapter lane(*m_document, int(covered->id.track), covered->id.controller);
    setCcPoints(covered->id, {{kHeldTick, lane.maximumValue()},
                              {kNodeTick, lane.minimumValue()},
                              {kSecondTick, lane.maximumValue()}});
    QTRY_VERIFY(scene->layer(songview::TimelineQuickLayer::AutomationCurves).revision > revision);

    const QRect tempo = automationPage->canvas()->pinnedTempoRect();
    const QRegion coveredRegion(covered->overlap);
    const QRegion visibleRegion = QRegion(covered->body).subtracted(QRegion(tempo));
    const QColor ccColor =
        themes::trackIdentityColor(int(covered->id.track) % themes::trackIdentityColorCount);
    const QPoint contentOrigin(0, -automationPage->verticalScroll());
    const auto &curves = scene->layer(songview::TimelineQuickLayer::AutomationCurves);
    QVERIFY(!coveredRegion.isEmpty());
    QVERIFY(!visibleRegion.isEmpty());
    QVERIFY(!layerHasColorIn(curves, coveredRegion, contentOrigin, ccColor));
    QVERIFY(layerHasColorIn(curves, visibleRegion, contentOrigin, ccColor));
}

void AutomationPresentationTest::tempoSelectionReticleComposedInCoveredBody()
{
    AutomationPage *const automationPage = page();
    songview::TimelineQuickScene *const scene = quickScene();
    QVERIFY(automationPage);
    QVERIFY(scene);
    const AutomationGeometry geometry = AutomationGeometry::resolve();
    m_rig->view().setDrawerSectionHeight(EditorDrawerPage::Automations,
                                         2 * geometry.rowDefaultHeight);
    QVERIFY(setTempoExpanded(true));
    auto covered = ccCoveredBy(automationPage->canvas()->pinnedTempoRect());
    if (!covered)
        covered = scrollToCcOverlap(automationPage->canvas()->pinnedTempoRect().height());
    QVERIFY(covered.has_value());

    const quint64 revision =
        scene->layer(songview::TimelineQuickLayer::AutomationSelection).revision;
    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = kHeldTick;
    selection.endTick = kSecondTick;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    selection.tempo = true;
    m_rig->view().selectionModel().setTimeSelection(selection);
    refreshDocumentPresentation();
    QTRY_VERIFY(scene->layer(songview::TimelineQuickLayer::AutomationSelection).revision >
                revision);

    const QPoint contentOrigin(0, -automationPage->verticalScroll());
    QVERIFY(layerHasColorIn(scene->layer(songview::TimelineQuickLayer::AutomationSelection),
                            QRegion(covered->overlap), contentOrigin,
                            themes::color(themes::Role::song_view_selection_edge)));
}

void AutomationPresentationTest::collapsedTempoHeaderClipsCoveredCcCurves()
{
    AutomationPage *const automationPage = page();
    songview::TimelineQuickScene *const scene = quickScene();
    QVERIFY(automationPage);
    QVERIFY(scene);
    const AutomationGeometry geometry = AutomationGeometry::resolve();
    m_rig->view().setDrawerSectionHeight(EditorDrawerPage::Automations,
                                         2 * geometry.rowDefaultHeight);
    QCoreApplication::processEvents();
    QVERIFY(setTempoExpanded(false));
    auto covered = ccCoveredBy(automationPage->canvas()->pinnedTempoRect());
    if (!covered)
        covered = scrollToCcOverlap(geometry.addLaneStripHeight);
    QVERIFY(covered.has_value());

    const quint64 revision = scene->layer(songview::TimelineQuickLayer::AutomationCurves).revision;
    CCLaneAdapter lane(*m_document, int(covered->id.track), covered->id.controller);
    setCcPoints(covered->id, {{kHeldTick, lane.maximumValue()},
                              {kNodeTick, lane.minimumValue()},
                              {kSecondTick, lane.maximumValue()}});
    QTRY_VERIFY(scene->layer(songview::TimelineQuickLayer::AutomationCurves).revision > revision);

    const QRect header = automationPage->canvas()->pinnedTempoRect();
    const QPoint contentOrigin(0, -automationPage->verticalScroll());
    const QColor ccColor =
        themes::trackIdentityColor(int(covered->id.track) % themes::trackIdentityColorCount);
    const auto &curves = scene->layer(songview::TimelineQuickLayer::AutomationCurves);
    QVERIFY(!layerHasColorIn(curves, QRegion(covered->overlap), contentOrigin, ccColor));
    QVERIFY(layerHasColorIn(curves, QRegion(covered->body).subtracted(QRegion(header)),
                            contentOrigin, ccColor));
}

void AutomationPresentationTest::tempoHeaderFillUsesTimelineChrome()
{
    AutomationPage *const automationPage = page();
    QVERIFY(automationPage);
    QVERIFY(m_quickWindow);
    QVERIFY(setTempoExpanded(false));
    refreshDocumentPresentation();

    QColor chrome = themes::color(themes::Role::song_view_timeline_chrome_background);
    chrome.setAlpha(255);
    auto *gutterFill = m_quickWindow->findChild<QQuickItem *>(
        QStringLiteral("timelineQuickTempoHeaderGutterFill"));
    auto *plotFill =
        m_quickWindow->findChild<QQuickItem *>(QStringLiteral("timelineQuickTempoHeaderPlotFill"));
    QVERIFY(gutterFill);
    QVERIFY(plotFill);

    const auto plateMatches = [&](qreal height) {
        return gutterFill->isVisible() && plotFill->isVisible() && gutterFill->height() == height &&
               plotFill->height() == height &&
               gutterFill->property("color").value<QColor>() == chrome &&
               plotFill->property("color").value<QColor>() == chrome;
    };
    const QRect collapsed = automationPage->canvas()->pinnedTempoRect();
    QVERIFY(!collapsed.isEmpty());
    QVERIFY(plateMatches(collapsed.height()));

    QVERIFY(setTempoExpanded(true));
    refreshDocumentPresentation();
    QVERIFY(plateMatches(AutomationGeometry::resolve().addLaneStripHeight));
}

void AutomationPresentationTest::gutterTextRecordsUseSemanticLabelsAndBounds()
{
    AutomationPage *const automationPage = page();
    songview::TimelineQuickScene *const scene = quickScene();
    QVERIFY(automationPage);
    QVERIFY(scene);
    QVERIFY(setTempoExpanded(true));
    TempoEdit edit;
    edit.remove = m_document->tempoPoints();
    edit.add = {{kHeldTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(120)},
                {kNodeTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(180)}};
    m_document->applyTempoEdit(edit);
    refreshDocumentPresentation();

    const auto &band =
        m_rig->view().timelineBandLayout().geometry(songview::TimelineBand::Automation);
    QVERIFY(band);
    const int gutterWidth = std::max(0, band->plotRect.x() - band->rect.x());
    const int gutterMargin = layout::space(layout::Space::One);
    const QRect gutterColumn(gutterMargin, 0, std::max(0, gutterWidth - 2 * gutterMargin),
                             automationPage->automationViewportSize().height());
    const AutomationGeometry geometry = AutomationGeometry::resolve();
    const auto labelBounds = [&](const QRect &body) {
        const int arrow = std::max(layout::fontPx(0.5), geometry.addLaneStripHeight / 3);
        return QRect(gutterColumn.x() + arrow + layout::space(layout::Space::One), body.top(),
                     std::max(0, gutterColumn.width() - arrow - layout::space(layout::Space::One)),
                     geometry.addLaneStripHeight)
            .intersected(body);
    };
    const QRect tempoBody = automationPage->canvas()->laneBody(LaneHandle{0});
    const QRectF tempoTitle =
        visibleContentBounds(labelBounds(tempoBody), automationPage->verticalScroll(),
                             automationPage->automationViewportSize());
    QVERIFY(textRecord(automationPage->canvas()->tr("Tempo (BPM)"), tempoTitle).has_value());
    const auto &rows = automationPage->canvas()->rows();
    for (int index = 0; index < int(rows.size()); ++index) {
        const QRect body = automationPage->canvas()->laneBody({index + 1});
        const QRectF bounds = visibleContentBounds(
            QRect(gutterColumn.x(), body.top(), gutterColumn.width(), body.height()),
            automationPage->verticalScroll(), automationPage->automationViewportSize());
        if (!bounds.isEmpty()) {
            QVERIFY(textRecord(CCLanes::laneLabel(rows[std::size_t(index)].id.controller), bounds)
                        .has_value());
        }
    }
    const int addLaneTop =
        rows.empty() ? 0 : automationPage->canvas()->laneBody({int(rows.size())}).bottom() + 1;
    const QRectF addLaneBounds = visibleContentBounds(
        QRect(gutterColumn.x(), addLaneTop, gutterColumn.width(), geometry.addLaneStripHeight),
        automationPage->verticalScroll(), automationPage->automationViewportSize());
    QVERIFY(
        textRecord(automationPage->canvas()->tr("Add automation lane"), addLaneBounds).has_value());
}

void AutomationPresentationTest::tempoHoverValueHasVisibleTextRecord()
{
    AutomationPage *const automationPage = page();
    QVERIFY(automationPage);
    QVERIFY(setTempoExpanded(true));
    TempoEdit edit;
    edit.add = {{kNodeTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(180)}};
    m_document->applyTempoEdit(edit);
    refreshDocumentPresentation();
    TempoLane lane(*m_document);
    const QRect body = automationPage->canvas()->laneBody(LaneHandle{0});
    const QPointF point(
        m_rig->view().camera().displayX(double(kNodeTick), 0.0, m_plotInput->devicePixelRatio()),
        nodelane::valueY(lane, body, AutomationGeometry::resolve(), 180));
    const auto &band =
        m_rig->view().timelineBandLayout().geometry(songview::TimelineBand::Automation);
    QVERIFY(band);
    const QImage before = checks::support::captureQuickBand(m_rig->view(), band->rect);
    QVERIFY(!before.isNull());
    mouseMove(*m_plotInput, point);
    QTRY_VERIFY(visibleHoverTextRecord(lane.valueText(180)).has_value());
    const QImage after = checks::support::captureQuickBand(m_rig->view(), band->rect);
    QVERIFY(!after.isNull());
    QVERIFY(after != before);
}

void AutomationPresentationTest::addingEmptyLanePreservesLfoSemanticTitleAndUniqueRows()
{
    AutomationPage *const automationPage = page();
    songview::TimelineQuickScene *const scene = quickScene();
    QVERIFY(automationPage);
    QVERIFY(scene);
    const EditorAutomationRowId lfoId{EditorAutomationRowKind::ControlChange, 0, 21};
    const LaneHandle beforeHandle = findRow(lfoId);
    QVERIFY(beforeHandle.valid());
    const QRect beforeBody = automationPage->canvas()->laneBody(beforeHandle);
    const QRectF beforeBounds = visibleContentBounds(beforeBody, automationPage->verticalScroll(),
                                                     automationPage->automationViewportSize());
    const QString lfoTitle = CCLanes::laneLabel(lfoId.controller);
    QVERIFY(textRecord(lfoTitle, beforeBounds).has_value());
    const auto &band =
        m_rig->view().timelineBandLayout().geometry(songview::TimelineBand::Automation);
    QVERIFY(band);
    const int gutterWidth = std::max(0, band->plotRect.x() - band->rect.x());
    const auto captureLfoGutter = [&](const QRect &body) {
        const QRect viewport =
            QRect(0, body.top() - automationPage->verticalScroll(), gutterWidth, body.height());
        if (!QRect(QPoint{}, automationPage->automationViewportSize()).contains(viewport))
            return QImage{};
        return checks::support::captureQuickBand(
            m_rig->view(), QRect(band->rect.x(), band->rect.y() + viewport.y(), viewport.width(),
                                 viewport.height()));
    };
    const QImage beforePixels = captureLfoGutter(beforeBody);
    QVERIFY(!beforePixels.isNull());
    const quint64 gridRevision =
        scene->layer(songview::TimelineQuickLayer::AutomationGrid).revision;

    automationPage->addEmptyLane(0, kNewController);
    QCoreApplication::processEvents();
    const LaneHandle afterHandle = findRow(lfoId);
    const EditorAutomationRowId newId{EditorAutomationRowKind::ControlChange, 0, kNewController};
    const LaneHandle newHandle = findRow(newId);
    QVERIFY(afterHandle.valid());
    QVERIFY(newHandle.valid());
    const QRectF afterBounds = visibleContentBounds(automationPage->canvas()->laneBody(afterHandle),
                                                    automationPage->verticalScroll(),
                                                    automationPage->automationViewportSize());
    const QRectF newBounds = visibleContentBounds(automationPage->canvas()->laneBody(newHandle),
                                                  automationPage->verticalScroll(),
                                                  automationPage->automationViewportSize());
    QVERIFY(textRecord(lfoTitle, afterBounds).has_value());
    QVERIFY(textRecord(CCLanes::laneLabel(kNewController), newBounds).has_value());
    const QImage afterPixels = captureLfoGutter(automationPage->canvas()->laneBody(afterHandle));
    QVERIFY(!afterPixels.isNull());
    QCOMPARE(afterPixels, beforePixels);
    QVERIFY(rowsHaveUniqueIds(automationPage->canvas()->rows()));
    QVERIFY(scene->layer(songview::TimelineQuickLayer::AutomationGrid).revision > gridRevision);
}
