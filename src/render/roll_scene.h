#pragma once

#include "roll_content.h"
#include "roll_projection.h"

#include <vector>

namespace RollScene {

using RollProjection::Rect;

struct PaintedNote {
    Rect box;
    uint64_t id = 0;
    uint8_t pitch = 0;
    uint8_t velocity = 0;
    uint8_t flags = 0;
};

struct Frame {
    const RollContent::Content &content;
    const RollProjection::Camera &camera;
    double width = 0;
    double height = 0;
};

struct BandSelection {
    bool active = false;
    Rect rect;
};

void appendRows(const Frame &f, std::vector<Rect> &out);
void appendPreRollMask(const Frame &f, std::vector<Rect> &out);
void appendTimeGrid(const Frame &f, std::vector<Rect> &out);
void appendNoteFills(const Frame &f, std::vector<uint32_t> &visible, std::vector<Rect> &out,
                     std::vector<PaintedNote> &painted);
bool drawPreviewBox(const Frame &f, Rect &box);
void appendNoteFrames(const Frame &f, const std::vector<PaintedNote> &painted,
                      const Rect *preview, const BandSelection &band, std::vector<Rect> &out);
void appendBandSelection(const Frame &f, const BandSelection &band, std::vector<Rect> &out);
void appendTimeSelection(const Frame &f, std::vector<Rect> &out);
void appendLoop(const Frame &f, std::vector<Rect> &out);
void appendKeys(const Frame &f, int hoverPitch, std::vector<Rect> &under,
                std::vector<Rect> &over);

} // namespace RollScene
