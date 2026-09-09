#include "checks/workspace/tst_workspacesessions.h"

#include <QtTest>

#include <QAbstractItemModelTester>
#include <QSignalSpy>

#include <algorithm>
#include <memory>
#include <optional>
#include <utility>
#include <vector>

#include "core/smf.h"
#include "project/decompproject.h"
#include "project/projectidentity.h"
#include "ui/songtab.h"
#include "ui/workspacequick/songtabsmodel.h"

namespace {

constexpr double kTabSampleRate = 48000.0;

std::optional<SongInfo> playableSongInfo(const DecompProject &project, const QString &label)
{
    for (const SongInfo &song : project.songs()) {
        if (song.label == label && song.isPlayable())
            return song;
    }
    return std::nullopt;
}

// Stages the workspace's MidiStage delivery onto a bare tab the way the
// project worker publishes it: the document label, mid path, and paired
// timeline all become real before the model projects them.
bool stageMidi(SongTab &tab, const SongInfo &song, int trackBudget, QString &error)
{
    SmfFile smf;
    if (!SmfFile::readFile(song.midPath, &smf, &error))
        return false;
    tab.setSampleRate(kTabSampleRate);
    tab.applyMidiStage(song, std::move(smf), trackBudget);
    error.clear();
    return true;
}

std::optional<VoicegroupId> songVoicegroup(const SongInfo &song)
{
    return VoicegroupId::create(
        QStringLiteral("sound/songs/midi/") + song.label + QStringLiteral(".s"), QString());
}

// Builds a tab staged to terminal readiness, mirroring the workspace's
// MidiStage + VoicegroupBound delivery so the model's ready projection
// rests on the real readiness signal.
std::unique_ptr<SongTab> readyTab(const SongInfo &song, int trackBudget, QString &error)
{
    error.clear();
    const std::optional<SongName> name = SongName::create(song.label);
    if (!name) {
        error = QStringLiteral("invalid song label: %1").arg(song.label);
        return nullptr;
    }
    auto page = std::make_unique<SongTab>(*name);
    if (!stageMidi(*page, song, trackBudget, error))
        return nullptr;
    const std::optional<VoicegroupId> voicegroup = songVoicegroup(song);
    if (!voicegroup) {
        error = QStringLiteral("invalid voicegroup identity for %1").arg(song.label);
        return nullptr;
    }
    page->applyVoicegroupBound(*voicegroup);
    return page;
}

std::unique_ptr<SongTab> bareTab(const QString &label, QString &error)
{
    error.clear();
    const std::optional<SongName> name = SongName::create(label);
    if (!name) {
        error = QStringLiteral("invalid song label: %1").arg(label);
        return nullptr;
    }
    return std::make_unique<SongTab>(*name);
}

} // namespace

void WorkspaceTabsTest::tabModelRemovalKeepsSelection()
{
    DecompProject project;
    QString error;
    QVERIFY2(project.open(m_project.root(), &error), qPrintable(error));
    const std::optional<SongInfo> infoA = playableSongInfo(project, m_songA);
    const std::optional<SongInfo> infoB = playableSongInfo(project, m_songB);
    QVERIFY(infoA);
    QVERIFY(infoB);

    std::vector<std::unique_ptr<SongTab>> pages;
    QString tabError;
    auto pageA = readyTab(*infoA, project.trackBudgetFor(*infoA), tabError);
    QVERIFY2(pageA, qPrintable(tabError));
    // B starts bare: initial readiness false, projected the moment the real
    // readiness signal lands, exactly like a freshly created SongTab.
    auto pageB = bareTab(m_songB, tabError);
    QVERIFY2(pageB, qPrintable(tabError));
    auto pageC = bareTab(QStringLiteral("mus_route103"), tabError);
    QVERIFY2(pageC, qPrintable(tabError));
    SongTab *const tabA = pageA.get();
    SongTab *const tabB = pageB.get();
    SongTab *const tabC = pageC.get();
    pages.push_back(std::move(pageA));
    pages.push_back(std::move(pageB));
    pages.push_back(std::move(pageC));

    SongTab *selected = tabB;
    SongTabsModel model(pages, selected);
    QAbstractItemModelTester modelTester(&model);
    QSignalSpy selectionChangedSpy(&model, &SongTabsModel::selectionChanged);
    QSignalSpy selectedIndexChangedSpy(&model, &SongTabsModel::selectedIndexChanged);

    QCOMPARE(model.rowCount(), 3);
    QCOMPARE(model.selectedIndex(), 1);
    QCOMPARE(model.selectedSession(), static_cast<QObject *>(tabB));
    QCOMPARE(model.index(1).data(SongTabsModel::ReadyRole).toBool(), false);

    // Removing a row before the selection shifts the derived index without
    // touching the borrowed selection authority.
    QPersistentModelIndex removedRow(model.index(0));
    auto removedA = model.take(*tabA);
    QVERIFY(removedA);
    QVERIFY(!removedRow.isValid());
    QCOMPARE(model.rowCount(), 2);
    QCOMPARE(model.songAt(0), tabB);
    QCOMPARE(model.songAt(1), tabC);
    QCOMPARE(model.selectedIndex(), 0);
    QCOMPARE(model.selectedSession(), static_cast<QObject *>(tabB));
    QCOMPARE(selectionChangedSpy.count(), 0);
    QCOMPARE(selectedIndexChangedSpy.count(), 1);
    // The removed session outlives the bracket and stays fully usable.
    QCOMPARE(removedA->name().value(), m_songA);
    QVERIFY(removedA->document().undoStack() != nullptr);

    // The readiness signal projects into the ready role.
    QVERIFY2(stageMidi(*tabB, *infoB, project.trackBudgetFor(*infoB), tabError),
             qPrintable(tabError));
    const std::optional<VoicegroupId> voicegroupB = songVoicegroup(*infoB);
    QVERIFY(voicegroupB);
    tabB->applyVoicegroupBound(*voicegroupB);
    QVERIFY(tabB->isReady());
    QCOMPARE(model.index(0).data(SongTabsModel::ReadyRole).toBool(), true);
    QCOMPARE(model.index(0).data(SongTabsModel::TooltipRole).toString(), infoB->midPath);
    QCOMPARE(selectedIndexChangedSpy.count(), 1);

    // The edit signal projects the dirty asterisk into the title role; undo
    // drops it again.
    uint64_t end = 0;
    for (const SmfTrack &track : tabB->document().smf().tracks)
        end = (std::max)(end, track.endTick);
    tabB->document().addNote(0, end + 96, 72, 24, 93);
    QVERIFY(tabB->document().isDirty());
    QCOMPARE(model.index(0).data(SongTabsModel::TitleRole).toString(), m_songB + QLatin1Char('*'));
    tabB->document().undoStack()->undo();
    QVERIFY(!tabB->document().isDirty());
    QCOMPARE(model.index(0).data(SongTabsModel::TitleRole).toString(), m_songB);
    QCOMPARE(selectedIndexChangedSpy.count(), 1);

    // A save emits no tab signal, so consumers get no notification until the
    // owner refreshes the row; the model's data() itself reads the live
    // session and shows the clean title immediately.
    tabB->document().addNote(0, end + 96, 72, 24, 93);
    QVERIFY(tabB->document().isDirty());
    QCOMPARE(model.index(0).data(SongTabsModel::TitleRole).toString(), m_songB + QLatin1Char('*'));
    tabB->applySongSaved(tabB->captureSaveSnapshot(), false);
    QVERIFY(!tabB->document().isDirty());
    QCOMPARE(model.index(0).data(SongTabsModel::TitleRole).toString(), m_songB);
    QSignalSpy dataChangedSpy(&model, &QAbstractItemModel::dataChanged);
    model.refresh(*tabB);
    QCOMPARE(dataChangedSpy.count(), 1);
    QCOMPARE(model.index(0).data(SongTabsModel::TitleRole).toString(), m_songB);
    QCOMPARE(selectedIndexChangedSpy.count(), 1);
    QCOMPARE(selectionChangedSpy.count(), 0);

    // Removing the selected session keeps it alive but leaves the model with
    // no row for it: the borrowed authority is untouched, only the derived
    // index becomes -1.
    QPersistentModelIndex selectedRow(model.index(0));
    QCOMPARE(selectedRow.data(SongTabsModel::SessionRole).value<QObject *>(),
             static_cast<QObject *>(tabB));
    auto removedSelected = model.take(*tabB);
    QVERIFY(removedSelected);
    QCOMPARE(removedSelected.get(), tabB);
    QVERIFY(!selectedRow.isValid());
    QCOMPARE(model.rowCount(), 1);
    QCOMPARE(model.songAt(0), tabC);
    QCOMPARE(model.selectedSession(), static_cast<QObject *>(tabB));
    QCOMPARE(model.selectedIndex(), -1);
    QCOMPARE(selectionChangedSpy.count(), 0);
    QCOMPARE(selectedIndexChangedSpy.count(), 2);

    // The owner reassigns the borrowed slot and publishes it explicitly.
    selected = tabC;
    model.notifySelectionChanged();
    QCOMPARE(model.selectedSession(), static_cast<QObject *>(tabC));
    QCOMPARE(model.selectedIndex(), 0);
    QCOMPARE(selectionChangedSpy.count(), 1);
    QCOMPARE(selectedIndexChangedSpy.count(), 3);

    // takeAll drains the borrowed storage in order and keeps every session
    // alive for the caller's teardown.
    QPersistentModelIndex lastRow(model.index(0));
    std::vector<std::unique_ptr<SongTab>> drained = model.takeAll();
    QCOMPARE(drained.size(), size_t(1));
    QCOMPARE(drained[0].get(), tabC);
    QCOMPARE(drained[0]->name().value(), QStringLiteral("mus_route103"));
    QVERIFY(!lastRow.isValid());
    QVERIFY(pages.empty());
    QCOMPARE(model.rowCount(), 0);
    QCOMPARE(model.selectedSession(), static_cast<QObject *>(tabC));
    QCOMPARE(model.selectedIndex(), -1);
    QCOMPARE(selectionChangedSpy.count(), 1);
    // The drained row was the selected session: the derived index lands on
    // -1 and notifies, while the borrowed selection identity stays untouched.
    QCOMPARE(selectedIndexChangedSpy.count(), 4);

    // Draining an empty model and removing an already-removed session are
    // no-ops, and a stale refresh stays safe.
    QVERIFY(model.takeAll().empty());
    QVERIFY(!model.take(*tabC));
    model.refresh(*tabB);
    QCOMPARE(model.rowCount(), 0);
    QCOMPARE(selectedIndexChangedSpy.count(), 4);
    QCOMPARE(selectionChangedSpy.count(), 1);
}
