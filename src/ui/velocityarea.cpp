#include "ui/velocityarea.h"

#include <algorithm>
#include <cmath>
#include <optional>
#include <string_view>

#include <QApplication>
#include <QContextMenuEvent>
#include <QEvent>
#include <QFocusEvent>
#include <QKeyEvent>
#include <QKeySequence>
#include <QMouseEvent>
#include <QPainter>
#include <QPalette>
#include <QRegion>
#include <QWheelEvent>

#include "core/miditimeline.h"
#include "ui/layout.h"
#include "ui/selectionreticle.h"
#include "ui/songview.h"
#include "ui/theme/themeruntime.h"

namespace {

bool contains(const std::vector<NoteId> &notes, NoteId noteId)
{
    return std::find(notes.begin(), notes.end(), noteId) != notes.end();
}

std::vector<NoteId> noteIds(const std::vector<DocNote> &notes)
{
    std::vector<NoteId> ids;
    ids.reserve(notes.size());
    for (const DocNote &note : notes)
        ids.push_back(note.noteId);
    return ids;
}

int effectiveVelocity(uint8_t storedVelocity)
{
    return std::min(127, ((int(storedVelocity) + 3) / 4) * 4);
}

QString latin1(std::string_view value)
{
    return QString::fromLatin1(value.data(), int(value.size()));
}

uint64_t drawerContextTick(double tick)
{
    return static_cast<uint64_t>(std::floor(std::max(0.0, tick) + 0.5));
}

} // namespace

VelocityArea::VelocityArea(SongView &owner, QWidget *parent)
    : songview::TimelineSurface(parent)
    , m_owner(owner)
{
    setFocusPolicy(Qt::ClickFocus);
    setMouseTracking(false);
    publishAccessibleDescription();
}

bool VelocityArea::event(QEvent *event)
{
    if (event->type() == QEvent::UngrabMouse)
        cancelInteraction();
    return songview::TimelineSurface::event(event);
}

void VelocityArea::songChanged()
{
    cancelInteraction();
    m_pianoRollVelocityDelta.reset();
    m_live = {};
    m_axis = VelocityAxis(VelocityMap::resolve(nullptr, std::nullopt), {});
    publishAccessibleDescription();
    rebuildVisualState();
}

void VelocityArea::refreshLiveState(const EditorPageLiveState &liveState)
{
    if (m_interaction != Interaction::None && m_committingPreview) {
        m_live = liveState;
        rebuildVisualState();
        return;
    }
    if (m_interaction != Interaction::None &&
        m_live.documentRevision == liveState.documentRevision) {
        if (m_live.playback.playheadTick != liveState.playback.playheadTick)
            presentPlayhead(liveState.playback.playheadTick);
        return;
    }
    const bool presentationOnly = m_live.documentRevision == liveState.documentRevision &&
                                  m_live.timeZoom == liveState.timeZoom &&
                                  m_live.horizontalScroll == liveState.horizontalScroll &&
                                  m_live.editCursorTick == liveState.editCursorTick &&
                                  m_live.trackColor == liveState.trackColor &&
                                  m_live.playback.playing == liveState.playback.playing &&
                                  m_live.playback.playheadTick != liveState.playback.playheadTick;
    m_live = liveState;
    if (presentationOnly) {
        if (selectedNotes().empty() && currentContext() != m_axis.map())
            rebuildVisualState();
        presentPlayhead(liveState.playback.playheadTick);
        return;
    }
    cancelInteraction();
    rebuildVisualState();
}

void VelocityArea::cancelInteraction()
{
    if (m_interaction == Interaction::None)
        return;
    if (m_interaction == Interaction::Relative || m_interaction == Interaction::Paint)
        restorePreview();
    pauseFollowScroll(false);
    m_owner.setSelection(m_selectionBeforePress);
    clearPreview();
    m_interaction = Interaction::None;
    m_relativeActivated = false;
    m_suppressContextMenu = false;
    invalidateContent();
}

void VelocityArea::documentChanged()
{
    if (m_committingPreview)
        return;
    m_pianoRollVelocityDelta.reset();
    cancelInteraction();
    rebuildVisualState();
}

void VelocityArea::tracksRemapped(const TrackRemap &)
{
    m_pianoRollVelocityDelta.reset();
    cancelInteraction();
    rebuildVisualState();
}

int VelocityArea::plotOrigin() const
{
    return layout::editorGeometry().plotOrigin;
}

int VelocityArea::plotWidth() const
{
    return std::max(0, width() - plotOrigin());
}

void VelocityArea::clearTrackHeaderSelection()
{
    setSelection({});
}

void VelocityArea::presentPlayhead(double tick)
{
    m_live.playback.playheadTick = tick;
    m_diagnostics.presentedPlayheadTick = tick;
    ++m_diagnostics.playheadPresentationCount;
}

void VelocityArea::presentPianoRollVelocityPreview(std::optional<int> delta)
{
    if (m_pianoRollVelocityDelta == delta)
        return;
    m_pianoRollVelocityDelta = delta;
    rebuildVisualState();
}

void VelocityArea::invalidateContent(const QRect &rect)
{
    if (rect.isEmpty())
        songview::TimelineSurface::invalidateContent();
    else
        songview::TimelineSurface::invalidateContent(QRegion(rect));
}

void VelocityArea::contentGeometryChanged()
{
    rebuildAxis();
}

void VelocityArea::rebuildVisualState()
{
    rebuildAxis();
    invalidateContent();
}

void VelocityArea::rebuildAxis()
{
    std::vector<uint8_t> activeValues;
    const std::vector<DocNote> notes = selectedNotes();
    activeValues.reserve(std::max(notes.size(), m_previewVelocities.size()));
    for (const DocNote &note : notes)
        activeValues.push_back(displayedVelocity(note));
    const VelocityAxisGeometry geometry{
        double(height()),
        double(layout::space(layout::Space::Three)),
        double(std::max(0, plotOrigin() - layout::singlePixel())),
        double(layout::space(layout::Space::Two)),
        double(layout::space(layout::Space::One)),
        double(layout::editorGeometry().velocityDensityThresholdD1),
        double(layout::editorGeometry().velocityDensityThresholdD2),
        double(layout::editorGeometry().velocityDensityThresholdD3),
        double(layout::editorGeometry().velocityDensityThresholdD4),
    };
    m_axis = VelocityAxis(currentContext(), geometry, activeValues.data(), activeValues.size());
    publishAccessibleDescription();
}

void VelocityArea::publishAccessibleDescription()
{
    setAccessibleDescription(latin1(m_axis.accessibleDescription()));
}

// One compatible PSG map lets users edit intrinsic levels. Unresolved, non-PSG,
// or selections that are not compatible use the continuous 1–127 velocity domain.
VelocityMap VelocityArea::currentContext() const
{
    const std::vector<DocNote> notes = selectedNotes();
    if (notes.empty()) {
        const uint64_t tick = m_live.playback.playing
                                  ? drawerContextTick(m_live.playback.playheadTick)
                                  : m_live.editCursorTick;
        return VelocityMap::resolve(m_owner.voiceContext(tick).voice, std::nullopt);
    }
    const VelocityMap first = contextForNote(notes.front());
    if (!first.isPsg())
        return VelocityMap::resolve(nullptr, std::nullopt);
    for (const DocNote &note : notes) {
        const VelocityMap next = contextForNote(note);
        if (!next.isPsg() || !first.compatibleWith(next))
            return VelocityMap::resolve(nullptr, std::nullopt);
    }
    return first;
}

VelocityMap VelocityArea::contextForNote(const DocNote &note) const
{
    const EditorPageVoiceContext context = m_owner.voiceContext(note.tick);
    return VelocityMap::resolve(context.voice, note.key);
}

std::vector<DocNote> VelocityArea::selectedNotes() const
{
    std::vector<DocNote> notes;
    const SongDocument *document = m_owner.document();
    if (!document)
        return notes;
    for (const NoteId noteId : m_owner.selection()) {
        DocNote note;
        if (document->findNote(noteId, &note))
            notes.push_back(note);
    }
    return notes;
}

std::vector<DocNote> VelocityArea::primaryTrackNotes() const
{
    const SongDocument *document = m_owner.document();
    if (!document)
        return {};
    return document->notesForTrack(m_owner.selectedTrack());
}

std::vector<DocNote> VelocityArea::notesAt(const QPointF &position, bool includeStems) const
{
    std::vector<DocNote> hits;
    std::vector<DocNote> selectedHits;
    const std::vector<NoteId> &selection = m_owner.selection();
    for (const DocNote &note : primaryTrackNotes()) {
        if (!nodeRect(note).contains(position) &&
            (!includeStems || !stemRect(note).contains(position))) {
            continue;
        }
        if (contains(selection, note.noteId))
            selectedHits.push_back(note);
        else
            hits.push_back(note);
    }
    return selectedHits.empty() ? hits : selectedHits;
}

QRectF VelocityArea::nodeRect(const DocNote &note) const
{
    const double radius = double(layout::editorGeometry().velocityStartNodeHitRadius);
    return QRectF(xForTick(note.tick) - radius, yForNote(note, note.velocity) - radius,
                  radius * 2.0, radius * 2.0);
}

QRectF VelocityArea::stemRect(const DocNote &note) const
{
    const double verticalRadius =
        double(layout::editorGeometry().velocityDurationLineVerticalRadius);
    const double horizontalSlop =
        double(layout::editorGeometry().velocityDurationLineHorizontalSlop);
    const double start = xForTick(note.tick) - horizontalSlop;
    const double end = xForTick(note.tick + note.duration) + horizontalSlop;
    return QRectF(start, yForNote(note, note.velocity) - verticalRadius, std::max(0.0, end - start),
                  verticalRadius * 2.0);
}

double VelocityArea::xForTick(uint64_t tick) const
{
    const MidiTimeline *timeline = m_owner.timeline();
    const double ticksPerBeat = timeline ? double(std::max(1u, timeline->ticksPerBeat)) : 1.0;
    return double(plotOrigin()) + double(tick) * pxPerBeat() / ticksPerBeat -
           m_live.horizontalScroll;
}

double VelocityArea::yForVelocity(uint8_t velocity) const
{
    return m_axis.velocityToY(velocity);
}

double VelocityArea::yForNote(const DocNote &note, uint8_t velocity) const
{
    VelocityMap map = contextForNote(note);
    for (const FrozenNote &frozen : m_frozen) {
        if (frozen.noteId == note.noteId) {
            map = frozen.map;
            break;
        }
    }
    if (m_axis.mode() == VelocityAxis::Mode::Intrinsic && m_axis.map().compatibleWith(map)) {
        const std::optional<std::size_t> level = map.levelOf(velocity);
        if (level)
            return m_axis.levelToY(int(*level));
    }
    return yForVelocity(velocity);
}

uint8_t VelocityArea::displayedVelocity(const DocNote &note) const
{
    for (std::size_t index = 0; index < m_frozen.size(); ++index) {
        if (m_frozen[index].noteId == note.noteId)
            return m_previewVelocities[index];
    }
    if (m_pianoRollVelocityDelta && contains(m_owner.selection(), note.noteId)) {
        return uint8_t(std::clamp(int(note.velocity) + *m_pianoRollVelocityDelta, 1, 127));
    }
    return note.velocity;
}

double VelocityArea::pxPerBeat() const
{
    return std::max(1.0, m_live.timeZoom > 1.0
                             ? m_live.timeZoom
                             : layout::editorGeometry().editorDefaultPixelsPerBeat);
}

bool VelocityArea::inRuler(const QPointF &position) const
{
    return m_axis.inRuler(position, double(plotOrigin()));
}

int VelocityArea::rulerVelocityAt(const QPointF &position) const
{
    return m_axis.rulerVelocityAt(position, double(fontMetrics().height()));
}

void VelocityArea::setSelection(const std::vector<NoteId> &selection)
{
    m_owner.setSelection(selection);
    rebuildVisualState();
}

std::vector<NoteId> VelocityArea::toggledSelection(const std::vector<DocNote> &notes) const
{
    std::vector<NoteId> selection = m_owner.selection();
    for (const DocNote &note : notes) {
        const auto it = std::find(selection.begin(), selection.end(), note.noteId);
        if (it == selection.end())
            selection.push_back(note.noteId);
        else
            selection.erase(it);
    }
    return selection;
}

void VelocityArea::appendFrozenNotes(const std::vector<DocNote> &notes)
{
    m_frozen.reserve(m_frozen.size() + notes.size());
    m_previewVelocities.reserve(m_previewVelocities.size() + notes.size());
    for (const DocNote &note : notes) {
        const auto existing =
            std::find_if(m_frozen.begin(), m_frozen.end(), [&note](const FrozenNote &frozen) {
                return frozen.noteId == note.noteId;
            });
        if (existing != m_frozen.end())
            continue;
        const VelocityMap map = contextForNote(note);
        m_frozen.push_back(
            {note.noteId, note.tick, note.duration, note.key, note.velocity, map, note.velocity});
        m_previewVelocities.push_back(note.velocity);
    }
}

void VelocityArea::beginFrozenGesture(const std::vector<DocNote> &notes, Interaction interaction,
                                      const QPointF &position)
{
    const std::vector<NoteId> pressedHits = m_pressedHits;
    const std::vector<NoteId> selectionBeforePress = m_selectionBeforePress;
    const bool controlPress = m_controlPress;
    clearPreview();
    m_pressedHits = pressedHits;
    m_selectionBeforePress = selectionBeforePress;
    m_controlPress = controlPress;
    if (!hasDocument() || notes.empty())
        return;
    appendFrozenNotes(notes);
    m_previewRevision = m_live.documentRevision;
    m_velocityGesture = m_owner.beginVelocityMutation();
    for (const NoteId noteId : m_pressedHits) {
        if (std::any_of(m_frozen.begin(), m_frozen.end(),
                        [noteId](const FrozenNote &note) { return note.noteId == noteId; })) {
            m_announcedNote = noteId;
            break;
        }
    }
    m_pressPosition = position;
    m_previousPosition = position;
    m_interaction = interaction;
    m_relativeActivated = false;
    pauseFollowScroll(true);
}

void VelocityArea::beginVelocityPaint(const QPointF &position)
{
    const std::vector<NoteId> pressedHits = m_pressedHits;
    const std::vector<NoteId> selectionBeforePress = m_selectionBeforePress;
    const bool controlPress = m_controlPress;
    clearPreview();
    m_pressedHits = pressedHits;
    m_selectionBeforePress = selectionBeforePress;
    m_controlPress = controlPress;
    m_previewRevision = m_live.documentRevision;
    m_velocityGesture = m_owner.beginVelocityMutation();
    m_pressPosition = position;
    m_previousPosition = position;
    m_interaction = Interaction::Paint;
    m_relativeActivated = false;
    pauseFollowScroll(true);
}

void VelocityArea::paintSelectedNodesBetween(const QPointF &first, const QPointF &last)
{
    const double deltaX = last.x() - first.x();
    const double radius = double(layout::editorGeometry().velocityStartNodeHitRadius);
    std::vector<DocNote> notes;
    std::vector<double> ys;
    for (const DocNote &note : selectedNotes()) {
        const double x = xForTick(note.tick);
        double y = last.y();
        if (deltaX == 0.0) {
            if (std::abs(x - last.x()) > radius)
                continue;
        } else {
            if (x < std::min(first.x(), last.x()) - radius ||
                x > std::max(first.x(), last.x()) + radius) {
                continue;
            }
            const double t = std::clamp((x - first.x()) / deltaX, 0.0, 1.0);
            y = first.y() + t * (last.y() - first.y());
        }
        notes.push_back(note);
        ys.push_back(y);
    }
    if (notes.empty())
        return;
    appendFrozenNotes(notes);
    for (std::size_t index = 0; index < notes.size(); ++index) {
        const auto it = std::find_if(m_frozen.begin(), m_frozen.end(),
                                     [&notes, index](const FrozenNote &frozen) {
                                         return frozen.noteId == notes[index].noteId;
                                     });
        if (it == m_frozen.end())
            continue;
        const std::size_t frozenIndex = std::size_t(std::distance(m_frozen.begin(), it));
        if (m_axis.mode() == VelocityAxis::Mode::Continuous)
            m_previewVelocities[frozenIndex] = it->map.canonicalize(m_axis.yToVelocity(ys[index]));
        else
            m_previewVelocities[frozenIndex] = it->map.representative(m_axis.yToLevel(ys[index]));
    }
    m_announcedNote = notes.front().noteId;
    announcePreview();
    rebuildVisualState();
}

void VelocityArea::updateRelativePreview(const QPointF &position)
{
    if (m_frozen.empty())
        return;
    const double distance =
        std::abs(position.x() - m_pressPosition.x()) + std::abs(position.y() - m_pressPosition.y());
    if (!m_relativeActivated) {
        const bool intrinsicChange =
            m_axis.mode() == VelocityAxis::Mode::Intrinsic &&
            m_axis.yToLevel(position.y()) != m_axis.yToLevel(m_pressPosition.y());
        if (distance < double(layout::editorGeometry().velocityRelativeDragActivationDistance) &&
            !intrinsicChange)
            return;
        m_relativeActivated = true;
    }
    if (m_axis.mode() == VelocityAxis::Mode::Continuous) {
        const int delta =
            m_axis.yToVelocity(position.y()) - m_axis.yToVelocity(m_pressPosition.y());
        for (std::size_t index = 0; index < m_frozen.size(); ++index) {
            const int proposal = int(m_frozen[index].velocity) + delta;
            m_previewVelocities[index] = m_frozen[index].map.canonicalize(proposal);
        }
    } else {
        const int levelDelta = m_axis.yToLevel(position.y()) - m_axis.yToLevel(m_pressPosition.y());
        for (std::size_t index = 0; index < m_frozen.size(); ++index)
            m_previewVelocities[index] =
                m_frozen[index].map.moveLevels(m_frozen[index].exactOrigin, levelDelta);
    }
    announcePreview();
    applyPreview();
    rebuildVisualState();
}

void VelocityArea::updateBandPreview(const QPointF &position)
{
    m_bandRect = QRectF(m_pressPosition, position).normalized();
    m_bandPreview.clear();
    for (const DocNote &note : primaryTrackNotes()) {
        if (m_bandRect.intersects(nodeRect(note)))
            m_bandPreview.push_back(note.noteId);
    }
    invalidateContent();
}

void VelocityArea::finishGesture(bool commit)
{
    if (m_interaction == Interaction::None)
        return;
    if (commit) {
        if (applyPreview())
            m_owner.announce(tr("Painted note velocities."));
    } else if (m_interaction == Interaction::Relative || m_interaction == Interaction::Paint) {
        restorePreview();
    }
    pauseFollowScroll(false);
    clearPreview();
    m_interaction = Interaction::None;
    m_relativeActivated = false;
    m_suppressContextMenu = false;
    rebuildVisualState();
}

// SongView validates every live update against the revision produced by the
// preceding update. VelocityEditCommand merges updates from this gesture into
// one undo command.
bool VelocityArea::applyPreview()
{
    if (m_frozen.empty())
        return false;
    std::vector<NoteVelocity> edits;
    edits.reserve(m_frozen.size());
    for (std::size_t index = 0; index < m_frozen.size(); ++index)
        edits.push_back({m_frozen[index].noteId, int(m_previewVelocities[index])});
    const uint64_t expectedRevision = m_previewRevision;
    m_committingPreview = true;
    const std::optional<uint64_t> revision =
        m_owner.applyVelocityMutation(expectedRevision, edits, m_velocityGesture);
    m_committingPreview = false;
    if (!revision) {
        m_owner.announce(tr("Velocity edit cancelled because notes changed."));
        pauseFollowScroll(false);
        clearPreview();
        m_interaction = Interaction::None;
        m_relativeActivated = false;
        m_suppressContextMenu = false;
        return false;
    }
    m_previewRevision = *revision;
    m_owner.refreshEditorPages();
    return *revision > expectedRevision;
}

void VelocityArea::restorePreview()
{
    for (std::size_t index = 0; index < m_frozen.size(); ++index)
        m_previewVelocities[index] = m_frozen[index].velocity;
    applyPreview();
}

void VelocityArea::announcePreview()
{
    const SongDocument *document = m_owner.document();
    if (!document || m_frozen.empty())
        return;
    if (!m_announcedNote.isAssigned())
        m_announcedNote = m_frozen.front().noteId;
    for (std::size_t index = 0; index < m_frozen.size(); ++index) {
        if (m_frozen[index].noteId != m_announcedNote)
            continue;
        const uint64_t clocks = document->ticksPerClock() == 0
                                    ? 0
                                    : m_frozen[index].duration / document->ticksPerClock();
        const EditorPageNoteStatus status{m_frozen[index].key, m_previewVelocities[index],
                                          uint8_t(effectiveVelocity(m_previewVelocities[index])),
                                          m_frozen[index].duration, clocks};
        m_owner.showEditorNoteStatus(std::optional<EditorPageNoteStatus>{status});
        return;
    }
}

void VelocityArea::pauseFollowScroll(bool paused)
{
    if (m_followScrollPaused == paused)
        return;
    m_followScrollPaused = paused;
    m_owner.setFollowScrollPaused(paused);
}

void VelocityArea::clearPreview()
{
    m_frozen.clear();
    m_previewVelocities.clear();
    m_bandPreview.clear();
    m_bandRect = {};
    m_pressedHits.clear();
    m_selectionBeforePress.clear();
    m_controlPress = false;
    m_announcedNote = NoteId{};
    m_previewRevision = 0;
    m_velocityGesture = 0;
}

bool VelocityArea::hasDocument() const
{
    return m_owner.document() != nullptr;
}
void VelocityArea::paintContent(QPainter &painter)
{
    painter.setRenderHint(QPainter::Antialiasing, false);
    painter.fillRect(rect(), themes::color(themes::Role::song_view_piano_roll_background));
    const int origin = plotOrigin();
    const int width = plotWidth();
    const int separatorX = origin - layout::singlePixel();
    const double labelLeft = double(layout::space(layout::Space::Two));
    const double labelRight =
        std::max(labelLeft, double(separatorX - layout::space(layout::Space::Two)));
    const double labelWidth = labelRight - labelLeft;
    const double labelHeight = double(fontMetrics().height());
    QFont captionFont = painter.font();
    QFont boldCaptionFont = captionFont;
    boldCaptionFont.setBold(true);
    painter.fillRect(QRect(layout::space(layout::Space::Zero), layout::space(layout::Space::Zero),
                           std::min(origin, this->width()), height()),
                     palette().alternateBase());
    painter.setPen(QPen(palette().mid().color(), layout::singlePixel()));
    painter.drawLine(separatorX, 0, separatorX, height());
    const QColor trackColor =
        m_live.trackColor.isValid() ? m_live.trackColor : palette().highlight().color();
    const QColor stemColor = songview::mixTowardOklab(trackColor, Qt::black, 1.0 / 3.0);
    const QColor selectedColor = palette().highlight().color();
    VelocityAxisPaintStyle axisStyle;
    axisStyle.labelColor = palette().placeholderText().color();
    axisStyle.accentColor = selectedColor;
    axisStyle.labelFont = captionFont;
    axisStyle.emphasizedFont = boldCaptionFont;
    axisStyle.separatorX = double(separatorX);
    axisStyle.labelLeft = labelLeft;
    axisStyle.labelWidth = labelWidth;
    axisStyle.labelHeight = labelHeight;
    axisStyle.tickWidth = double(layout::singlePixel());
    axisStyle.emphasizedWidth = 1.5;
    axisStyle.markerWidth = 1.5;
    axisStyle.minorTickLength = double(layout::space(layout::Space::One));
    axisStyle.majorTickLength = double(3 * layout::space(layout::Space::Half));
    axisStyle.markerTickLength = double(layout::space(layout::Space::Two));
    axisStyle.graduationTickLength = double(3 * layout::space(layout::Space::Half));
    axisStyle.contentClip = QRectF(double(origin), double(layout::space(layout::Space::Zero)),
                                   double(width), double(height()));
    axisStyle.relativeGesture = m_relativeActivated;
    m_axis.paintRuler(painter, axisStyle);
    painter.save();
    painter.setClipRect(axisStyle.contentClip, Qt::IntersectClip);
    const MidiTimeline *timeline = m_owner.timeline();
    if (timeline) {
        const uint64_t length = timeline->lengthTicks;
        const auto gridTicksAt = [this](uint64_t tick) {
            return std::max<uint64_t>(1, m_owner.gridState(tick, false).gridTicks);
        };
        const auto nextGridTick = [&gridTicksAt](uint64_t tick, uint64_t limit) {
            if (tick >= limit)
                return limit;
            const uint64_t spacing = gridTicksAt(tick);
            const uint64_t candidate = spacing >= limit - tick ? limit : tick + spacing;
            if (gridTicksAt(candidate) == spacing)
                return candidate;
            uint64_t first = tick + 1;
            uint64_t last = candidate;
            while (first < last) {
                const uint64_t probe = first + (last - first) / 2;
                if (gridTicksAt(probe) == spacing)
                    first = probe + 1;
                else
                    last = probe;
            }
            return first;
        };
        painter.setPen(QPen(themes::color(themes::Role::song_view_grid), layout::singlePixel()));
        for (uint64_t tick = 0;;) {
            const EditorPageGridState state = m_owner.gridState(tick, false);
            const qreal x = xForTick(tick);
            if (x >= double(origin) && x <= double(origin + width))
                painter.drawLine(QPointF(x, 0), QPointF(x, height()));
            if (tick >= length)
                break;
            tick = nextGridTick(tick, length);
        }
    }
    const std::vector<NoteId> selection = m_owner.selection();
    const std::vector<DocNote> notes = primaryTrackNotes();
    const auto selected = [&selection, this](const DocNote &note) {
        return contains(selection, note.noteId) || contains(m_bandPreview, note.noteId);
    };
    const double stemWidth = layout::editorGeometry().velocityStemDipWidth / devicePixelRatioF();
    for (const DocNote &note : notes) {
        if (selected(note))
            continue;
        const uint8_t velocity = displayedVelocity(note);
        const double start = xForTick(note.tick);
        const double end = std::max(start + 1.0, xForTick(note.tick + note.duration));
        painter.setPen(QPen(stemColor, stemWidth, Qt::SolidLine, Qt::FlatCap));
        painter.drawLine(QPointF(start, yForNote(note, velocity)),
                         QPointF(end, yForNote(note, velocity)));
    }
    for (const DocNote &note : notes) {
        if (!selected(note))
            continue;
        const uint8_t velocity = displayedVelocity(note);
        const double start = xForTick(note.tick);
        const double end = std::max(start + 1.0, xForTick(note.tick + note.duration));
        painter.setPen(
            QPen(selectedColor,
                 layout::editorGeometry().velocitySelectedStemDipWidth / devicePixelRatioF(),
                 Qt::SolidLine, Qt::FlatCap));
        painter.drawLine(QPointF(start, yForNote(note, velocity)),
                         QPointF(end, yForNote(note, velocity)));
    }
    painter.setRenderHint(QPainter::Antialiasing, true);
    for (const DocNote &note : notes) {
        if (selected(note))
            continue;
        const uint8_t velocity = displayedVelocity(note);
        painter.setPen(QPen(Qt::black, layout::editorGeometry().velocityNodeOutlineDipWidth));
        painter.setBrush(trackColor);
        painter.drawEllipse(QPointF(xForTick(note.tick), yForNote(note, velocity)),
                            layout::editorGeometry().velocityNodePaintRadius,
                            layout::editorGeometry().velocityNodePaintRadius);
    }
    for (const DocNote &note : notes) {
        if (!selected(note))
            continue;
        const uint8_t velocity = displayedVelocity(note);
        const QPointF center(xForTick(note.tick), yForNote(note, velocity));
        painter.setPen(
            QPen(selectedColor, layout::editorGeometry().velocitySelectedNodeRingDipWidth));
        painter.setBrush(Qt::NoBrush);
        painter.drawEllipse(center, layout::editorGeometry().velocitySelectedNodeRingRadius,
                            layout::editorGeometry().velocitySelectedNodeRingRadius);
        painter.setPen(QPen(Qt::black, layout::editorGeometry().velocityNodeOutlineDipWidth));
        painter.setBrush(trackColor);
        painter.drawEllipse(center, layout::editorGeometry().velocityNodePaintRadius,
                            layout::editorGeometry().velocityNodePaintRadius);
    }
    if (m_interaction == Interaction::Band)
        songview::paintSelectionReticle(painter, m_bandRect);
    painter.restore();
    painter.setFont(captionFont);
    painter.setPen(palette().placeholderText().color());
    const SongDocument *document = m_owner.document();
    const QString title = document ? document->trackName(m_owner.selectedTrack()) : QString();
    painter.drawText(QRectF(double(origin), double(layout::space(layout::Space::Zero)),
                            double(width), double(height())),
                     Qt::AlignCenter, title);
    if (m_axis.mode() == VelocityAxis::Mode::Intrinsic) {
        const QString levels = tr("%1 has %2 volume levels.")
                                   .arg(QString::fromLatin1(m_axis.map().voiceName()))
                                   .arg(int(m_axis.graduationCount()));
        painter.drawText(QRectF(double(origin), double(layout::space(layout::Space::Three)),
                                double(width), double(fontMetrics().height())),
                         Qt::AlignHCenter | Qt::AlignTop, levels);
    }
    ++m_diagnostics.contentBuildCount;
}

void VelocityArea::mousePressEvent(QMouseEvent *event)
{
    if (!hasDocument()) {
        event->ignore();
        return;
    }
    setFocus(Qt::MouseFocusReason);
    const QPointF position = event->position();
    m_pressPosition = position;
    m_previousPosition = position;
    m_selectionBeforePress = m_owner.selection();
    if (event->button() == Qt::MiddleButton) {
        m_interaction = Interaction::Pan;
        pauseFollowScroll(true);
        event->accept();
        return;
    }
    if (event->button() == Qt::RightButton) {
        m_pressedHits = noteIds(notesAt(position, false));
        m_interaction = Interaction::PendingBand;
        m_controlPress = event->modifiers().testFlag(Qt::ControlModifier);
        m_suppressContextMenu = true;
        pauseFollowScroll(true);
        event->accept();
        return;
    }
    if (event->button() != Qt::LeftButton) {
        event->ignore();
        return;
    }
    if (inRuler(position)) {
        const int velocity = rulerVelocityAt(position);
        if (velocity >= 1) {
            const std::vector<DocNote> notes = selectedNotes();
            beginFrozenGesture(notes, Interaction::Relative, position);
            std::fill(m_previewVelocities.begin(), m_previewVelocities.end(), uint8_t(velocity));
            finishGesture(true);
        }
        event->accept();
        return;
    }
    const std::vector<DocNote> hits = notesAt(position, false);
    m_pressedHits = noteIds(hits);
    m_controlPress = event->modifiers().testFlag(Qt::ControlModifier);
    if (hits.empty()) {
        beginVelocityPaint(position);
        paintSelectedNodesBetween(position, position);
        event->accept();
        return;
    }
    if (!m_controlPress) {
        const bool allSelected = std::all_of(hits.begin(), hits.end(), [this](const DocNote &note) {
            return contains(m_selectionBeforePress, note.noteId);
        });
        if (!allSelected)
            setSelection(noteIds(hits));
    } else {
        std::vector<NoteId> unionSelection = m_selectionBeforePress;
        for (const DocNote &note : hits) {
            if (!contains(unionSelection, note.noteId))
                unionSelection.push_back(note.noteId);
        }
        setSelection(unionSelection);
    }
    beginFrozenGesture(selectedNotes(), Interaction::Relative, position);
    event->accept();
}

void VelocityArea::mouseMoveEvent(QMouseEvent *event)
{
    const QPointF position = event->position();
    if (m_interaction == Interaction::Relative)
        updateRelativePreview(position);
    else if (m_interaction == Interaction::Paint)
        paintSelectedNodesBetween(m_previousPosition, position);
    else if (m_interaction == Interaction::PendingBand) {
        const double distance = std::abs(position.x() - m_pressPosition.x()) +
                                std::abs(position.y() - m_pressPosition.y());
        if (distance >= double(QApplication::startDragDistance()))
            m_interaction = Interaction::Band;
    }
    if (m_interaction == Interaction::Band)
        updateBandPreview(position);
    else if (m_interaction == Interaction::Pan) {
        m_live.horizontalScroll -= position.x() - m_previousPosition.x();
        m_owner.setEditorHorizontalScroll(m_live.horizontalScroll);
        invalidateContent();
    }
    m_previousPosition = position;
    event->accept();
}

void VelocityArea::mouseReleaseEvent(QMouseEvent *event)
{
    if (event->button() == Qt::MiddleButton && m_interaction == Interaction::Pan) {
        pauseFollowScroll(false);
        m_interaction = Interaction::None;
        event->accept();
        return;
    }
    if (event->button() == Qt::RightButton &&
        (m_interaction == Interaction::PendingBand || m_interaction == Interaction::Band)) {
        if (m_interaction == Interaction::Band) {
            std::vector<NoteId> selection =
                m_controlPress ? m_selectionBeforePress : std::vector<NoteId>{};
            for (const NoteId noteId : m_bandPreview) {
                if (!contains(selection, noteId))
                    selection.push_back(noteId);
            }
            setSelection(selection);
        } else if (m_controlPress) {
            setSelection(toggledSelection(notesAt(m_pressPosition, false)));
        } else {
            setSelection(noteIds(notesAt(m_pressPosition, false)));
        }
        finishGesture(false);
        event->accept();
        return;
    }
    if (event->button() == Qt::LeftButton) {
        if (m_interaction == Interaction::Paint) {
            const bool commit = !m_frozen.empty();
            if (!commit)
                setSelection({});
            finishGesture(commit);
        } else if (m_interaction == Interaction::Relative) {
            if (m_controlPress && !m_relativeActivated) {
                std::vector<NoteId> selection = m_selectionBeforePress;
                for (const NoteId noteId : m_pressedHits) {
                    const auto it = std::find(selection.begin(), selection.end(), noteId);
                    if (it == selection.end())
                        selection.push_back(noteId);
                    else
                        selection.erase(it);
                }
                setSelection(selection);
            }
            finishGesture(m_relativeActivated);
        }
        event->accept();
        return;
    }
    event->ignore();
}

void VelocityArea::wheelEvent(QWheelEvent *event)
{
    const QPointF position = event->position();
    const bool horizontal = event->modifiers().testFlag(Qt::ShiftModifier) ||
                            event->angleDelta().x() != 0 || event->pixelDelta().x() != 0;
    if (horizontal) {
        const int delta =
            event->pixelDelta().x() != 0 ? event->pixelDelta().x() : event->angleDelta().y();
        m_owner.setEditorHorizontalScroll(m_live.horizontalScroll - double(delta));
        event->accept();
        return;
    }
    if (!inRuler(position)) {
        const int delta = event->angleDelta().y();
        if (delta != 0)
            m_owner.setEditorTimeZoom(m_live.timeZoom * (delta > 0 ? 1.125 : 0.875));
        event->accept();
        return;
    }
    event->ignore();
}

void VelocityArea::keyPressEvent(QKeyEvent *event)
{
    if (event->key() == Qt::Key_Escape) {
        cancelInteraction();
        event->accept();
        return;
    }
    EditorPageEditCommandRequest request;
    bool routed = true;
    if (event->matches(QKeySequence::Copy))
        request.command = EditorPageEditCommand::Copy;
    else if (event->matches(QKeySequence::Cut))
        request.command = EditorPageEditCommand::Cut;
    else if (event->matches(QKeySequence::Paste))
        request.command = EditorPageEditCommand::Paste;
    else if (event->matches(QKeySequence::SelectAll))
        request.command = EditorPageEditCommand::SelectAll;
    else if (event->key() == Qt::Key_Delete || event->key() == Qt::Key_Backspace)
        request.command = EditorPageEditCommand::Delete;
    else if (event->key() == Qt::Key_Up || event->key() == Qt::Key_Down) {
        request.command = EditorPageEditCommand::Transpose;
        request.direction = event->key() == Qt::Key_Up ? EditorPageEditDirection::Positive
                                                       : EditorPageEditDirection::Negative;
    } else if (event->key() == Qt::Key_Left || event->key() == Qt::Key_Right) {
        request.command = EditorPageEditCommand::NudgeNotePosition;
        request.direction = event->key() == Qt::Key_Right ? EditorPageEditDirection::Positive
                                                          : EditorPageEditDirection::Negative;
    } else {
        routed = false;
    }
    if (!routed) {
        QWidget::keyPressEvent(event);
        return;
    }
    m_owner.executeEditorCommand(request);
    event->accept();
}

void VelocityArea::focusOutEvent(QFocusEvent *event)
{
    cancelInteraction();
    QWidget::focusOutEvent(event);
}

void VelocityArea::contextMenuEvent(QContextMenuEvent *event)
{
    if (m_suppressContextMenu)
        event->accept();
    else
        event->ignore();
}
