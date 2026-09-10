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

class AutomationPage;
class QQuickItem;
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

    void parameterLabelsFitGutterAtDerivedMinimum();
    void parameterLabelClicksSwitchActivePlot();
    void tempoUsesFullSharedPlotBody();
    void drawerGrowthMovesValueAxisKeepsGridAlignment();
    void selectedInactiveParametersKeepScopeIndicators();

    void pencilCursorUsesPlotGutterBoundary();
    void pencilCursorUsesInputDevicePixelRatio();
    void pencilCursorScalesWithInjectedDevicePixelRatio();
    void pencilCursorTurnsOffToArrow();

    void tempoHoverValueHasVisibleTextRecord();

  private:
    static SmfFile presentationSmf();
    static bool layerHasColorIn(const songview::TimelineQuickLayerData &layer,
                                const QRegion &contentRegion, const QPoint &contentOrigin,
                                const QColor &color);
    QQuickItem *parameterLabelItem(int index) const;
    bool activateParameter(const EditorAutomationRowId &row);
    AutomationPage *page() const;
    songview::TimelineQuickScene *quickScene() const;
    LaneHandle findRow(EditorAutomationRowId id) const;
    QPointF lanePoint(LaneHandle handle, uint64_t tick, int value) const;
    QPoint windowPoint(const songview::TimelineInputItem &input, QPointF contentPoint) const;
    void refreshDocumentPresentation();
    void mouseMove(songview::TimelineInputItem &input, QPointF contentPoint);
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
