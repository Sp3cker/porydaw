#pragma once

#include <cstdint>
#include <memory>
#include <optional>

#include <QByteArray>
#include <QColor>
#include <QPoint>
#include <QPointF>
#include <QRectF>
#include <QString>
#include <QTemporaryDir>

#include "checks/support/editorrig.h"
#include "core/songdocument.h"
#include "ui/editordrawer/nodelane/nodelane.h"

class AutomationCanvas;
class AutomationPage;
class QQuickWindow;

namespace songview {
class TimelineInputItem;
class TimelineQuickLayerData;
class TimelineQuickScene;
} // namespace songview

namespace automation_hover {

enum class LaneKind : uint8_t {
    Tempo,
    Cc,
};

struct DocumentState {
    QByteArray smf;
    uint64_t revision = 0;
    int undoCount = 0;
    int undoIndex = 0;

    bool operator==(const DocumentState &) const = default;
};

struct HoverObservation {
    quint64 revision = 0;
    int textRows = 0;
    int valueTextRows = 0;
    int drawableValueTextRows = 0;
    int viewportValueTextRows = 0;
    QString text;
    QColor color;
    bool chromeVisible = false;
    bool guidePublished = false;
    qreal guideRootX = 0.0;
    QRectF rect;
    QRectF clip;

    bool operator==(const HoverObservation &) const = default;
};

struct PreparedLane {
    LaneKind kind = LaneKind::Cc;
    LaneHandle handle;
    uint64_t insertionTick = 0;
    QPoint insertionWindowPosition;
    QPoint nodeWindowPosition;
    QPointF pointerViewport;
    QPointF insertionViewport;
    QPointF nodeViewport;
    QPointF strayGhostViewport;
    int nodeValue = 0;
    int heldValue = 0;
};

struct Topology {
    bool insertionGuide = false;
    bool heldGhost = false;
    bool insertionText = false;
    bool nodeRing = false;
    bool nodeText = false;
    bool suppressesInsertionGhost = false;
    bool repeatDoesNotChurn = false;
    bool leaveCleared = false;
    bool reactivatedHeldText = false;
    bool operator==(const Topology &) const = default;
};

class Fixture final
{
  public:
    QTemporaryDir directory;
    SongDocument document;
    LoadedVoiceGroup bank = {};
    std::unique_ptr<checks::EditorRig> rig;
    Qt::MouseButton heldButton = Qt::NoButton;
    QPoint lastWindowPosition;
    bool windowEntered = false;
};

bool create(Fixture &fixture, QString &error);
AutomationPage *page(const Fixture &fixture);
AutomationCanvas *canvas(const Fixture &fixture);
songview::TimelineInputItem *plotInput(const Fixture &fixture);
songview::TimelineInputItem *gutterInput(const Fixture &fixture);
QQuickWindow *quickWindow(const Fixture &fixture);
DocumentState documentState(Fixture &fixture);

LaneHandle findHandle(const AutomationCanvas &canvas, const EditorAutomationRowId &id);
bool rowMatches(const AutomationCanvas &canvas, LaneHandle handle, const EditorAutomationRowId &id);
bool activateParameter(Fixture &fixture, const EditorAutomationRowId &row);
std::optional<PreparedLane> prepareLane(Fixture &fixture, LaneKind kind);

QPoint windowPoint(const Fixture &fixture, QPointF viewportPoint);
void mouseMove(Fixture &fixture, QPoint position, bool primeTarget = true);
void mousePress(Fixture &fixture, QPoint position);
void mouseRelease(Fixture &fixture, QPoint position);
bool leavePlot(Fixture &fixture);

HoverObservation observe(const Fixture &fixture);
bool isClear(const Fixture &fixture);
bool hasFilledNodeAt(const songview::TimelineQuickLayerData &layer, QPointF center);
Topology topologyFor(Fixture &fixture, const PreparedLane &lane, QString &error);

bool hasValueText(const Fixture &fixture, const HoverObservation &observation);

} // namespace automation_hover
