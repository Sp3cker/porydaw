#include "ui/editordrawer/automationpage.h"

#include <algorithm>
#include <cmath>

#include <QAction>
#include <QApplication>
#include <QEvent>
#include <QKeyEvent>
#include <QScrollArea>
#include <QScrollBar>
#include <QSignalBlocker>
#include <QStyle>
#include <QVBoxLayout>
#include <QWindow>

#include "core/songdocument.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinput.h"
#include "ui/theme/themeruntime.h"
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
class AutomationPage::ScrollArea final : public QScrollArea
{
  public:
    using QScrollArea::QScrollArea;

    int gutter() const
    {
        const QWidget *scrollViewport = viewport();
        auto left = scrollViewport ? scrollViewport->geometry().left() : 0;
        if (left == 0 && layoutDirection() == Qt::RightToLeft)
            left = style()->pixelMetric(QStyle::PM_ScrollBarExtent, nullptr, verticalScrollBar());
        return left;
    }

    void updateScrollbarGutter(bool) { setViewportMargins(0, 0, 0, 0); }

    void syncBackground()
    {
        const QColor bg = themes::color(themes::Role::song_view_piano_roll_background);
        QPalette pal = palette();
        pal.setColor(QPalette::Window, bg);
        setPalette(pal);
        setAutoFillBackground(false);
        if (QWidget *vp = viewport()) {
            QPalette vpPal = vp->palette();
            vpPal.setColor(QPalette::Window, bg);
            vp->setPalette(vpPal);
            vp->setAutoFillBackground(false);
        }
    }
};

AutomationPage::Geometry AutomationPage::Geometry::resolve()
{
    return {layout::fontPx(4.0), layout::fontPx(5.0 / 3.0), layout::fontPx(8.0 / 3.0)};
}

void AutomationPage::refreshGeometry()
{
    m_geometry = Geometry::resolve();
    if (m_scroll) {
        m_scroll->setMinimumHeight(m_geometry.rowDefaultHeight + m_geometry.addLaneStripHeight);
        m_scroll->updateGeometry();
    }
    updateGeometry();
}

int AutomationPage::scrollGutter() const noexcept
{
    return m_scroll ? m_scroll->gutter() : 0;
}
QWidget *AutomationPage::scrollViewport() const noexcept
{
    return m_scroll ? m_scroll->viewport() : nullptr;
}

QSize AutomationPage::automationViewportSize() const noexcept
{
    const QWidget *const viewport = scrollViewport();
    return viewport ? viewport->size() : QSize{};
}

int AutomationPage::automationContentHeight() const noexcept
{
    return m_automationContentHeight;
}

int AutomationPage::verticalScroll() const noexcept
{
    const QScrollBar *const bar = m_scroll ? m_scroll->verticalScrollBar() : nullptr;
    return bar ? bar->value() : 0;
}

void AutomationPage::synchronizeAutomationViewport()
{
    if (!m_scroll || !m_canvas)
        return;
    QScrollBar *const verticalBar = m_scroll->verticalScrollBar();
    if (!verticalBar)
        return;
    const int viewportHeight = automationViewportSize().height();
    m_automationContentHeight = std::max(viewportHeight, m_canvas->minimumContentHeight());
    {
        const QSignalBlocker blocked(verticalBar);
        verticalBar->setPageStep(viewportHeight);
        verticalBar->setRange(0, std::max(0, m_automationContentHeight - viewportHeight));
    }
    m_canvas->scrollStateChanged();
}

void AutomationPage::setVerticalScroll(int value)
{
    if (m_scroll)
        m_scroll->verticalScrollBar()->setValue(value);
}

bool AutomationPage::scrollVertically(const songview::TimelineWheelInput &input)
{
    if (!m_scroll)
        return false;
    QScrollBar *const verticalBar = m_scroll->verticalScrollBar();
    if (!verticalBar)
        return false;
    const QPoint delta = input.pixelDelta.isNull() ? input.angleDelta : input.pixelDelta;
    if ((!input.angleDelta.isNull() &&
         std::abs(input.angleDelta.x()) > std::abs(input.angleDelta.y())) ||
        std::abs(delta.x()) > std::abs(delta.y()) || delta.y() == 0) {
        return false;
    }
    const int singleStep = std::max(1, verticalBar->singleStep());
    const qreal wheelSteps = input.pixelDelta.isNull() ? qreal(delta.y()) / qreal(120)
                                                       : qreal(delta.y()) / qreal(singleStep);
    const qreal scrollSteps = input.inverted ? wheelSteps : -wheelSteps;
    if (m_verticalWheelRemainder != 0.0 && m_verticalWheelRemainder * scrollSteps < 0.0)
        m_verticalWheelRemainder = 0.0;
    m_verticalWheelRemainder += scrollSteps;
    const int wholeSteps = int(std::trunc(m_verticalWheelRemainder));
    if (wholeSteps == 0)
        return true;
    m_verticalWheelRemainder -= qreal(wholeSteps);
    const int pageStep = std::max(1, verticalBar->pageStep());
    const int scrollDelta = std::clamp(wholeSteps * singleStep, -pageStep, pageStep);
    const int current = verticalBar->value();
    const int requested = current + scrollDelta;
    const int target = std::clamp(requested, verticalBar->minimum(), verticalBar->maximum());
    if (target == current) {
        m_verticalWheelRemainder = 0.0;
        return true;
    }
    setVerticalScroll(target);
    if (target != requested)
        m_verticalWheelRemainder = 0.0;
    return true;
}
int AutomationPage::laneHeightFor(const EditorAutomationRowId &row) const noexcept
{
    const int shared =
        m_viewState.laneHeight > 0 ? m_viewState.laneHeight : m_geometry.rowDefaultHeight;
    const auto it = m_viewState.laneHeights.find(row);
    return it == m_viewState.laneHeights.cend() ? shared : it->second;
}

AutomationPage::AutomationPage(SongView &owner, QWidget *parent)
    : QWidget(parent)
    , m_geometry(Geometry::resolve())
    , m_owner(owner)
{
    auto *box = new QVBoxLayout(this);
    box->setContentsMargins(0, 0, 0, 0);
    box->setSpacing(0);
    m_scroll = new ScrollArea(this);
    m_scroll->setObjectName(QStringLiteral("automationScroll"));
    m_scroll->setStyleSheet(
        QStringLiteral("QScrollArea#automationScroll { background-color: transparent; }"));
    m_scroll->setFrameShape(QFrame::NoFrame);
    m_scroll->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    m_scroll->setVerticalScrollBarPolicy(Qt::ScrollBarAlwaysOn);
    m_scroll->setFocusPolicy(Qt::NoFocus);
    m_scroll->setLayoutDirection(Qt::RightToLeft);
    m_scroll->setMinimumHeight(m_geometry.rowDefaultHeight + m_geometry.addLaneStripHeight);
    m_canvas = new AutomationCanvas(*this);
    connect(m_scroll->verticalScrollBar(), &QScrollBar::valueChanged, m_canvas,
            [this](int) { m_canvas->scrollStateChanged(); });
    m_scroll->updateScrollbarGutter(false);
    m_scroll->viewport()->setStyleSheet(QStringLiteral("background-color: transparent;"));
    m_scroll->syncBackground();
    m_pencilModeAction = new QAction(tr("Pencil Mode"), this);
    m_pencilModeAction->setCheckable(true);
    m_pencilModeAction->setShortcutContext(Qt::WindowShortcut);
    keymap::Registry::instance().attach(QStringLiteral("automation.pencil_mode"),
                                        m_pencilModeAction);
    addAction(m_pencilModeAction);
    connect(m_pencilModeAction, &QAction::toggled, m_canvas, &AutomationCanvas::setPencilMode);
    box->addWidget(m_scroll);
    synchronizeAutomationViewport();
    qApp->installEventFilter(this);
}

AutomationPage::~AutomationPage()
{
    qApp->removeEventFilter(this);
}

bool AutomationPage::event(QEvent *event)
{
    const QEvent::Type type = event->type();
    if (type == QEvent::FontChange) {
        refreshGeometry();
        if (m_scroll)
            m_scroll->syncBackground();
    }
    if (type == QEvent::StyleChange || type == QEvent::ThemeChange ||
        type == QEvent::PaletteChange || type == QEvent::ApplicationPaletteChange) {
        if (m_scroll)
            m_scroll->syncBackground();
    }
    if (type == QEvent::Hide || type == QEvent::WindowDeactivate)
        cancelInteraction();
    return QWidget::event(event);
}

bool AutomationPage::eventFilter(QObject *watched, QEvent *event)
{
    const QEvent::Type type = event->type();
    if (watched == scrollViewport() && type == QEvent::Resize) {
        m_canvas->viewportResized();
        synchronizeAutomationViewport();
    }
    if (type != QEvent::ShortcutOverride && type != QEvent::KeyPress)
        return QWidget::eventFilter(watched, event);
    if (!belongsToPageWindow(watched) || !isVisible() || !m_pencilModeAction ||
        !m_pencilModeAction->isEnabled()) {
        return QWidget::eventFilter(watched, event);
    }
    const auto *keyEvent = static_cast<QKeyEvent *>(event);
    if (!matchesPencilShortcut(keyEvent->key(), keyEvent->modifiers()))
        return QWidget::eventFilter(watched, event);
    const QWidget *focus = QApplication::focusWidget();
    if (focus && focus->testAttribute(Qt::WA_InputMethodEnabled))
        return QWidget::eventFilter(watched, event);
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
    if (const auto *widget = qobject_cast<const QWidget *>(target))
        return widget->window() == window();
    const QWindow *const pageWindow = window()->windowHandle();
    for (const auto *targetWindow = qobject_cast<const QWindow *>(target); targetWindow;
         targetWindow = qobject_cast<const QWindow *>(targetWindow->parent())) {
        if (targetWindow == pageWindow)
            return true;
    }
    return false;
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
    const bool preservePan = m_canvas->isPanning() &&
                             m_liveState.documentRevision == liveState.documentRevision &&
                             !viewStateChanged;
    m_liveState = liveState;
    m_viewState = viewState;
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

uint64_t AutomationPage::snapTick(double tick, bool fineMode) const noexcept
{
    return m_owner.snapTick(tick, fineMode);
}
uint64_t AutomationPage::snapTickDown(double tick, bool fineMode) const noexcept
{
    tick = std::max(0.0, tick);
    if (!fineMode)
        return m_owner.snapTickDown(tick);
    const uint64_t spacing = gridState(uint64_t(tick), true).snapTicks;
    return uint64_t(tick / double(spacing)) * spacing;
}

DrawerPageGridState AutomationPage::gridState(uint64_t tick, bool fineMode) const noexcept
{
    return m_owner.gridState(tick, fineMode);
}

uint64_t AutomationPage::nextGridTick(uint64_t tick, bool fineMode, uint64_t limit) const noexcept
{
    if (tick >= limit)
        return limit;
    const uint64_t spacing = gridState(tick, fineMode).snapTicks;
    const uint64_t candidate = spacing >= limit - tick ? limit : tick + spacing;
    if (gridState(candidate, fineMode).snapTicks == spacing)
        return candidate;
    uint64_t first = tick + 1;
    uint64_t last = candidate;
    while (first < last) {
        const uint64_t probe = first + (last - first) / 2;
        const uint64_t probeSpacing = gridState(probe, fineMode).snapTicks;
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

void AutomationPage::addEmptyLane(int track, uint8_t controller)
{
    const EditorAutomationRowId row{EditorAutomationRowKind::ControlChange, uint8_t(track),
                                    controller};
    if (m_viewState.emptyLanes.insert(row).second) {
        m_viewState.unhideLane(row);
        publishViewState();
        m_canvas->rebuildRows();
    }
}

void AutomationPage::removeEmptyLane(int track, uint8_t controller)
{
    const EditorAutomationRowId row{EditorAutomationRowKind::ControlChange, uint8_t(track),
                                    controller};
    if (m_viewState.emptyLanes.erase(row) != 0) {
        publishViewState();
        m_canvas->rebuildRows();
    }
}

void AutomationPage::setLaneRange(const EditorAutomationRowId &row, uint8_t range)
{
    m_viewState.laneRanges[row] = range;
    publishViewState();
    m_canvas->requestFullQuickUpdate();
}

bool AutomationPage::scaleSharedHeight(int wheelSteps, const AutomationGeometry &geometry)
{
    const int shared =
        m_viewState.laneHeight > 0 ? m_viewState.laneHeight : geometry.rowDefaultHeight;
    const int height = std::clamp(shared + wheelSteps * geometry.rowWheelIncrement,
                                  geometry.rowMinimumHeight, geometry.rowMaximumHeight);
    if (height == shared)
        return false;
    const double factor = double(height) / double(shared);
    for (auto &[row, rowHeight] : m_viewState.laneHeights) {
        rowHeight = std::clamp(int(std::lround(rowHeight * factor)), geometry.rowMinimumHeight,
                               geometry.rowMaximumHeight);
    }
    m_viewState.laneHeight = height;
    publishViewState();
    return true;
}

void AutomationPage::publishTimeSelection(uint64_t startTick, uint64_t endTick,
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

DrawerPageVoiceContext AutomationPage::voiceContext(uint64_t tick) const
{
    return m_owner.voiceContext(tick);
}

void AutomationPage::showTimeSelectionMenu(const DrawerPageTimeSelectionMenuRequest &request) const
{
    m_owner.showDrawerPageTimeSelectionMenu(request);
}

bool AutomationPage::pickVoice(const QString &title, int initialVoice, int *outVoice) const
{
    return m_owner.pickVoice(title, initialVoice, outVoice);
}

void AutomationPage::requestRefresh() const
{
    m_owner.refreshAllDrawerPages();
}
void AutomationPage::requestQuickUpdate(songview::AutomationRefreshSet dirty) const
{
    m_owner.requestAutomationQuickUpdate(dirty);
}

void AutomationPage::commitEditCursor(uint64_t tick) const
{
    m_owner.commitEditCursor(tick);
}

void AutomationPage::announce(const QString &message) const
{
    m_owner.announce(message);
}
