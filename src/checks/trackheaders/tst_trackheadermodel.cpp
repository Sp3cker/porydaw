#include "checks/trackheaders/tst_trackheaders.h"

#include <QtTest>

#include <QAbstractItemModel>
#include <QCoreApplication>
#include <QModelIndex>
#include <QPointF>
#include <QSize>
#include <cstdint>
#include <memory>
#include <optional>
#include <utility>

#include "checks/support/editorrig.h"
#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"
#include "checks/trackheaders/trackheaderoracles.h"
#include "core/miditimeline.h"
#include "core/songdocument.h"
#include "ui/activity/trackactivity.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/trackheadermodel.h"

namespace {

using checks::events::pointerInput;

class TrackHeaderModelTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(TrackHeaderModelTest)

  public:
    TrackHeaderModelTest(QString projectRoot, QString songLabel)
        : m_projectRoot(std::move(projectRoot))
        , m_songLabel(std::move(songLabel))
    {}

  private slots:
    void unattachedModelPublishesSafeZeroGeometry()
    {
        TrackHeadersFixture fixture(m_projectRoot, m_songLabel);
        QString error;
        QVERIFY2(fixture.create(error), qPrintable(error));

        TrackActivity activity;
        songview::TrackHeaderModel model(fixture.view());
        model.rebuild(activity, false);

        QCOMPARE(model.viewportHeight(), 0.0);
        QCOMPARE(model.maximumScrollY(), 0.0);
        QCOMPARE(model.rowCount(),
                 int(fixture.tracks().size()) + int(fixture.tab().document().canAddTrack()));
        for (int row = 0; row < model.rowCount(); ++row) {
            const QModelIndex index = model.index(row, 0);
            if (model.data(index, songview::TrackHeaderModel::IsAddTrackRole).toBool())
                continue;
            QCOMPARE(model.data(index, songview::TrackHeaderModel::ActivityLeftHeightRole).toReal(),
                     0.0);
            QCOMPARE(
                model.data(index, songview::TrackHeaderModel::ActivityRightHeightRole).toReal(),
                0.0);
        }
    }

    void reorderSlotsResolveInsertionTargetsAndUndoRestores()
    {
        TrackHeadersFixture fixture(m_projectRoot, m_songLabel);
        QString error;
        QVERIFY2(fixture.create(error), qPrintable(error));

        songview::TrackHeaderModel &headers = fixture.headers();
        SongDocument &doc = fixture.tab().document();

        // Three-row insertion-slot arithmetic on a duplicated third track:
        // dropping inside a target row's top quarter inserts above it, the
        // bottom three quarters insert below it, and the adjacent slot leaves
        // the row in place. Every probe undoes back to the duplicated baseline.
        const int baselineUndo = doc.undoStack()->index();
        const int duplicatedTrack = doc.duplicateTrack(fixture.sourceTrack());
        QVERIFY2(duplicatedTrack >= 0, "could not create the third track for slot arithmetic");
        QCoreApplication::processEvents();
        checks::support::pumpQuick();
        QTRY_COMPARE(doc.engineTrackCount(), int(fixture.tracks().size()) + 1);
        const int fixtureTracks[] = {fixture.tracks().front(), fixture.tracks()[1],
                                     duplicatedTrack};
        const uint8_t identities[] = {doc.channelFor(fixtureTracks[0]),
                                      doc.channelFor(fixtureTracks[1]),
                                      doc.channelFor(fixtureTracks[2])};
        QVERIFY2(identities[0] != identities[1] && identities[0] != identities[2] &&
                     identities[1] != identities[2],
                 "the three-track slot fixture channels are not distinct");
        const auto hasTrackOrder = [&](int first, int second, int third) {
            return doc.channelFor(fixtureTracks[0]) == identities[first] &&
                   doc.channelFor(fixtureTracks[1]) == identities[second] &&
                   doc.channelFor(fixtureTracks[2]) == identities[third];
        };
        const auto dragToSlot = [&](int fromTrack, int slot) {
            const int targetTrack = fixtureTracks[slot < 3 ? slot : 2];
            const std::optional<int> sourceRow = fixture.rowForTrack(fromTrack);
            const std::optional<int> targetRow = fixture.rowForTrack(targetTrack);
            QVERIFY(sourceRow && targetRow);
            const qreal scroll = qreal(*sourceRow * fixture.rowHeight());
            headers.setScrollY(scroll);
            checks::support::pumpQuick();
            const std::optional<QPointF> start = fixture.titlePoint(*sourceRow);
            QVERIFY(start);
            const QPointF drop{headers.voiceLineRect().center().x(),
                               qreal(*targetRow) * fixture.rowHeight() +
                                   fixture.rowHeight() * (slot < 3 ? 0.25 : 0.75) - scroll};
            QVERIFY(headers.pointerPress(
                pointerInput(fixture.input(), *start, Qt::LeftButton, Qt::LeftButton)));
            QVERIFY(headers.pointerMove(
                pointerInput(fixture.input(), drop, Qt::NoButton, Qt::LeftButton)));
            QVERIFY(headers.pointerRelease(
                pointerInput(fixture.input(), drop, Qt::LeftButton, Qt::NoButton)));
            QCoreApplication::processEvents();
        };

        fixture.view().setTrackMute(fixtureTracks[0], false);
        fixture.view().setTrackMute(fixtureTracks[1], false);
        fixture.view().setTrackMute(duplicatedTrack, true);
        const int upwardIndex = doc.undoStack()->index();
        dragToSlot(duplicatedTrack, 0);
        QCOMPARE(doc.undoStack()->index(), upwardIndex + 1);
        QVERIFY(hasTrackOrder(2, 0, 1));
        QVERIFY(fixture.view().trackMuted(fixtureTracks[0]));
        QVERIFY(!fixture.view().trackMuted(fixtureTracks[1]));
        QVERIFY(!fixture.view().trackMuted(fixtureTracks[2]));
        doc.undoStack()->setIndex(upwardIndex);
        QVERIFY(hasTrackOrder(0, 1, 2));
        QVERIFY(!fixture.view().trackMuted(fixtureTracks[0]));
        QVERIFY(!fixture.view().trackMuted(fixtureTracks[1]));
        QVERIFY(fixture.view().trackMuted(fixtureTracks[2]));
        fixture.view().setTrackMute(duplicatedTrack, false);

        fixture.view().setTrackMute(fixtureTracks[0], true);
        const int downwardIndex = doc.undoStack()->index();
        dragToSlot(fixtureTracks[0], 3);
        QCOMPARE(doc.undoStack()->index(), downwardIndex + 1);
        QVERIFY(hasTrackOrder(1, 2, 0));
        QVERIFY(!fixture.view().trackMuted(fixtureTracks[0]));
        QVERIFY(!fixture.view().trackMuted(fixtureTracks[1]));
        QVERIFY(fixture.view().trackMuted(fixtureTracks[2]));
        doc.undoStack()->setIndex(downwardIndex);
        QVERIFY(hasTrackOrder(0, 1, 2));
        QVERIFY(fixture.view().trackMuted(fixtureTracks[0]));
        QVERIFY(!fixture.view().trackMuted(fixtureTracks[1]));
        QVERIFY(!fixture.view().trackMuted(fixtureTracks[2]));
        fixture.view().setTrackMute(fixtureTracks[0], false);

        fixture.view().setTrackMute(fixtureTracks[1], true);
        const int adjacentIndex = doc.undoStack()->index();
        dragToSlot(fixtureTracks[1], 2);
        QCOMPARE(doc.undoStack()->index(), adjacentIndex);
        QVERIFY(hasTrackOrder(0, 1, 2));
        QVERIFY(!fixture.view().trackMuted(fixtureTracks[0]));
        QVERIFY(fixture.view().trackMuted(fixtureTracks[1]));
        QVERIFY(!fixture.view().trackMuted(fixtureTracks[2]));
        doc.undoStack()->setIndex(adjacentIndex);
        fixture.view().setTrackMute(fixtureTracks[1], false);

        // Every probe returned to the duplicated baseline; undoing the
        // duplicate restores the fixture's original track set.
        doc.undoStack()->setIndex(baselineUndo);
        QTRY_COMPARE(doc.engineTrackCount(), int(fixture.tracks().size()));
        checks::support::pumpQuick();
    }

    void headerReconciliationUnchanged()
    {
        QString error;
        const std::unique_ptr<checks::LoadedSong> source =
            checks::LoadedSong::load(m_projectRoot, m_songLabel, error);
        QVERIFY2(source, qPrintable(error));

        HeaderFixture fixture;
        if (!fixture.prepare(source->songInfo(), &error)) {
            QFAIL(fixture.documentLoaded ? "header reconciliation fixture lacks TrackHeaderModel"
                                         : "could not load header reconciliation fixture");
        }
        if (!fixture.hasOrderedRecords())
            QFAIL("header reconciliation fixture lacks ordered records and a last add record");

        const std::optional<int> addBefore = trackheaders_test::addTrackRow(*fixture.headers);
        trackheaders_test::ModelChanges changes;
        QObject::connect(fixture.headers, &QAbstractItemModel::modelReset, &fixture.view,
                         [&changes] { ++changes.resets; });
        fixture.view.setSong(fixture.timeline.get(), nullptr);
        if (changes.resets != 0 ||
            !trackheaders_test::recordsMatchTimeline(*fixture.headers, *fixture.timeline,
                                                     fixture.document.canAddTrack()) ||
            trackheaders_test::addTrackRow(*fixture.headers) != addBefore) {
            QFAIL("unchanged song reset or reordered TrackHeaderModel records");
        }
    }

    void headerReconciliationStructural()
    {
        QString error;
        const std::unique_ptr<checks::LoadedSong> source =
            checks::LoadedSong::load(m_projectRoot, m_songLabel, error);
        QVERIFY2(source, qPrintable(error));

        HeaderFixture fixture;
        if (!fixture.prepare(source->songInfo(), &error)) {
            QFAIL(fixture.documentLoaded ? "header reconciliation fixture lacks TrackHeaderModel"
                                         : "could not load header reconciliation fixture");
        }
        if (!fixture.hasOrderedRecords())
            QFAIL("header reconciliation fixture lacks ordered records and a last add record");

        trackheaders_test::ModelChanges changes;
        QObject::connect(fixture.headers, &QAbstractItemModel::modelReset, &fixture.view,
                         [&changes] { ++changes.resets; });
        fixture.document.deleteTrack(fixture.lastUsed);
        std::unique_ptr<MidiTimeline> replacement = fixture.document.buildTimeline(48000.0);
        if (replacement->tracks[fixture.lastUsed].used ||
            !replacement->tracks[fixture.firstUsed].used) {
            QFAIL("replacement fixture did not drop exactly the last used slot");
        }

        changes.clear();
        fixture.view.setSong(replacement.get(), nullptr);
        if (changes.resets != 1 ||
            !trackheaders_test::recordsMatchTimeline(*fixture.headers, *replacement,
                                                     fixture.document.canAddTrack()) ||
            trackheaders_test::rowForTrack(*fixture.headers, fixture.lastUsed)) {
            QFAIL("structural header replacement did not reset to the replacement records");
        }

        fixture.document.undoStack()->undo();
        fixture.timeline = fixture.document.buildTimeline(48000.0);
        changes.clear();
        fixture.view.setSong(fixture.timeline.get(), nullptr);
        const std::optional<int> restoredAdd = trackheaders_test::addTrackRow(*fixture.headers);
        if (changes.resets != 1 ||
            !trackheaders_test::recordsMatchTimeline(*fixture.headers, *fixture.timeline,
                                                     fixture.document.canAddTrack()) ||
            !trackheaders_test::rowForTrack(*fixture.headers, fixture.lastUsed) || !restoredAdd ||
            *restoredAdd != fixture.headers->rowCount() - 1) {
            QFAIL("re-added track did not restore ordered model records and last add row");
        }
        // An open rename state does not survive a structural song replacement:
        // the reset cancels it without committing the draft.
        fixture.view.renameTrack(fixture.firstUsed);
        if (fixture.headers->renamingTrack() != fixture.firstUsed)
            QFAIL("rename state did not open on a live TrackHeaderModel record");

        fixture.headers->setRenameDraft(QStringLiteral("zzz"));
        changes.clear();
        fixture.view.setSong(replacement.get(), nullptr);
        QCoreApplication::processEvents();
        if (changes.resets != 1 || fixture.headers->renamingTrack() != -1)
            QFAIL("song replacement did not cancel the open header rename state");
        if (fixture.document.trackName(fixture.firstUsed) == QStringLiteral("zzz"))
            QFAIL("cancelled rename committed across song replacement");
    }

  private:
    struct HeaderFixture {
        SongDocument document;
        std::unique_ptr<MidiTimeline> timeline;
        SongView view;
        // Declared after the view so the host detaches and dies before the
        // borrowed SongView.
        std::unique_ptr<checks::QuickSceneHost> host;
        songview::TrackHeaderModel *headers = nullptr;
        int firstUsed = -1;
        bool documentLoaded = false;
        int lastUsed = -1;

        bool prepare(const SongInfo &song, QString *error)
        {
            if (!document.load(song, error))
                return false;
            documentLoaded = true;
            timeline = document.buildTimeline(48000.0);
            host = std::make_unique<checks::QuickSceneHost>(view, QSize(800, 480));
            if (!checks::support::showQuickViewport(view, QSize(800, 480)))
                return false;
            view.setSong(timeline.get(), nullptr);
            view.setDocument(&document);
            headers =
                view.findChild<songview::TrackHeaderModel *>(QStringLiteral("trackHeaderModel"));
            if (!headers)
                return false;
            for (int track = 0; track < 16; ++track) {
                if (!timeline->tracks[track].used)
                    continue;
                if (firstUsed < 0)
                    firstUsed = track;
                lastUsed = track;
            }
            return true;
        }

        bool hasOrderedRecords() const
        {
            const std::optional<int> add = trackheaders_test::addTrackRow(*headers);
            return firstUsed >= 0 && firstUsed != lastUsed &&
                   trackheaders_test::rowForTrack(*headers, firstUsed) &&
                   trackheaders_test::rowForTrack(*headers, lastUsed) && add &&
                   *add == headers->rowCount() - 1;
        }
    };

    QString m_projectRoot;
    QString m_songLabel;
};

} // namespace

int runTrackHeaderModelCheck(const QString &projectRoot, const QString &songLabel,
                             const QStringList &qtArguments)
{
    TrackHeaderModelTest test(projectRoot, songLabel);
    QStringList arguments{QStringLiteral("trackheader-model")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "tst_trackheadermodel.moc"
