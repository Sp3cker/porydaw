#include "core/mid2agbtables.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/trackheaderpanel.h"
#include "ui/songview/voicepicker.h"
#include "ui/theme/color_math.h"
#include "ui/theme/themeruntime.h"
#include "ui/theme/trackidentitycolors.h"

#include <QColor>
#include <QDialog>
#include <QMetaObject>
#include <QStringList>

#include <algorithm>
#include <array>
#include <climits>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <utility>
#include <vector>

using namespace songview;
using namespace songview::detail;

void SongView::selectTrack(int track)
{
    transitionSelectedTrack(track);
}
void SongView::transitionSelectedTrack(int newTrack)
{
    transitionSelectedTrack(newTrack, newTrack != m_selectionModel.primaryTrack());
}
void SongView::transitionSelectedTrack(int newTrack, bool trackIdentityChanged)
{
    if (newTrack < 0 || newTrack > 15 || !trackIdentityChanged)
        return;
    if (m_roll)
        m_roll->cancelPitchBendPopup();
    cancelActiveInteractions();
    m_selectionModel.applyPrimaryTrackTransition(newTrack);
}
bool SongView::revealNote(int track, uint8_t key, uint64_t tick)
{
    if (track < 0 || track > 15)
        return false;
    selectTrack(track);
    // Notes are sorted by startTick, so the last match is the note that was
    // sounding (or had just finished fading) at the event's position.
    const ViewNote *found = nullptr;
    for (const ViewNote &note : m_model.notes) {
        if (note.startTick > tick)
            break;
        if (note.track == track && note.key == key)
            found = &note;
    }
    if (!found)
        return false;
    m_selectionModel.setNoteSelection({found->noteId});
    ensureKeyVisible(key);
    return true;
}
void SongView::trackHeaderClicked(int track, Qt::KeyboardModifiers modifiers)
{
    if (track < 0 || track > 15)
        return;
    if (m_roll)
        m_roll->cancelPitchBendPopup();
    cancelActiveInteractions();
    const uint32_t used = usedTrackMask(m_timeline);
    const auto action =
        modifiers & Qt::ControlModifier ? EditorSelectionModel::TrackScopeAction::Toggle
        : modifiers & Qt::ShiftModifier ? EditorSelectionModel::TrackScopeAction::Range
                                        : EditorSelectionModel::TrackScopeAction::Plain;
    m_selectionModel.applyTrackScopeAdjustment(track, used, action);
}
void SongView::setTrackMute(int track, bool on)
{
    const uint32_t bit = 1u << track;
    const uint32_t mask = on ? (m_muteMask | bit) : (m_muteMask & ~bit);
    if (mask != m_muteMask) {
        m_muteMask = mask;
        emit muteMaskChanged(mask);
    }
}
void SongView::setTrackSolo(int track, bool on)
{
    const uint32_t bit = 1u << track;
    const uint32_t mask = on ? (m_soloMask | bit) : (m_soloMask & ~bit);
    if (mask != m_soloMask) {
        m_soloMask = mask;
        emit soloMaskChanged(mask);
    }
}
// Names the scoped tracks for the status line: "track 3" or "tracks 1, 3".
static QString scopedTracksText(uint32_t mask)
{
    QStringList nums;
    for (int t = 0; t < 16; t++) {
        if (mask & (1u << t))
            nums << QString::number(t + 1);
    }
    return nums.size() == 1 ? SongView::tr("track %1").arg(nums.first())
                            : SongView::tr("tracks %1").arg(nums.join(QStringLiteral(", ")));
}
void SongView::toggleMuteOnSelectedTracks()
{
    const uint32_t scope = m_selectionModel.resolvedTrackScope(usedTrackMask(m_timeline));
    const bool allOn = (m_muteMask & scope) == scope;
    const uint32_t mask = allOn ? (m_muteMask & ~scope) : (m_muteMask | scope);
    if (mask == m_muteMask)
        return;
    m_muteMask = mask;
    emit muteMaskChanged(mask);
    announce(allOn ? tr("Unmuted %1").arg(scopedTracksText(scope))
                   : tr("Muted %1").arg(scopedTracksText(scope)));
}
void SongView::toggleSoloOnSelectedTracks()
{
    const uint32_t scope = m_selectionModel.resolvedTrackScope(usedTrackMask(m_timeline));
    const bool allOn = (m_soloMask & scope) == scope;
    const uint32_t mask = allOn ? (m_soloMask & ~scope) : (m_soloMask | scope);
    if (mask == m_soloMask)
        return;
    m_soloMask = mask;
    emit soloMaskChanged(mask);
    announce(allOn ? tr("Unsoloed %1").arg(scopedTracksText(scope))
                   : tr("Soloed %1").arg(scopedTracksText(scope)));
}
QColor SongView::trackColor(int track)
{
    return themes::trackIdentityColor(trackIdentityIndex(track));
}
QColor SongView::noteColor(int track, int velocity)
{
    // 16 identities × 128 velocities; rebuilt when the theme zero-velocity
    // color changes. Steady-state paint is a table load.
    static std::array<std::array<QColor, 128>, themes::trackIdentityColorCount> table{};
    static std::optional<QRgb> zeroColorKey{};

    const auto zeroColor = themes::color(themes::Role::song_view_note_velocity_zero);
    if (!zeroColorKey || *zeroColorKey != zeroColor.rgba()) {
        zeroColorKey = zeroColor.rgba();
        for (std::size_t i = 0; i < table.size(); ++i) {
            const auto identity = themes::trackIdentityColor(i);
            table[i][0] = zeroColor;
            table[i][127] = identity;
            for (int velocityIndex = 1; velocityIndex < 127; ++velocityIndex) {
                const double t = 1.0 - (double(velocityIndex) / 127.0);
                table[i][static_cast<std::size_t>(velocityIndex)] =
                    mixTowardOklab(identity, zeroColor, t);
            }
        }
    }
    const auto clampedVelocity = std::clamp(velocity, 0, 127);
    return table[trackIdentityIndex(track)][static_cast<std::size_t>(clampedVelocity)];
}
QColor SongView::velocityNoteColor(int velocity)
{
    if (velocity <= 0)
        return themes::color(themes::Role::song_view_note_velocity_zero);
    // Purple's hue (~250°) interpolates linearly down to red's (~1°), which
    // is the long way around the wheel — through blue, green, and yellow —
    // so the full spectrum spreads across the velocity range.
    static const QColor kMinVelocity(0x5f, 0x44, 0xe9);
    static const QColor kMaxVelocity(0xe9, 0x09, 0x04);
    if (velocity <= 1)
        return kMinVelocity;
    if (velocity >= 127)
        return kMaxVelocity;
    const float t = float(velocity - 1) / 126.0f;
    float h0, s0, v0, h1, s1, v1;
    kMinVelocity.getHsvF(&h0, &s0, &v0);
    kMaxVelocity.getHsvF(&h1, &s1, &v1);
    // Quantize to 8-bit RGB: QColor equality is spec- and depth-sensitive,
    // and callers compare against rendered pixels.
    return QColor(
        QColor::fromHsvF(h0 + (h1 - h0) * t, s0 + (s1 - s0) * t, v0 + (v1 - v0) * t).rgb());
}
QColor SongView::noteFillColor(int track, int velocity) const
{
    return m_velocityColorMode ? velocityNoteColor(velocity) : noteColor(track, velocity);
}
int SongView::currentProgram(int track) const
{
    if (!m_timeline)
        return -1;
    int prog = m_timeline->tracks[track].firstProgram;
    const uint64_t tick = m_playing ? uint64_t(m_playheadTick) : m_editCursorTick;
    for (const VoiceChange &vc : m_model.voices) {
        if (vc.tick > tick)
            break;
        if (vc.track == track)
            prog = vc.program;
    }
    return prog;
}
QString SongView::instrumentLabel(int track) const
{
    if (!m_timeline)
        return QString();
    const int prog = currentProgram(track);
    if (prog < 0)
        return tr("(no voice set)");
    QString name = voiceShortName(uint8_t(prog));
    return QStringLiteral("%1 %2").arg(prog, 3, 10, QLatin1Char('0')).arg(name);
}
QString SongView::voiceShortName(uint8_t program) const
{
    QString name;
    QString type;
    if (m_voicegroup && program < VOICEGROUP_SIZE) {
        name = QString::fromUtf8(m_voicegroup->voiceNames[program]).trimmed();
        type = m4aVoiceTypeName(m_voicegroup->voices[program].type);
    }
    if (name.isEmpty())
        return type.isEmpty() ? tr("Voice") : type;
    return QStringLiteral("%1 (%2)").arg(name, type);
}
DrawerPageVoiceContext SongView::voiceContext(uint64_t tick) const
{
    const int primaryTrack = m_selectionModel.primaryTrack();
    if (!m_timeline || !m_voicegroup || primaryTrack < 0 || primaryTrack >= 16)
        return {};
    int program = m_timeline->tracks[primaryTrack].firstProgram;
    uint64_t endTick = UINT64_MAX;
    for (const VoiceChange &change : m_model.voices) {
        if (change.track != primaryTrack)
            continue;
        if (change.tick > tick) {
            endTick = change.tick;
            break;
        }
        program = change.program;
    }
    if (program < 0 || program >= VOICEGROUP_SIZE)
        return {nullptr, -1, endTick};
    return {&m_voicegroup->voices[program], program, endTick};
}
void SongView::revealVoice(int program)
{
    if (program >= 0 && program < 128)
        emit revealVoiceRequested(program);
}
void SongView::revealTrackVoice(int track)
{
    if (!m_timeline || track < 0 || track > 15)
        return;
    const int prog = currentProgram(track);
    if (prog < 0) {
        emit statusMessage(tr("Track %1 has no voice set.").arg(track + 1));
        return;
    }
    revealVoice(prog);
}
QSet<int> SongView::usedVoices() const
{
    QSet<int> used;
    if (!m_timeline)
        return used;
    for (int t = 0; t < 16; t++) {
        if (m_timeline->tracks[t].used && m_timeline->tracks[t].firstProgram >= 0)
            used.insert(m_timeline->tracks[t].firstProgram);
    }
    for (const VoiceChange &vc : m_model.voices)
        used.insert(vc.program);
    return used;
}
bool SongView::pickVoice(const QString &title, int initialVoice, int *outVoice)
{
    VoicePickerDialog dialog(this, title, initialVoice, [this](int voice, int velocity) {
        emit auditionVoice(voice, kVoiceAuditionKey, velocity);
    });
    if (dialog.exec() != QDialog::Accepted)
        return false;
    *outVoice = dialog.selectedVoice();
    return true;
}
void SongView::editTrackVoice(int track)
{
    if (!m_document || track < 0 || track > 15)
        return;
    const std::vector<DocLanePoint> changes = m_document->lanePoints(track, DOC_CC_VOICE);
    // The track's initial voice is the LAST change on the first change's
    // tick: same-tick duplicates are audibly last-wins, and the header label
    // (currentProgram) already reads them that way — edit what it shows.
    const DocLanePoint *target = nullptr;
    for (const DocLanePoint &pt : changes) {
        if (pt.tick != changes.front().tick)
            break;
        target = &pt;
    }
    const int initial = target ? target->value : 0;
    int voice = initial;
    if (!pickVoice(tr("Track %1 voice").arg(track + 1), initial, &voice))
        return;
    if (!target)
        m_document->addLanePoint(track, DOC_CC_VOICE, 0, voice);
    else if (voice != initial)
        m_document->moveLanePoints({{track, DOC_CC_VOICE, *target, target->tick, voice}});
}
void SongView::renameTrack(int track)
{
    if (!m_document || track < 0 || track > 15 || m_document->smfTrackFor(track) < 0)
        return;
    m_headers->beginRename(track);
}
void SongView::commitTrackRename(int track, const QString &name)
{
    if (!m_document || track < 0 || track > 15 || m_document->smfTrackFor(track) < 0)
        return;
    const QString trimmed = name.trimmed();
    if (nameIsLoopMarker(trimmed)) {
        announce(tr("\"%1\" is read by the song build as a loop or label "
                    "marker, so it can't be a track name.")
                     .arg(trimmed));
        return;
    }
    // Queued: the commit arrives from the header row's editor signal, and
    // the edit rebuilds the header panel — deleting that editor mid-signal.
    QMetaObject::invokeMethod(
        this,
        [this, track, trimmed] {
            if (m_document)
                m_document->renameTrack(track, trimmed);
        },
        Qt::QueuedConnection);
}
void SongView::addTrack()
{
    if (!m_document || !m_document->canAddTrack())
        return;
    int voice = 0;
    if (!pickVoice(tr("New track voice"), 0, &voice))
        return;
    const int track = m_document->addTrack(voice); // rebuilds via documentChanged
    if (track >= 0) {
        selectTrack(track);
        announce(tr("Added track %1").arg(track + 1));
    }
}
void SongView::duplicateTrack(int track)
{
    if (!m_document || track < 0 || track > 15 || m_document->smfTrackFor(track) < 0)
        return;
    const int copy = m_document->duplicateTrack(track); // rebuilds via documentChanged
    if (copy >= 0) {
        selectTrack(copy);
        announce(tr("Duplicated track %1 as track %2").arg(track + 1).arg(copy + 1));
    }
}
void SongView::deleteTrack(int track)
{
    if (!m_document || track < 0 || track > 15 || m_document->smfTrackFor(track) < 0)
        return;
    m_document->deleteTrack(track); // remaps before documentChanged
    announce(tr("Deleted track %1").arg(track + 1));
}
void SongView::moveTrack(int from, int to)
{
    if (!m_document)
        return;
    if (m_document->moveTrack(from, to)) // remaps before documentChanged
        announce(tr("Moved track %1 to slot %2").arg(from + 1).arg(to + 1));
}
void SongView::onTracksRemapped(const TrackRemap &remap)
{
    if (m_roll)
        m_roll->cancelPitchBendPopup();
    cancelActiveInteractions();
    const auto remapTrack = [&remap](int track) {
        return track >= 0 && static_cast<std::size_t>(track) < remap.engineTrackMap.size()
                   ? remap.engineTrackMap[static_cast<std::size_t>(track)]
                   : -1;
    };
    const auto remapMask = [&remap, &remapTrack](uint32_t mask) {
        uint32_t mapped = 0;
        for (int track = 0; track < 16; ++track) {
            if (!(mask & (1u << track)))
                continue;
            const int destination = remapTrack(track);
            if (destination >= 0 && destination < remap.newEngineTrackCount)
                mapped |= 1u << destination;
        }
        return mapped;
    };

    // Compute the complete remap before committing any SongView-owned state.
    const int oldPrimaryTrack = m_selectionModel.primaryTrack();
    const int mappedPrimaryTrack = remapTrack(oldPrimaryTrack);
    const int remappedPrimaryTrack =
        mappedPrimaryTrack >= 0
            ? mappedPrimaryTrack
            : std::min(oldPrimaryTrack, std::max(0, remap.newEngineTrackCount - 1));
    const uint32_t mappedTrackScope =
        remapMask(m_selectionModel.storedTrackScope()) | (1u << remappedPrimaryTrack);
    const auto &selection = m_selectionModel.timeSelection();
    const bool hadLaneSelection = selection.scope == EditorSelectionModel::TimeSelection::Lanes;
    std::vector<std::pair<int, uint8_t>> remappedLanes;
    if (hadLaneSelection) {
        remappedLanes.reserve(selection.lanes.size());
        for (const std::pair<int, uint8_t> &lane : selection.lanes) {
            const int track = lane.first < 0 ? lane.first : remapTrack(lane.first);
            if (track >= 0 || lane.first < 0)
                remappedLanes.emplace_back(track, lane.second);
        }
    }
    const uint32_t mute = remapMask(m_muteMask);
    const uint32_t solo = remapMask(m_soloMask);
    auto remappedEditorViewState = m_editorViewState;
    const bool drawerChanged = remappedEditorViewState.remapEngineTracks(remap.engineTrackMap);
    std::vector<ClipTrack> remappedTracks;
    remappedTracks.reserve(m_clip.tracks.size());
    for (ClipTrack &track : m_clip.tracks) {
        const int destination = remapTrack(track.track);
        if (destination >= 0) {
            track.track = destination;
            remappedTracks.push_back(std::move(track));
        }
    }
    std::vector<ClipLane> remappedClipLanes;
    remappedClipLanes.reserve(m_clip.lanes.size());
    for (ClipLane &lane : m_clip.lanes) {
        const int destination = lane.track < 0 ? lane.track : remapTrack(lane.track);
        if (destination >= 0 || lane.track < 0) {
            lane.track = destination;
            remappedClipLanes.push_back(std::move(lane));
        }
    }

    // Commit external state without refreshes or application signals. The
    // model notification below must observe this complete batch.
    m_editorViewState = std::move(remappedEditorViewState);
    m_clip.tracks = std::move(remappedTracks);
    m_clip.lanes = std::move(remappedClipLanes);
    const bool muteChanged = mute != m_muteMask;
    const bool soloChanged = solo != m_soloMask;
    m_muteMask = mute;
    m_soloMask = solo;

    m_selectionModel.applyRemap(remap);
    Q_ASSERT(m_selectionModel.primaryTrack() == remappedPrimaryTrack);
    Q_ASSERT(m_selectionModel.storedTrackScope() == mappedTrackScope);
    if (hadLaneSelection)
        Q_ASSERT(m_selectionModel.timeSelection().lanes == remappedLanes);
    m_editorDrawer->velocityArea()->tracksRemapped(remap);
    if (drawerChanged)
        emit editorDrawerStateChanged(m_editorViewState.drawerState());
    if (muteChanged)
        emit muteMaskChanged(m_muteMask);
    if (soloChanged)
        emit soloMaskChanged(m_soloMask);
}
void SongView::auditionTimed(int track, int key, int velocity, uint64_t startTick, uint64_t endTick)
{
    if (!m_timeline || endTick <= startTick)
        return;
    uint64_t dur = m_timeline->sampleForTick(endTick) - m_timeline->sampleForTick(startTick);
    // Safety cap: an unterminated note's span runs to the end of the song,
    // which is not a useful audition length.
    const uint64_t cap = uint64_t(m_timeline->sampleRate * 10.0);
    if (cap > 0)
        dur = std::min(dur, cap);
    if (dur > 0)
        emit auditionNoteTimed(track, key, velocity, quint32(std::min<uint64_t>(dur, UINT32_MAX)));
}
