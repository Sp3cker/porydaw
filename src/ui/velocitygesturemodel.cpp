#include "ui/velocitygesturemodel.h"

#include <algorithm>
#include <utility>

bool VelocityGestureModel::begin(uint64_t expectedRevision, std::vector<NoteVelocity> targets)
{
    if (m_session || targets.empty())
        return false;

    for (const NoteVelocity &target : targets) {
        if (!target.noteId.isAssigned() || target.velocity < 1 || target.velocity > 127)
            return false;
    }

    std::sort(targets.begin(), targets.end(),
              [](const NoteVelocity &left, const NoteVelocity &right) {
                  return left.noteId < right.noteId;
              });
    for (size_t index = 1; index < targets.size(); index++) {
        if (targets[index - 1].noteId == targets[index].noteId)
            return false;
    }

    Session session;
    session.expectedRevision = expectedRevision;
    session.originalVelocities.reserve(targets.size());
    session.updateMarks.assign(targets.size(), uint8_t{0});
    for (const NoteVelocity &target : targets)
        session.originalVelocities.push_back(uint8_t(target.velocity));
    session.targets = std::move(targets);
    m_session = std::move(session);
    return true;
}

bool VelocityGestureModel::update(const std::vector<NoteVelocity> &updates)
{
    if (!m_session || updates.empty())
        return false;

    // Validate the whole batch before writing any of it: a half-applied
    // preview would commit values the gesture never showed.
    std::fill(m_session->updateMarks.begin(), m_session->updateMarks.end(), uint8_t{0});
    for (const NoteVelocity &update : updates) {
        if (!update.noteId.isAssigned())
            return false;
        const size_t index = targetIndex(update.noteId);
        if (index == m_session->targets.size() || m_session->updateMarks[index])
            return false;
        m_session->updateMarks[index] = 1;
    }

    bool changed = false;
    for (const NoteVelocity &update : updates) {
        const size_t index = targetIndex(update.noteId);
        const int velocity = std::clamp(update.velocity, 1, 127);
        changed |= m_session->targets[index].velocity != velocity;
        m_session->targets[index].velocity = velocity;
    }
    return changed;
}

bool VelocityGestureModel::updateByDelta(int delta)
{
    if (!m_session)
        return false;

    bool changed = false;
    for (size_t index = 0; index < m_session->targets.size(); index++) {
        const int64_t proposed = int64_t(m_session->originalVelocities[index]) + int64_t(delta);
        const int velocity = int(std::clamp<int64_t>(proposed, 1, 127));
        if (m_session->targets[index].velocity != velocity) {
            m_session->targets[index].velocity = velocity;
            changed = true;
        }
    }
    return changed;
}

std::optional<uint8_t> VelocityGestureModel::previewVelocity(NoteId noteId) const
{
    if (!m_session || !noteId.isAssigned())
        return std::nullopt;

    const size_t index = targetIndex(noteId);
    if (index == m_session->targets.size())
        return std::nullopt;
    return uint8_t(m_session->targets[index].velocity);
}

std::optional<VelocityGestureModel::Completion> VelocityGestureModel::takeCompletion()
{
    if (!m_session)
        return std::nullopt;

    Completion completion{m_session->expectedRevision, std::move(m_session->targets)};
    m_session.reset();
    return completion;
}

bool VelocityGestureModel::cancel()
{
    if (!m_session)
        return false;
    m_session.reset();
    return true;
}

size_t VelocityGestureModel::targetIndex(NoteId noteId) const
{
    const auto target =
        std::lower_bound(m_session->targets.begin(), m_session->targets.end(), noteId,
                         [](const NoteVelocity &value, NoteId id) { return value.noteId < id; });
    return target == m_session->targets.end() || target->noteId != noteId
               ? m_session->targets.size()
               : size_t(target - m_session->targets.begin());
}
