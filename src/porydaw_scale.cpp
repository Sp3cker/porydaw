#include "porydaw_scale.h"

namespace porydaw_scale {
namespace {

constexpr uint16_t cScaleMasks[cScaleCount] = {
    0xAB5, // Major
    0x5AD, // Natural Minor
    0x6AD, // Dorian
    0x5AB, // Phrygian
    0xAD5, // Lydian
    0x6B5, // Mixolydian
    0x56B, // Locrian
    0x9AD, // Harmonic Minor
    0xAAD, // Melodic Minor
    0x9B5, // Harmonic Major
    0x295, // Major Pentatonic
    0x4A9, // Minor Pentatonic
    0x4E9, // Minor Blues
    0x555, // Whole Tone
    0x6DB, // Half-Whole Diminished
    0xB6D, // Whole-Half Diminished
    0x6CD, // Dorian #4
    0x5B3, // Phrygian Dominant
    0xB55, // Lydian Augmented
    0x6D5, // Lydian Dominant
    0x55B, // Altered
    0x57B, // Eight-Tone Spanish
    0x9B3, // Bhairav
    0x9CD, // Hungarian Minor
    0x18D, // Hirajoshi
    0x4A3, // In Sen
    0x463, // Iwato
    0x28D, // Kumoi
};

constexpr const char *cScaleNames[cScaleCount] = {
    "Major",
    "Natural Minor",
    "Dorian",
    "Phrygian",
    "Lydian",
    "Mixolydian",
    "Locrian",
    "Harmonic Minor",
    "Melodic Minor",
    "Harmonic Major",
    "Major Pentatonic",
    "Minor Pentatonic",
    "Minor Blues",
    "Whole Tone",
    "Half-Whole Diminished",
    "Whole-Half Diminished",
    "Dorian #4",
    "Phrygian Dominant",
    "Lydian Augmented",
    "Lydian Dominant",
    "Altered (Super Locrian)",
    "8-Tone Spanish",
    "Bhairav",
    "Hungarian Minor",
    "Hirajoshi",
    "In-Sen",
    "Iwato",
    "Kumoi",
};

constexpr const char *cRootNames[cRootCount] = {
    "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
};

constexpr ScaleId cDisplayOrder[cScaleCount] = {
    ScaleId::major,
    ScaleId::natural_minor,
    ScaleId::dorian,
    ScaleId::phrygian,
    ScaleId::lydian,
    ScaleId::mixolydian,
    ScaleId::locrian,
    ScaleId::harmonic_minor,
    ScaleId::melodic_minor,
    ScaleId::harmonic_major,
    ScaleId::major_pentatonic,
    ScaleId::minor_pentatonic,
    ScaleId::minor_blues,
    ScaleId::whole_tone,
    ScaleId::half_whole_diminished,
    ScaleId::whole_half_diminished,
    ScaleId::dorian_sharp_4,
    ScaleId::phrygian_dominant,
    ScaleId::lydian_augmented,
    ScaleId::lydian_dominant,
    ScaleId::altered,
    ScaleId::eight_tone_spanish,
    ScaleId::bhairav,
    ScaleId::hungarian_minor,
    ScaleId::hirajoshi,
    ScaleId::in_sen,
    ScaleId::iwato,
    ScaleId::kumoi,
};

bool isValidScaleId(ScaleId id)
{
    const int value = static_cast<int>(id);
    return value >= 0 && value < cScaleCount;
}

int pitchClass(int pitch)
{
    int result = pitch % cRootCount;
    if (result < 0)
        result += cRootCount;
    return result;
}

void fillRejectedDests(std::span<uint8_t> destsOut)
{
    for (uint8_t &dest : destsOut)
        dest = static_cast<uint8_t>(-1);
}

} // namespace

const char *scaleDisplayName(ScaleId id)
{
    if (!isValidScaleId(id))
        return "";
    return cScaleNames[static_cast<int>(id)];
}

const char *rootDisplayName(int root)
{
    return cRootNames[pitchClass(root)];
}

bool isScalePitch(ScaleId id, int root, int midiPitch)
{
    const uint16_t mask = scaleMask(id);
    const int interval = pitchClass(pitchClass(midiPitch) - pitchClass(root));
    return (mask & (uint16_t{1} << interval)) != 0;
}

uint16_t scaleMask(ScaleId id)
{
    if (!isValidScaleId(id))
        return 0;
    return cScaleMasks[static_cast<int>(id)];
}

ScaleId defaultScale()
{
    return ScaleId::major;
}

int defaultRoot()
{
    return 0;
}

const ScaleId *displayOrder()
{
    return cDisplayOrder;
}

int firstScalePitchAbove(ScaleId id, int root, int midiPitch)
{
    if (!isValidScaleId(id) || midiPitch >= 127)
        return -1;
    const int firstPitch = midiPitch < 0 ? 0 : midiPitch + 1;
    for (int pitch = firstPitch; pitch <= 127; pitch++) {
        if (isScalePitch(id, root, pitch))
            return pitch;
    }
    return -1;
}

int firstScalePitchBelow(ScaleId id, int root, int midiPitch)
{
    if (!isValidScaleId(id) || midiPitch <= 0)
        return -1;
    const int firstPitch = midiPitch > 127 ? 127 : midiPitch - 1;
    for (int pitch = firstPitch; pitch >= 0; pitch--) {
        if (isScalePitch(id, root, pitch))
            return pitch;
    }
    return -1;
}

int nextScalePitch(ScaleId id, int root, int midiPitch, int steps)
{
    if (!isValidScaleId(id) || midiPitch < 0 || midiPitch > 127)
        return -1;
    int pitch = midiPitch;
    while (steps > 0) {
        pitch = firstScalePitchAbove(id, root, pitch);
        if (pitch < 0)
            return -1;
        steps--;
    }
    while (steps < 0) {
        pitch = firstScalePitchBelow(id, root, pitch);
        if (pitch < 0)
            return -1;
        steps++;
    }
    return pitch;
}

bool resolveDiatonicDestinations(ScaleId id, int root, std::span<const uint8_t> sourcePitches,
                                 std::span<const int> degreeDisplacements,
                                 std::span<uint8_t> destsOut)
{
    if (sourcePitches.size() != degreeDisplacements.size() ||
        sourcePitches.size() != destsOut.size()) {
        return false;
    }
    const auto count = sourcePitches.size();
    if (count == 0)
        return true;
    if (!isValidScaleId(id)) {
        fillRejectedDests(destsOut);
        return false;
    }

    bool movingDown = true;
    for (std::span<const uint8_t>::size_type i = 0; i < count; i++) {
        if (degreeDisplacements[i] > 0) {
            movingDown = false;
            break;
        }
    }

    if (!movingDown) {
        int previousDestination = -1;
        for (std::span<const uint8_t>::size_type i = 0; i < count; i++) {
            if (i > 0 && sourcePitches[i] == sourcePitches[i - 1]) {
                destsOut[i] = destsOut[i - 1];
                continue;
            }
            int destination = nextScalePitch(id, root, sourcePitches[i], degreeDisplacements[i]);
            if (destination < 0) {
                fillRejectedDests(destsOut);
                return false;
            }
            if (previousDestination >= 0 && destination <= previousDestination)
                destination = firstScalePitchAbove(id, root, previousDestination);
            if (destination < 0) {
                fillRejectedDests(destsOut);
                return false;
            }
            destsOut[i] = static_cast<uint8_t>(destination);
            previousDestination = destination;
        }
        return true;
    }

    int previousDestination = 128;
    for (auto i = count; i-- > 0;) {
        if (i > 0 && sourcePitches[i] == sourcePitches[i - 1])
            continue;
        int destination = nextScalePitch(id, root, sourcePitches[i], degreeDisplacements[i]);
        if (destination < 0) {
            fillRejectedDests(destsOut);
            return false;
        }
        if (destination >= previousDestination)
            destination = firstScalePitchBelow(id, root, previousDestination);
        if (destination < 0) {
            fillRejectedDests(destsOut);
            return false;
        }
        auto lastDuplicate = i;
        while (lastDuplicate + 1 < count && sourcePitches[lastDuplicate + 1] == sourcePitches[i])
            lastDuplicate++;
        for (auto duplicate = i; duplicate <= lastDuplicate; duplicate++)
            destsOut[duplicate] = static_cast<uint8_t>(destination);
        previousDestination = destination;
    }
    return true;
}

} // namespace porydaw_scale
