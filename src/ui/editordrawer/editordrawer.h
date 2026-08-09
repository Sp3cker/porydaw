#pragma once

#include <QRect>
#include <QWidget>

#include "ui/editorviewstate.h"

class QAction;
class AutomationPage;
class QEvent;
class SongView;
class VelocityArea;
class DrawerSections;

class EditorDrawer final : public QWidget
{
  public:
    EditorDrawer(SongView &owner, QWidget *parent, EditorViewState viewState = {});

    void setHostBounds(const QRect &bounds);
    void useParentBounds();
    void setViewState(const EditorViewState &viewState);
    void cancelVisiblePageInteraction();

    // Focus the active section, or the other visible section when it is collapsed.
    void focusVisiblePage();

    bool hasVisibleSection() const noexcept;
    EditorDrawerPage activePage() const noexcept;
    int sectionHeight(EditorDrawerPage page) const noexcept;
    int minimumSectionHeight() const noexcept;
    int maximumSectionHeight() const noexcept;
    int defaultAutomationHeight() const noexcept;
    int plotOrigin() const noexcept;
    int plotWidth() const noexcept;
    bool pageVisible(EditorDrawerPage page) const noexcept;
    QAction *automationAction() const noexcept { return m_automationAction; }
    QAction *velocityAction() const noexcept { return m_velocityAction; }
    AutomationPage *automationPage() noexcept { return m_automationPage; }
    const AutomationPage *automationPage() const noexcept { return m_automationPage; }
    VelocityArea *velocityArea() noexcept { return m_velocityArea; }
    const VelocityArea *velocityArea() const noexcept { return m_velocityArea; }

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    struct DrawerDiff {
        bool visibilityChanged = false;
        bool activePageChanged = false;
        bool becameFullyHidden = false;
    };

    void activatePage(EditorDrawerPage page);
    void syncViewState(const EditorViewState &viewState);
    EditorViewState drawerViewState() const;
    static DrawerDiff drawerDiff(const EditorViewState &previous,
                                 const EditorViewState &next) noexcept;
    DrawerDiff prepareViewStateTransition(const EditorViewState &previous,
                                          const EditorViewState &next);
    void finishViewStateTransition(const DrawerDiff &diff, bool drawerOwnedFocus);
    void publishViewState(bool geometryAlreadyArranged);
    void arrange();
    void arrangeChildren();
    void cancelPageInteraction(EditorDrawerPage page);
    bool ownsFocus() const;
    QWidget *canvasFor(EditorDrawerPage page) const;
    QRect resolvedHostBounds() const noexcept;

    SongView &m_owner;
    QRect m_hostBounds;
    bool m_usesParentBounds = true;
    bool m_drawerCanvasOwnsFocus = false;
    AutomationPage *m_automationPage = nullptr;
    VelocityArea *m_velocityArea = nullptr;
    DrawerSections *m_sections = nullptr;
    QAction *m_automationAction = nullptr;
    QAction *m_velocityAction = nullptr;
};
