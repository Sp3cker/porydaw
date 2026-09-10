#pragma once

#include <QFlags>

namespace songview {

enum class PianoRollQuickDirty : quint32 {
    None = 0,
    GridRows = 1u << 0,
    NoteFills = 1u << 1,
    DrawPreviewFill = 1u << 2,
    NoteBordersAndSelection = 1u << 3,
    Overlay = 1u << 4,
    KeyboardKeys = 1u << 5,
    KeyboardHighlights = 1u << 6,
    NoteText = 1u << 7,
    LoadingText = 1u << 8,
    KeyboardText = 1u << 9,
    HoverChip = 1u << 10,
    GridTime = 1u << 11,
    All = (1u << 12) - 1,
};
Q_DECLARE_FLAGS(PianoRollQuickDirtySet, PianoRollQuickDirty)
Q_DECLARE_OPERATORS_FOR_FLAGS(PianoRollQuickDirtySet)

inline constexpr PianoRollQuickDirtySet cPlotDirty =
    PianoRollQuickDirty::GridRows | PianoRollQuickDirty::GridTime | PianoRollQuickDirty::NoteFills |
    PianoRollQuickDirty::DrawPreviewFill | PianoRollQuickDirty::NoteBordersAndSelection |
    PianoRollQuickDirty::Overlay | PianoRollQuickDirty::NoteText;
// Pitch rows span the plot width but do not depend on horizontal camera state.
inline constexpr PianoRollQuickDirtySet cHorizontalCameraDirty =
    cPlotDirty & ~PianoRollQuickDirtySet(PianoRollQuickDirty::GridRows);
// Time lines span the plot height but do not depend on vertical camera state.
inline constexpr PianoRollQuickDirtySet cVerticalCameraDirty =
    PianoRollQuickDirty::All & ~PianoRollQuickDirtySet(PianoRollQuickDirty::GridTime);
inline constexpr PianoRollQuickDirtySet cPlotAndLoadingDirty =
    cPlotDirty | PianoRollQuickDirty::LoadingText;
inline constexpr PianoRollQuickDirtySet cNoteMutationDirty =
    PianoRollQuickDirty::NoteFills | PianoRollQuickDirty::NoteBordersAndSelection |
    PianoRollQuickDirty::NoteText;
inline constexpr PianoRollQuickDirtySet cVelocityMutationDirty =
    PianoRollQuickDirty::NoteFills | PianoRollQuickDirty::NoteText;
inline constexpr PianoRollQuickDirtySet cDrawCommitDirty =
    cNoteMutationDirty | PianoRollQuickDirty::DrawPreviewFill | PianoRollQuickDirty::Overlay;

} // namespace songview
