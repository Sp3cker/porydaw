#include <QtTest>

#include <memory>
#include <utility>
#include <vector>

#include "checks/support/songfixture.h"
#include "core/songdocument.h"
#include "document_feed_check.h"
#include "ui/songview/quick/swiftgrid/swift_grid_document_feed.h"

namespace {

struct Capture {
    int deliveries = 0;
    SgdDocumentHeader header{};
    std::vector<SgdNote> notes;
    std::vector<SgdTimeSignature> signatures;

    static void receive(const SgdDocumentHeader *incomingHeader, const SgdNote *incomingNotes,
                        const SgdTimeSignature *incomingSignatures, void *context)
    {
        auto &capture = *static_cast<Capture *>(context);
        ++capture.deliveries;
        capture.header = *incomingHeader;
        capture.notes.clear();
        capture.signatures.clear();
        if (incomingHeader->noteCount)
            capture.notes.assign(incomingNotes, incomingNotes + incomingHeader->noteCount);
        if (incomingHeader->timeSignatureCount)
            capture.signatures.assign(incomingSignatures,
                                      incomingSignatures + incomingHeader->timeSignatureCount);
    }
};

void compareDocument(const Capture &capture, const SongDocument &document, uint64_t token)
{
    QCOMPARE(capture.header.documentId, token);
    QCOMPARE(capture.header.revision, document.revision());
    QCOMPARE(capture.header.ticksPerBeat, int32_t(document.smf().division));
    QCOMPARE(capture.header.trackCount, document.engineTrackCount());
    size_t index = 0;
    for (int track = 0; track < document.engineTrackCount(); ++track) {
        for (const DocNote &note : document.notesForTrack(track)) {
            QVERIFY(index < capture.notes.size());
            const SgdNote &actual = capture.notes[index++];
            QCOMPARE(actual.trackIndex, track);
            QCOMPARE(actual.key, int32_t(note.key));
            QCOMPARE(actual.onTick, note.tick);
            QCOMPARE(actual.durationTicks, note.duration);
            QCOMPARE(actual.velocity, int32_t(note.velocity));
        }
    }
    QCOMPARE(capture.notes.size(), index);
    QCOMPARE(capture.header.noteCount, int32_t(index));
    const auto signatures = document.timeSigs();
    QCOMPARE(capture.signatures.size(), signatures.size());
    QCOMPARE(capture.header.timeSignatureCount, int32_t(signatures.size()));
    for (size_t i = 0; i < signatures.size(); ++i) {
        QCOMPARE(capture.signatures[i].startTick, signatures[i].tick);
        QCOMPARE(capture.signatures[i].numerator, signatures[i].numerator);
        QCOMPARE(capture.signatures[i].denomPow2, signatures[i].denomPow2);
    }
}

class SwiftDocFeedTest final : public QObject
{
    Q_OBJECT

  public:
    SwiftDocFeedTest(QString projectRoot, QString songLabel)
        : m_projectRoot(std::move(projectRoot))
        , m_songLabel(std::move(songLabel))
    {}

  private slots:
    void fixtureMutationHistoryAndTeardown()
    {
        QString error;
        auto song = checks::LoadedSong::load(m_projectRoot, m_songLabel, error);
        QVERIFY2(song, qPrintable(error));
        auto otherSong = checks::LoadedSong::load(m_projectRoot, m_songLabel, error);
        QVERIFY2(otherSong, qPrintable(error));
        SongDocument &document = song->document();
        QSignalSpy emissions(&document, &SongDocument::documentChanged);
        auto capture = std::make_unique<Capture>();
        Capture otherCapture;
        auto feed = std::make_unique<SwiftGridDocumentFeed>(document);
        SwiftGridDocumentFeed otherFeed(otherSong->document());
        const uint64_t token = feed->documentId();
        QVERIFY(token != 0);
        QVERIFY(otherFeed.documentId() != token);
        QVERIFY(!sgd_set_delivery(0, Capture::receive, capture.get()));
        QVERIFY(!sgd_set_delivery(token, nullptr, capture.get()));
        QVERIFY(!sgd_set_delivery(token, Capture::receive, nullptr));
        QVERIFY(sgd_set_delivery(token, Capture::receive, capture.get()));
        QVERIFY(sgd_set_delivery(otherFeed.documentId(), Capture::receive, &otherCapture));
        QVERIFY(!sgd_set_delivery(token, Capture::receive, &otherCapture));
        QCOMPARE(capture->deliveries, 0);
        feed->pushSnapshot();
        otherFeed.pushSnapshot();
        QCOMPARE(capture->deliveries, 1);
        QCOMPARE(otherCapture.deliveries, 1);
        compareDocument(*capture, document, token);
        compareDocument(otherCapture, otherSong->document(), otherFeed.documentId());

        const auto notes = document.notesForTrack(0);
        QVERIFY(!notes.empty());
        const DocNote note = notes.front();
        const uint8_t velocity = note.velocity == 99 ? 100 : 99;
        const uint64_t revision = document.revision();
        document.setNotesVelocity({note}, velocity);
        QCOMPARE(emissions.count(), 1);
        QCOMPARE(capture->deliveries, 2);
        QCOMPARE(document.revision(), revision + 1);
        compareDocument(*capture, document, token);
        QCOMPARE(otherCapture.deliveries, 1);
        document.undoStack()->undo();
        QCOMPARE(emissions.count(), 2);
        QCOMPARE(capture->deliveries, 3);
        QCOMPARE(document.revision(), revision + 2);
        compareDocument(*capture, document, token);
        document.undoStack()->redo();
        QCOMPARE(emissions.count(), 3);
        QCOMPARE(capture->deliveries, 4);
        QCOMPARE(document.revision(), revision + 3);
        compareDocument(*capture, document, token);

        sgd_clear_delivery(token);
        QVERIFY(feed->delivery()->fn == nullptr);
        QVERIFY(feed->delivery()->context == nullptr);
        document.undoStack()->undo();
        QCOMPARE(capture->deliveries, 4);
        QVERIFY(sgd_set_delivery(token, Capture::receive, capture.get()));
        feed.reset();
        QVERIFY(!sgd_set_delivery(token, Capture::receive, capture.get()));
        document.undoStack()->redo();
        QCOMPARE(capture->deliveries, 4);
        capture.reset();
        document.undoStack()->undo(); // Must not touch the released callback context.
        sgd_clear_delivery(token);
        sgd_unregister_feed(token);

        Capture remountCapture;
        SwiftGridDocumentFeed remount(document);
        QVERIFY(remount.documentId() != token);
        QVERIFY(remount.documentId() != otherFeed.documentId());
        QVERIFY(sgd_set_delivery(remount.documentId(), Capture::receive, &remountCapture));
        remount.pushSnapshot();
        compareDocument(remountCapture, document, remount.documentId());
        QCOMPARE(otherCapture.deliveries, 1);
        sgd_clear_delivery(remount.documentId());
        sgd_clear_delivery(otherFeed.documentId());
    }

    void unsignedTicksAndRawSignaturePrecedence()
    {
        SmfFile smf;
        smf.division = 960;
        smf.tracks.resize(3);
        SmfEvent signature;
        signature.status = 0xff;
        signature.metaType = 0x58;
        signature.blob = QByteArray::fromHex("07031808");
        smf.tracks[0].events.push_back(signature);
        signature.blob = QByteArray::fromHex("051f1808");
        smf.tracks[0].events.push_back(signature);
        signature.blob = QByteArray::fromHex("00ff1808");
        smf.tracks[1].events.push_back(signature);
        SmfEvent on;
        on.status = 0x90;
        on.data0 = 64;
        on.data1 = 81;
        on.tick = 0x80000010U;
        SmfEvent off = on;
        off.status = 0x80;
        off.tick += 32;
        smf.tracks[1].events.push_back(on);
        smf.tracks[1].events.push_back(off);
        smf.tracks[1].endTick = off.tick;
        on.status = 0x91;
        on.data0 = 72;
        off.status = 0x81;
        off.data0 = 72;
        smf.tracks[2].events = {on, off};
        smf.tracks[2].endTick = off.tick;
        SongDocument document;
        QString error;
        QVERIFY2(document.adoptSmf(std::move(smf), SongInfo{}, &error), qPrintable(error));
        Capture capture;
        SwiftGridDocumentFeed feed(document);
        QVERIFY(sgd_set_delivery(feed.documentId(), Capture::receive, &capture));
        feed.pushSnapshot();
        compareDocument(capture, document, feed.documentId());
        QCOMPARE(capture.header.trackCount, 2);
        QCOMPARE(capture.header.ticksPerBeat, 960);
        QCOMPARE(capture.notes.size(), size_t(2));
        QCOMPARE(capture.notes[0].trackIndex, 0);
        QCOMPARE(capture.notes[1].trackIndex, 1);
        QCOMPARE(capture.notes[0].onTick, uint32_t(0x80000010U));
        QCOMPARE(capture.notes[0].durationTicks, uint32_t(32));
        QCOMPARE(capture.signatures.size(), size_t(3));
        QCOMPARE(capture.signatures[0].numerator, uint8_t(7));
        QCOMPARE(capture.signatures[1].denomPow2, uint8_t(31));
        QCOMPARE(capture.signatures[2].numerator, uint8_t(0));
        QCOMPARE(capture.signatures[2].denomPow2, uint8_t(255));
    }

    void actualSwiftReceiverGuard() { QCOMPARE(sgd_check_swift_guard(), int32_t(0)); }

  private:
    QString m_projectRoot;
    QString m_songLabel;
};

} // namespace

int runSwiftDocFeedCheck(const QString &projectRoot, const QString &songLabel,
                         const QStringList &qtArguments)
{
    SwiftDocFeedTest test(projectRoot, songLabel);
    QStringList arguments{QStringLiteral("swiftdocfeed")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "tst_swiftdocfeed.moc"
