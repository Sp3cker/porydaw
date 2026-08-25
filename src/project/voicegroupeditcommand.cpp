#include "voicegroupeditcommand.h"

#include <QObject>
#include <QUndoStack>

#include <optional>
#include <utility>

// Voicegroup-specific undo mechanics live here so MainWindow only requests an
// edit and reacts after it is applied. Commands retain the session-stable
// holder, never a replaceable VoicegroupSource address.
namespace {
// QUndoStack only offers adjacent commands to mergeWith() when their nonnegative
// IDs match. mergeWith() still verifies the concrete command and edit target.
constexpr int kExistingVoiceValueMergeId = 0x7661; // 'va'

class ExistingVoiceValueEditCommand final : public QUndoCommand
{
  public:
    ExistingVoiceValueEditCommand(VoicegroupSourceHolder &target, QString loadName, int slot,
                                  const VgVoice &before, const VgVoice &after, bool structural,
                                  VoicegroupEditApplied applied)
        : QUndoCommand(QObject::tr("edit voice %1").arg(slot))
        , m_target(&target)
        , m_loadName(std::move(loadName))
        , m_slot(slot)
        , m_before(before)
        , m_after(after)
        , m_structural(structural)
        , m_applied(std::move(applied))
    {}

    int id() const override { return kExistingVoiceValueMergeId; }

    bool mergeWith(const QUndoCommand *other) override
    {
        const auto *edit = dynamic_cast<const ExistingVoiceValueEditCommand *>(other);
        if (!edit || edit->m_target != m_target || edit->m_loadName != m_loadName ||
            edit->m_slot != m_slot || m_structural || edit->m_structural ||
            changedFieldMask(edit->m_before, edit->m_after) != changedFieldMask(m_before, m_after))
            return false;
        m_after = edit->m_after;
        if (m_after == m_before)
            setObsolete(true);
        return true;
    }

    void redo() override
    {
        VoicegroupSource *source = m_target->resolve(m_loadName);
        if (!source)
            return;
        if (!source->setVoice(m_slot, m_after)) {
            setObsolete(true);
            return;
        }
        notifyApplied(*source);
    }

    void undo() override
    {
        VoicegroupSource *source = m_target->resolve(m_loadName);
        if (source && source->setVoice(m_slot, m_before))
            notifyApplied(*source);
    }

    void reapplyToReopenedSource(VoicegroupSourceHolder &target) const
    {
        if (isObsolete() || m_target != &target)
            return;
        VoicegroupSource *source = m_target->resolve(m_loadName);
        if (source)
            source->setVoice(m_slot, m_after);
    }

  private:
    void notifyApplied(VoicegroupSource &source) const
    {
        if (m_applied)
            m_applied(source, m_slot, m_structural);
    }

    static uint changedFieldMask(const VgVoice &a, const VgVoice &b)
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

    VoicegroupSourceHolder *const m_target;
    const QString m_loadName;
    int m_slot;
    VgVoice m_before;
    VgVoice m_after;
    bool m_structural;
    VoicegroupEditApplied m_applied;
};

class BlankSlotMaterializationCommand final : public QUndoCommand
{
  public:
    BlankSlotMaterializationCommand(VoicegroupSourceHolder &target, QString loadName, int slot,
                                    const VgVoice &after, VoicegroupEditApplied applied)
        : QUndoCommand(QObject::tr("edit voice %1").arg(slot))
        , m_target(&target)
        , m_loadName(std::move(loadName))
        , m_slot(slot)
        , m_after(after)
        , m_applied(std::move(applied))
    {}

    void redo() override
    {
        VoicegroupSource *source = m_target->resolve(m_loadName);
        if (!source)
            return;
        std::optional<VoicegroupSource::BlankSlotMaterialization> materialization =
            source->materializeBlankSlot(m_slot, m_after);
        if (!materialization) {
            setObsolete(true);
            return;
        }
        m_materialization = std::move(materialization);
        notifyApplied(*source);
    }

    void undo() override
    {
        VoicegroupSource *source = m_target->resolve(m_loadName);
        if (!source || !m_materialization ||
            !source->revertBlankSlotMaterialization(*m_materialization))
            return;
        m_materialization.reset();
        notifyApplied(*source);
    }

    void reapplyToReopenedSource(VoicegroupSourceHolder &target)
    {
        if (isObsolete() || m_target != &target)
            return;
        VoicegroupSource *source = m_target->resolve(m_loadName);
        if (!source)
            return;

        // Reopening creates a new structural generation. Refresh this command's
        // token so a later undo removes the exact insertion in the current source.

        m_materialization.reset();
        if (source->kindAt(m_slot) == VgLineKind::None)
            m_materialization = source->materializeBlankSlot(m_slot, m_after);
    }

  private:
    void notifyApplied(VoicegroupSource &source) const
    {
        if (m_applied)
            m_applied(source, m_slot, true);
    }

    VoicegroupSourceHolder *const m_target;
    const QString m_loadName;
    int m_slot;
    VgVoice m_after;
    std::optional<VoicegroupSource::BlankSlotMaterialization> m_materialization;
    VoicegroupEditApplied m_applied;
};
} // namespace

std::unique_ptr<QUndoCommand> makeUndoableVoicegroupEdit(VoicegroupSourceHolder &target, int slot,
                                                         const VgVoice &voice, bool structural,
                                                         VoicegroupEditApplied applied)
{
    VoicegroupSource *source = target.get();
    if (!source || slot < 0 || slot >= VOICEGROUP_SIZE)
        return nullptr;
    if (source->kindAt(slot) == VgLineKind::Editable) {
        const VgVoice *before = source->voiceAt(slot);
        if (!before || *before == voice)
            return nullptr;
        return std::make_unique<ExistingVoiceValueEditCommand>(
            target, source->loadName(), slot, *before, voice, structural, std::move(applied));
    }
    if (source->kindAt(slot) != VgLineKind::None)
        return nullptr;
    return std::make_unique<BlankSlotMaterializationCommand>(target, source->loadName(), slot,
                                                             voice, std::move(applied));
}

void reapplyVoicegroupEditsToReopenedSource(const QUndoStack &undoStack,
                                            VoicegroupSourceHolder &target)
{
    for (int i = 0; i < undoStack.index(); i++) {
        const QUndoCommand *command = undoStack.command(i);
        if (const auto *valueEdit = dynamic_cast<const ExistingVoiceValueEditCommand *>(command)) {
            valueEdit->reapplyToReopenedSource(target);
        } else if (const auto *blankEdit =
                       dynamic_cast<const BlankSlotMaterializationCommand *>(command)) {
            // QUndoStack::command() exposes only a const command pointer. Structural
            // replay must update this command's current-generation materialization
            // token so a later undo can safely revert the insertion it just applied.
            const_cast<BlankSlotMaterializationCommand *>(blankEdit)->reapplyToReopenedSource(
                target);
        }
    }
}
