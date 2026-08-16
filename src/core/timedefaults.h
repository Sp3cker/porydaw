#pragma once

#include <cstdint>

namespace CoreTimeDefaults {

inline constexpr int kTempoBpm = 120;

struct ControllerDefault {
    uint8_t cc;
    uint8_t value;
};

inline constexpr ControllerDefault kControllerDefaults[] = {
    {0x01, 0},   // MOD
    {0x05, 0},   // PORTAMENTO
    {0x07, 127}, // VOL
    {0x0A, 64},  // PAN
    {0x14, 2},   // BENDR
    {0x15, 22},  // LFOS
    {0x17, 0},   // PWMC
    {0x19, 0},   // PWMS
};

constexpr int controllerDefault(uint8_t cc)
{
    for (const ControllerDefault &entry : kControllerDefaults) {
        if (entry.cc == cc)
            return entry.value;
    }
    return -1;
}

} // namespace CoreTimeDefaults
