#include "ui/songview/clipmime.h"

#include <QClipboard>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QMimeData>
#include <QStringList>

#include <algorithm>
#include <cassert>
#include <cmath>
#include <limits>
#include <memory>

namespace songview {
namespace {

constexpr double kLargestExactJsonInteger = 9007199254740991.0;

bool hasKeys(const QJsonObject &object, const QStringList &keys)
{
    // Future formats may add keys; only the required ones are checked.
    return std::all_of(keys.begin(), keys.end(),
                       [&](const QString &key) { return object.contains(key); });
}

bool readUnsigned(const QJsonValue &value, uint64_t maximum, uint64_t &result)
{
    if (!value.isDouble())
        return false;
    const double number = value.toDouble();
    if (!std::isfinite(number) || number < 0.0 || number > kLargestExactJsonInteger ||
        number > static_cast<double>(maximum) || std::floor(number) != number)
        return false;
    result = static_cast<uint64_t>(number);
    return true;
}

bool readSigned(const QJsonValue &value, int &result)
{
    if (!value.isDouble())
        return false;
    const double number = value.toDouble();
    if (!std::isfinite(number) || number < double(std::numeric_limits<int>::min()) ||
        number > double(std::numeric_limits<int>::max()) || std::floor(number) != number)
        return false;
    result = static_cast<int>(number);
    return true;
}
bool requireUint(const QJsonObject &object, const char *key, uint64_t maximum, uint64_t &out)
{
    return object.contains(QLatin1String(key)) &&
           readUnsigned(object.value(QLatin1String(key)), maximum, out);
}

QJsonObject encodeNote(const ClipNote &note)
{
    return {{QStringLiteral("relTick"), double(note.relTick)},
            {QStringLiteral("key"), int(note.key)},
            {QStringLiteral("duration"), double(note.duration)},
            {QStringLiteral("velocity"), int(note.velocity)}};
}

QJsonObject encodeTrack(const ClipTrack &track)
{
    auto notes = QJsonArray{};
    for (const auto &note : track.notes)
        notes.append(encodeNote(note));
    return {{QStringLiteral("track"), track.track}, {QStringLiteral("notes"), notes}};
}

QJsonObject encodeLane(const ClipLane &lane)
{
    auto points = QJsonArray{};
    for (const auto &[tick, value] : lane.points)
        points.append(QJsonArray{double(tick), value});
    return {{QStringLiteral("track"), lane.track},
            {QStringLiteral("cc"), int(lane.cc)},
            {QStringLiteral("points"), points}};
}

QJsonObject encodeTempo(const TempoPoint &point)
{
    return {
        {QStringLiteral("relTick"), double(point.tick)},
        {QStringLiteral("microsecondsPerQuarterNote"), double(point.microsecondsPerQuarterNote)}};
}

std::optional<ClipNote> decodeNote(const QJsonValue &value)
{
    if (!value.isObject())
        return std::nullopt;
    const auto object = value.toObject();
    if (!hasKeys(object, {QStringLiteral("relTick"), QStringLiteral("key"),
                          QStringLiteral("duration"), QStringLiteral("velocity")}))
        return std::nullopt;
    uint64_t relTick = 0;
    uint64_t key = 0;
    uint64_t duration = 0;
    uint64_t velocity = 0;
    if (!requireUint(object, "relTick", UINT32_MAX, relTick) ||
        !requireUint(object, "key", UINT8_MAX, key) ||
        !requireUint(object, "duration", UINT32_MAX, duration) ||
        !requireUint(object, "velocity", UINT8_MAX, velocity))
        return std::nullopt;
    return ClipNote{uint32_t(relTick), uint8_t(key), uint32_t(duration), uint8_t(velocity)};
}

std::optional<ClipTrack> decodeTrack(const QJsonValue &value)
{
    if (!value.isObject())
        return std::nullopt;
    const auto object = value.toObject();
    if (!hasKeys(object, {QStringLiteral("track"), QStringLiteral("notes")}) ||
        !object.value(QStringLiteral("notes")).isArray())
        return std::nullopt;
    auto track = ClipTrack{};
    if (!readSigned(object.value(QStringLiteral("track")), track.track))
        return std::nullopt;
    for (const auto &noteValue : object.value(QStringLiteral("notes")).toArray()) {
        auto note = decodeNote(noteValue);
        if (!note)
            return std::nullopt;
        track.notes.push_back(*note);
    }
    return track;
}

std::optional<ClipLane> decodeLane(const QJsonValue &value)
{
    if (!value.isObject())
        return std::nullopt;
    const auto object = value.toObject();
    if (!hasKeys(object,
                 {QStringLiteral("track"), QStringLiteral("cc"), QStringLiteral("points")}) ||
        !object.value(QStringLiteral("points")).isArray())
        return std::nullopt;
    auto lane = ClipLane{};
    uint64_t cc = 0;
    if (!readSigned(object.value(QStringLiteral("track")), lane.track) ||
        !requireUint(object, "cc", UINT8_MAX, cc))
        return std::nullopt;
    lane.cc = uint8_t(cc);
    for (const auto &pointValue : object.value(QStringLiteral("points")).toArray()) {
        if (!pointValue.isArray())
            return std::nullopt;
        const auto point = pointValue.toArray();
        uint64_t tick = 0;
        int pointValueInt = 0;
        if (point.size() != 2 || !readUnsigned(point.at(0), UINT32_MAX, tick) ||
            !readSigned(point.at(1), pointValueInt))
            return std::nullopt;
        lane.points.emplace_back(uint32_t(tick), pointValueInt);
    }
    return lane;
}

std::optional<TempoPoint> decodeTempo(const QJsonValue &value)
{
    if (!value.isObject())
        return std::nullopt;
    const auto object = value.toObject();
    if (!hasKeys(object, {QStringLiteral("relTick"), QStringLiteral("microsecondsPerQuarterNote")}))
        return std::nullopt;
    uint64_t relTick = 0;
    uint64_t microseconds = 0;
    if (!requireUint(object, "relTick", UINT64_MAX, relTick) ||
        !requireUint(object, "microsecondsPerQuarterNote", UINT32_MAX, microseconds))
        return std::nullopt;
    return TempoPoint{relTick, uint32_t(microseconds)};
}

uint64_t scaleTick(uint64_t tick, uint32_t sourceTicksPerBeat, uint32_t destinationTicksPerBeat,
                   uint64_t maximum)
{
    const auto quotient = tick / sourceTicksPerBeat;
    const auto remainder = tick % sourceTicksPerBeat;
    if (quotient > maximum / destinationTicksPerBeat)
        return maximum;
    const auto whole = quotient * destinationTicksPerBeat;
    const auto scaledRemainder = remainder * uint64_t(destinationTicksPerBeat);
    auto fractional = scaledRemainder / sourceTicksPerBeat;
    const auto residual = scaledRemainder % sourceTicksPerBeat;
    if (residual * 2 >= sourceTicksPerBeat)
        fractional++;
    if (fractional > maximum - whole)
        return maximum;
    return whole + fractional;
}
// Stable-sorts by tick and coalesces same-tick entries, the later entry
// winning — the collision policy rescaleClip relies on for both lane points
// (std::pair, .first) and tempo points (.tick).
template <class Point>
void dedupLastWinsByTick(std::vector<Point> &points)
{
    const auto tickOf = [](const Point &point) -> uint64_t {
        if constexpr (requires { point.tick; })
            return point.tick;
        else
            return point.first;
    };
    std::stable_sort(points.begin(), points.end(),
                     [&](const Point &a, const Point &b) { return tickOf(a) < tickOf(b); });
    auto output = size_t{0};
    for (const Point &point : points) {
        if (output != 0 && tickOf(points[output - 1]) == tickOf(point))
            points[output - 1] = point;
        else
            points[output++] = point;
    }
    points.resize(output);
}

} // namespace

Clip rescaleClip(Clip result, uint32_t sourceTicksPerBeat, uint32_t destinationTicksPerBeat)
{
    assert(sourceTicksPerBeat != 0);
    assert(destinationTicksPerBeat != 0);
    if (sourceTicksPerBeat == destinationTicksPerBeat)
        return result;
    if (result.span != 0)
        result.span = std::max(uint64_t{1}, scaleTick(result.span, sourceTicksPerBeat,
                                                      destinationTicksPerBeat, UINT64_MAX));
    for (auto &track : result.tracks) {
        for (auto &note : track.notes) {
            note.relTick = uint32_t(
                scaleTick(note.relTick, sourceTicksPerBeat, destinationTicksPerBeat, UINT32_MAX));
            if (note.duration != 0)
                note.duration =
                    std::max(uint32_t{1}, uint32_t(scaleTick(note.duration, sourceTicksPerBeat,
                                                             destinationTicksPerBeat, UINT32_MAX)));
        }
    }
    for (auto &lane : result.lanes) {
        for (auto &[tick, value] : lane.points) {
            (void)value;
            tick =
                uint32_t(scaleTick(tick, sourceTicksPerBeat, destinationTicksPerBeat, UINT32_MAX));
        }
        dedupLastWinsByTick(lane.points);
    }
    for (auto &point : result.tempo)
        point.tick = scaleTick(point.tick, sourceTicksPerBeat, destinationTicksPerBeat, UINT64_MAX);
    dedupLastWinsByTick(result.tempo);
    return result;
}

QByteArray encodeClip(const Clip &clip, uint32_t ticksPerBeat)
{
    auto tracks = QJsonArray{};
    for (const auto &track : clip.tracks)
        tracks.append(encodeTrack(track));
    auto lanes = QJsonArray{};
    for (const auto &lane : clip.lanes)
        lanes.append(encodeLane(lane));
    auto tempo = QJsonArray{};
    for (const auto &point : clip.tempo)
        tempo.append(encodeTempo(point));
    const auto object = QJsonObject{
        {QStringLiteral("format"), 1},
        {QStringLiteral("ticksPerBeat"), double(ticksPerBeat)},
        {QStringLiteral("span"), double(clip.span)},
        {QStringLiteral("wholeLane"), false},
        {QStringLiteral("tracks"), tracks},
        {QStringLiteral("lanes"), lanes},
        {QStringLiteral("tempo"), tempo},
    };
    return QJsonDocument(object).toJson(QJsonDocument::Compact);
}

std::optional<DecodedClip> decodeClip(const QByteArray &payload)
{
    auto error = QJsonParseError{};
    const auto document = QJsonDocument::fromJson(payload, &error);
    if (error.error != QJsonParseError::NoError || !document.isObject())
        return std::nullopt;
    const auto object = document.object();
    if (!hasKeys(object,
                 {QStringLiteral("format"), QStringLiteral("ticksPerBeat"), QStringLiteral("span"),
                  QStringLiteral("tracks"), QStringLiteral("lanes"), QStringLiteral("tempo")}))
        return std::nullopt;
    uint64_t format = 0;
    uint64_t ticksPerBeat = 0;
    uint64_t span = 0;
    if (!requireUint(object, "format", 1, format) || format != 1 ||
        !requireUint(object, "ticksPerBeat", UINT32_MAX, ticksPerBeat) || ticksPerBeat == 0 ||
        !requireUint(object, "span", UINT64_MAX, span) ||
        !object.value(QStringLiteral("tracks")).isArray() ||
        !object.value(QStringLiteral("lanes")).isArray() ||
        !object.value(QStringLiteral("tempo")).isArray())
        return std::nullopt;
    auto decoded = DecodedClip{};
    decoded.ticksPerBeat = uint32_t(ticksPerBeat);
    decoded.clip.span = span;
    for (const auto &trackValue : object.value(QStringLiteral("tracks")).toArray()) {
        auto track = decodeTrack(trackValue);
        if (!track)
            return std::nullopt;
        decoded.clip.tracks.push_back(std::move(*track));
    }
    for (const auto &laneValue : object.value(QStringLiteral("lanes")).toArray()) {
        auto lane = decodeLane(laneValue);
        if (!lane)
            return std::nullopt;
        decoded.clip.lanes.push_back(std::move(*lane));
    }
    for (const auto &tempoValue : object.value(QStringLiteral("tempo")).toArray()) {
        auto point = decodeTempo(tempoValue);
        if (!point)
            return std::nullopt;
        decoded.clip.tempo.push_back(*point);
    }
    return decoded;
}

void writeClipboard(const Clip &clip, uint32_t ticksPerBeat)
{
    auto mimeData = std::make_unique<QMimeData>();
    mimeData->setData(kClipMimeType, encodeClip(clip, ticksPerBeat));
    QGuiApplication::clipboard()->setMimeData(mimeData.release());
}

std::optional<Clip> readClipboard(uint32_t destinationTicksPerBeat, bool *outDecodeFailed)
{
    if (outDecodeFailed)
        *outDecodeFailed = false;
    const auto *mimeData = QGuiApplication::clipboard()->mimeData();
    if (!mimeData || !mimeData->hasFormat(kClipMimeType))
        return std::nullopt;
    auto decoded = decodeClip(mimeData->data(kClipMimeType));
    if (!decoded) {
        if (outDecodeFailed)
            *outDecodeFailed = true;
        return std::nullopt;
    }
    return rescaleClip(std::move(decoded->clip), decoded->ticksPerBeat, destinationTicksPerBeat);
}

bool clipboardHasClipMime()
{
    const auto *mimeData = QGuiApplication::clipboard()->mimeData();
    return mimeData && mimeData->hasFormat(kClipMimeType);
}

} // namespace songview
