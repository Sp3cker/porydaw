#pragma once

#include "ui/songview/clip.h"

#include <QByteArray>
#include <cstdint>
#include <optional>

namespace songview {

inline constexpr char kClipMimeType[] = "application/x-porydaw-clip";

struct DecodedClip {
    Clip clip;
    uint32_t ticksPerBeat = 0;
};

QByteArray encodeClip(const Clip &clip, uint32_t ticksPerBeat);
std::optional<DecodedClip> decodeClip(const QByteArray &payload);
Clip rescaleClip(Clip clip, uint32_t sourceTicksPerBeat, uint32_t destinationTicksPerBeat);

void writeClipboard(const Clip &clip, uint32_t ticksPerBeat);
// The clipboard clip rescaled to destinationTicksPerBeat, or nullopt when
// the clipboard holds no clip. When a clip payload is present but cannot be
// decoded, *outDecodeFailed is set (the one case callers announce).
std::optional<Clip> readClipboard(uint32_t destinationTicksPerBeat,
                                  bool *outDecodeFailed = nullptr);
bool clipboardHasClipMime();

} // namespace songview