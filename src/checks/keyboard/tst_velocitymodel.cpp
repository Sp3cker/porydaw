#include "checks/keyboard/tst_velocitymodel.h"

#include <QPointF>
#include <QtTest>

#include <array>
#include <optional>

#include "core/velocitymodel.h"
#include "ui/editordrawer/velocityaxis.h"
#include "ui/velocitygesturemodel.h"

namespace {

VelocityAxisGeometry axisGeometry(double height, double labelWidth = 200.0)
{
    return {height, 6.0, labelWidth, 2.0, 1.0, 12.0, 84.0, 112.0, 156.0, 300.0};
}

bool hasLevel(const std::optional<std::size_t> &level, std::size_t expected)
{
    return level.has_value() && *level == expected;
}

ToneData tone(uint8_t type)
{
    ToneData result{};
    result.type = type;
    return result;
}

VelocityMap mapForTone(uint8_t type)
{
    const ToneData data = tone(type);
    return VelocityMap::resolve(&data, 60);
}

} // namespace

void VelocityModelTest::gestureLifecycle()
{
    const NoteVelocity first{NoteId(1), 40};
    const NoteVelocity second{NoteId(2), 120};
    VelocityGestureModel gesture;

    QVERIFY(!gesture.active());
    QVERIFY(!gesture.update({first}));
    QVERIFY(!gesture.previewVelocity(first.noteId).has_value());
    QVERIFY(!gesture.takeCompletion().has_value());
    QVERIFY(!gesture.cancel());

    QVERIFY(!gesture.begin(42, {}));
    QVERIFY(!gesture.begin(42, {{NoteId(), 40}}));
    QVERIFY(!gesture.begin(42, {{NoteId(3), 0}}));
    QVERIFY(!gesture.begin(42, {{NoteId(3), 128}}));
    QVERIFY(!gesture.begin(42, {first, first}));
    QVERIFY(!gesture.begin(42, {first, second, second}));
    QVERIFY(!gesture.active());

    QVERIFY(gesture.begin(42, {second, first}));
    QVERIFY(gesture.active());
    QCOMPARE(gesture.previewVelocity(first.noteId), std::optional<uint8_t>(40));
    QCOMPARE(gesture.previewVelocity(second.noteId), std::optional<uint8_t>(120));
    QVERIFY(!gesture.begin(43, {second}));
    QCOMPARE(gesture.previewVelocity(first.noteId), std::optional<uint8_t>(40));
}

void VelocityModelTest::gestureAtomicity()
{
    const NoteVelocity first{NoteId(1), 40};
    const NoteVelocity second{NoteId(2), 120};
    VelocityGestureModel gesture;
    QVERIFY(gesture.begin(42, {first, second}));

    QVERIFY(!gesture.update({{first.noteId, 100}, {NoteId(3), 64}}));
    QCOMPARE(gesture.previewVelocity(first.noteId), std::optional<uint8_t>(40));
    QCOMPARE(gesture.previewVelocity(second.noteId), std::optional<uint8_t>(120));

    QVERIFY(!gesture.update({}));
    QVERIFY(!gesture.update({{first.noteId, 100}, {first.noteId, 110}}));
    QCOMPARE(gesture.previewVelocity(first.noteId), std::optional<uint8_t>(40));
    QCOMPARE(gesture.previewVelocity(second.noteId), std::optional<uint8_t>(120));
}

void VelocityModelTest::gestureCompletionAndDeltaFromOriginals()
{
    const NoteVelocity first{NoteId(1), 40};
    const NoteVelocity second{NoteId(2), 120};
    VelocityGestureModel gesture;
    QVERIFY(gesture.begin(42, {second, first}));
    QVERIFY(gesture.update({{first.noteId, 100}}));
    QCOMPARE(gesture.previewVelocity(first.noteId), std::optional<uint8_t>(100));
    QCOMPARE(gesture.previewVelocity(second.noteId), std::optional<uint8_t>(120));

    QVERIFY(gesture.updateByDelta(-10));
    QCOMPARE(gesture.previewVelocity(first.noteId), std::optional<uint8_t>(30));
    QCOMPARE(gesture.previewVelocity(second.noteId), std::optional<uint8_t>(110));

    const std::optional<VelocityGestureModel::Completion> completion = gesture.takeCompletion();
    QVERIFY(completion.has_value());
    QCOMPARE(completion->expectedRevision, uint64_t(42));
    QCOMPARE(completion->targets.size(), std::size_t(2));
    QCOMPARE(completion->targets[0].noteId, first.noteId);
    QCOMPARE(completion->targets[0].velocity, uint8_t(30));
    QCOMPARE(completion->targets[1].noteId, second.noteId);
    QCOMPARE(completion->targets[1].velocity, uint8_t(110));
    QVERIFY(!gesture.active());
    QVERIFY(!gesture.previewVelocity(first.noteId).has_value());
    QVERIFY(!gesture.takeCompletion().has_value());
}

void VelocityModelTest::gestureClampedDeltaAndCancellation()
{
    const NoteVelocity first{NoteId(1), 40};
    const NoteVelocity second{NoteId(2), 120};
    VelocityGestureModel gesture;
    QVERIFY(gesture.begin(42, {first, second}));
    QVERIFY(gesture.update({{first.noteId, 0}}));
    QCOMPARE(gesture.previewVelocity(first.noteId), std::optional<uint8_t>(1));
    QVERIFY(gesture.update({{first.noteId, 128}}));
    QCOMPARE(gesture.previewVelocity(first.noteId), std::optional<uint8_t>(127));
    QVERIFY(gesture.updateByDelta(-50));
    QCOMPARE(gesture.previewVelocity(first.noteId), std::optional<uint8_t>(1));
    QCOMPARE(gesture.previewVelocity(second.noteId), std::optional<uint8_t>(70));
    QVERIFY(gesture.cancel());
    QVERIFY(!gesture.active());
    QVERIFY(!gesture.previewVelocity(first.noteId).has_value());
    QVERIFY(!gesture.takeCompletion().has_value());
    QVERIFY(!gesture.cancel());
}

void VelocityModelTest::resolvesVoiceKinds()
{
    const VelocityMap square = mapForTone(VOICE_SQUARE_1);
    const VelocityMap squareTwo = mapForTone(VOICE_SQUARE_2);
    const VelocityMap noise = mapForTone(VOICE_NOISE);
    const VelocityMap wave = mapForTone(VOICE_PROGRAMMABLE_WAVE);
    const VelocityMap directSound = mapForTone(VOICE_DIRECTSOUND);
    const VelocityMap unresolved = VelocityMap::resolve(nullptr, std::nullopt);

    QVERIFY(square.isPsg());
    QCOMPARE(QString::fromLatin1(square.voiceName()), QStringLiteral("Square 1"));
    QVERIFY(squareTwo.isPsg());
    QCOMPARE(QString::fromLatin1(squareTwo.voiceName()), QStringLiteral("Square 2"));
    QVERIFY(noise.isPsg());
    QCOMPARE(QString::fromLatin1(noise.voiceName()), QStringLiteral("Noise"));
    QVERIFY(wave.isPsg());
    QCOMPARE(QString::fromLatin1(wave.voiceName()), QStringLiteral("Programmable Wave"));
    QVERIFY(!directSound.isPsg());
    QVERIFY(!unresolved.isPsg());

    const ToneData invalid = tone(VOICE_CRY);
    QVERIFY(!VelocityMap::resolve(&invalid, 60).isPsg());
    std::array<ToneData, 128> nestedChildren{};
    nestedChildren[60].type = VOICE_KEYSPLIT;
    ToneData nested{};
    nested.type = VOICE_KEYSPLIT_ALL;
    nested.subGroup = nestedChildren.data();
    QVERIFY(!VelocityMap::resolve(&nested, 60).isPsg());
    QVERIFY(!VelocityMap::resolve(&nested, std::nullopt).isPsg());

    std::array<ToneData, 128> splitChildren{};
    std::array<uint8_t, 128> splitTable{};
    splitChildren[7].type = VOICE_PROGRAMMABLE_WAVE;
    splitTable[60] = 7;
    ToneData split{};
    split.type = VOICE_KEYSPLIT;
    split.subGroup = splitChildren.data();
    split.keySplitTable = splitTable.data();
    const VelocityMap resolvedSplit = VelocityMap::resolve(&split, 60);
    QVERIFY(resolvedSplit.isPsg());
    QCOMPARE(QString::fromLatin1(resolvedSplit.voiceName()), QStringLiteral("Programmable Wave"));
}

void VelocityModelTest::levelsCanonicalizeAndMove()
{
    const VelocityMap square = mapForTone(VOICE_SQUARE_1);
    const VelocityMap squareTwo = mapForTone(VOICE_SQUARE_2);
    const VelocityMap noise = mapForTone(VOICE_NOISE);
    const VelocityMap wave = mapForTone(VOICE_PROGRAMMABLE_WAVE);
    const VelocityMap directSound = mapForTone(VOICE_DIRECTSOUND);
    const VelocityMap invalid = mapForTone(VOICE_CRY);
    const std::array<uint8_t, 16> squareNoise = {
        1, 12, 20, 28, 36, 44, 52, 60, 68, 76, 84, 92, 100, 108, 116, 127,
    };
    const std::array<uint8_t, 5> waveLevels = {1, 32, 64, 96, 127};

    QCOMPARE(square.levelCount(), squareNoise.size());
    QCOMPARE(noise.levelCount(), squareNoise.size());
    QCOMPARE(wave.levelCount(), waveLevels.size());
    for (std::size_t index = 0; index < squareNoise.size(); ++index) {
        QCOMPARE(square.representative(int(index)), squareNoise[index]);
        QCOMPARE(noise.representative(int(index)), squareNoise[index]);
    }
    for (std::size_t index = 0; index < waveLevels.size(); ++index)
        QCOMPARE(wave.representative(int(index)), waveLevels[index]);
    QVERIFY(hasLevel(square.levelOf(1), 0));
    QVERIFY(hasLevel(square.levelOf(127), 15));
    QVERIFY(hasLevel(wave.levelOf(1), 0));
    QVERIFY(hasLevel(wave.levelOf(127), 4));
    QVERIFY(!directSound.levelOf(1).has_value());
    QVERIFY(square.compatibleWith(square));
    QVERIFY(!square.compatibleWith(squareTwo));
    QVERIFY(!square.compatibleWith(noise));

    QCOMPARE(square.canonicalize(1), uint8_t(1));
    QCOMPARE(square.canonicalize(127), uint8_t(127));
    QCOMPARE(square.canonicalize(64), uint8_t(60));
    QCOMPARE(wave.canonicalize(80), uint8_t(64));
    QCOMPARE(square.canonicalize(8), uint8_t(1));
    QCOMPARE(noise.canonicalize(8), uint8_t(1));
    QCOMPARE(noise.canonicalize(9), uint8_t(12));
    QCOMPARE(square.canonicalize(9), uint8_t(12));
    QCOMPARE(wave.canonicalize(112), uint8_t(96));
    QCOMPARE(wave.canonicalize(65), uint8_t(64));
    QCOMPARE(square.canonicalize(65), uint8_t(68));
    QCOMPARE(noise.canonicalize(65), uint8_t(68));
    QCOMPARE(directSound.canonicalize(65), uint8_t(65));
    QCOMPARE(invalid.canonicalize(65), uint8_t(65));

    QVERIFY(hasLevel(wave.levelOf(95), 3));
    QCOMPARE(wave.moveLevels(95, 0), uint8_t(95));
    QCOMPARE(wave.moveLevels(95, -1), uint8_t(64));
    QCOMPARE(wave.moveLevels(95, 1), uint8_t(127));
    QCOMPARE(square.moveLevels(60, 1), uint8_t(68));
    QCOMPARE(directSound.moveLevels(65, 1), uint8_t(66));
    QCOMPARE(wave.moveLevels(1, -1), uint8_t(1));
    QCOMPARE(square.moveLevels(127, 1), uint8_t(127));
    QCOMPARE(directSound.moveLevels(1, -1), uint8_t(1));
    QCOMPARE(directSound.moveLevels(127, 1), uint8_t(127));
}

void VelocityModelTest::continuousAxisGeometryAndDensity()
{
    const VelocityMap unresolved = VelocityMap::resolve(nullptr, std::nullopt);
    const VelocityMap directSound = mapForTone(VOICE_DIRECTSOUND);
    const VelocityMap invalid = mapForTone(VOICE_CRY);
    const VelocityAxis axis(unresolved, axisGeometry(200.0), std::array<uint8_t, 3>{12, 64, 100});

    QCOMPARE(axis.mode(), VelocityAxis::Mode::Continuous);
    QCOMPARE(axis.top(), 6.0);
    QCOMPARE(axis.bottom(), 194.0);
    QCOMPARE(axis.velocityToY(127), 6.0);
    QCOMPARE(axis.velocityToY(1), 194.0);
    QCOMPARE(axis.velocityToY(64), 100.0);
    QCOMPARE(axis.yToVelocity(6.0), 127);
    QCOMPARE(axis.yToVelocity(194.0), 1);
    QCOMPARE(axis.markerCount(), std::size_t(2));
    QCOMPARE(axis.markers()[0].velocity, uint8_t(12));
    QCOMPARE(axis.markers()[1].velocity, uint8_t(100));
    QCOMPARE(axis.tickCount(), std::size_t(17));
    QVERIFY(axis.hasLabel(127));
    QVERIFY(axis.hasLabel(112));
    QVERIFY(axis.hasLabel(1));
    QVERIFY(axis.inRuler(QPointF(0.0, 0.0), 200.0));
    QVERIFY(!axis.inRuler(QPointF(200.0, 0.0), 200.0));
    QCOMPARE(axis.rulerVelocityAt(QPointF(0.0, axis.labels()[0].y), 12.0),
             int(axis.labels()[0].velocity));
    QCOMPARE(axis.rulerVelocityAt(QPointF(0.0, axis.labels()[0].y + 6.01), 12.0), -1);
    QCOMPARE(axis.ticks()[0].velocity, uint8_t(127));
    QCOMPARE(axis.ticks()[0].y, axis.top());
    QCOMPARE(VelocityAxis(directSound, axisGeometry(200.0)).mode(), VelocityAxis::Mode::Continuous);
    QCOMPARE(VelocityAxis(invalid, axisGeometry(200.0)).mode(), VelocityAxis::Mode::Continuous);

    QCOMPARE(VelocityAxis(unresolved, axisGeometry(83.0)).tickCount(), std::size_t(5));
    QCOMPARE(VelocityAxis(unresolved, axisGeometry(84.0)).tickCount(), std::size_t(9));
    QCOMPARE(VelocityAxis(unresolved, axisGeometry(112.0)).tickCount(), std::size_t(9));
    QCOMPARE(VelocityAxis(unresolved, axisGeometry(156.0)).tickCount(), std::size_t(17));
    const VelocityAxis dense(unresolved, axisGeometry(300.0));
    QCOMPARE(dense.tickCount(), std::size_t(32));
    QCOMPARE(dense.ticks()[1].velocity, uint8_t(123));
    QCOMPARE(dense.ticks()[30].velocity, uint8_t(7));
    const VelocityAxis belowD2(unresolved, axisGeometry(111.999));
    const VelocityAxis atD2(unresolved, axisGeometry(112.0));
    const std::array<uint8_t, 3> belowD2Labels = {127, 64, 1};
    const std::array<uint8_t, 5> atD2Labels = {127, 96, 64, 32, 1};
    const std::array<uint8_t, 17> denseLabels = {
        127, 120, 112, 104, 96, 88, 80, 72, 64, 56, 48, 40, 32, 24, 16, 8, 1,
    };
    QCOMPARE(belowD2.labelCount(), belowD2Labels.size());
    for (std::size_t index = 0; index < belowD2Labels.size(); ++index)
        QCOMPARE(belowD2.labels()[index].velocity, belowD2Labels[index]);
    QCOMPARE(atD2.labelCount(), atD2Labels.size());
    for (std::size_t index = 0; index < atD2Labels.size(); ++index)
        QCOMPARE(atD2.labels()[index].velocity, atD2Labels[index]);
    QCOMPARE(dense.labelCount(), denseLabels.size());
    for (std::size_t index = 0; index < denseLabels.size(); ++index)
        QCOMPARE(dense.labels()[index].velocity, denseLabels[index]);
}

void VelocityModelTest::intrinsicAxisRowsAndRoundTrip()
{
    const VelocityMap square = mapForTone(VOICE_SQUARE_1);
    const VelocityMap noise = mapForTone(VOICE_NOISE);
    const VelocityMap wave = mapForTone(VOICE_PROGRAMMABLE_WAVE);
    for (const VelocityMap *const map : {&square, &noise, &wave}) {
        const VelocityAxis axis(*map, axisGeometry(200.0));
        QCOMPARE(axis.mode(), VelocityAxis::Mode::Intrinsic);
        QCOMPARE(axis.graduationCount(), map->levelCount());
        for (std::size_t level = 0; level < axis.graduationCount(); ++level) {
            QCOMPARE(axis.graduations()[level].velocity, map->representative(int(level)));
            QVERIFY(axis.graduations()[level].y >= axis.top());
            QVERIFY(axis.graduations()[level].y <= axis.bottom());
            QCOMPARE(axis.yToLevel(axis.levelToY(int(level))), int(level));
        }
    }

    const VelocityAxis narrow(square, axisGeometry(200.0, 2.0));
    QCOMPARE(narrow.intrinsicColumnWidth(), 0.0);
    QCOMPARE(narrow.graduations()[0].width, 0.0);
    QVERIFY(narrow.graduations()[0].x >= 0.0);
    QVERIFY(narrow.graduations()[1].x >= 0.0);
}

void VelocityModelTest::markerCapAndAccessibility()
{
    const VelocityMap unresolved = VelocityMap::resolve(nullptr, std::nullopt);
    const VelocityAxis selected(unresolved, axisGeometry(300.0), std::array<uint8_t, 1>{73});
    QCOMPARE(selected.labelCount(), std::size_t(17));
    const std::array<uint8_t, 17> denseLabels = {
        127, 120, 112, 104, 96, 88, 80, 72, 64, 56, 48, 40, 32, 24, 16, 8, 1,
    };
    for (std::size_t index = 0; index < denseLabels.size(); ++index)
        QCOMPARE(selected.labels()[index].velocity, denseLabels[index]);
    QCOMPARE(selected.markerCount(), std::size_t(1));
    QCOMPARE(selected.markers()[0].velocity, uint8_t(73));

    const VelocityAxis capped(unresolved, axisGeometry(200.0), std::array<uint8_t, 3>{12, 64, 100});
    QCOMPARE(capped.markerCount(), VelocityAxis::MAXIMUM_MARKERS);
    QCOMPARE(capped.markers()[0].velocity, uint8_t(12));
    QCOMPARE(capped.markers()[1].velocity, uint8_t(100));
    QCOMPARE(QString::fromUtf8(capped.accessibleDescription().data(),
                               int(capped.accessibleDescription().size())),
             QStringLiteral("Velocity"));
    QVERIFY(!VelocityAxis::nodesFocusable());
    QVERIFY(!VelocityAxis::graduationLabelsFocusable());
}

int runVelocityModelCheck(const QStringList &qtArguments)
{
    VelocityModelTest test;
    QStringList arguments{QStringLiteral("velocity-model")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
