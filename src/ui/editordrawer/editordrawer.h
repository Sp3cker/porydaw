#pragma once

#include <QObject>
#include <QPoint>
#include <QRect>

#include <optional>

#include "ui/editordrawer/drawerchrome.h"
#include "ui/editorviewstate.h"

class QAction;
class QPalette;
class AutomationPage;
class SongView;
class VelocityArea;
class VoiceChangeArea;
class DrawerSections;

class EditorDrawer final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(EditorDrawer)

  public:
    EditorDrawer(SongView &owner, EditorViewState viewState = {});

    SongView &owner() noexcept { return m_owner; }
    DrawerChrome &chrome() noexcept { return *m_chrome; }
    const DrawerChrome &chrome() const noexcept { return *m_chrome; }

    void setHostBounds(const QRect &songViewLocalRollPane);
    void useParentBounds();
    void refreshAppearance(const QPalette &palette);
    void arrange();

    int overlayHeight() const noexcept;
    QRect overlayRect() const noexcept;

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
    std::optional<QRect> bodyRect(EditorDrawerPage page) const noexcept;
    bool pageVisible(EditorDrawerPage page) const noexcept;
    QAction *automationAction() const noexcept { return m_automationAction; }
    QAction *velocityAction() const noexcept { return m_velocityAction; }
    QAction *voiceChangesAction() const noexcept { return m_voiceChangesAction; }
    AutomationPage *automationPage() noexcept { return m_automationPage; }
    const AutomationPage *automationPage() const noexcept { return m_automationPage; }
    VelocityArea *velocityArea() noexcept { return m_velocityArea; }
    const VelocityArea *velocityArea() const noexcept { return m_velocityArea; }
    VoiceChangeArea *voiceChangeArea() noexcept { return m_voiceChangeArea; }
    const VoiceChangeArea *voiceChangeArea() const noexcept { return m_voiceChangeArea; }

  private:
    friend class DrawerChrome;

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
    static bool statePageVisible(const EditorViewState &state, EditorDrawerPage page) noexcept;
    DrawerDiff prepareViewStateTransition(const EditorViewState &previous,
                                          const EditorViewState &next);
    void finishViewStateTransition(const DrawerDiff &diff, bool drawerOwnedFocus);
    void publishViewState(bool geometryAlreadyArranged);
    void arrangeChildren();
    void publishChromeSnapshot(const DrawerChromeSnapshot &localSnapshot,
                               const QPoint &overlayOrigin);
    void refreshChromeIcons();
    void syncDetentChrome();
    void cancelPageInteraction(EditorDrawerPage page);
    bool ownsFocus() const;
    QRect resolvedHostBounds() const noexcept;

    int resizeMinimumBodyHeight() const;
    int resizeBodyHeight(EditorDrawerPage page) const;
    std::optional<int> resizeStoredBodyHeight(EditorDrawerPage page) const;
    int maximumResizeBodyHeight(EditorDrawerPage page) const;
    void setResizeBodyHeight(EditorDrawerPage page, std::optional<int> height);
    void publishResizeState();

    SongView &m_owner;
    QRect m_hostBounds;
    bool m_usesParentBounds = true;
    AutomationPage *m_automationPage = nullptr;
    VelocityArea *m_velocityArea = nullptr;
    VoiceChangeArea *m_voiceChangeArea = nullptr;
    DrawerChrome *m_chrome = nullptr;
    DrawerChromeSnapshot m_chromeSnapshot;
    DrawerSections *m_sections = nullptr;
    QAction *m_automationAction = nullptr;
    QAction *m_velocityAction = nullptr;
    QAction *m_voiceChangesAction = nullptr;
};
