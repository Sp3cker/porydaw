#pragma once

#include <QObject>
#include <QRect>
#include <QSize>

#include <optional>

#include "ui/editordrawer/drawerchrome.h"
#include "ui/editorviewstate.h"

class AutomationPage;
class EditorDrawer;
class SongView;
class VelocityArea;
class VoiceChangeArea;

struct DrawerMetrics {
    int header = 0;
    int handle = 0;
    int minBody = 0;
    int pianoRollReserve = 0;
    int plotOrigin = 0;
};

class DrawerSections final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(DrawerSections)

  public:
    DrawerSections(SongView &owner, QObject *parent, AutomationPage *automation,
                   VelocityArea *velocity, VoiceChangeArea *voiceChanges);

    const DrawerMetrics &metrics() const;
    void updateHostContext(int hostHeight, int defaultAutomationHeight);
    int preferredHeight() const;
    std::optional<int> velocityHeight() const noexcept;
    std::optional<int> automationHeight() const noexcept;
    std::optional<int> voiceChangesHeight() const noexcept;
    bool velocityVisible() const noexcept;
    bool automationVisible() const noexcept;
    bool voiceChangesVisible() const noexcept;
    EditorDrawerPage activePage() const noexcept;
    void applyState(DrawerSectionState velocity, DrawerSectionState automation,
                    DrawerSectionState voiceChanges, EditorDrawerPage activePage);
    void focusActivePage();
    void cancelVisibleInteractions();
    void arrangeLocal(const QSize &overlaySize);
    std::optional<QRect> bodyRect(EditorDrawerPage page) const noexcept;
    const DrawerChromeSnapshot &chromeSnapshot() const noexcept { return m_chromeSnapshot; }

  signals:
    void geometryChanged();
    void statePublished(bool geometryAlreadyArranged);

  private:
    friend class EditorDrawer;

    void ensureChrome() const;
    void syncDetentState();
    int velocityBodyHeight(int hostHeight) const;
    int effectiveAutomationBodyHeight() const;
    int effectiveVoiceChangesBodyHeight() const;
    bool pageVisible(EditorDrawerPage page) const noexcept;
    int pageBodyHeight(EditorDrawerPage page) const;
    std::optional<int> &pageStoredHeight(EditorDrawerPage page) noexcept;
    const std::optional<int> &pageStoredHeight(EditorDrawerPage page) const noexcept;
    int resizeBodyHeight(EditorDrawerPage page) const;
    int maximumResizeBodyHeight(EditorDrawerPage page) const;
    void setResizeBodyHeight(EditorDrawerPage page, std::optional<int> height);
    void publishResizeState();

    SongView &m_owner;
    AutomationPage *m_automation = nullptr;
    VelocityArea *m_velocity = nullptr;
    VoiceChangeArea *m_voiceChanges = nullptr;
    EditorDrawerPage m_activePage = EditorDrawerPage::Automations;
    mutable DrawerMetrics m_chrome;
    mutable bool m_chromeDirty = true;
    int m_lastHostHeight = 0;
    std::optional<int> m_velocityBodyHeight;
    std::optional<int> m_automationBodyHeight;
    std::optional<int> m_voiceChangesBodyHeight;
    std::optional<int> m_preferredAutomationBodyHeight;
    std::optional<QRect> m_automationBodyRect;
    std::optional<QRect> m_velocityBodyRect;
    std::optional<QRect> m_voiceChangesBodyRect;
    DrawerChromeSnapshot m_chromeSnapshot;
    bool m_velocityVisible = true;
    bool m_automationVisible = true;
    bool m_voiceChangesVisible = true;
    bool m_detentEnabled = false;
};
