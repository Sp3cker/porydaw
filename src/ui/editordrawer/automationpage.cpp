#include "ui/editordrawer/automationpage.h"

#include <algorithm>
#include <cmath>

#include <QAction>
#include <QApplication>
#include <QEvent>
#include <QKeyEvent>
#include <QScrollArea>
#include <QScrollBar>
#include <QStyle>
#include <QVBoxLayout>
#include <QWindow>

#include "core/songdocument.h"
#include "ui/editordrawer/automationarea.h"
#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/theme/themeruntime.h"
namespace {

constexpr std::chrono::milliseconds kPencilMomentaryHold{500};

Qt::KeyboardModifiers shortcutModifiers(Qt::KeyboardModifiers modifiers)
{
    return modifiers &
           (Qt::ControlModifier | Qt::ShiftModifier | Qt::AltModifier | Qt::MetaModifier);
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
        setAutoFillBackground(true);
        if (QWidget *vp = viewport()) {
            QPalette vpPal = vp->palette();
            vpPal.setColor(QPalette::Window, bg);
            vp->setPalette(vpPal);
            vp->setAutoFillBackground(true);
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
    m_scroll->setFrameShape(QFrame::NoFrame);
    m_scroll->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    m_scroll->setVerticalScrollBarPolicy(Qt::ScrollBarAlwaysOn);
    m_scroll->setWidgetResizable(true);
    m_scroll->setFocusPolicy(Qt::NoFocus);
    m_scroll->setLayoutDirection(Qt::RightToLeft);
    m_scroll->setMinimumHeight(m_geometry.rowDefaultHeight + m_geometry.addLaneStripHeight);
    m_area = new AutomationArea(this, m_scroll);
    m_area->setLayoutDirection(Qt::LeftToRight);
    m_scroll->setWidget(m_area);
    m_scroll->updateScrollbarGutter(false);
    m_scroll->syncBackground();
    if (m_area)
        m_area->contentGeometryChanged();
    m_pencilModeAction = new QAction(tr("Pencil Mode"), this);
    m_pencilModeAction->setCheckable(true);
    m_pencilModeAction->setShortcutContext(Qt::WindowShortcut);
    keymap::Registry::instance().attach(QStringLiteral("automation.pencil_mode"),
                                        m_pencilModeAction);
    addAction(m_pencilModeAction);
    connect(m_pencilModeAction, &QAction::toggled, m_area, &AutomationArea::setPencilMode);
    box->addWidget(m_scroll);
    qApp->installEventFilter(this);
}

AutomationPage::~AutomationPage() = default;

bool AutomationPage::event(QEvent *event)
{
    if (event->type() == QEvent::FontChange) {
        refreshGeometry();
        if (m_scroll)
            m_scroll->syncBackground();
    }
    if (event->type() == QEvent::StyleChange || event->type() == QEvent::ThemeChange ||
        event->type() == QEvent::PaletteChange ||
        event->type() == QEvent::ApplicationPaletteChange) {
        if (m_scroll)
            m_scroll->syncBackground();
    }
    if (event->type() == QEvent::Hide || event->type() == QEvent::WindowDeactivate) {
        finishPencilShortcut(true);
        cancelInteraction();
    }
    return QWidget::event(event);
}

bool AutomationPage::eventFilter(QObject *watched, QEvent *event)
{
    const QEvent::Type type = event->type();
    if (type != QEvent::ShortcutOverride && type != QEvent::KeyPress && type != QEvent::KeyRelease)
        return QWidget::eventFilter(watched, event);
    const auto *targetWidget = qobject_cast<QWidget *>(watched);
    const auto *targetWindow = qobject_cast<QWindow *>(watched);
    // Native shortcuts reach the top-level QWindow before its focused widget.
    const bool inPageWindow = (targetWidget && targetWidget->window() == window()) ||
                              (targetWindow && targetWindow == window()->windowHandle());
    if (!inPageWindow || !isVisible() || !m_pencilModeAction || !m_pencilModeAction->isEnabled())
        return QWidget::eventFilter(watched, event);

    const auto *keyEvent = static_cast<QKeyEvent *>(event);
    const QWidget *focus = QApplication::focusWidget();
    // Native window events reach this application filter before the focused
    // editor can claim printable keys through ShortcutOverride.
    if (!m_pencilShortcutHeld && focus && focus->testAttribute(Qt::WA_InputMethodEnabled))
        return QWidget::eventFilter(watched, event);
    if (type == QEvent::ShortcutOverride) {
        if (!handlesPencilShortcut(keyEvent))
            return QWidget::eventFilter(watched, event);
        event->accept();
        return true;
    }
    if (type == QEvent::KeyPress) {
        if (m_pencilShortcutHeld && keyEvent->key() == m_pencilShortcutKey)
            return true;
        if (!handlesPencilShortcut(keyEvent))
            return QWidget::eventFilter(watched, event);
        if (keyEvent->isAutoRepeat())
            return true;
        m_pencilShortcutHeld = true;
        m_pencilShortcutKey = keyEvent->key();
        m_pencilShortcutPriorState = m_pencilModeAction->isChecked();
        m_pencilShortcutGestureStarted = false;
        m_pencilShortcutPressedAt = std::chrono::steady_clock::now();
        m_area->setPencilMode(!m_pencilShortcutPriorState);
        return true;
    }

    if (m_pencilShortcutHeld && keyEvent->key() == m_pencilShortcutKey) {
        if (!keyEvent->isAutoRepeat())
            finishPencilShortcut(false);
        return true;
    }
    if (keyEvent->isAutoRepeat() && handlesPencilShortcut(keyEvent))
        return true;
    return QWidget::eventFilter(watched, event);
}

void AutomationPage::automationGestureStarted() noexcept
{
    if (m_pencilShortcutHeld)
        m_pencilShortcutGestureStarted = true;
}

bool AutomationPage::handlesPencilShortcut(const QKeyEvent *event) const noexcept
{
    const QKeySequence shortcut = m_pencilModeAction->shortcut();
    if (shortcut.count() != 1)
        return false;
    const QKeyCombination combination = shortcut[0];
    const int key = int(combination.key());
    return combination.keyboardModifiers() == Qt::NoModifier && key != 0 &&
           key != Qt::Key_unknown && !keymap::Registry::isModifierKey(key) && event->key() == key &&
           shortcutModifiers(event->modifiers()) == Qt::NoModifier;
}

void AutomationPage::finishPencilShortcut(bool forceMomentary)
{
    if (!m_pencilShortcutHeld)
        return;
    const bool momentary =
        forceMomentary || m_pencilShortcutGestureStarted ||
        std::chrono::steady_clock::now() - m_pencilShortcutPressedAt >= kPencilMomentaryHold;
    const bool priorState = m_pencilShortcutPriorState;
    m_pencilShortcutHeld = false;
    m_pencilShortcutKey = 0;
    m_pencilShortcutGestureStarted = false;
    if (momentary)
        m_area->setPencilMode(priorState);
    else
        m_pencilModeAction->setChecked(!priorState);
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
    const bool preservePan = m_area->isPanning() &&
                             m_liveState.documentRevision == liveState.documentRevision &&
                             m_viewState == viewState;
    m_liveState = liveState;
    m_viewState = viewState;
    if (preservePan)
        m_area->invalidateContent();
    else
        m_area->rebuildRows();
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

uint64_t AutomationPage::snapTick(double tick, bool fineMode) const noexcept
{
    return m_owner.snapTick(tick, fineMode);
}
uint64_t AutomationPage::snapTickDown(double tick, bool fineMode) const noexcept
{
    tick = std::max(0.0, tick);
    if (!fineMode)
        return m_owner.snapTickDown(tick);
    const uint64_t spacing = std::max<uint64_t>(1, gridState(uint64_t(tick), true).snapTicks);
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
    const uint64_t spacing = std::max<uint64_t>(1, gridState(tick, fineMode).snapTicks);
    const uint64_t candidate = spacing >= limit - tick ? limit : tick + spacing;
    if (std::max<uint64_t>(1, gridState(candidate, fineMode).snapTicks) == spacing)
        return candidate;
    uint64_t first = tick + 1;
    uint64_t last = candidate;
    while (first < last) {
        const uint64_t probe = first + (last - first) / 2;
        const uint64_t probeSpacing = std::max<uint64_t>(1, gridState(probe, fineMode).snapTicks);
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

void AutomationPage::requestTimeZoom(const QWheelEvent *event, qreal anchorContentX) const
{
    m_owner.zoomTimelineAtWheel(event, anchorContentX);
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
    if (m_area)
        m_area->rebuildRows();
}

void AutomationPage::addEmptyLane(int track, uint8_t controller)
{
    const EditorAutomationRowId row{EditorAutomationRowKind::ControlChange, uint8_t(track),
                                    controller};
    if (m_viewState.emptyLanes.insert(row).second) {
        m_viewState.unhideLane(row);
        publishViewState();
        m_area->rebuildRows();
    }
}

void AutomationPage::removeEmptyLane(int track, uint8_t controller)
{
    const EditorAutomationRowId row{EditorAutomationRowKind::ControlChange, uint8_t(track),
                                    controller};
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

void AutomationPage::commitEditCursor(uint64_t tick) const
{
    m_owner.commitEditCursor(tick);
}

void AutomationPage::announce(const QString &message) const
{
    m_owner.announce(message);
}

bool AutomationPage::paintGrid(QPainter &painter, const QRect &bounds, qreal origin) const
{
    return m_owner.paintGrid(painter, bounds, origin);
}
