#include <QByteArray>
#include <QString>
#include <QUndoCommand>
#include <QUndoStack>
#include <QVector>

#include <cstdio>
#include <optional>
#include <utility>
#include <variant>

#include "core/songhistory.h"
#include "project/projectidentity.h"
#include "project/projectworkspace.h"
#include "project/voicegroupsource.h"
#include "ui/voicegroupviewcache.h"

// --voicegroupviewcachecheck: self-contained SongHistory shared-bank and
// VoicegroupViewCache coordinator contracts, no fixtures. A fake bank model
// stands in for the worker: it applies exactly the drafts the history hands
// out (validating expected voices and blank tokens like the real worker) and
// answers with fresh blank materializations or conflicts, so every request,
// crossing, merge, conflict, and pending resolution runs end to end.

namespace {

constexpr int kSlotScalar = 3;
constexpr int kSlotBlank = 4;
constexpr int kSlotStaleUndo = 5;
constexpr int kSlotStaleRedo = 6;
constexpr int kSlotMerge = 2;

// Report and count each failure.
auto contractCheck(int &failures)
{
    return [&failures](bool ok, const char *what) {
        if (!ok) {
            std::fprintf(stderr, "voicegroupviewcachecheck: FAIL: %s\n", what);
            failures++;
        }
        return ok;
    };
}

// A mergeable document command, shaped like the roll's per-gesture moves.
class CountCommand final : public QUndoCommand
{
  public:
    CountCommand(int *value, int delta, int id)
        : QUndoCommand(QStringLiteral("count"))
        , m_value(value)
        , m_delta(delta)
        , m_id(id)
    {}

    int id() const override { return m_id; }
    void redo() override { *m_value += m_delta; }
    void undo() override { *m_value -= m_delta; }

  private:
    int *m_value;
    int m_delta;
    int m_id;
};

VgVoice makeVoice(int duty, int attack, const QString &symbol = QStringLiteral("snd_a"))
{
    VgVoice voice;
    voice.duty = duty;
    voice.attack = attack;
    voice.symbol = symbol;
    return voice;
}

SetVoicegroupSlot setSlot(int slot, const VgVoice &value, const std::optional<VgVoice> &expected)
{
    return SetVoicegroupSlot{slot, value, expected};
}

bool isSetDraft(const VoicegroupEditInput &draft, int slot, const VgVoice &value,
                const std::optional<VgVoice> &expected)
{
    const auto *set = std::get_if<SetVoicegroupSlot>(&draft.operation);
    return set && set->slot == slot && set->value == value && set->expected == expected;
}

bool isRevertDraft(const VoicegroupEditInput &draft,
                   const VoicegroupSource::BlankSlotMaterialization &token)
{
    const auto *revert = std::get_if<RevertBlankSlot>(&draft.operation);
    return revert && revert->materialization.firstAddedSlot == token.firstAddedSlot &&
           revert->materialization.headerAfter == token.headerAfter;
}

const VoicegroupEditInput *bankDraft(const HistoryRequest &request)
{
    return std::get_if<VoicegroupEditInput>(&request);
}

// The worker stand-in: eight voice slots plus the one live blank
// materialization token. Each generated token carries a distinct marker, so a
// stale token can never pass the revert check — the fake bank reproduces the
// real worker's confirmed-conflict behavior for stale drafts.
class FakeBank
{
  public:
    // The typed worker outcome: applied with an optional fresh blank token,
    // or a confirmed conflict that changed nothing.
    struct Outcome {
        bool applied = false;
        std::optional<VoicegroupSource::BlankSlotMaterialization> materialization;
    };

    void poke(int index, const VgVoice &voice) { m_slots[index] = voice; }
    // Another tab's confirmed edit lands under everyone: the slot changes and
    // any live blank token for it is replaced.
    void rematerialize(int index, const VgVoice &voice)
    {
        m_slots[index] = voice;
        m_token = makeToken(index);
    }

    Outcome apply(const VoicegroupEditInput &input)
    {
        if (const auto *set = std::get_if<SetVoicegroupSlot>(&input.operation)) {
            if (set->slot < 0 || set->slot >= kSlotCount)
                return {};
            const bool blankBefore = !m_slots[set->slot].has_value();
            const bool expectsBlank = !set->expected.has_value();
            if (blankBefore != expectsBlank)
                return {};
            if (!expectsBlank && !(*set->expected == *m_slots[set->slot]))
                return {};
            m_slots[set->slot] = set->value;
            if (!expectsBlank)
                return {true, std::nullopt};
            const auto token = makeToken(set->slot);
            m_token = token;
            return {true, token};
        }
        if (const auto *revert = std::get_if<RevertBlankSlot>(&input.operation)) {
            if (!m_token || revert->materialization.headerAfter != m_token->headerAfter)
                return {};
            m_slots[revert->materialization.firstAddedSlot].reset();
            m_token.reset();
            return {true, std::nullopt};
        }
        return {};
    }

  private:
    static constexpr int kSlotCount = 8;

    VoicegroupSource::BlankSlotMaterialization makeToken(int slot)
    {
        VoicegroupSource::BlankSlotMaterialization token;
        token.firstAddedSlot = slot;
        token.addedLines = {QByteArrayLiteral("generated")};
        token.headerAfter = QByteArray::number(++m_tokenCounter);
        return token;
    }

    std::optional<VgVoice> m_slots[kSlotCount];
    std::optional<VoicegroupSource::BlankSlotMaterialization> m_token;
    int m_tokenCounter = 0;
};

// SongHistory's shared-bank contracts: identity preservation, exact drafts,
// inert crossings, the blank-token lifecycle, and stale-entry conflicts.
int checkBankHistoryContracts()
{
    auto failures = 0;
    const auto check = contractCheck(failures);
    const auto identity =
        VoicegroupId::create(QStringLiteral("sound/voicegroups/bank.inc"), QString()).value();
    QUndoStack stack;
    SongHistory history(stack);
    int document = 0;
    constexpr int kDocumentGesture = 0x6463; // 'dc'
    FakeBank bank;

    check(!history.canUndo() && !history.canRedo() &&
              history.currentDocumentIdentity() == history.savedDocumentIdentity(),
          "a fresh history did not start clean");

    // A document entry crosses synchronously in both directions.
    history.pushDocument(std::make_unique<CountCommand>(&document, 1, kDocumentGesture));
    const auto afterDocument = history.currentDocumentIdentity();
    check(afterDocument != history.savedDocumentIdentity(),
          "a document push did not advance the current identity");
    const auto savedBase = history.savedDocumentIdentity();
    check(std::holds_alternative<DocumentHistoryApplied>(history.requestUndo()) && document == 0 &&
              history.currentDocumentIdentity() == history.savedDocumentIdentity(),
          "a document undo did not cross synchronously back to the saved identity");
    check(std::holds_alternative<DocumentHistoryApplied>(history.requestRedo()) && document == 1,
          "a document redo did not cross synchronously");

    // An initial confirmed bank entry is pushed past its own inert redo and
    // preserves the document identity and the saved boundary.
    const auto scalarBefore = makeVoice(2, 0);
    const auto scalarAfter = makeVoice(5, 0);
    bank.poke(kSlotScalar, scalarBefore);
    const auto scalarDraft =
        VoicegroupEditInput{identity, setSlot(kSlotScalar, scalarAfter, scalarBefore)};
    const auto scalarApplied = bank.apply(scalarDraft);
    check(scalarApplied.applied && !scalarApplied.materialization.has_value(),
          "a scalar bank edit must not mint a blank token");
    history.pushConfirmedBank(scalarDraft, scalarApplied.materialization);
    check(stack.count() == 2 && stack.index() == 2 && !stack.canRedo() &&
              history.currentDocumentIdentity() == afterDocument &&
              history.savedDocumentIdentity() == savedBase,
          "the initial bank push did not land past an inert redo on the same identity");

    // Undo and redo prepare exact drafts, leave the index alone, and cross
    // only through the confirmed inert callbacks.
    auto request = history.requestUndo();
    const auto *draft = bankDraft(request);
    check(draft && isSetDraft(*draft, kSlotScalar, scalarBefore, scalarAfter) && stack.index() == 2,
          "the scalar bank undo did not prepare the swapped set draft without moving the index");
    const auto undoOutcome = bank.apply(*draft);
    check(undoOutcome.applied, "the worker rejected a fresh scalar bank undo draft");
    history.crossConfirmedBankUndo(undoOutcome.materialization);
    check(stack.index() == 1 && document == 1 && history.currentDocumentIdentity() == afterDocument,
          "a bank undo crossing moved the index, the document, or the identity");
    request = history.requestRedo();
    draft = bankDraft(request);
    check(draft && isSetDraft(*draft, kSlotScalar, scalarAfter, scalarBefore) && stack.index() == 1,
          "the bank redo did not return the stored forward draft without moving the index");
    const auto redoOutcome = bank.apply(*draft);
    check(redoOutcome.applied, "the worker rejected the bank redo draft");
    history.crossConfirmedBankRedo(redoOutcome.materialization);
    check(stack.index() == 2 && history.currentDocumentIdentity() == afterDocument,
          "a bank redo crossing moved the index or the identity");

    // A blank initial edit carries its token through undo, loses it, and
    // adopts each fresh blank-redo token.
    const auto blankVoice = makeVoice(2, 0, QStringLiteral("snd_new"));
    const auto blankDraft =
        VoicegroupEditInput{identity, setSlot(kSlotBlank, blankVoice, std::nullopt)};
    const auto blankApplied = bank.apply(blankDraft);
    check(blankApplied.applied && blankApplied.materialization.has_value(),
          "a blank initial set did not return a fresh materialization");
    const auto firstToken = *blankApplied.materialization;
    history.pushConfirmedBank(blankDraft, firstToken);
    request = history.requestUndo();
    draft = bankDraft(request);
    check(draft && isRevertDraft(*draft, firstToken),
          "the blank undo did not prepare a revert of the live token");
    const auto revertOutcome = bank.apply(*draft);
    check(revertOutcome.applied && !revertOutcome.materialization.has_value(),
          "the worker rejected the blank revert");
    history.crossConfirmedBankUndo(revertOutcome.materialization);
    request = history.requestRedo();
    draft = bankDraft(request);
    check(draft && isSetDraft(*draft, kSlotBlank, blankVoice, std::nullopt),
          "the blank redo did not prepare the forward materialize draft");
    const auto freshApplied = bank.apply(*draft);
    check(freshApplied.applied && freshApplied.materialization.has_value() &&
              !(freshApplied.materialization->headerAfter == firstToken.headerAfter),
          "the blank redo did not mint a fresh token");
    history.crossConfirmedBankRedo(freshApplied.materialization);
    request = history.requestUndo();
    draft = bankDraft(request);
    check(draft && isRevertDraft(*draft, *freshApplied.materialization),
          "the history did not replace its token with the fresh blank-redo token");
    const auto secondRevert = bank.apply(*draft);
    check(secondRevert.applied, "the worker rejected the revert of the fresh token");
    history.crossConfirmedBankUndo(secondRevert.materialization);
    check(history.currentDocumentIdentity() == afterDocument && stack.index() == 2,
          "blank bank transitions moved the index or the identity");

    // A confirmed stale undo obsoletes its bank entry: the stack drops it and
    // the index falls to the entry below without crossing anything.
    const auto staleVoice = makeVoice(2, 0, QStringLiteral("snd_stale"));
    const auto staleDraft =
        VoicegroupEditInput{identity, setSlot(kSlotStaleUndo, staleVoice, std::nullopt)};
    const auto staleApplied = bank.apply(staleDraft);
    history.pushConfirmedBank(staleDraft, staleApplied.materialization);
    bank.rematerialize(kSlotStaleUndo, staleVoice); // another tab made the revert stale
    request = history.requestUndo();
    draft = bankDraft(request);
    check(draft && !bank.apply(*draft).applied,
          "the stale revert draft did not conflict in the worker");
    const auto countBeforeUndoConflict = stack.count();
    history.resolveBankUndoConflict();
    check(stack.count() == countBeforeUndoConflict - 1 && history.canUndo() && !history.canRedo() &&
              history.currentDocumentIdentity() == afterDocument &&
              history.savedDocumentIdentity() == savedBase,
          "the confirmed undo conflict did not drop the stale bank entry cleanly");

    // A confirmed stale redo obsoletes the entry above the index: it is
    // pushed, undone, made stale, and dropped by the conflict resolution.
    const auto redoStaleVoice = makeVoice(2, 0, QStringLiteral("snd_redo"));
    const auto redoStaleDraft =
        VoicegroupEditInput{identity, setSlot(kSlotStaleRedo, redoStaleVoice, std::nullopt)};
    const auto redoStaleApplied = bank.apply(redoStaleDraft);
    history.pushConfirmedBank(redoStaleDraft, redoStaleApplied.materialization);
    request = history.requestUndo();
    draft = bankDraft(request);
    const auto redoStaleUndo = bank.apply(*draft);
    check(redoStaleUndo.applied, "the stale-redo entry's fresh revert conflicted");
    history.crossConfirmedBankUndo(redoStaleUndo.materialization);
    bank.rematerialize(kSlotStaleRedo, redoStaleVoice); // the slot is occupied again
    request = history.requestRedo();
    draft = bankDraft(request);
    check(draft && !bank.apply(*draft).applied,
          "the stale redo draft did not conflict in the worker");
    const auto countBeforeRedoConflict = stack.count();
    history.resolveBankRedoConflict();
    check(stack.count() == countBeforeRedoConflict - 1 && !stack.canRedo() && history.canUndo() &&
              history.currentDocumentIdentity() == afterDocument,
          "the confirmed redo conflict did not drop the stale bank entry cleanly");

    return failures;
}

// The existing scalar merge rules restricted to confirmed bank entries.
int checkBankMergeContracts()
{
    auto failures = 0;
    const auto check = contractCheck(failures);
    const auto identity =
        VoicegroupId::create(QStringLiteral("sound/voicegroups/bank.inc"), QString()).value();
    const auto v1 = makeVoice(2, 0);
    const auto v2 = makeVoice(5, 0);                          // duty changed: mask {duty}
    const auto v3 = makeVoice(7, 0);                          // duty changed: mask {duty}
    const auto v4 = makeVoice(2, 3);                          // attack changed: mask {attack}
    const auto v5 = makeVoice(2, 0, QStringLiteral("snd_b")); // structural: mask {symbol}

    {
        QUndoStack stack;
        SongHistory history(stack);
        const auto base = history.currentDocumentIdentity();

        history.pushConfirmedBank(VoicegroupEditInput{identity, setSlot(kSlotMerge, v2, v1)}, {});
        history.pushConfirmedBank(VoicegroupEditInput{identity, setSlot(kSlotMerge, v3, v2)}, {});
        check(stack.count() == 1, "two same-slot same-mask scalar bank pushes did not merge");
        const auto request = history.requestUndo();
        const auto *draft = bankDraft(request);
        check(draft && isSetDraft(*draft, kSlotMerge, v1, v3),
              "the merged bank entry did not keep the oldest before and newest after");
        history.crossConfirmedBankUndo({});
        check(history.currentDocumentIdentity() == base,
              "crossing a merged bank entry moved the document identity");
    }
    {
        // A self-cancelling merge at the top disappears entirely at push time.
        QUndoStack stack;
        SongHistory history(stack);
        history.pushConfirmedBank(VoicegroupEditInput{identity, setSlot(kSlotMerge, v2, v1)}, {});
        history.pushConfirmedBank(VoicegroupEditInput{identity, setSlot(kSlotMerge, v1, v2)}, {});
        check(stack.count() == 0 && !history.canUndo(),
              "a self-cancelling scalar bank merge did not drop its obsolete entry");
    }
    {
        QUndoStack stack;
        SongHistory history(stack);
        history.pushConfirmedBank(
            VoicegroupEditInput{identity, setSlot(kSlotMerge, v2, std::nullopt)},
            VoicegroupSource::BlankSlotMaterialization{});
        history.pushConfirmedBank(VoicegroupEditInput{identity, setSlot(kSlotMerge, v3, v2)}, {});
        check(stack.count() == 2, "a scalar push merged into a blank bank entry");
    }
    {
        QUndoStack stack;
        SongHistory history(stack);
        history.pushConfirmedBank(VoicegroupEditInput{identity, setSlot(kSlotMerge, v2, v1)}, {});
        history.pushConfirmedBank(VoicegroupEditInput{identity, setSlot(kSlotMerge + 1, v3, v1)},
                                  {});
        check(stack.count() == 2, "scalar bank entries on different slots merged");
    }
    {
        QUndoStack stack;
        SongHistory history(stack);
        history.pushConfirmedBank(VoicegroupEditInput{identity, setSlot(kSlotMerge, v2, v1)}, {});
        history.pushConfirmedBank(VoicegroupEditInput{identity, setSlot(kSlotMerge, v4, v1)}, {});
        check(stack.count() == 2, "scalar bank entries with different changed masks merged");
    }
    {
        QUndoStack stack;
        SongHistory history(stack);
        history.pushConfirmedBank(VoicegroupEditInput{identity, setSlot(kSlotMerge, v2, v1)}, {});
        history.pushConfirmedBank(VoicegroupEditInput{identity, setSlot(kSlotMerge, v5, v1)}, {});
        check(stack.count() == 2, "a structural voice edit merged into a scalar bank entry");
    }
    {
        // A bank merge never crosses a document boundary: both entries
        // preserve one document identity, so even a saved one cannot refuse.
        QUndoStack stack;
        SongHistory history(stack);
        history.pushConfirmedBank(VoicegroupEditInput{identity, setSlot(kSlotMerge, v2, v1)}, {});
        history.markDocumentSaved(history.currentDocumentIdentity());
        history.pushConfirmedBank(VoicegroupEditInput{identity, setSlot(kSlotMerge, v3, v2)}, {});
        check(stack.count() == 1,
              "a scalar bank push refused to merge across the saved document identity");
        history.sealBankMerge();
        history.pushConfirmedBank(VoicegroupEditInput{identity, setSlot(kSlotMerge, v2, v3)}, {});
        check(stack.count() == 2, "a scalar bank push crossed a clean bank boundary");
    }

    return failures;
}

// VoicegroupViewCache: the view map, the one pending transition, the typed
// outcome routing, and the two gates.
int checkViewCacheContracts()
{
    auto failures = 0;
    const auto check = contractCheck(failures);
    const auto identity =
        VoicegroupId::create(QStringLiteral("sound/voicegroups/bank.inc"), QString()).value();
    const auto otherIdentity =
        VoicegroupId::create(QStringLiteral("sound/voicegroups/other.inc"), QString()).value();
    const auto tab = SongName::create(QStringLiteral("banktab")).value();
    const auto otherTab = SongName::create(QStringLiteral("othertab")).value();

    QUndoStack stack;
    SongHistory history(stack);
    VoicegroupViewCache cache;
    FakeBank bank;
    const auto before = makeVoice(2, 0);
    const auto after = makeVoice(5, 0);
    bank.poke(kSlotScalar, before);
    const auto scalarDraft = VoicegroupEditInput{identity, setSlot(kSlotScalar, after, before)};

    check(cache.find(identity) == nullptr && cache.bankActionsEnabled() &&
              !cache.pendingOrigin().has_value() && cache.closeEnabledFor(tab),
          "an empty cache did not start unbounded and viewless");

    LoadedBankView staleView{identity, {}, QStringLiteral("bank"), true, {}};
    cache.applyView(staleView);
    check(cache.find(identity) && cache.find(identity)->dirty,
          "applyView did not install the bank view");
    LoadedBankView freshView = staleView;
    freshView.dirty = false;
    cache.applyView(freshView);
    check(cache.find(identity) && !cache.find(identity)->dirty,
          "applyView did not replace the view for the same identity");

    // begin() starts the one FIFO transition and refuses a second.
    check(cache.begin(PendingBankTransition{identity, tab, PendingBankTransition::Kind::Initial,
                                            scalarDraft}),
          "begin refused the first transition");
    check(!cache.begin(PendingBankTransition{identity, otherTab, PendingBankTransition::Kind::Undo,
                                             scalarDraft}),
          "begin accepted a second pending transition");
    check(!cache.bankActionsEnabled() && cache.pendingOrigin() == tab &&
              !cache.closeEnabledFor(tab) && cache.closeEnabledFor(otherTab),
          "the pending gates did not hold for the origin alone");

    // A mismatched identity resolves nothing and keeps the transition.
    cache.resolveConflict(VoicegroupEditConflict{otherIdentity}, history);
    check(cache.pendingOrigin().has_value() && stack.count() == 0,
          "a mismatched conflict resolved the pending transition");
    cache.resolveApplied(VoicegroupEditApplied{otherIdentity, std::nullopt}, history);
    check(cache.pendingOrigin().has_value() && stack.count() == 0,
          "a mismatched applied outcome resolved the pending transition");

    // Initial: the installed view precedes the history push, and the pushed
    // entry is exactly the submitted draft.
    cache.applyView(freshView);
    const auto initialOutcome = bank.apply(scalarDraft);
    check(initialOutcome.applied && !initialOutcome.materialization.has_value(),
          "the worker rejected the initial scalar draft");
    cache.resolveApplied(VoicegroupEditApplied{identity, std::nullopt}, history);
    check(cache.find(identity) && !cache.find(identity)->dirty,
          "resolveApplied lost the applied view");
    check(stack.count() == 1 && stack.index() == 1 && !stack.canRedo() &&
              history.currentDocumentIdentity() == history.savedDocumentIdentity(),
          "the initial resolution did not push one confirmed bank entry");
    const auto request = history.requestUndo();
    const auto *draft = bankDraft(request);
    check(draft && isSetDraft(*draft, kSlotScalar, before, after),
          "the pushed initial entry did not return the submitted draft");
    check(cache.bankActionsEnabled() && !cache.pendingOrigin().has_value() &&
              cache.closeEnabledFor(tab),
          "the initial resolution did not end the pending transition");

    // Undo: the prepared draft goes through the cache as an Undo transition.
    const auto undoRequest = history.requestUndo();
    const auto *undoDraft = bankDraft(undoRequest);
    check(undoDraft != nullptr, "the scalar entry did not prepare an undo draft");
    const auto undoOutcome = bank.apply(*undoDraft);
    check(undoOutcome.applied, "the worker rejected the undo draft");
    LoadedBankView undoView{identity, {}, QStringLiteral("bank"), false, {}};
    cache.applyView(undoView);
    check(cache.begin(
              PendingBankTransition{identity, tab, PendingBankTransition::Kind::Undo, *undoDraft}),
          "begin refused the undo transition");
    cache.resolveApplied(VoicegroupEditApplied{identity, undoOutcome.materialization}, history);
    check(stack.count() == 1 && stack.index() == 0 && !history.canUndo() && history.canRedo() &&
              cache.bankActionsEnabled(),
          "the undo resolution did not cross the confirmed entry");

    // Redo: the symmetric forward crossing.
    const auto redoRequest = history.requestRedo();
    const auto *redoDraft = bankDraft(redoRequest);
    check(redoDraft != nullptr, "the crossed entry did not prepare a redo draft");
    const auto redoOutcome = bank.apply(*redoDraft);
    check(redoOutcome.applied, "the worker rejected the redo draft");
    check(cache.begin(
              PendingBankTransition{identity, tab, PendingBankTransition::Kind::Redo, *redoDraft}),
          "begin refused the redo transition");
    cache.resolveApplied(VoicegroupEditApplied{identity, redoOutcome.materialization}, history);
    check(stack.index() == 1 && !history.canRedo() && cache.bankActionsEnabled(),
          "the redo resolution did not cross the confirmed entry");

    // An initial conflict leaves the history untouched.
    check(cache.begin(PendingBankTransition{identity, tab, PendingBankTransition::Kind::Initial,
                                            scalarDraft}),
          "begin refused the conflict transition");
    const auto countBeforeInitialConflict = stack.count();
    cache.resolveConflict(VoicegroupEditConflict{identity}, history);
    check(stack.count() == countBeforeInitialConflict && stack.index() == 1 &&
              cache.bankActionsEnabled(),
          "an initial conflict changed history or left the transition pending");

    // A confirmed undo conflict drops the stale entry through the cache.
    const auto conflictUndoRequest = history.requestUndo();
    const auto *conflictUndoDraft = bankDraft(conflictUndoRequest);
    check(conflictUndoDraft != nullptr, "the entry did not prepare a conflict undo draft");
    bank.poke(kSlotScalar, makeVoice(6, 0)); // another tab's edit makes it stale
    check(!bank.apply(*conflictUndoDraft).applied, "the stale undo draft did not conflict");
    check(cache.begin(PendingBankTransition{identity, tab, PendingBankTransition::Kind::Undo,
                                            *conflictUndoDraft}),
          "begin refused the stale undo transition");
    cache.resolveConflict(VoicegroupEditConflict{identity}, history);
    check(stack.count() == 0 && !history.canUndo() && cache.bankActionsEnabled() &&
              history.currentDocumentIdentity() == history.savedDocumentIdentity(),
          "the undo conflict resolution did not drop the stale entry");

    // A confirmed redo conflict drops the stale entry above the index.
    const auto redoStaleVoice = makeVoice(2, 0, QStringLiteral("snd_redo"));
    const auto redoStaleDraft =
        VoicegroupEditInput{identity, setSlot(kSlotStaleRedo, redoStaleVoice, std::nullopt)};
    const auto redoStaleApplied = bank.apply(redoStaleDraft);
    history.pushConfirmedBank(redoStaleDraft, redoStaleApplied.materialization);
    const auto revertRequest = history.requestUndo();
    const auto *revertDraft = bankDraft(revertRequest);
    const auto revertOutcome = bank.apply(*revertDraft);
    check(revertOutcome.applied, "the fresh revert conflicted");
    history.crossConfirmedBankUndo(revertOutcome.materialization);
    bank.rematerialize(kSlotStaleRedo, redoStaleVoice);
    const auto staleRedoRequest = history.requestRedo();
    const auto *staleRedoDraft = bankDraft(staleRedoRequest);
    check(staleRedoDraft && !bank.apply(*staleRedoDraft).applied,
          "the stale redo draft did not conflict");
    check(cache.begin(PendingBankTransition{identity, tab, PendingBankTransition::Kind::Redo,
                                            *staleRedoDraft}),
          "begin refused the stale redo transition");
    cache.resolveConflict(VoicegroupEditConflict{identity}, history);
    check(stack.count() == 0 && !history.canRedo() && cache.bankActionsEnabled(),
          "the redo conflict resolution did not drop the stale entry");

    // A hard error clears the transition without touching history.
    history.pushConfirmedBank(scalarDraft, std::nullopt);
    check(cache.begin(
              PendingBankTransition{identity, tab, PendingBankTransition::Kind::Undo, scalarDraft}),
          "begin refused the hard-error transition");
    VoicegroupMutationFailed otherFailure{otherIdentity, QStringLiteral("other boom")};
    cache.resolveHardError(otherFailure);
    check(cache.pendingOrigin().has_value() && stack.count() == 1 && history.canUndo(),
          "a mismatched hard error cleared the pending transition");
    cache.resolveHardError(VoicegroupMutationFailed{identity, QStringLiteral("boom")});
    check(stack.count() == 1 && stack.index() == 1 && history.canUndo() &&
              cache.bankActionsEnabled() && !cache.pendingOrigin().has_value(),
          "the hard error did not leave the history index fixed with the transition cleared");

    // clear() resets both owned stores.
    cache.applyView(freshView);
    cache.clear();
    check(cache.find(identity) == nullptr && !cache.pendingOrigin().has_value() &&
              cache.bankActionsEnabled() && cache.closeEnabledFor(tab),
          "clear did not reset the owned stores");

    return failures;
}

} // namespace

int runVoicegroupViewCacheCheck()
{
    auto failures = checkBankHistoryContracts();
    failures += checkBankMergeContracts();
    failures += checkViewCacheContracts();
    if (failures == 0)
        std::printf("voicegroupviewcachecheck: PASS\n");
    return failures;
}
