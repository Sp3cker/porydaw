// ------------------------------------------------ AutomationCanvas parameter selector

#include "ui/editordrawer/automationcanvas.h"

#include <algorithm>

#include <QFontInfo>
#include <QGuiApplication>
#include <QVariantMap>

#include "core/m4asemantics.h"
#include "core/songdocument.h"
#include "core/xcmd.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/layout.h"
#include "ui/theme/themeruntime.h"

namespace {

// Nine identities: the supported CC catalog plus song-global Tempo.
int parameterCount() noexcept
{
    return int(CCLanes::supportedControllers().size()) + 1;
}

} // namespace

std::optional<EditorAutomationRowId> AutomationCanvas::parameterRow(int index) const
{
    if (index < 0 || index >= parameterCount())
        return std::nullopt;
    if (index == parameterCount() - 1)
        return EditorAutomationRowId{EditorAutomationRowKind::Tempo, 0, 0};
    const int track = m_page.m_owner.selectionModel().primaryTrack();
    if (track < 0 || track > 0xFF)
        return std::nullopt;
    return EditorAutomationRowId{EditorAutomationRowKind::ControlChange, uint8_t(track),
                                 CCLanes::supportedControllers()[std::size_t(index)]};
}

// Labels come from the m4a semantic layer — classified CCs, registered XCMD
// selectors, dedicated PitchBend, and Tempo — so no display name is
// duplicated and every identity stays available without written events.
QStringList AutomationCanvas::parameterLabels() const
{
    QStringList labels;
    labels.reserve(parameterCount());
    for (const uint8_t controller : CCLanes::supportedControllers()) {
        if (controller == CCLanes::bendController())
            labels.append(m4aLaneName(M4aLane::PitchBend));
        else if (const xcmd::Descriptor *descriptor = xcmd::descriptorForLane(controller))
            labels.append(m4aLaneName(m4aLaneForXcmdSelector(descriptor->selector)));
        else
            labels.append(m4aLaneName(m4aClassifyCc(controller).lane));
    }
    labels.append(m4aLaneName(M4aLane::Tempo));
    return labels;
}

int AutomationCanvas::activeParameter() const noexcept
{
    if (!m_activeController)
        return parameterCount() - 1;
    const auto controllers = CCLanes::supportedControllers();
    const auto position = std::find(controllers.begin(), controllers.end(), *m_activeController);
    return position == controllers.end() ? parameterCount() - 1
                                         : int(position - controllers.begin());
}

// Resolved fresh on every call: rebuilds remap m_nodeStack handles, so the
// active row's handle is never cached.
LaneHandle AutomationCanvas::activeLane() const noexcept
{
    const std::optional<EditorAutomationRowId> row = parameterRow(activeParameter());
    if (!row)
        return {};
    const auto slot =
        std::find_if(m_nodeStack.cbegin(), m_nodeStack.cend(),
                     [&row](const NodeLaneSlot &candidate) { return candidate.id == *row; });
    if (slot == m_nodeStack.cend())
        return {};
    return {int(slot - m_nodeStack.cbegin())};
}

// Ghost secondaries resolved fresh per paint: rebuilds remap m_nodeStack
// handles, so no handle is cached. The active row is skipped — it paints
// through the active pass; a pin on it simply waits there.
std::vector<LaneHandle> AutomationCanvas::ghostSecondaryHandles() const
{
    std::vector<LaneHandle> handles;
    const std::optional<EditorAutomationRowId> activeRow = parameterRow(activeParameter());
    for (const int index : ghostParameters()) {
        const std::optional<EditorAutomationRowId> row = parameterRow(index);
        if (!row || (activeRow && *row == *activeRow))
            continue;
        const auto slot =
            std::find_if(m_nodeStack.cbegin(), m_nodeStack.cend(),
                         [&row](const NodeLaneSlot &candidate) { return candidate.id == *row; });
        if (slot != m_nodeStack.cend())
            handles.push_back({int(slot - m_nodeStack.cbegin())});
    }
    return handles;
}

// Selection-scope inclusion over the nine catalog identities — not a count of
// stored nodes; unpainted lanes and global Tempo are included when covered.
QList<int> AutomationCanvas::selectedParameters() const
{
    QList<int> selected;
    for (int index = 0; index < parameterCount(); ++index) {
        const std::optional<EditorAutomationRowId> row = parameterRow(index);
        if (row && m_laneSelection.coversNodes(*row))
            selected.append(index);
    }
    return selected;
}

// User ghost-enabled identities: the catalog-index projection of the
// controller-identity ghost set, mirroring selectedParameters.
QList<int> AutomationCanvas::ghostParameters() const
{
    QList<int> ghosts;
    for (int index = 0; index < parameterCount(); ++index) {
        const std::optional<EditorAutomationRowId> row = parameterRow(index);
        if (!row)
            continue;
        const bool ghosted = row->kind == EditorAutomationRowKind::Tempo
                                 ? m_ghostTempo
                                 : std::find(m_ghostControllers.begin(), m_ghostControllers.end(),
                                             row->controller) != m_ghostControllers.end();
        if (ghosted)
            ghosts.append(index);
    }
    return ghosts;
}

// Ghost toggling is view-only like activation: selection, document, undo,
// and hover are untouched; only the ghost set and its notification change.
// Command-clicking the active tab collapses back to a single shown lane.
void AutomationCanvas::toggleGhostParameter(int index)
{
    const auto row = parameterRow(index);
    if (!row || !parametersEnabled())
        return;
    const QString label = parameterLabels().value(index);
    if (index == activeParameter()) {
        if (m_ghostControllers.empty() && !m_ghostTempo)
            return;
        m_ghostControllers.clear();
        m_ghostTempo = false;
        emit ghostParametersChanged();
        requestFullQuickUpdate();
        m_page.announce(tr("Showing only %1").arg(label));
        return;
    }
    bool nowGhosted = false;
    if (row->kind == EditorAutomationRowKind::Tempo) {
        m_ghostTempo = !m_ghostTempo;
        nowGhosted = m_ghostTempo;
    } else if (const auto position =
                   std::find(m_ghostControllers.begin(), m_ghostControllers.end(), row->controller);
               position != m_ghostControllers.end()) {
        m_ghostControllers.erase(position);
    } else {
        m_ghostControllers.push_back(row->controller);
        nowGhosted = true;
    }
    emit ghostParametersChanged();
    requestFullQuickUpdate();
    m_page.announce(nowGhosted ? tr("%1 ghost shown").arg(label)
                               : tr("%1 ghost hidden").arg(label));
}

bool AutomationCanvas::parametersEnabled() const noexcept
{
    return m_page.ready() && m_page.document() != nullptr;
}

// Tab switching is view-only: the document, revision, undo stack, edit
// cursor, track, and shared selection are untouched. Provisional gestures and
// stale owned menus end first; the cancellers end only a session this canvas
// still owns, so a foreign popup survives.
void AutomationCanvas::activateParameter(int index)
{
    const auto row = parameterRow(index);
    if (!row || !parametersEnabled() || index == activeParameter())
        return;
    cancelInteraction();
    cancelLaneMenuWithoutFocus();
    cancelNodeMenuWithoutFocus();
    m_activeController = row->kind == EditorAutomationRowKind::Tempo
                             ? std::nullopt
                             : std::optional<uint8_t>{row->controller};
    m_hoverState.clearHover();
    m_hoverState.invalidateCaches();
    m_hoverState.hoverValueLabel = {};
    emit activeParameterChanged();
    // The Hover bit inside All re-syncs the cross-band hover owner after
    // clearHover above.
    requestFullQuickUpdate();
}

// AbstractButton press/click carry no modifiers, so the QML tab handlers
// delegate here and the canvas reads the live modifier state itself.
void AutomationCanvas::parameterPressed(int index)
{
    if (QGuiApplication::queryKeyboardModifiers() & Qt::ControlModifier)
        toggleGhostParameter(index);
    else
        activateParameter(index);
}

void AutomationCanvas::parameterClicked(int index)
{
    // A real command-click already toggled on press; never toggle twice.
    // Assistive activation without modifiers still activates.
    if (QGuiApplication::queryKeyboardModifiers() & Qt::ControlModifier)
        return;
    activateParameter(index);
}

// The selector's context menu: activate the target parameter, then open the
// existing lane menu for its resolved row at the pointer. Invalid indexes and
// requests without a bound document do nothing.
void AutomationCanvas::openParameterMenu(int index, qreal sceneX, qreal sceneY)
{
    if (!parametersEnabled() || !parameterRow(index))
        return;
    activateParameter(index);
    const LaneHandle lane = activeLane();
    if (!lane.valid())
        return;
    showLaneMenuFor(lane, QPointF(sceneX, sceneY));
}

// The project-style appearance bridge for the selector labels: typography and
// song-view theme roles only. QML owns text measurement, fitting, and layout;
// Qt binding invalidation drives construction — never scene/pointer refreshes.
QVariantMap AutomationCanvas::parameterAppearance() const
{
    QFont font = m_laneCaptionFont;
    font.setPixelSize(qMax(1, QFontInfo(font).pixelSize()));
    QFont minimumFont = font;
    minimumFont.setPixelSize(std::max(1, layout::fontPx(2.0 / 3.0)));
    QVariantMap appearance;
    appearance.insert(QStringLiteral("font"), QVariant::fromValue(font));
    appearance.insert(QStringLiteral("minimumFont"), QVariant::fromValue(minimumFont));
    appearance.insert(QStringLiteral("minimumCellHeight"), layout::fontPxF(4.0 / 3.0));
    appearance.insert(QStringLiteral("pipExtent"), layout::fontPxF(0.5));
    appearance.insert(QStringLiteral("inset"), layout::space(layout::Space::One));
    appearance.insert(QStringLiteral("stroke"), layout::singlePixel());
    appearance.insert(QStringLiteral("selectionOutline"),
                      themes::color(themes::Role::song_view_selection_edge));
    appearance.insert(QStringLiteral("focusOutline"), themes::color(themes::Role::focus_outline));
    appearance.insert(QStringLiteral("tabBackground"),
                      themes::color(themes::Role::song_view_automation_tab_background));
    appearance.insert(QStringLiteral("tabHoverBackground"),
                      themes::color(themes::Role::song_view_automation_tab_hover_background));
    appearance.insert(QStringLiteral("tabSelectedBackground"),
                      themes::color(themes::Role::song_view_automation_tab_active_background));
    appearance.insert(QStringLiteral("tabText"), themes::color(themes::Role::tab_text));
    appearance.insert(QStringLiteral("tabHoverText"), themes::color(themes::Role::tab_hover_text));
    appearance.insert(QStringLiteral("tabSelectedText"),
                      themes::color(themes::Role::tab_selected_text));
    appearance.insert(QStringLiteral("tabOutline"),
                      themes::color(themes::Role::song_view_automation_tab_outline));
    appearance.insert(QStringLiteral("pipColor"),
                      themes::color(themes::Role::song_view_automation_node_ink));
    return appearance;
}

// Written-event pips: one bool per catalog index, in parameterLabels order.
// Uniform rule for every identity — Vol/Pan/Tempo included, no carve-outs:
// Tempo reads the song-global tempoPoints, CC rows read lanePoints. Adapter
// projections (Volume/Pan synthetic tick-0 node, Tempo 120 BPM leadIn) are
// never consulted, so an unpainted default shows no pip.
QVariantList AutomationCanvas::parameterPips() const
{
    QVariantList pips;
    pips.reserve(parameterCount());
    const SongDocument *document = m_page.document();
    for (int index = 0; index < parameterCount(); ++index) {
        bool hasEvents = false;
        if (document) {
            if (const std::optional<EditorAutomationRowId> row = parameterRow(index)) {
                hasEvents = row->kind == EditorAutomationRowKind::Tempo
                                ? !document->tempoPoints().empty()
                                : !document->lanePoints(row->track, row->controller).empty();
            }
        }
        pips.append(hasEvents);
    }
    return pips;
}
