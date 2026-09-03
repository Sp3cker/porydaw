#include "ui/editordrawer/voicechangearea/voicechangearea.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <utility>

#include <QAction>
#include <QApplication>
#include <QContextMenuEvent>
#include <QEvent>
#include <QFocusEvent>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QResizeEvent>
#include <QWheelEvent>

#include "core/miditimeline.h"
#include "ui/contextmenu.h"
#include "ui/layout.h"
#include "ui/m4asemantics.h"
#include "ui/songview.h"
#include "ui/songview/editorselectionmodel.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/typography.h"

void VoiceChangeArea::Geometry::resolve()
{
    plotOrigin = layout::fontPx(17.5 + 13.0 / 3.0);
    markerHitRadius = layout::fontPx(3.0 / 4.0);
    hoverPaintPadding = layout::fontPx(1.0 / 6.0);
    gridMinimumCellWidth = layout::fontPx(4.0 / 3.0);
}

void VoiceChangeArea::rebuildFonts()
{
    m_titleFont = typography::bold(typography::caption(font()));
    m_captionFont = typography::regular(typography::caption(font()));
}

VoiceChangeArea::VoiceChangeArea(SongView &owner, QWidget *parent) : QWidget(parent), m_owner(owner)
{
    m_geometry.resolve();
    rebuildFonts();
    setAutoFillBackground(false);
    setMouseTracking(true);
    setFocusPolicy(Qt::ClickFocus);
}

bool VoiceChangeArea::event(QEvent *event)
{
    if (event->type() == QEvent::UngrabMouse || event->type() == QEvent::Hide) {
        cancelInteraction();
    }
    return QWidget::event(event);
}

void VoiceChangeArea::songChanged()
{
    cancelInteraction();
    m_live = {};
    m_lastPresentedPlayheadTick.reset();
    m_changeCount = -1;
    m_secondary.clear();
    m_paintTexts.fill(VoicePaintText{});
    m_voicePointsDocument = nullptr;
    // Recaptures the primary track and drops hover state before repainting.
    rebuildVisualState();
}

void VoiceChangeArea::refreshLiveState(const DrawerPageLiveState &liveState)
{
    // Recapture the primary track first: track transitions end in
    // refreshDrawerPages, and comparing against the captured track is what
    // forces the rebuild (the area owns no persistent track identity).
    const int previousTrack = m_engineTrack;
    m_engineTrack = primaryTrack();
    const bool trackChanged = m_engineTrack != previousTrack;
    if (m_interaction == Interaction::Pan &&
        m_live.documentRevision == liveState.documentRevision) {
        if (m_live.playback.playheadTick != liveState.playback.playheadTick)
            presentPlayhead(liveState.playback.playheadTick);
        return;
    }
    const bool presentationOnly = !trackChanged &&
                                  m_live.documentRevision == liveState.documentRevision &&
                                  m_live.timeZoom == liveState.timeZoom &&
                                  m_live.horizontalScroll == liveState.horizontalScroll &&
                                  m_live.editCursorTick == liveState.editCursorTick &&
                                  m_live.trackColor == liveState.trackColor &&
                                  m_live.playback.playing == liveState.playback.playing &&
                                  m_live.playback.playheadTick != liveState.playback.playheadTick;
    m_live = liveState;
    if (presentationOnly) {
        presentPlayhead(liveState.playback.playheadTick);
        return;
    }
    cancelInteraction();
    rebuildVisualState();
    presentPlayhead(liveState.playback.playheadTick);
}

void VoiceChangeArea::cancelInteraction()
{
    const bool wasPanning = m_interaction == Interaction::Pan;
    const bool wasDragging = voiceDragActive();
    m_interaction = Interaction::None;
    m_previousPosition = QPointF();
    m_suppressContextMenu = false;
    resetVoiceDrag();
    if (wasPanning || wasDragging)
        m_owner.setFollowScrollPaused(false);
    if (wasDragging) {
        unsetCursor();
        requestQuickUpdate();
    }
    clearHover();
}

void VoiceChangeArea::documentChanged()
{
    cancelInteraction();
    m_changeCount = -1;
    // Rebuild before the caller's live refresh: it recaptures the primary
    // track and republishes marker/text-derived state for the new revision.
    rebuildVisualState();
}

void VoiceChangeArea::tracksRemapped(const TrackRemap &)
{
    documentChanged();
}

int VoiceChangeArea::plotOrigin() const
{
    return m_geometry.plotOrigin;
}

int VoiceChangeArea::plotWidth() const
{
    return std::max(0, width() - plotOrigin());
}

void VoiceChangeArea::presentPlayhead(double tick)
{
    // The playhead line itself is painted by SongView's shared Quick chrome; this
    // updates the right-aligned context readout only when the displayed program
    // context changes.
    if (m_live.playback.playing && m_lastPresentedPlayheadTick &&
        *m_lastPresentedPlayheadTick != tick &&
        voiceSlotAt(uint64_t(std::round(std::max(0.0, *m_lastPresentedPlayheadTick)))) !=
            voiceSlotAt(uint64_t(std::round(std::max(0.0, tick)))))
        requestQuickUpdate();
    m_live.playback.playheadTick = tick;
    m_lastPresentedPlayheadTick = tick;
}

void VoiceChangeArea::requestQuickUpdate()
{
    m_owner.requestTimelineQuickUpdate(songview::TimelineQuickDirty::VoiceChanges);
}

void VoiceChangeArea::resizeEvent(QResizeEvent *event)
{
    QWidget::resizeEvent(event);
    if (m_hoverActive) {
        updateHover(m_owner.displayX(double(m_hoverTick), plotOrigin(), devicePixelRatioF()));
    } else {
        requestQuickUpdate();
    }
}

void VoiceChangeArea::rebuildVisualState()
{
    m_engineTrack = primaryTrack();
    const SongDocument *document = m_owner.document();
    const uint64_t revision = document ? document->revision() : 0;
    if (document != m_voicePointsDocument || revision != m_voicePointsRevision ||
        m_engineTrack != m_voicePointsTrack) {
        m_voicePoints = document && m_engineTrack >= 0
                            ? document->lanePoints(m_engineTrack, DOC_CC_VOICE)
                            : std::vector<DocLanePoint>{};
        m_voicePointsDocument = document;
        m_voicePointsRevision = revision;
        m_voicePointsTrack = m_engineTrack;
        m_changeCount = -1;
    }
    clearHover();
    requestQuickUpdate();
}

void VoiceChangeArea::clearHover()
{
    if (!m_hoverActive)
        return;
    m_hoverActive = false;
    m_hoverX = 0.0;
    m_hoverTick = 0;
    m_hoverLabel.clear();
    m_hoverLabelRect = QRectF();
    m_owner.clearTimelineQuickHover(songview::TimelineQuickHoverOwner::VoiceChanges);
    m_owner.requestTimelineQuickUpdate(songview::TimelineQuickDirty::VoiceChangesHover);
}

void VoiceChangeArea::updateHover(qreal x)
{
    const QRect plot = plotRect();
    if (!ready() || rect().isEmpty() || x < qreal(plotOrigin())) {
        clearHover();
        return;
    }
    const qreal dpr = devicePixelRatioF();
    const double tick = std::max(
        0.0, m_owner.tickAtContentX(std::max<qreal>(plotOrigin(), x) - qreal(plotOrigin())));
    const uint64_t snapped = m_owner.snapTick(tick, true);
    DocLanePoint markerPoint;
    const bool atMarker = voiceMarkerAt(x, &markerPoint);
    const uint64_t hoverTick = atMarker ? markerPoint.tick : snapped;
    const qreal lineX = m_owner.displayX(double(hoverTick), plotOrigin(), dpr);
    QString hoverLabel;
    if (!voiceMarkerAt(lineX, &markerPoint)) {
        const int slot = voiceSlotAt(hoverTick);
        if (slot >= 0 && slot < VOICEGROUP_SIZE)
            hoverLabel = paintTextFor(slot).hoverLabel;
    }
    QRectF labelRect;
    if (!hoverLabel.isEmpty()) {
        ensureHoverLabelFontCache();
        labelRect = QRectF(lineX + layout::space(layout::Space::One), plot.top(),
                           std::max<qreal>(0, plot.right() - lineX), plot.height());
    }
    if (m_hoverActive && m_hoverX == lineX && m_hoverTick == hoverTick &&
        m_hoverLabel == hoverLabel && m_hoverLabelRect == labelRect)
        return;
    m_hoverActive = true;
    m_hoverX = lineX;
    m_hoverTick = hoverTick;
    m_hoverLabel = std::move(hoverLabel);
    m_hoverLabelRect = labelRect;
    m_owner.publishTimelineQuickHover(songview::TimelineQuickHoverOwner::VoiceChanges, m_hoverTick);
    m_owner.requestTimelineQuickUpdate(songview::TimelineQuickDirty::VoiceChangesHover);
}

void VoiceChangeArea::ensureHoverLabelFontCache()
{
    m_hoverLabelFont = typography::noteName(font());
}

bool VoiceChangeArea::ready() const noexcept
{
    return m_owner.timeline() != nullptr;
}

int VoiceChangeArea::primaryTrack() const noexcept
{
    return m_owner.selectionModel().primaryTrack();
}

const VoiceChangeArea::VoicePaintText &VoiceChangeArea::paintTextFor(int program) const
{
    static const VoicePaintText invalid;
    if (program < 0 || program >= VOICEGROUP_SIZE)
        return invalid;
    auto &cache = m_paintTexts[std::size_t(program)];
    const auto *voicegroup = m_owner.voicegroup();
    const int type = voicegroup ? int(voicegroup->voices[program].type) : -1;
    const char *sourceName = voicegroup ? voicegroup->voiceNames[program] : "";
    if (cache.group == voicegroup && cache.type == type &&
        std::strncmp(cache.sourceName.data(), sourceName, VG_VOICE_NAME_LEN) == 0 &&
        !cache.label.isEmpty())
        return cache;
    cache.group = voicegroup;
    cache.type = type;
    std::strncpy(cache.sourceName.data(), sourceName, cache.sourceName.size() - 1);
    cache.sourceName.back() = '\0';
    QString name;
    QString typeName;
    if (voicegroup) {
        name = QString::fromUtf8(cache.sourceName.data()).trimmed();
        typeName = m4aVoiceTypeName(voicegroup->voices[program].type);
    }
    const QString shortName = name.isEmpty() ? (typeName.isEmpty() ? tr("Voice") : typeName)
                                             : QStringLiteral("%1 (%2)").arg(name, typeName);
    cache.label = QStringLiteral("%1 %2").arg(program, 3, 10, QLatin1Char('0')).arg(shortName);
    cache.hoverLabel =
        QStringLiteral("→ %1 %2").arg(program, 3, 10, QLatin1Char('0')).arg(shortName);
    return cache;
}

int VoiceChangeArea::voiceSlotAt(uint64_t tick) const
{
    if (m_engineTrack < 0 || m_engineTrack >= 16)
        return -1;
    const auto *timeline = m_owner.timeline();
    if (!timeline || !m_owner.voicegroup())
        return -1;
    int program = timeline->tracks[m_engineTrack].firstProgram;
    for (const DocLanePoint &point : m_voicePoints) {
        if (point.tick > tick)
            break;
        program = point.value;
    }
    return program;
}

QRect VoiceChangeArea::plotRect() const
{
    return QRect(plotOrigin(), 0, plotWidth(), height());
}

bool VoiceChangeArea::voiceMarkerAt(qreal x, DocLanePoint *out) const
{
    if (m_engineTrack < 0 || !out)
        return false;
    const qreal dpr = devicePixelRatioF();
    const DocLanePoint *marker = nullptr;
    qreal distance = qreal(m_geometry.markerHitRadius) + 1;
    for (const DocLanePoint &point : m_voicePoints) {
        const qreal candidate =
            std::abs(m_owner.displayX(double(point.tick), plotOrigin(), dpr) - x);
        if (candidate <= qreal(m_geometry.markerHitRadius) && (!marker || candidate <= distance)) {
            marker = &point;
            distance = candidate;
        }
    }
    if (!marker)
        return false;
    *out = *marker;
    return true;
}

bool VoiceChangeArea::voiceDragActive() const noexcept
{
    return m_voiceDrag && m_voiceDrag->phase == VoiceDragState::Phase::Active;
}

void VoiceChangeArea::resetVoiceDrag()
{
    m_voiceDrag.reset();
}

void VoiceChangeArea::mousePressEvent(QMouseEvent *event)
{
    SongDocument *document = m_owner.document();
    if (!document) {
        event->ignore();
        return;
    }
    const QPointF position = event->position();
    m_previousPosition = position;
    const bool inPlot = position.x() >= qreal(plotOrigin());
    if (event->button() == Qt::MiddleButton && inPlot) {
        setFocus(Qt::MouseFocusReason);
        m_interaction = Interaction::Pan;
        clearHover();
        m_owner.setFollowScrollPaused(true);
        event->accept();
        return;
    }
    if (event->button() == Qt::RightButton) {
        m_suppressContextMenu = true;
        if (inPlot) {
            setFocus(Qt::MouseFocusReason);
            showContextMenu(event->globalPosition().toPoint());
        }
        event->accept();
        return;
    }
    if (event->button() == Qt::LeftButton) {
        if (inPlot) {
            setFocus(Qt::MouseFocusReason);
            DocLanePoint point;
            if (voiceMarkerAt(position.x(), &point)) {
                m_voiceDrag = VoiceDragState{
                    .phase = VoiceDragState::Phase::Pending,
                    .pressPosition = position,
                    .engineTrack = m_engineTrack,
                    .point = point,
                    .revision = document->revision(),
                    .previewTick = point.tick,
                };
            }
        }
        event->accept();
        return;
    }
    event->ignore();
}

void VoiceChangeArea::mouseDoubleClickEvent(QMouseEvent *event)
{
    if (event->button() == Qt::LeftButton && event->position().x() >= qreal(plotOrigin()))
        showPicker(event->globalPosition().toPoint());
    event->accept();
}

void VoiceChangeArea::mouseMoveEvent(QMouseEvent *event)
{
    const QPointF position = event->position();
    if (m_voiceDrag) {
        if (m_voiceDrag->phase == VoiceDragState::Phase::Pending) {
            const qreal horizontalDistance =
                std::abs(position.x() - m_voiceDrag->pressPosition.x());
            if (horizontalDistance < QApplication::startDragDistance()) {
                event->accept();
                return;
            }
            m_voiceDrag->phase = VoiceDragState::Phase::Active;
            clearHover();
            m_owner.setFollowScrollPaused(true);
            setCursor(Qt::SizeHorCursor);
            requestQuickUpdate();
        }
        const double rawTick =
            std::max(0.0, m_owner.tickAtContentX(std::max<qreal>(plotOrigin(), position.x()) -
                                                 qreal(plotOrigin())));
        const uint64_t tick = m_owner.snapTick(rawTick, event->modifiers() & Qt::AltModifier);
        if (tick != m_voiceDrag->previewTick) {
            m_voiceDrag->previewTick = tick;
            requestQuickUpdate();
        }
        m_previousPosition = position;
        event->accept();
        return;
    }
    if (m_interaction == Interaction::Pan) {
        const auto requestedScroll =
            m_live.horizontalScroll - (position.x() - m_previousPosition.x());
        m_owner.setEditorHorizontalScroll(requestedScroll);
        m_live.horizontalScroll = m_owner.viewState().scrollPx;
        requestQuickUpdate();
    } else if (m_interaction == Interaction::None) {
        updateHover(position.x());
    }
    m_previousPosition = position;
    event->accept();
}

void VoiceChangeArea::mouseReleaseEvent(QMouseEvent *event)
{
    if (event->button() == Qt::MiddleButton && m_interaction == Interaction::Pan) {
        m_owner.setFollowScrollPaused(false);
        m_interaction = Interaction::None;
        event->accept();
        return;
    }
    if (event->button() == Qt::LeftButton && m_voiceDrag) {
        const VoiceDragState completed = *m_voiceDrag;
        const bool active = voiceDragActive();
        resetVoiceDrag();
        if (active) {
            m_owner.setFollowScrollPaused(false);
            unsetCursor();
            requestQuickUpdate();
        }
        SongDocument *document = m_owner.document();
        if (active && completed.previewTick != completed.point.tick && document &&
            document->revision() == completed.revision) {
            document->moveLanePoints({{completed.engineTrack, DOC_CC_VOICE, completed.point,
                                       completed.previewTick, completed.point.value}});
            m_owner.refreshAllDrawerPages();
        }
        event->accept();
        return;
    }
    event->ignore();
}

void VoiceChangeArea::leaveEvent(QEvent *event)
{
    clearHover();
    QWidget::leaveEvent(event);
}

void VoiceChangeArea::wheelEvent(QWheelEvent *event)
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
    m_owner.zoomTimelineAtWheel(event, position.x() - plotOrigin());
    event->accept();
}

void VoiceChangeArea::keyPressEvent(QKeyEvent *event)
{
    if (event->key() == Qt::Key_Escape) {
        cancelInteraction();
        event->accept();
        return;
    }
    QWidget::keyPressEvent(event);
}

void VoiceChangeArea::focusOutEvent(QFocusEvent *event)
{
    cancelInteraction();
    QWidget::focusOutEvent(event);
}

void VoiceChangeArea::contextMenuEvent(QContextMenuEvent *event)
{
    if (m_suppressContextMenu && event->reason() == QContextMenuEvent::Mouse) {
        m_suppressContextMenu = false;
        event->accept();
        return;
    }
    m_suppressContextMenu = false;
    if (m_owner.document() && event->pos().x() >= plotOrigin()) {
        setFocus(Qt::MouseFocusReason);
        showContextMenu(event->globalPos());
        event->accept();
        return;
    }
    event->ignore();
}

void VoiceChangeArea::showPicker(const QPoint &globalPosition)
{
    SongDocument *const sourceDocument = m_owner.document();
    if (!sourceDocument || m_engineTrack < 0)
        return;
    const int track = m_engineTrack;
    const qreal x = mapFromGlobal(globalPosition).x();
    DocLanePoint markerPoint;
    const DocLanePoint *marker = voiceMarkerAt(x, &markerPoint) ? &markerPoint : nullptr;
    const double rawTick = std::max(
        0.0, m_owner.tickAtContentX(std::max<qreal>(plotOrigin(), x) - qreal(plotOrigin())));
    const uint64_t tick = marker ? marker->tick : m_owner.snapTick(rawTick, false);
    const int current = marker ? marker->value : voiceSlotAt(tick);
    int selectedVoice = 0;
    if (!m_owner.pickVoice(marker ? tr("Change voice") : tr("Insert voice change"),
                           std::max(0, current), &selectedVoice))
        return;
    // Modal UI can outlive its initiating song or track. Only commit back to
    // that still-current context, and re-resolve the point so undo/import
    // activity while the picker was open cannot create a stale undo step.
    SongDocument *document = m_owner.document();
    if (document != sourceDocument || primaryTrack() != track)
        return;
    DocLanePoint existing;
    if (document->findLanePoint(track, DOC_CC_VOICE, tick, &existing)) {
        if (existing.value == selectedVoice)
            return;
        document->moveLanePoints({{track, DOC_CC_VOICE, existing, tick, selectedVoice}});
    } else {
        document->addLanePoint(track, DOC_CC_VOICE, tick, selectedVoice);
    }
    m_owner.refreshAllDrawerPages();
}

void VoiceChangeArea::showContextMenu(const QPoint &globalPosition)
{
    SongDocument *const sourceDocument = m_owner.document();
    if (!sourceDocument || m_engineTrack < 0)
        return;
    const int track = m_engineTrack;
    const qreal x = mapFromGlobal(globalPosition).x();
    DocLanePoint markerPoint;
    const bool hasMarker = voiceMarkerAt(x, &markerPoint);
    ui::ContextMenu menu(this);
    QAction *change = nullptr;
    QAction *insert = nullptr;
    QAction *remove = nullptr;
    if (hasMarker) {
        change = menu.addAction(tr("Change voice"));
        remove = menu.addAction(tr("Delete"));
    } else {
        insert = menu.addAction(tr("Insert voice change"));
    }
    QAction *chosen = menu.exec(globalPosition);
    if (!chosen || m_owner.document() != sourceDocument || primaryTrack() != track)
        return;
    if (chosen == change || chosen == insert) {
        showPicker(globalPosition);
        return;
    }
    DocLanePoint currentMarker;
    if (!sourceDocument->findLanePoint(track, DOC_CC_VOICE, markerPoint.tick, &currentMarker))
        return;
    sourceDocument->deleteLanePoints(track, DOC_CC_VOICE, {currentMarker});
    m_owner.refreshAllDrawerPages();
}
