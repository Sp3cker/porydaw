#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QString>
#include <cstdio>
#include <optional>
#include <variant>

#include "project/decompproject.h"

extern "C" {
#include "voicegroup_loader.h"
}

// --vgbankcheck <projectRoot> <song>: worker bank-ownership check. Drives
// DecompProject's worker-side LoadedBankEntry records end to end against the
// decomp fixture project: loadBank reuse by identity and source timestamp
// (same song and a second song sharing the voicegroup), old-lease survival
// across bank replacement, applied vs confirmed-conflict vs hard-error
// atomicity (including source rollback when the loader rejects a candidate),
// blank materialize/revert token round-trips, and save clearing the source
// dirty bit with a refreshed bank. Run against a scratch copy of a project —
// it edits and saves into it.

namespace {

int fail(const char *what)
{
    std::fprintf(stderr, "vgbankcheck: FAIL: %s\n", what);
    return 1;
}

QByteArray readFileBytes(const QString &path)
{
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
}

// True when both views classify every source line into the same slot kind,
// ignoring the one slot named as legitimately changed by the scenario.
bool sameSlotKinds(const LoadedBankView &a, const LoadedBankView &b, int exceptSlot)
{
    if (a.slotViews.size() != b.slotViews.size() || exceptSlot >= a.slotViews.size())
        return false;
    for (int i = 0; i < a.slotViews.size(); ++i) {
        if (i != exceptSlot && a.slotViews[i].kind != b.slotViews[i].kind)
            return false;
    }
    return true;
}

} // namespace

int runVgBankCheck(const QString &projectRoot, const QString &songLabel)
{
    DecompProject project;
    QString error;
    if (!project.open(projectRoot, &error)) {
        std::fprintf(stderr, "vgbankcheck: %s\n", qUtf8Printable(error));
        return 1;
    }

    // ---- playableSong resolves the label, and only playable songs ----
    auto songName = SongName::create(songLabel);
    if (!songName)
        return fail("song label rejected");
    const std::optional<SongInfo> song = project.playableSong(*songName);
    if (!song)
        return fail("playableSong missed the fixture song");
    if (project.playableSong(SongName::create(QStringLiteral("mus_absent")).value()))
        return fail("playableSong invented a song");

    // ---- load and reuse by identity + timestamp ----
    const std::optional<LoadedBankView> first = project.loadBank(*song, &error);
    if (!error.isEmpty() || !first || !first->bank || first->slotViews.size() != VOICEGROUP_SIZE)
        return fail("initial loadBank failed");
    if (first->dirty || first->loadName != QLatin1String("fixture_rich"))
        return fail("unexpected initial bank view");
    const std::optional<LoadedBankView> reused = project.loadBank(*song, &error);
    if (!error.isEmpty() || !reused || reused->bank.get() != first->bank.get())
        return fail("unchanged record was not reused by identity/timestamp");

    // A second song sharing the voicegroup must resolve to the one record.
    const std::optional<SongInfo> other =
        project.playableSong(SongName::create(QStringLiteral("mus_oldale")).value());
    if (!other)
        return fail("second fixture song missing");
    const std::optional<LoadedBankView> shared = project.loadBank(*other, &error);
    if (!error.isEmpty() || !shared || shared->bank.get() != first->bank.get() ||
        !(shared->id == first->id))
        return fail("shared voicegroup did not resolve to one canonical bank");

    const int dsSlot = 0; // fixture_rich slot 0: voice_directsound fixture_loop
    int sq1Slot = -1;
    for (int i = 0; i < first->slotViews.size(); ++i) {
        if (first->slotViews[i].voice &&
            (first->slotViews[i].voice->macro == VgMacro::Square1 ||
             first->slotViews[i].voice->macro == VgMacro::Square1Alt)) {
            sq1Slot = i;
            break;
        }
    }
    if (sq1Slot < 0)
        return fail("fixture voicegroup missing a Square 1 slot");

    if (first->slotViews[dsSlot].kind != VgLineKind::Editable ||
        first->slotViews[sq1Slot].kind != VgLineKind::Editable || !first->slotViews[dsSlot].voice ||
        !first->slotViews[sq1Slot].voice)
        return fail("initial view does not classify the edited slots as editable");
    // ---- rebuilding project maps repins loaded bank identities ----
    const VoicegroupLease preRebuildLease = first->bank;
    error.clear();
    if (!project.rebuildVoicegroupProject(&error) || !error.isEmpty())
        return fail("voicegroup project rebuild failed");
    const std::optional<LoadedBankView> rebuilt = project.loadBank(*song, &error);
    if (!error.isEmpty() || !rebuilt || !rebuilt->bank)
        return fail("rebuild dropped the loaded bank identity");
    if (rebuilt->bank.get() == first->bank.get())
        return fail("rebuild did not repin the bank to the replacement context");
    if (!preRebuildLease || preRebuildLease->voices[dsSlot].key != 60)
        return fail("published lease did not survive the context rebuild");

    const VoicegroupId id = rebuilt->id;
    const VgVoice original = rebuilt->slotViews[dsSlot].voice.value();
    VgVoice edited = original;
    edited.key = 61;

    // ---- applied edit replaces the bank; the old lease survives ----
    const VoicegroupLease oldLease = first->bank;
    error.clear();
    const std::optional<VoicegroupEditResult> applied = project.applyVoicegroupEdit(
        VoicegroupEditInput{id, SetVoicegroupSlot{dsSlot, edited, original}}, &error);
    if (!error.isEmpty() || !applied)
        return fail("matching expected edit was not applied");
    const auto *appliedView = std::get_if<VoicegroupEditAppliedResult>(&*applied);
    if (!appliedView)
        return fail("matching expected edit was not applied");
    if (appliedView->view.bank.get() == first->bank.get())
        return fail("applied edit did not replace the bank");
    if (!appliedView->view.dirty)
        return fail("applied edit did not mark the source dirty");
    if (!sameSlotKinds(appliedView->view, *first, -1))
        return fail("scalar edit changed a slot kind");
    if (!appliedView->view.slotViews[dsSlot].voice ||
        appliedView->view.slotViews[dsSlot].voice->key != 61)
        return fail("applied view lost the edit");
    if (appliedView->materialization)
        return fail("scalar application returned a blank token");
    if (!oldLease || oldLease->voices[dsSlot].key != 60)
        return fail("old lease did not survive the replacement");

    // ---- stale expected is a confirmed conflict, not an error ----
    error.clear();
    const std::optional<VoicegroupEditResult> stale = project.applyVoicegroupEdit(
        VoicegroupEditInput{id, SetVoicegroupSlot{dsSlot, edited, original}}, &error);
    if (!error.isEmpty() || !stale || !std::get_if<VoicegroupEditConflictResult>(&*stale))
        return fail("stale expected was not a typed conflict");
    const std::optional<LoadedBankView> afterConflict = project.loadBank(*song, &error);
    if (!error.isEmpty() || !afterConflict ||
        afterConflict->bank.get() != appliedView->view.bank.get() || !afterConflict->dirty)
        return fail("conflict mutated the record");

    // ---- remaining validation no-ops are conflicts too ----
    error.clear();
    const std::optional<VoicegroupEditResult> occupied = project.applyVoicegroupEdit(
        VoicegroupEditInput{id, SetVoicegroupSlot{dsSlot, edited, std::nullopt}}, &error);
    if (!error.isEmpty() || !occupied || !std::get_if<VoicegroupEditConflictResult>(&*occupied))
        return fail("blank expected on an occupied slot was not a conflict");
    const std::optional<VoicegroupEditResult> outOfRange = project.applyVoicegroupEdit(
        VoicegroupEditInput{id, SetVoicegroupSlot{VOICEGROUP_SIZE, edited, std::nullopt}}, &error);
    if (!error.isEmpty() || !outOfRange || !std::get_if<VoicegroupEditConflictResult>(&*outOfRange))
        return fail("out-of-range slot was not a conflict");

    // ---- unknown identity is a hard error ----
    auto unknown = VoicegroupId::create(QStringLiteral("sound/voicegroups/absent.inc"), QString());
    if (!unknown)
        return fail("identity factory rejected a valid relative path");
    error.clear();
    const std::optional<VoicegroupEditResult> missing = project.applyVoicegroupEdit(
        VoicegroupEditInput{*unknown, SetVoicegroupSlot{0, edited, std::nullopt}}, &error);
    if (missing || error.isEmpty())
        return fail("unknown identity was not a hard error");

    const QString previewPath = QDir(projectRoot).filePath(QStringLiteral(".porydaw/vgpreview"));
    QDir(previewPath).removeRecursively();
    if (!QDir().mkpath(QFileInfo(previewPath).path()))
        return fail("could not prepare the preview failure path");
    QFile blocker(previewPath);
    if (!blocker.open(QIODevice::WriteOnly))
        return fail("could not block the preview directory");
    blocker.close();
    VgVoice rejectedEdit = edited;
    rejectedEdit.key = 62;
    error.clear();
    const std::optional<VoicegroupEditResult> rejected = project.applyVoicegroupEdit(
        VoicegroupEditInput{id, SetVoicegroupSlot{dsSlot, rejectedEdit, edited}}, &error);
    QFile::remove(previewPath);
    if (rejected || error.isEmpty())
        return fail("preview setup failure was not a hard error");
    error.clear();
    const std::optional<LoadedBankView> survived = project.loadBank(*song, &error);
    if (!error.isEmpty() || !survived || survived->bank.get() != appliedView->view.bank.get() ||
        !survived->slotViews[dsSlot].voice || survived->slotViews[dsSlot].voice->key != 61 ||
        survived->slotViews[dsSlot].voice->symbol != original.symbol)
        return fail("hard error did not leave the old record untouched");

    // ---- blank materialize / revert token round-trip ----
    const int blankSlot = 12; // first slot past fixture_rich's last voice line

    // The conflicts and hard errors above never mutate the record, so the
    // view loaded before them is still current: only a None-kind slot may be
    // submitted as blank materialization.
    if (survived->slotViews.size() != VOICEGROUP_SIZE ||
        survived->slotViews[blankSlot].kind != VgLineKind::None)
        return fail("blank materialization target is not a None-kind slot");
    VgVoice blankVoice;
    blankVoice.macro = VgMacro::Square1;
    blankVoice.sustain = 15;
    error.clear();
    const std::optional<VoicegroupEditResult> materialized = project.applyVoicegroupEdit(
        VoicegroupEditInput{id, SetVoicegroupSlot{blankSlot, blankVoice, std::nullopt}}, &error);
    if (!error.isEmpty() || !materialized)
        return fail("blank set did not materialize with a token");
    const auto *materializedView = std::get_if<VoicegroupEditAppliedResult>(&*materialized);
    if (!materializedView || !materializedView->materialization)
        return fail("blank set did not materialize with a token");
    if (materializedView->materialization->firstAddedSlot != blankSlot ||
        materializedView->materialization->addedLines.isEmpty())
        return fail("blank token does not describe the materialization");
    if (!sameSlotKinds(materializedView->view, *survived, blankSlot))
        return fail("materialization changed an unrelated slot kind");
    if (materializedView->view.slotViews[blankSlot].kind != VgLineKind::Editable)
        return fail("materialized slot is not editable");
    if (!materializedView->view.slotViews[blankSlot].voice)
        return fail("applied view lost the materialized voice");
    const auto token = *materializedView->materialization;
    error.clear();
    const std::optional<VoicegroupEditResult> reverted =
        project.applyVoicegroupEdit(VoicegroupEditInput{id, RevertBlankSlot{token}}, &error);
    if (!error.isEmpty() || !reverted)
        return fail("blank revert was not applied without a fresh token");
    const auto *revertedView = std::get_if<VoicegroupEditAppliedResult>(&*reverted);
    if (!revertedView || revertedView->materialization)
        return fail("blank revert was not applied without a fresh token");
    if (!sameSlotKinds(revertedView->view, *first, -1))
        return fail("revert did not restore the pristine slot kinds");
    if (revertedView->view.slotViews[blankSlot].voice)
        return fail("reverted slot is not blank again");
    if (revertedView->view.slotViews[blankSlot].kind != VgLineKind::None)
        return fail("reverted slot did not return to a None kind");
    error.clear();
    const std::optional<VoicegroupEditResult> spent =
        project.applyVoicegroupEdit(VoicegroupEditInput{id, RevertBlankSlot{token}}, &error);
    if (!error.isEmpty() || !spent || !std::get_if<VoicegroupEditConflictResult>(&*spent))
        return fail("spent blank token was not a conflict");

    // ---- save clears the dirty bit and refreshes the bank ----
    VoicegroupSource source;
    if (!source.open(projectRoot, song->cfg.voicegroupArg, &error)) {
        std::fprintf(stderr, "vgbankcheck: locate: %s\n", qUtf8Printable(error));
        return 1;
    }
    const QString vgPath = source.filePath();
    const QByteArray bytesBefore = readFileBytes(vgPath);
    const std::optional<LoadedBankView> saved =
        project.saveVoicegroup(SaveVoicegroupInput{id, {}}, &error);
    if (!error.isEmpty() || !saved || !saved->bank)
        return fail("saveVoicegroup failed");
    if (saved->dirty)
        return fail("save did not clear the dirty bit");
    if (saved->bank.get() == revertedView->view.bank.get())
        return fail("save did not refresh the bank from disk");
    if (!sameSlotKinds(*saved, *first, -1))
        return fail("save did not preserve the slot kinds");
    if (!saved->slotViews[dsSlot].voice || saved->slotViews[dsSlot].voice->key != 61)
        return fail("saved bank lost the edit");
    if (readFileBytes(vgPath) == bytesBefore)
        return fail("save wrote nothing to disk");
    const std::optional<LoadedBankView> afterSave = project.loadBank(*song, &error);
    if (!error.isEmpty() || !afterSave || afterSave->bank.get() != saved->bank.get())
        return fail("save did not refresh the record's file time for reuse");

    // ---- a failing synth write is a hard error that aborts the save ----
    if (!saved->slotViews[sq1Slot].voice)
        return fail("saved bank missing square slot");
    VgVoice sq1Edited = saved->slotViews[sq1Slot].voice.value();
    sq1Edited.duty = 3;
    error.clear();
    const std::optional<VoicegroupEditResult> redirtied = project.applyVoicegroupEdit(
        VoicegroupEditInput{id,
                            SetVoicegroupSlot{sq1Slot, sq1Edited, saved->slotViews[sq1Slot].voice}},
        &error);
    if (!error.isEmpty() || !redirtied)
        return fail("square edit was not applied");
    const auto *redirtiedView = std::get_if<VoicegroupEditAppliedResult>(&*redirtied);
    if (!redirtiedView)
        return fail("square edit was not applied");
    const std::optional<LoadedBankView> synthFailed = project.saveVoicegroup(
        SaveVoicegroupInput{id,
                            QList<QPair<QString, VgSynthDesc>>{
                                {QStringLiteral("DirectSoundSynth_check_missing"), VgSynthDesc{}}}},
        &error);
    if (synthFailed || error.isEmpty())
        return fail("failing synth write was not a hard error");
    error.clear();
    const std::optional<LoadedBankView> stillDirty = project.loadBank(*song, &error);
    if (!error.isEmpty() || !stillDirty ||
        stillDirty->bank.get() != redirtiedView->view.bank.get() || !stillDirty->dirty)
        return fail("failed save disturbed the record");

    std::printf("vgbankcheck: reuse, lease survival, edit outcomes, blank tokens, save OK\n");
    return 0;
}
