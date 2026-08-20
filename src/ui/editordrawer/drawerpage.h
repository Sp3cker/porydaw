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

struct DrawerPageGridState {
    uint64_t gridTicks = 0;
    uint64_t snapTicks = 0;
};

struct DrawerPagePlaybackState {
    double playheadTick = 0.0;
    bool playing = false;
};

// Live values shared by concrete drawer surfaces. The document revision lets
// an interaction discard a frozen edit when the model changes underneath it.
struct DrawerPageLiveState {
    uint64_t documentRevision = 0;
    double timeZoom = 1.0;
    double horizontalScroll = 0.0;
    uint64_t editCursorTick = 0;
    QColor trackColor;
    DrawerPagePlaybackState playback;
};

struct DrawerPageVoiceContext {
    const ToneData *voice = nullptr;
    int voiceSlot = -1;
    uint64_t endTick = UINT64_MAX;
};

struct DrawerPageTimeSelectionMenuRequest {
    uint64_t startTick = 0;
    uint64_t endTick = 0;
    std::vector<std::pair<int, uint8_t>> lanes;
    bool tempo = false;
    QPoint globalPosition;
};

struct DrawerPageNoteStatus {
    uint8_t key = 0;
    uint8_t storedVelocity = 0;
    uint8_t effectiveVelocity = 0;
    uint64_t durationTicks = 0;
    uint64_t durationClocks = 0;
};
