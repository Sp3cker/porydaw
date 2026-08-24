#include "ui/editordrawer/velocityarea/velocityarea.h"

#include <algorithm>
#include <cmath>
#include <optional>
#include <string_view>
#include <utility>
#include <vector>

#include <QEvent>
#include <QFontMetrics>
#include <QKeyEvent>
#include <QObject>
#include <QRegion>

#include "ui/editordrawer/velocityarea/detail.h"
#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/typography.h"

using velocityarea::detail::contains;

namespace {

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
    m_boldCaptionFont = typography::bold(m_captionFont);
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
    presentPlayhead(liveState.playback.playheadTick);
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
    m_owner.selectionModel().setNoteSelection(selectionBeforePress);
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
    m_axis = VelocityAxis(context, geometry, activeValues);
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
    const std::string_view description = m_axis.accessibleDescription();
    setAccessibleDescription(QString::fromLatin1(description.data(), int(description.size())));
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
    for (const NoteId noteId : m_owner.selectionModel().noteSelection()) {
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
    return document->notesForTrack(m_owner.selectionModel().primaryTrack());
}

std::optional<DocNote> VelocityArea::notesAt(const QPointF &position, bool includeStems) const
{
    const std::vector<NoteId> &selection = m_owner.selectionModel().noteSelection();
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
    m_owner.selectionModel().setNoteSelection(selection);
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
