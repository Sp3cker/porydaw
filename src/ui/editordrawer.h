#pragma once

#include <QRect>
#include <QWidget>

#include "ui/editorviewstate.h"

class QAction;
class AutomationPage;
class QEvent;
class QTabBar;
class QStackedWidget;
class SongView;
class VelocityArea;

class EditorDrawer final : public QWidget
{
  public:
    EditorDrawer(SongView &owner, QWidget *parent, EditorViewState viewState = {});

    void setHostBounds(const QRect &bounds);
    void useParentBounds();
    void setViewState(const EditorViewState &viewState);
    void setDrawerVisible(bool visible);
    void setDrawerPage(EditorDrawerPage page);
    void setDrawerHeight(int height);
    void cancelVisiblePageInteraction();

    bool drawerVisible() const noexcept { return m_viewState.drawerVisible; }
    EditorDrawerPage drawerPage() const noexcept { return m_viewState.drawerPage; }
    int drawerHeight() const noexcept;
    int minimumDrawerHeight() const noexcept;
    int maximumDrawerHeight() const noexcept;
    int defaultDrawerHeight() const noexcept;
    int plotOrigin() const noexcept;
    int plotWidth() const noexcept;
    QAction *automationAction() const noexcept { return m_automationAction; }
    QAction *velocityAction() const noexcept { return m_velocityAction; }
    AutomationPage *automationPage() noexcept { return m_automationPage; }
    const AutomationPage *automationPage() const noexcept { return m_automationPage; }
    VelocityArea *velocityArea() noexcept { return m_velocityArea; }
    const VelocityArea *velocityArea() const noexcept { return m_velocityArea; }

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    class ResizeHandle;

    void activatePage(EditorDrawerPage page);
    void updateGeometry();
    void updateTabState();
    void publishViewState();
    void cancelPageInteraction(EditorDrawerPage page);
    void refreshPage(EditorDrawerPage page);
    void requestPageFocus(EditorDrawerPage page);
    bool ownsFocus() const;
    QWidget *canvasFor(EditorDrawerPage page) const;
    void beginResize(qreal globalY);
    void resizeTo(qreal globalY);
    void endResize();
    void cancelResize();
    QRect resolvedHostBounds() const noexcept;

    SongView &m_owner;
    EditorViewState m_viewState;
    QRect m_hostBounds;
    bool m_usesParentBounds = true;
    int m_lastOpenHeight = 0;
    qreal m_resizeStartGlobalY = 0.0;
    int m_resizeStartHeight = 0;
    bool m_resizing = false;
    bool m_drawerCanvasOwnsFocus = false;
    QTabBar *m_tabBar = nullptr;
    ResizeHandle *m_handle = nullptr;
    QStackedWidget *m_stack = nullptr;
    AutomationPage *m_automationPage = nullptr;
    VelocityArea *m_velocityArea = nullptr;
    QAction *m_automationAction = nullptr;
    QAction *m_velocityAction = nullptr;
};
