#pragma once

#include <cstdint>
#include <memory>
#include <optional>
#include <vector>

#include <QColor>
#include <QObject>
#include <QPoint>
#include <QPointF>
#include <QPointer>
#include <QRect>
#include <QRectF>
#include <QRegion>
#include <QStringList>

#include "checks/support/editorrig.h"
#include "core/songdocument.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/editorviewstate.h"

class AutomationPage;
class QAbstractItemModel;
class QQuickWindow;

namespace songview {
class TimelineInputItem;
class TimelineQuickLayerData;
class TimelineQuickScene;
} // namespace songview

class AutomationPresentationTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(AutomationPresentationTest)

  public:
    AutomationPresentationTest() = default;

  private slots:
    void init();
    void cleanup();

    void collapsedTempoGeometryIsPinned();
    void headerClickExpandsTempoToConfiguredHeight();
    void verticalScrollPinsTempoOverCcContent();
    void viewportResizeKeepsTempoPinned();
    void headerClickRecollapsesTempoAndRecoversCanvasSpace();
    void headerReexpansionRestoresConfiguredTempoHeight();

    void pencilCursorUsesPlotGutterBoundaryAndTempoPrecedence();
    void pencilCursorUsesInputDevicePixelRatio();
    void pencilCursorScalesWithInjectedDevicePixelRatio();
    void pencilCursorTurnsOffToArrow();

    void expandedTempoClipsCoveredCcCurves();
    void tempoSelectionReticleComposedInCoveredBody();
    void collapsedTempoHeaderClipsCoveredCcCurves();
    void tempoHeaderFillUsesTimelineChrome();
    void gutterTextRecordsUseSemanticLabelsAndBounds();
    void tempoHoverValueHasVisibleTextRecord();
    void addingEmptyLanePreservesLfoSemanticTitleAndUniqueRows();

  private:
    struct CoveredCcLane final {
        EditorAutomationRowId id;
        QRect body;
        QRect overlap;
    };

    static SmfFile presentationSmf();
    static bool layerHasColorIn(const songview::TimelineQuickLayerData &layer,
                                const QRegion &contentRegion, const QPoint &contentOrigin,
                                const QColor &color);
    static bool rowsHaveUniqueIds(const std::vector<AutomationRow> &rows);

    AutomationPage *page() const;
    songview::TimelineQuickScene *quickScene() const;
    LaneHandle findRow(EditorAutomationRowId id) const;
    QPointF lanePoint(LaneHandle handle, uint64_t tick, int value) const;
    QPoint windowPoint(const songview::TimelineInputItem &input, QPointF contentPoint) const;
    QPointF tempoHeaderPoint() const;
    int maximumScroll() const;
    bool tempoPinnedToViewport() const;
    bool setTempoExpanded(bool expanded);
    std::optional<CoveredCcLane> ccCoveredBy(const QRect &cover) const;
    std::optional<CoveredCcLane> scrollToCcOverlap(int coverHeight);
    void refreshDocumentPresentation();
    void setCcPoints(EditorAutomationRowId row,
                     const std::vector<SongDocument::LanePointValue> &points);
    void mouseMove(songview::TimelineInputItem &input, QPointF contentPoint);
    void gutterClick(QPointF contentPoint);
    std::optional<QRectF> textRecord(const QString &text, const QRectF &bounds) const;
    std::optional<QRectF> visibleHoverTextRecord(const QString &text) const;

    LoadedVoiceGroup m_bank = {};
    std::unique_ptr<SongDocument> m_document;
    std::unique_ptr<checks::EditorRig> m_rig;
    QPointer<songview::TimelineInputItem> m_plotInput;
    QPointer<songview::TimelineInputItem> m_gutterInput;
    QPointer<QQuickWindow> m_quickWindow;
    bool m_windowEntered = false;
    Qt::MouseButton m_heldButton = Qt::NoButton;
    QPoint m_lastWindowPoint;
};

int runAutomationPresentationCheck(const QStringList &qtArguments);
