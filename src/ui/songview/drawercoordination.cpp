#include "core/songdocument.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/drawerchrome.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/songview.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timeruler.h"

#include <optional>

using namespace songview;
namespace {

// Page-keyed projection onto the drawer state. Every section exists in the
// state, so the mapping is total over EditorDrawerPage; the switch guards
// against future enumerators growing without a section.
DrawerSectionState &sectionFor(EditorViewState &state, EditorDrawerPage page) noexcept
{
    switch (page) {
    case EditorDrawerPage::Automations:
        return state.automation;
    case EditorDrawerPage::Velocity:
        return state.velocity;
    case EditorDrawerPage::VoiceChanges:
        return state.voiceChanges;
    }
    Q_UNREACHABLE();
}

const DrawerSectionState &sectionFor(const EditorViewState &state, EditorDrawerPage page) noexcept
{
    switch (page) {
    case EditorDrawerPage::Automations:
        return state.automation;
    case EditorDrawerPage::Velocity:
        return state.velocity;
    case EditorDrawerPage::VoiceChanges:
        return state.voiceChanges;
    }
    Q_UNREACHABLE();
}

} // namespace

void SongView::toggleDrawerSection(EditorDrawerPage page)
{
    EditorViewState state = m_editorViewState;
    DrawerSectionState &section = sectionFor(state, page);
    section.visible = !section.visible;
    state.activePage = page;
    setEditorViewState(state);
}

void SongView::setDrawerSectionVisible(EditorDrawerPage page, bool visible)
{
    EditorViewState state = m_editorViewState;
    DrawerSectionState &section = sectionFor(state, page);
    if (section.visible == visible)
        return;
    section.visible = visible;
    setEditorViewState(state);
}

bool SongView::drawerSectionVisible(EditorDrawerPage page) const
{
    return sectionFor(m_editorViewState, page).visible;
}

void SongView::setDrawerSectionHeight(EditorDrawerPage page, std::optional<int> height)
{
    if (height && *height < 1)
        height = std::nullopt;
    EditorViewState state = m_editorViewState;
    DrawerSectionState &section = sectionFor(state, page);
    if (section.height == height)
        return;
    section.height = height;
    setEditorViewState(state);
}

int SongView::drawerSectionHeight(EditorDrawerPage page) const
{
    const DrawerSectionState &section = sectionFor(m_editorViewState, page);
    return section.effectiveHeight(0);
}

void SongView::setDrawerActivePage(EditorDrawerPage page)
{
    if (m_editorViewState.activePage == page)
        return;
    EditorViewState state = m_editorViewState;
    state.activePage = page;
    setEditorViewState(state);
}

EditorDrawerPage SongView::drawerActivePage() const
{
    return m_editorViewState.activePage;
}

bool SongView::hasVisibleDrawerSection() const
{
    return m_editorViewState.velocity.visible || m_editorViewState.automation.visible ||
           m_editorViewState.voiceChanges.visible;
}

void SongView::showDrawerPageTimeSelectionMenu(const DrawerPageTimeSelectionMenuRequest &request)
{
    EditorSelectionModel::TimeSelection selection;
    selection.startTick = request.startTick;
    selection.endTick = request.endTick;
    selection.scope = EditorSelectionModel::TimeSelection::Lanes;
    selection.lanes = request.lanes;
    selection.tempo = request.tempo;
    m_selectionModel.setTimeSelection(selection);
    openTimeSelectionMenu(request.scenePosition);
}

DrawerPageLiveState SongView::drawerPageLiveState() const
{
    return {
        m_document.revision(),
        pxPerBeat(),
        m_camera.scrollX(),
        m_editCursorTick,
        trackColor(m_selectionModel.primaryTrack()),
        {m_playheadTick, m_playing},
    };
}

void SongView::cancelActiveInteractions()
{
    // The converted Quick scene is the sole pointer-cancellation traversal.
    // Its primary inputs cover ruler, roll, headers, every drawer page, and
    // drawer chrome exactly once. Keep the direct path only before that scene
    // exists, during native construction/destruction.
    if (m_quickView) {
        m_quickView->cancelActiveGestures();
    } else {
        if (m_ruler)
            m_ruler->cancelInteraction();
        if (m_roll)
            m_roll->cancelInteraction();
        if (m_editorDrawer) {
            m_editorDrawer->cancelVisiblePageInteraction();
            m_editorDrawer->chrome().cancelInteraction();
        }
    }
    // A model gesture can outlive its originating item during teardown; end
    // it only if the semantic traversal did not already do so.
    if (m_velocityGesture.active())
        cancelVelocityGesture();
    cancelVoicePicker(/*restoreFocus=*/true);
}

void SongView::notifyDrawerSongChanged()
{
    if (!m_editorDrawer)
        return;
    m_editorDrawer->automationPage()->songChanged();
    m_editorDrawer->velocityArea()->songChanged();
    m_editorDrawer->voiceChangeArea()->songChanged();
    refreshDrawerPages(DrawerScope::Content);
}

void SongView::refreshDrawerPages(DrawerScopes scopes)
{
    if (!m_editorDrawer)
        return;
    if (m_editorDrawer->pageVisible(EditorDrawerPage::Automations))
        refreshAutomationPage(scopes);
    if (m_editorDrawer->pageVisible(EditorDrawerPage::Velocity))
        refreshVelocityPage(scopes);
    if (m_editorDrawer->pageVisible(EditorDrawerPage::VoiceChanges))
        refreshVoiceChangePage(scopes);
}

void SongView::refreshAutomationPage(DrawerScopes scopes)
{
    if (!m_editorDrawer)
        return;
    m_editorDrawer->automationPage()->refresh(scopes);
}

void SongView::refreshVelocityPage(DrawerScopes scopes)
{
    if (!m_editorDrawer)
        return;
    m_editorDrawer->velocityArea()->refresh(scopes);
}

void SongView::refreshVoiceChangePage(DrawerScopes scopes)
{
    if (!m_editorDrawer)
        return;
    m_editorDrawer->voiceChangeArea()->refresh(scopes);
}

void SongView::refreshAllDrawerPages(DrawerScopes scopes)
{
    if (!m_editorDrawer)
        return;
    m_editorDrawer->automationPage()->refresh(scopes);
    m_editorDrawer->velocityArea()->refresh(scopes);
    m_editorDrawer->voiceChangeArea()->refresh(scopes);
}
