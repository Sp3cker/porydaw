#include "ui/editordrawer/editordrawer.h"

#include <QAction>
#include <QIcon>
#include <QImage>
#include <QPainter>
#include <QPalette>
#include <QPixmap>
#include <QPointF>
#include <QSize>
#include <QStackedWidget>
#include <QWidget>

#include <algorithm>
#include <optional>

#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/drawersections.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/pianorollquick.h"
#include "ui/theme/themeruntime.h"

namespace {

QImage tintedIcon(const QString &source, const QColor &color)
{
    QPixmap pixmap = QIcon(source).pixmap(QSize(512, 512));
    QPainter painter(&pixmap);
    painter.setCompositionMode(QPainter::CompositionMode_SourceIn);
    painter.fillRect(pixmap.rect(), color);
    painter.end();
    return pixmap.toImage();
}

} // namespace

EditorDrawer::EditorDrawer(SongView &owner, EditorViewState viewState)
    : QObject(&owner)
    , m_owner(owner)
{
    m_automationPage = new AutomationPage(owner, this);
    m_chrome = new DrawerChrome(*m_automationPage, this);
    m_velocityArea = new VelocityArea(owner, this);
    m_voiceChangeArea = new VoiceChangeArea(owner, this);
    m_sections =
        new DrawerSections(owner, this, m_automationPage, m_velocityArea, m_voiceChangeArea);
    connect(m_sections, &DrawerSections::geometryChanged, this, &EditorDrawer::arrange);
    connect(m_sections, &DrawerSections::statePublished, this, &EditorDrawer::publishViewState);

    m_automationAction = new QAction(tr("Automations"), this);
    connect(m_automationAction, &QAction::triggered, this,
            [this] { activatePage(EditorDrawerPage::Automations); });
    m_velocityAction = new QAction(tr("Velocity"), this);
    connect(m_velocityAction, &QAction::triggered, this,
            [this] { activatePage(EditorDrawerPage::Velocity); });
    m_voiceChangesAction = new QAction(tr("Voice Changes"), this);
    connect(m_voiceChangesAction, &QAction::triggered, this,
            [this] { activatePage(EditorDrawerPage::VoiceChanges); });

    syncViewState(viewState);
    refreshAppearance(m_owner.palette());
    arrange();
}

void EditorDrawer::refreshAppearance(const QPalette &palette)
{
    m_chromeSnapshot.toggleBackground = themes::color(themes::Role::combo_background);
    m_chromeSnapshot.toggleCheckedBackground = palette.color(QPalette::Highlight);
    m_chromeSnapshot.toggleOutline = themes::color(themes::Role::combo_outline);
    m_chromeSnapshot.toggleIconTint = palette.color(QPalette::WindowText);
    m_chromeSnapshot.toggleCheckedIconTint = palette.color(QPalette::HighlightedText);
    m_chromeSnapshot.handleColor = palette.color(QPalette::Mid);
    m_chromeSnapshot.handleHoverColor = palette.color(QPalette::Highlight);
    m_chromeSnapshot.barBackground = palette.color(QPalette::Window);
    m_chromeSnapshot.barOutline = palette.color(QPalette::Mid);
    m_chromeSnapshot.scrollbarHandle = themes::color(themes::Role::scrollbar_handle);
    m_chromeSnapshot.scrollbarHandleHover =
        themes::color(themes::Role::scrollbar_handle_hover_background);
    m_chromeSnapshot.detentTint = palette.color(QPalette::WindowText);
    m_chromeSnapshot.detentCheckedTint = palette.color(QPalette::Highlight);
    m_chromeSnapshot.detentDisabledTint = palette.color(QPalette::Disabled, QPalette::WindowText);
    m_chromeSnapshot.barBorderWidth = layout::singlePixel();

    refreshChromeIcons();
    m_chrome->setSnapshot(m_chromeSnapshot);
}

void EditorDrawer::refreshChromeIcons()
{
    const QColor detentColor =
        m_velocityArea->isPsgContext()
            ? (m_velocityArea->useDetents() ? m_chromeSnapshot.detentCheckedTint
                                            : m_chromeSnapshot.detentTint)
            : m_chromeSnapshot.detentDisabledTint;
    m_chrome->setIcons(
        tintedIcon(QStringLiteral(":/icons/velocity.svg"), m_chromeSnapshot.toggleIconTint),
        tintedIcon(QStringLiteral(":/icons/velocity.svg"), m_chromeSnapshot.toggleCheckedIconTint),
        tintedIcon(QStringLiteral(":/icons/automation.svg"), m_chromeSnapshot.toggleIconTint),
        tintedIcon(QStringLiteral(":/icons/automation.svg"),
                   m_chromeSnapshot.toggleCheckedIconTint),
        tintedIcon(QStringLiteral(":/icons/flat-music.svg"), m_chromeSnapshot.toggleIconTint),
        tintedIcon(QStringLiteral(":/icons/flat-music.svg"),
                   m_chromeSnapshot.toggleCheckedIconTint),
        tintedIcon(QStringLiteral(":/icons/velocity_labels.svg"), detentColor));
    ++m_chromeSnapshot.iconRevision;
}

void EditorDrawer::syncDetentChrome()
{
    m_chromeSnapshot.detentChecked = m_chromeSnapshot.detentEnabled && m_velocityArea->useDetents();
    refreshChromeIcons();
    m_chrome->setSnapshot(m_chromeSnapshot);
}

void EditorDrawer::setHostBounds(const QRect &songViewLocalRollPane)
{
    m_usesParentBounds = false;
    m_hostBounds = songViewLocalRollPane;
    arrange();
}

void EditorDrawer::useParentBounds()
{
    m_usesParentBounds = true;
    arrange();
}

int EditorDrawer::overlayHeight() const noexcept
{
    return m_sections->preferredHeight();
}

QRect EditorDrawer::overlayRect() const noexcept
{
    const int height = overlayHeight();
    return QRect(m_hostBounds.x(),
                 std::max(m_hostBounds.y(), m_hostBounds.bottom() - height + layout::singlePixel()),
                 m_hostBounds.width(), height);
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
    if (drawerOwnedFocus && diff.becameFullyHidden)
        m_owner.focusContent();
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
    return QRect(overlayRect().topLeft() + body->topLeft(), body->size());
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
    if (m_usesParentBounds) {
        QWidget *const host = m_owner.m_rollStack->parentWidget();
        Q_ASSERT(host);
        m_hostBounds = QRect(host->mapTo(&m_owner, QPoint()), host->size());
    }

    const QRect bounds = resolvedHostBounds();
    m_sections->updateHostContext(bounds.height(), defaultAutomationHeight());
    m_sections->syncDetentState();
    const bool detentEnabled = m_velocityArea->isPsgContext();
    const bool detentChecked = detentEnabled && m_velocityArea->useDetents();
    if (m_chromeSnapshot.detentEnabled != detentEnabled ||
        m_chromeSnapshot.detentChecked != detentChecked) {
        refreshChromeIcons();
    }

    arrangeChildren();
    if (m_owner.m_editorDrawer == this)
        m_owner.updateScrollbars();
}

void EditorDrawer::arrangeChildren()
{
    const QRect overlay = overlayRect();
    m_sections->arrangeLocal(overlay.size());
    publishChromeSnapshot(m_sections->chromeSnapshot(), overlay.topLeft());

    if (const std::optional<QRect> automationBody = bodyRect(EditorDrawerPage::Automations)) {
        const int scrollbarWidth = layout::space(layout::Space::Two);
        m_automationPage->synchronizeAutomationViewport(QSize(
            std::max(layout::space(layout::Space::Zero), automationBody->width() - scrollbarWidth),
            std::max(layout::space(layout::Space::Zero), automationBody->height())));
    }

    if (m_owner.m_editorDrawer == this)
        m_owner.synchronizeTimelineBandLayout();
}

void EditorDrawer::publishChromeSnapshot(const DrawerChromeSnapshot &localSnapshot,
                                         const QPoint &overlayOrigin)
{
    const QPointF offset(overlayOrigin);
    const auto translate = [&offset](const QRectF &rect) {
        return rect.isNull() ? QRectF{} : rect.translated(offset);
    };

    m_chromeSnapshot.voiceChangesHandleRect = translate(localSnapshot.voiceChangesHandleRect);
    m_chromeSnapshot.velocityHandleRect = translate(localSnapshot.velocityHandleRect);
    m_chromeSnapshot.automationHandleRect = translate(localSnapshot.automationHandleRect);
    m_chromeSnapshot.barRect = translate(localSnapshot.barRect);
    m_chromeSnapshot.voiceChangesToggleRect = translate(localSnapshot.voiceChangesToggleRect);
    m_chromeSnapshot.automationToggleRect = translate(localSnapshot.automationToggleRect);
    m_chromeSnapshot.velocityToggleRect = translate(localSnapshot.velocityToggleRect);
    m_chromeSnapshot.detentRect = translate(localSnapshot.detentRect);
    m_chromeSnapshot.automationScrollbarRect = translate(localSnapshot.automationScrollbarRect);
    m_chromeSnapshot.voiceChangesHandleVisible = localSnapshot.voiceChangesHandleVisible;
    m_chromeSnapshot.velocityHandleVisible = localSnapshot.velocityHandleVisible;
    m_chromeSnapshot.automationHandleVisible = localSnapshot.automationHandleVisible;
    m_chromeSnapshot.detentVisible = localSnapshot.detentVisible;
    m_chromeSnapshot.detentEnabled = localSnapshot.detentEnabled;
    m_chromeSnapshot.detentChecked = localSnapshot.detentChecked;
    m_chromeSnapshot.velocityChecked = localSnapshot.velocityChecked;
    m_chromeSnapshot.automationChecked = localSnapshot.automationChecked;
    m_chromeSnapshot.voiceChangesChecked = localSnapshot.voiceChangesChecked;
    m_chrome->setSnapshot(m_chromeSnapshot);
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
    if (const std::optional<songview::TimelineBand> focused = m_owner.focusedTimelineBand();
        focused && (*focused == songview::TimelineBand::Velocity ||
                    *focused == songview::TimelineBand::VoiceChanges ||
                    *focused == songview::TimelineBand::Automation)) {
        return true;
    }
    return false;
}

QRect EditorDrawer::resolvedHostBounds() const noexcept
{
    return m_hostBounds;
}

int EditorDrawer::resizeMinimumBodyHeight() const
{
    return m_sections->metrics().minBody;
}

int EditorDrawer::resizeBodyHeight(EditorDrawerPage page) const
{
    return m_sections->resizeBodyHeight(page);
}

std::optional<int> EditorDrawer::resizeStoredBodyHeight(EditorDrawerPage page) const
{
    return m_sections->pageStoredHeight(page);
}

int EditorDrawer::maximumResizeBodyHeight(EditorDrawerPage page) const
{
    return m_sections->maximumResizeBodyHeight(page);
}

void EditorDrawer::setResizeBodyHeight(EditorDrawerPage page, std::optional<int> height)
{
    m_sections->setResizeBodyHeight(page, height);
}

void EditorDrawer::publishResizeState()
{
    m_sections->publishResizeState();
}
