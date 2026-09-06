#pragma once

#include <algorithm>
#include <cassert>
#include <cstddef>
#include <cstdint>
#include <span>

#include "audio/audioengine.h"
#include "miniaudio.h"

namespace checks {

// Test-only access to the real AudioEngine process path. Callers must
// initialize and park the engine before rendering, and supply complete
// interleaved stereo frames.
class AudioEngineTestAccess final
{
  public:
    static bool parkDevice(AudioEngine &engine)
    {
        if (ma_device_stop(engine.m_device) != MA_SUCCESS)
            return false;
        engine.m_deviceStarted = false;
        return true;
    }

    static void renderParked(AudioEngine &engine, std::span<float> stereoOutput)
    {
        assert(stereoOutput.size() % 2 == 0);
        std::size_t done = 0;
        const std::size_t frames = stereoOutput.size() / 2;
        while (done < frames) {
            const auto chunk = uint32_t(std::min<std::size_t>(512, frames - done));
            engine.process(stereoOutput.data() + done * 2, chunk);
            done += chunk;
        }
    }
};

} // namespace checks
