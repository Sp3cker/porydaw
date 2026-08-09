#include "ui/editordrawer/velocityarea.h"

#include <algorithm>
#include <cmath>
#include <optional>
#include <string_view>
#include <utility>

#include <QApplication>
#include <QContextMenuEvent>
#include <QEvent>
#include <QFocusEvent>
#include <QFontMetrics>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QPainter>
#include <QPalette>
#include <QRegion>
#include <QWheelEvent>

#include "core/miditimeline.h"
#include "ui/editordrawer/linearramp.h"
#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/selectionreticle.h"
#include "ui/songview.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"

namespace {

bool contains(const std::vector<NoteId> &notes, NoteId noteId)
{
    return std::find(notes.begin(), notes.end(), noteId) != notes.end();
}

int effectiveVelocity(uint8_t storedVelocity)
{
    return std::min(127, ((int(storedVelocity) + 3) / 4) * 4);
}

uint8_t exactVelocity(int proposed)
{
    return uint8_t(std::clamp(proposed, 1, 127));
}

bool detentUnlockHeld(Qt::KeyboardModifiers modifiers, bool allowShift)
{
    const auto &registry = keymap::Registry::instance();
    const QString command = QStringLiteral("velocity.detent_unlock");
    const Qt::KeyboardModifiers binding = registry.modifierBinding(command);
    if (binding == Qt::NoModifier)
        return false;
    const Qt::KeyboardModifiers shortcutModifiers =
        modifiers & (Qt::ControlModifier | Qt::ShiftModifier | Qt::AltModifier | Qt::MetaModifier);
    if (shortcutModifiers == binding)
        return true;
    // Shift-ramp adds exactly one Shift modifier to the configured hold chord.
    return allowShift && shortcutModifiers == (binding | Qt::ShiftModifier);
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
void VelocityArea::Geometry::resolve()
{
    plotOrigin = layout::fontPx(13.0 / 3.0);
    densityThresholdD1 = layout::fontPx(6.0);
    densityThresholdD2 = layout::fontPx(25.0 / 3.0);
    densityThresholdD3 = layout::fontPx(12.0);
    densityThresholdD4 = layout::fontPx(24.0);
    startNodeHitRadius = layout::fontPx(0.5);
    durationLineVerticalRadius = layout::fontPx(1.0 / 3.0);
    durationLineHorizontalSlop = layout::fontPx(1.0 / 6.0);
    relativeDragActivationDistance = layout::fontPx(1.0 / 12.0);
    defaultPixelsPerBeat = layout::fontPx(8.0 / 3.0);
    nodePaintRadius = layout::fontPxF(7.0 / 26.0);
    nodeOutlineDipWidth = layout::fontPxF(1.0 / 12.0);
    selectedNodeRingRadius = layout::fontPxF(3.0 / 8.0);
    selectedNodeRingDipWidth = layout::fontPxF(1.0 / 6.0);
    stemDipWidth = layout::fontPxF(1.0 / 6.0);
    selectedStemDipWidth = layout::fontPxF(1.0 / 4.0);
}
void VelocityArea::rebuildFonts()
{
    m_captionFont = typography::noteName(font());
    m_boldCaptionFont = m_captionFont;
    m_boldCaptionFont.setBold(true);
    m_captionFontHeight = QFontMetrics(m_captionFont).height();
}

VelocityArea::VelocityArea(SongView &owner, QWidget *parent)
    : songview::TimelineSurface(parent)
    , m_owner(owner)
{
    m_geometry.resolve();
    rebuildFonts();
    setMouseTracking(true);
    setFocusPolicy(Qt::ClickFocus);
    rebuildAxis();
    qApp->installEventFilter(this);
}

bool VelocityArea::event(QEvent *event)
{
    if (event->type() == QEvent::UngrabMouse) {
        cancelInteraction();
    } else if (event->type() == QEvent::FontChange) {
        rebuildFonts();
        m_geometry.resolve();
        rebuildVisualState();
    }
    return songview::TimelineSurface::event(event);
}

bool VelocityArea::eventFilter(QObject *watched, QEvent *event)
{
    if (m_axis.mode() == VelocityAxis::Mode::Intrinsic &&
        (event->type() == QEvent::KeyPress || event->type() == QEvent::KeyRelease)) {
        const int key = static_cast<QKeyEvent *>(event)->key();
        if (key == Qt::Key_Control || key == Qt::Key_Shift || key == Qt::Key_Alt ||
            key == Qt::Key_Meta) {
            invalidateContent();
        }
    }
    return songview::TimelineSurface::eventFilter(watched, event);
}

void VelocityArea::songChanged()
{
    cancelInteraction();
    m_hoveredNote.reset();
    m_lastPresentedPlayheadTick.reset();
    m_live = {};
    m_axis = VelocityAxis(VelocityMap::resolve(nullptr, std::nullopt), {});
    publishAccessibleDescription();
    rebuildVisualState();
}

void VelocityArea::refreshLiveState(const DrawerPageLiveState &liveState)
{
    if (m_interaction != Interaction::None &&
        m_live.documentRevision == liveState.documentRevision) {
        if (m_live.playback.playheadTick != liveState.playback.playheadTick)
            presentPlayhead(liveState.playback.playheadTick);
        return;
    }
    const bool staleVelocityGesture = m_interaction != Interaction::None && !m_frozen.empty() &&
                                      m_live.documentRevision != liveState.documentRevision;
    const bool presentationOnly = m_live.documentRevision == liveState.documentRevision &&
                                  m_live.timeZoom == liveState.timeZoom &&
                                  m_live.horizontalScroll == liveState.horizontalScroll &&
                                  m_live.editCursorTick == liveState.editCursorTick &&
                                  m_live.trackColor == liveState.trackColor &&
                                  m_live.playback.playing == liveState.playback.playing &&
                                  m_live.playback.playheadTick != liveState.playback.playheadTick;
    m_live = liveState;
    if (presentationOnly) {
        if (currentContext() != m_axis.map())
            rebuildVisualState();
        presentPlayhead(liveState.playback.playheadTick);
        return;
    }
    const bool hadInteraction = m_interaction != Interaction::None;
    cancelInteraction();
    if (staleVelocityGesture)
        m_owner.announce(tr("Velocity edit cancelled because notes changed."));
    if (!hadInteraction)
        rebuildVisualState();
}

void VelocityArea::cancelInteraction()
{
    if (m_interaction == Interaction::None)
        return;
    const bool hadVelocityGesture = !m_frozen.empty();
    const SongDocument *document = m_owner.document();
    const bool staleVelocityGesture =
        hadVelocityGesture && document && m_live.documentRevision != document->revision();
    const std::vector<NoteId> selectionBeforePress = m_selectionBeforePress;
    pauseFollowScroll(false);
    m_owner.setSelection(selectionBeforePress);
    m_interaction = Interaction::None;
    m_relativeActivated = false;
    m_suppressContextMenu = false;
    clearPreview();
    if (hadVelocityGesture) {
        m_owner.cancelVelocityGesture();
        if (staleVelocityGesture)
            m_owner.announce(tr("Velocity edit cancelled because notes changed."));
    } else {
        rebuildVisualState();
    }
}

void VelocityArea::documentChanged()
{
    const bool hadInteraction = m_interaction != Interaction::None;
    cancelInteraction();
    m_hoveredNote.reset();
    if (!hadInteraction)
        rebuildVisualState();
}

void VelocityArea::tracksRemapped(const TrackRemap &)
{
    documentChanged();
}
void VelocityArea::setUseDetents(bool on)
{
    if (m_useDetents == on)
        return;
    m_useDetents = on;
    cancelInteraction();
    invalidateContent();
}

void VelocityArea::setContextChangedCallback(std::function<void()> callback)
{
    m_contextChanged = std::move(callback);
}

VelocityAreaDiagnostics VelocityArea::diagnostics() const noexcept
{
    auto diagnostics = m_diagnostics;
    diagnostics.contentBuildCount = songview::TimelineSurface::diagnostics().contentPaintCount;
    return diagnostics;
}

int VelocityArea::plotOrigin() const
{
    return m_geometry.plotOrigin;
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
    if (m_lastPresentedPlayheadTick && *m_lastPresentedPlayheadTick == tick)
        return;
    m_lastPresentedPlayheadTick = tick;
    ++m_diagnostics.playheadPresentationCount;
}

void VelocityArea::velocityGestureChanged()
{
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
    VelocityMap context = currentContext();
    if (m_hoveredNote) {
        DocNote note;
        const SongDocument *document = m_owner.document();
        if (document && document->findNote(*m_hoveredNote, &note)) {
            activeValues.push_back(displayedVelocity(note));
            context = contextForNote(note);
        }
    } else {
        const std::vector<DocNote> notes = selectedNotes();
        activeValues.reserve(std::max(notes.size(), m_frozen.size()));
        for (const DocNote &note : notes)
            activeValues.push_back(displayedVelocity(note));
    }
    const VelocityAxisGeometry geometry{
        double(height()),
        double(layout::space(layout::Space::Three)),
        double(std::max(0, plotOrigin() - layout::singlePixel())),
        double(layout::space(layout::Space::Two)),
        double(layout::space(layout::Space::One)),
        double(m_captionFontHeight),
        double(m_geometry.densityThresholdD1),
        double(m_geometry.densityThresholdD2),
        double(m_geometry.densityThresholdD3),
        double(m_geometry.densityThresholdD4),
    };
    const bool contextChanged = context != m_axis.map();
    m_axis = VelocityAxis(context, geometry, activeValues.data(), activeValues.size());
    publishAccessibleDescription();
    if (contextChanged && m_contextChanged)
        m_contextChanged();
}

void VelocityArea::setHoveredNote(std::optional<NoteId> noteId)
{
    if (m_hoveredNote == noteId)
        return;
    m_hoveredNote = noteId;
    rebuildAxis();
    invalidateContent();
}

void VelocityArea::updateHoveredNote(const QPointF &position)
{
    const std::optional<DocNote> hit = notesAt(position, false);
    setHoveredNote(hit ? std::optional<NoteId>{hit->noteId} : std::nullopt);
}

bool VelocityArea::detentsDisabled() const
{
    return !m_useDetents;
}

bool VelocityArea::detentsUnlocked(Qt::KeyboardModifiers modifiers, bool allowShift) const
{
    return detentsDisabled() || detentUnlockHeld(modifiers, allowShift);
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
    const DrawerPageVoiceContext context = m_owner.voiceContext(note.tick);
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

std::optional<DocNote> VelocityArea::notesAt(const QPointF &position, bool includeStems) const
{
    const std::vector<NoteId> &selection = m_owner.selection();
    const double radius = double(m_geometry.startNodeHitRadius);
    const double radiusSquared = radius * radius;
    std::optional<DocNote> primary;
    bool primaryCircleHit = false;
    bool primarySelected = false;
    double primaryDistanceSquared = 0.0;
    std::size_t primaryOrder = 0;
    std::size_t order = 0;
    for (const DocNote &note : primaryTrackNotes()) {
        const QPointF delta = nodeRect(note).center() - position;
        const double distanceSquared = delta.x() * delta.x() + delta.y() * delta.y();
        const bool circleHit = distanceSquared <= radiusSquared;
        const bool stemHit = includeStems && stemRect(note).contains(position);
        if (!circleHit && !stemHit) {
            ++order;
            continue;
        }
        const bool selected = contains(selection, note.noteId);
        const bool better = !primary || circleHit > primaryCircleHit ||
                            (circleHit == primaryCircleHit && selected > primarySelected) ||
                            (circleHit == primaryCircleHit && selected == primarySelected &&
                             (distanceSquared < primaryDistanceSquared ||
                              (distanceSquared == primaryDistanceSquared && order > primaryOrder)));
        if (better) {
            primary = note;
            primaryCircleHit = circleHit;
            primarySelected = selected;
            primaryDistanceSquared = distanceSquared;
            primaryOrder = order;
        }
        ++order;
    }
    return primary;
}

QRectF VelocityArea::nodeRect(const DocNote &note) const
{
    const double radius = double(m_geometry.startNodeHitRadius);
    const uint8_t velocity = displayedVelocity(note);
    return QRectF(xForTick(note.tick) - radius, yForNote(note, velocity) - radius, radius * 2.0,
                  radius * 2.0);
}

QRectF VelocityArea::stemRect(const DocNote &note) const
{
    const double verticalRadius = double(m_geometry.durationLineVerticalRadius);
    const double horizontalSlop = double(m_geometry.durationLineHorizontalSlop);
    const double start = xForTick(note.tick) - horizontalSlop;
    const double end = xForTick(note.tick + note.duration) + horizontalSlop;
    const uint8_t velocity = displayedVelocity(note);
    return QRectF(start, yForNote(note, velocity) - verticalRadius, std::max(0.0, end - start),
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

double VelocityArea::levelBoundaryY(const VelocityMap &map, int lowerLevel) const
{
    const VelocityLevelRange lower = map.levelRange(lowerLevel);
    const VelocityLevelRange upper = map.levelRange(lowerLevel + 1);
    return (yForVelocity(lower.last) + yForVelocity(upper.first)) / 2.0;
}

double VelocityArea::levelCenterY(const VelocityMap &map, int level) const
{
    const double lowerBoundary = level == 0 ? m_axis.bottom() : levelBoundaryY(map, level - 1);
    const double upperBoundary =
        level + 1 == int(map.levelCount()) ? m_axis.top() : levelBoundaryY(map, level);
    return (lowerBoundary + upperBoundary) / 2.0;
}

double VelocityArea::yForNote(const DocNote &note, uint8_t velocity) const
{
    VelocityMap map = contextForNote(note);
    bool frozen = false;
    for (const FrozenNote &frozenNote : m_frozen) {
        if (frozenNote.noteId == note.noteId) {
            map = frozenNote.map;
            frozen = true;
            break;
        }
    }
    if ((frozen && m_detentUnlock) || detentsDisabled())
        return yForVelocity(velocity);
    if (const std::optional<std::size_t> level = map.levelOf(velocity))
        return levelCenterY(map, int(*level));
    return yForVelocity(velocity);
}

uint8_t VelocityArea::displayedVelocity(const DocNote &note) const
{
    if (const std::optional<uint8_t> preview = m_owner.previewVelocity(note.noteId))
        return *preview;
    return note.velocity;
}

double VelocityArea::pxPerBeat() const
{
    return std::max(1.0, m_live.timeZoom > 1.0 ? m_live.timeZoom
                                               : double(m_geometry.defaultPixelsPerBeat));
}

bool VelocityArea::inRuler(const QPointF &position) const
{
    return m_axis.inRuler(position, double(plotOrigin()));
}

int VelocityArea::rulerVelocityAt(const QPointF &position) const
{
    return m_axis.rulerVelocityAt(position, double(m_captionFontHeight));
}

void VelocityArea::setSelection(const std::vector<NoteId> &selection)
{
    m_owner.setSelection(selection);
    rebuildVisualState();
}

void VelocityArea::appendFrozenNotes(const std::vector<DocNote> &notes)
{
    m_frozen.reserve(m_frozen.size() + notes.size());
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
    }
}

void VelocityArea::beginFrozenGesture(const std::vector<DocNote> &notes, Interaction interaction,
                                      const QPointF &position, bool detentUnlock)
{
    const std::optional<NoteId> pressedNote = m_pressedNote;
    const std::vector<NoteId> selectionBeforePress = m_selectionBeforePress;
    const bool controlPress = m_controlPress;
    clearPreview();
    m_pressedNote = pressedNote;
    m_selectionBeforePress = selectionBeforePress;
    m_controlPress = controlPress;
    if (!hasDocument() || notes.empty())
        return;
    m_detentUnlock = detentUnlock;
    appendFrozenNotes(notes);
    if (!m_owner.beginVelocityGesture(notes)) {
        clearPreview();
        return;
    }
    if (m_pressedNote && std::any_of(m_frozen.begin(), m_frozen.end(),
                                     [noteId = *m_pressedNote](const FrozenNote &note) {
                                         return note.noteId == noteId;
                                     }))
        m_announcedNote = *m_pressedNote;
    m_pressPosition = position;
    m_previousPosition = position;
    m_interaction = interaction;
    m_relativeActivated = false;
    pauseFollowScroll(true);
}

void VelocityArea::beginVelocityPaint(const QPointF &position, bool detentUnlock)
{
    const std::optional<NoteId> pressedNote = m_pressedNote;
    const std::vector<NoteId> selectionBeforePress = m_selectionBeforePress;
    const bool controlPress = m_controlPress;
    clearPreview();
    m_pressedNote = pressedNote;
    m_selectionBeforePress = selectionBeforePress;
    m_controlPress = controlPress;
    if (!hasDocument())
        return;
    m_detentUnlock = detentUnlock;
    m_pressPosition = position;
    m_previousPosition = position;
    m_interaction = Interaction::Paint;
    m_relativeActivated = false;
    pauseFollowScroll(true);
}

void VelocityArea::paintSelectedNodesBetween(const QPointF &first, const QPointF &last)
{
    const double deltaX = last.x() - first.x();
    const double radius = double(m_geometry.startNodeHitRadius);
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
    if (m_frozen.empty()) {
        const std::vector<DocNote> selection = selectedNotes();
        if (!m_owner.beginVelocityGesture(selection))
            return;
    }
    appendFrozenNotes(notes);
    std::vector<NoteVelocity> updates;
    updates.reserve(notes.size());
    for (std::size_t index = 0; index < notes.size(); ++index) {
        const auto it = std::find_if(m_frozen.begin(), m_frozen.end(),
                                     [&notes, index](const FrozenNote &frozen) {
                                         return frozen.noteId == notes[index].noteId;
                                     });
        if (it == m_frozen.end())
            continue;
        uint8_t velocity = 1;
        if (m_detentUnlock)
            velocity = exactVelocity(m_axis.yToVelocity(ys[index]));
        else if (m_axis.mode() == VelocityAxis::Mode::Continuous)
            velocity = it->map.canonicalize(m_axis.yToVelocity(ys[index]));
        else
            velocity = it->map.representative(m_axis.yToLevel(ys[index]));
        updates.push_back({it->noteId, int(velocity)});
    }
    if (!updates.empty())
        m_owner.updateVelocityGesture(updates);
    m_announcedNote = notes.front().noteId;
    announcePreview();
}

void VelocityArea::updateRampPreview(const QPointF &position)
{
    if (m_frozen.empty())
        return;
    const double radius = double(m_geometry.startNodeHitRadius);
    const double firstX = std::min(m_pressPosition.x(), position.x()) - radius;
    const double lastX = std::max(m_pressPosition.x(), position.x()) + radius;
    std::vector<NoteVelocity> updates;
    updates.reserve(m_frozen.size());
    for (const FrozenNote &note : m_frozen) {
        const double x = xForTick(note.tick);
        uint8_t velocity = note.velocity;
        if (x >= firstX && x <= lastX) {
            const double y = ui::linearRampValue(x, m_pressPosition.x(), m_pressPosition.y(),
                                                 position.x(), position.y());
            if (m_detentUnlock)
                velocity = exactVelocity(m_axis.yToVelocity(y));
            else if (m_axis.mode() == VelocityAxis::Mode::Continuous)
                velocity = note.map.canonicalize(m_axis.yToVelocity(y));
            else
                velocity = note.map.representative(m_axis.yToLevel(y));
            m_announcedNote = note.noteId;
        }
        updates.push_back({note.noteId, int(velocity)});
    }
    m_owner.updateVelocityGesture(updates);
    announcePreview();
}

void VelocityArea::updateRelativePreview(const QPointF &position)
{
    if (m_frozen.empty())
        return;
    const double distance =
        std::abs(position.x() - m_pressPosition.x()) + std::abs(position.y() - m_pressPosition.y());
    if (!m_relativeActivated) {
        const bool intrinsicChange =
            !m_detentUnlock && m_axis.mode() == VelocityAxis::Mode::Intrinsic &&
            m_axis.yToLevel(position.y()) != m_axis.yToLevel(m_pressPosition.y());
        if (distance < double(m_geometry.relativeDragActivationDistance) && !intrinsicChange)
            return;
        m_relativeActivated = true;
    }
    std::vector<NoteVelocity> updates;
    updates.reserve(m_frozen.size());
    if (m_detentUnlock || m_axis.mode() == VelocityAxis::Mode::Continuous) {
        const int delta =
            m_axis.yToVelocity(position.y()) - m_axis.yToVelocity(m_pressPosition.y());
        for (const FrozenNote &note : m_frozen) {
            const int proposal = int(note.velocity) + delta;
            const uint8_t velocity =
                m_detentUnlock ? exactVelocity(proposal) : note.map.canonicalize(proposal);
            updates.push_back({note.noteId, int(velocity)});
        }
    } else {
        const int levelDelta = m_axis.yToLevel(position.y()) - m_axis.yToLevel(m_pressPosition.y());
        for (const FrozenNote &note : m_frozen)
            updates.push_back(
                {note.noteId, int(note.map.moveLevels(note.exactOrigin, levelDelta))});
    }
    m_owner.updateVelocityGesture(updates);
    announcePreview();
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
    const bool hadVelocityGesture = !m_frozen.empty();
    pauseFollowScroll(false);
    m_interaction = Interaction::None;
    m_relativeActivated = false;
    m_suppressContextMenu = false;
    clearPreview();
    if (hadVelocityGesture) {
        if (!commit) {
            m_owner.cancelVelocityGesture();
        } else {
            switch (m_owner.commitVelocityGesture()) {
            case SongView::VelocityCommitResult::Committed:
                m_owner.announce(tr("Painted note velocities."));
                break;
            case SongView::VelocityCommitResult::Unchanged:
                rebuildVisualState();
                break;
            case SongView::VelocityCommitResult::Rejected:
                m_owner.announce(tr("Velocity edit cancelled because notes changed."));
                break;
            case SongView::VelocityCommitResult::NoGesture:
                break;
            }
        }
    } else {
        rebuildVisualState();
    }
}

void VelocityArea::announcePreview()
{
    const SongDocument *document = m_owner.document();
    if (!document || m_frozen.empty())
        return;
    if (!m_announcedNote.isAssigned())
        m_announcedNote = m_frozen.front().noteId;
    for (const FrozenNote &note : m_frozen) {
        if (note.noteId != m_announcedNote)
            continue;
        const uint8_t velocity = m_owner.previewVelocity(note.noteId).value_or(note.velocity);
        const uint64_t clocks =
            document->ticksPerClock() == 0 ? 0 : note.duration / document->ticksPerClock();
        const DrawerPageNoteStatus status{note.key, velocity, uint8_t(effectiveVelocity(velocity)),
                                          note.duration, clocks};
        m_owner.showDrawerPageNoteStatus(std::optional<DrawerPageNoteStatus>{status});
        return;
    }
}

void VelocityArea::pauseFollowScroll(bool paused)
{
    m_owner.setFollowScrollPaused(paused);
}

void VelocityArea::clearPreview()
{
    m_frozen.clear();
    m_bandPreview.clear();
    m_bandRect = {};
    m_pressedNote.reset();
    m_selectionBeforePress.clear();
    m_controlPress = false;
    m_detentUnlock = false;
    m_announcedNote = NoteId{};
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
    const double labelHeight = double(m_captionFontHeight);
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
    axisStyle.labelColor = themes::color(themes::Role::song_view_primary_text);
    axisStyle.accentColor = selectedColor;
    axisStyle.labelFont = m_captionFont;
    axisStyle.emphasizedFont = m_boldCaptionFont;
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
    axisStyle.continuousRuler = detentsDisabled();
    std::optional<DocNote> hoveredNote;
    if (m_hoveredNote) {
        DocNote note;
        const SongDocument *document = m_owner.document();
        if (document && document->findNote(*m_hoveredNote, &note))
            hoveredNote = note;
    }
    axisStyle.relativeGesture =
        m_relativeActivated || m_owner.selection().size() > 1 || hoveredNote.has_value();
    m_axis.paintRuler(painter, axisStyle);
    painter.save();
    painter.setClipRect(axisStyle.contentClip, Qt::IntersectClip);
    m_owner.paintGrid(painter, QRect(origin, 0, width, height()), origin);
    const MidiTimeline *timeline = m_owner.timeline();
    if (timeline) {
        const double ticksPerBeat = double(std::max(1u, timeline->ticksPerBeat));
        const double ticksPerPixel = ticksPerBeat / pxPerBeat();
        const uint64_t firstTick =
            uint64_t(std::max(0.0, std::floor(m_live.horizontalScroll * ticksPerPixel)));
        const uint64_t lastTick = std::max(
            firstTick + 1,
            uint64_t(std::ceil((m_live.horizontalScroll + double(width)) * ticksPerPixel)));
        uint64_t sectionTick = firstTick;
        painter.setPen(QPen(themes::color(themes::Role::song_view_psg_velocity_levels),
                            layout::singlePixel()));
        while (sectionTick < lastTick) {
            const DrawerPageVoiceContext context = m_owner.voiceContext(sectionTick);
            const uint64_t sectionEnd = std::min(lastTick, context.endTick);
            if (sectionEnd <= sectionTick)
                break;
            const VelocityMap map = VelocityMap::resolve(context.voice, std::nullopt);
            if (map.isPsg()) {
                const double left =
                    std::clamp(xForTick(sectionTick), double(origin), double(origin + width));
                const double right =
                    std::clamp(xForTick(sectionEnd), double(origin), double(origin + width));
                for (std::size_t level = 0; level + 1 < map.levelCount(); ++level) {
                    const double y = levelBoundaryY(map, int(level));
                    painter.drawLine(QPointF(left, y), QPointF(right, y));
                }
            }
            sectionTick = sectionEnd;
        }
    }
    const std::vector<NoteId> selection = m_owner.selection();
    const std::vector<DocNote> notes = primaryTrackNotes();
    const auto selected = [&selection, this](const DocNote &note) {
        return contains(selection, note.noteId) || contains(m_bandPreview, note.noteId);
    };
    const auto selectedCount = std::count_if(notes.begin(), notes.end(), selected);
    const bool dimUnselectedNodes = selectedCount > 1;
    const QColor unselectedNodeColor = dimUnselectedNodes ? palette().mid().color() : trackColor;
    const double stemWidth = m_geometry.stemDipWidth / devicePixelRatioF();
    painter.setPen(QPen(stemColor, stemWidth, Qt::SolidLine, Qt::FlatCap));
    for (const DocNote &note : notes) {
        if (selected(note))
            continue;
        const uint8_t velocity = displayedVelocity(note);
        const double start = xForTick(note.tick);
        const double end = std::max(start + 1.0, xForTick(note.tick + note.duration));
        painter.drawLine(QPointF(start, yForNote(note, velocity)),
                         QPointF(end, yForNote(note, velocity)));
    }
    painter.setPen(QPen(selectedColor, m_geometry.selectedStemDipWidth / devicePixelRatioF(),
                        Qt::SolidLine, Qt::FlatCap));
    for (const DocNote &note : notes) {
        if (!selected(note))
            continue;
        const uint8_t velocity = displayedVelocity(note);
        const double start = xForTick(note.tick);
        const double end = std::max(start + 1.0, xForTick(note.tick + note.duration));
        painter.drawLine(QPointF(start, yForNote(note, velocity)),
                         QPointF(end, yForNote(note, velocity)));
    }
    painter.setRenderHint(QPainter::Antialiasing, true);
    painter.setPen(dimUnselectedNodes ? QPen(Qt::NoPen)
                                      : QPen(Qt::black, m_geometry.nodeOutlineDipWidth));
    painter.setBrush(unselectedNodeColor);
    for (const DocNote &note : notes) {
        if (selected(note))
            continue;
        const uint8_t velocity = displayedVelocity(note);
        painter.drawEllipse(QPointF(xForTick(note.tick), yForNote(note, velocity)),
                            m_geometry.nodePaintRadius, m_geometry.nodePaintRadius);
    }
    for (const DocNote &note : notes) {
        if (!selected(note))
            continue;
        const uint8_t velocity = displayedVelocity(note);
        const QPointF center(xForTick(note.tick), yForNote(note, velocity));
        painter.setPen(QPen(selectedColor, m_geometry.selectedNodeRingDipWidth));
        painter.setBrush(Qt::NoBrush);
        painter.drawEllipse(center, m_geometry.selectedNodeRingRadius,
                            m_geometry.selectedNodeRingRadius);
        painter.setPen(QPen(Qt::black, m_geometry.nodeOutlineDipWidth));
        painter.setBrush(trackColor);
        painter.drawEllipse(center, m_geometry.nodePaintRadius, m_geometry.nodePaintRadius);
    }
    if (m_interaction == Interaction::Ramp) {
        painter.setPen(QPen(themes::color(themes::Role::song_view_edit_preview_outline),
                            layout::singlePixel()));
        painter.drawLine(m_pressPosition, m_previousPosition);
    }
    if (m_interaction == Interaction::Band)
        songview::paintSelectionReticle(painter, m_bandRect);
    painter.setRenderHint(QPainter::Antialiasing, false);
    painter.setPen(QPen(themes::color(themes::Role::song_view_edit_cursor), layout::singlePixel(),
                        Qt::DashLine));
    painter.drawLine(QPointF(xForTick(m_live.editCursorTick), 0),
                     QPointF(xForTick(m_live.editCursorTick), height()));
    painter.restore();
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
    m_pressedNote.reset();
    if (event->button() == Qt::MiddleButton) {
        m_interaction = Interaction::Pan;
        pauseFollowScroll(true);
        event->accept();
        return;
    }
    if (event->button() == Qt::RightButton) {
        if (const std::optional<DocNote> hit = notesAt(position, true))
            m_pressedNote = hit->noteId;
        m_interaction = Interaction::PendingBand;
        m_controlPress = event->modifiers().testFlag(Qt::ControlModifier);
        if (m_pressedNote && !m_controlPress && !contains(m_selectionBeforePress, *m_pressedNote))
            setSelection({*m_pressedNote});
        m_suppressContextMenu = true;
        pauseFollowScroll(true);
        event->accept();
        return;
    }
    if (event->button() != Qt::LeftButton) {
        event->ignore();
        return;
    }
    const bool inRulerPosition = inRuler(position);
    const bool detentUnlock = detentsUnlocked(
        event->modifiers(), !inRulerPosition && event->modifiers().testFlag(Qt::ShiftModifier));
    if (inRulerPosition) {
        const int velocity = detentUnlock ? exactVelocity(m_axis.yToVelocity(position.y()))
                                          : rulerVelocityAt(position);
        if (velocity >= 1) {
            const std::vector<DocNote> notes = selectedNotes();
            beginFrozenGesture(notes, Interaction::Relative, position, detentUnlock);
            std::vector<NoteVelocity> updates;
            updates.reserve(m_frozen.size());
            for (const FrozenNote &note : m_frozen)
                updates.push_back({note.noteId, velocity});
            if (!updates.empty())
                m_owner.updateVelocityGesture(updates);
            finishGesture(true);
        }
        event->accept();
        return;
    }
    if (event->modifiers().testFlag(Qt::ShiftModifier)) {
        beginFrozenGesture(selectedNotes(), Interaction::Ramp, position, detentUnlock);
        updateRampPreview(position);
        event->accept();
        return;
    }
    const std::optional<DocNote> hit = notesAt(position, true);
    if (hit)
        m_pressedNote = hit->noteId;
    m_controlPress = event->modifiers().testFlag(Qt::ControlModifier);
    if (!hit) {
        beginVelocityPaint(position, detentUnlock);
        paintSelectedNodesBetween(position, position);
        event->accept();
        return;
    }
    if (m_controlPress) {
        std::vector<NoteId> selection = m_selectionBeforePress;
        if (!contains(selection, hit->noteId))
            selection.push_back(hit->noteId);
        setSelection(selection);
    } else if (!contains(m_selectionBeforePress, hit->noteId)) {
        setSelection({hit->noteId});
    }
    beginFrozenGesture(selectedNotes(), Interaction::Relative, position, detentUnlock);
    event->accept();
}

void VelocityArea::mouseMoveEvent(QMouseEvent *event)
{
    const QPointF position = event->position();
    if (m_interaction == Interaction::None)
        updateHoveredNote(position);
    if (m_interaction == Interaction::Relative)
        updateRelativePreview(position);
    else if (m_interaction == Interaction::Paint)
        paintSelectedNodesBetween(m_previousPosition, position);
    else if (m_interaction == Interaction::Ramp)
        updateRampPreview(position);
    else if (m_interaction == Interaction::PendingBand) {
        const double distance = std::abs(position.x() - m_pressPosition.x()) +
                                std::abs(position.y() - m_pressPosition.y());
        if (distance >= double(QApplication::startDragDistance()))
            m_interaction = Interaction::Band;
    }
    if (m_interaction == Interaction::Band)
        updateBandPreview(position);
    else if (m_interaction == Interaction::Pan) {
        const auto requestedScroll =
            m_live.horizontalScroll - (position.x() - m_previousPosition.x());
        m_owner.setEditorHorizontalScroll(requestedScroll);
        m_live.horizontalScroll = m_owner.viewState().scrollPx;
        invalidateContent();
    }
    m_previousPosition = position;
    event->accept();
}

void VelocityArea::leaveEvent(QEvent *event)
{
    setHoveredNote(std::nullopt);
    songview::TimelineSurface::leaveEvent(event);
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
        } else if (m_controlPress && m_pressedNote) {
            std::vector<NoteId> selection = m_owner.selection();
            const auto it = std::find(selection.begin(), selection.end(), *m_pressedNote);
            if (it == selection.end())
                selection.push_back(*m_pressedNote);
            else
                selection.erase(it);
            setSelection(selection);
        } else if (!m_controlPress && !m_pressedNote) {
            setSelection({});
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
        } else if (m_interaction == Interaction::Ramp) {
            finishGesture(m_pressPosition != m_previousPosition);
        } else if (m_interaction == Interaction::Relative) {
            if (!m_relativeActivated) {
                if (m_controlPress) {
                    std::vector<NoteId> selection = m_selectionBeforePress;
                    if (m_pressedNote) {
                        const auto it =
                            std::find(selection.begin(), selection.end(), *m_pressedNote);
                        if (it == selection.end())
                            selection.push_back(*m_pressedNote);
                        else
                            selection.erase(it);
                    }
                    setSelection(selection);
                } else if (m_pressedNote) {
                    setSelection({*m_pressedNote});
                } else {
                    setSelection({});
                }
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
        m_owner.zoomTimelineAtWheel(event, position.x() - plotOrigin());
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
    QWidget::keyPressEvent(event);
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
