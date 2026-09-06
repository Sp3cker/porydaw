#include "checks/polyphony/tst_polyphonycheck.h"

#include <QByteArray>
#include <QCoreApplication>
#include <QFileInfo>
#include <QImage>
#include <QStringList>
#include <QtTest>

#include <memory>

#include "audio/audioengine.h"
#include "core/miditimeline.h"
#include "core/smf.h"
#include "ui/polyphonypanel.h"

extern "C" {
#include "m4a_engine.h"
}

namespace {

constexpr uint32_t kDivision = 24;
constexpr double kSampleRate = 48000.0;

SmfEvent event(uint64_t tick, uint8_t status, uint8_t data0, uint8_t data1)
{
    SmfEvent result;
    result.tick = tick;
    result.status = status;
    result.data0 = data0;
    result.data1 = data1;
    return result;
}

SmfEvent meta(uint64_t tick, uint8_t type, const QByteArray &blob)
{
    SmfEvent result;
    result.tick = tick;
    result.status = 0xFF;
    result.metaType = type;
    result.blob = blob;
    return result;
}

std::unique_ptr<MidiTimeline> signatureTimeline()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = kDivision;
    smf.tracks.resize(2);
    smf.tracks[0].events = {meta(0, 0x51, QByteArray("\x07\xA1\x20", 3)),
                            meta(0, 0x58, QByteArray("\x04\x02\x18\x08", 4)),
                            meta(192, 0x58, QByteArray("\x03\x02\x18\x08", 4))};
    smf.tracks[0].endTick = 384;
    smf.tracks[1].events = {event(0, 0xC0, 0, 0), event(0, 0x90, 60, 100), event(24, 0x80, 60, 0)};
    smf.tracks[1].endTick = 384;
    return MidiTimeline::build(smf, kSampleRate);
}

AudioEngine::PolySnapshot snapshotWithEvents(std::initializer_list<M4APolyEvent> events,
                                             uint32_t startTotal = 0)
{
    AudioEngine::PolySnapshot snapshot;
    snapshot.maxPcmChannels = 5;
    uint32_t total = startTotal;
    for (const M4APolyEvent &event : events)
        snapshot.events[total++ % M4A_POLY_EVENT_CAPACITY] = event;
    snapshot.eventTotal = total;
    return snapshot;
}

AudioEngine::PolySnapshot richSnapshot()
{
    AudioEngine::PolySnapshot snapshot = snapshotWithEvents({
        {M4A_POLY_STOLEN, 2, 60, 4, 5, 96},
        {M4A_POLY_TAIL_CUT, 2, 72, 0, 5, 216},
        {M4A_POLY_DROPPED, 1, 67, 1, 0, M4A_POLY_TICK_NONE},
    });
    snapshot.steal[2] = 1;
    snapshot.tailCut[2] = 1;
    snapshot.drop[1] = 1;
    snapshot.invert = true;
    snapshot.pcm[0] = {true, false, 2, 60};
    snapshot.pcm[MAX_PCM_CHANNELS] = {true, false, 4, 72};
    return snapshot;
}

struct PanelFixture {
    std::unique_ptr<MidiTimeline> timeline = signatureTimeline();
    std::unique_ptr<PolyphonyPanel> panel = std::make_unique<PolyphonyPanel>();

    PanelFixture()
    {
        panel->resize(380, 760);
        panel->setTimeline(timeline.get());
        QStringList trackNames;
        trackNames.reserve(16);
        for (int track = 0; track < 16; ++track)
            trackNames.append(QString());
        trackNames[2] = QStringLiteral("Brass");
        panel->setTrackNames(trackNames);
        QStringList voiceNames;
        voiceNames.reserve(128);
        for (int voice = 0; voice < 128; ++voice)
            voiceNames.append(QString());
        voiceNames[5] = QStringLiteral("voice_piano");
        panel->setVoiceNames(voiceNames);
    }

    void showAndSettle()
    {
        panel->show();
        for (int pass = 0; pass < 3; ++pass)
            QCoreApplication::processEvents();
    }
};

QString derivedScreenshotPath(const QString &path, const QString &suffix)
{
    const QFileInfo info(path);
    return info.path() + QLatin1Char('/') + info.completeBaseName() + suffix + QLatin1Char('.') +
           info.suffix();
}

} // namespace

namespace checks {

void PolyphonyGateTest::logOrderAndFormatting()
{
    PanelFixture fixture;
    QVERIFY(fixture.timeline);
    fixture.panel->updateSnapshot(richSnapshot());

    QCOMPARE(fixture.panel->logRowCount(), 3);
    const QString newest = fixture.panel->logRowText(0);
    const QString middle = fixture.panel->logRowText(1);
    const QString oldest = fixture.panel->logRowText(2);
    QVERIFY(newest.contains(QStringLiteral("live")));
    QVERIFY(newest.contains(QStringLiteral("dropped")));
    QVERIFY(middle.contains(QStringLiteral("3:2.0")));
    QVERIFY(middle.contains(QStringLiteral("tail cut")));
    QVERIFY(oldest.contains(QStringLiteral("2:1.0")));
    QVERIFY(oldest.contains(QStringLiteral("Trk 3")));
    QVERIFY(oldest.contains(QStringLiteral("C4")));
    QVERIFY(oldest.contains(QStringLiteral("voice_piano")));
    QVERIFY(oldest.contains(QStringLiteral("cut off by Trk 5")));
}

void PolyphonyGateTest::positionedLogRowJumpsAndLiveDoesNot()
{
    PanelFixture fixture;
    QSignalSpy jumped(fixture.panel.get(), &PolyphonyPanel::jumpToEvent);
    QVERIFY(jumped.isValid());
    fixture.panel->updateSnapshot(richSnapshot());

    fixture.panel->activateLogRow(2);
    QCOMPARE(jumped.count(), 1);
    const QList<QVariant> jump = jumped.takeFirst();
    QCOMPARE(jump[0].toULongLong(), uint64_t(96));
    QCOMPARE(jump[1].toInt(), 2);
    QCOMPARE(jump[2].toInt(), 60);
    fixture.panel->activateLogRow(0);
    QCOMPARE(jumped.count(), 0);
}

void PolyphonyGateTest::resetRebasesLog()
{
    PanelFixture fixture;
    fixture.panel->updateSnapshot(richSnapshot());
    AudioEngine::PolySnapshot reset = snapshotWithEvents({{M4A_POLY_DROPPED, 0, 60, 0, 0, 48}});
    reset.drop[0] = 1;
    fixture.panel->updateSnapshot(reset);
    QCOMPARE(fixture.panel->logRowCount(), 1);
}

void PolyphonyGateTest::logCapIs500()
{
    PanelFixture fixture;
    AudioEngine::PolySnapshot snapshot = snapshotWithEvents({{M4A_POLY_DROPPED, 0, 60, 0, 0, 48}});
    snapshot.drop[0] = 1;
    fixture.panel->updateSnapshot(snapshot);
    uint32_t total = snapshot.eventTotal;
    for (int poll = 0; poll < 10; ++poll) {
        AudioEngine::PolySnapshot burst;
        burst.maxPcmChannels = 5;
        for (int index = 0; index < 60; ++index)
            burst.events[total++ % M4A_POLY_EVENT_CAPACITY] = {M4A_POLY_DROPPED, 0, 60, 0, 0,
                                                               uint32_t(total)};
        burst.eventTotal = total;
        fixture.panel->updateSnapshot(burst);
    }
    QCOMPARE(fixture.panel->logRowCount(), 500);
}

void PolyphonyGateTest::responsiveLayout()
{
    PanelFixture fixture;
    fixture.panel->updateSnapshot(richSnapshot());
    fixture.showAndSettle();

    fixture.panel->resize(180, 980);
    QCoreApplication::processEvents();
    QTRY_VERIFY(fixture.panel->isVisible());
    QTRY_VERIFY(!fixture.panel->wideLayoutActive());
    QTRY_VERIFY(fixture.panel->overflowSectionRect().top() >=
                fixture.panel->usageSectionRect().bottom());
    QTRY_VERIFY(fixture.panel->gridFullyVisible());

    fixture.panel->resize(900, 600);
    QCoreApplication::processEvents();
    QTRY_VERIFY(fixture.panel->wideLayoutActive());
    QTRY_VERIFY(fixture.panel->overflowSectionRect().left() >=
                fixture.panel->usageSectionRect().right());
    QTRY_VERIFY(fixture.panel->gridFullyVisible());

    fixture.panel->resize(380, 240);
    QCoreApplication::processEvents();
    QTRY_VERIFY(fixture.panel->gridFullyVisible());
    QTRY_VERIFY(fixture.panel->vScrollRange() > 0);

    fixture.panel->resize(380, 980);
    QCoreApplication::processEvents();
    QTRY_COMPARE(fixture.panel->vScrollRange(), 0);
}

void PolyphonyGateTest::rasterSmoke()
{
    PanelFixture fixture;
    fixture.panel->updateSnapshot(snapshotWithEvents({}));
    fixture.panel->updateSnapshot(richSnapshot());
    fixture.showAndSettle();

    QTRY_VERIFY(fixture.panel->isVisible());
    QImage initial(fixture.panel->size(), QImage::Format_ARGB32_Premultiplied);
    initial.fill(Qt::white);
    fixture.panel->render(&initial);
    QVERIFY(!initial.isNull());
    if (!m_screenshotPath.isEmpty())
        QVERIFY(initial.save(m_screenshotPath));

    fixture.panel->resize(900, 600);
    QCoreApplication::processEvents();
    QImage wide(fixture.panel->size(), QImage::Format_ARGB32_Premultiplied);
    wide.fill(Qt::white);
    fixture.panel->render(&wide);
    QVERIFY(!wide.isNull());
    if (!m_screenshotPath.isEmpty())
        QVERIFY(wide.save(derivedScreenshotPath(m_screenshotPath, QStringLiteral("-wide"))));

    fixture.panel->resize(380, 240);
    QCoreApplication::processEvents();
    QImage shortImage(fixture.panel->size(), QImage::Format_ARGB32_Premultiplied);
    shortImage.fill(Qt::white);
    fixture.panel->render(&shortImage);
    QVERIFY(!shortImage.isNull());
    if (!m_screenshotPath.isEmpty())
        QVERIFY(shortImage.save(derivedScreenshotPath(m_screenshotPath, QStringLiteral("-short"))));
}

} // namespace checks
