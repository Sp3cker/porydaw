#pragma once

#include <cstdint>
#include <optional>
#include <utility>
#include <vector>

#include <QColor>
#include <QFlags>

#include <QPointF>

#include "core/noteid.h"
#include "core/timedefaults.h"

extern "C" {
#include "voicegroup_loader.h"
}

// Both fields are >= 1 and safe as divisors or loop strides.
struct DrawerPageGridState {
    uint32_t gridTicks = 0;
    uint32_t snapTicks = 0;
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
    Tick editCursorTick = 0;
    QColor trackColor;
    DrawerPagePlaybackState playback;
};

struct DrawerPageVoiceContext {
    const ToneData *voice = nullptr;
    int voiceSlot = -1;
    Tick endTick = CoreTimeDefaults::kNoTick;
};

struct DrawerPageTimeSelectionMenuRequest {
    Tick startTick = 0;
    Tick endTick = 0;
    std::vector<std::pair<int, uint8_t>> lanes;
    bool tempo = false;
    // Quick-window scene position of the menu anchor (never screen-global:
    // the shared popup layer is parented to the canvas window).
    QPointF scenePosition;
};

// Why a drawer page is being refreshed. Call sites on the SongView fan-out
// name the narrowest set their change justifies; handlers evaluate arms in
// fixed priority order (structural > geometry > transient).
enum class DrawerScope : quint8 {
    Document = 1u << 0,
    Content = 1u << 1,
    Selection = 1u << 2,
    HorizontalScroll = 1u << 3,
    Zoom = 1u << 4,
    Playhead = 1u << 5,
};
Q_DECLARE_FLAGS(DrawerScopes, DrawerScope)
Q_DECLARE_OPERATORS_FOR_FLAGS(DrawerScopes)
