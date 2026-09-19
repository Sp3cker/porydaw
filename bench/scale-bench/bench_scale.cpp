// Sequential reference twin of scale_sweep.bend.
// Same kernel as porydaw_scale::{scaleMask,isScalePitch} over 0..127/0..11.
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>

static constexpr uint16_t kMasks[28] = {
    2741, 1453, 1709, 1451, 2773, 1717, 1387, 2477, 2733, 2485, 661, 1193, 1257, 1365,
    1755, 2925, 1741, 1459, 2901, 1749, 1371, 1403, 2483, 2509, 397,  1187, 1123, 653,
};

static int pitchClass(int p)
{
    int r = p % 12;
    if (r < 0)
        r += 12;
    return r;
}

static bool isScalePitch(int scale, int root, int pitch)
{
    const uint16_t mask = kMasks[scale];
    const int interval = pitchClass(pitchClass(pitch) - pitchClass(root));
    return (mask & (uint16_t{1} << interval)) != 0;
}

int main(int argc, char **argv)
{
    const int reps = argc > 1 ? std::atoi(argv[1]) : 3000;
    uint32_t acc = 0;
    const auto t0 = std::chrono::steady_clock::now();
    for (int n = 0; n < reps; ++n)
        for (int s = 0; s < 28; ++s)
            for (int r = 0; r < 12; ++r)
                for (int p = 0; p < 128; ++p)
                    acc += isScalePitch(s, r, p) ? 1u : 0u;
    const auto t1 = std::chrono::steady_clock::now();
    const double ms =
        std::chrono::duration_cast<std::chrono::duration<double, std::milli>>(t1 - t0).count();
    std::printf("checksum=%u reps=%d ms=%.3f us_per_sweep=%.3f\n", acc, reps, ms,
                ms * 1000.0 / reps);
    return 0;
}
