#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/eventlistview.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/timelinequickview.h"
#include <algorithm>
#include <array>
#include <cstdint>
#include <optional>
#include <ranges>
#include <span>
#include <utility>
#include <vector>

using namespace songview;
using namespace songview::detail;

void SongView::notifyVelocityGestureChanged()
{
    if (m_roll)
        m_roll->requestQuickUpdate(cVelocityMutationDirty);
    if (m_editorDrawer)
        m_editorDrawer->velocityArea()->velocityGestureChanged();
}
bool SongView::beginVelocityGesture(const std::vector<DocNote> &notes)
{
    if (!m_document)
        return false;
    std::vector<NoteVelocity> targets;
    targets.reserve(notes.size());
    for (const DocNote &note : notes)
        targets.push_back({note.noteId, int(note.velocity)});
    if (!m_velocityGesture.begin(m_document->revision(), std::move(targets)))
        return false;
    notifyVelocityGestureChanged();
    return true;
}
bool SongView::updateVelocityGesture(const std::vector<NoteVelocity> &updates)
{
    if (!m_velocityGesture.update(updates))
        return false;
    notifyVelocityGestureChanged();
    return true;
}
bool SongView::updateVelocityGestureByDelta(int delta)
{
    if (!m_velocityGesture.updateByDelta(delta))
        return false;
    notifyVelocityGestureChanged();
    return true;
}
void SongView::cancelVelocityGesture()
{
    if (m_velocityGesture.cancel())
        notifyVelocityGestureChanged();
}
SongView::VelocityCommitResult SongView::commitVelocityGesture()
{
    std::optional<VelocityGestureModel::Completion> completion = m_velocityGesture.takeCompletion();
    if (!completion)
        return VelocityCommitResult::NoGesture;
    const uint64_t expectedRevision = completion->expectedRevision;
    notifyVelocityGestureChanged();
    if (!m_document)
        return VelocityCommitResult::Rejected;
    const DocumentSwapHintScope swapHint{*this, cVelocityMutationDirty};
    const std::optional<uint64_t> revision =
        m_document->setNotesVelocities(expectedRevision, completion->targets);
    if (!revision)
        return VelocityCommitResult::Rejected;
    if (*revision > expectedRevision)
        return VelocityCommitResult::Committed;
    if (*revision == expectedRevision)
        return VelocityCommitResult::Unchanged;
    return VelocityCommitResult::Rejected;
}
std::optional<uint8_t> SongView::previewVelocity(NoteId noteId) const
{
    return m_velocityGesture.previewVelocity(noteId);
}
void SongView::setScaleHighlight(bool enabled)
{
    if (enabled == m_scaleController.scaleHighlight())
        return;
    m_scaleController.setScaleHighlight(enabled);
    m_roll->requestQuickUpdate(PianoRollQuickDirty::Grid);
    emit scaleHighlightChanged();
}
void SongView::setScaleFold(bool enabled)
{
    if (enabled == m_scaleController.scaleFold())
        return;
    m_scaleController.setScaleFold(enabled);
    rebuildProjectionWithAnchoring();
    emit scaleFoldChanged();
}
void SongView::setScaleRoot(int root)
{
    root = std::clamp(root, 0, 11);
    if (root == m_scaleController.scaleRoot())
        return;
    m_scaleController.setScaleRoot(root);
    m_scaleController.rebuildClassification(m_projection);
    // Folding rebuilds the projection, so only a fold repaints everything;
    // a highlight-only change just re-tints the grid.
    if (m_scaleController.scaleFold())
        m_roll->requestQuickUpdate(PianoRollQuickDirty::All);
    else if (m_scaleController.scaleHighlight())
        m_roll->requestQuickUpdate(PianoRollQuickDirty::Grid);
    emit scaleRootChanged();
}
void SongView::setScaleId(porydaw_scale::ScaleId id)
{
    if (id == m_scaleController.scaleId())
        return;
    m_scaleController.setScaleId(id);
    m_scaleController.rebuildClassification(m_projection);
    // Folding rebuilds the projection, so only a fold repaints everything;
    // a highlight-only change just re-tints the grid.
    if (m_scaleController.scaleFold())
        m_roll->requestQuickUpdate(PianoRollQuickDirty::All);
    else if (m_scaleController.scaleHighlight())
        m_roll->requestQuickUpdate(PianoRollQuickDirty::Grid);
    emit scaleIdChanged();
}
void SongView::setProjectionLocked(bool locked)
{
    m_projectionLocked = locked;
}
void SongView::flushProjectionIfDirty()
{
    if (!m_projectionLocked && m_projectionDirty) {
        m_projectionDirty = false;
        rebuildProjectionWithAnchoring();
    }
}
void SongView::requestProjectionRebuild()
{
    if (m_projectionLocked)
        m_projectionDirty = true;
    else
        rebuildProjectionWithAnchoring();
}

void SongView::buildOccupancySet(std::span<bool, 128> out) const
{
    std::ranges::fill(out, false);
    for (const ViewNote &note : m_model.notes) {
        if (note.track == m_selectionModel.primaryTrack())
            out[note.key] = true;
    }
}
void SongView::rebuildProjectionWithAnchoring()
{
    m_projectionDirty = false;
    if (!m_timeline)
        return;

    const double centerY = rollViewportHeight() / 2.0;
    const int centerPitch =
        m_projection.yToPitch(centerY, m_keyHeight, m_scrollY, m_roll->devicePixelRatioF());
    updateScaleProjection();

    double newScrollY = m_scrollY;
    if (centerPitch != PitchProjection::cHiddenRow) {
        const int anchorPitch = m_projection.nearestVisiblePitch(centerPitch);
        const int anchorRow = m_projection.rowForPitch(anchorPitch);
        if (anchorRow != PitchProjection::cHiddenRow)
            newScrollY = anchorRow * m_keyHeight - centerY;
    }
    m_scrollY = std::clamp(newScrollY, 0.0, maxRollScroll());
    updateScrollbars();
    m_roll->requestQuickUpdate(PianoRollQuickDirty::All);
}
void SongView::updateScaleProjection()
{
    std::array<bool, 128> occupancy{};
    if (m_scaleController.scaleFold())
        buildOccupancySet(std::span<bool, 128>(occupancy));
    m_scaleController.rebuildProjection(m_projection, std::span<const bool, 128>(occupancy));
    m_scaleController.rebuildClassification(m_projection);
}
void SongView::setVelocityColorMode(bool on)
{
    if (m_velocityColorMode == on)
        return;
    m_velocityColorMode = on;
    m_roll->requestQuickUpdate(PianoRollQuickDirty::NoteFills |
                               PianoRollQuickDirty::DrawPreviewFill |
                               PianoRollQuickDirty::NoteText);
}
void SongView::setNoteNameMode(bool on)
{
    if (m_noteNameMode == on)
        return;
    m_noteNameMode = on;
    m_roll->requestQuickUpdate(PianoRollQuickDirty::NoteText);
}
void SongView::setFollowPlayhead(bool on)
{
    if (m_followPlayhead == on)
        return;
    m_followPlayhead = on;
    m_events->setFollowPlayhead(on);
    refreshDrawerPages();
}
void SongView::addEmptyLane(int track, uint8_t cc)
{
    if (track < 0 || track > 15)
        return;
    const EditorAutomationRowId lane{EditorAutomationRowKind::ControlChange, uint8_t(track), cc};
    EditorViewState next = m_editorViewState;
    if (!next.emptyLanes.insert(lane).second)
        return;
    setEditorViewState(next);
}
void SongView::removeEmptyLane(int track, uint8_t cc)
{
    if (track < 0 || track > 15)
        return;
    const EditorAutomationRowId lane{EditorAutomationRowKind::ControlChange, uint8_t(track), cc};
    EditorViewState next = m_editorViewState;
    if (next.emptyLanes.erase(lane) == 0)
        return;
    setEditorViewState(next);
}
void SongView::setLaneDisplayRange(int track, uint8_t cc, int maxValue)
{
    if (track < 0 || track > 15)
        return;
    const EditorAutomationRowId lane{EditorAutomationRowKind::ControlChange, uint8_t(track), cc};
    EditorViewState next = m_editorViewState;
    if (maxValue > 0) {
        const uint8_t range = uint8_t(std::clamp(maxValue, 0, 127));
        const auto it = next.laneRanges.find(lane);
        const bool unchanged = it != next.laneRanges.end() && it->second == range;
        next.laneRanges[lane] = range;
        if (unchanged)
            return;
    } else if (next.laneRanges.erase(lane) == 0) {
        return;
    }
    setEditorViewState(next);
}
EditorViewState SongView::editorViewState() const
{
    return m_editorViewState;
}
void SongView::applyEditorViewStateToWidgets(bool drawerChanged)
{
    if (drawerChanged && m_editorDrawer)
        m_editorDrawer->setViewState(m_editorViewState);
    refreshAllDrawerPages();
    // Drawer/view-state replacement can affect any roll domain.
    refreshTimelineViews(PianoRollQuickDirty::All);
}
void SongView::setEditorViewState(const EditorViewState &state)
{
    if (m_editorViewState == state)
        return;
    const bool drawerChanged = m_editorViewState.drawerState() != state.drawerState();
    m_editorViewState = state;
    applyEditorViewStateToWidgets(drawerChanged);
    emit editorViewStateChanged(m_editorViewState);
}
void SongView::applyEditorViewState(const EditorViewState &state)
{
    if (m_editorViewState == state)
        return;
    const bool drawerChanged = m_editorViewState.drawerState() != state.drawerState();
    cancelActiveInteractions();
    m_editorViewState = state;
    applyEditorViewStateToWidgets(drawerChanged);
}
