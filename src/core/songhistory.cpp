#include "core/songhistory.h"

#include <QObject>

#include <cassert>
#include <utility>

namespace {

// QUndoStack only offers the adjacent top to mergeWith() when both ids are
// nonnegative and equal. Shared-bank entries merge only with each other and
// only under the scalar rules implemented by changedFieldMask below: same
// voicegroup and slot, neither side materializes a blank slot, and both touch
// the same changed-field mask.
constexpr int kSharedBankMergeId = 0x6261; // 'ba'

uint changedFieldMask(const VgVoice &a, const VgVoice &b)
{
    uint mask = 0;
    mask |= uint(a.macro != b.macro) << 0;
    mask |= uint(a.key != b.key) << 1;
    mask |= uint(a.pan != b.pan) << 2;
    mask |= uint(a.symbol != b.symbol) << 3;
    mask |= uint(a.keysplitTable != b.keysplitTable) << 4;
    mask |= uint(a.sweep != b.sweep) << 5;
    mask |= uint(a.duty != b.duty) << 6;
    mask |= uint(a.period != b.period) << 7;
    mask |= uint(a.attack != b.attack) << 8;
    mask |= uint(a.decay != b.decay) << 9;
    mask |= uint(a.sustain != b.sustain) << 10;
    mask |= uint(a.release != b.release) << 11;
    return mask;
}

} // namespace

class SongHistory::Entry final : public QUndoCommand
{
  public:
    Entry(DocumentStateIdentity before, SongHistory *history, std::unique_ptr<QUndoCommand> inner)
        : QUndoCommand(inner->text())
        , m_kind(HistoryKind::Document)
        , m_before(before)
        , m_after(history->mintIdentity())
        , m_history(history)
        , m_inner(std::move(inner))
    {}

    // A confirmed bank entry records the draft the worker applied and the
    // document identity the bank transition preserved. Both callbacks stay
    // inert for the entry's whole life: every bank mutation is performed by
    // the worker before this entry is pushed or crossed.
    Entry(DocumentStateIdentity identity, SongHistory *history, VoicegroupEditInput draft,
          std::optional<VoicegroupSource::BlankSlotMaterialization> materialization)
        : QUndoCommand(QObject::tr("voicegroup bank edit"))
        , m_kind(HistoryKind::SharedBank)
        , m_before(identity)
        , m_after(identity)
        , m_history(history)
        , m_draft(std::move(draft))
        , m_materialization(std::move(materialization))
    {}

    HistoryKind kind() const { return m_kind; }
    DocumentStateIdentity after() const { return m_after; }
    const VoicegroupEditInput &draft() const { return *m_draft; }
    const std::optional<VoicegroupSource::BlankSlotMaterialization> &materialization() const
    {
        return m_materialization;
    }

    // The exact draft that reverts this entry: a live blank token becomes a
    // revert, a scalar edit becomes the swapped set. The worker is the only
    // validator; the index moves only on the typed confirmation.
    VoicegroupEditInput undoDraft() const
    {
        if (m_materialization)
            return VoicegroupEditInput{m_draft->id, RevertBlankSlot{*m_materialization}};
        const auto &set = std::get<SetVoicegroupSlot>(m_draft->operation);
        return VoicegroupEditInput{m_draft->id,
                                   SetVoicegroupSlot{set.slot, *set.expected, set.value}};
    }

    void replaceMaterialization(
        std::optional<VoicegroupSource::BlankSlotMaterialization> materialization)
    {
        m_materialization = std::move(materialization);
    }

    void clearMaterialization() { m_materialization.reset(); }
    void sealMerge() { m_mergeable = false; }

    void undo() override
    {
        if (m_inner)
            m_inner->undo();
    }

    void redo() override
    {
        if (m_inner)
            m_inner->redo();
    }

    int id() const override
    {
        if (m_kind == HistoryKind::SharedBank)
            return m_materialization ? -1 : kSharedBankMergeId;
        return m_inner->id();
    }

    bool mergeWith(const QUndoCommand *other) override
    {
        const auto *entry = dynamic_cast<const Entry *>(other);
        if (!entry || entry->m_kind != m_kind)
            return false;
        if (m_kind == HistoryKind::SharedBank)
            return mergeBank(*entry);
        if (m_history->savedDocumentIdentity() == m_after)
            return false;
        if (!m_inner->mergeWith(entry->m_inner.get()))
            return false;
        m_after = DocumentStateIdentity(m_history->mintIdentity());
        setObsolete(m_inner->isObsolete());
        return true;
    }

  private:
    // Scalar bank merge: keep the oldest before, adopt the newest value, and
    // mark a self-cancelling pair obsolete so push() drops the entry.
    bool mergeBank(const Entry &incoming)
    {
        if (!m_mergeable)
            return false;
        if (m_materialization || incoming.m_materialization)
            return false;
        if (!(m_draft->id == incoming.m_draft->id))
            return false;
        auto *mine = std::get_if<SetVoicegroupSlot>(&m_draft->operation);
        const auto *theirs = std::get_if<SetVoicegroupSlot>(&incoming.m_draft->operation);
        if (!mine || !theirs || !mine->expected || !theirs->expected || mine->slot != theirs->slot)
            return false;
        if (changedFieldMask(*mine->expected, mine->value) !=
            changedFieldMask(*theirs->expected, theirs->value))
            return false;
        mine->value = theirs->value;
        setObsolete(*mine->expected == mine->value);
        return true;
    }

    HistoryKind m_kind;
    DocumentStateIdentity m_before;
    DocumentStateIdentity m_after;
    SongHistory *m_history = nullptr;
    std::unique_ptr<QUndoCommand> m_inner;
    std::optional<VoicegroupEditInput> m_draft;
    std::optional<VoicegroupSource::BlankSlotMaterialization> m_materialization;
    bool m_mergeable = true;
};

SongHistory::SongHistory(QUndoStack &stack)
    : m_stack(stack)
    , m_baseIdentity(mintIdentity())
    , m_savedIdentity(m_baseIdentity)
{}

bool SongHistory::canUndo() const
{
    return m_stack.canUndo();
}

bool SongHistory::canRedo() const
{
    return m_stack.canRedo();
}

DocumentStateIdentity SongHistory::currentDocumentIdentity() const
{
    // The entry just below the index carries the state the document is in;
    // below the first entry (or under a raw QUndoStack push) it is the base.
    if (const auto *entry = dynamic_cast<const Entry *>(m_stack.command(m_stack.index() - 1)))
        return entry->after();
    return m_baseIdentity;
}

DocumentStateIdentity SongHistory::savedDocumentIdentity() const
{
    return m_savedIdentity;
}

void SongHistory::markDocumentSaved(DocumentStateIdentity identity)
{
    m_savedIdentity = identity;
}

void SongHistory::sealBankMerge()
{
    if (auto *entry = entryAt(m_stack.index() - 1);
        entry && entry->kind() == HistoryKind::SharedBank)
        entry->sealMerge();
}

HistoryRequest SongHistory::requestUndo()
{
    assert(m_stack.canUndo());
    if (auto *entry = entryAt(m_stack.index() - 1)) {
        if (entry->kind() == HistoryKind::SharedBank)
            return entry->undoDraft();
        m_stack.undo();
    }
    return DocumentHistoryApplied{};
}

HistoryRequest SongHistory::requestRedo()
{
    assert(m_stack.canRedo());
    if (auto *entry = entryAt(m_stack.index())) {
        if (entry->kind() == HistoryKind::SharedBank)
            return entry->draft();
        m_stack.redo();
    }
    return DocumentHistoryApplied{};
}

void SongHistory::pushConfirmedBank(
    VoicegroupEditInput draft,
    std::optional<VoicegroupSource::BlankSlotMaterialization> materialization)
{
    // The worker already applied this transition, so the entry is pushed with
    // the index past it and its first (armed) redo is inert. A bank entry
    // preserves the current document identity.
    const auto identity = currentDocumentIdentity();
    m_stack.push(new Entry(identity, this, std::move(draft), std::move(materialization)));
}

void SongHistory::crossConfirmedBankUndo(
    std::optional<VoicegroupSource::BlankSlotMaterialization> materialization)
{
    auto *entry = entryAt(m_stack.index() - 1);
    assert(entry && entry->kind() == HistoryKind::SharedBank);
    if (!entry || entry->kind() != HistoryKind::SharedBank)
        return;
    if (entry->materialization())
        entry->clearMaterialization(); // the confirmed revert consumed the live token
    m_stack.undo();                    // crosses the armed inert callback
}

void SongHistory::crossConfirmedBankRedo(
    std::optional<VoicegroupSource::BlankSlotMaterialization> materialization)
{
    auto *entry = entryAt(m_stack.index());
    assert(entry && entry->kind() == HistoryKind::SharedBank);
    if (!entry || entry->kind() != HistoryKind::SharedBank)
        return;
    entry->replaceMaterialization(std::move(materialization)); // a blank redo mints a fresh token
    m_stack.redo();                                            // crosses the armed inert callback
}

void SongHistory::resolveBankUndoConflict()
{
    auto *entry = entryAt(m_stack.index() - 1);
    assert(entry && entry->kind() == HistoryKind::SharedBank);
    if (!entry || entry->kind() != HistoryKind::SharedBank)
        return;
    // The stale entry can never be reverted faithfully: obsoleting it makes
    // the crossing drop it from the stack without invoking its callback.
    entry->setObsolete(true);
    m_stack.undo();
}

void SongHistory::resolveBankRedoConflict()
{
    auto *entry = entryAt(m_stack.index());
    assert(entry && entry->kind() == HistoryKind::SharedBank);
    if (!entry || entry->kind() != HistoryKind::SharedBank)
        return;
    entry->setObsolete(true);
    m_stack.redo();
}

void SongHistory::pushDocument(std::unique_ptr<QUndoCommand> command)
{
    m_stack.push(new Entry(currentDocumentIdentity(), this, std::move(command)));
}

void SongHistory::clear()
{
    m_stack.clear();
    m_savedIdentity = m_baseIdentity;
}

uint64_t SongHistory::mintIdentity()
{
    return m_nextIdentity++;
}

SongHistory::Entry *SongHistory::entryAt(int index) const
{
    if (index < 0 || index >= m_stack.count())
        return nullptr;
    // The stack owns non-const commands; songhistory minted every one of them.
    return const_cast<Entry *>(dynamic_cast<const Entry *>(m_stack.command(index)));
}
