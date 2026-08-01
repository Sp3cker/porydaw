#include "ui/automationpage.h"

#include <algorithm>
#include <cmath>

#include <QEvent>
#include <QScrollArea>
#include <QVBoxLayout>

#include "core/songdocument.h"
#include "ui/automationarea.h"
#include "ui/layout.h"
#include "ui/songview.h"

AutomationPage::AutomationPage(SongView &owner, QWidget *parent)
    : QWidget(parent)
    , m_owner(owner)
{
    auto *box = new QVBoxLayout(this);
    box->setContentsMargins(0, 0, 0, 0);
    box->setSpacing(0);
    m_scroll = new QScrollArea(this);
    m_scroll->setObjectName(QStringLiteral("automationScroll"));
    m_scroll->setFrameShape(QFrame::NoFrame);
    m_scroll->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    m_scroll->setWidgetResizable(true);
    m_scroll->setFocusPolicy(Qt::NoFocus);
    m_scroll->setMinimumHeight(layout::editorGeometry().automationRowDefaultHeight
                               + layout::editorGeometry().addAutomationLaneStripHeight);
    m_area = new AutomationArea(this, m_scroll);
    m_scroll->setWidget(m_area);
    box->addWidget(m_scroll);
}

AutomationPage::~AutomationPage() = default;

bool AutomationPage::event(QEvent *event)
{
    if (event->type() == QEvent::Hide || event->type() == QEvent::WindowDeactivate)
        cancelInteraction();
    return QWidget::event(event);
}

bool AutomationPage::ready() const noexcept
{
    return timeline() != nullptr;
}

const SongViewModel &AutomationPage::model() const noexcept
{
    return m_owner.model();
}

const MidiTimeline *AutomationPage::timeline() const noexcept
{
    return m_owner.timeline();
}

SongDocument *AutomationPage::document() const noexcept
{
    return m_owner.document();
}

const LoadedVoiceGroup *AutomationPage::voicegroup() const noexcept
{
    return m_owner.voicegroup();
}

void AutomationPage::songChanged()
{
    cancelInteraction();
    m_viewState = m_owner.editorViewState();
    rebuildModel();
}

void AutomationPage::refreshLiveState(const EditorPageLiveState &liveState)
{
    m_liveState = liveState;
    m_viewState = m_owner.editorViewState();
    const int track = selectedTrack();
    if (track != m_rowsTrack) {
        m_rowsTrack = track;
        m_area->rebuildRows();
    } else {
        m_area->invalidateContent();
    }
}

void AutomationPage::cancelInteraction()
{
    if (m_area)
        m_area->cancelInteraction();
}

void AutomationPage::documentChanged()
{
    cancelInteraction();
    m_viewState = m_owner.editorViewState();
    rebuildModel();
}

int AutomationPage::selectedTrack() const noexcept
{
    return m_owner.selectedTrack();
}

uint64_t AutomationPage::snapTick(double tick, bool fineMode) const noexcept
{
    return m_owner.snapTick(tick, fineMode);
}

EditorPageGridState AutomationPage::gridState(uint64_t tick, bool fineMode) const noexcept
{
    return m_owner.gridState(tick, fineMode);
}

uint64_t AutomationPage::nextGridTick(uint64_t tick, bool fineMode, uint64_t limit) const noexcept
{
    if (tick >= limit)
        return limit;
    const uint64_t spacing = std::max<uint64_t>(1, gridState(tick, fineMode).snapTicks
                                                       ? (fineMode ? gridState(tick, fineMode).snapTicks
                                                                   : gridState(tick, fineMode).gridTicks)
                                                       : 1);
    const uint64_t candidate = spacing >= limit - tick ? limit : tick + spacing;
    if (std::max<uint64_t>(1, gridState(candidate, fineMode).snapTicks
                                  ? (fineMode ? gridState(candidate, fineMode).snapTicks
                                              : gridState(candidate, fineMode).gridTicks)
                                  : 1)
        == spacing)
        return candidate;
    uint64_t first = tick + 1;
    uint64_t last = candidate;
    while (first < last) {
        const uint64_t probe = first + (last - first) / 2;
        const auto state = gridState(probe, fineMode);
        const uint64_t probeSpacing =
            std::max<uint64_t>(1, state.snapTicks ? (fineMode ? state.snapTicks : state.gridTicks) : 1);
        if (probeSpacing == spacing)
            first = probe + 1;
        else
            last = probe;
    }
    return first;
}

double AutomationPage::tickAtContentX(double x) const noexcept
{
    const auto *songTimeline = timeline();
    const double ticksPerBeat =
        songTimeline ? double(std::max(1u, songTimeline->ticksPerBeat)) : 1.0;
    return (x + m_liveState.horizontalScroll) * ticksPerBeat / pxPerBeat();
}

qreal AutomationPage::displayX(double tick, qreal origin, qreal dpr) const noexcept
{
    const auto *songTimeline = timeline();
    const double ticksPerBeat =
        songTimeline ? double(std::max(1u, songTimeline->ticksPerBeat)) : 1.0;
    const qreal x = origin + qreal(tick * pxPerBeat() / ticksPerBeat
                                   - m_liveState.horizontalScroll);
    return std::round(x * dpr) / dpr;
}

double AutomationPage::pxPerBeat() const noexcept
{
    return std::max(1.0, m_liveState.timeZoom > 1.0 ? m_liveState.timeZoom
                                                    : layout::editorGeometry().editorDefaultPixelsPerBeat);
}

void AutomationPage::requestHorizontalScroll(double value) const
{
    m_owner.setEditorHorizontalScroll(value);
}

void AutomationPage::requestTimeZoom(double value) const
{
    m_owner.setEditorTimeZoom(value);
}

void AutomationPage::setFollowScrollPaused(bool paused) const
{
    m_owner.setFollowScrollPaused(paused);
}

void AutomationPage::publishViewState()
{
    m_owner.setEditorViewState(m_viewState);
}

void AutomationPage::rebuildModel()
{
    m_rowsTrack = selectedTrack();
    if (m_area)
        m_area->rebuildRows();
}

void AutomationPage::addEmptyLane(int track, uint8_t controller)
{
    const EditorAutomationRowId row{EditorAutomationRowKind::ControlChange, uint8_t(track), controller};
    if (m_viewState.emptyLanes.insert(row).second) {
        m_viewState.unhideLane(row);
        publishViewState();
        m_area->rebuildRows();
    }
}

void AutomationPage::removeEmptyLane(int track, uint8_t controller)
{
    const EditorAutomationRowId row{EditorAutomationRowKind::ControlChange, uint8_t(track), controller};
    if (m_viewState.emptyLanes.erase(row) != 0) {
        publishViewState();
        m_area->rebuildRows();
    }
}

void AutomationPage::setLaneRange(const EditorAutomationRowId &row, uint8_t range)
{
    m_viewState.laneRanges[row] = range;
    publishViewState();
    m_area->invalidateContent();
}

void AutomationPage::publishTimeSelection(
    uint64_t startTick, uint64_t endTick,
    const std::vector<std::pair<int, uint8_t>> &lanes) const
{
    SongView::TimeSelection selection;
    selection.startTick = startTick;
    selection.endTick = endTick;
    selection.scope = SongView::TimeSelection::Lanes;
    selection.lanes = lanes;
    m_owner.setTimeSelection(selection);
}

EditorPageVoiceContext AutomationPage::voiceContext(uint64_t tick) const
{
    return m_owner.voiceContext(tick);
}

void AutomationPage::showTimeSelectionMenu(
    const EditorPageTimeSelectionMenuRequest &request) const
{
    m_owner.showEditorTimeSelectionMenu(request);
}

bool AutomationPage::pickVoice(const QString &title, int initialVoice, int *outVoice) const
{
    return m_owner.pickVoice(title, initialVoice, outVoice);
}

void AutomationPage::requestRefresh() const
{
    m_owner.refreshEditorPages();
}

void AutomationPage::announce(const QString &message) const
{
    m_owner.announce(message);
}

bool AutomationPage::paintGrid(QPainter &painter, const QRect &bounds, qreal origin) const
{
    return m_owner.paintGrid(painter, bounds, origin);
}
