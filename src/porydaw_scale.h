#pragma once

#include <cstdint>

namespace porydaw_scale {

enum class ScaleId {
    major = 0,
    natural_minor = 1,
    dorian = 2,
    phrygian = 3,
    lydian = 4,
    mixolydian = 5,
    locrian = 6,
    harmonic_minor = 7,
    melodic_minor = 8,
    harmonic_major = 9,
    major_pentatonic = 10,
    minor_pentatonic = 11,
    minor_blues = 12,
    whole_tone = 13,
    half_whole_diminished = 14,
    whole_half_diminished = 15,
    dorian_sharp_4 = 16,
    phrygian_dominant = 17,
    lydian_augmented = 18,
    lydian_dominant = 19,
    altered = 20,
    eight_tone_spanish = 21,
    bhairav = 22,
    hungarian_minor = 23,
    hirajoshi = 24,
    in_sen = 25,
    iwato = 26,
    kumoi = 27,
};

constexpr int cRootCount = 12;
constexpr int cScaleCount = 28;

const char *scaleDisplayName(ScaleId id);
const char *rootDisplayName(int root);
bool isScalePitch(ScaleId id, int root, int midiPitch);
uint16_t scaleMask(ScaleId id);
ScaleId defaultScale();
int defaultRoot();
const ScaleId *displayOrder();

int firstScalePitchAbove(ScaleId id, int root, int midiPitch);
int firstScalePitchBelow(ScaleId id, int root, int midiPitch);
int nextScalePitch(ScaleId id, int root, int midiPitch, int steps);

// sourcePitches must be sorted. Repeated source pitches share the destination
// selected for their first occurrence. On boundary failure, destsOut is filled
// with uint8_t(-1).
bool resolveDiatonicDestinations(ScaleId id, int root, const uint8_t *sourcePitches,
                                 const int *degreeDisplacements, int count,
                                 uint8_t *destsOut);

} // namespace porydaw_scale
