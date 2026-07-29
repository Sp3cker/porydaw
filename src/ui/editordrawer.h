#pragma once

#include "songview.h"

#include <QWidget>

class QAction;
class QResizeEvent;
class QScrollArea;
class QShortcut;
class QShowEvent;
class QStackedWidget;
class QString;
class QToolButton;

namespace songview {

class EditorDrawer final : public QWidget {
  Q_OBJECT

public:
  using DrawerPage = SongView::DrawerPage;

  EditorDrawer(QWidget *mainContent, QWidget *automationPage,
               QWidget *velocityPage, QWidget *parent = nullptr);

  void setDrawerPage(DrawerPage page);
  void setDrawerVisible(bool visible);
  void setDrawerHeight(int height);
  void toggleDrawerPage(DrawerPage page);
  void setShortcutsEnabled(bool enabled);

  DrawerPage drawerPage() const { return m_drawerPage; }
  bool drawerVisible() const { return m_drawerVisible; }
  int drawerHeight() const { return m_drawerHeight; }
  QWidget *timelineSurface() const;

signals:
  void drawerStateChanged();
  void announceRequested(const QString &text);
  void contentFocusRequested();

protected:
  void resizeEvent(QResizeEvent *event) override;
  void showEvent(QShowEvent *event) override;

private:
  class ResizeHandle;

  void layoutEditorDrawer();
  void syncDrawerTabs();

  QStackedWidget *m_drawerStack = nullptr;
  QScrollArea *m_lanesScroll = nullptr;
  ResizeHandle *m_resizeHandle = nullptr;
  QAction *m_automationAction = nullptr;
  QToolButton *m_automationTab = nullptr;
  QAction *m_velocityAction = nullptr;
  QToolButton *m_velocityTab = nullptr;
  QShortcut *m_automationShortcut = nullptr;
  QShortcut *m_velocityShortcut = nullptr;
  int m_drawerHeight = 0;
  DrawerPage m_drawerPage = DrawerPage::Automations;
  bool m_drawerVisible = true;
  bool m_drawerHeightInitialized = false;
};

} // namespace songview
