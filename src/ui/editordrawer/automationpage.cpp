#include "ui/editordrawer/automationpage.h"

#include <algorithm>

#include <QAction>
#include <QWindow>

#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/songview/editactions.h"
#include "ui/songview/quick/timelineinput.h"
#include "ui/songview/timecamera.h"

QSize AutomationPage::automationViewportSize() const noexcept
{
    return m_viewportSize;
}

void AutomationPage::synchronizeAutomationViewport(QSize viewportSize)
{
    if (m_viewportSize == viewportSize)
        return;
    m_viewportSize = viewportSize;
}

AutomationPage::AutomationPage(SongView &owner, QObject *parent)
    : QObject(parent)
    , m_owner(owner)
    , m_grid(owner.grid())
    , m_camera(owner.camera())
{}

QPointer<QAction> AutomationPage::pencilModeAction() const noexcept
{
    const songview::EditActions *const actions = m_owner.editActions();
    if (!actions)
        return {};
    return actions->action(SongView::EditCommand::PencilMode);
}

void AutomationPage::setInputWindow(QWindow *window) noexcept
{
    if (m_inputWindow == window)
        return;
    QObject::disconnect(m_inputWindowDeactivationConnection);
    m_inputWindow = window;
    if (!window)
        return;
    const QPointer<QWindow> inputWindow{window};
    m_inputWindowDeactivationConnection =
        connect(window, &QWindow::activeChanged, this, [this, inputWindow] {
            if (!inputWindow || m_inputWindow.data() != inputWindow.data() ||
                inputWindow->isActive()) {
                return;
            }
            // Deactivation ends the page's live interaction. Do not request
            // focus here: the foreground window now owns it.
            cancelInteraction();
        });
}

bool AutomationPage::ready() const noexcept
{
    return timeline() != nullptr;
}

const SongViewModel &AutomationPage::model() const noexcept
{
    return m_owner.model();
}

const MidiTimeline *AutomationPage::timeline() const noexcept
{
    return m_owner.timeline();
}

SongDocument &AutomationPage::document() const noexcept
{
    return m_owner.document();
}

const LoadedVoiceGroup *AutomationPage::voicegroup() const noexcept
{
    return m_owner.voicegroup();
}

void AutomationPage::songChanged()
{
    cancelInteraction();
    m_viewState = m_owner.editorViewState();
    rebuildModel();
}

void AutomationPage::refresh(DrawerScopes)
{
    m_viewState = m_owner.editorViewState();
}

void AutomationPage::cancelInteraction() {}

void AutomationPage::documentChanged()
{
    cancelInteraction();
    m_viewState = m_owner.editorViewState();
    rebuildModel();
}

Tick AutomationPage::snapTick(double tick, bool fineMode) const noexcept
{
    return m_grid.snapTick(tick, fineMode);
}
Tick AutomationPage::snapTickDown(double tick, bool fineMode) const noexcept
{
    return m_grid.snapTickDown(tick, fineMode);
}

Tick AutomationPage::nextGridTick(Tick tick, bool fineMode, Tick limit) const noexcept
{
    if (tick >= limit)
        return limit;
    return std::min(limit, m_grid.nextSnapTickAfter(tick, fineMode));
}

double AutomationPage::tickAtContentX(double x) const noexcept
{
    return m_camera.tickAtContentX(x);
}

qreal AutomationPage::displayX(double tick, qreal origin, qreal dpr) const noexcept
{
    return m_camera.displayX(tick, origin, dpr);
}

double AutomationPage::pxPerBeat() const noexcept
{
    return m_camera.pxPerBeat();
}

double AutomationPage::scrollX() const noexcept
{
    return m_camera.scrollX();
}

void AutomationPage::requestHorizontalScroll(double value) const
{
    m_owner.setEditorHorizontalScroll(value);
}

void AutomationPage::requestTimeZoom(const songview::TimelineWheelInput &input,
                                     qreal anchorContentX) const
{
    m_owner.zoomTimelineAtWheel(input, anchorContentX);
}

void AutomationPage::setFollowScrollPaused(bool paused) const
{
    m_owner.setFollowScrollPaused(paused);
}

void AutomationPage::publishViewState()
{
    const EditorViewState canonical = m_owner.editorViewState();
    m_viewState.velocity = canonical.velocity;
    m_viewState.automation = canonical.automation;
    m_viewState.activePage = canonical.activePage;
    m_owner.setEditorViewState(m_viewState);
}

void AutomationPage::rebuildModel() {}

void AutomationPage::setLaneRange(const EditorAutomationRowId &row, uint8_t range)
{
    m_viewState.laneRanges[row] = range;
    publishViewState();
}

void AutomationPage::publishTimeSelection(Tick startTick, Tick endTick,
                                          const std::vector<std::pair<int, uint8_t>> &lanes,
                                          bool tempo) const
{
    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = startTick;
    selection.endTick = endTick;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    selection.lanes = lanes;
    selection.tempo = tempo;
    m_owner.selectionModel().setTimeSelection(selection);
}

DrawerPageVoiceContext AutomationPage::voiceContext(Tick tick) const
{
    return m_owner.voiceContext(tick);
}

void AutomationPage::showTimeSelectionMenu(const DrawerPageTimeSelectionMenuRequest &request) const
{
    m_owner.showDrawerPageTimeSelectionMenu(request);
}

void AutomationPage::requestRefresh() const
{
    m_owner.refreshAllDrawerPages(DrawerScope::Content);
}
void AutomationPage::requestQuickUpdate(songview::AutomationRefreshSet dirty) const
{
    m_owner.requestAutomationQuickUpdate(dirty);
}

void AutomationPage::commitEditCursor(Tick tick) const
{
    m_owner.commitEditCursor(tick);
}
