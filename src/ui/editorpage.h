#pragma once

#include <cstdint>
#include <optional>
#include <utility>
#include <vector>

#include <QColor>
#include <QPoint>

#include "core/noteid.h"

extern "C" {
#include "voicegroup_loader.h"
}

struct EditorPageGridState {
    uint64_t gridTicks = 0;
    uint64_t snapTicks = 0;
};

struct EditorPagePlaybackState {
    double playheadTick = 0.0;
    bool playing = false;
};

// Live values shared by concrete editor surfaces. The document revision lets
// an interaction discard a frozen edit when the model changes underneath it.
struct EditorPageLiveState {
    uint64_t documentRevision = 0;
    double timeZoom = 1.0;
    double horizontalScroll = 0.0;
    uint64_t editCursorTick = 0;
    QColor trackColor;
    EditorPagePlaybackState playback;
};

struct EditorPageVoiceContext {
    const ToneData *voice = nullptr;
    int voiceSlot = -1;
};

enum class EditorPageEditCommand : uint8_t {
    Copy,
    Cut,
    Paste,
    SelectAll,
    Delete,
    Transpose,
    NudgeNotePosition,
};

enum class EditorPageEditDirection : uint8_t {
    None,
    Negative,
    Positive,
};

struct EditorPageEditCommandRequest {
    EditorPageEditCommand command = EditorPageEditCommand::Copy;
    // Negative means down or left; Positive means up or right.
    EditorPageEditDirection direction = EditorPageEditDirection::None;
};

struct EditorPageTimeSelectionMenuRequest {
    uint64_t startTick = 0;
    uint64_t endTick = 0;
    std::vector<std::pair<int, uint8_t>> lanes;
    QPoint globalPosition;
};

struct EditorPageNoteStatus {
    uint8_t key = 0;
    uint8_t storedVelocity = 0;
    uint8_t effectiveVelocity = 0;
    uint64_t durationTicks = 0;
    uint64_t durationClocks = 0;
};
