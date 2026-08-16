#include <QString>
#include <cstdio>
#include <cstring>

#include "porydaw_scale.h"

namespace {

struct ExpectedScale {
    porydaw_scale::ScaleId id;
    const char *name;
    uint16_t mask;
};

constexpr ExpectedScale cExpectedScales[] = {
    {porydaw_scale::ScaleId::major, "Major", 0xAB5},
    {porydaw_scale::ScaleId::natural_minor, "Natural Minor", 0x5AD},
    {porydaw_scale::ScaleId::dorian, "Dorian", 0x6AD},
    {porydaw_scale::ScaleId::phrygian, "Phrygian", 0x5AB},
    {porydaw_scale::ScaleId::lydian, "Lydian", 0xAD5},
    {porydaw_scale::ScaleId::mixolydian, "Mixolydian", 0x6B5},
    {porydaw_scale::ScaleId::locrian, "Locrian", 0x56B},
    {porydaw_scale::ScaleId::harmonic_minor, "Harmonic Minor", 0x9AD},
    {porydaw_scale::ScaleId::melodic_minor, "Melodic Minor", 0xAAD},
    {porydaw_scale::ScaleId::harmonic_major, "Harmonic Major", 0x9B5},
    {porydaw_scale::ScaleId::major_pentatonic, "Major Pentatonic", 0x295},
    {porydaw_scale::ScaleId::minor_pentatonic, "Minor Pentatonic", 0x4A9},
    {porydaw_scale::ScaleId::minor_blues, "Minor Blues", 0x4E9},
    {porydaw_scale::ScaleId::whole_tone, "Whole Tone", 0x555},
    {porydaw_scale::ScaleId::half_whole_diminished, "Half-Whole Diminished", 0x6DB},
    {porydaw_scale::ScaleId::whole_half_diminished, "Whole-Half Diminished", 0xB6D},
    {porydaw_scale::ScaleId::dorian_sharp_4, "Dorian #4", 0x6CD},
    {porydaw_scale::ScaleId::phrygian_dominant, "Phrygian Dominant", 0x5B3},
    {porydaw_scale::ScaleId::lydian_augmented, "Lydian Augmented", 0xB55},
    {porydaw_scale::ScaleId::lydian_dominant, "Lydian Dominant", 0x6D5},
    {porydaw_scale::ScaleId::altered, "Altered (Super Locrian)", 0x55B},
    {porydaw_scale::ScaleId::eight_tone_spanish, "8-Tone Spanish", 0x57B},
    {porydaw_scale::ScaleId::bhairav, "Bhairav", 0x9B3},
    {porydaw_scale::ScaleId::hungarian_minor, "Hungarian Minor", 0x9CD},
    {porydaw_scale::ScaleId::hirajoshi, "Hirajoshi", 0x18D},
    {porydaw_scale::ScaleId::in_sen, "In-Sen", 0x4A3},
    {porydaw_scale::ScaleId::iwato, "Iwato", 0x463},
    {porydaw_scale::ScaleId::kumoi, "Kumoi", 0x28D},
};

} // namespace

int runScaleCheck(const QString &projectRoot)
{
    static_cast<void>(projectRoot);
    int failures = 0;
    const auto expect = [&failures](bool condition, const char *message) {
        if (!condition) {
            std::fprintf(stderr, "scalecheck: %s\n", message);
            failures++;
        }
    };

    expect(porydaw_scale::cRootCount == 12, "wrong root count");
    expect(porydaw_scale::cScaleCount == 28, "wrong scale count");
    const porydaw_scale::ScaleId *order = porydaw_scale::displayOrder();
    expect(order != nullptr, "missing display order");
    for (int i = 0; i < porydaw_scale::cScaleCount; i++) {
        const ExpectedScale &scale = cExpectedScales[i];
        expect(static_cast<int>(scale.id) == i, "wrong stable scale ID");
        expect(std::strcmp(porydaw_scale::scaleDisplayName(scale.id), scale.name) == 0,
               "wrong scale display name");
        expect(porydaw_scale::scaleMask(scale.id) == scale.mask, "wrong scale mask");
        expect(order && order[i] == scale.id, "wrong display order");
    }

    constexpr const char *cRootNames[] = {
        "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
    };
    for (int root = 0; root < porydaw_scale::cRootCount; root++)
        expect(std::strcmp(porydaw_scale::rootDisplayName(root), cRootNames[root]) == 0,
               "wrong root display name");

    expect(porydaw_scale::defaultScale() == porydaw_scale::ScaleId::major,
           "wrong default scale");
    expect(porydaw_scale::defaultRoot() == 0, "wrong default root");
    expect(porydaw_scale::isScalePitch(porydaw_scale::ScaleId::major, 0, 60),
           "C is missing from C Major");
    expect(!porydaw_scale::isScalePitch(porydaw_scale::ScaleId::major, 0, 61),
           "C# is present in C Major");
    expect(porydaw_scale::isScalePitch(porydaw_scale::ScaleId::major, 2, 62),
           "D is missing from D Major");
    expect(!porydaw_scale::isScalePitch(porydaw_scale::ScaleId::major, 2, 60),
           "C is present in D Major");

    expect(porydaw_scale::firstScalePitchAbove(porydaw_scale::ScaleId::major, 0, 61) == 62,
           "wrong scale pitch above C#");
    expect(porydaw_scale::firstScalePitchBelow(porydaw_scale::ScaleId::major, 0, 61) == 60,
           "wrong scale pitch below C#");
    expect(porydaw_scale::firstScalePitchAbove(porydaw_scale::ScaleId::major, 0, 127) == -1,
           "pitch above MIDI ceiling accepted");
    expect(porydaw_scale::firstScalePitchBelow(porydaw_scale::ScaleId::major, 0, 0) == -1,
           "pitch below MIDI floor accepted");

    expect(porydaw_scale::nextScalePitch(porydaw_scale::ScaleId::major, 0, 60, 1) == 62,
           "wrong one-degree upward move");
    expect(porydaw_scale::nextScalePitch(porydaw_scale::ScaleId::major, 0, 62, -1) == 60,
           "wrong one-degree downward move");
    expect(porydaw_scale::nextScalePitch(porydaw_scale::ScaleId::major, 0, 60, 3) == 65,
           "wrong multi-degree upward move");
    expect(porydaw_scale::nextScalePitch(porydaw_scale::ScaleId::major, 0, 67, -3) == 62,
           "wrong multi-degree downward move");

    const uint8_t upwardSources[] = {60, 61};
    const int upwardDegrees[] = {1, 1};
    uint8_t upwardDests[] = {0, 0};
    expect(porydaw_scale::resolveDiatonicDestinations(porydaw_scale::ScaleId::major, 0,
                                                        upwardSources, upwardDegrees, 2,
                                                        upwardDests),
           "C and C# upward move rejected");
    expect(upwardDests[0] == 62 && upwardDests[1] == 64,
           "C and C# upward move did not separate destinations");

    const uint8_t downwardSources[] = {61, 62};
    const int downwardDegrees[] = {-1, -1};
    uint8_t downwardDests[] = {0, 0};
    expect(porydaw_scale::resolveDiatonicDestinations(porydaw_scale::ScaleId::major, 0,
                                                        downwardSources, downwardDegrees, 2,
                                                        downwardDests),
           "C# and D downward move rejected");
    expect(downwardDests[0] == 59 && downwardDests[1] == 60,
           "C# and D downward move did not separate destinations");

    const uint8_t repeatedSources[] = {60, 60, 61};
    const int repeatedDegrees[] = {1, 4, 1};
    uint8_t repeatedDests[] = {0, 0, 0};
    expect(porydaw_scale::resolveDiatonicDestinations(porydaw_scale::ScaleId::major, 0,
                                                        repeatedSources, repeatedDegrees, 3,
                                                        repeatedDests),
           "repeated-source move rejected");
    expect(repeatedDests[0] == 62 && repeatedDests[1] == 62,
           "repeated source pitches did not share a destination");
    expect(repeatedDests[2] == 64, "repeated-source move lost uniqueness");

    const uint8_t orderedSources[] = {60, 61, 62};
    const int orderedDegrees[] = {1, 1, 1};
    uint8_t orderedDests[] = {0, 0, 0};
    expect(porydaw_scale::resolveDiatonicDestinations(porydaw_scale::ScaleId::major, 0,
                                                        orderedSources, orderedDegrees, 3,
                                                        orderedDests),
           "ordered move rejected");
    expect(orderedDests[0] == 62 && orderedDests[1] == 64 && orderedDests[2] == 65,
           "ordered move did not preserve destination order");
    expect(orderedDests[0] < orderedDests[1] && orderedDests[1] < orderedDests[2],
           "distinct pitches did not resolve uniquely");

    const uint8_t highSource[] = {127};
    const int highDegree[] = {1};
    uint8_t highDest[] = {0};
    expect(!porydaw_scale::resolveDiatonicDestinations(porydaw_scale::ScaleId::major, 0,
                                                         highSource, highDegree, 1, highDest),
           "upper MIDI boundary was not rejected");
    expect(highDest[0] == static_cast<uint8_t>(-1), "upper MIDI boundary did not clear output");

    const uint8_t lowSource[] = {0};
    const int lowDegree[] = {-1};
    uint8_t lowDest[] = {42};
    expect(!porydaw_scale::resolveDiatonicDestinations(porydaw_scale::ScaleId::major, 0,
                                                         lowSource, lowDegree, 1, lowDest),
           "lower MIDI boundary was not rejected");

    if (failures == 0) {
        std::printf("scalecheck: PASS\n");
        return 0;
    }
    std::printf("scalecheck: FAIL (%d failures)\n", failures);
    return 1;
}
