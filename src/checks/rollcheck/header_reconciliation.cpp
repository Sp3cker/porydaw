#include "checks/rollcheck/tst_pianoroll.h"

#include <QtTest>

#include <QAbstractItemModel>
#include <QCoreApplication>
#include <QPointer>
#include <algorithm>
#include <memory>
#include <optional>

#include "checks/quickpopupguard.h"
#include "checks/rollcheck/headerchecksupport.h"
#include "checks/support/songfixture.h"
#include "core/songdocument.h"
#include "ui/songview.h"

namespace {
using checks::rollcheck::headercheck::addTrackRow;
using checks::rollcheck::headercheck::model;
using checks::rollcheck::headercheck::ModelChanges;
using checks::rollcheck::headercheck::recordsMatchTimeline;
using checks::rollcheck::headercheck::rowForTrack;
using checks::rollcheck::headercheck::titlePoint;

struct HeaderFixture {
    SongDocument document;
    std::unique_ptr<MidiTimeline> timeline;
    SongView view;
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
        view.resize(800, 480);
        view.setSong(timeline.get(), nullptr);
        view.setDocument(&document);
        (void)view.grab(); // realizes the attached Quick input
        headers = model(view);
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
        const std::optional<int> add = addTrackRow(*headers);
        return firstUsed >= 0 && firstUsed != lastUsed && rowForTrack(*headers, firstUsed) &&
               rowForTrack(*headers, lastUsed) && add && *add == headers->rowCount() - 1;
    }
};
} // namespace

void PianoRollTest::headerContextMenu()
{
    SongView &view = m_fixture->view();
    auto *headers = model(view);
    auto *input = checks::rollcheck::headercheck::input(view);
    const int originalTrack = view.selectionModel().primaryTrack();
    if (!headers || !input) {
        QFAIL("Quick track-header model or input was not found");
    }

    int menuTrack = -1;
    int menuRow = -1;
    for (int row = 0; row < headers->rowCount(); ++row) {
        const QModelIndex index = headers->index(row, 0);
        if (headers->data(index, songview::TrackHeaderModel::IsAddTrackRole).toBool())
            continue;
        const int track = headers->data(index, songview::TrackHeaderModel::TrackRole).toInt();
        if (track != originalTrack) {
            menuTrack = track;
            menuRow = row;
            break;
        }
    }
    if (menuRow < 0)
        QFAIL("context-menu fixture lacks a secondary track header");

    const quick_popup::PromptGuard guard(view);
    const QPointer<songview::QuickPopupSession> session{quick_popup::popupSession(view)};
    if (!session || !session->window())
        QFAIL("the Quick track-header canvas has no popup session");
    const auto awaitMenu = [&session] {
        return QTest::qWaitFor([&session] {
            return session && session->isOpen() && quick_popup::menuPanel(*session) &&
                   quick_popup::menuModel(*quick_popup::menuPanel(*session)) != nullptr;
        });
    };

    const QPointF title = titlePoint(*headers, *input, menuRow);
    QTest::mouseClick(session->window(), Qt::RightButton, Qt::NoModifier,
                      input->mapToScene(title).toPoint());
    if (!awaitMenu())
        QFAIL("the header right-press did not open the shared Quick menu");
    if (view.selectionModel().primaryTrack() != menuTrack)
        QFAIL("right press did not select its track");

    using HeaderMenuAction = songview::TrackHeaderModel::HeaderMenuAction;
    QTest::keyClick(session->window(), Qt::Key_Escape);
    QCoreApplication::processEvents();
    if (session->isOpen())
        QFAIL("Escape did not dismiss the header menu");

    // Duplicate stays disabled once the document sits at track capacity; a
    // real click on the disabled row neither dispatches nor dismisses.
    SongDocument &doc = m_fixture->document();
    while (doc.canAddTrack()) {
        if (doc.duplicateTrack(0) < 0)
            QFAIL("capacity fixture could not fill the track slots");
    }
    QCoreApplication::processEvents();
    if (!QTest::qWaitFor([&] { return headers->rowCount() == doc.engineTrackCount(); }))
        QFAIL("capacity fixture header records did not settle after the fill");
    headers->setScrollY(qreal(menuRow * headers->rowHeight()));
    const QPointF capacityTitle = titlePoint(*headers, *input, menuRow);
    QTest::mouseClick(session->window(), Qt::RightButton, Qt::NoModifier,
                      input->mapToScene(capacityTitle).toPoint());
    if (!awaitMenu())
        QFAIL("the header right-press at capacity did not open the shared Quick menu");
    songview::QuickMenuModel *const capacityMenu =
        quick_popup::menuModel(*quick_popup::menuPanel(*session));
    const int duplicateRow =
        capacityMenu->rowForId(static_cast<int>(HeaderMenuAction::DuplicateTrack));
    if (duplicateRow < 0 || !capacityMenu->itemAt(duplicateRow) ||
        capacityMenu->itemAt(duplicateRow)->enabled) {
        QFAIL("Duplicate track stayed enabled at track capacity");
    }
    const QByteArray capacityBytes = doc.smf().write();
    const int capacityUndo = doc.undoStack()->index();
    if (!quick_popup::clickMenuRow(*session, duplicateRow))
        QFAIL("the disabled Duplicate row did not receive a real click");
    QCoreApplication::processEvents();
    if (!session->isOpen())
        QFAIL("a click on the disabled Duplicate row dismissed the menu");
    if (doc.undoStack()->index() != capacityUndo || doc.smf().write() != capacityBytes)
        QFAIL("a disabled Duplicate row mutated the document");
    QTest::keyClick(session->window(), Qt::Key_Escape);
    QCoreApplication::processEvents();
    if (session->isOpen())
        QFAIL("Escape did not dismiss the header menu at capacity");
    view.selectTrack(originalTrack);
}

void PianoRollTest::headerReconciliationUnchanged()
{
    QString error;
    const std::unique_ptr<checks::LoadedSong> source =
        checks::LoadedSong::load(m_project->root(), m_songLabel, error);
    QVERIFY2(source, qPrintable(error));

    HeaderFixture fixture;
    if (!fixture.prepare(source->songInfo(), &error)) {
        QFAIL(fixture.documentLoaded ? "header reconciliation fixture lacks TrackHeaderModel"
                                     : "could not load header reconciliation fixture");
    }
    if (!fixture.hasOrderedRecords())
        QFAIL("header reconciliation fixture lacks ordered records and a last add record");

    const std::optional<int> addBefore = addTrackRow(*fixture.headers);
    ModelChanges changes;
    QObject::connect(fixture.headers, &QAbstractItemModel::modelReset, &fixture.view,
                     [&changes] { ++changes.resets; });
    fixture.view.setSong(fixture.timeline.get(), nullptr);
    if (changes.resets != 0 ||
        !recordsMatchTimeline(*fixture.headers, *fixture.timeline,
                              fixture.document.canAddTrack()) ||
        addTrackRow(*fixture.headers) != addBefore) {
        QFAIL("unchanged song reset or reordered TrackHeaderModel records");
    }
}

void PianoRollTest::headerReconciliationMute()
{
    QString error;
    const std::unique_ptr<checks::LoadedSong> source =
        checks::LoadedSong::load(m_project->root(), m_songLabel, error);
    QVERIFY2(source, qPrintable(error));

    HeaderFixture fixture;
    if (!fixture.prepare(source->songInfo(), &error)) {
        QFAIL(fixture.documentLoaded ? "header reconciliation fixture lacks TrackHeaderModel"
                                     : "could not load header reconciliation fixture");
    }
    if (!fixture.hasOrderedRecords())
        QFAIL("header reconciliation fixture lacks ordered records and a last add record");

    ModelChanges changes;
    QObject::connect(fixture.headers, &QAbstractItemModel::modelReset, &fixture.view,
                     [&changes] { ++changes.resets; });
    QObject::connect(fixture.headers, &QAbstractItemModel::dataChanged, &fixture.view,
                     [&changes](const QModelIndex &topLeft, const QModelIndex &bottomRight,
                                const QList<int> &roles) {
                         changes.data.push_back({topLeft.row(), bottomRight.row(), roles});
                     });
    fixture.view.setTrackMute(fixture.firstUsed, false);
    changes.clear();
    fixture.view.setTrackMute(fixture.firstUsed, true);
    const std::optional<int> mutedRow = rowForTrack(*fixture.headers, fixture.firstUsed);
    const bool boundedMuteChange =
        changes.resets == 0 && mutedRow && !changes.data.empty() &&
        std::all_of(changes.data.cbegin(), changes.data.cend(),
                    [mutedRow](const checks::rollcheck::headercheck::ModelChange &change) {
                        return change.firstRow == *mutedRow && change.lastRow == *mutedRow;
                    }) &&
        checks::rollcheck::headercheck::includesRole(changes.data, *mutedRow,
                                                     songview::TrackHeaderModel::MuteCheckedRole) &&
        fixture.headers
            ->data(fixture.headers->index(*mutedRow, 0),
                   songview::TrackHeaderModel::MuteCheckedRole)
            .toBool();
    if (!boundedMuteChange)
        QFAIL("mask-only header update was not bounded mute-role coverage");
}

void PianoRollTest::headerReconciliationStructural()
{
    QString error;
    const std::unique_ptr<checks::LoadedSong> source =
        checks::LoadedSong::load(m_project->root(), m_songLabel, error);
    QVERIFY2(source, qPrintable(error));

    HeaderFixture fixture;
    if (!fixture.prepare(source->songInfo(), &error)) {
        QFAIL(fixture.documentLoaded ? "header reconciliation fixture lacks TrackHeaderModel"
                                     : "could not load header reconciliation fixture");
    }
    if (!fixture.hasOrderedRecords())
        QFAIL("header reconciliation fixture lacks ordered records and a last add record");

    ModelChanges changes;
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
        !recordsMatchTimeline(*fixture.headers, *replacement, fixture.document.canAddTrack()) ||
        rowForTrack(*fixture.headers, fixture.lastUsed)) {
        QFAIL("structural header replacement did not reset to the replacement records");
    }

    fixture.document.undoStack()->undo();
    fixture.timeline = fixture.document.buildTimeline(48000.0);
    changes.clear();
    fixture.view.setSong(fixture.timeline.get(), nullptr);
    const std::optional<int> restoredAdd = addTrackRow(*fixture.headers);
    if (changes.resets != 1 ||
        !recordsMatchTimeline(*fixture.headers, *fixture.timeline,
                              fixture.document.canAddTrack()) ||
        !rowForTrack(*fixture.headers, fixture.lastUsed) || !restoredAdd ||
        *restoredAdd != fixture.headers->rowCount() - 1) {
        QFAIL("re-added track did not restore ordered model records and last add row");
    }
}

void PianoRollTest::headerRenameCancellation()
{
    QString error;
    const std::unique_ptr<checks::LoadedSong> source =
        checks::LoadedSong::load(m_project->root(), m_songLabel, error);
    QVERIFY2(source, qPrintable(error));

    HeaderFixture fixture;
    if (!fixture.prepare(source->songInfo(), &error)) {
        QFAIL(fixture.documentLoaded ? "header reconciliation fixture lacks TrackHeaderModel"
                                     : "could not load header reconciliation fixture");
    }
    if (!fixture.hasOrderedRecords())
        QFAIL("header reconciliation fixture lacks ordered records and a last add record");

    ModelChanges changes;
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
        !recordsMatchTimeline(*fixture.headers, *replacement, fixture.document.canAddTrack()) ||
        rowForTrack(*fixture.headers, fixture.lastUsed)) {
        QFAIL("structural header replacement did not reset to the replacement records");
    }

    fixture.document.undoStack()->undo();
    fixture.timeline = fixture.document.buildTimeline(48000.0);
    changes.clear();
    fixture.view.setSong(fixture.timeline.get(), nullptr);
    const std::optional<int> restoredAdd = addTrackRow(*fixture.headers);
    if (changes.resets != 1 ||
        !recordsMatchTimeline(*fixture.headers, *fixture.timeline,
                              fixture.document.canAddTrack()) ||
        !rowForTrack(*fixture.headers, fixture.lastUsed) || !restoredAdd ||
        *restoredAdd != fixture.headers->rowCount() - 1) {
        QFAIL("re-added track did not restore ordered model records and last add row");
    }

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
