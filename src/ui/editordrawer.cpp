#include "ui/editordrawer.h"

#include <QAction>
#include <QApplication>
#include <QEvent>
#include <QMouseEvent>
#include <QPainter>
#include <QPaintEvent>
#include <QStackedWidget>
#include <QTabBar>
#include <QtMath>

#include <algorithm>

#include "ui/automationarea.h"
#include "ui/automationpage.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/theme/themeruntime.h"
#include "ui/velocityarea.h"

class EditorDrawer::ResizeHandle final : public QWidget
{
  public:
    explicit ResizeHandle(EditorDrawer *drawer) : QWidget(drawer), m_drawer(drawer)
    {
        setMouseTracking(true);
        setCursor(Qt::SizeVerCursor);
    }

  protected:
    void enterEvent(QEnterEvent *event) override
    {
        QWidget::enterEvent(event);
        m_hovered = true;
        update();
    }

    void leaveEvent(QEvent *event) override
    {
        QWidget::leaveEvent(event);
        m_hovered = false;
        update();
    }

    void mousePressEvent(QMouseEvent *event) override
    {
        if (event->button() != Qt::LeftButton) {
            event->ignore();
            return;
        }
        m_pressed = true;
        grabMouse();
        m_drawer->beginResize(event->globalPosition().y());
        event->accept();
    }

    void mouseMoveEvent(QMouseEvent *event) override
    {
        if (!m_pressed) {
            event->ignore();
            return;
        }
        m_drawer->resizeTo(event->globalPosition().y());
        event->accept();
    }

    void mouseReleaseEvent(QMouseEvent *event) override
    {
        if (!m_pressed || event->button() != Qt::LeftButton) {
            event->ignore();
            return;
        }
        m_pressed = false;
        releaseMouse();
        m_drawer->endResize();
        event->accept();
    }

    bool event(QEvent *event) override
    {
        if (event->type() == QEvent::UngrabMouse && m_pressed) {
            m_pressed = false;
            m_drawer->endResize();
        }
        return QWidget::event(event);
    }

    void paintEvent(QPaintEvent *event) override
    {
        QPainter painter(this);
        painter.fillRect(event->rect(), themes::color(m_hovered
                                                          ? themes::Role::splitter_handle_hover_background
                                                          : themes::Role::splitter_handle));
    }

  private:
    EditorDrawer *m_drawer = nullptr;
    bool m_hovered = false;
    bool m_pressed = false;
};

EditorDrawer::EditorDrawer(SongView &owner, QWidget *parent, EditorViewState viewState)
    : QWidget(parent), m_owner(owner), m_viewState(viewState)
{
    Q_ASSERT(parent);
    setObjectName(QStringLiteral("editorDrawer"));
    setFocusPolicy(Qt::NoFocus);
    parent->installEventFilter(this);

    m_tabBar = new QTabBar(this);
    m_tabBar->setObjectName(QStringLiteral("editorDrawerTabs"));
    m_tabBar->setFocusPolicy(Qt::NoFocus);
    m_tabBar->setExpanding(true);
    m_tabBar->addTab(tr("Automations"));
    m_tabBar->setTabToolTip(0, tr("Show or hide automation lanes (A)"));
    m_tabBar->addTab(tr("Velocity"));
    m_tabBar->setTabToolTip(1, tr("Show or hide note velocities (V)"));
    connect(m_tabBar, &QTabBar::tabBarClicked, this, [this](int index) {
        activatePage(index == 0 ? EditorDrawerPage::Automations : EditorDrawerPage::Velocity);
    });

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

    m_handle = new ResizeHandle(this);
    m_handle->setObjectName(QStringLiteral("editorDrawerResizeHandle"));
    m_stack = new QStackedWidget(this);
    m_stack->setObjectName(QStringLiteral("editorDrawerPages"));
    m_stack->setFocusPolicy(Qt::NoFocus);
    m_automationPage = new AutomationPage(owner, m_stack);
    m_velocityArea = new VelocityArea(owner, m_stack);
    m_stack->addWidget(m_automationPage);
    m_stack->addWidget(m_velocityArea);
    m_automationPage->setFocusPolicy(Qt::NoFocus);
    m_velocityArea->installEventFilter(this);
    if (m_automationPage->area())
        m_automationPage->area()->installEventFilter(this);
    m_lastOpenHeight = m_viewState.drawerHeight;
    updateTabState();
    updateGeometry();
    show();
}

void EditorDrawer::setHostBounds(const QRect &bounds)
{
    m_usesParentBounds = false;
    m_hostBounds = bounds;
    updateGeometry();
}

void EditorDrawer::useParentBounds()
{
    m_usesParentBounds = true;
    updateGeometry();
}

void EditorDrawer::setViewState(const EditorViewState &viewState)
{
    const bool pageChanged = m_viewState.drawerPage != viewState.drawerPage;
    const bool visibleChanged = m_viewState.drawerVisible != viewState.drawerVisible;
    const bool requestMainFocus = m_viewState.drawerVisible && !viewState.drawerVisible
                                  && ownsFocus();
    if (m_viewState.drawerVisible && (pageChanged || !viewState.drawerVisible))
        cancelPageInteraction(m_viewState.drawerPage);
    m_viewState = viewState;
    m_lastOpenHeight = viewState.drawerHeight;
    updateTabState();
    updateGeometry();
    if (m_viewState.drawerVisible && (pageChanged || visibleChanged)) {
        refreshPage(m_viewState.drawerPage);
        requestPageFocus(m_viewState.drawerPage);
    }
    if (requestMainFocus) {
        m_owner.focusContent();
        m_drawerCanvasOwnsFocus = false;
    }
    m_owner.refreshTimelineViews();
    if (m_viewState.drawerVisible)
        refreshPage(m_viewState.drawerPage);
}

void EditorDrawer::setDrawerVisible(bool visible)
{
    if (m_viewState.drawerVisible == visible)
        return;
    const bool requestMainFocus = !visible && ownsFocus();
    if (!visible)
        cancelPageInteraction(m_viewState.drawerPage);
    m_viewState.drawerVisible = visible;
    updateTabState();
    updateGeometry();
    if (visible) {
        refreshPage(m_viewState.drawerPage);
        requestPageFocus(m_viewState.drawerPage);
    } else if (requestMainFocus) {
        m_owner.focusContent();
        m_drawerCanvasOwnsFocus = false;
    }
    publishViewState();
}

void EditorDrawer::setDrawerPage(EditorDrawerPage page)
{
    const bool pageChanged = m_viewState.drawerPage != page;
    const bool wasVisible = m_viewState.drawerVisible;
    if (pageChanged && wasVisible)
        cancelPageInteraction(m_viewState.drawerPage);
    m_viewState.drawerPage = page;
    m_viewState.drawerVisible = true;
    updateTabState();
    updateGeometry();
    if (pageChanged || !wasVisible) {
        refreshPage(page);
        requestPageFocus(page);
        publishViewState();
    }
}

void EditorDrawer::setDrawerHeight(int height)
{
    const int clamped = std::clamp(height, minimumDrawerHeight(), maximumDrawerHeight());
    if (m_lastOpenHeight == clamped && m_viewState.drawerHeight == clamped)
        return;
    m_lastOpenHeight = clamped;
    m_viewState.drawerHeight = clamped;
    updateGeometry();
    publishViewState();
}

void EditorDrawer::cancelVisiblePageInteraction()
{
    if (m_viewState.drawerVisible)
        cancelPageInteraction(m_viewState.drawerPage);
}

int EditorDrawer::drawerHeight() const noexcept
{
    const int requested = m_lastOpenHeight > 0 ? m_lastOpenHeight : defaultDrawerHeight();
    return std::clamp(requested, minimumDrawerHeight(), maximumDrawerHeight());
}

int EditorDrawer::minimumDrawerHeight() const noexcept
{
    const int minimum = layout::editorGeometry().automationRowDefaultHeight + layout::editorGeometry().addAutomationLaneStripHeight;
    return std::min(resolvedHostBounds().height(), minimum);
}

int EditorDrawer::maximumDrawerHeight() const noexcept
{
    const int hostHeight = resolvedHostBounds().height();
    const int reserve = minimumDrawerHeight() + layout::editorGeometry().minimumVisiblePianoRollHeight;
    return hostHeight >= reserve ? hostHeight - layout::editorGeometry().minimumVisiblePianoRollHeight
                                 : hostHeight;
}

int EditorDrawer::defaultDrawerHeight() const noexcept
{
    const int hostHeight = resolvedHostBounds().height();
    return std::clamp(hostHeight / 5, minimumDrawerHeight(), maximumDrawerHeight());
}

int EditorDrawer::plotOrigin() const noexcept
{
    return layout::editorGeometry().plotOrigin;
}

int EditorDrawer::plotWidth() const noexcept
{
    return std::max(layout::space(layout::Space::Zero), resolvedHostBounds().width() - plotOrigin());
}

bool EditorDrawer::eventFilter(QObject *watched, QEvent *event)
{
    if (watched == canvasFor(EditorDrawerPage::Automations)
        || watched == canvasFor(EditorDrawerPage::Velocity)) {
        if (event->type() == QEvent::FocusIn)
            m_drawerCanvasOwnsFocus = true;
        else if (event->type() == QEvent::FocusOut)
            m_drawerCanvasOwnsFocus = false;
    }
    if (watched == parentWidget() && m_usesParentBounds
        && (event->type() == QEvent::Resize || event->type() == QEvent::LayoutRequest)) {
        updateGeometry();
    }
    return QWidget::eventFilter(watched, event);
}

void EditorDrawer::activatePage(EditorDrawerPage page)
{
    if (m_viewState.drawerVisible && m_viewState.drawerPage == page) {
        setDrawerVisible(false);
        m_owner.announce(page == EditorDrawerPage::Automations
                             ? QStringLiteral("Automation lanes hidden")
                             : QStringLiteral("Velocity lane hidden"));
        return;
    }
    setDrawerPage(page);
    m_owner.announce(page == EditorDrawerPage::Automations
                         ? QStringLiteral("Automation lanes shown")
                         : QStringLiteral("Velocity lane shown"));
}

void EditorDrawer::updateGeometry()
{
    const QRect bounds = resolvedHostBounds();
    const int width = std::max(layout::space(layout::Space::Zero), bounds.width());
    const int tabHeight = layout::chromeRowHeight(font(), layout::space(layout::Space::Zero));
    const int handleHeight = m_viewState.drawerVisible ? layout::editorGeometry().editorDrawerResizeHandleHeight
                                                        : layout::space(layout::Space::Zero);
    const int contentHeight = m_viewState.drawerVisible ? drawerHeight()
                                                         : layout::space(layout::Space::Zero);
    const int totalHeight = tabHeight + handleHeight + contentHeight;
    setGeometry(bounds.x(), std::max(bounds.y(), bounds.bottom() - totalHeight + layout::singlePixel()),
                width, totalHeight);

    const int tabWidth = std::min(width, layout::editorGeometry().trackHeaderWidth);
    m_tabBar->setGeometry(layout::space(layout::Space::Zero), layout::space(layout::Space::Zero),
                          tabWidth, tabHeight);
    m_handle->setGeometry(layout::space(layout::Space::Zero), tabHeight, width, handleHeight);
    m_handle->setVisible(m_viewState.drawerVisible && width > layout::space(layout::Space::Zero));
    m_stack->setCurrentIndex(m_viewState.drawerPage == EditorDrawerPage::Automations ? 0 : 1);
    m_stack->setGeometry(layout::space(layout::Space::Zero), tabHeight + handleHeight, width,
                         contentHeight);
    m_stack->setVisible(m_viewState.drawerVisible && plotWidth() > layout::space(layout::Space::Zero));
}

void EditorDrawer::updateTabState()
{
    m_tabBar->setCurrentIndex(m_viewState.drawerVisible
                                  ? m_viewState.drawerPage == EditorDrawerPage::Automations ? 0 : 1
                                  : -1);
}

void EditorDrawer::publishViewState()
{
    m_owner.setEditorViewState(m_viewState);
    m_owner.refreshTimelineViews();
    if (m_viewState.drawerVisible)
        refreshPage(m_viewState.drawerPage);
}

void EditorDrawer::cancelPageInteraction(EditorDrawerPage page)
{
    cancelResize();
    if (page == EditorDrawerPage::Automations)
        m_automationPage->cancelInteraction();
    else
        m_velocityArea->cancelInteraction();
}

void EditorDrawer::refreshPage(EditorDrawerPage page)
{
    if (page == EditorDrawerPage::Automations)
        m_automationPage->refreshLiveState(m_owner.editorLiveState());
    else
        m_velocityArea->refreshLiveState(m_owner.editorLiveState());
}

void EditorDrawer::requestPageFocus(EditorDrawerPage page)
{
    QWidget *canvas = canvasFor(page);
    if (canvas && canvas->isVisible())
        canvas->setFocus(Qt::OtherFocusReason);
}

bool EditorDrawer::ownsFocus() const
{
    QWidget *focus = QApplication::focusWidget();
    const QWidget *automationCanvas = canvasFor(EditorDrawerPage::Automations);
    const QWidget *velocityCanvas = canvasFor(EditorDrawerPage::Velocity);
    return m_drawerCanvasOwnsFocus
           || (focus && (focus == automationCanvas || focus == velocityCanvas
                         || (automationCanvas && automationCanvas->isAncestorOf(focus))
                         || (velocityCanvas && velocityCanvas->isAncestorOf(focus))));
}

QWidget *EditorDrawer::canvasFor(EditorDrawerPage page) const
{
    return page == EditorDrawerPage::Automations
               ? static_cast<QWidget *>(m_automationPage->area())
               : static_cast<QWidget *>(m_velocityArea);
}
void EditorDrawer::beginResize(qreal globalY)
{
    if (m_resizing)
        return;
    m_resizing = true;
    m_resizeStartGlobalY = globalY;
    m_resizeStartHeight = drawerHeight();
    m_owner.setFollowScrollPaused(true);
}

void EditorDrawer::resizeTo(qreal globalY)
{
    if (m_resizing)
        setDrawerHeight(m_resizeStartHeight - qRound(globalY - m_resizeStartGlobalY));
}

void EditorDrawer::endResize()
{
    if (!m_resizing)
        return;
    m_resizing = false;
    m_owner.setFollowScrollPaused(false);
}

void EditorDrawer::cancelResize()
{
    if (!m_resizing)
        return;
    if (m_handle && m_handle->hasMouseTracking())
        m_handle->releaseMouse();
    endResize();
}

QRect EditorDrawer::resolvedHostBounds() const noexcept
{
    if (m_usesParentBounds && parentWidget())
        return parentWidget()->rect();
    return m_hostBounds;
}
