#include "voicegroupeditcommand.h"

#include "songsession.h"

#include <QByteArray>
#include <QObject>
#include <QUndoStack>
#include <optional>

#include <utility>

// Voicegroup-specific undo mechanics live here so MainWindow only requests an
// edit and reacts after it is applied; source snapshots never leak into UI code.
namespace {
// QUndoStack only offers adjacent commands to mergeWith() when their nonnegative
// IDs match. mergeWith() still verifies the concrete command and edit target.
constexpr int kExistingVoiceValueMergeId = 0x7661; // 'va'

VoicegroupSource *openTargetSource(SongSession &session, const QString &loadName)
{
    if (!session.vgSource || session.vgSource->loadName() != loadName)
        return nullptr;
    return session.vgSource.get();
}

class ExistingVoiceValueEditCommand final : public QUndoCommand
{
  public:
    ExistingVoiceValueEditCommand(SongSession &session, int slot, const VgVoice &before,
                                  const VgVoice &after, bool structural,
                                  VoicegroupEditApplied applied)
        : QUndoCommand(QObject::tr("edit voice %1").arg(slot))
        , m_session(&session)
        , m_loadName(session.vgSource->loadName())
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
        if (!edit || edit->m_session != m_session || edit->m_loadName != m_loadName ||
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
        if (!applyValueToOpenSource(m_after))
            setObsolete(true);
    }

    void undo() override { applyValueToOpenSource(m_before); }

    void reapplyToReopenedSource(SongSession &session) const
    {
        if (isObsolete())
            return;
        auto *source = openTargetSource(session, m_loadName);
        if (source)
            source->setVoice(m_slot, m_after);
    }

  private:
    bool applyValueToOpenSource(const VgVoice &voice)
    {
        auto *source = openTargetSource(*m_session, m_loadName);
        if (!source)
            return true; // reapplyVoicegroupEditsToReopenedSource handles reopened targets
        if (!source->setVoice(m_slot, voice))
            return false;
        if (m_applied)
            m_applied(*m_session, m_slot, m_structural);
        return true;
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

    SongSession *m_session;
    QString m_loadName;
    int m_slot;
    VgVoice m_before;
    VgVoice m_after;
    bool m_structural;
    VoicegroupEditApplied m_applied;
};

class BlankSlotMaterializationCommand final : public QUndoCommand
{
  public:
    BlankSlotMaterializationCommand(SongSession &session, int slot, const VgVoice &after,
                                    QByteArray beforeSource, VoicegroupEditApplied applied)
        : QUndoCommand(QObject::tr("edit voice %1").arg(slot))
        , m_session(&session)
        , m_loadName(session.vgSource->loadName())
        , m_slot(slot)
        , m_after(after)
        , m_beforeSource(std::move(beforeSource))
        , m_applied(std::move(applied))
    {}

    void redo() override
    {
        if (m_afterSource) {
            restoreSnapshotToOpenSource(*m_afterSource);
            return;
        }
        auto *source = openTargetSource(*m_session, m_loadName);
        if (!source)
            return; // stale target; retry if this command is redone on its source
        if (!source->setVoice(m_slot, m_after)) {
            setObsolete(true);
            return;
        }
        m_afterSource = source->sourceBytes();
        if (m_applied)
            m_applied(*m_session, m_slot, true);
    }

    void undo() override { restoreSnapshotToOpenSource(m_beforeSource); }

    void reapplyToReopenedSource(SongSession &session) const
    {
        if (isObsolete() || !m_afterSource)
            return;
        auto *source = openTargetSource(session, m_loadName);
        if (source)
            source->restoreSourceBytes(*m_afterSource);
    }

  private:
    void restoreSnapshotToOpenSource(const QByteArray &sourceBytes)
    {
        auto *source = openTargetSource(*m_session, m_loadName);
        if (!source || !source->restoreSourceBytes(sourceBytes))
            return;
        if (m_applied)
            m_applied(*m_session, m_slot, true);
    }

    SongSession *m_session;
    QString m_loadName;
    int m_slot;
    VgVoice m_after;
    QByteArray m_beforeSource;
    std::optional<QByteArray> m_afterSource;
    VoicegroupEditApplied m_applied;
};
} // namespace

std::unique_ptr<QUndoCommand> makeUndoableVoicegroupEdit(SongSession &session, int slot,
                                                         const VgVoice &voice, bool structural,
                                                         VoicegroupEditApplied applied)
{
    if (!session.vgSource || slot < 0 || slot >= VOICEGROUP_SIZE)
        return nullptr;
    if (session.vgSource->kindAt(slot) == VgLineKind::Editable) {
        const VgVoice *before = session.vgSource->voiceAt(slot);
        if (!before || *before == voice)
            return nullptr;
        return std::make_unique<ExistingVoiceValueEditCommand>(session, slot, *before, voice,
                                                               structural, std::move(applied));
    }
    if (session.vgSource->kindAt(slot) != VgLineKind::None)
        return nullptr;
    return std::make_unique<BlankSlotMaterializationCommand>(
        session, slot, voice, session.vgSource->sourceBytes(), std::move(applied));
}

void reapplyVoicegroupEditsToReopenedSource(SongSession &session)
{
    if (!session.vgSource)
        return;
    const QUndoStack *stack = session.doc.undoStack();
    for (int i = 0; i < stack->index(); i++) {
        const QUndoCommand *command = stack->command(i);
        if (const auto *valueEdit = dynamic_cast<const ExistingVoiceValueEditCommand *>(command)) {
            valueEdit->reapplyToReopenedSource(session);
        } else if (const auto *blankEdit =
                       dynamic_cast<const BlankSlotMaterializationCommand *>(command)) {
            blankEdit->reapplyToReopenedSource(session);
        }
    }
}
