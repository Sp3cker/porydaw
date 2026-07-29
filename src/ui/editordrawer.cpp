#include "ui/editordrawer.h"
#include "theme/themeruntime.h"

#include <QAction>
#include <QApplication>
#include <QEnterEvent>
#include <QFrame>
#include <QKeySequence>
#include <QMouseEvent>
#include <QPaintEvent>
#include <QPainter>
#include <QResizeEvent>
#include <QScrollArea>
#include <QShortcut>
#include <QShowEvent>
#include <QStackedWidget>
#include <QToolButton>
#include <QVBoxLayout>
#include <algorithm>

namespace {

constexpr int kLaneH = 48;
constexpr int kAddLaneH = 20;
constexpr int kDefaultDrawerHeightDivisor = 5;
constexpr int kAutomationHandleH = 4;

} // namespace

namespace songview {

class EditorDrawer::ResizeHandle final : public QWidget {
public:
  ResizeHandle(EditorDrawer *drawer, QWidget *parent)
      : QWidget(parent), m_drawer(drawer) {
    setCursor(Qt::SplitVCursor);
    setMouseTracking(true);
  }

protected:
  void paintEvent(QPaintEvent *) override {
    QPainter p(this);
    p.fillRect(
        rect(),
        themes::color(m_hovered ? themes::Role::splitter_handle_hover_background
                                : themes::Role::splitter_handle));
  }

  void enterEvent(QEnterEvent *) override {
    m_hovered = true;
    update();
  }

  void leaveEvent(QEvent *) override {
    m_hovered = false;
    update();
  }

  void mousePressEvent(QMouseEvent *event) override {
    if (event->button() != Qt::LeftButton)
      return;
    m_dragging = true;
    m_lastGlobalY = event->globalPosition().y();
    event->accept();
  }

  void mouseMoveEvent(QMouseEvent *event) override {
    if (!m_dragging || !(event->buttons() & Qt::LeftButton))
      return;
    const int globalY = event->globalPosition().y();
    const int delta = globalY - m_lastGlobalY;
    m_lastGlobalY = globalY;
    if (delta != 0 && m_drawer->drawerVisible())
      m_drawer->setDrawerHeight(m_drawer->drawerHeight() - delta);
    event->accept();
  }

  void mouseReleaseEvent(QMouseEvent *event) override {
    if (event->button() == Qt::LeftButton) {
      m_dragging = false;
      event->accept();
    }
  }

private:
  EditorDrawer *m_drawer;
  bool m_hovered = false;
  bool m_dragging = false;
  int m_lastGlobalY = 0;
};

EditorDrawer::EditorDrawer(QWidget *mainContent, QWidget *automationPage,
                           QWidget *velocityPage, QWidget *parent)
    : QWidget(parent) {
  auto *overlayLayout = new QVBoxLayout(this);
  overlayLayout->setContentsMargins(0, 0, 0, 0);
  overlayLayout->setSpacing(0);
  mainContent->setParent(this);
  overlayLayout->addWidget(mainContent);

  m_automationAction = new QAction(tr("Automations"), this);
  m_automationAction->setObjectName(QStringLiteral("automationDrawerAction"));
  m_automationAction->setCheckable(true);
  m_automationAction->setChecked(true);
  m_automationAction->setAutoRepeat(false);
  m_automationAction->setToolTip(tr("Show or hide automation lanes (A)"));
  addAction(m_automationAction);

  m_automationTab = new QToolButton(this);
  m_automationTab->setObjectName(QStringLiteral("automationDrawerTab"));
  m_automationTab->setDefaultAction(m_automationAction);
  m_automationTab->setAutoRaise(false);
  m_automationTab->setFocusPolicy(Qt::NoFocus);
  m_automationTab->setToolButtonStyle(Qt::ToolButtonTextOnly);
  m_automationTab->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Fixed);

  m_velocityAction = new QAction(tr("Velocity"), this);
  m_velocityAction->setObjectName(QStringLiteral("velocityDrawerAction"));
  m_velocityAction->setCheckable(true);
  m_velocityAction->setChecked(false);
  m_velocityAction->setAutoRepeat(false);
  m_velocityAction->setToolTip(tr("Show or hide note velocities (V)"));
  addAction(m_velocityAction);

  m_velocityTab = new QToolButton(this);
  m_velocityTab->setObjectName(QStringLiteral("velocityDrawerTab"));
  m_velocityTab->setDefaultAction(m_velocityAction);
  m_velocityTab->setAutoRaise(false);
  m_velocityTab->setFocusPolicy(Qt::NoFocus);
  m_velocityTab->setToolButtonStyle(Qt::ToolButtonTextOnly);
  m_velocityTab->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Fixed);

  m_drawerStack = new QStackedWidget(this);
  m_drawerStack->setObjectName(QStringLiteral("editorDrawer"));
  m_drawerStack->setMinimumHeight(kLaneH + kAddLaneH);
  m_drawerStack->setFocusPolicy(Qt::NoFocus);

  m_lanesScroll = new QScrollArea(m_drawerStack);
  m_lanesScroll->setFrameShape(QFrame::NoFrame);
  m_lanesScroll->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
  m_lanesScroll->setWidgetResizable(true);
  m_lanesScroll->setFocusPolicy(Qt::NoFocus);
  m_lanesScroll->setWidget(automationPage);
  m_drawerStack->addWidget(m_lanesScroll);
  m_drawerStack->addWidget(velocityPage);

  m_resizeHandle = new ResizeHandle(this, this);
  m_resizeHandle->setObjectName(QStringLiteral("editorDrawerHandle"));

  m_drawerStack->raise();
  m_resizeHandle->raise();
  m_automationTab->raise();
  m_velocityTab->raise();

  m_automationShortcut = new QShortcut(QKeySequence(Qt::Key_A), this);
  m_automationShortcut->setContext(Qt::WindowShortcut);
  connect(m_automationShortcut, &QShortcut::activated, this,
          [this] { toggleDrawerPage(DrawerPage::Automations); });
  m_velocityShortcut = new QShortcut(QKeySequence(Qt::Key_V), this);
  m_velocityShortcut->setContext(Qt::WindowShortcut);
  connect(m_velocityShortcut, &QShortcut::activated, this,
          [this] { toggleDrawerPage(DrawerPage::Velocity); });

  connect(m_automationAction, &QAction::triggered, this,
          [this] { toggleDrawerPage(DrawerPage::Automations); });
  connect(m_velocityAction, &QAction::triggered, this,
          [this] { toggleDrawerPage(DrawerPage::Velocity); });
}

void EditorDrawer::setShortcutsEnabled(bool enabled) {
  m_automationShortcut->setEnabled(enabled);
  m_velocityShortcut->setEnabled(enabled);
}

void EditorDrawer::setDrawerPage(DrawerPage page) {
  if (m_drawerPage == page)
    return;
  m_drawerPage = page;
  m_drawerStack->setCurrentIndex(page == DrawerPage::Velocity ? 1 : 0);
  syncDrawerTabs();
  emit drawerStateChanged();
}

void EditorDrawer::setDrawerVisible(bool visible) {
  if (m_drawerVisible == visible) {
    syncDrawerTabs();
    return;
  }
  const QWidget *focused = QApplication::focusWidget();
  const bool restoreContentFocus =
      !visible && focused &&
      (focused == m_drawerStack || m_drawerStack->isAncestorOf(focused));
  const bool freezeUpdates = updatesEnabled();
  if (freezeUpdates)
    setUpdatesEnabled(false);
  m_drawerVisible = visible;
  m_drawerStack->setVisible(visible);
  syncDrawerTabs();
  layoutEditorDrawer();
  if (freezeUpdates) {
    setUpdatesEnabled(true);
    update();
  }
  emit drawerStateChanged();
  if (restoreContentFocus)
    emit contentFocusRequested();
}

void EditorDrawer::setDrawerHeight(int height) {
  m_drawerHeightInitialized = true;
  if (m_drawerHeight == height)
    return;
  m_drawerHeight = height;
  layoutEditorDrawer();
}

QWidget *EditorDrawer::timelineSurface() const { return m_drawerStack; }

void EditorDrawer::toggleDrawerPage(DrawerPage page) {
  if (drawerVisible() && m_drawerPage == page) {
    setDrawerVisible(false);
  } else {
    setDrawerPage(page);
    setDrawerVisible(true);
  }
  if (page == DrawerPage::Automations) {
    emit announceRequested(drawerVisible() ? tr("Automation lanes shown")
                                           : tr("Automation lanes hidden"));
  } else {
    emit announceRequested(drawerVisible() ? tr("Velocity lane shown")
                                           : tr("Velocity lane hidden"));
  }
}

void EditorDrawer::syncDrawerTabs() {
  m_automationAction->setChecked(m_drawerVisible &&
                                 m_drawerPage == DrawerPage::Automations);
  m_velocityAction->setChecked(m_drawerVisible &&
                               m_drawerPage == DrawerPage::Velocity);
}


void EditorDrawer::showEvent(QShowEvent *event) {
  QWidget::showEvent(event);
  if (m_drawerHeightInitialized)
    return;
  m_drawerHeight = height() / kDefaultDrawerHeightDivisor;
  m_drawerHeightInitialized = true;
  layoutEditorDrawer();
}

void EditorDrawer::layoutEditorDrawer() {
  const int hostW = width();
  const int hostH = height();
  const int tabH = std::max(1, m_automationTab->sizeHint().height());
  if (!m_drawerHeightInitialized)
    m_drawerHeight = hostH / kDefaultDrawerHeightDivisor;
  if (hostW <= 0 || hostH <= 0) {
    m_resizeHandle->hide();
    return;
  }
  const int minDrawerH = std::min(kLaneH + kAddLaneH, hostH);
  const int maxDrawerH = std::max(minDrawerH, hostH - std::min(120, hostH));
  m_drawerHeight = std::clamp(m_drawerHeight, minDrawerH, maxDrawerH);
  const int automationTabW = kHeaderW / 2;
  const int velocityTabW = kHeaderW - automationTabW;
  if (m_drawerVisible) {
    const int drawerTop = hostH - m_drawerHeight;
    m_drawerStack->setGeometry(0, drawerTop, hostW, m_drawerHeight);
    m_resizeHandle->setGeometry(
        kHeaderW, std::max(0, drawerTop - kAutomationHandleH / 2),
        std::max(0, hostW - kHeaderW), kAutomationHandleH);
    m_automationTab->setGeometry(0, std::max(0, drawerTop - tabH),
                                 automationTabW, tabH);
    m_velocityTab->setGeometry(automationTabW, std::max(0, drawerTop - tabH),
                               velocityTabW, tabH);
    m_resizeHandle->show();
    m_drawerStack->raise();
    m_resizeHandle->raise();
  } else {
    m_resizeHandle->hide();
    m_automationTab->setGeometry(0, std::max(0, hostH - tabH), automationTabW,
                                 tabH);
    m_velocityTab->setGeometry(automationTabW, std::max(0, hostH - tabH),
                               velocityTabW, tabH);
  }
  m_automationTab->raise();
  m_velocityTab->raise();
}

void EditorDrawer::resizeEvent(QResizeEvent *event) {
  QWidget::resizeEvent(event);
  layoutEditorDrawer();
}

} // namespace songview
