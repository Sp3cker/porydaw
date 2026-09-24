#include "checks/playback/tst_transport.h"

#include <QDebug>
#include <QFile>
#include <QTemporaryFile>
#include <QTest>
#include <array>

#include "audio/audioengine.h"
#include "checks/playback/transportfixture.h"

namespace checks {

TransportTest::TransportTest() = default;

TransportTest::~TransportTest() = default;

void TransportTest::init()
{
    // The transport contracts are sample- and timing-exact, so they run on
    // the forced null backend: init failure fails the slot instead of
    // silently skipping (a missing real device is not a valid skip — the
    // null device runs the same callbacks without hardware).
    qputenv("PORYDAW_AUDIO_BACKEND", "null");
    m_bank = std::make_unique<AuditionVoicegroup>();
    m_engine = std::make_unique<AudioEngine>();
    QString error;
    QVERIFY2(m_engine->init(&error),
             qPrintable(QStringLiteral("forced null audio backend init failed: %1").arg(error)));
    QVERIFY2(m_engine->usingNullBackend() && m_engine->nullBackendForced(),
             "AudioEngine did not land on the forced null backend");
}

void TransportTest::cleanup()
{
    // Audio dies before the bank it borrowed (contract: destroy audio
    // before fixture data).
    m_engine.reset();
    m_bank.reset();
}

AudioEngine &TransportTest::engine() noexcept
{
    return *m_engine;
}

std::shared_ptr<const PdPlaybackData> TransportTest::loadedSong(const TransportMidiFile &midi,
                                                                const char *what)
{
    const QByteArray bytes = midi.encode();
    if (bytes.isEmpty()) {
        qWarning("%s: fixture MIDI encoding failed", what);
        return {};
    }

    QTemporaryFile file;
    if (!file.open() || file.write(bytes) != bytes.size() || !file.flush()) {
        qWarning("%s: could not write fixture MIDI bytes", what);
        return {};
    }

    PdPlaybackData *publication = nullptr;
    std::array<char, 1024> diagnostic{};
    const QByteArray path = QFile::encodeName(file.fileName());
    if (!pd_playback_data_load_file(path.constData(), engine().sampleRate(), &publication,
                                    diagnostic.data(), diagnostic.size())) {
        if (publication)
            pd_playback_data_release(publication);
        qWarning("%s: Swift playback loader failed: %s", what, diagnostic.data());
        return {};
    }
    if (!publication) {
        qWarning("%s: Swift playback loader returned no publication", what);
        return {};
    }
    return std::shared_ptr<const PdPlaybackData>{publication, pd_playback_data_release};
}

bool TransportTest::ringingTail(AudioEngine &engine, uint8_t track)
{
    engine.previewNoteTimed(track, 60, 127, uint32_t(0.15 * engine.sampleRate()));
    if (!QTest::qWaitFor([&] { return engine.activePcmChannels() >= 1; }, 2000)) {
        QTest::qFail("timed preview never sounded", __FILE__, __LINE__);
        return false;
    }
    QTest::qWait(400); // note-off sent; the slow release rings on
    if (engine.activePcmChannels() < 1) {
        QTest::qFail("slow-release tail died early (control expectation changed?)", __FILE__,
                     __LINE__);
        return false;
    }
    return true;
}

} // namespace checks

int runTransportCheck(const QStringList &qtArguments)
{
    checks::TransportTest test;
    QStringList arguments{QStringLiteral("transportcheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
