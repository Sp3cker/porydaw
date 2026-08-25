#pragma once

#include "ui/songview/clipmime.h"

#include <cstddef>
#include <optional>

#include <QClipboard>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMimeData>

namespace clipcheck_support {

// Read the raw clip payload so checks can verify the source TPB carried by a
// clipboard write, without rescaling it through readClipboard().
inline std::optional<songview::DecodedClip> checkClipboardClip()
{
    const auto *mimeData = QGuiApplication::clipboard()->mimeData();
    if (!mimeData || !mimeData->hasFormat(songview::kClipMimeType))
        return std::nullopt;
    return songview::decodeClip(mimeData->data(songview::kClipMimeType));
}

inline bool sameClip(const songview::Clip &a, const songview::Clip &b)
{
    if (a.span != b.span || a.tracks.size() != b.tracks.size() ||
        a.lanes.size() != b.lanes.size() || a.tempo.size() != b.tempo.size())
        return false;
    for (std::size_t i = 0; i < a.tracks.size(); ++i) {
        const auto &left = a.tracks[i];
        const auto &right = b.tracks[i];
        if (left.track != right.track || left.notes.size() != right.notes.size())
            return false;
        for (std::size_t j = 0; j < left.notes.size(); ++j) {
            const auto &leftNote = left.notes[j];
            const auto &rightNote = right.notes[j];
            if (leftNote.relTick != rightNote.relTick || leftNote.key != rightNote.key ||
                leftNote.duration != rightNote.duration || leftNote.velocity != rightNote.velocity)
                return false;
        }
    }
    for (std::size_t i = 0; i < a.lanes.size(); ++i) {
        const auto &left = a.lanes[i];
        const auto &right = b.lanes[i];
        if (left.track != right.track || left.cc != right.cc ||
            left.points.size() != right.points.size())
            return false;
        for (std::size_t j = 0; j < left.points.size(); ++j)
            if (left.points[j] != right.points[j])
                return false;
    }
    for (std::size_t i = 0; i < a.tempo.size(); ++i)
        if (!(a.tempo[i] == b.tempo[i]))
            return false;
    return true;
}

// A well-formed format-1 payload object; malformed-payload checks delete or
// corrupt one key at a time.
inline QJsonObject makeValidClipPayload(uint32_t ticksPerBeat = 24)
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

inline QByteArray compactJson(const QJsonObject &object)
{
    return QJsonDocument(object).toJson(QJsonDocument::Compact);
}

} // namespace clipcheck_support
