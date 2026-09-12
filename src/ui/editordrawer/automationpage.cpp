#include "ui/editordrawer/automationpage.h"

#include <algorithm>
#include <cmath>

#include <QAction>
#include <QCoreApplication>
#include <QEvent>
#include <QKeyEvent>
#include <QQuickItem>
#include <QQuickWindow>
#include <QWindow>

#include "core/songdocument.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinput.h"
namespace {

Qt::KeyboardModifiers shortcutModifiers(Qt::KeyboardModifiers modifiers)
{
    return modifiers &
           (Qt::ControlModifier | Qt::ShiftModifier | Qt::AltModifier | Qt::MetaModifier);
}

bool sameLiveState(const DrawerPageLiveState &a, const DrawerPageLiveState &b)
{
    return a.documentRevision == b.documentRevision && a.timeZoom == b.timeZoom &&
           a.horizontalScroll == b.horizontalScroll && a.editCursorTick == b.editCursorTick &&
           a.trackColor == b.trackColor && a.playback.playheadTick == b.playback.playheadTick &&
           a.playback.playing == b.playback.playing;
}

} // namespace
AutomationPage::Geometry AutomationPage::Geometry::resolve()
{
    return {layout::fontPx(8.0 / 3.0)};
}

QSize AutomationPage::automationViewportSize() const noexcept
{
    return m_viewportSize;
}

void AutomationPage::synchronizeAutomationViewport(QSize viewportSize)
{
    if (m_viewportSize == viewportSize)
        return;
    m_viewportSize = viewportSize;
    m_canvas->viewportResized();
}

AutomationPage::AutomationPage(SongView &owner, QObject *parent)
    : QObject(parent)
    , m_geometry(Geometry::resolve())
    , m_owner(owner)
    , m_grid(owner.grid())
{
    m_canvas = new AutomationCanvas(*this);
    m_pencilModeAction = new QAction(tr("Pencil Mode"), this);
    m_pencilModeAction->setCheckable(true);
    m_pencilModeAction->setShortcutContext(Qt::WindowShortcut);
    keymap::Registry::instance().attach(QStringLiteral("automation.pencil_mode"),
                                        m_pencilModeAction);
    connect(m_pencilModeAction, &QAction::toggled, m_canvas, &AutomationCanvas::setPencilMode);
    qApp->installEventFilter(this);
}

AutomationPage::~AutomationPage()
{
    qApp->removeEventFilter(this);
}

bool AutomationPage::eventFilter(QObject *watched, QEvent *event)
{
    const QEvent::Type type = event->type();
    if (type == QEvent::WindowDeactivate && belongsToPageWindow(watched)) {
        // Synthetic and native deactivation both terminate a pending draft.
        // Do not request focus here: the foreground window now owns it.
        if (m_canvas && m_canvas->valuePromptVisible())
            m_canvas->cancelInteraction();
        return QObject::eventFilter(watched, event);
    }
    if (type != QEvent::ShortcutOverride && type != QEvent::KeyPress)
        return QObject::eventFilter(watched, event);
    if (!belongsToPageWindow(watched) ||
        !m_owner.drawerSectionVisible(EditorDrawerPage::Automations) || !m_pencilModeAction ||
        !m_pencilModeAction->isEnabled()) {
        return QObject::eventFilter(watched, event);
    }
    const auto *keyEvent = static_cast<QKeyEvent *>(event);
    if (!matchesPencilShortcut(keyEvent->key(), keyEvent->modifiers()))
        return QObject::eventFilter(watched, event);
    // The inline value prompt owns text input while it is open; the pencil
    // shortcut must stay claimable by its editor and resume after it closes.
    if (m_canvas && m_canvas->valuePromptVisible())
        return QObject::eventFilter(watched, event);
    // Any input-method surface in the Quick scene (the value prompt's editor,
    // a rename field, future text items) owns its keys; identify it through
    // the injected input window so the bare-letter shortcut never steals from
    // an editing item.
    const auto *quickWindow = qobject_cast<const QQuickWindow *>(m_inputWindow.data());
    if (quickWindow) {
        const QQuickItem *quickFocus = quickWindow->activeFocusItem();
        if (quickFocus && quickFocus->flags().testFlag(QQuickItem::ItemAcceptsInputMethod))
            return QObject::eventFilter(watched, event);
    }
    if (type == QEvent::ShortcutOverride) {
        event->accept();
        return true;
    }
    if (keyEvent->isAutoRepeat())
        return true;
    m_pencilModeAction->trigger();
    return true;
}

bool AutomationPage::matchesPencilShortcut(int key, Qt::KeyboardModifiers modifiers) const noexcept
{
    const QKeySequence shortcut = m_pencilModeAction->shortcut();
    if (shortcut.count() != 1)
        return false;
    const QKeyCombination combination = shortcut[0];
    const int shortcutKey = int(combination.key());
    return shortcutKey != 0 && shortcutKey != Qt::Key_unknown &&
           !keymap::Registry::isModifierKey(shortcutKey) && key == shortcutKey &&
           shortcutModifiers(modifiers) == shortcutModifiers(combination.keyboardModifiers());
}

bool AutomationPage::belongsToPageWindow(const QObject *target) const noexcept
{
    if (!m_inputWindow)
        return false;
    for (const auto *window = qobject_cast<const QWindow *>(target); window;
         window = qobject_cast<const QWindow *>(window->parent())) {
        if (window == m_inputWindow)
            return true;
    }
    return false;
}

void AutomationPage::setInputWindow(QWindow *window) noexcept
{
    m_inputWindow = window;
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

uint32_t AutomationPage::usedTrackMask() const noexcept
{
    const MidiTimeline *songTimeline = timeline();
    if (!songTimeline)
        return 0;
    uint32_t mask = 0;
    for (int track = 0; track < 16; ++track)
        if (songTimeline->tracks[track].used)
            mask |= 1u << track;
    return mask;
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

void AutomationPage::refreshLiveState(const DrawerPageLiveState &liveState)
{
    const EditorViewState viewState = m_owner.editorViewState();
    const bool liveChanged = !sameLiveState(m_liveState, liveState);
    const bool viewStateChanged = m_viewState != viewState;
    const bool scrollOnly = !viewStateChanged &&
                            m_liveState.horizontalScroll != liveState.horizontalScroll &&
                            m_liveState.documentRevision == liveState.documentRevision &&
                            m_liveState.timeZoom == liveState.timeZoom &&
                            m_liveState.editCursorTick == liveState.editCursorTick &&
                            m_liveState.trackColor == liveState.trackColor &&
                            m_liveState.playback.playheadTick == liveState.playback.playheadTick &&
                            m_liveState.playback.playing == liveState.playback.playing;
    const bool preservePan = m_canvas->isPanning() &&
                             m_liveState.documentRevision == liveState.documentRevision &&
                             !viewStateChanged;
    m_liveState = liveState;
    m_viewState = viewState;
    // The shared camera tail requests moving content and live overlays.
    if (scrollOnly)
        return;
    if (!liveChanged && !viewStateChanged) {
        m_canvas->requestSelectionQuickUpdate();
    } else if (preservePan) {
        m_canvas->requestFullQuickUpdate();
    } else {
        m_canvas->rebuildRows();
    }
}

void AutomationPage::cancelInteraction()
{
    if (m_canvas)
        m_canvas->cancelInteraction();
}

void AutomationPage::documentChanged()
{
    cancelInteraction();
    m_viewState = m_owner.editorViewState();
    rebuildModel();
}

Tick AutomationPage::snapTick(double tick, bool fineMode) const noexcept
{
    return m_grid.snapTick(tick, fineMode);
}
Tick AutomationPage::snapTickDown(double tick, bool fineMode) const noexcept
{
    tick = std::max(0.0, tick);
    if (!fineMode)
        return m_grid.snapTickDown(tick);
    const uint32_t spacing = gridState(Tick(tick), true).snapTicks;
    return Tick(uint64_t(tick / double(spacing)) * spacing);
}

DrawerPageGridState AutomationPage::gridState(Tick tick, bool fineMode) const noexcept
{
    return {m_grid.gridTicksAt(tick), fineMode ? m_grid.fineGridTicks() : m_grid.snapTicksAt(tick)};
}

Tick AutomationPage::nextGridTick(Tick tick, bool fineMode, Tick limit) const noexcept
{
    if (tick >= limit)
        return limit;
    const uint32_t spacing = gridState(tick, fineMode).snapTicks;
    const Tick candidate = spacing >= limit - tick ? limit : tick + spacing;
    if (gridState(candidate, fineMode).snapTicks == spacing)
        return candidate;
    Tick first = tick + 1;
    Tick last = candidate;
    while (first < last) {
        const Tick probe = first + (last - first) / 2;
        const uint32_t probeSpacing = gridState(probe, fineMode).snapTicks;
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
    const qreal x =
        origin + qreal(tick * pxPerBeat() / ticksPerBeat - m_liveState.horizontalScroll);
    return std::round(x * dpr) / dpr;
}

double AutomationPage::pxPerBeat() const noexcept
{
    return std::max(1.0, m_liveState.timeZoom > 1.0 ? m_liveState.timeZoom
                                                    : m_geometry.defaultPixelsPerBeat);
}

void AutomationPage::requestHorizontalScroll(double value) const
{
    m_owner.setEditorHorizontalScroll(value);
}

void AutomationPage::requestTimeZoom(const songview::TimelineWheelInput &input,
                                     qreal anchorContentX) const
{
    m_owner.zoomTimelineAtWheel(input, anchorContentX);
}

void AutomationPage::setFollowScrollPaused(bool paused) const
{
    m_owner.setFollowScrollPaused(paused);
}

void AutomationPage::publishViewState()
{
    const EditorViewState canonical = m_owner.editorViewState();
    m_viewState.velocity = canonical.velocity;
    m_viewState.automation = canonical.automation;
    m_viewState.activePage = canonical.activePage;
    m_owner.setEditorViewState(m_viewState);
}

void AutomationPage::rebuildModel()
{
    if (m_canvas)
        m_canvas->rebuildRows();
}

void AutomationPage::setLaneRange(const EditorAutomationRowId &row, uint8_t range)
{
    m_viewState.laneRanges[row] = range;
    publishViewState();
    m_canvas->requestFullQuickUpdate();
}

void AutomationPage::publishTimeSelection(Tick startTick, Tick endTick,
                                          const std::vector<std::pair<int, uint8_t>> &lanes,
                                          bool tempo) const
{
    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = startTick;
    selection.endTick = endTick;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    selection.lanes = lanes;
    selection.tempo = tempo;
    m_owner.selectionModel().setTimeSelection(selection);
}

DrawerPageVoiceContext AutomationPage::voiceContext(Tick tick) const
{
    return m_owner.voiceContext(tick);
}

void AutomationPage::showTimeSelectionMenu(const DrawerPageTimeSelectionMenuRequest &request) const
{
    m_owner.showDrawerPageTimeSelectionMenu(request);
}

void AutomationPage::requestRefresh() const
{
    m_owner.refreshAllDrawerPages();
}
void AutomationPage::requestQuickUpdate(songview::AutomationRefreshSet dirty) const
{
    m_owner.requestAutomationQuickUpdate(dirty);
}

void AutomationPage::commitEditCursor(Tick tick) const
{
    m_owner.commitEditCursor(tick);
}

void AutomationPage::announce(const QString &message) const
{
    m_owner.announce(message);
}
