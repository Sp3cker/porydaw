#include <memory>
#include <optional>
#include <utility>
#include <variant>

#include <QDir>
#include <QFile>
#include <QtTest>

#include "checks/support/songfixture.h"
#include "checks/voicegroup/voicegrouptestfixture.h"
#include "project/decompproject.h"

namespace {

constexpr auto kSharedSong = "mus_oldale";
constexpr int kDirectSoundSlot = 0;
constexpr int kBlankSlot = 12;

bool sameKindsExcept(const LoadedBankView &before, const LoadedBankView &after, int except = -1)
{
    if (before.slotViews.size() != after.slotViews.size())
        return false;
    for (qsizetype slot = 0; slot < before.slotViews.size(); ++slot) {
        if (slot != except && before.slotViews[slot].kind != after.slotViews[slot].kind)
            return false;
    }
    return true;
}

int firstSquareSlot(const LoadedBankView &view)
{
    for (qsizetype slot = 0; slot < view.slotViews.size(); ++slot) {
        const std::optional<VgVoice> &voice = view.slotViews[slot].voice;
        if (voice && voicegroup_test::isSquare1(voice->macro))
            return int(slot);
    }
    return -1;
}

class VoicegroupBankTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(VoicegroupBankTest)

  public:
    VoicegroupBankTest(QString stagedRoot, QString songLabel)
        : m_stagedRoot(std::move(stagedRoot))
        , m_songLabel(std::move(songLabel))
    {}

  private slots:
    void init();
    void playableSongResolvesOnlyPlayableLabels();
    void bankLeaseIsReusedAcrossSharedVoicegroup();
    void appliedScalarEditReplacesBankAndPreservesOldLease();
    void staleBlankAndOutOfRangeEditsConflictWithoutMutation();
    void unknownIdentityIsHardError();
    void previewFailureRollsBackCandidate();
    void blankMaterializationRevertAndSpentToken();
    void saveRefreshesBankAndFailedSynthSaveLeavesRecordDirty();

  private:
    std::optional<VoicegroupEditAppliedResult> editedDirectSound(QString &error);

    QString m_stagedRoot;
    QString m_songLabel;
    DecompProject m_project;
    SongInfo m_song;
    std::unique_ptr<checks::ProjectFixture> m_copy;
    std::optional<LoadedBankView> m_initial;
};

void VoicegroupBankTest::init()
{
    QString error;
    m_copy = checks::ProjectFixture::copyOf(m_stagedRoot, error);
    QVERIFY2(m_copy, qPrintable(error));
    QVERIFY2(m_project.open(m_copy->root(), &error), qPrintable(error));
    const std::optional<SongName> name = SongName::create(m_songLabel);
    QVERIFY(name.has_value());
    const std::optional<SongInfo> song = m_project.playableSong(*name);
    QVERIFY(song.has_value());
    m_song = *song;
    m_initial = m_project.loadBank(m_song, &error);
    QVERIFY2(m_initial && m_initial->bank && error.isEmpty(), qPrintable(error));
    QCOMPARE(m_initial->slotViews.size(), qsizetype(VOICEGROUP_SIZE));
    QCOMPARE(m_initial->loadName, QStringLiteral("fixture_rich"));
    QCOMPARE(m_initial->slotViews[kDirectSoundSlot].kind, VgLineKind::Editable);
    QVERIFY(m_initial->slotViews[kDirectSoundSlot].voice.has_value());
    const int squareSlot = firstSquareSlot(*m_initial);
    QVERIFY2(squareSlot >= 0, "fixture_rich must retain a Square 1 voice");
    QCOMPARE(m_initial->slotViews[squareSlot].kind, VgLineKind::Editable);
    QVERIFY(m_initial->slotViews[squareSlot].voice.has_value());
    QVERIFY(!m_initial->dirty);
}

void VoicegroupBankTest::playableSongResolvesOnlyPlayableLabels()
{
    QVERIFY(m_copy);
    const std::optional<SongName> found = SongName::create(m_songLabel);
    QVERIFY(found.has_value());
    QVERIFY(m_project.playableSong(*found).has_value());
    const std::optional<SongName> absent = SongName::create(QStringLiteral("mus_absent"));
    QVERIFY(absent.has_value());
    QVERIFY(!m_project.playableSong(*absent).has_value());
}

void VoicegroupBankTest::bankLeaseIsReusedAcrossSharedVoicegroup()
{
    QVERIFY(m_initial);
    QString error;
    const std::optional<LoadedBankView> repeated = m_project.loadBank(m_song, &error);
    QVERIFY2(repeated && error.isEmpty(), qPrintable(error));
    QCOMPARE(repeated->bank.get(), m_initial->bank.get());
    const std::optional<SongName> sharedName = SongName::create(QString::fromLatin1(kSharedSong));
    QVERIFY(sharedName.has_value());
    const std::optional<SongInfo> sharedSong = m_project.playableSong(*sharedName);
    QVERIFY(sharedSong.has_value());
    const std::optional<LoadedBankView> shared = m_project.loadBank(*sharedSong, &error);
    QVERIFY2(shared && error.isEmpty(), qPrintable(error));
    QCOMPARE(shared->bank.get(), m_initial->bank.get());
    QCOMPARE(shared->id, m_initial->id);
}

std::optional<VoicegroupEditAppliedResult> VoicegroupBankTest::editedDirectSound(QString &error)
{
    if (!m_initial || !m_initial->slotViews[kDirectSoundSlot].voice) {
        error = QStringLiteral("fixture has no DirectSound slot");
        return std::nullopt;
    }
    const VgVoice original = *m_initial->slotViews[kDirectSoundSlot].voice;
    VgVoice edited = original;
    edited.key = 61;
    const std::optional<VoicegroupEditResult> result = m_project.applyVoicegroupEdit(
        {m_initial->id, SetVoicegroupSlot{kDirectSoundSlot, edited, original}}, &error);
    if (!result || !error.isEmpty()) {
        if (error.isEmpty())
            error = QStringLiteral("DirectSound edit was rejected");
        return std::nullopt;
    }
    const auto *const applied = std::get_if<VoicegroupEditAppliedResult>(&*result);
    if (!applied) {
        error = QStringLiteral("DirectSound edit did not produce an applied result");
        return std::nullopt;
    }
    return std::move(*applied);
}

void VoicegroupBankTest::appliedScalarEditReplacesBankAndPreservesOldLease()
{
    QVERIFY(m_initial);
    const VoicegroupLease oldLease = m_initial->bank;
    QString error;
    const std::optional<VoicegroupEditAppliedResult> applied = editedDirectSound(error);
    QVERIFY2(applied, qPrintable(error));
    QVERIFY(applied->view.dirty);
    QVERIFY(applied->view.bank.get() != m_initial->bank.get());
    QVERIFY(sameKindsExcept(*m_initial, applied->view));
    QVERIFY(applied->view.slotViews[kDirectSoundSlot].voice.has_value());
    QCOMPARE(applied->view.slotViews[kDirectSoundSlot].voice->key, 61);
    QVERIFY(!applied->materialization.has_value());
    QCOMPARE(oldLease->voices[kDirectSoundSlot].key, uint8_t(60));
}

void VoicegroupBankTest::staleBlankAndOutOfRangeEditsConflictWithoutMutation()
{
    QString initialEditError;
    const std::optional<VoicegroupEditAppliedResult> appliedEdit =
        editedDirectSound(initialEditError);
    QVERIFY2(appliedEdit, qPrintable(initialEditError));
    const VgVoice original = *m_initial->slotViews[kDirectSoundSlot].voice;
    VgVoice edited = original;
    edited.key = 61;
    const VoicegroupEditAppliedResult &applied = *appliedEdit;
    const QList<VoicegroupEditInput> conflicts = {
        {m_initial->id, SetVoicegroupSlot{kDirectSoundSlot, edited, original}},
        {m_initial->id, SetVoicegroupSlot{kDirectSoundSlot, edited, std::nullopt}},
        {m_initial->id, SetVoicegroupSlot{VOICEGROUP_SIZE, edited, std::nullopt}},
    };
    for (const VoicegroupEditInput &conflict : conflicts) {
        QString error;
        const std::optional<VoicegroupEditResult> result =
            m_project.applyVoicegroupEdit(conflict, &error);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QVERIFY(result.has_value());
        QVERIFY(std::holds_alternative<VoicegroupEditConflictResult>(*result));
        const std::optional<LoadedBankView> current = m_project.loadBank(m_song, &error);
        QVERIFY2(current && error.isEmpty(), qPrintable(error));
        QCOMPARE(current->bank.get(), applied.view.bank.get());
        QVERIFY(current->dirty);
    }
}

void VoicegroupBankTest::unknownIdentityIsHardError()
{
    QVERIFY(m_initial);
    const std::optional<VoicegroupId> unknown =
        VoicegroupId::create(QStringLiteral("sound/voicegroups/absent.inc"), QString());
    QVERIFY(unknown.has_value());
    const VgVoice value = *m_initial->slotViews[kDirectSoundSlot].voice;
    QString error;
    const std::optional<VoicegroupEditResult> result = m_project.applyVoicegroupEdit(
        {*unknown, SetVoicegroupSlot{kDirectSoundSlot, value, std::nullopt}}, &error);
    QVERIFY(!result.has_value());
    QVERIFY(!error.isEmpty());
}

void VoicegroupBankTest::previewFailureRollsBackCandidate()
{
    QString initialEditError;
    const std::optional<VoicegroupEditAppliedResult> applied = editedDirectSound(initialEditError);
    QVERIFY2(applied, qPrintable(initialEditError));
    const VgVoice before = *applied->view.slotViews[kDirectSoundSlot].voice;
    VgVoice rejected = before;
    rejected.key = 62;
    const QString previewPath = m_copy->root() + QStringLiteral("/.porydaw/vgpreview");
    QVERIFY(QDir().mkpath(QFileInfo(previewPath).path()));
    QFile blocker(previewPath);
    QVERIFY(blocker.open(QIODevice::WriteOnly));
    blocker.close();
    QString error;
    const std::optional<VoicegroupEditResult> rejectedResult = m_project.applyVoicegroupEdit(
        {m_initial->id, SetVoicegroupSlot{kDirectSoundSlot, rejected, before}}, &error);
    QVERIFY(QFile::remove(previewPath));
    QVERIFY(!rejectedResult.has_value());
    QVERIFY(!error.isEmpty());
    error.clear();
    const std::optional<LoadedBankView> survived = m_project.loadBank(m_song, &error);
    QVERIFY2(survived && error.isEmpty(), qPrintable(error));
    QCOMPARE(survived->bank.get(), applied->view.bank.get());
    QVERIFY(survived->slotViews[kDirectSoundSlot].voice.has_value());
    QCOMPARE(survived->slotViews[kDirectSoundSlot].voice->key, 61);
    QCOMPARE(survived->slotViews[kDirectSoundSlot].voice->symbol,
             m_initial->slotViews[kDirectSoundSlot].voice->symbol);
}

void VoicegroupBankTest::blankMaterializationRevertAndSpentToken()
{
    QVERIFY(m_initial);
    QCOMPARE(m_initial->slotViews[kBlankSlot].kind, VgLineKind::None);
    VgVoice blank;
    blank.macro = VgMacro::Square1;
    blank.sustain = 15;
    QString error;
    const std::optional<VoicegroupEditResult> materialized = m_project.applyVoicegroupEdit(
        {m_initial->id, SetVoicegroupSlot{kBlankSlot, blank, std::nullopt}}, &error);
    QVERIFY2(materialized && error.isEmpty(), qPrintable(error));
    const auto *const applied = std::get_if<VoicegroupEditAppliedResult>(&*materialized);
    QVERIFY(applied);
    QVERIFY(applied->materialization.has_value());
    QCOMPARE(applied->materialization->firstAddedSlot, kBlankSlot);
    QVERIFY(!applied->materialization->addedLines.isEmpty());
    QVERIFY(sameKindsExcept(*m_initial, applied->view, kBlankSlot));
    QCOMPARE(applied->view.slotViews[kBlankSlot].kind, VgLineKind::Editable);
    QCOMPARE(*applied->view.slotViews[kBlankSlot].voice, blank);

    const VoicegroupSource::BlankSlotMaterialization token = *applied->materialization;
    error.clear();
    const std::optional<VoicegroupEditResult> reverted =
        m_project.applyVoicegroupEdit({m_initial->id, RevertBlankSlot{token}}, &error);
    QVERIFY2(reverted && error.isEmpty(), qPrintable(error));
    const auto *const revertedView = std::get_if<VoicegroupEditAppliedResult>(&*reverted);
    QVERIFY(revertedView);
    QVERIFY(!revertedView->materialization.has_value());
    QVERIFY(sameKindsExcept(*m_initial, revertedView->view));
    QCOMPARE(revertedView->view.slotViews[kBlankSlot].kind, VgLineKind::None);
    QVERIFY(!revertedView->view.slotViews[kBlankSlot].voice.has_value());

    const std::optional<VoicegroupEditResult> spent =
        m_project.applyVoicegroupEdit({m_initial->id, RevertBlankSlot{token}}, &error);
    QVERIFY(spent.has_value());
    QVERIFY(std::holds_alternative<VoicegroupEditConflictResult>(*spent));
}

void VoicegroupBankTest::saveRefreshesBankAndFailedSynthSaveLeavesRecordDirty()
{
    QString initialEditError;
    const std::optional<VoicegroupEditAppliedResult> edited = editedDirectSound(initialEditError);
    QVERIFY2(edited, qPrintable(initialEditError));
    VoicegroupSource source;
    QString error;
    QVERIFY2(source.open(m_copy->root(), m_song.cfg.voicegroupArg, &error), qPrintable(error));
    const QByteArray before = voicegroup_test::readFile(source.filePath());
    const std::optional<LoadedBankView> saved =
        m_project.saveVoicegroup({m_initial->id, {}}, &error);
    QVERIFY2(saved && error.isEmpty(), qPrintable(error));
    QVERIFY(!saved->dirty);
    QVERIFY(saved->bank.get() != edited->view.bank.get());
    QCOMPARE(saved->slotViews[kDirectSoundSlot].voice->key, 61);
    QVERIFY(sameKindsExcept(*m_initial, *saved));
    QVERIFY(voicegroup_test::readFile(source.filePath()) != before);
    const std::optional<LoadedBankView> reused = m_project.loadBank(m_song, &error);
    QVERIFY2(reused && error.isEmpty(), qPrintable(error));
    QCOMPARE(reused->bank.get(), saved->bank.get());

    const int squareSlot = firstSquareSlot(*saved);
    QVERIFY2(squareSlot >= 0, "fixture_rich must retain a Square 1 voice");
    VgVoice square = *saved->slotViews[squareSlot].voice;
    square.duty = 3;
    const std::optional<VoicegroupEditResult> redirtied = m_project.applyVoicegroupEdit(
        {m_initial->id, SetVoicegroupSlot{squareSlot, square, *saved->slotViews[squareSlot].voice}},
        &error);
    QVERIFY2(redirtied && error.isEmpty(), qPrintable(error));
    const auto *const dirtyView = std::get_if<VoicegroupEditAppliedResult>(&*redirtied);
    QVERIFY(dirtyView);
    const std::optional<LoadedBankView> failed = m_project.saveVoicegroup(
        {m_initial->id, {{QStringLiteral("DirectSoundSynth_check_missing"), VgSynthDesc{}}}},
        &error);
    QVERIFY(!failed.has_value());
    QVERIFY(!error.isEmpty());
    error.clear();
    const std::optional<LoadedBankView> current = m_project.loadBank(m_song, &error);
    QVERIFY2(current && error.isEmpty(), qPrintable(error));
    QCOMPARE(current->bank.get(), dirtyView->view.bank.get());
    QVERIFY(current->dirty);
}

} // namespace

int runVgBankCheck(const QString &projectRoot, const QString &songLabel,
                   const QStringList &qtArguments)
{
    VoicegroupBankTest test(projectRoot, songLabel);
    QStringList arguments{QStringLiteral("voicegroup-bank")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "tst_voicegroupbank.moc"
