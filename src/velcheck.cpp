#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <functional>
#include <optional>
#include <vector>

#include <QApplication>
#include <QColor>
#include <QFontMetrics>
#include <QImage>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QPixmap>
#include <QSettings>
#include <QSplitter>
#include <QTemporaryDir>
#include <QWheelEvent>

#include "core/noteid.h"
#include "core/songdocument.h"
#include "core/velocitymodel.h"
#include "project/decompproject.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songviewmodel.h"
#include "ui/theme/color_math.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"
#include "ui/velocityaxis.h"
#include "ui/velocitygesturemodel.h"

// --velmodelcheck: PSG velocity model check (self-contained, no project
// needed). VelocityMap is the engine-behavior half of the velocity lane: it
// decides which voice a note plays on and which stored velocities that voice
// cannot tell apart. The numbers here are the engine's, not a design choice —
// the effective-velocity rounding is m4a's, the 16 envelope steps are the CGB
// channels', and the wave channel's five loudness classes are gCgb3Vol's
// distinct outputs (external/poryaaaa/plugin/m4a_tables.c).
// Ported from specker/cleanup/psg-velocity-history-pr's velocity-model check.

namespace {

bool equals(const std::optional<std::size_t> &value, std::size_t expected)
{
    return value && *value == expected;
}

} // namespace

int runVelocityModelCheck()
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        if (!condition) {
            std::fprintf(stderr, "velmodelcheck: FAIL: %s\n", message);
            ++failures;
        }
    };

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
    check(!directSound.isPsg() && directSound.levelCount() == 0,
          "DirectSound should remain continuous");
    check(!unresolved.isPsg() && unresolved.levelCount() == 0,
          "missing voice should remain unresolved");

    // The CGB mask keeps the alternate voice types on their channel.
    ToneData squareAltTone{};
    squareAltTone.type = VOICE_SQUARE_1_ALT;
    ToneData directSoundAltTone{};
    directSoundAltTone.type = VOICE_DIRECTSOUND_ALT;
    check(VelocityMap::resolve(&squareAltTone, 60) == square,
          "the alternate Square 1 type should map to the same voice");
    check(!VelocityMap::resolve(&directSoundAltTone, 60).isPsg() &&
              VelocityMap::resolve(&directSoundAltTone, 60) == directSound,
          "the alternate DirectSound type should stay continuous");

    ToneData invalidTone{};
    invalidTone.type = VOICE_CRY;
    const VelocityMap invalid = VelocityMap::resolve(&invalidTone, 60);
    check(!invalid.isPsg() && invalid != directSound,
          "a cry voice masks to no CGB channel and is not DirectSound either");
    // The nested child's CGB bits would classify as Square 1 if the second
    // keysplit hop were followed instead of refused.
    std::array<ToneData, 128> nestedChildren{};
    nestedChildren[60].type = VOICE_KEYSPLIT | VOICE_SQUARE_1;
    ToneData nestedSplit{};
    nestedSplit.type = VOICE_KEYSPLIT_ALL;
    nestedSplit.subGroup = nestedChildren.data();
    check(!VelocityMap::resolve(&nestedSplit, 60).isPsg(), "nested keysplit should be invalid");
    // The children here are PSG, so only refusing to guess a key keeps this
    // keysplit continuous.
    std::array<ToneData, 128> psgChildren{};
    psgChildren[60].type = VOICE_SQUARE_1;
    ToneData keylessSplit{};
    keylessSplit.type = VOICE_KEYSPLIT_ALL;
    keylessSplit.subGroup = psgChildren.data();
    check(!VelocityMap::resolve(&keylessSplit, std::nullopt).isPsg() &&
              VelocityMap::resolve(&keylessSplit, 60).isPsg(),
          "keyless keysplit should remain continuous");
    ToneData subgroupLessSplit{};
    subgroupLessSplit.type = VOICE_KEYSPLIT_ALL;
    check(!VelocityMap::resolve(&subgroupLessSplit, 60).isPsg(),
          "a keysplit without a subgroup must not be dereferenced");
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
    ToneData tableLessSplit{};
    tableLessSplit.type = VOICE_KEYSPLIT;
    tableLessSplit.subGroup = splitChildren.data();
    check(!VelocityMap::resolve(&tableLessSplit, 60).isPsg(),
          "a table-less VOICE_KEYSPLIT must not be indexed");

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
    check(!directSound.levelOf(1) && !unresolved.levelOf(64),
          "continuous voices should not gain an intrinsic level");
    check(square.compatibleWith(square), "matching maps should be compatible");
    check(!square.compatibleWith(squareTwo) && !square.compatibleWith(noise) &&
              !directSound.compatibleWith(directSound),
          "different PSG identities — and continuous voices — should be incompatible");

    // Every stored velocity must land in the level whose range contains it,
    // and the ranges must tile 1-127 without gaps or overlap.
    const auto rangesTile = [&](const VelocityMap &map) {
        int expectedFirst = 1;
        for (std::size_t level = 0; level < map.levelCount(); ++level) {
            const VelocityLevelRange range = map.levelRange(int(level));
            if (range.first != expectedFirst || range.last < range.first)
                return false;
            for (int velocity = range.first; velocity <= range.last; ++velocity) {
                if (!equals(map.levelOf(velocity), level))
                    return false;
            }
            const uint8_t representative = map.representative(int(level));
            if (representative < range.first || representative > range.last)
                return false;
            expectedFirst = range.last + 1;
        }
        return expectedFirst == 128;
    };
    check(rangesTile(square) && rangesTile(noise) && rangesTile(wave),
          "level ranges should tile the velocity domain and contain their representatives");
    check(square.levelRange(-1).first == 1 && square.levelRange(99).last == 127 &&
              directSound.levelRange(64).first == 64 && directSound.levelRange(64).last == 64 &&
              directSound.representative(64) == 64,
          "level ranges should clamp, and a continuous voice's range is the velocity itself");

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
    check(square.canonicalize(0) == 1 && square.canonicalize(200) == 127 &&
              directSound.canonicalize(0) == 1 && directSound.canonicalize(200) == 127,
          "canonicalization should clamp out-of-range proposals into the MIDI domain");

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
    // A non-representative origin only survives while the gesture is still on
    // its own level; stepping away and back lands on the representative.
    check(square.moveLevels(square.moveLevels(65, 1), -1) == 68,
          "stepping off a level and back should land on that level's representative");

    // The deferred-gesture bookkeeping behind every lane edit: it holds
    // identities and preview values, and hands back one all-or-nothing batch
    // plus the revision the gesture began at.
    const NoteId first(1);
    const NoteId second(2);
    const NoteId absent(3);
    VelocityGestureModel gesture;
    check(!gesture.active() && !gesture.update({{first, 60}}) && !gesture.updateByDelta(4) &&
              !gesture.previewVelocity(first) && !gesture.takeCompletion() && !gesture.cancel(),
          "an inactive gesture must reject updates, previews, completion, and cancellation");
    check(!gesture.begin(7, {}) && !gesture.begin(7, {{NoteId(), 60}}) &&
              !gesture.begin(7, {{first, 0}}) && !gesture.begin(7, {{first, 60}, {first, 61}}) &&
              !gesture.active(),
          "empty, unassigned, out-of-range, or duplicated targets must not open a gesture");
    check(gesture.begin(7, {{second, 100}, {first, 40}}) && gesture.active() &&
              gesture.previewVelocity(first) == std::optional<uint8_t>(40) &&
              gesture.previewVelocity(second) == std::optional<uint8_t>(100) &&
              !gesture.previewVelocity(absent) && !gesture.previewVelocity(NoteId()),
          "a gesture must capture its targets whatever order they arrive in");
    check(!gesture.begin(9, {{first, 50}}) && gesture.previewVelocity(first) == 40,
          "a live gesture must not be replaced by another one");
    check(!gesture.update({{absent, 50}}) && !gesture.update({{first, 50}, {first, 51}}) &&
              !gesture.update({}) && gesture.previewVelocity(first) == 40,
          "an update naming an unknown or repeated note must change nothing at all");
    check(gesture.update({{first, 200}, {second, -5}}) && gesture.previewVelocity(first) == 127 &&
              gesture.previewVelocity(second) == 1,
          "updates must clamp into the MIDI velocity domain");
    check(gesture.updateByDelta(-20) && gesture.previewVelocity(first) == 20 &&
              gesture.previewVelocity(second) == 80 && gesture.updateByDelta(0) &&
              gesture.previewVelocity(first) == 40 && gesture.previewVelocity(second) == 100,
          "relative updates must measure from each note's own origin, clamps included");
    const std::optional<VelocityGestureModel::Completion> completion = gesture.takeCompletion();
    check(completion && completion->expectedRevision == 7 && completion->targets.size() == 2 &&
              !gesture.active() && !gesture.previewVelocity(first),
          "taking the completion must hand over the batch and leave the model inactive");
    check(gesture.begin(11, {{first, 40}}) && gesture.cancel() && !gesture.active(),
          "cancelling must discard the session");

    if (failures != 0) {
        std::fprintf(stderr, "velmodelcheck: %d failure(s)\n", failures);
        return 1;
    }
    std::printf("velmodelcheck: PASS (velocity model)\n");
    return 0;
}

// --velcheck <projectRoot> <song> [shot.png]: velocity-lane check. Drives the lane
// widget offscreen: the pane is hidden until the view.velocity_lane command
// (V, dispatched from the focused roll like M/S/B) opens it, the selected
// track's notes paint as nodes at (start tick, velocity) with a stem across
// their duration, the roll's selection rings its nodes and marks their
// velocities on the ruler, the ruler graduates more finely as the pane
// grows, and the lane pans and zooms the shared timeline camera (with the
// ruler column passing the wheel through instead of zooming).

namespace {

void sendLaneMouse(QWidget *widget, QEvent::Type type, QPointF position, Qt::MouseButton button,
                   Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers = Qt::NoModifier)
{
    QMouseEvent event(type, position, QPointF(widget->mapToGlobal(position.toPoint())), button,
                      buttons, modifiers);
    QCoreApplication::sendEvent(widget, &event);
}

void sendLaneKey(QWidget *widget, int key)
{
    QKeyEvent press(QEvent::KeyPress, key, Qt::NoModifier);
    QCoreApplication::sendEvent(widget, &press);
    QKeyEvent release(QEvent::KeyRelease, key, Qt::NoModifier);
    QCoreApplication::sendEvent(widget, &release);
}

void sendLaneWheel(QWidget *widget, QPointF position, int angleDeltaY,
                   Qt::KeyboardModifiers modifiers = Qt::NoModifier)
{
    QWheelEvent event(position, widget->mapToGlobal(position), QPoint(), QPoint(0, angleDeltaY),
                      Qt::NoButton, modifiers, Qt::NoScrollPhase, false);
    QCoreApplication::sendEvent(widget, &event);
}

// The stem's ink: the track color a third of the way to black in OKLab,
// stated here independently of the paint path's own helper.
QColor stemInk(const QColor &trackColor)
{
    const themes::Oklab from = themes::oklabFromColor(trackColor);
    const themes::Oklab to = themes::oklabFromColor(QColor(Qt::black));
    return themes::colorFromOklab({from.lightness + (to.lightness - from.lightness) / 3.0,
                                   from.a + (to.a - from.a) / 3.0, from.b + (to.b - from.b) / 3.0});
}

// Whether any pixel within radius of center is within tolerance of expected.
bool hasColorNear(const QImage &image, QPointF center, int radius, const QColor &expected,
                  int tolerance)
{
    const int left = std::max(0, int(std::floor(center.x())) - radius);
    const int right = std::min(image.width() - 1, int(std::ceil(center.x())) + radius);
    const int top = std::max(0, int(std::floor(center.y())) - radius);
    const int bottom = std::min(image.height() - 1, int(std::ceil(center.y())) + radius);
    for (int y = top; y <= bottom; y++) {
        for (int x = left; x <= right; x++) {
            const QColor actual = image.pixelColor(x, y);
            if (std::abs(actual.red() - expected.red()) <= tolerance &&
                std::abs(actual.green() - expected.green()) <= tolerance &&
                std::abs(actual.blue() - expected.blue()) <= tolerance) {
                return true;
            }
        }
    }
    return false;
}

// The lane's ruler mapping, stated independently of VelocityAxis: velocity 1
// sits on the bottom inset, 127 on the top one, linear in between.
double laneVelocityY(const QWidget *lane, int velocity)
{
    const double top = lane->property("velocityAxisTop").toDouble();
    const double bottom = lane->property("velocityAxisBottom").toDouble();
    return bottom - double(std::clamp(velocity, 1, 127) - 1) * (bottom - top) / 126.0;
}

// Its inverse — the velocity a pointer y asks for, which a gesture writes.
int laneVelocityAt(const QWidget *lane, double y)
{
    const double top = lane->property("velocityAxisTop").toDouble();
    const double bottom = lane->property("velocityAxisBottom").toDouble();
    if (bottom <= top)
        return 1;
    const double clamped = std::clamp(y, top, bottom);
    return std::clamp(1 + int(std::lround((bottom - clamped) * 126.0 / (bottom - top))), 1, 127);
}

} // namespace

// Every printed ruler value must sit on a real graduation: the labels are a
// subset of the ticks in each density band, and neither run may overrun its
// fixed array.
int runVelocityAxisBandCheck(const std::function<void(bool, const char *)> &check)
{
    VelocityAxisGeometry geometry;
    geometry.verticalInset = 6.0;
    geometry.labelHeight = 12.0;
    geometry.densityD1 = 84.0;
    geometry.densityD2 = 112.0;
    geometry.densityD3 = 156.0;
    geometry.densityD4 = 300.0;
    bool everyLabelOnATick = true;
    bool countsInRange = true;
    std::size_t widestTicks = 0;
    for (const double height :
         {40.0, 83.0, 84.0, 111.0, 112.0, 155.0, 156.0, 299.0, 300.0, 900.0}) {
        geometry.height = height;
        const VelocityAxis axis(geometry);
        countsInRange = countsInRange && axis.tickCount() <= VelocityAxis::MaximumTicks &&
                        axis.labelCount() <= VelocityAxis::MaximumLabels;
        widestTicks = std::max(widestTicks, axis.tickCount());
        for (std::size_t label = 0; label < axis.labelCount(); label++) {
            bool onTick = false;
            for (std::size_t tick = 0; tick < axis.tickCount(); tick++) {
                if (axis.ticks()[tick].velocity == axis.labels()[label].velocity)
                    onTick = true;
            }
            everyLabelOnATick = everyLabelOnATick && onTick;
        }
    }
    check(everyLabelOnATick, "every ruler label must land on a graduation");
    check(countsInRange && widestTicks == VelocityAxis::MaximumTicks,
          "the densest band must fill the tick array without overrunning it");
    return 0;
}

int runVelocityLaneCheck(const QString &projectRoot, const QString &songLabel,
                         const QString &screenshotPath)
{
    // The lane's V toggle goes through keymap::Registry, so redirect QSettings
    // into a temp dir first: a user's rebind must not reach these assertions.
    QTemporaryDir settingsDir;
    if (settingsDir.isValid()) {
        QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, settingsDir.path());
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, settingsDir.path());
        QSettings::setDefaultFormat(QSettings::IniFormat);
    }

    DecompProject project;
    QString error;
    if (!project.open(projectRoot, &error)) {
        std::fprintf(stderr, "velcheck: %s\n", qUtf8Printable(error));
        return 1;
    }
    const SongInfo *info = nullptr;
    for (const SongInfo &song : project.songs()) {
        if (song.label == songLabel && song.isPlayable())
            info = &song;
    }
    if (!info) {
        std::fprintf(stderr, "velcheck: no playable song %s\n", qUtf8Printable(songLabel));
        return 1;
    }
    SongDocument doc;
    if (!doc.load(*info, &error)) {
        std::fprintf(stderr, "velcheck: %s\n", qUtf8Printable(error));
        return 1;
    }
    auto timeline = doc.buildTimeline(48000.0);
    SongView view;
    view.resize(1280, 800);
    view.setSong(timeline.get(), nullptr);
    view.setDocument(&doc);
    // The app rebuilds the timeline after every edit
    // (MainWindow::onDocumentChanged); the lane hit-tests against the view
    // model, so the check must keep it fresh the same way.
    QObject::connect(&doc, &SongDocument::documentChanged, &view, [&] {
        auto rebuilt = doc.buildTimeline(48000.0);
        view.updateSong(rebuilt.get());
        timeline = std::move(rebuilt); // frees the old one after the swap
    });
    view.setGridMinDenom(4); // a comfortable 32px grid, as in rollcheck
    (void)view.grab();       // force layout so child geometry is real

    int failures = 0;
    const auto fail = [&](const char *what) {
        std::fprintf(stderr, "velcheck: FAIL %s: %s\n", qUtf8Printable(songLabel), what);
        failures++;
    };
    const auto check = [&](bool condition, const char *what) {
        if (!condition)
            fail(what);
    };

    auto *roll = view.findChild<QWidget *>(QStringLiteral("pianoRoll"));
    auto *lane = view.findChild<QWidget *>(QStringLiteral("velocityLane"));
    if (!roll || !lane) {
        fail("piano roll or velocity lane not found");
        return 1;
    }

    // --- the pane and its toggle
    int visibilitySignals = 0;
    bool lastVisibility = false;
    QObject::connect(&view, &SongView::velocityLaneVisibilityChanged, &view, [&](bool on) {
        visibilitySignals++;
        lastVisibility = on;
    });
    // The harness never shows the window, so isHidden() — the explicit hide
    // flag — is the honest question here, not isVisible().
    check(!view.velocityLaneVisible() && lane->isHidden(), "the velocity lane must start hidden");
    sendLaneKey(roll, Qt::Key_V);
    (void)view.grab();
    check(view.velocityLaneVisible() && !lane->isHidden() && visibilitySignals == 1 &&
              lastVisibility,
          "V from the roll must open the lane and report it");
    check(lane->height() > lane->minimumHeight() && lane->width() > songview::kGutterW,
          "the opened lane must borrow a working height, not just its minimum");
    sendLaneKey(roll, Qt::Key_V);
    (void)view.grab();
    check(!view.velocityLaneVisible() && visibilitySignals == 2 && !lastVisibility,
          "V again must close the lane");
    sendLaneKey(lane, Qt::Key_V);
    (void)view.grab();
    check(view.velocityLaneVisible() && visibilitySignals == 3,
          "the lane's own focus must reach the same toggle");

    runVelocityAxisBandCheck(check);

    // The playhead overlay clips its line to the registered bands' visible
    // rects; without the lane among them it would break across the pane.
    const songview::TimelineSurfaces surfaces = view.timelineSurfaces();
    check(&surfaces.velocity.widget == lane &&
              surfaces.velocity.timelineOrigin == songview::kGutterW,
          "the lane must be registered as a timeline band at the shared origin");

    lane->setFocus(Qt::OtherFocusReason);
    sendLaneKey(lane, Qt::Key_V);
    (void)view.grab();
    // The harness never shows the window, so ask the view which child holds
    // the focus rather than the activation-sensitive hasFocus().
    check(!view.velocityLaneVisible() && view.focusWidget() == roll,
          "closing the focused lane must hand the keyboard back to the roll");
    sendLaneKey(roll, Qt::Key_V);
    (void)view.grab();

    // --- node and stem placement
    const int track = view.selectedTrack();
    const qreal dpr = lane->devicePixelRatioF();
    // A note whose node stands alone: far enough into the plot to be clear of
    // the ruler column, away from the overlays' verticals, and with no other
    // node of the track within a ring's reach.
    // The overlays paint verticals over the nodes (edit cursor, loop markers,
    // playhead), and their ink is close enough to the selection color to fool
    // a pixel probe; keep the probed node clear of all of them.
    const auto overlayContested = [&](qreal x) {
        const qreal cursorX = view.displayX(double(view.editCursorTick()), songview::kGutterW, dpr);
        if (std::abs(x - cursorX) < 16)
            return true;
        if (std::abs(x - view.displayX(view.playheadTick(), songview::kGutterW, dpr)) < 16)
            return true;
        for (const uint64_t loopTick : {timeline->loopStartTick, timeline->loopEndTick}) {
            if (loopTick == UINT64_MAX)
                continue;
            if (std::abs(x - view.displayX(double(loopTick), songview::kGutterW, dpr)) < 52)
                return true;
        }
        return false;
    };
    const ViewNote *probe = nullptr;
    for (const ViewNote &note : view.model().notes) {
        if (note.track != track || note.velocity < 8 || note.velocity > 120)
            continue;
        const qreal x = view.displayX(double(note.startTick), songview::kGutterW, dpr);
        if (x < songview::kGutterW + 60 || x > lane->width() - 60 || overlayContested(x))
            continue;
        bool crowded = false;
        for (const ViewNote &other : view.model().notes) {
            if (&other == &note || other.track != track)
                continue;
            const qreal otherX = view.displayX(double(other.startTick), songview::kGutterW, dpr);
            if (std::abs(otherX - x) < 16)
                crowded = true;
        }
        if (!crowded)
            probe = &note;
        if (probe)
            break;
    }
    if (!probe) {
        fail("no isolated note to probe in the visible span");
        return failures == 0 ? 0 : 1;
    }
    const QPixmap lanePixmap = lane->grab();
    const QImage laneImage = lanePixmap.toImage();
    const qreal rasterDpr = lanePixmap.devicePixelRatio();
    const QColor trackColor = SongView::trackColor(track);
    const QPointF nodeCenter(view.displayX(double(probe->startTick), songview::kGutterW, dpr) *
                                 rasterDpr,
                             laneVelocityY(lane, probe->velocity) * rasterDpr);
    check(hasColorNear(laneImage, nodeCenter, int(std::ceil(2 * rasterDpr)), trackColor, 24),
          "a node must paint in the track color at its tick and velocity");
    // The same x at another velocity's row carries no node: placement is the
    // velocity's, not just "somewhere in the lane".
    const int otherVelocity = probe->velocity > 64 ? probe->velocity - 40 : probe->velocity + 40;
    const QPointF elsewhere(nodeCenter.x(), laneVelocityY(lane, otherVelocity) * rasterDpr);
    check(!hasColorNear(laneImage, elsewhere, int(std::ceil(2 * rasterDpr)), trackColor, 24),
          "no node may paint at a velocity the note does not have");
    // The stem spans the note's duration at the node's height.
    const qreal stemEndX =
        view.displayX(double(probe->endTick), songview::kGutterW, dpr) * rasterDpr;
    if (stemEndX - nodeCenter.x() > 8 * rasterDpr) {
        const QPointF stemMid((nodeCenter.x() + stemEndX) / 2.0, nodeCenter.y());
        const QColor stemColor = stemInk(trackColor);
        check(hasColorNear(laneImage, stemMid, int(std::ceil(2 * rasterDpr)), stemColor, 28),
              "a stem must run from the node across the note's duration");
    }

    // The stem's weight is authored in DIPs, so its painted thickness must
    // grow with the display scale rather than staying a fixed pixel count.
    if (stemEndX - nodeCenter.x() > 8 * rasterDpr) {
        const QColor stemColor = stemInk(trackColor);
        int thickness = 0;
        for (int dy = -6; dy <= 6; dy++) {
            const QColor actual = laneImage.pixelColor(int((nodeCenter.x() + stemEndX) / 2.0),
                                                       int(nodeCenter.y()) + dy);
            if (std::abs(actual.red() - stemColor.red()) <= 28 &&
                std::abs(actual.green() - stemColor.green()) <= 28 &&
                std::abs(actual.blue() - stemColor.blue()) <= 28) {
                thickness++;
            }
        }
        check(thickness >= int(std::floor(1.5 * rasterDpr)),
              "the stem's weight must scale with the display, not stay a device pixel");
    }

    // --- the roll's selection rings its nodes and marks the ruler
    check(lane->property("velocityMarkerCount").toInt() == 0,
          "an empty selection must leave the ruler unmarked");
    view.setSelection({{probe->startTick, probe->key}});
    (void)view.grab();
    const QImage selectedImage = lane->grab().toImage();
    const QColor ringColor = lane->palette().highlight().color();
    // Probe above the node, not across it: a selected note's stem carries the
    // same color through the center, so only the ring can put it up here.
    const QPointF ringTop(nodeCenter.x(), nodeCenter.y() - 5.0 * rasterDpr);
    const int ringProbe = int(std::ceil(2 * rasterDpr));
    check(!hasColorNear(laneImage, ringTop, ringProbe, ringColor, 24) &&
              hasColorNear(selectedImage, ringTop, ringProbe, ringColor, 24),
          "a selected note's node must gain a ring in the selection color");
    check(lane->property("velocityMarkerCount").toInt() == 1,
          "one selected velocity must mark the ruler once");
    const ViewNote *second = nullptr;
    for (const ViewNote &note : view.model().notes) {
        if (note.track == track && note.velocity != probe->velocity)
            second = &note;
        if (second)
            break;
    }
    if (second) {
        view.setSelection({{probe->startTick, probe->key}, {second->startTick, second->key}});
        (void)view.grab();
        check(lane->property("velocityMarkerCount").toInt() == 2,
              "two selected velocities must mark the ruler's extremes");
    }
    if (second) {
        // Dimming reads the selection, not what happens to be on screen.
        check(lane->property("velocityDimmed").toBool(),
              "two selected notes must dim the rest of the track");
        const double before = view.tickAtContentX(0);
        view.scrollByPx(4000.0);
        (void)view.grab();
        check(view.tickAtContentX(0) != before && lane->property("velocityDimmed").toBool(),
              "scrolling away from the selection must not undim the lane");
        view.scrollByPx(-4000.0);
        (void)view.grab();
    }

    // A selected velocity's marker prints its own value in the label column;
    // any fixed ruler label that close must yield instead of overprinting.
    const QColor labelColor = themes::color(themes::Role::song_view_secondary_text);
    const int labelHeight = QFontMetrics(typography::caption(lane->font())).height();
    // Text only: the ruler's tick marks are drawn in the same ink and reach
    // into the right edge of this column.
    const int labelInset = layout::space(layout::Space::Two);
    const QRect labelColumn(songview::kHeaderW, 0, songview::kKeyboardW - 2 * labelInset,
                            lane->height());
    const auto labelInkAt = [&](const QImage &image, double y) {
        const int top = int((y - labelHeight / 2.0) * rasterDpr);
        const int bottom = int((y + labelHeight / 2.0) * rasterDpr);
        for (int py = std::max(0, top); py <= std::min(image.height() - 1, bottom); py++) {
            for (int px = int(labelColumn.left() * rasterDpr);
                 px <= std::min(image.width() - 1, int(labelColumn.right() * rasterDpr)); px++) {
                const QColor actual = image.pixelColor(px, py);
                if (std::abs(actual.red() - labelColor.red()) <= 12 &&
                    std::abs(actual.green() - labelColor.green()) <= 12 &&
                    std::abs(actual.blue() - labelColor.blue()) <= 12) {
                    return true;
                }
            }
        }
        return false;
    };
    view.clearSelection();
    (void)view.grab();
    const QImage unselectedRuler = lane->grab().toImage();
    const ViewNote *onLabel = nullptr;
    for (const ViewNote &note : view.model().notes) {
        if (note.track == track && labelInkAt(unselectedRuler, laneVelocityY(lane, note.velocity)))
            onLabel = &note;
        if (onLabel)
            break;
    }
    if (onLabel) {
        view.setSelection({{onLabel->startTick, onLabel->key}});
        (void)view.grab();
        check(!labelInkAt(lane->grab().toImage(), laneVelocityY(lane, onLabel->velocity)),
              "a fixed ruler label must yield to the selection's own marker label");
    }
    view.clearSelection();
    (void)view.grab();

    // --- ruler density follows the pane's height
    const int shortTicks = lane->property("velocityTickCount").toInt();
    const int shortHeight = lane->height();
    auto *splitter = view.findChild<QSplitter *>();
    if (!splitter) {
        fail("the roll/lanes splitter is missing");
        return failures == 0 ? 0 : 1;
    }
    QList<int> sizes = splitter->sizes();
    sizes[0] -= 220;
    sizes[1] += 220;
    splitter->setSizes(sizes);
    (void)view.grab();
    check(lane->height() > shortHeight && lane->property("velocityTickCount").toInt() > shortTicks,
          "a taller lane must graduate its ruler more finely");

    // --- camera: the plot zooms at the cursor, the ruler column does not
    const double beforeZoom = view.pxPerBeat();
    const QPointF overRuler(songview::kGutterW / 2.0, lane->height() / 2.0);
    sendLaneWheel(lane, overRuler, 120);
    check(view.pxPerBeat() == beforeZoom, "the wheel over the ruler column must not zoom");
    const QPointF overPlot(songview::kGutterW + 200.0, lane->height() / 2.0);
    const double anchoredTick = view.tickAtContentX(overPlot.x() - songview::kGutterW);
    sendLaneWheel(lane, overPlot, 120);
    check(view.pxPerBeat() > beforeZoom, "the wheel over the plot must zoom the timeline in");
    check(std::abs(view.tickAtContentX(overPlot.x() - songview::kGutterW) - anchoredTick) < 0.5,
          "zooming must keep the tick under the cursor in place");
    const double beforeScroll = view.tickAtContentX(0);
    const double zoomedPxPerBeat = view.pxPerBeat();
    sendLaneWheel(lane, overPlot, 120, Qt::ShiftModifier);
    check(view.pxPerBeat() == zoomedPxPerBeat && view.tickAtContentX(0) != beforeScroll,
          "Shift+wheel must scroll instead of zoom");

    // --- middle-button pan
    const double beforePan = view.tickAtContentX(0);
    sendLaneMouse(lane, QEvent::MouseButtonPress, overPlot, Qt::MiddleButton, Qt::MiddleButton);
    sendLaneMouse(lane, QEvent::MouseMove, overPlot - QPointF(40.0, 0.0), Qt::NoButton,
                  Qt::MiddleButton);
    sendLaneMouse(lane, QEvent::MouseButtonRelease, overPlot - QPointF(40.0, 0.0), Qt::MiddleButton,
                  Qt::NoButton);
    check(view.tickAtContentX(0) > beforePan, "a middle drag must pan the timeline");

    // --- editing: a node drag moves the whole selection, deferred to the release
    // The camera checks above left the view zoomed in and scrolled away from
    // the notes; put it back where the placement probes were taken.
    view.zoomAroundContentX(beforeZoom / view.pxPerBeat(), 0.0);
    view.scrollByPx(-1e6);
    (void)view.grab();
    const auto noteAt = [&](uint32_t startTick, uint8_t key) -> const ViewNote * {
        for (const ViewNote &note : view.model().notes) {
            if (note.track == track && note.startTick == startTick && note.key == key)
                return &note;
        }
        return nullptr;
    };
    // A note whose node can be pressed without ambiguity under the camera as
    // it stands now: clear of the ruler, the overlays, and any neighbor's
    // node, with room either side of its velocity for a drag that never
    // clamps.
    const auto isolated = [&](const ViewNote *avoid, bool farthest) -> const ViewNote * {
        const ViewNote *found = nullptr;
        for (const ViewNote &note : view.model().notes) {
            if (note.track != track || !note.noteId.isAssigned())
                continue;
            if (note.velocity < 25 || note.velocity > 103)
                continue;
            const qreal x = view.displayX(double(note.startTick), songview::kGutterW, dpr);
            if (x < songview::kGutterW + 60 || x > lane->width() - 60 || overlayContested(x))
                continue;
            if (avoid && std::abs(view.displayX(double(avoid->startTick), songview::kGutterW, dpr) -
                                  x) < 24) {
                continue;
            }
            bool crowded = false;
            for (const ViewNote &other : view.model().notes) {
                if (&other == &note || other.track != track)
                    continue;
                const qreal otherX =
                    view.displayX(double(other.startTick), songview::kGutterW, dpr);
                if (std::abs(otherX - x) < 16)
                    crowded = true;
            }
            if (!crowded) {
                found = &note;
                if (!farthest)
                    break;
            }
        }
        return found;
    };
    // The partner is the farthest such note, so the paint stroke between the
    // two spans other notes it must not touch.
    const ViewNote *dragProbe = isolated(nullptr, false);
    const ViewNote *partnerProbe = dragProbe ? isolated(dragProbe, true) : nullptr;
    if (!dragProbe || !partnerProbe) {
        fail("no pair of drag-safe notes in the visible span");
        return failures == 0 ? 0 : 1;
    }
    const ViewNote dragNote = *dragProbe;
    const ViewNote partner = *partnerProbe;
    const SongView::NoteKey dragId{dragNote.startTick, dragNote.key};
    const SongView::NoteKey partnerId{partner.startTick, partner.key};
    const int ringProbeRadius = int(std::ceil(2 * rasterDpr));
    view.setSelection({dragId, partnerId});
    (void)view.grab();
    const QPointF nodePoint(view.displayX(double(dragNote.startTick), songview::kGutterW, dpr),
                            laneVelocityY(lane, dragNote.velocity));
    // The drag's y is the y of a real velocity, so the delta it asks for is
    // exactly this one whatever the pane's height and display scale are. It
    // heads away from the note's own end of the ruler, so nothing clamps.
    const int dragDelta = dragNote.velocity > 64 ? -20 : 20;
    const QPointF partnerPoint(view.displayX(double(partner.startTick), songview::kGutterW, dpr),
                               laneVelocityY(lane, partner.velocity));
    const QPointF dragPoint(nodePoint.x(), laneVelocityY(lane, dragNote.velocity + dragDelta));
    const uint64_t revisionBeforeDrag = doc.revision();
    // The undo INDEX, not the stack's size: these probes undo as they go, and
    // the next commit discards the redo branch instead of growing the stack.
    const int undoBeforeDrag = doc.undoStack()->index();
    sendLaneMouse(lane, QEvent::MouseButtonPress, nodePoint, Qt::LeftButton, Qt::LeftButton);
    sendLaneMouse(lane, QEvent::MouseMove, dragPoint, Qt::NoButton, Qt::LeftButton);
    const QImage draggingImage = lane->grab().toImage();
    check(doc.revision() == revisionBeforeDrag && doc.undoStack()->index() == undoBeforeDrag,
          "a velocity drag must leave the document alone until the release");
    // The ring rides the preview: probe above the node, where only the ring
    // can put the selection color.
    check(hasColorNear(draggingImage,
                       QPointF(dragPoint.x() * rasterDpr, (dragPoint.y() - 5.0) * rasterDpr),
                       ringProbeRadius, ringColor, 24),
          "a velocity drag must preview its node at the pointer's velocity");
    sendLaneMouse(lane, QEvent::MouseButtonRelease, dragPoint, Qt::LeftButton, Qt::NoButton);
    (void)view.grab();
    const ViewNote *draggedNote = noteAt(dragNote.startTick, dragNote.key);
    const ViewNote *draggedPartner = noteAt(partner.startTick, partner.key);
    check(doc.revision() != revisionBeforeDrag && doc.undoStack()->index() == undoBeforeDrag + 1 &&
              draggedNote && draggedPartner &&
              draggedNote->velocity == dragNote.velocity + dragDelta &&
              draggedPartner->velocity == partner.velocity + dragDelta &&
              view.selection().size() == 2,
          "the release must move every selected note by the drag's delta as one undo entry");
    doc.undoStack()->undo();
    (void)view.grab();

    // --- click semantics: press, no travel, release
    view.setSelection({dragId, partnerId});
    (void)view.grab();
    const uint64_t revisionBeforeClick = doc.revision();
    sendLaneMouse(lane, QEvent::MouseButtonPress, nodePoint, Qt::LeftButton, Qt::LeftButton);
    sendLaneMouse(lane, QEvent::MouseMove, nodePoint + QPointF(1.0, 0.0), Qt::NoButton,
                  Qt::LeftButton);
    sendLaneMouse(lane, QEvent::MouseButtonRelease, nodePoint + QPointF(1.0, 0.0), Qt::LeftButton,
                  Qt::NoButton);
    check(view.selection().size() == 1 && view.selection()[0] == dragId &&
              doc.revision() == revisionBeforeClick,
          "a click on a node must collapse the selection onto it and edit nothing");
    sendLaneMouse(lane, QEvent::MouseButtonPress, nodePoint, Qt::LeftButton, Qt::LeftButton,
                  Qt::ControlModifier);
    sendLaneMouse(lane, QEvent::MouseButtonRelease, nodePoint, Qt::LeftButton, Qt::NoButton,
                  Qt::ControlModifier);
    check(view.selection().empty(), "Ctrl+click must drop a selected node from the selection");
    sendLaneMouse(lane, QEvent::MouseButtonPress, nodePoint, Qt::LeftButton, Qt::LeftButton,
                  Qt::ControlModifier);
    sendLaneMouse(lane, QEvent::MouseButtonRelease, nodePoint, Qt::LeftButton, Qt::NoButton,
                  Qt::ControlModifier);
    check(view.selection().size() == 1 && view.selection()[0] == dragId,
          "Ctrl+click must add an unselected node without dropping the rest");

    // A velocity row at the probe's tick with no node or stem near it.
    const auto emptyRowY = [&](double x) {
        for (int velocity = 120; velocity >= 8; velocity -= 4) {
            const double y = laneVelocityY(lane, velocity);
            bool clear = true;
            for (const ViewNote &note : view.model().notes) {
                if (note.track != track)
                    continue;
                const double start = view.displayX(double(note.startTick), songview::kGutterW, dpr);
                const double end = view.displayX(double(note.endTick), songview::kGutterW, dpr);
                if (x < start - 12.0 || x > end + 12.0)
                    continue;
                if (std::abs(laneVelocityY(lane, note.velocity) - y) < 12.0)
                    clear = false;
            }
            if (clear)
                return y;
        }
        return -1.0;
    };
    const double emptyY = emptyRowY(nodePoint.x());
    if (emptyY < 0.0) {
        fail("no empty plot row at the probe's tick");
        return failures == 0 ? 0 : 1;
    }
    // A stroke only reaches notes that are selected AND under it, so with
    // only the far note selected this press crosses nothing and stays a
    // click.
    const QPointF emptyPoint(nodePoint.x(), emptyY);
    view.setSelection({partnerId});
    (void)view.grab();
    sendLaneMouse(lane, QEvent::MouseButtonPress, emptyPoint, Qt::LeftButton, Qt::LeftButton);
    check(view.selection().size() == 1,
          "a press on empty plot must leave the selection alone until the release");
    sendLaneMouse(lane, QEvent::MouseButtonRelease, emptyPoint, Qt::LeftButton, Qt::NoButton);
    check(view.selection().empty() && doc.revision() == revisionBeforeClick,
          "a click on empty plot must clear the selection on the release");

    // --- the stem grabs its own note, and Escape abandons a live drag
    const double stemX =
        (nodePoint.x() + view.displayX(double(dragNote.endTick), songview::kGutterW, dpr)) / 2.0;
    if (stemX - nodePoint.x() > 8.0) {
        const QPointF stemPoint(stemX, nodePoint.y());
        sendLaneMouse(lane, QEvent::MouseButtonPress, stemPoint, Qt::LeftButton, Qt::LeftButton);
        sendLaneMouse(lane, QEvent::MouseButtonRelease, stemPoint, Qt::LeftButton, Qt::NoButton);
        check(view.selection().size() == 1 && view.selection()[0] == dragId,
              "a press on a note's stem must grab that note");
    }
    view.setSelection({partnerId});
    (void)view.grab();
    const uint64_t revisionBeforeEscape = doc.revision();
    sendLaneMouse(lane, QEvent::MouseButtonPress, nodePoint, Qt::LeftButton, Qt::LeftButton);
    check(view.selection().size() == 1 && view.selection()[0] == dragId,
          "pressing an unselected node must take the selection over");
    sendLaneMouse(lane, QEvent::MouseMove, dragPoint, Qt::NoButton, Qt::LeftButton);
    sendLaneKey(lane, Qt::Key_Escape);
    check(view.selection().size() == 1 && view.selection()[0] == partnerId &&
              doc.revision() == revisionBeforeEscape,
          "Escape must abandon the drag and put the pre-press selection back");
    sendLaneMouse(lane, QEvent::MouseButtonRelease, dragPoint, Qt::LeftButton, Qt::NoButton);
    const ViewNote *escapedNote = noteAt(dragNote.startTick, dragNote.key);
    check(doc.revision() == revisionBeforeEscape && escapedNote &&
              escapedNote->velocity == dragNote.velocity,
          "the release after an Escape must not commit the abandoned drag");
    view.clearSelection();
    (void)view.grab();

    // --- painting, ramps, and the ruler's own click
    const double partnerEmptyY = emptyRowY(partnerPoint.x());
    if (partnerEmptyY < 0.0) {
        fail("no empty plot row at the partner's tick");
        return failures == 0 ? 0 : 1;
    }
    // The stroke starts on an empty row above the near note and runs off to
    // the right past the far one, so it crosses unselected notes on the way.
    const QPointF paintStart(nodePoint.x(), emptyY);
    const QPointF paintEnd(lane->width() - 20.0, partnerEmptyY);
    const double paintSpan = paintEnd.x() - paintStart.x();
    const auto paintedVelocity = [&](double x) {
        const double t = std::clamp((x - paintStart.x()) / paintSpan, 0.0, 1.0);
        return laneVelocityAt(lane, paintStart.y() + t * (paintEnd.y() - paintStart.y()));
    };
    const int paintTarget = paintedVelocity(nodePoint.x());
    const int paintPartnerTarget = paintedVelocity(partnerPoint.x());
    // A note the stroke passes over but never selects: paint must leave it
    // exactly where it was, and it must have somewhere to move to.
    const ViewNote *bystanderProbe = nullptr;
    for (const ViewNote &note : view.model().notes) {
        const double x = view.displayX(double(note.startTick), songview::kGutterW, dpr);
        if (note.track == track && x > paintStart.x() && x < paintEnd.x() &&
            note.startTick != dragNote.startTick && note.startTick != partner.startTick &&
            paintedVelocity(x) != note.velocity)
            bystanderProbe = &note;
        if (bystanderProbe)
            break;
    }
    if (paintSpan <= 0.0 || paintTarget == dragNote.velocity ||
        paintPartnerTarget == partner.velocity || !bystanderProbe) {
        fail("the paint stroke's fixture must ask for new velocities and cross a bystander");
        return failures == 0 ? 0 : 1;
    }
    const ViewNote bystander = *bystanderProbe;
    view.setSelection({dragId, partnerId});
    (void)view.grab();
    const uint64_t revisionBeforePaint = doc.revision();
    const int undoBeforePaint = doc.undoStack()->index();
    sendLaneMouse(lane, QEvent::MouseButtonPress, paintStart, Qt::LeftButton, Qt::LeftButton);
    sendLaneMouse(lane, QEvent::MouseMove, paintEnd, Qt::NoButton, Qt::LeftButton);
    check(doc.revision() == revisionBeforePaint,
          "a paint stroke must leave the document alone until the release");
    sendLaneMouse(lane, QEvent::MouseButtonRelease, paintEnd, Qt::LeftButton, Qt::NoButton);
    (void)view.grab();
    const ViewNote *paintedNote = noteAt(dragNote.startTick, dragNote.key);
    const ViewNote *paintedPartner = noteAt(partner.startTick, partner.key);
    check(paintedNote && paintedPartner && paintedNote->velocity == paintTarget &&
              paintedPartner->velocity == paintPartnerTarget &&
              doc.undoStack()->index() == undoBeforePaint + 1 && view.selection().size() == 2,
          "a paint stroke must write each selected note it crosses in one undo entry");
    const ViewNote *untouched = noteAt(bystander.startTick, bystander.key);
    check(untouched && untouched->velocity == bystander.velocity,
          "a paint stroke must not touch an unselected note under it");
    doc.undoStack()->undo();
    (void)view.grab();

    // A click on empty plot straight below a selected node is how one note
    // is set on its own.
    view.setSelection({dragId});
    (void)view.grab();
    const int spotTarget = laneVelocityAt(lane, emptyY);
    const QPointF spotPoint(nodePoint.x(), emptyY);
    const int undoBeforeSpot = doc.undoStack()->index();
    sendLaneMouse(lane, QEvent::MouseButtonPress, spotPoint, Qt::LeftButton, Qt::LeftButton);
    sendLaneMouse(lane, QEvent::MouseButtonRelease, spotPoint, Qt::LeftButton, Qt::NoButton);
    (void)view.grab();
    const ViewNote *spotNote = noteAt(dragNote.startTick, dragNote.key);
    const ViewNote *spotPartner = noteAt(partner.startTick, partner.key);
    check(spotNote && spotPartner && spotNote->velocity == spotTarget &&
              spotPartner->velocity == partner.velocity &&
              doc.undoStack()->index() == undoBeforeSpot + 1 && view.selection().size() == 1,
          "clicking below a selected node must set that note alone");
    doc.undoStack()->undo();
    (void)view.grab();

    // Shift is a ramp: the straight line from the press to the pointer, laid
    // across the selection. Pressing on a node proves it — a relative drag
    // would have moved that node too.
    view.setSelection({dragId, partnerId});
    (void)view.grab();
    const int rampTarget = laneVelocityAt(lane, emptyY);
    const QPointF rampStart(partnerPoint.x(), laneVelocityY(lane, partner.velocity));
    const QPointF rampEnd(nodePoint.x(), emptyY);
    const int undoBeforeRamp = doc.undoStack()->index();
    sendLaneMouse(lane, QEvent::MouseButtonPress, rampStart, Qt::LeftButton, Qt::LeftButton,
                  Qt::ShiftModifier);
    sendLaneMouse(lane, QEvent::MouseMove, rampEnd, Qt::NoButton, Qt::LeftButton,
                  Qt::ShiftModifier);
    const QImage rampImage = lane->grab().toImage();
    const QPointF rampQuarter = rampStart + 0.25 * (rampEnd - rampStart);
    check(hasColorNear(rampImage, QPointF(rampQuarter.x() * rasterDpr, rampQuarter.y() * rasterDpr),
                       int(std::ceil(2 * rasterDpr)),
                       themes::color(themes::Role::song_view_edit_preview_outline), 24),
          "a ramp must draw the line it is reading its values off");
    sendLaneMouse(lane, QEvent::MouseButtonRelease, rampEnd, Qt::LeftButton, Qt::NoButton,
                  Qt::ShiftModifier);
    (void)view.grab();
    const ViewNote *rampedNote = noteAt(dragNote.startTick, dragNote.key);
    const ViewNote *rampedPartner = noteAt(partner.startTick, partner.key);
    check(rampedNote && rampedPartner && rampedNote->velocity == rampTarget &&
              rampedPartner->velocity == partner.velocity &&
              doc.undoStack()->index() == undoBeforeRamp + 1,
          "a Shift drag must ramp the selection between its ends instead of moving it");
    doc.undoStack()->undo();
    (void)view.grab();

    // The ruler's printed values are click targets for the whole selection;
    // 127 is labeled in every density band.
    view.setSelection({dragId, partnerId});
    (void)view.grab();
    const int undoBeforeRuler = doc.undoStack()->index();
    const QPointF headerPoint(songview::kHeaderW / 2.0, laneVelocityY(lane, 127));
    sendLaneMouse(lane, QEvent::MouseButtonPress, headerPoint, Qt::LeftButton, Qt::LeftButton);
    sendLaneMouse(lane, QEvent::MouseButtonRelease, headerPoint, Qt::LeftButton, Qt::NoButton);
    check(doc.undoStack()->index() == undoBeforeRuler,
          "a press in the track-header column must not edit velocities");
    const QPointF rulerPoint(songview::kHeaderW + songview::kKeyboardW / 2.0,
                             laneVelocityY(lane, 127));
    sendLaneMouse(lane, QEvent::MouseButtonPress, rulerPoint, Qt::LeftButton, Qt::LeftButton);
    sendLaneMouse(lane, QEvent::MouseButtonRelease, rulerPoint, Qt::LeftButton, Qt::NoButton);
    (void)view.grab();
    const ViewNote *rulerNote = noteAt(dragNote.startTick, dragNote.key);
    const ViewNote *rulerPartner = noteAt(partner.startTick, partner.key);
    check(rulerNote && rulerPartner && rulerNote->velocity == 127 &&
              rulerPartner->velocity == 127 && doc.undoStack()->index() == undoBeforeRuler + 1 &&
              view.selection().size() == 2,
          "clicking a ruler value must set the whole selection to it in one undo entry");
    doc.undoStack()->undo();
    view.clearSelection();
    (void)view.grab();

    // --- the pane's height is per-song view state, and pre-lane sidecars load
    SongView::ViewState state = view.viewState();
    check(state.splitterSizes.size() == 3 && state.splitterSizes[1] == lane->height(),
          "view state must carry the lane's own pane size");
    SongView::ViewState legacy = state;
    legacy.splitterSizes = {400, 150};
    view.setVelocityLaneVisible(false); // as an old sidecar's song would open
    view.applyViewState(legacy);
    (void)view.grab();
    const QList<int> restored = splitter->sizes();
    // The lanes pane keeps the size the sidecar saved; the roll pane, the
    // stretchy one, absorbs the splitter's remaining height.
    check(restored.size() == 3 && restored[1] == 0 && restored[2] == 150 && restored[0] > 0,
          "a sidecar written before the lane must still restore its two panes");
    // With the app-wide preference on, the same sidecar must still open the
    // lane at a usable height instead of clamping it to its minimum.
    view.setVelocityLaneVisible(true);
    view.applyViewState(legacy);
    (void)view.grab();
    check(lane->height() > lane->minimumHeight() && splitter->sizes()[2] == 150,
          "a pre-lane sidecar must open a visible lane at its default height");

    if (!screenshotPath.isEmpty()) {
        view.setVelocityLaneVisible(true);
        (void)view.grab();
        if (!view.grab().save(screenshotPath))
            fail("could not write the screenshot");
    }

    if (failures != 0) {
        std::fprintf(stderr, "velcheck: %d failure(s)\n", failures);
        return 1;
    }
    std::printf("velcheck: PASS (velocity lane)\n");
    return 0;
}
