#include "core/velocitymodel.h"
#include "ui/editordrawer/velocityaxis.h"
#include "ui/velocitygesturemodel.h"

#include <array>
#include <cstddef>
#include <cstdio>
#include <cstring>
#include <optional>
#include <vector>

#include <QPointF>

namespace {

bool equals(const std::optional<std::size_t> &value, std::size_t expected)
{
    return value && *value == expected;
}

bool labelsMatch(const VelocityAxis &axis, const uint8_t *expected, std::size_t count)
{
    if (axis.labelCount() != count)
        return false;
    for (std::size_t index = 0; index < count; ++index) {
        if (axis.labels()[index].velocity != expected[index])
            return false;
    }
    return true;
}

bool intrinsicLevelsRoundTrip(const VelocityAxis &axis)
{
    for (std::size_t level = 0; level < axis.graduationCount(); ++level) {
        if (axis.yToLevel(axis.levelToY(int(level))) != int(level))
            return false;
    }
    return true;
}

VelocityAxisGeometry axisGeometry(double height, double labelWidth = 200.0)
{
    return {height, 6.0, labelWidth, 2.0, 1.0, 12.0, 84.0, 112.0, 156.0, 300.0};
}

} // namespace

int runVelocityModelCheck()
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        if (!condition) {
            std::fprintf(stderr, "velocity-model: FAIL: %s\n", message);
            ++failures;
        }
    };

    const NoteVelocity firstGestureTarget{NoteId(1), 40};
    const NoteVelocity secondGestureTarget{NoteId(2), 120};
    const std::vector<NoteVelocity> sortedGestureTargets = {
        firstGestureTarget,
        secondGestureTarget,
    };
    VelocityGestureModel gesture;
    check(!gesture.active() && !gesture.update({firstGestureTarget}) &&
              !gesture.previewVelocity(firstGestureTarget.noteId) && !gesture.takeCompletion() &&
              !gesture.cancel(),
          "inactive gesture model must reject updates, previews, completion, and cancellation");
    check(!gesture.begin(42, {}) && !gesture.begin(42, {{NoteId(), 40}}) &&
              !gesture.begin(42, {{NoteId(3), 0}}) && !gesture.begin(42, {{NoteId(3), 128}}) &&
              !gesture.begin(42, {firstGestureTarget, firstGestureTarget}) &&
              !gesture.begin(42, {firstGestureTarget, secondGestureTarget, secondGestureTarget}) &&
              !gesture.active(),
          "empty, invalid, or duplicate targets must fail without activating a gesture");
    check(gesture.begin(42, {secondGestureTarget, firstGestureTarget}) && gesture.active() &&
              gesture.previewVelocity(firstGestureTarget.noteId) == firstGestureTarget.velocity &&
              gesture.previewVelocity(secondGestureTarget.noteId) == secondGestureTarget.velocity,
          "gesture model must capture a sorted unique target set and original velocities");
    check(!gesture.begin(43, {secondGestureTarget}) && gesture.active() &&
              gesture.previewVelocity(firstGestureTarget.noteId) == firstGestureTarget.velocity &&
              gesture.previewVelocity(secondGestureTarget.noteId) == secondGestureTarget.velocity,
          "an active gesture must not be replaced by another interaction");
    check(!gesture.update({{firstGestureTarget.noteId, 100}, {NoteId(3), 64}}) &&
              gesture.previewVelocity(firstGestureTarget.noteId) == firstGestureTarget.velocity &&
              gesture.previewVelocity(secondGestureTarget.noteId) == secondGestureTarget.velocity,
          "unknown updates must fail atomically");
    check(
        !gesture.update({}) &&
            !gesture.update({{firstGestureTarget.noteId, 100}, {firstGestureTarget.noteId, 110}}) &&
            gesture.previewVelocity(firstGestureTarget.noteId) == firstGestureTarget.velocity,
        "empty or duplicate updates must fail atomically");
    check(gesture.update({{firstGestureTarget.noteId, 0}}) &&
              gesture.previewVelocity(firstGestureTarget.noteId) == 1 &&
              gesture.update({{firstGestureTarget.noteId, 128}}) &&
              gesture.previewVelocity(firstGestureTarget.noteId) == 127,
          "out-of-range updates must clamp without disturbing the session");
    check(gesture.update({{firstGestureTarget.noteId, 100}}) &&
              gesture.previewVelocity(firstGestureTarget.noteId) == 100 &&
              gesture.previewVelocity(secondGestureTarget.noteId) == secondGestureTarget.velocity,
          "valid per-note preview updates must apply");
    check(gesture.updateByDelta(-50) && gesture.previewVelocity(firstGestureTarget.noteId) == 1 &&
              gesture.previewVelocity(secondGestureTarget.noteId) == 70,
          "relative updates must resolve from each captured original");
    const auto completion = gesture.takeCompletion();
    check(completion && completion->expectedRevision == 42 &&
              completion->targets.size() == sortedGestureTargets.size() &&
              completion->targets[0].noteId == sortedGestureTargets[0].noteId &&
              completion->targets[0].velocity == 1 &&
              completion->targets[1].noteId == sortedGestureTargets[1].noteId &&
              completion->targets[1].velocity == 70,
          "taking a completion must move its revision and sorted target contents");
    check(!gesture.active() && !gesture.previewVelocity(firstGestureTarget.noteId) &&
              !gesture.previewVelocity(secondGestureTarget.noteId) && !gesture.takeCompletion(),
          "taking a completion must reset the inactive model state");
    check(gesture.begin(99, sortedGestureTargets) && gesture.cancel() && !gesture.active() &&
              !gesture.previewVelocity(firstGestureTarget.noteId) &&
              !gesture.previewVelocity(secondGestureTarget.noteId) && !gesture.takeCompletion() &&
              !gesture.cancel(),
          "cancellation must discard a session and leave inactive reset state");

    ToneData squareTone{};
    squareTone.type = VOICE_SQUARE_1;
    ToneData squareTwoTone{};
    squareTwoTone.type = VOICE_SQUARE_2;
    ToneData noiseTone{};
    noiseTone.type = VOICE_NOISE;
    ToneData waveTone{};
    waveTone.type = VOICE_PROGRAMMABLE_WAVE;
    ToneData directSoundTone{};
    directSoundTone.type = VOICE_DIRECTSOUND;
    const VelocityMap square = VelocityMap::resolve(&squareTone, 60);
    const VelocityMap squareTwo = VelocityMap::resolve(&squareTwoTone, 60);
    const VelocityMap noise = VelocityMap::resolve(&noiseTone, 60);
    const VelocityMap wave = VelocityMap::resolve(&waveTone, 60);
    const VelocityMap directSound = VelocityMap::resolve(&directSoundTone, 60);
    const VelocityMap unresolved = VelocityMap::resolve(nullptr, std::nullopt);

    check(square.isPsg() && std::strcmp(square.voiceName(), "Square 1") == 0,
          "Square 1 should resolve intrinsically");
    check(squareTwo.isPsg() && std::strcmp(squareTwo.voiceName(), "Square 2") == 0,
          "Square 2 should resolve intrinsically");
    check(noise.isPsg() && std::strcmp(noise.voiceName(), "Noise") == 0,
          "Noise should resolve intrinsically");
    check(wave.isPsg() && std::strcmp(wave.voiceName(), "Programmable Wave") == 0,
          "Wave should resolve intrinsically");
    check(!directSound.isPsg(), "DirectSound should remain continuous");
    check(!unresolved.isPsg(), "missing voice should remain unresolved");

    ToneData invalidTone{};
    invalidTone.type = VOICE_CRY;
    const VelocityMap invalid = VelocityMap::resolve(&invalidTone, 60);
    check(!invalid.isPsg(), "invalid voice should remain continuous");
    std::array<ToneData, 128> nestedChildren{};
    nestedChildren[60].type = VOICE_KEYSPLIT;
    ToneData nestedSplit{};
    nestedSplit.type = VOICE_KEYSPLIT_ALL;
    nestedSplit.subGroup = nestedChildren.data();
    check(!VelocityMap::resolve(&nestedSplit, 60).isPsg(), "nested keysplit should be invalid");
    ToneData keylessSplit{};
    keylessSplit.type = VOICE_KEYSPLIT_ALL;
    keylessSplit.subGroup = nestedChildren.data();
    check(!VelocityMap::resolve(&keylessSplit, std::nullopt).isPsg(),
          "keyless keysplit should remain continuous");
    std::array<ToneData, 128> splitChildren{};
    std::array<uint8_t, 128> splitTable{};
    splitChildren[7].type = VOICE_PROGRAMMABLE_WAVE;
    splitTable[60] = 7;
    ToneData splitTone{};
    splitTone.type = VOICE_KEYSPLIT;
    splitTone.subGroup = splitChildren.data();
    splitTone.keySplitTable = splitTable.data();
    const VelocityMap keyedSplit = VelocityMap::resolve(&splitTone, 60);
    check(keyedSplit.isPsg() && std::strcmp(keyedSplit.voiceName(), "Programmable Wave") == 0,
          "keyed keysplit should resolve its selected voice");

    const std::array<uint8_t, 16> squareNoiseRepresentatives = {
        1, 12, 20, 28, 36, 44, 52, 60, 68, 76, 84, 92, 100, 108, 116, 127,
    };
    const std::array<uint8_t, 5> waveRepresentatives = {1, 32, 64, 96, 127};
    const auto representativesMatch = [](const VelocityMap &map, const auto &expected) {
        if (map.levelCount() != expected.size())
            return false;
        for (std::size_t level = 0; level < expected.size(); ++level) {
            if (map.representative(int(level)) != expected[level])
                return false;
        }
        return true;
    };
    check(representativesMatch(square, squareNoiseRepresentatives),
          "Square representatives should be exact");
    check(representativesMatch(wave, waveRepresentatives), "Wave representatives should be exact");
    check(representativesMatch(noise, squareNoiseRepresentatives),
          "Noise representatives should describe every hardware level");
    check(equals(square.levelOf(1), 0) && equals(square.levelOf(127), 15) &&
              equals(wave.levelOf(1), 0) && equals(wave.levelOf(127), 4),
          "intrinsic levels should include velocity boundaries");
    check(!directSound.levelOf(1), "DirectSound should not gain an intrinsic level");
    check(square.compatibleWith(square), "matching maps should be compatible");
    check(!square.compatibleWith(squareTwo) && !square.compatibleWith(noise),
          "different PSG voice identities should be incompatible");

    check(square.canonicalize(1) == 1 && square.canonicalize(127) == 127,
          "Square canonicalization should retain endpoints");
    check(square.canonicalize(64) == 60 && wave.canonicalize(80) == 64,
          "canonicalization should select the representative for its hardware class");
    check(square.canonicalize(8) == 1 && square.canonicalize(9) == 12 &&
              noise.canonicalize(8) == 1 && noise.canonicalize(9) == 12 &&
              wave.canonicalize(112) == 96,
          "canonicalization should preserve hardware classes at their boundaries");
    check(wave.canonicalize(65) == 64 && square.canonicalize(65) == 68 &&
              noise.canonicalize(65) == 68 && directSound.canonicalize(65) == 65 &&
              invalid.canonicalize(65) == 65,
          "canonicalization should respect every voice type and fallback");
    const std::optional<std::size_t> originLevel = wave.levelOf(95);
    check(equals(originLevel, 3) && wave.moveLevels(95, 0) == 95 && wave.moveLevels(95, -1) == 64,
          "returning to an origin level should restore its exact value");
    const std::array<uint8_t, 3> moved = {
        wave.moveLevels(95, 1),
        square.moveLevels(60, 1),
        directSound.moveLevels(65, 1),
    };
    check(moved == std::array<uint8_t, moved.size()>{127, 68, 66},
          "level movement should preserve heterogeneous exact origins");
    check(wave.moveLevels(1, -1) == 1 && square.moveLevels(127, 1) == 127 &&
              directSound.moveLevels(1, -1) == 1 && directSound.moveLevels(127, 1) == 127,
          "level movement should clamp at both velocity endpoints");

    const VelocityAxis continuous(VelocityMap::resolve(nullptr, std::nullopt), axisGeometry(200.0),
                                  std::array<uint8_t, 3>{12, 64, 100});
    check(continuous.mode() == VelocityAxis::Mode::Continuous && continuous.top() == 6.0 &&
              continuous.bottom() == 194.0 && continuous.velocityToY(127) == 6.0 &&
              continuous.velocityToY(1) == 194.0 && continuous.velocityToY(64) == 100.0,
          "continuous placement should use inset endpoints");
    check(VelocityAxis(directSound, axisGeometry(200.0)).mode() == VelocityAxis::Mode::Continuous &&
              VelocityAxis(invalid, axisGeometry(200.0)).mode() == VelocityAxis::Mode::Continuous,
          "DirectSound and invalid contexts should select the continuous axis");
    check(continuous.yToVelocity(6.0) == 127 && continuous.yToVelocity(194.0) == 1 &&
              continuous.markerCount() == 2 && continuous.markers()[0].velocity == 12 &&
              continuous.markers()[1].velocity == 100,
          "continuous inverse placement and extrema should be exact");
    check(continuous.tickCount() == 17 && continuous.hasLabel(127) && continuous.hasLabel(112) &&
              continuous.hasLabel(1),
          "continuous density should select the D3 band");
    check(continuous.inRuler(QPointF(0.0, 0.0), 200.0) &&
              !continuous.inRuler(QPointF(200.0, 0.0), 200.0) &&
              continuous.rulerVelocityAt(QPointF(0.0, continuous.labels()[0].y), 12.0) ==
                  continuous.labels()[0].velocity &&
              continuous.rulerVelocityAt(QPointF(0.0, continuous.labels()[0].y + 6.01), 12.0) == -1,
          "continuous ruler hit mapping should use label tolerance and bounds");
    check(continuous.tickCount() == 17 && continuous.hasLabel(127) &&
              continuous.ticks()[0].velocity == 127 && continuous.ticks()[0].y == continuous.top(),
          "continuous major tick should be published in the axis model");
    const VelocityAxis intrinsicAxis(square, axisGeometry(200.0));
    check(intrinsicAxis.graduationCount() == square.levelCount() &&
              intrinsicAxis.graduations()[0].velocity == square.representative(0) &&
              intrinsicAxis.graduations()[0].y >= intrinsicAxis.top() &&
              intrinsicAxis.graduations()[0].y <= intrinsicAxis.bottom(),
          "intrinsic detent ticks should be published as axis graduations");
    check(VelocityAxis(unresolved, axisGeometry(83.0)).tickCount() == 5 &&
              VelocityAxis(unresolved, axisGeometry(84.0)).tickCount() == 9 &&
              VelocityAxis(unresolved, axisGeometry(112.0)).tickCount() == 9 &&
              VelocityAxis(unresolved, axisGeometry(156.0)).tickCount() == 17 &&
              VelocityAxis(unresolved, axisGeometry(300.0)).tickCount() == 32,
          "continuous density boundaries should be inclusive at each upper band");
    const std::array<uint8_t, 3> belowD2Labels = {127, 64, 1};
    const std::array<uint8_t, 5> atD2Labels = {127, 96, 64, 32, 1};
    const VelocityAxis belowD2(unresolved, axisGeometry(111.999));
    const VelocityAxis atD2(unresolved, axisGeometry(112.0));
    check(labelsMatch(belowD2, belowD2Labels.data(), belowD2Labels.size()) &&
              labelsMatch(atD2, atD2Labels.data(), atD2Labels.size()),
          "continuous labels should change at the D2 boundary");
    const std::array<uint8_t, 17> denseLabels = {
        127, 120, 112, 104, 96, 88, 80, 72, 64, 56, 48, 40, 32, 24, 16, 8, 1,
    };
    const VelocityAxis denseAxis(unresolved, axisGeometry(300.0));
    check(labelsMatch(denseAxis, denseLabels.data(), denseLabels.size()) &&
              denseAxis.tickCount() == 32 && denseAxis.ticks()[1].velocity == 123 &&
              denseAxis.ticks()[30].velocity == 7,
          "dense labels should be explicit and ordered apart from minor ticks");
    check(continuous.accessibleDescription() == "Velocity" && !VelocityAxis::nodesFocusable() &&
              !VelocityAxis::graduationLabelsFocusable(),
          "continuous accessibility should not create focus targets");

    const VelocityAxis narrowAxis(square, axisGeometry(200.0, 2.0));
    check(narrowAxis.intrinsicColumnWidth() == 0.0 && narrowAxis.graduations()[0].width == 0.0 &&
              narrowAxis.graduations()[0].x >= 0.0 && narrowAxis.graduations()[1].x >= 0.0,
          "narrow label geometry should remain non-negative");
    const std::array<uint8_t, 1> selectedValue = {73};
    const VelocityAxis selectedAxis(unresolved, axisGeometry(300.0), selectedValue);
    check(selectedAxis.labelCount() == denseAxis.labelCount() &&
              labelsMatch(selectedAxis, denseLabels.data(), denseLabels.size()) &&
              selectedAxis.markerCount() == 1 && selectedAxis.markers()[0].velocity == 73,
          "a single selected velocity must add a marker, not a graduation label");

    return failures == 0 ? 0 : 1;
}
