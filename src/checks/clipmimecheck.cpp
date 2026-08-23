// Codec unit checks for the system-clipboard clip MIME payload
// (src/ui/songview/clipmime.{h,cpp}): encode/decode round trips, TPB rescaling,
// the QClipboard write/read path, and rejection of malformed or foreign
// payloads. Deterministic under the offscreen QApplication; no fixture needed.
#include "ui/songview/clip.h"
#include "ui/songview/clipmime.h"

#include "core/tempo.h"

#include <QByteArray>
#include <QClipboard>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMimeData>

#include <cstdio>
#include <limits>
#include <optional>
#include <utility>

namespace {

using songview::Clip;
using songview::ClipLane;
using songview::ClipNote;
using songview::ClipTrack;
using songview::decodeClip;
using songview::encodeClip;
using songview::rescaleClip;

bool sameNote(const ClipNote &a, const ClipNote &b)
{
    return a.relTick == b.relTick && a.key == b.key && a.duration == b.duration &&
           a.velocity == b.velocity;
}

bool sameTrack(const ClipTrack &a, const ClipTrack &b)
{
    if (a.track != b.track || a.notes.size() != b.notes.size())
        return false;
    for (size_t i = 0; i < a.notes.size(); i++)
        if (!sameNote(a.notes[i], b.notes[i]))
            return false;
    return true;
}

bool sameLane(const ClipLane &a, const ClipLane &b)
{
    if (a.track != b.track || a.cc != b.cc || a.points.size() != b.points.size())
        return false;
    for (size_t i = 0; i < a.points.size(); i++)
        if (a.points[i] != b.points[i])
            return false;
    return true;
}

bool sameClip(const Clip &a, const Clip &b)
{
    if (a.span != b.span || a.wholeLane != b.wholeLane || a.tracks.size() != b.tracks.size() ||
        a.lanes.size() != b.lanes.size() || a.tempo.size() != b.tempo.size())
        return false;
    for (size_t i = 0; i < a.tracks.size(); i++)
        if (!sameTrack(a.tracks[i], b.tracks[i]))
            return false;
    for (size_t i = 0; i < a.lanes.size(); i++)
        if (!sameLane(a.lanes[i], b.lanes[i]))
            return false;
    for (size_t i = 0; i < a.tempo.size(); i++)
        if (!(a.tempo[i] == b.tempo[i]))
            return false;
    return true;
}

// A well-formed format-1 payload object; tests delete or corrupt one key.
QJsonObject validPayload(uint32_t ticksPerBeat = 24)
{
    auto notes = QJsonArray{};
    notes.append(QJsonObject{{QStringLiteral("relTick"), 0.0},
                             {QStringLiteral("key"), 60},
                             {QStringLiteral("duration"), 24.0},
                             {QStringLiteral("velocity"), 100}});
    auto tracks = QJsonArray{};
    tracks.append(QJsonObject{{QStringLiteral("track"), 0}, {QStringLiteral("notes"), notes}});
    auto lanes = QJsonArray{};
    auto tempo = QJsonArray{};
    return QJsonObject{
        {QStringLiteral("format"), 1},      {QStringLiteral("ticksPerBeat"), double(ticksPerBeat)},
        {QStringLiteral("span"), 0.0},      {QStringLiteral("wholeLane"), false},
        {QStringLiteral("tracks"), tracks}, {QStringLiteral("lanes"), lanes},
        {QStringLiteral("tempo"), tempo},
    };
}

QByteArray compact(const QJsonObject &object)
{
    return QJsonDocument(object).toJson(QJsonDocument::Compact);
}

} // namespace

int runClipMimeCheck()
{
    auto failures = 0;
    const auto fail = [&failures](const char *what) {
        std::fprintf(stderr, "clipmimecheck: FAIL %s\n", what);
        failures++;
    };
    const auto expect = [&fail](bool condition, const char *what) {
        if (!condition)
            fail(what);
    };

    // A plain note clip (span == 0) round-trips exactly.
    {
        Clip clip;
        clip.span = 0;
        clip.tracks = {{3, {{0, 60, 24, 100}, {12, 64, 12, 80}}}};
        const auto decoded = decodeClip(encodeClip(clip, 24));
        expect(decoded.has_value(), "note clip did not decode");
        if (decoded) {
            expect(decoded->ticksPerBeat == 24, "note clip lost ticksPerBeat");
            expect(sameClip(decoded->clip, clip), "note clip round trip changed content");
        }
    }

    // A time clip (span > 0) carries notes, MOD + pitch-bend lane points, an
    // empty volume lane, and tempo points; every field survives.
    {
        Clip clip;
        clip.span = 96;
        // wholeLane stays false: format 1 always carries it as false and
        // paste ignores it, so the codec round trip must preserve that.
        clip.tracks = {{0, {{0, 60, 24, 100}, {72, 67, 12, 90}}}};
        clip.lanes = {{0, 0x01, {{24, 80}, {72, 32}}}, // MOD
                      {0, 0xFF, {{48, 4096}}},         // pitch bend
                      {0, 0x07, {}}};                  // empty volume lane
        clip.tempo = {{0, 500000}, {48, 400000}};
        const auto decoded = decodeClip(encodeClip(clip, 24));
        expect(decoded.has_value(), "time clip did not decode");
        if (decoded) {
            expect(decoded->ticksPerBeat == 24, "time clip lost its ticksPerBeat");
            expect(sameClip(decoded->clip, clip), "time clip round trip changed content");
        }
    }

    // Rescaling up converts every tick field while preserving musical and
    // routing data verbatim.
    {
        Clip clip;
        clip.span = 12;
        clip.wholeLane = true;
        clip.tracks = {{3, {{6, 64, 3, 91}}}};
        clip.lanes = {{4, 0x01, {{6, -12}}}};
        clip.tempo = {{6, 400000}};
        Clip expected;
        expected.span = 24;
        expected.wholeLane = true;
        expected.tracks = {{3, {{12, 64, 6, 91}}}};
        expected.lanes = {{4, 0x01, {{12, -12}}}};
        expected.tempo = {{12, 400000}};
        expect(sameClip(rescaleClip(clip, 24, 48), expected),
               "upscaling changed fields other than tick units");
    }

    // Half ticks round up. Nonzero spans and durations survive aggressive
    // downscaling, while zero-duration notes stay zero. Points that coalesce
    // are ordered by destination tick and the last source point wins.
    {
        Clip clip;
        clip.span = 1;
        clip.tracks = {{2, {{1, 60, 1, 100}, {3, 61, 0, 80}}}};
        clip.lanes = {{2, 0x07, {{2, 20}, {1, 10}, {3, 30}}}};
        clip.tempo = {{2, 500000}, {1, 600000}, {3, 700000}};
        Clip expected;
        expected.span = 1;
        expected.tracks = {{2, {{1, 60, 1, 100}, {2, 61, 0, 80}}}};
        expected.lanes = {{2, 0x07, {{1, 10}, {2, 30}}}};
        expected.tempo = {{1, 600000}, {2, 700000}};
        expect(sameClip(rescaleClip(clip, 48, 24), expected),
               "downscaling did not round, preserve, or coalesce correctly");
    }

    // Destination field widths saturate instead of wrapping.
    {
        Clip clip;
        clip.span = UINT64_MAX;
        clip.tracks = {{0, {{UINT32_MAX, 127, UINT32_MAX, 255}}}};
        clip.lanes = {{0, 0x01, {{UINT32_MAX, std::numeric_limits<int>::min()}}}};
        clip.tempo = {{UINT64_MAX, UINT32_MAX}};
        const auto scaled = rescaleClip(clip, 1, UINT32_MAX);
        expect(scaled.span == UINT64_MAX, "scaled span overflowed");
        expect(scaled.tracks[0].notes[0].relTick == UINT32_MAX &&
                   scaled.tracks[0].notes[0].duration == UINT32_MAX,
               "scaled note fields overflowed");
        expect(scaled.lanes[0].points[0] ==
                   std::pair<uint32_t, int>{UINT32_MAX, std::numeric_limits<int>::min()},
               "scaled lane tick overflowed or changed its value");
        expect(scaled.tempo[0] == TempoPoint{UINT64_MAX, UINT32_MAX},
               "scaled tempo tick overflowed or changed its tempo");
    }

    // Same-resolution conversion is an exact identity, including source
    // ordering and duplicate point ticks.
    {
        Clip clip;
        clip.span = 0;
        clip.wholeLane = true;
        clip.tracks = {{7, {{9, 72, 5, 44}}}};
        clip.lanes = {{7, 0x01, {{4, 1}, {4, 2}, {2, 3}}}};
        clip.tempo = {{4, 500000}, {4, 600000}, {2, 700000}};
        expect(sameClip(rescaleClip(clip, 24, 24), clip),
               "same-TPB rescaling was not an exact identity");
    }

    // The QClipboard write/read path itself: decoding the raw clipboard
    // payload sees exactly what writeClipboard() published, and
    // clipboardHasClipMime() agrees.
    {
        Clip clip;
        clip.span = 24;
        clip.tracks = {{1, {{0, 55, 12, 70}}}};
        writeClipboard(clip, 24);
        expect(songview::clipboardHasClipMime(),
               "clipboard did not carry the custom MIME after write");
        const auto *mimeData = QGuiApplication::clipboard()->mimeData();
        const auto decoded = mimeData
                                 ? songview::decodeClip(mimeData->data(songview::kClipMimeType))
                                 : std::optional<songview::DecodedClip>{};
        expect(decoded.has_value(), "writeClipboard/readClipboard round trip failed");
        if (decoded)
            expect(sameClip(decoded->clip, clip) && decoded->ticksPerBeat == 24,
                   "clipboard round trip changed content");
        const auto converted = songview::readClipboard(48);
        expect(converted && converted->span == 48 && converted->tracks[0].notes[0].duration == 24,
               "typed clipboard read did not return destination tick units");
    }

    // A clipboard without the custom MIME reads as absent.
    {
        auto plain = new QMimeData();
        plain->setText(QStringLiteral("not a porydaw clip"));
        QGuiApplication::clipboard()->setMimeData(plain);
        expect(!songview::clipboardHasClipMime(), "plain text clipboard reported as a clip");
        const auto *mimeData = QGuiApplication::clipboard()->mimeData();
        expect(!mimeData ||
                   !songview::decodeClip(mimeData->data(songview::kClipMimeType)).has_value(),
               "plain text clipboard decoded as a clip");
    }

    // Malformed payloads decode to nothing: bad JSON, format != 1, missing
    // ticksPerBeat, ticksPerBeat == 0, and a truncated note entry.
    {
        expect(!decodeClip(QByteArrayLiteral("{\"format\": 1")).has_value(),
               "truncated JSON decoded");
        expect(!decodeClip(QByteArrayLiteral("not json at all")).has_value(),
               "garbage bytes decoded");

        auto wrongFormat = validPayload();
        wrongFormat.insert(QStringLiteral("format"), 2);
        expect(!decodeClip(compact(wrongFormat)).has_value(), "format 2 payload decoded");

        auto noTpb = validPayload();
        noTpb.remove(QStringLiteral("ticksPerBeat"));
        expect(!decodeClip(compact(noTpb)).has_value(), "payload without ticksPerBeat decoded");

        auto zeroTpb = validPayload(0);
        expect(!decodeClip(compact(zeroTpb)).has_value(), "payload with ticksPerBeat 0 decoded");

        auto truncatedNote = validPayload();
        auto brokenTracks = truncatedNote.value(QStringLiteral("tracks")).toArray();
        auto badNote = QJsonObject{{QStringLiteral("relTick"), 0.0},
                                   {QStringLiteral("key"), 60},
                                   {QStringLiteral("duration"), 24.0}}; // no velocity
        auto notes = QJsonArray{};
        notes.append(badNote);
        brokenTracks =
            QJsonArray{QJsonObject{{QStringLiteral("track"), 0}, {QStringLiteral("notes"), notes}}};
        truncatedNote.insert(QStringLiteral("tracks"), brokenTracks);
        expect(!decodeClip(compact(truncatedNote)).has_value(), "note missing velocity decoded");
    }

    return failures == 0 ? 0 : 1;
}