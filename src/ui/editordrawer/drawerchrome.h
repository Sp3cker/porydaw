#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>

#include <QColor>
#include <QObject>
#include <QRectF>

#include "ui/editorviewstate.h"
#include "ui/songview/quick/timelineinput.h"

class AutomationPage;
class DrawerChrome;
class DrawerChromeIconProvider;
class EditorDrawer;
class QImage;
class QQuickImageProvider;

// The five non-scrollbar controls owned by the drawer's Quick chrome.
enum class DrawerChromeTarget : uint8_t {
    VoiceChangesHandle,
    VelocityHandle,
    AutomationHandle,
    Bar,
    Detent,
};

// One SongView-local chrome arrangement. Empty rectangles represent hidden controls.
struct DrawerChromeSnapshot {
    QRectF voiceChangesHandleRect;
    QRectF velocityHandleRect;
    QRectF automationHandleRect;
    QRectF barRect;
    QRectF voiceChangesToggleRect;
    QRectF automationToggleRect;
    QRectF velocityToggleRect;
    QRectF detentRect;
    QRectF automationScrollbarRect;
    qreal toggleIconInset = 0;
    qreal detentIconInset = 0;
    bool voiceChangesHandleVisible = false;
    bool velocityHandleVisible = false;
    bool automationHandleVisible = false;
    bool detentVisible = false;
    bool detentEnabled = false;
    bool detentChecked = false;
    bool velocityChecked = false;
    bool automationChecked = false;
    bool voiceChangesChecked = false;
    QColor toggleBackground;
    QColor toggleCheckedBackground;
    QColor toggleOutline;
    QColor toggleIconTint;
    QColor toggleCheckedIconTint;
    QColor handleColor;
    QColor handleHoverColor;
    QColor barBackground;
    QColor barOutline;
    QColor scrollbarHandle;
    QColor scrollbarHandleHover;
    QColor detentTint;
    QColor detentCheckedTint;
    QColor detentDisabledTint;
    int barBorderWidth = 0;
    int iconRevision = 0;
};

class DrawerChromeInteraction final : public songview::TimelineBandInteraction
{
  public:
    DrawerChromeInteraction(DrawerChrome &chrome, DrawerChromeTarget target);

    void attachInputHost(songview::TimelineInputHost &host) override;
    void detachInputHost(songview::TimelineInputHost &host) override;
    bool pointerPress(const songview::TimelinePointerInput &input) override;
    bool pointerMove(const songview::TimelinePointerInput &input) override;
    bool pointerRelease(const songview::TimelinePointerInput &input) override;
    void pointerLeave() override;
    void inputCancelled(songview::TimelineInputCancelReason reason) override;
    void hostAppearanceChanged() override;

  private:
    friend class DrawerChrome;

    DrawerChrome &m_chrome;
    const DrawerChromeTarget m_target;
    songview::TimelineInputHost *m_host = nullptr;
};

class DrawerChrome final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(DrawerChrome)

    Q_PROPERTY(QRectF voiceChangesHandleRect READ voiceChangesHandleRect NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QRectF velocityHandleRect READ velocityHandleRect NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QRectF automationHandleRect READ automationHandleRect NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QRectF barRect READ barRect NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QRectF voiceChangesToggleRect READ voiceChangesToggleRect NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QRectF automationToggleRect READ automationToggleRect NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QRectF velocityToggleRect READ velocityToggleRect NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QRectF detentRect READ detentRect NOTIFY chromeChanged FINAL)
    Q_PROPERTY(
        QRectF automationScrollbarRect READ automationScrollbarRect NOTIFY chromeChanged FINAL)
    Q_PROPERTY(
        bool automationScrollbarVisible READ automationScrollbarVisible NOTIFY chromeChanged FINAL)
    Q_PROPERTY(
        bool voiceChangesHandleVisible READ voiceChangesHandleVisible NOTIFY chromeChanged FINAL)
    Q_PROPERTY(bool velocityHandleVisible READ velocityHandleVisible NOTIFY chromeChanged FINAL)
    Q_PROPERTY(bool automationHandleVisible READ automationHandleVisible NOTIFY chromeChanged FINAL)
    Q_PROPERTY(bool detentVisible READ detentVisible NOTIFY chromeChanged FINAL)
    Q_PROPERTY(bool detentEnabled READ detentEnabled NOTIFY chromeChanged FINAL)
    Q_PROPERTY(bool detentChecked READ detentChecked NOTIFY chromeChanged FINAL)
    Q_PROPERTY(bool velocityChecked READ velocityChecked NOTIFY chromeChanged FINAL)
    Q_PROPERTY(bool automationChecked READ automationChecked NOTIFY chromeChanged FINAL)
    Q_PROPERTY(bool voiceChangesChecked READ voiceChangesChecked NOTIFY chromeChanged FINAL)
    Q_PROPERTY(bool barVisible READ barVisible NOTIFY chromeChanged FINAL)
    Q_PROPERTY(
        bool voiceChangesToggleVisible READ voiceChangesToggleVisible NOTIFY chromeChanged FINAL)
    Q_PROPERTY(bool automationToggleVisible READ automationToggleVisible NOTIFY chromeChanged FINAL)
    Q_PROPERTY(bool velocityToggleVisible READ velocityToggleVisible NOTIFY chromeChanged FINAL)
    Q_PROPERTY(int scrollbarWidth READ scrollbarWidth NOTIFY chromeChanged FINAL)
    Q_PROPERTY(
        int scrollbarMinimumThumbHeight READ scrollbarMinimumThumbHeight NOTIFY chromeChanged FINAL)
    Q_PROPERTY(qreal toggleIconInset READ toggleIconInset NOTIFY chromeChanged FINAL)
    Q_PROPERTY(qreal detentIconInset READ detentIconInset NOTIFY chromeChanged FINAL)
    Q_PROPERTY(int barBorderWidth READ barBorderWidth NOTIFY chromeChanged FINAL)
    Q_PROPERTY(int iconRevision READ iconRevision NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QColor toggleBackground READ toggleBackground NOTIFY chromeChanged FINAL)
    Q_PROPERTY(
        QColor toggleCheckedBackground READ toggleCheckedBackground NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QColor toggleOutline READ toggleOutline NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QColor handleColor READ handleColor NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QColor handleHoverColor READ handleHoverColor NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QColor barBackground READ barBackground NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QColor barOutline READ barOutline NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QColor scrollbarHandle READ scrollbarHandle NOTIFY chromeChanged FINAL)
    Q_PROPERTY(QColor scrollbarHandleHover READ scrollbarHandleHover NOTIFY chromeChanged FINAL)
    Q_PROPERTY(int automationScrollY READ automationScrollY NOTIFY scrollChanged FINAL)
    Q_PROPERTY(int automationContentHeight READ automationContentHeight NOTIFY scrollChanged FINAL)
    Q_PROPERTY(
        int automationViewportHeight READ automationViewportHeight NOTIFY scrollChanged FINAL)
    Q_PROPERTY(
        int automationMaximumScrollY READ automationMaximumScrollY NOTIFY scrollChanged FINAL)
    Q_PROPERTY(int hoveredHandle READ hoveredHandle NOTIFY chromeChanged FINAL)

  public:
    DrawerChrome(AutomationPage &page, EditorDrawer *parent);

    DrawerChromeInteraction &interaction(DrawerChromeTarget target) noexcept;
    void setSnapshot(const DrawerChromeSnapshot &snapshot);
    QQuickImageProvider *releaseIconProvider();
    void cancelInteraction();

    Q_INVOKABLE void setAutomationScrollY(int value);
    Q_INVOKABLE void scrollAutomationByWheel(int pixelDeltaY, int angleDeltaY, bool inverted);
    Q_INVOKABLE void pageAutomationToward(int localY);
    Q_INVOKABLE void activateToggle(int page);
    Q_INVOKABLE void setDetentChecked(bool checked);
    Q_INVOKABLE void adjustResizeHandle(int target, int direction);

    QRectF voiceChangesHandleRect() const noexcept { return m_snapshot.voiceChangesHandleRect; }
    QRectF velocityHandleRect() const noexcept { return m_snapshot.velocityHandleRect; }
    QRectF automationHandleRect() const noexcept { return m_snapshot.automationHandleRect; }
    QRectF barRect() const noexcept { return m_snapshot.barRect; }
    QRectF voiceChangesToggleRect() const noexcept { return m_snapshot.voiceChangesToggleRect; }
    QRectF automationToggleRect() const noexcept { return m_snapshot.automationToggleRect; }
    QRectF velocityToggleRect() const noexcept { return m_snapshot.velocityToggleRect; }
    QRectF detentRect() const noexcept { return m_snapshot.detentRect; }
    QRectF automationScrollbarRect() const noexcept { return m_snapshot.automationScrollbarRect; }
    bool barVisible() const noexcept { return !m_snapshot.barRect.isEmpty(); }
    bool voiceChangesToggleVisible() const noexcept
    {
        return barVisible() && !m_snapshot.voiceChangesToggleRect.isEmpty();
    }
    bool automationToggleVisible() const noexcept
    {
        return barVisible() && !m_snapshot.automationToggleRect.isEmpty();
    }
    bool velocityToggleVisible() const noexcept
    {
        return barVisible() && !m_snapshot.velocityToggleRect.isEmpty();
    }
    bool automationScrollbarVisible() const noexcept
    {
        return m_snapshot.automationHandleVisible && !m_snapshot.automationScrollbarRect.isEmpty();
    }
    bool voiceChangesHandleVisible() const noexcept { return m_snapshot.voiceChangesHandleVisible; }
    bool velocityHandleVisible() const noexcept { return m_snapshot.velocityHandleVisible; }
    bool automationHandleVisible() const noexcept { return m_snapshot.automationHandleVisible; }
    bool detentVisible() const noexcept { return m_snapshot.detentVisible; }
    bool detentEnabled() const noexcept { return m_snapshot.detentEnabled; }
    bool detentChecked() const noexcept { return m_snapshot.detentChecked; }
    bool velocityChecked() const noexcept { return m_snapshot.velocityChecked; }
    bool automationChecked() const noexcept { return m_snapshot.automationChecked; }
    bool voiceChangesChecked() const noexcept { return m_snapshot.voiceChangesChecked; }
    int scrollbarWidth() const noexcept;
    int scrollbarMinimumThumbHeight() const noexcept;
    int barBorderWidth() const noexcept { return m_snapshot.barBorderWidth; }
    qreal toggleIconInset() const noexcept { return m_snapshot.toggleIconInset; }
    qreal detentIconInset() const noexcept { return m_snapshot.detentIconInset; }
    int iconRevision() const noexcept { return m_snapshot.iconRevision; }
    QColor toggleBackground() const { return m_snapshot.toggleBackground; }
    QColor toggleCheckedBackground() const { return m_snapshot.toggleCheckedBackground; }
    QColor toggleOutline() const { return m_snapshot.toggleOutline; }
    QColor handleColor() const { return m_snapshot.handleColor; }
    QColor handleHoverColor() const { return m_snapshot.handleHoverColor; }
    QColor barBackground() const { return m_snapshot.barBackground; }
    QColor barOutline() const { return m_snapshot.barOutline; }
    QColor scrollbarHandle() const { return m_snapshot.scrollbarHandle; }
    QColor scrollbarHandleHover() const { return m_snapshot.scrollbarHandleHover; }
    int automationScrollY() const noexcept;
    int automationContentHeight() const noexcept;
    int automationViewportHeight() const noexcept;
    int automationMaximumScrollY() const noexcept;
    int hoveredHandle() const noexcept;

  signals:
    void chromeChanged();
    void scrollChanged();

  private:
    friend class DrawerChromeInteraction;
    friend class EditorDrawer;

    bool handlePress(DrawerChromeTarget target, const songview::TimelinePointerInput &input);
    bool handleMove(DrawerChromeTarget target, const songview::TimelinePointerInput &input);
    bool handleRelease(DrawerChromeTarget target, const songview::TimelinePointerInput &input);
    void handleLeave(DrawerChromeTarget target);
    void handleCancelled(DrawerChromeTarget target, songview::TimelineInputCancelReason reason);
    void setIcons(QImage velocity, QImage velocityOn, QImage automation, QImage automationOn,
                  QImage voiceChanges, QImage voiceChangesOn, QImage detent);

    AutomationPage &m_page;
    EditorDrawer &m_drawer;
    DrawerChromeSnapshot m_snapshot;
    std::array<DrawerChromeInteraction, 5> m_interactions;
    std::optional<DrawerChromeTarget> m_resizeTarget;
    qreal m_resizeStartGlobalY = 0.0;
    int m_resizeStartBodyHeight = 0;
    std::optional<int> m_resizeOriginalBodyHeight;
    std::optional<DrawerChromeTarget> m_hoveredHandle;
    std::optional<EditorDrawerPage> m_pressedToggle;
    bool m_pressedDetent = false;
    DrawerChromeIconProvider *m_icons = nullptr;
    bool m_iconProviderReleased = false;
};
