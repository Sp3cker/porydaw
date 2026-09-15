#include "checks/automation/presentation/tst_automationpresentation.h"

#include <algorithm>
#include <array>
#include <cmath>

#include <QtTest>

#include <QAbstractItemModel>
#include <QColor>
#include <QCoreApplication>
#include <QImage>
#include <QQuickItem>
#include <QRegion>
#include <QSize>
#include <QVariant>

#include "checks/support/quickframebuffer.h"
#include "checks/support/timelinequickcheck.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/nodelane/hover.h"
#include "ui/editordrawer/tempolane.h"
#include "ui/layout.h"
#include "ui/songview/editorselectionmodel.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/theme/themeruntime.h"
#include "ui/theme/trackidentitycolors.h"

namespace {

constexpr int kTrack = 0;
constexpr Tick kHeldTick = 48;
constexpr Tick kNodeTick = 96;
constexpr Tick kSecondTick = 144;

QRectF triangleBounds(const songview::TimelineQuickTriangle &triangle)
{
    const qreal left = std::min({triangle.first.x(), triangle.second.x(), triangle.third.x()});
    const qreal right = std::max({triangle.first.x(), triangle.second.x(), triangle.third.x()});
    const qreal top = std::min({triangle.first.y(), triangle.second.y(), triangle.third.y()});
    const qreal bottom = std::max({triangle.first.y(), triangle.second.y(), triangle.third.y()});
    return {QPointF(left, top), QPointF(right, bottom)};
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

void AutomationPresentationTest::refreshDocumentPresentation()
{
    AutomationPage *const automationPage = page();
    if (!automationPage)
        return;
    automationPage->documentChanged();
    automationPage->canvas()->requestFullQuickUpdate();
    QCoreApplication::processEvents();
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

void AutomationPresentationTest::parameterLabelsFitGutterAtDerivedMinimum()
{
    AutomationPage *const automationPage = page();
    AutomationCanvas *const canvas = automationPage ? automationPage->canvas() : nullptr;
    QVERIFY(automationPage);
    QVERIFY(canvas);
    const QStringList expected{
        QStringLiteral("Volume"),      QStringLiteral("Pan"),         QStringLiteral("Modulation"),
        QStringLiteral("Pitch bend"),  QStringLiteral("LFO speed"),   QStringLiteral("Bend range"),
        QStringLiteral("Echo volume"), QStringLiteral("Echo length"), QStringLiteral("Tempo")};
    QCOMPARE(canvas->parameterLabels(), expected);
    const std::array<uint8_t, 8> controllers{CoreTimeDefaults::kCcVolume,
                                             CoreTimeDefaults::kCcPan,
                                             CoreTimeDefaults::kCcModulation,
                                             CoreTimeDefaults::kLaneCcBend,
                                             CoreTimeDefaults::kCcLfoSpeed,
                                             CoreTimeDefaults::kCcBendRange,
                                             uint8_t{0xFB},
                                             uint8_t{0xFC}};
    for (int index = 0; index < int(controllers.size()); ++index) {
        const auto row = canvas->parameterRow(index);
        QVERIFY(row.has_value());
        QVERIFY((*row == EditorAutomationRowId{EditorAutomationRowKind::ControlChange, kTrack,
                                               controllers[std::size_t(index)]}));
    }
    const auto tempoRow = canvas->parameterRow(expected.size() - 1);
    QVERIFY(tempoRow.has_value());
    QVERIFY((*tempoRow == EditorAutomationRowId{EditorAutomationRowKind::Tempo, 0, 0}));

    EditorDrawer *const drawer = m_rig->view().editorDrawer();
    QVERIFY(drawer);
    const int minimumHeight = drawer->minimumSectionHeight();
    QVERIFY(minimumHeight > 0);
    const int originalHeight = m_rig->view().drawerSectionHeight(EditorDrawerPage::Automations);
    m_rig->view().setDrawerSectionHeight(EditorDrawerPage::Automations, minimumHeight);
    QTRY_COMPARE(automationPage->automationViewportSize().height(), minimumHeight);
    QVERIFY(m_gutterInput);
    QTRY_COMPARE(qCeil(m_gutterInput->height()), minimumHeight);
    const QRectF gutter = m_gutterInput->mapRectToScene(m_gutterInput->boundingRect());

    std::vector<QPointF> centers;
    std::vector<QRectF> labelBounds;
    for (int index = 0; index < expected.size(); ++index) {
        QQuickItem *tab = nullptr;
        QTRY_VERIFY((tab = parameterLabelItem(index)) && tab->isVisible() && tab->width() > 0.0 &&
                    tab->height() > 0.0);
        const QRectF bounds = tab->mapRectToScene(tab->boundingRect());
        QVERIFY2(!bounds.isEmpty() && bounds.left() >= gutter.left() - layout::singlePixel() &&
                     bounds.right() <= gutter.right() + layout::singlePixel(),
                 "a label escaped the gutter's width");
        for (const QPointF center : centers) {
            QVERIFY(std::abs(center.x() - bounds.center().x()) > layout::singlePixel() ||
                    std::abs(center.y() - bounds.center().y()) > layout::singlePixel());
        }
        centers.push_back(bounds.center());
        labelBounds.push_back(bounds);

        QQuickItem *const content = tab->property("contentItem").value<QQuickItem *>();
        QVERIFY2(content, "a catalog label rendered without its content item");
        QQuickItem *const text = content->findChild<QQuickItem *>(
            QStringLiteral("automationParameterTabText"), Qt::FindDirectChildrenOnly);
        QVERIFY2(text, "a catalog label rendered without its Text item");
        QCOMPARE(text->property("text").toString(), expected.at(index));
        const qreal contentWidth = text->property("contentWidth").toReal();
        const qreal contentHeight = text->property("contentHeight").toReal();
        QVERIFY(contentWidth > 0.0 && contentHeight > 0.0);
        QVERIFY2(contentWidth <= text->width() + 0.5,
                 "the rendered fitted Text exceeds its label width");
        QVERIFY2(contentHeight <= text->height() + 0.5,
                 "the rendered fitted Text exceeds its label height");
    }

    const QVariantList pips = canvas->parameterPips();
    QCOMPARE(pips.size(), expected.size());
    for (int index = 0; index < expected.size(); ++index) {
        const auto row = canvas->parameterRow(index);
        QVERIFY(row.has_value());
        const bool written = row->kind == EditorAutomationRowKind::Tempo
                                 ? !m_document->tempoPoints().empty()
                                 : !m_document->lanePoints(row->track, row->controller).empty();
        QCOMPARE(pips.at(index).toBool(), written);
    }

    // The selector keeps the catalog's grouping visible: each related pair
    // shares one row, and song-global Tempo closes the grid on its own wider
    // row instead of joining a pair.
    QCOMPARE(labelBounds.size(), static_cast<std::size_t>(expected.size()));
    const std::size_t pairedLabels = labelBounds.size() - 1;
    for (std::size_t pair = 0; pair < pairedLabels; pair += 2) {
        QVERIFY2(std::abs(labelBounds.at(pair).center().y() -
                          labelBounds.at(pair + 1).center().y()) <= layout::singlePixel(),
                 "a related parameter pair no longer shares a selector row");
    }
    const QRectF &tempoBounds = labelBounds.back();
    QVERIFY2(tempoBounds.center().y() > labelBounds.front().center().y(),
             "the song-global Tempo label no longer closes the selector grid");
    QVERIFY2(tempoBounds.width() > labelBounds.front().width() * 1.5,
             "the song-global Tempo label no longer spans the closing selector row");

    QQuickItem *const scroller = checks::support::automationTabsScroller(m_rig->quickRoot());
    QVERIFY(scroller);
    QVERIFY(scroller->property("clip").toBool());
    scroller->setProperty("contentY", QVariant::fromValue(0.0));
    QTRY_VERIFY(scroller->property("contentHeight").toReal() > scroller->height());
    const QRectF viewport = scroller->mapRectToScene(scroller->boundingRect());
    QVERIFY2(checks::support::rectInside(labelBounds.front(), viewport),
             "the first tab is not visible at the content top");
    const qreal maximumContentY = scroller->property("contentHeight").toReal() - scroller->height();
    QVERIFY(maximumContentY > 0.0);
    scroller->setProperty("contentY", QVariant::fromValue(maximumContentY));
    QQuickItem *const lastTab = parameterLabelItem(int(expected.size()) - 1);
    QVERIFY(lastTab);
    QTRY_VERIFY(
        checks::support::rectInside(lastTab->mapRectToScene(lastTab->boundingRect()), viewport));
    scroller->setProperty("contentY", QVariant::fromValue(0.0));
    m_rig->view().setDrawerSectionHeight(EditorDrawerPage::Automations, originalHeight);
}

void AutomationPresentationTest::parameterLabelClicksSwitchActivePlot()
{
    AutomationPage *const automationPage = page();
    songview::TimelineQuickScene *const scene = quickScene();
    AutomationCanvas *const canvas = automationPage ? automationPage->canvas() : nullptr;
    QVERIFY(automationPage);
    QVERIFY(scene);
    QVERIFY(canvas);

    const QByteArray before = m_document->smf().write();
    const QStringList labels = canvas->parameterLabels();
    for (int index = 0; index < labels.size(); ++index) {
        const auto row = canvas->parameterRow(index);
        QVERIFY(row.has_value());
        QVERIFY2(activateParameter(*row), qUtf8Printable(labels.at(index)));
        QCOMPARE(canvas->activeParameter(), index);
    }
    QCOMPARE(m_document->smf().write(), before);

    const EditorAutomationRowId volume{EditorAutomationRowKind::ControlChange, kTrack,
                                       CoreTimeDefaults::kCcVolume};
    const EditorAutomationRowId pan{EditorAutomationRowKind::ControlChange, kTrack,
                                    CoreTimeDefaults::kCcPan};
    const EditorAutomationRowId lfo{EditorAutomationRowKind::ControlChange, kTrack,
                                    CoreTimeDefaults::kCcLfoSpeed};
    const LaneHandle volumeHandle = findRow(volume);
    const LaneHandle panHandle = findRow(pan);
    const LaneHandle lfoHandle = findRow(lfo);
    QVERIFY(volumeHandle.valid());
    QVERIFY(panHandle.valid());
    QVERIFY(lfoHandle.valid());
    const qreal radius = AutomationGeometry::resolve().nodePaintRadius + layout::singlePixel();
    const auto nodeRegion = [radius](QPointF center) {
        return QRegion(QRectF(center.x() - radius, center.y() - radius, 2.0 * radius, 2.0 * radius)
                           .toAlignedRect());
    };
    const QRegion volumeNode = nodeRegion(lanePoint(volumeHandle, 24, 48));
    const QRegion panNode = nodeRegion(lanePoint(panHandle, 48, 32));
    const QRegion lfoNode = nodeRegion(lanePoint(lfoHandle, 96, 96));
    const QColor ccColor = themes::color(themes::Role::song_view_automation_node_ink);

    QVERIFY(activateParameter(volume));
    QTRY_VERIFY(layerHasColorIn(scene->layer(songview::TimelineQuickLayer::AutomationNodes),
                                volumeNode, QPoint{}, ccColor));
    QVERIFY(!layerHasColorIn(scene->layer(songview::TimelineQuickLayer::AutomationNodes), lfoNode,
                             QPoint{}, ccColor));

    QVERIFY(activateParameter(lfo));
    QTRY_VERIFY(layerHasColorIn(scene->layer(songview::TimelineQuickLayer::AutomationNodes),
                                lfoNode, QPoint{}, ccColor));
    QVERIFY(!layerHasColorIn(scene->layer(songview::TimelineQuickLayer::AutomationNodes),
                             volumeNode, QPoint{}, ccColor));

    QVERIFY(activateParameter(pan));
    QTRY_VERIFY(layerHasColorIn(scene->layer(songview::TimelineQuickLayer::AutomationNodes),
                                panNode, QPoint{}, ccColor));
    QVERIFY(!layerHasColorIn(scene->layer(songview::TimelineQuickLayer::AutomationNodes), lfoNode,
                             QPoint{}, ccColor));

    TempoEdit edit;
    edit.remove = m_document->tempoPoints();
    edit.add = {{kNodeTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(180)}};
    m_document->applyTempoEdit(edit);
    refreshDocumentPresentation();
    const EditorAutomationRowId tempo{EditorAutomationRowKind::Tempo, 0, 0};
    QVERIFY(activateParameter(tempo));
    const QRect body = canvas->laneBody(LaneHandle{0});
    const QColor tempoColor = themes::color(themes::Role::song_view_automation_node_ink);
    QTRY_VERIFY(layerHasColorIn(scene->layer(songview::TimelineQuickLayer::AutomationCurves),
                                QRegion(body), QPoint{}, tempoColor));
    QVERIFY(!layerHasColorIn(scene->layer(songview::TimelineQuickLayer::AutomationCurves),
                             QRegion(body), QPoint{},
                             themes::trackIdentityColor(kTrack % themes::trackIdentityColorCount)));
}

void AutomationPresentationTest::tempoUsesFullSharedPlotBody()
{
    AutomationPage *const automationPage = page();
    songview::TimelineQuickScene *const scene = quickScene();
    AutomationCanvas *const canvas = automationPage ? automationPage->canvas() : nullptr;
    QVERIFY(automationPage);
    QVERIFY(scene);
    QVERIFY(canvas);
    const EditorAutomationRowId tempo{EditorAutomationRowKind::Tempo, 0, 0};
    const EditorAutomationRowId volume{EditorAutomationRowKind::ControlChange, kTrack,
                                       CoreTimeDefaults::kCcVolume};
    QVERIFY(activateParameter(tempo));
    const QRect tempoBody = canvas->laneBody(LaneHandle{0});
    const LaneHandle volumeHandle = findRow(volume);
    QVERIFY(volumeHandle.valid());
    QCOMPARE(tempoBody, canvas->laneBody(volumeHandle));
    QCOMPARE(tempoBody, m_plotInput->bounds().toAlignedRect());
    QVERIFY(!tempoBody.isEmpty());

    TempoEdit edit;
    edit.remove = m_document->tempoPoints();
    edit.add = {{kHeldTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(120)}};
    m_document->applyTempoEdit(edit);
    refreshDocumentPresentation();
    const QColor tempoColor = themes::color(themes::Role::song_view_automation_node_ink);
    QTRY_VERIFY(layerHasColorIn(scene->layer(songview::TimelineQuickLayer::AutomationCurves),
                                QRegion(tempoBody), QPoint{}, tempoColor));
}

void AutomationPresentationTest::ghostTempoPaintsUnderActiveLane()
{
    AutomationPage *const automationPage = page();
    songview::TimelineQuickScene *const scene = quickScene();
    AutomationCanvas *const canvas = automationPage ? automationPage->canvas() : nullptr;
    QVERIFY(automationPage);
    QVERIFY(scene);
    QVERIFY(canvas);
    const EditorAutomationRowId tempo{EditorAutomationRowKind::Tempo, 0, 0};
    const EditorAutomationRowId volume{EditorAutomationRowKind::ControlChange, kTrack,
                                       CoreTimeDefaults::kCcVolume};
    QVERIFY(activateParameter(volume));
    TempoEdit edit;
    edit.remove = m_document->tempoPoints();
    edit.add = {{kHeldTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(120)}};
    m_document->applyTempoEdit(edit);
    refreshDocumentPresentation();
    const QRect body = canvas->laneBody(LaneHandle{0});
    const QColor ink = themes::color(themes::Role::song_view_automation_node_ink);
    QColor ghostInk = ink;
    ghostInk.setAlphaF(0.5);
    QVERIFY(!layerHasColorIn(scene->layer(songview::TimelineQuickLayer::AutomationCurves),
                             QRegion(body), QPoint{}, ghostInk));
    QTRY_VERIFY(layerHasColorIn(scene->layer(songview::TimelineQuickLayer::AutomationCurves),
                                QRegion(body), QPoint{}, ink));
    const int tempoIndex = checks::support::automationParameterIndex(*canvas, tempo);
    QVERIFY(tempoIndex >= 0);
    canvas->toggleGhostParameter(tempoIndex);
    QTRY_VERIFY(layerHasColorIn(scene->layer(songview::TimelineQuickLayer::AutomationCurves),
                                QRegion(body), QPoint{}, ghostInk));
    QTRY_VERIFY(layerHasColorIn(scene->layer(songview::TimelineQuickLayer::AutomationCurves),
                                QRegion(body), QPoint{}, ink));
    canvas->toggleGhostParameter(tempoIndex);
    QVERIFY(canvas->ghostParameters().isEmpty());
    QTRY_VERIFY(!layerHasColorIn(scene->layer(songview::TimelineQuickLayer::AutomationCurves),
                                 QRegion(body), QPoint{}, ghostInk));
}

void AutomationPresentationTest::drawerGrowthMovesValueAxisKeepsGridAlignment()
{
    AutomationPage *const automationPage = page();
    songview::TimelineQuickScene *const scene = quickScene();
    AutomationCanvas *const canvas = automationPage ? automationPage->canvas() : nullptr;
    QVERIFY(automationPage);
    QVERIFY(scene);
    QVERIFY(canvas);
    const EditorAutomationRowId volume{EditorAutomationRowKind::ControlChange, kTrack,
                                       CoreTimeDefaults::kCcVolume};
    QVERIFY(activateParameter(volume));
    const LaneHandle volumeHandle = findRow(volume);
    QVERIFY(volumeHandle.valid());
    const QRect beforeBody = canvas->laneBody(volumeHandle);
    const qreal beforeValueY = lanePoint(volumeHandle, 24, 48).y();
    const auto gridCenters = [&scene](const QRect &body) {
        std::vector<qreal> centers;
        for (const songview::TimelineQuickRect &rect :
             scene->layer(songview::TimelineQuickLayer::AutomationGrid).rects) {
            if (rect.rect.width() <= 2.0 * layout::singlePixel() &&
                rect.rect.height() >= body.height() - layout::singlePixel()) {
                centers.push_back(rect.rect.center().x());
            }
        }
        std::sort(centers.begin(), centers.end());
        centers.erase(std::unique(centers.begin(), centers.end()), centers.end());
        return centers;
    };
    const std::vector<qreal> beforeGrid = gridCenters(beforeBody);
    QVERIFY(!beforeGrid.empty());

    const int originalHeight = m_rig->view().drawerSectionHeight(EditorDrawerPage::Automations);
    m_rig->view().setDrawerSectionHeight(EditorDrawerPage::Automations,
                                         originalHeight + layout::fontPx(3.0));
    QTRY_VERIFY(canvas->laneBody(volumeHandle).height() > beforeBody.height());
    const QRect afterBody = canvas->laneBody(volumeHandle);
    const qreal afterValueY = lanePoint(volumeHandle, 24, 48).y();
    QVERIFY(beforeValueY != afterValueY);
    const auto sameGridCenters = [](const std::vector<qreal> &first,
                                    const std::vector<qreal> &second) {
        return first.size() == second.size() &&
               std::equal(first.begin(), first.end(), second.begin(), [](qreal left, qreal right) {
                   return std::abs(left - right) <= layout::singlePixel();
               });
    };
    QTRY_VERIFY(sameGridCenters(beforeGrid, gridCenters(afterBody)));

    const QColor separator = themes::color(themes::Role::song_view_separator);
    const auto hasFrame = [&scene, &afterBody, &separator](qreal y) {
        for (const songview::TimelineQuickRect &rect :
             scene->layer(songview::TimelineQuickLayer::AutomationGrid).rects) {
            if (rect.rect.width() >= afterBody.width() - layout::singlePixel() &&
                std::abs(rect.rect.center().y() - y) <= layout::singlePixel() &&
                (rect.topLeft == separator || rect.topRight == separator ||
                 rect.bottomLeft == separator || rect.bottomRight == separator)) {
                return true;
            }
        }
        return false;
    };
    QVERIFY(hasFrame(QRectF(afterBody).top()));
    QVERIFY(hasFrame(QRectF(afterBody).bottom()));
    m_rig->view().setDrawerSectionHeight(EditorDrawerPage::Automations, originalHeight);
}

void AutomationPresentationTest::selectedInactiveParametersKeepScopeIndicators()
{
    AutomationPage *const automationPage = page();
    AutomationCanvas *const canvas = automationPage ? automationPage->canvas() : nullptr;
    QVERIFY(automationPage);
    QVERIFY(canvas);
    const EditorAutomationRowId pan{EditorAutomationRowKind::ControlChange, kTrack,
                                    CoreTimeDefaults::kCcPan};
    const EditorAutomationRowId lfo{EditorAutomationRowKind::ControlChange, kTrack,
                                    CoreTimeDefaults::kCcLfoSpeed};
    const EditorAutomationRowId tempo{EditorAutomationRowKind::Tempo, 0, 0};
    const EditorAutomationRowId modulation{EditorAutomationRowKind::ControlChange, kTrack,
                                           CoreTimeDefaults::kCcModulation};
    QVERIFY(activateParameter(pan));
    const int panIndex = checks::support::automationParameterIndex(*canvas, pan);
    const int lfoIndex = checks::support::automationParameterIndex(*canvas, lfo);
    const int tempoIndex = checks::support::automationParameterIndex(*canvas, tempo);
    const int modulationIndex = checks::support::automationParameterIndex(*canvas, modulation);
    QVERIFY(panIndex >= 0 && lfoIndex >= 0 && tempoIndex >= 0 && modulationIndex >= 0);

    TempoEdit edit;
    edit.remove = m_document->tempoPoints();
    edit.add = {{kNodeTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(120)}};
    m_document->applyTempoEdit(edit);
    refreshDocumentPresentation();

    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = kHeldTick;
    selection.endTick = kSecondTick;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    selection.tempo = true;
    selection.lanes.push_back({kTrack, CoreTimeDefaults::kCcLfoSpeed});
    selection.lanes.push_back({kTrack, CoreTimeDefaults::kCcModulation});
    m_rig->view().selectionModel().setTimeSelection(selection);
    refreshDocumentPresentation();
    const QList<int> expectedSelected{lfoIndex, tempoIndex};
    QTRY_VERIFY(canvas->selectedParameters() == expectedSelected);
    QVERIFY(!canvas->selectedParameters().contains(modulationIndex));

    QQuickItem *const panTab = parameterLabelItem(panIndex);
    QQuickItem *const lfoTab = parameterLabelItem(lfoIndex);
    QQuickItem *const tempoTab = parameterLabelItem(tempoIndex);
    QVERIFY(panTab);
    QVERIFY(lfoTab);
    QVERIFY(tempoTab);
    QQuickItem *const panBackground = panTab->property("background").value<QQuickItem *>();
    QQuickItem *const lfoBackground = lfoTab->property("background").value<QQuickItem *>();
    QQuickItem *const tempoBackground = tempoTab->property("background").value<QQuickItem *>();
    QVERIFY(panBackground);
    QVERIFY(lfoBackground);
    QVERIFY(tempoBackground);
    const QVariantMap appearance = canvas->parameterAppearance();
    QCOMPARE(panBackground->property("color").value<QColor>(),
             appearance.value(QStringLiteral("tabSelectedBackground")).value<QColor>());
    QCOMPARE(lfoBackground->property("color").value<QColor>(),
             appearance.value(QStringLiteral("tabBackground")).value<QColor>());
    QCOMPARE(tempoBackground->property("color").value<QColor>(),
             appearance.value(QStringLiteral("tabBackground")).value<QColor>());

    const auto &band =
        m_rig->view().timelineBandLayout().geometry(songview::TimelineBand::Automation);
    QVERIFY(band);
    const QImage image = checks::support::captureQuickBand(m_rig->view(), band->rect);
    QVERIFY(!image.isNull());
    const QColor selectionBar =
        appearance.value(QStringLiteral("tabSelectedBackground")).value<QColor>();
    const auto containsOutline = [&image](const QRect &rect, QColor color) {
        color.setAlpha(255);
        const QRect pixels = checks::support::devicePixelRect(image, rect);
        for (int y = pixels.top(); y <= pixels.bottom(); ++y) {
            for (int x = pixels.left(); x <= pixels.right(); ++x) {
                if (image.pixelColor(x, y).rgb() == color.rgb())
                    return true;
            }
        }
        return false;
    };
    const auto localBounds = [&band](QQuickItem *item) {
        return item->mapRectToScene(item->boundingRect())
            .toAlignedRect()
            .translated(-band->rect.topLeft());
    };
    QVERIFY2(containsOutline(localBounds(lfoTab), selectionBar),
             "the inactive LFO label has no visible shared-selection indicator");
    QVERIFY2(containsOutline(localBounds(tempoTab), selectionBar),
             "the inactive Tempo label has no visible shared-selection indicator");
    const QColor ghostRule = appearance.value(QStringLiteral("selectionOutline")).value<QColor>();
    QVERIFY2(!containsOutline(localBounds(lfoTab), ghostRule),
             "the shared selection leaked onto the ghost rule");
    QVERIFY2(!containsOutline(localBounds(tempoTab), ghostRule),
             "the shared selection leaked onto the ghost rule");
}

void AutomationPresentationTest::tempoHoverValueHasVisibleTextRecord()
{
    AutomationPage *const automationPage = page();
    AutomationCanvas *const canvas = automationPage ? automationPage->canvas() : nullptr;
    QVERIFY(automationPage);
    QVERIFY(canvas);
    QVERIFY(activateParameter({EditorAutomationRowKind::Tempo, 0, 0}));
    constexpr int bpm = CoreTimeDefaults::kMaxTempoBpm;
    TempoEdit edit;
    edit.remove = m_document->tempoPoints();
    edit.add = {{kNodeTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(bpm)}};
    m_document->applyTempoEdit(edit);
    refreshDocumentPresentation();
    TempoLane lane(*m_document);
    const QRect body = canvas->laneBody(LaneHandle{0});
    const QPointF point(
        m_rig->view().camera().displayX(double(kNodeTick), 0.0, m_plotInput->devicePixelRatio()),
        nodelane::valueY(lane, body, AutomationGeometry::resolve(), bpm));
    const auto &band =
        m_rig->view().timelineBandLayout().geometry(songview::TimelineBand::Automation);
    QVERIFY(band);
    const QImage before = checks::support::captureQuickBand(m_rig->view(), band->rect);
    QVERIFY(!before.isNull());
    mouseMove(*m_plotInput, point);
    std::optional<QRectF> label;
    QTRY_VERIFY((label = visibleHoverTextRecord(lane.valueText(bpm))).has_value());
    QVERIFY(QRectF(QPointF{}, QSizeF(automationPage->automationViewportSize())).contains(*label));
    const QImage after = checks::support::captureQuickBand(m_rig->view(), band->rect);
    QVERIFY(!after.isNull());
    QVERIFY(after != before);
}

void AutomationPresentationTest::ghostLabelNamesCurveAndFollowsHover()
{
    AutomationPage *const automationPage = page();
    songview::TimelineQuickScene *const scene = quickScene();
    AutomationCanvas *const canvas = automationPage ? automationPage->canvas() : nullptr;
    QVERIFY(automationPage);
    QVERIFY(scene);
    QVERIFY(canvas);
    const EditorAutomationRowId tempo{EditorAutomationRowKind::Tempo, 0, 0};
    const EditorAutomationRowId volume{EditorAutomationRowKind::ControlChange, kTrack,
                                       CoreTimeDefaults::kCcVolume};
    QVERIFY(activateParameter(volume));
    TempoEdit edit;
    edit.remove = m_document->tempoPoints();
    edit.add = {{kHeldTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(120)}};
    m_document->applyTempoEdit(edit);
    refreshDocumentPresentation();
    const QRectF viewport(QPointF{}, QSizeF(automationPage->automationViewportSize()));
    const QAbstractItemModel *const ghostModel = scene->automationLaneTextModel();
    QVERIFY(ghostModel);

    const int tempoIndex = checks::support::automationParameterIndex(*canvas, tempo);
    QVERIFY(tempoIndex >= 0);
    canvas->toggleGhostParameter(tempoIndex);

    std::optional<QRectF> label;
    QTRY_VERIFY((label = findTextRecord(ghostModel, QStringLiteral("Tempo · 1 Event"), viewport))
                    .has_value());
    QVERIFY2(label->right() <= viewport.right() && label->right() > viewport.right() * 0.5,
             "the ghost name label no longer hugs the plot's right edge");
    TempoLane lane(*m_document);
    const QRect body = canvas->laneBody(LaneHandle{0});
    const qreal curveY = nodelane::valueY(lane, body, AutomationGeometry::resolve(), 120);
    QVERIFY2(std::abs(label->center().y() - curveY) <= label->height(),
             "the ghost name label no longer tracks its curve's height");
    QVERIFY(!findTextRecord(ghostModel, QStringLiteral("Volume"), viewport).has_value());

    const QPointF hoverPoint(viewport.width() / 2.0, curveY);
    mouseMove(*m_plotInput, hoverPoint);
    QTRY_VERIFY((label = findTextRecord(scene->automationHoverTextModel(), QStringLiteral("Tempo"),
                                        viewport))
                    .has_value());
    QVERIFY2(std::abs(label->center().x() - hoverPoint.x()) <= label->width(),
             "the ghost hover label no longer tracks the pointer horizontally");
    QVERIFY2(label->bottom() <= curveY, "the ghost hover label no longer sits above the nodeline");
    QVERIFY(!findTextRecord(ghostModel, QStringLiteral("Tempo"), viewport).has_value());

    canvas->toggleGhostParameter(tempoIndex);
    QVERIFY(canvas->ghostParameters().isEmpty());
    QTRY_VERIFY(!findTextRecord(ghostModel, QStringLiteral("Tempo"), viewport).has_value());
    QTRY_VERIFY(
        !findTextRecord(scene->automationHoverTextModel(), QStringLiteral("Tempo"), viewport)
             .has_value());
}

void AutomationPresentationTest::laneEventCountsRenderAtLeftEdge()
{
    AutomationPage *const automationPage = page();
    songview::TimelineQuickScene *const scene = quickScene();
    AutomationCanvas *const canvas = automationPage ? automationPage->canvas() : nullptr;
    QVERIFY(automationPage);
    QVERIFY(scene);
    QVERIFY(canvas);
    const QRectF viewport(QPointF{}, QSizeF(automationPage->automationViewportSize()));

    const EditorAutomationRowId pan{EditorAutomationRowKind::ControlChange, kTrack,
                                    CoreTimeDefaults::kCcPan};
    QVERIFY(activateParameter(pan));
    refreshDocumentPresentation();
    const QAbstractItemModel *const laneTextModel = scene->automationLaneTextModel();
    QVERIFY(laneTextModel);
    std::optional<QRectF> count;
    QTRY_VERIFY(
        (count = findTextRecord(laneTextModel, QStringLiteral("2 Events"), viewport)).has_value());
    QVERIFY2(count->left() < viewport.left() + viewport.width() / 4.0,
             "the lane event count no longer hugs the viewport's left edge");
    QVERIFY2(count->bottom() > viewport.top() + viewport.height() * 3.0 / 4.0,
             "the lane event count no longer hugs the viewport's bottom edge");
    const EditorAutomationRowId volume{EditorAutomationRowKind::ControlChange, kTrack,
                                       CoreTimeDefaults::kCcVolume};
    const int volumeIndex = checks::support::automationParameterIndex(*canvas, volume);
    QVERIFY(volumeIndex >= 0);
    canvas->activateParameter(volumeIndex);
    refreshDocumentPresentation();
    QTRY_VERIFY(findTextRecord(laneTextModel, QStringLiteral("1 Event"), viewport).has_value());

    const EditorAutomationRowId modulation{EditorAutomationRowKind::ControlChange, kTrack,
                                           CoreTimeDefaults::kCcModulation};
    const int modulationIndex = checks::support::automationParameterIndex(*canvas, modulation);
    QVERIFY(modulationIndex >= 0);
    canvas->activateParameter(modulationIndex);
    refreshDocumentPresentation();
    QTRY_VERIFY(!findTextRecord(laneTextModel, QStringLiteral("0 Events"), viewport).has_value());
    QTRY_VERIFY(!findTextRecord(laneTextModel, QStringLiteral("2 Events"), viewport).has_value());
}

void AutomationPresentationTest::laneScaleLabelsRenderAtLeftEdge()
{
    AutomationPage *const automationPage = page();
    songview::TimelineQuickScene *const scene = quickScene();
    AutomationCanvas *const canvas = automationPage ? automationPage->canvas() : nullptr;
    QVERIFY(automationPage);
    QVERIFY(scene);
    QVERIFY(canvas);
    const QRectF viewport(QPointF{}, QSizeF(automationPage->automationViewportSize()));
    const QAbstractItemModel *const laneTextModel = scene->automationLaneTextModel();
    QVERIFY(laneTextModel);
    const EditorAutomationRowId pan{EditorAutomationRowKind::ControlChange, kTrack,
                                    CoreTimeDefaults::kCcPan};
    const EditorAutomationRowId volume{EditorAutomationRowKind::ControlChange, kTrack,
                                       CoreTimeDefaults::kCcVolume};
    const EditorAutomationRowId tempo{EditorAutomationRowKind::Tempo, 0, 0};
    const EditorAutomationRowId bend{EditorAutomationRowKind::ControlChange, kTrack,
                                     CoreTimeDefaults::kLaneCcBend};

    // Pan labels: max, min, and neutral hug the left edge at their curve
    // heights, spread across the plot's thirds without overlapping.
    QVERIFY(activateParameter(pan));
    refreshDocumentPresentation();
    std::optional<QRectF> maxLabel;
    std::optional<QRectF> minLabel;
    std::optional<QRectF> neutralLabel;
    QTRY_VERIFY(
        (maxLabel = findTextRecord(laneTextModel, QStringLiteral("c_v+63"), viewport)).has_value());
    QTRY_VERIFY(
        (minLabel = findTextRecord(laneTextModel, QStringLiteral("c_v-64"), viewport)).has_value());
    QTRY_VERIFY((neutralLabel = findTextRecord(laneTextModel, QStringLiteral("c_v+0"), viewport))
                    .has_value());
    for (const QRectF &rect : {*maxLabel, *minLabel, *neutralLabel}) {
        QVERIFY2(rect.left() < viewport.left() + viewport.width() / 4.0,
                 "a scale label no longer hugs the viewport's left edge");
    }
    QVERIFY2(maxLabel->center().y() < viewport.top() + viewport.height() / 3.0,
             "the maximum scale label left the plot's top third");
    QVERIFY2(neutralLabel->center().y() >= viewport.top() + viewport.height() / 3.0 &&
                 neutralLabel->center().y() < viewport.top() + viewport.height() * 2.0 / 3.0,
             "the neutral scale label left the plot's middle third");
    QVERIFY2(minLabel->center().y() >= viewport.top() + viewport.height() * 2.0 / 3.0,
             "the minimum scale label left the plot's bottom third");
    QVERIFY(!maxLabel->intersects(*minLabel));
    QVERIFY(!maxLabel->intersects(*neutralLabel));
    QVERIFY(!minLabel->intersects(*neutralLabel));
    std::optional<QRectF> count;
    QTRY_VERIFY(
        (count = findTextRecord(laneTextModel, QStringLiteral("2 Events"), viewport)).has_value());
    QVERIFY2(!count->intersects(*minLabel),
             "the lane event count collides with the minimum scale label");

    // Ticks: short left-edge horizontals in the grid layer at each label's
    // curve-true Y, emitted only on content passes so hover passes never
    // accumulate duplicates.
    const LaneHandle panHandle = findRow(pan);
    QVERIFY(panHandle.valid());
    const QRect body = canvas->laneBody(panHandle);
    QVERIFY(!body.isEmpty());
    const CCLaneAdapter panLane(*m_document, kTrack, CoreTimeDefaults::kCcPan);
    const AutomationGeometry geometry = AutomationGeometry::resolve();
    const qreal maxY = nodelane::valueY(panLane, body, geometry, 127);
    const qreal neutralY = nodelane::valueY(panLane, body, geometry, 64);
    const qreal minY = nodelane::valueY(panLane, body, geometry, 0);
    const qreal tickLength = 3.0 * layout::space(layout::Space::Half);
    const auto edgeTickYs = [&scene, &viewport, tickLength] {
        std::vector<qreal> ys;
        for (const songview::TimelineQuickRect &rect :
             scene->layer(songview::TimelineQuickLayer::AutomationGrid).rects) {
            if (rect.rect.left() <= viewport.left() + layout::singlePixel() &&
                rect.rect.width() >= 2.0 * layout::singlePixel() &&
                rect.rect.width() <= tickLength + layout::singlePixel()) {
                ys.push_back(rect.rect.center().y());
            }
        }
        return ys;
    };
    const auto ticksNear = [&edgeTickYs](qreal y) {
        const std::vector<qreal> ys = edgeTickYs();
        return std::count_if(ys.begin(), ys.end(), [y](qreal tickY) {
            return std::abs(tickY - y) <= 2.0 * layout::singlePixel();
        });
    };
    QTRY_VERIFY(ticksNear(maxY) == 1 && ticksNear(neutralY) == 1 && ticksNear(minY) == 1 &&
                edgeTickYs().size() == 3);

    // Hover must preserve the scale labels, their non-overlap contract, and
    // the exact three-tick edge set.
    mouseMove(*m_plotInput, lanePoint(panHandle, kHeldTick, 32));
    QTRY_VERIFY(scene->automationHoverTextModel()->rowCount() > 0);
    QCOMPARE(findTextRecord(laneTextModel, QStringLiteral("c_v+63"), viewport), maxLabel);
    QCOMPARE(findTextRecord(laneTextModel, QStringLiteral("c_v-64"), viewport), minLabel);
    QCOMPARE(findTextRecord(laneTextModel, QStringLiteral("c_v+0"), viewport), neutralLabel);
    QVERIFY2(ticksNear(maxY) == 1 && ticksNear(neutralY) == 1 && ticksNear(minY) == 1,
             "a scale tick no longer sits at its label's curve height");
    QVERIFY2(edgeTickYs().size() == 3,
             "a hover-only pass appended duplicate left-edge scale ticks");

    // Ghost labels ride the right edge while scale labels ride the left, so
    // the seeded rects never collide — the ghost keeps its at-height
    // placement instead of shifting down or dropping.
    m_document->writeLanePoints(kTrack, CoreTimeDefaults::kCcVolume, 0, CoreTimeDefaults::kNoTick,
                                {{24, 127}, {96, 127}});
    refreshDocumentPresentation();
    const int volumeIndex = checks::support::automationParameterIndex(*canvas, volume);
    QVERIFY(volumeIndex >= 0);
    canvas->toggleGhostParameter(volumeIndex);
    std::optional<QRectF> ghostLabel;
    QTRY_VERIFY(
        (ghostLabel = findTextRecord(laneTextModel, QStringLiteral("Volume · 2 Events"), viewport))
            .has_value());
    QTRY_VERIFY(
        (maxLabel = findTextRecord(laneTextModel, QStringLiteral("c_v+63"), viewport)).has_value());
    QTRY_VERIFY(
        (minLabel = findTextRecord(laneTextModel, QStringLiteral("c_v-64"), viewport)).has_value());
    QTRY_VERIFY((neutralLabel = findTextRecord(laneTextModel, QStringLiteral("c_v+0"), viewport))
                    .has_value());
    for (const QRectF &rect : {*maxLabel, *minLabel, *neutralLabel}) {
        QVERIFY2(!ghostLabel->intersects(rect),
                 "the ghost label overlaps a scale label instead of keeping its side");
    }
    canvas->toggleGhostParameter(volumeIndex);
    QVERIFY(canvas->ghostParameters().isEmpty());

    // Neutral rule: volume has no neutral value, so only min and max emit.
    canvas->activateParameter(volumeIndex);
    refreshDocumentPresentation();
    QTRY_VERIFY(findTextRecord(laneTextModel, QStringLiteral("127"), viewport).has_value());
    QTRY_VERIFY(findTextRecord(laneTextModel, QStringLiteral("0"), viewport).has_value());
    QTRY_VERIFY(!findTextRecord(laneTextModel, QStringLiteral("c_v+0"), viewport).has_value());

    // Tempo inherits neutral -1, so its 120-BPM lead-in never labels; pitch
    // bend's negative minimum and zero neutral take the bend format path.
    const int tempoIndex = checks::support::automationParameterIndex(*canvas, tempo);
    QVERIFY(tempoIndex >= 0);
    canvas->activateParameter(tempoIndex);
    refreshDocumentPresentation();
    QTRY_VERIFY(findTextRecord(laneTextModel, QStringLiteral("255"), viewport).has_value());
    QTRY_VERIFY(findTextRecord(laneTextModel, QStringLiteral("20"), viewport).has_value());
    QTRY_VERIFY(!findTextRecord(laneTextModel, QStringLiteral("120"), viewport).has_value());
    const int bendIndex = checks::support::automationParameterIndex(*canvas, bend);
    QVERIFY(bendIndex >= 0);
    canvas->activateParameter(bendIndex);
    refreshDocumentPresentation();
    QTRY_VERIFY(findTextRecord(laneTextModel, QStringLiteral("+8191"), viewport).has_value());
    QTRY_VERIFY(findTextRecord(laneTextModel, QStringLiteral("-8192"), viewport).has_value());
    QTRY_VERIFY(findTextRecord(laneTextModel, QStringLiteral("0"), viewport).has_value());
}
