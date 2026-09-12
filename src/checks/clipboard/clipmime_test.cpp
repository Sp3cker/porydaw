#include "checks/clipcheck_support.h"

#include <QClipboard>
#include <QGuiApplication>
#include <QMimeData>
#include <QtTest>

#include <limits>
#include <memory>
#include <optional>

#include "ui/songview/clip.h"
#include "ui/songview/clipmime.h"

namespace {

using songview::Clip;

constexpr uint8_t kCcModulation = 0x01;
constexpr uint8_t kCcVolume = 0x07;
constexpr uint8_t kCcPitchBend = 0xff;

enum class RescaleFamily { Up, DownWithCoalescing, Saturation, Identity };
enum class CodecFamily { Note, Time };

Clip rescaleInput(RescaleFamily family)
{
    Clip clip;
    switch (family) {
    case RescaleFamily::Up:
        clip.span = 12;
        clip.tracks = {{3, {{6, 64, 3, 91}}}};
        clip.lanes = {{4, kCcModulation, {{6, -12}}}};
        clip.tempo = {{6, 400000}};
        return clip;
    case RescaleFamily::DownWithCoalescing:
        clip.span = 1;
        clip.tracks = {{2, {{1, 60, 1, 100}, {3, 61, 0, 80}}}};
        clip.lanes = {{2, kCcVolume, {{2, 20}, {1, 10}, {3, 30}}}};
        clip.tempo = {{2, 500000}, {1, 600000}, {3, 700000}};
        return clip;
    case RescaleFamily::Saturation:
        clip.span = CoreTimeDefaults::kNoTick;
        clip.tracks = {{0, {{CoreTimeDefaults::kNoTick, 127, UINT32_MAX, 255}}}};
        clip.lanes = {
            {0, kCcModulation, {{CoreTimeDefaults::kNoTick, std::numeric_limits<int>::min()}}}};
        clip.tempo = {{CoreTimeDefaults::kNoTick, UINT32_MAX}};
        return clip;
    case RescaleFamily::Identity:
        clip.tracks = {{7, {{9, 72, 5, 44}}}};
        clip.lanes = {{7, kCcModulation, {{4, 1}, {4, 2}, {2, 3}}}};
        clip.tempo = {{4, 500000}, {4, 600000}, {2, 700000}};
        return clip;
    }
    Q_UNREACHABLE();
}

Clip rescaleExpected(RescaleFamily family)
{
    Clip expected;
    switch (family) {
    case RescaleFamily::Up:
        expected.span = 24;
        expected.tracks = {{3, {{12, 64, 6, 91}}}};
        expected.lanes = {{4, kCcModulation, {{12, -12}}}};
        expected.tempo = {{12, 400000}};
        return expected;
    case RescaleFamily::DownWithCoalescing:
        expected.span = 1;
        expected.tracks = {{2, {{1, 60, 1, 100}, {2, 61, 0, 80}}}};
        expected.lanes = {{2, kCcVolume, {{1, 10}, {2, 30}}}};
        expected.tempo = {{1, 600000}, {2, 700000}};
        return expected;
    case RescaleFamily::Saturation: {
        Clip saturated = rescaleInput(family);
        // span and tempo ticks clamp at kMaxTick; relTick and lane ticks
        // saturate at UINT32_MAX (== kNoTick), unchanged from the input.
        saturated.span = CoreTimeDefaults::kMaxTick;
        saturated.tempo = {{CoreTimeDefaults::kMaxTick, UINT32_MAX}};
        return saturated;
    }
    case RescaleFamily::Identity:
        return rescaleInput(family);
    }
    Q_UNREACHABLE();
}

Clip codecClip(CodecFamily family)
{
    Clip clip;
    if (family == CodecFamily::Note) {
        clip.tracks = {{3, {{0, 60, 24, 100}, {12, 64, 12, 80}}}};
        return clip;
    }

    clip.span = 96;
    clip.tracks = {{0, {{0, 60, 24, 100}, {72, 67, 12, 90}}}};
    clip.lanes = {{0, kCcModulation, {{24, 80}, {72, 32}}},
                  {0, kCcPitchBend, {{48, 4096}}},
                  {0, kCcVolume, {}}};
    clip.tempo = {{0, 500000}, {48, 400000}};
    return clip;
}

QByteArray malformedPayload(const QString &kind)
{
    if (kind == QStringLiteral("truncated_json"))
        return QByteArrayLiteral("{\"format\": 1");
    if (kind == QStringLiteral("garbage_bytes"))
        return QByteArrayLiteral("not json at all");

    QJsonObject payload = clipcheck_support::makeValidClipPayload();
    if (kind == QStringLiteral("wrong_format"))
        payload.insert(QStringLiteral("format"), 2);
    else if (kind == QStringLiteral("missing_ticks_per_beat"))
        payload.remove(QStringLiteral("ticksPerBeat"));
    else if (kind == QStringLiteral("zero_ticks_per_beat"))
        payload.insert(QStringLiteral("ticksPerBeat"), 0);
    else if (kind == QStringLiteral("missing_tracks"))
        payload.remove(QStringLiteral("tracks"));
    else if (kind == QStringLiteral("wrong_typed_lanes"))
        payload.insert(QStringLiteral("lanes"), QJsonObject{});
    else if (kind == QStringLiteral("missing_tempo"))
        payload.remove(QStringLiteral("tempo"));
    else if (kind == QStringLiteral("negative_span"))
        payload.insert(QStringLiteral("span"), -1.0);
    else if (kind == QStringLiteral("negative_note_tick")) {
        QJsonArray tracks = payload.value(QStringLiteral("tracks")).toArray();
        QJsonObject track = tracks.first().toObject();
        QJsonArray notes = track.value(QStringLiteral("notes")).toArray();
        QJsonObject note = notes.first().toObject();
        note.insert(QStringLiteral("relTick"), -1.0);
        notes[0] = note;
        track.insert(QStringLiteral("notes"), notes);
        tracks[0] = track;
        payload.insert(QStringLiteral("tracks"), tracks);
    } else if (kind == QStringLiteral("missing_note_velocity")) {
        QJsonArray tracks = payload.value(QStringLiteral("tracks")).toArray();
        QJsonObject track = tracks.first().toObject();
        QJsonArray notes = track.value(QStringLiteral("notes")).toArray();
        QJsonObject note = notes.first().toObject();
        note.remove(QStringLiteral("velocity"));
        notes[0] = note;
        track.insert(QStringLiteral("notes"), notes);
        tracks[0] = track;
        payload.insert(QStringLiteral("tracks"), tracks);
    } else if (kind == QStringLiteral("lane_point_missing_value")) {
        payload.insert(
            QStringLiteral("lanes"),
            QJsonArray{QJsonObject{{QStringLiteral("track"), 0},
                                   {QStringLiteral("cc"), int(kCcModulation)},
                                   {QStringLiteral("points"), QJsonArray{QJsonArray{12}}}}});
    } else if (kind == QStringLiteral("tempo_missing_microseconds")) {
        payload.insert(QStringLiteral("tempo"),
                       QJsonArray{QJsonObject{{QStringLiteral("relTick"), 12.0}}});
    } else if (kind == QStringLiteral("nonfinite_tick")) {
        return QByteArrayLiteral(
            "{\"format\":1,\"ticksPerBeat\":24,\"span\":0,\"tracks\":[{\"track\":0,"
            "\"notes\":[{\"relTick\":NaN,\"key\":60,\"duration\":24,\"velocity\":100}]}],"
            "\"lanes\":[],\"tempo\":[]}");
    }
    return clipcheck_support::compactJson(payload);
}

class ClipMimeTest final : public QObject
{
    Q_OBJECT

  public:
    ClipMimeTest() = default;
    Q_DISABLE_COPY_MOVE(ClipMimeTest)

  private slots:
    void init()
    {
        m_clipboard = std::make_unique<clipcheck_support::ClipboardStateGuard>();
        m_clipboard->clear();
    }

    void cleanup() { m_clipboard.reset(); }

    void rescaleFamilies_data()
    {
        QTest::addColumn<int>("family");
        QTest::newRow("up_24_to_48") << int(RescaleFamily::Up);
        QTest::newRow("down_48_to_24_round_up_last_wins") << int(RescaleFamily::DownWithCoalescing);
        QTest::newRow("saturates_without_wrap") << int(RescaleFamily::Saturation);
        QTest::newRow("same_tpb_is_exact_identity") << int(RescaleFamily::Identity);
    }

    void rescaleFamilies()
    {
        QFETCH(int, family);
        const auto selected = static_cast<RescaleFamily>(family);
        uint32_t sourceTpb = 24;
        uint32_t destinationTpb = 24;
        if (selected == RescaleFamily::Up)
            destinationTpb = 48;
        else if (selected == RescaleFamily::DownWithCoalescing)
            sourceTpb = 48;
        else if (selected == RescaleFamily::Saturation) {
            sourceTpb = 1;
            destinationTpb = UINT32_MAX;
        }
        const Clip actual =
            songview::rescaleClip(rescaleInput(selected), sourceTpb, destinationTpb);
        QVERIFY(clipcheck_support::sameClip(actual, rescaleExpected(selected)));
    }

    void codecRoundTrips_data()
    {
        QTest::addColumn<int>("family");
        QTest::newRow("plain_note_clip") << int(CodecFamily::Note);
        QTest::newRow("time_clip_with_bend_empty_lane_and_tempo") << int(CodecFamily::Time);
    }

    void codecRoundTrips()
    {
        QFETCH(int, family);
        const Clip expected = codecClip(static_cast<CodecFamily>(family));
        const std::optional<songview::DecodedClip> decoded =
            songview::decodeClip(songview::encodeClip(expected, 24));
        QVERIFY(decoded.has_value());
        QCOMPARE(decoded->ticksPerBeat, uint32_t{24});
        QVERIFY(clipcheck_support::sameClip(decoded->clip, expected));
    }

    void clipboardRoutesClipMime()
    {
        Clip clip;
        clip.span = 24;
        clip.tracks = {{1, {{0, 55, 12, 70}}}};
        songview::writeClipboard(clip, 24);

        QVERIFY(songview::clipboardHasClipMime());
        const std::optional<songview::DecodedClip> raw = clipcheck_support::checkClipboardClip();
        QVERIFY(raw.has_value());
        QCOMPARE(raw->ticksPerBeat, uint32_t{24});
        QVERIFY(clipcheck_support::sameClip(raw->clip, clip));

        const std::optional<Clip> converted = songview::readClipboard(48);
        QVERIFY(converted.has_value());
        QCOMPARE(converted->span, uint64_t{48});
        QCOMPARE(converted->tracks.size(), size_t{1});
        QCOMPARE(converted->tracks.front().notes.front().duration, uint32_t{24});
    }

    void foreignClipboardIsNotClip()
    {
        auto plain = std::make_unique<QMimeData>();
        plain->setText(QStringLiteral("not a porydaw clip"));
        QGuiApplication::clipboard()->setMimeData(plain.release());

        QVERIFY(!songview::clipboardHasClipMime());
        QVERIFY(!clipcheck_support::checkClipboardClip().has_value());
    }

    void malformedPayloads_data()
    {
        QTest::addColumn<QString>("kind");
        QTest::newRow("truncated_json") << QStringLiteral("truncated_json");
        QTest::newRow("garbage_bytes") << QStringLiteral("garbage_bytes");
        QTest::newRow("wrong_format") << QStringLiteral("wrong_format");
        QTest::newRow("missing_ticks_per_beat") << QStringLiteral("missing_ticks_per_beat");
        QTest::newRow("zero_ticks_per_beat") << QStringLiteral("zero_ticks_per_beat");
        QTest::newRow("missing_tracks") << QStringLiteral("missing_tracks");
        QTest::newRow("wrong_typed_lanes") << QStringLiteral("wrong_typed_lanes");
        QTest::newRow("missing_tempo") << QStringLiteral("missing_tempo");
        QTest::newRow("negative_span") << QStringLiteral("negative_span");
        QTest::newRow("negative_note_tick") << QStringLiteral("negative_note_tick");
        QTest::newRow("missing_note_velocity") << QStringLiteral("missing_note_velocity");
        QTest::newRow("lane_point_missing_value") << QStringLiteral("lane_point_missing_value");
        QTest::newRow("tempo_missing_microseconds") << QStringLiteral("tempo_missing_microseconds");
        QTest::newRow("nonfinite_tick") << QStringLiteral("nonfinite_tick");
    }

    void malformedPayloads()
    {
        QFETCH(QString, kind);
        QVERIFY(!songview::decodeClip(malformedPayload(kind)).has_value());
    }

    void malformedCustomMimeReportsDecodeFailure()
    {
        auto corrupt = std::make_unique<QMimeData>();
        corrupt->setData(songview::kClipMimeType, QByteArrayLiteral("not json at all"));
        QGuiApplication::clipboard()->setMimeData(corrupt.release());

        bool decodeFailed = false;
        QVERIFY(!songview::readClipboard(24, &decodeFailed).has_value());
        QVERIFY(decodeFailed);
    }

  private:
    std::unique_ptr<clipcheck_support::ClipboardStateGuard> m_clipboard;
};

} // namespace

int runClipMimeCheck(const QStringList &qtArguments)
{
    ClipMimeTest test;
    QStringList arguments{QStringLiteral("clipmimecheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "clipmime_test.moc"
