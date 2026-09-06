#include <array>
#include <optional>
#include <variant>

#include <QStringList>
#include <QUndoCommand>
#include <QUndoStack>
#include <QtTest>

#include "core/songhistory.h"
#include "project/projectidentity.h"
#include "project/voicegroupsource.h"
#include "ui/voicegroupviewcache.h"

namespace {
constexpr int kScalarSlot = 3;
constexpr int kBlankSlot = 4;
constexpr int kStaleUndoSlot = 5;
constexpr int kStaleRedoSlot = 6;
constexpr int kMergeSlot = 2;

VgVoice voice(int duty, int attack, const QString &symbol = QStringLiteral("snd_a"))
{
    VgVoice value;
    value.duty = duty;
    value.attack = attack;
    value.symbol = symbol;
    return value;
}
SetVoicegroupSlot setSlot(int slot, const VgVoice &value, const std::optional<VgVoice> &expected)
{
    return {slot, value, expected};
}
std::optional<VoicegroupEditInput> draft(HistoryRequest request)
{
    if (auto *const input = std::get_if<VoicegroupEditInput>(&request))
        return std::move(*input);
    return std::nullopt;
}
bool isSet(const VoicegroupEditInput &input, int slot, const VgVoice &value,
           const std::optional<VgVoice> &expected)
{
    const auto *const set = std::get_if<SetVoicegroupSlot>(&input.operation);
    return set && set->slot == slot && set->value == value && set->expected == expected;
}

// No-host worker double for coordinator/history state rules. The bank worker
// Qt suite separately proves its materialization token against real source bytes.
class FakeBank final
{
  public:
    struct Outcome {
        bool applied = false;
        std::optional<VoicegroupSource::BlankSlotMaterialization> token;
    };
    void put(int slot, VgVoice value) { m_slots[slot] = std::move(value); }
    void rematerialize(int slot, VgVoice value)
    {
        m_slots[slot] = std::move(value);
        m_token = token(slot);
    }
    Outcome apply(const VoicegroupEditInput &input)
    {
        if (const auto *const set = std::get_if<SetVoicegroupSlot>(&input.operation)) {
            if (set->slot < 0 || set->slot >= int(m_slots.size()) ||
                m_slots[set->slot].has_value() != set->expected.has_value() ||
                (set->expected && *set->expected != *m_slots[set->slot]))
                return {};
            m_slots[set->slot] = set->value;
            if (set->expected)
                return {true, {}};
            m_token = token(set->slot);
            return {true, m_token};
        }
        const auto *const revert = std::get_if<RevertBlankSlot>(&input.operation);
        if (!revert || !m_token || revert->materialization.headerAfter != m_token->headerAfter)
            return {};
        m_slots[revert->materialization.firstAddedSlot].reset();
        m_token.reset();
        return {true, {}};
    }

  private:
    VoicegroupSource::BlankSlotMaterialization token(int slot)
    {
        VoicegroupSource::BlankSlotMaterialization result;
        result.firstAddedSlot = slot;
        result.addedLines = {QByteArrayLiteral("generated")};
        result.headerAfter = QByteArray::number(++m_counter);
        return result;
    }
    std::array<std::optional<VgVoice>, 8> m_slots;
    std::optional<VoicegroupSource::BlankSlotMaterialization> m_token;
    int m_counter = 0;
};

class CountCommand final : public QUndoCommand
{
  public:
    explicit CountCommand(int *value) : m_value(value) {}
    int id() const override { return 0x6463; }
    void redo() override { ++*m_value; }
    void undo() override { --*m_value; }

  private:
    int *m_value;
};

class VoicegroupViewCacheTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(VoicegroupViewCacheTest)
  public:
    VoicegroupViewCacheTest() = default;

  private slots:
    void historyLifecycleAndStaleTransitions();
    void mergeRules();
    void coordinatorRoutesTransitionsAndGates();
};

void VoicegroupViewCacheTest::historyLifecycleAndStaleTransitions()
{
    const auto identity =
        VoicegroupId::create(QStringLiteral("sound/voicegroups/bank.inc"), QString());
    QVERIFY(identity);
    QUndoStack stack;
    SongHistory history(stack);
    int document = 0;
    FakeBank bank;
    QVERIFY(!history.canUndo() && !history.canRedo());
    history.pushDocument(std::make_unique<CountCommand>(&document));
    const auto afterDocument = history.currentDocumentIdentity();
    const auto savedDocument = history.savedDocumentIdentity();
    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(history.requestUndo()));
    QCOMPARE(document, 0);
    QCOMPARE(history.currentDocumentIdentity(), history.savedDocumentIdentity());
    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(history.requestRedo()));
    QCOMPARE(document, 1);

    const VgVoice before = voice(2, 0);
    const VgVoice after = voice(5, 0);
    bank.put(kScalarSlot, before);
    const VoicegroupEditInput scalar{*identity, setSlot(kScalarSlot, after, before)};
    QVERIFY(bank.apply(scalar).applied);
    history.pushConfirmedBank(scalar, {});
    QCOMPARE(stack.count(), 2);
    QCOMPARE(history.currentDocumentIdentity(), afterDocument);
    std::optional<VoicegroupEditInput> undo = draft(history.requestUndo());
    QVERIFY(undo && isSet(*undo, kScalarSlot, before, after));
    QVERIFY(bank.apply(*undo).applied);
    history.crossConfirmedBankUndo({});
    QCOMPARE(stack.index(), 1);
    std::optional<VoicegroupEditInput> redo = draft(history.requestRedo());
    QVERIFY(redo && isSet(*redo, kScalarSlot, after, before));
    QVERIFY(bank.apply(*redo).applied);
    history.crossConfirmedBankRedo({});
    QCOMPARE(stack.index(), 2);

    const VgVoice blank = voice(2, 0, QStringLiteral("snd_new"));
    const VoicegroupEditInput blankInput{*identity, setSlot(kBlankSlot, blank, std::nullopt)};
    const FakeBank::Outcome first = bank.apply(blankInput);
    QVERIFY(first.applied && first.token);
    history.pushConfirmedBank(blankInput, *first.token);
    undo = draft(history.requestUndo());
    QVERIFY(undo && std::holds_alternative<RevertBlankSlot>(undo->operation));
    QVERIFY(bank.apply(*undo).applied);
    history.crossConfirmedBankUndo({});
    redo = draft(history.requestRedo());
    QVERIFY(redo && isSet(*redo, kBlankSlot, blank, std::nullopt));
    const FakeBank::Outcome fresh = bank.apply(*redo);
    QVERIFY(fresh.applied && fresh.token && fresh.token->headerAfter != first.token->headerAfter);
    history.crossConfirmedBankRedo(fresh.token);

    const VoicegroupEditInput staleUndo{
        *identity, setSlot(kStaleUndoSlot, voice(2, 0, QStringLiteral("stale")), std::nullopt)};
    const FakeBank::Outcome staleApplied = bank.apply(staleUndo);
    QVERIFY(staleApplied.applied && staleApplied.token);
    history.pushConfirmedBank(staleUndo, *staleApplied.token);
    bank.rematerialize(kStaleUndoSlot, voice(2, 0, QStringLiteral("stale")));
    undo = draft(history.requestUndo());
    QVERIFY(undo && !bank.apply(*undo).applied);
    const int undoCount = stack.count();
    history.resolveBankUndoConflict();
    QCOMPARE(stack.count(), undoCount - 1);
    QVERIFY(history.canUndo() && !history.canRedo());
    QCOMPARE(history.currentDocumentIdentity(), afterDocument);
    QCOMPARE(history.savedDocumentIdentity(), savedDocument);

    const VoicegroupEditInput staleRedo{
        *identity, setSlot(kStaleRedoSlot, voice(2, 0, QStringLiteral("redo")), std::nullopt)};
    const FakeBank::Outcome redoApplied = bank.apply(staleRedo);
    QVERIFY(redoApplied.applied && redoApplied.token);
    history.pushConfirmedBank(staleRedo, *redoApplied.token);
    undo = draft(history.requestUndo());
    QVERIFY(undo && bank.apply(*undo).applied);
    history.crossConfirmedBankUndo({});
    bank.rematerialize(kStaleRedoSlot, voice(2, 0, QStringLiteral("redo")));
    redo = draft(history.requestRedo());
    QVERIFY(redo && !bank.apply(*redo).applied);
    const int redoCount = stack.count();
    history.resolveBankRedoConflict();
    QCOMPARE(stack.count(), redoCount - 1);
    QVERIFY(!history.canRedo());
}

void VoicegroupViewCacheTest::mergeRules()
{
    const auto identity =
        VoicegroupId::create(QStringLiteral("sound/voicegroups/bank.inc"), QString());
    QVERIFY(identity);
    const VgVoice first = voice(2, 0), second = voice(5, 0), third = voice(7, 0),
                  attack = voice(2, 3), structural = voice(2, 0, QStringLiteral("snd_b"));
    {
        QUndoStack stack;
        SongHistory history(stack);
        history.pushConfirmedBank({*identity, setSlot(kMergeSlot, second, first)}, {});
        history.pushConfirmedBank({*identity, setSlot(kMergeSlot, third, second)}, {});
        QCOMPARE(stack.count(), 1);
        const std::optional<VoicegroupEditInput> undo = draft(history.requestUndo());
        QVERIFY(undo && isSet(*undo, kMergeSlot, first, third));
    }
    {
        QUndoStack stack;
        SongHistory history(stack);
        history.pushConfirmedBank({*identity, setSlot(kMergeSlot, second, first)}, {});
        history.pushConfirmedBank({*identity, setSlot(kMergeSlot, first, second)}, {});
        QCOMPARE(stack.count(), 0);
    }
    {
        QUndoStack stack;
        SongHistory history(stack);
        history.pushConfirmedBank({*identity, setSlot(kMergeSlot, second, std::nullopt)},
                                  VoicegroupSource::BlankSlotMaterialization{});
        history.pushConfirmedBank({*identity, setSlot(kMergeSlot, third, second)}, {});
        history.pushConfirmedBank({*identity, setSlot(kMergeSlot + 1, third, first)}, {});
        history.pushConfirmedBank({*identity, setSlot(kMergeSlot, attack, first)}, {});
        history.pushConfirmedBank({*identity, setSlot(kMergeSlot, structural, first)}, {});
        QCOMPARE(stack.count(), 5);
    }
    {
        QUndoStack stack;
        SongHistory history(stack);
        history.pushConfirmedBank({*identity, setSlot(kMergeSlot, second, first)}, {});
        history.markDocumentSaved(history.currentDocumentIdentity());
        history.pushConfirmedBank({*identity, setSlot(kMergeSlot, third, second)}, {});
        QCOMPARE(stack.count(), 1);
        history.sealBankMerge();
        history.pushConfirmedBank({*identity, setSlot(kMergeSlot, second, third)}, {});
        QCOMPARE(stack.count(), 2);
    }
}

void VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates()
{
    const auto identity =
        VoicegroupId::create(QStringLiteral("sound/voicegroups/bank.inc"), QString());
    const auto other =
        VoicegroupId::create(QStringLiteral("sound/voicegroups/other.inc"), QString());
    const auto tab = SongName::create(QStringLiteral("banktab"));
    const auto otherTab = SongName::create(QStringLiteral("othertab"));
    QVERIFY(identity && other && tab && otherTab);
    QUndoStack stack;
    SongHistory history(stack);
    VoicegroupViewCache cache;
    const VgVoice before = voice(2, 0), after = voice(5, 0);
    const VoicegroupEditInput input{*identity, setSlot(kScalarSlot, after, before)};
    QVERIFY(cache.find(*identity) == nullptr && cache.bankActionsEnabled() &&
            cache.closeEnabledFor(*tab));
    LoadedBankView view{*identity, {}, QStringLiteral("bank"), true, {}};
    cache.applyView(view);
    QVERIFY(cache.find(*identity) && cache.find(*identity)->dirty);
    view.dirty = false;
    cache.applyView(view);
    QVERIFY(!cache.find(*identity)->dirty);
    QVERIFY(cache.begin({*identity, *tab, PendingBankTransition::Kind::Initial, input}));
    QVERIFY(!cache.begin({*identity, *otherTab, PendingBankTransition::Kind::Undo, input}));
    QVERIFY(!cache.bankActionsEnabled() && cache.pendingOrigin() == *tab &&
            !cache.closeEnabledFor(*tab) && cache.closeEnabledFor(*otherTab));
    cache.resolveConflict({*other}, history);
    cache.resolveApplied({*other, std::nullopt}, history);
    QVERIFY(cache.pendingOrigin());
    cache.resolveApplied({*identity, std::nullopt}, history);
    QCOMPARE(stack.count(), 1);
    QVERIFY(cache.bankActionsEnabled() && !cache.pendingOrigin());

    std::optional<VoicegroupEditInput> undo = draft(history.requestUndo());
    QVERIFY(undo);
    QVERIFY(cache.begin({*identity, *tab, PendingBankTransition::Kind::Undo, *undo}));
    cache.resolveApplied({*identity, std::nullopt}, history);
    QCOMPARE(stack.index(), 0);
    std::optional<VoicegroupEditInput> redo = draft(history.requestRedo());
    QVERIFY(redo);
    QVERIFY(cache.begin({*identity, *tab, PendingBankTransition::Kind::Redo, *redo}));
    cache.resolveApplied({*identity, std::nullopt}, history);
    QCOMPARE(stack.index(), 1);
    QVERIFY(cache.begin({*identity, *tab, PendingBankTransition::Kind::Initial, input}));
    cache.resolveConflict({*identity}, history);
    QCOMPARE(stack.index(), 1);
    const std::optional<VoicegroupEditInput> staleUndo = draft(history.requestUndo());
    QVERIFY(staleUndo);
    QVERIFY(cache.begin({*identity, *tab, PendingBankTransition::Kind::Undo, *staleUndo}));
    cache.resolveConflict({*identity}, history);
    QCOMPARE(stack.count(), 0);
    QVERIFY(!history.canUndo());
    history.pushConfirmedBank(input, {});
    const std::optional<VoicegroupEditInput> revert = draft(history.requestUndo());
    QVERIFY(revert);
    history.crossConfirmedBankUndo({});
    const std::optional<VoicegroupEditInput> staleRedo = draft(history.requestRedo());
    QVERIFY(staleRedo);
    QVERIFY(cache.begin({*identity, *tab, PendingBankTransition::Kind::Redo, *staleRedo}));
    cache.resolveConflict({*identity}, history);
    QCOMPARE(stack.count(), 0);
    QVERIFY(!history.canRedo());
    QVERIFY(cache.begin({*identity, *tab, PendingBankTransition::Kind::Undo, input}));
    cache.resolveHardError({*other, QStringLiteral("other")});
    QVERIFY(cache.pendingOrigin());
    cache.resolveHardError({*identity, QStringLiteral("boom")});
    QVERIFY(cache.bankActionsEnabled() && !cache.pendingOrigin());
    cache.clear();
    QVERIFY(cache.find(*identity) == nullptr && cache.bankActionsEnabled() &&
            cache.closeEnabledFor(*tab));
}
} // namespace

int runVoicegroupViewCacheCheck(const QStringList &qtArguments)
{
    VoicegroupViewCacheTest test;
    QStringList arguments{QStringLiteral("voicegroup-view-cache")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "tst_voicegroupviewcache.moc"
