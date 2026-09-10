// ------------------------------------------------ AutomationCanvas parameter selector

#include "ui/editordrawer/automationcanvas.h"

#include <algorithm>

#include <QFontInfo>
#include <QVariantMap>

#include "core/m4asemantics.h"
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
    syncTimelineQuickHover();
    emit activeParameterChanged();
    requestFullQuickUpdate();
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
    appearance.insert(QStringLiteral("inset"), layout::space(layout::Space::One));
    appearance.insert(QStringLiteral("stroke"), layout::singlePixel());
    appearance.insert(QStringLiteral("background"),
                      themes::color(themes::Role::song_view_piano_roll_background));
    appearance.insert(QStringLiteral("currentFill"),
                      themes::color(themes::Role::song_view_timeline_chrome_background));
    appearance.insert(QStringLiteral("text"), themes::color(themes::Role::song_view_primary_text));
    appearance.insert(QStringLiteral("selectionOutline"),
                      themes::color(themes::Role::song_view_selection_edge));
    appearance.insert(QStringLiteral("focusOutline"), themes::color(themes::Role::focus_outline));
    return appearance;
}

// Nonnegative scalar setter for the QML-published selector minimum
// (Math.ceil(grid.implicitHeight) through a Qt Binding); the equality guard
// keeps binding churn flat.
void AutomationCanvas::setMinimumContentHeight(int height)
{
    height = qMax(0, height);
    if (height == m_minimumContentHeight)
        return;
    m_minimumContentHeight = height;
    emit minimumContentHeightChanged();
}
