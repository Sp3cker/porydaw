#include "ui/editordrawer/editordrawer.h"

#include <QAction>
#include <QApplication>
#include <QEvent>

#include <algorithm>
#include <optional>

#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/drawersections.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickview.h"
EditorDrawer::EditorDrawer(SongView &owner, QWidget *parent, EditorViewState viewState)
    : QWidget(parent)
    , m_owner(owner)
{
    Q_ASSERT(parent);
    setObjectName(QStringLiteral("editorDrawer"));
    setFocusPolicy(Qt::NoFocus);
    parent->installEventFilter(this);

    m_automationPage = new AutomationPage(owner, this);
    m_velocityArea = new VelocityArea(owner, this);
    m_voiceChangeArea = new VoiceChangeArea(owner, this);
    m_automationPage->setFocusPolicy(Qt::NoFocus);
    m_velocityArea->installEventFilter(this);
    m_voiceChangeArea->installEventFilter(this);
    if (m_automationPage->canvas())
        m_automationPage->canvas()->installEventFilter(this);
    m_sections = new DrawerSections(this, m_automationPage, m_velocityArea, m_voiceChangeArea);
    connect(m_sections, &DrawerSections::geometryChanged, this, &EditorDrawer::arrange);
    connect(m_sections, &DrawerSections::statePublished, this, &EditorDrawer::publishViewState);
    m_automationAction = new QAction(tr("Automations"), this);
    m_automationAction->setObjectName(QStringLiteral("automationDrawerAction"));
    addAction(m_automationAction);
    connect(m_automationAction, &QAction::triggered, this,
            [this] { activatePage(EditorDrawerPage::Automations); });
    m_velocityAction = new QAction(tr("Velocity"), this);
    m_velocityAction->setObjectName(QStringLiteral("velocityDrawerAction"));
    addAction(m_velocityAction);
    connect(m_velocityAction, &QAction::triggered, this,
            [this] { activatePage(EditorDrawerPage::Velocity); });
    m_voiceChangesAction = new QAction(tr("Voice Changes"), this);
    m_voiceChangesAction->setObjectName(QStringLiteral("voiceChangesDrawerAction"));
    addAction(m_voiceChangesAction);
    connect(m_voiceChangesAction, &QAction::triggered, this,
            [this] { activatePage(EditorDrawerPage::VoiceChanges); });
    syncViewState(viewState);

    arrange();
    show();
}

void EditorDrawer::setHostBounds(const QRect &bounds)
{
    m_usesParentBounds = false;
    m_hostBounds = bounds;
    arrange();
}

void EditorDrawer::useParentBounds()
{
    m_usesParentBounds = true;
    arrange();
}

void EditorDrawer::setViewState(const EditorViewState &viewState)
{
    const EditorViewState previous = drawerViewState();
    const bool drawerOwnedFocus = ownsFocus();
    const DrawerDiff diff = prepareViewStateTransition(previous, viewState);
    syncViewState(viewState);
    arrange();
    finishViewStateTransition(diff, drawerOwnedFocus);
}

void EditorDrawer::syncViewState(const EditorViewState &viewState)
{
    m_sections->applyState(viewState.velocity, viewState.automation, viewState.voiceChanges,
                           viewState.activePage);
}

EditorViewState EditorDrawer::drawerViewState() const
{
    EditorViewState state;
    state.velocity = {m_sections->velocityVisible(), m_sections->velocityHeight()};
    state.automation = {m_sections->automationVisible(), m_sections->automationHeight()};
    state.voiceChanges = {m_sections->voiceChangesVisible(), m_sections->voiceChangesHeight()};
    state.activePage = m_sections->activePage();
    return state;
}

EditorDrawer::DrawerDiff EditorDrawer::drawerDiff(const EditorViewState &previous,
                                                  const EditorViewState &next) noexcept
{
    DrawerDiff diff;
    diff.visibilityChanged = previous.velocity.visible != next.velocity.visible ||
                             previous.automation.visible != next.automation.visible ||
                             previous.voiceChanges.visible != next.voiceChanges.visible;
    diff.activePageChanged = previous.activePage != next.activePage;
    diff.becameFullyHidden = (previous.velocity.visible || previous.automation.visible ||
                              previous.voiceChanges.visible) &&
                             !next.velocity.visible && !next.automation.visible &&
                             !next.voiceChanges.visible;
    return diff;
}

bool EditorDrawer::statePageVisible(const EditorViewState &state, EditorDrawerPage page) noexcept
{
    switch (page) {
    case EditorDrawerPage::VoiceChanges:
        return state.voiceChanges.visible;
    case EditorDrawerPage::Velocity:
        return state.velocity.visible;
    case EditorDrawerPage::Automations:
        return state.automation.visible;
    }
    Q_UNREACHABLE();
}

EditorDrawer::DrawerDiff EditorDrawer::prepareViewStateTransition(const EditorViewState &previous,
                                                                  const EditorViewState &next)
{
    const DrawerDiff diff = drawerDiff(previous, next);
    for (const EditorDrawerPage page : {EditorDrawerPage::Automations, EditorDrawerPage::Velocity,
                                        EditorDrawerPage::VoiceChanges}) {
        if (statePageVisible(previous, page) && !statePageVisible(next, page))
            cancelPageInteraction(page);
    }
    if (diff.activePageChanged && statePageVisible(previous, previous.activePage))
        cancelPageInteraction(previous.activePage);
    return diff;
}

void EditorDrawer::finishViewStateTransition(const DrawerDiff &diff, bool drawerOwnedFocus)
{
    if (drawerOwnedFocus && hasVisibleSection() &&
        (diff.visibilityChanged || diff.activePageChanged)) {
        m_sections->focusActivePage();
    }
    if (drawerOwnedFocus && diff.becameFullyHidden) {
        m_owner.focusContent();
        m_drawerCanvasOwnsFocus = false;
    }
}

void EditorDrawer::publishViewState(bool geometryAlreadyArranged)
{
    const EditorViewState next = drawerViewState();
    EditorViewState state = m_owner.editorViewState();
    const bool drawerOwnedFocus = ownsFocus();
    const DrawerDiff diff = prepareViewStateTransition(state, next);
    state.velocity = next.velocity;
    state.automation = next.automation;
    state.voiceChanges = next.voiceChanges;
    state.activePage = next.activePage;
    m_owner.setEditorViewState(state);
    if (!geometryAlreadyArranged)
        arrange();
    finishViewStateTransition(diff, drawerOwnedFocus);
    // Drawer view-state publish can affect any roll domain.
    m_owner.refreshTimelineViews(songview::PianoRollQuickDirty::All);
    m_owner.refreshDrawerPages();
}

void EditorDrawer::cancelVisiblePageInteraction()
{
    m_sections->cancelVisibleInteractions();
}

void EditorDrawer::focusVisiblePage()
{
    m_sections->focusActivePage();
}

bool EditorDrawer::hasVisibleSection() const noexcept
{
    return pageVisible(EditorDrawerPage::Automations) || pageVisible(EditorDrawerPage::Velocity) ||
           pageVisible(EditorDrawerPage::VoiceChanges);
}

EditorDrawerPage EditorDrawer::activePage() const noexcept
{
    return m_sections->activePage();
}

int EditorDrawer::sectionHeight(EditorDrawerPage page) const noexcept
{
    const std::optional<int> height = [this, page] {
        switch (page) {
        case EditorDrawerPage::VoiceChanges:
            return m_sections->voiceChangesHeight();
        case EditorDrawerPage::Velocity:
            return m_sections->velocityHeight();
        case EditorDrawerPage::Automations:
            return m_sections->automationHeight();
        }
        Q_UNREACHABLE();
    }();
    return height.value_or(0);
}

bool EditorDrawer::pageVisible(EditorDrawerPage page) const noexcept
{
    switch (page) {
    case EditorDrawerPage::VoiceChanges:
        return m_sections->voiceChangesVisible();
    case EditorDrawerPage::Velocity:
        return m_sections->velocityVisible();
    case EditorDrawerPage::Automations:
        return m_sections->automationVisible();
    }
    Q_UNREACHABLE();
}

int EditorDrawer::minimumSectionHeight() const noexcept
{
    // DrawerSections owns the font-relative metrics used to clamp this overlay.
    return std::min(resolvedHostBounds().height(), m_sections->metrics().minBody);
}

int EditorDrawer::maximumSectionHeight() const noexcept
{
    const int hostHeight = resolvedHostBounds().height();
    const DrawerMetrics &metrics = m_sections->metrics();
    const int reserve = minimumSectionHeight() + metrics.pianoRollReserve;
    return hostHeight >= reserve ? hostHeight - metrics.pianoRollReserve : hostHeight;
}

int EditorDrawer::defaultAutomationHeight() const noexcept
{
    const int hostHeight = resolvedHostBounds().height();
    return std::clamp(hostHeight / 5, minimumSectionHeight(), maximumSectionHeight());
}

int EditorDrawer::plotOrigin() const noexcept
{
    return m_sections->metrics().plotOrigin;
}

int EditorDrawer::plotWidth() const noexcept
{
    return std::max(layout::space(layout::Space::Zero),
                    resolvedHostBounds().width() - plotOrigin());
}

std::optional<QRect> EditorDrawer::bodyRect(EditorDrawerPage page) const noexcept
{
    const std::optional<QRect> body = m_sections->bodyRect(page);
    if (!body)
        return std::nullopt;
    // Drawer-local bodies publish as SongView-owned canonical layout values.
    return QRect(m_sections->mapTo(&m_owner, body->topLeft()), body->size());
}

bool EditorDrawer::eventFilter(QObject *watched, QEvent *event)
{
    if (watched == canvasFor(EditorDrawerPage::Automations) ||
        watched == canvasFor(EditorDrawerPage::Velocity) ||
        watched == canvasFor(EditorDrawerPage::VoiceChanges)) {
        if (event->type() == QEvent::FocusIn)
            m_drawerCanvasOwnsFocus = true;
        else if (event->type() == QEvent::FocusOut)
            m_drawerCanvasOwnsFocus = false;
    }
    if (watched == parentWidget() && m_usesParentBounds &&
        (event->type() == QEvent::Resize || event->type() == QEvent::LayoutRequest)) {
        arrange();
    }
    return QWidget::eventFilter(watched, event);
}

void EditorDrawer::activatePage(EditorDrawerPage page)
{
    const bool hiding = m_owner.drawerSectionVisible(page);
    m_owner.toggleDrawerSection(page);
    QString announcement;
    switch (page) {
    case EditorDrawerPage::VoiceChanges:
        announcement =
            hiding ? QStringLiteral("Voice changes hidden") : QStringLiteral("Voice changes shown");
        break;
    case EditorDrawerPage::Velocity:
        announcement =
            hiding ? QStringLiteral("Velocity lane hidden") : QStringLiteral("Velocity lane shown");
        break;
    case EditorDrawerPage::Automations:
        announcement = hiding ? QStringLiteral("Automation lanes hidden")
                              : QStringLiteral("Automation lanes shown");
        break;
    }
    m_owner.announce(announcement);
}

void EditorDrawer::arrange()
{
    const QRect bounds = resolvedHostBounds();
    const int width = std::max(layout::space(layout::Space::Zero), bounds.width());
    m_sections->updateHostContext(bounds.height(), defaultAutomationHeight());
    const int totalHeight = m_sections->preferredHeight();
    const QRect drawerBounds(
        bounds.x(), std::max(bounds.y(), bounds.bottom() - totalHeight + layout::singlePixel()),
        width, totalHeight);
    if (geometry() != drawerBounds)
        setGeometry(drawerBounds);
    // EditorDrawer owns the outer geometry epoch; DrawerSections lays out within this rect.
    arrangeChildren();
    if (m_owner.m_editorDrawer == this)
        m_owner.updateScrollbars();
}

void EditorDrawer::arrangeChildren()
{
    if (m_sections->geometry() != rect())
        m_sections->setGeometry(rect());
    m_sections->show();
    m_sections->arrangeLocal();
    const QRegion occupied = m_sections->occupiedRegion();
    if (mask() != occupied)
        setMask(occupied);
    // The canonical band layout must observe settled drawer geometry and
    // masks; synchronize through the SongView friend seam, not a signal.
    if (m_owner.m_editorDrawer == this)
        m_owner.synchronizeTimelineBandLayout();
}

void EditorDrawer::cancelPageInteraction(EditorDrawerPage page)
{
    switch (page) {
    case EditorDrawerPage::VoiceChanges:
        m_voiceChangeArea->cancelInteraction();
        return;
    case EditorDrawerPage::Velocity:
        m_velocityArea->cancelInteraction();
        return;
    case EditorDrawerPage::Automations:
        m_automationPage->cancelInteraction();
        return;
    }
    Q_UNREACHABLE();
}

bool EditorDrawer::ownsFocus() const
{
    QWidget *focus = QApplication::focusWidget();
    if (m_drawerCanvasOwnsFocus || !focus)
        return m_drawerCanvasOwnsFocus;
    for (const EditorDrawerPage page : {EditorDrawerPage::Automations, EditorDrawerPage::Velocity,
                                        EditorDrawerPage::VoiceChanges}) {
        if (const QWidget *canvas = canvasFor(page);
            canvas && (focus == canvas || canvas->isAncestorOf(focus)))
            return true;
    }
    return false;
}

QWidget *EditorDrawer::canvasFor(EditorDrawerPage page) const
{
    switch (page) {
    case EditorDrawerPage::VoiceChanges:
        return m_voiceChangeArea;
    case EditorDrawerPage::Velocity:
        return m_velocityArea;
    case EditorDrawerPage::Automations:
        return m_automationPage->canvas();
    }
    Q_UNREACHABLE();
}

QRect EditorDrawer::resolvedHostBounds() const noexcept
{
    if (m_usesParentBounds && parentWidget())
        return parentWidget()->rect();
    return m_hostBounds;
}
