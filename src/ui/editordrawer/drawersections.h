#pragma once

#include <QRegion>
#include <QWidget>

#include <optional>

#include "ui/editorviewstate.h"

class AutomationPage;
class QFrame;
class QToolButton;
class VelocityArea;
class VoiceChangeArea;

struct DrawerMetrics {
    int header = 0;
    int handle = 0;
    int minBody = 0;
    int pianoRollReserve = 0;
    int plotOrigin = 0;
};

class DrawerSections final : public QWidget
{
    Q_OBJECT

  public:
    DrawerSections(QWidget *parent, AutomationPage *automation, VelocityArea *velocity,
                   VoiceChangeArea *voiceChanges);

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
    void arrangeLocal();
    QRegion occupiedRegion() const;

  signals:
    void geometryChanged();
    void statePublished(bool geometryAlreadyArranged);

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;
    void changeEvent(QEvent *event) override;

  private:
    void ensureChrome() const;
    void refreshDetentIcon();
    void syncDetentToggle();
    int velocityBodyHeight(int hostHeight) const;
    int effectiveAutomationBodyHeight() const;
    int effectiveVoiceChangesBodyHeight() const;
    QToolButton *pageToggle(EditorDrawerPage page) const noexcept;
    bool pageVisible(EditorDrawerPage page) const noexcept;
    int pageBodyHeight(EditorDrawerPage page) const;
    std::optional<int> &pageStoredHeight(EditorDrawerPage page) noexcept;
    QWidget *pageResizeHandle(EditorDrawerPage page) const noexcept;
    EditorDrawerPage resizePageForHandle(const QWidget *handle) const noexcept;
    void setPageVisible(EditorDrawerPage page, bool visible);

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
    qreal m_resizeStartGlobalY = 0.0;
    int m_resizeStartBodyHeight = 0;
    std::optional<int> m_resizeOriginalBodyHeight;
    QWidget *m_resizeTarget = nullptr;
    QToolButton *m_velocityToggle = nullptr;
    QToolButton *m_automationToggle = nullptr;
    QToolButton *m_voiceChangesToggle = nullptr;
    QToolButton *m_detentToggle = nullptr;
    QFrame *m_automationBar = nullptr;
    QFrame *m_velocityHandle = nullptr;
    QFrame *m_automationHandle = nullptr;
    QFrame *m_voiceChangesHandle = nullptr;
};
