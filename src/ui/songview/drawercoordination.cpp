#include "core/songdocument.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/songview/pianoroll.h"

#include <optional>

using namespace songview;
using namespace songview::detail;

void SongView::toggleDrawerSection(EditorDrawerPage page)
{
    EditorViewState state = m_editorViewState;
    DrawerSectionState &section =
        page == EditorDrawerPage::Velocity ? state.velocity : state.automation;
    section.visible = !section.visible;
    state.activePage = page;
    applyEditorViewState(state);
}

void SongView::setDrawerSectionVisible(EditorDrawerPage page, bool visible)
{
    EditorViewState state = m_editorViewState;
    DrawerSectionState &section =
        page == EditorDrawerPage::Velocity ? state.velocity : state.automation;
    if (section.visible == visible)
        return;
    section.visible = visible;
    applyEditorViewState(state);
}

bool SongView::drawerSectionVisible(EditorDrawerPage page) const
{
    return page == EditorDrawerPage::Velocity ? m_editorViewState.velocity.visible
                                              : m_editorViewState.automation.visible;
}

void SongView::setDrawerSectionHeight(EditorDrawerPage page, std::optional<int> height)
{
    if (height && *height < 1)
        height = std::nullopt;
    EditorViewState state = m_editorViewState;
    DrawerSectionState &section =
        page == EditorDrawerPage::Velocity ? state.velocity : state.automation;
    if (section.height == height)
        return;
    section.height = height;
    applyEditorViewState(state);
}

int SongView::drawerSectionHeight(EditorDrawerPage page) const
{
    const DrawerSectionState &section = page == EditorDrawerPage::Velocity
                                            ? m_editorViewState.velocity
                                            : m_editorViewState.automation;
    return section.effectiveHeight(0);
}

void SongView::setDrawerActivePage(EditorDrawerPage page)
{
    if (m_editorViewState.activePage == page)
        return;
    EditorViewState state = m_editorViewState;
    state.activePage = page;
    applyEditorViewState(state);
}

EditorDrawerPage SongView::drawerActivePage() const
{
    return m_editorViewState.activePage;
}

bool SongView::hasVisibleDrawerSection() const
{
    return m_editorViewState.velocity.visible || m_editorViewState.automation.visible;
}

void SongView::showDrawerPageTimeSelectionMenu(const DrawerPageTimeSelectionMenuRequest &request)
{
    EditorSelectionModel::TimeSelection selection;
    selection.startTick = request.startTick;
    selection.endTick = request.endTick;
    selection.scope = EditorSelectionModel::TimeSelection::Lanes;
    selection.lanes = request.lanes;
    m_selectionModel.setTimeSelection(selection);
    showTimeSelectionMenu(request.globalPosition);
}

void SongView::showDrawerPageNoteStatus(std::optional<DrawerPageNoteStatus> status)
{
    if (status) {
        announce(tr("%1 · velocity %2 → plays %3 · length %4 ticks → %5 clocks")
                     .arg(keyName(status->key))
                     .arg(status->storedVelocity)
                     .arg(status->effectiveVelocity)
                     .arg(status->durationTicks)
                     .arg(status->durationClocks));
    }
}

void SongView::requestDrawerPageUndo()
{
    if (m_document)
        m_document->undoStack()->undo();
}

void SongView::requestDrawerPageRedo()
{
    if (m_document)
        m_document->undoStack()->redo();
}

DrawerPageLiveState SongView::drawerPageLiveState() const
{
    return {
        m_document ? m_document->revision() : 0,
        pxPerBeat(),
        m_scrollX,
        m_editCursorTick,
        trackColor(m_selectionModel.primaryTrack()),
        {m_playheadTick, m_playing},
    };
}

void SongView::cancelActiveInteractions()
{
    if (m_editorDrawer && hasVisibleDrawerSection())
        m_editorDrawer->cancelVisiblePageInteraction();
    if (m_roll)
        m_roll->cancelVelocityInteraction();
    if (m_velocityGesture.active())
        cancelVelocityGesture();
}

void SongView::notifyDrawerSongChanged()
{
    if (!m_editorDrawer)
        return;
    m_editorDrawer->automationPage()->songChanged();
    m_editorDrawer->velocityArea()->songChanged();
    refreshDrawerPages();
}

void SongView::refreshDrawerPages()
{
    if (!m_editorDrawer)
        return;
    if (m_editorDrawer->pageVisible(EditorDrawerPage::Automations))
        refreshAutomationPage();
    if (m_editorDrawer->pageVisible(EditorDrawerPage::Velocity))
        refreshVelocityPage();
}

void SongView::refreshAutomationPage()
{
    if (!m_editorDrawer)
        return;
    m_editorDrawer->automationPage()->refreshLiveState(drawerPageLiveState());
}

void SongView::refreshVelocityPage()
{
    if (!m_editorDrawer)
        return;
    m_editorDrawer->velocityArea()->refreshLiveState(drawerPageLiveState());
}

void SongView::refreshAllDrawerPages()
{
    if (!m_editorDrawer)
        return;
    const DrawerPageLiveState liveState = drawerPageLiveState();
    m_editorDrawer->automationPage()->refreshLiveState(liveState);
    m_editorDrawer->velocityArea()->refreshLiveState(liveState);
}
