#include "ui/editordrawer/drawerchrome.h"

#include <QCursor>
#include <QImage>
#include <QMetaObject>
#include <QQuickImageProvider>
#include <QStringView>

#include <algorithm>
#include <cmath>
#include <utility>

#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/layout.h"
#include "ui/songview.h"

namespace {

std::optional<EditorDrawerPage> resizePage(DrawerChromeTarget target) noexcept
{
    switch (target) {
    case DrawerChromeTarget::VoiceChangesHandle:
        return EditorDrawerPage::VoiceChanges;
    case DrawerChromeTarget::VelocityHandle:
        return EditorDrawerPage::Velocity;
    case DrawerChromeTarget::AutomationHandle:
        return EditorDrawerPage::Automations;
    case DrawerChromeTarget::Bar:
    case DrawerChromeTarget::Detent:
        return std::nullopt;
    }
    return std::nullopt;
}

bool handleVisible(const DrawerChromeSnapshot &snapshot, DrawerChromeTarget target) noexcept
{
    switch (target) {
    case DrawerChromeTarget::VoiceChangesHandle:
        return snapshot.voiceChangesHandleVisible;
    case DrawerChromeTarget::VelocityHandle:
        return snapshot.velocityHandleVisible;
    case DrawerChromeTarget::AutomationHandle:
        return snapshot.automationHandleVisible;
    case DrawerChromeTarget::Bar:
    case DrawerChromeTarget::Detent:
        return false;
    }
    return false;
}

const QRectF &toggleRect(const DrawerChromeSnapshot &snapshot, EditorDrawerPage page) noexcept
{
    switch (page) {
    case EditorDrawerPage::VoiceChanges:
        return snapshot.voiceChangesToggleRect;
    case EditorDrawerPage::Velocity:
        return snapshot.velocityToggleRect;
    case EditorDrawerPage::Automations:
        return snapshot.automationToggleRect;
    }
    Q_UNREACHABLE();
}

std::optional<EditorDrawerPage> toggleAt(const DrawerChromeSnapshot &snapshot,
                                         QPointF songViewPosition) noexcept
{
    for (const EditorDrawerPage page :
         {EditorDrawerPage::VoiceChanges, EditorDrawerPage::Automations,
          EditorDrawerPage::Velocity}) {
        if (toggleRect(snapshot, page).contains(songViewPosition))
            return page;
    }
    return std::nullopt;
}

} // namespace

class DrawerChromeIconProvider final : public QQuickImageProvider
{
  public:
    DrawerChromeIconProvider() : QQuickImageProvider(QQuickImageProvider::Image) {}

    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override
    {
        const qsizetype slash = id.indexOf(QLatin1Char('/'));
        const QStringView imageId = QStringView{id}.left(slash < 0 ? id.size() : slash);
        const QImage *image = nullptr;
        if (imageId == u"velocity")
            image = &m_velocity;
        else if (imageId == u"velocityOn")
            image = &m_velocityOn;
        else if (imageId == u"automation")
            image = &m_automation;
        else if (imageId == u"automationOn")
            image = &m_automationOn;
        else if (imageId == u"voiceChanges")
            image = &m_voiceChanges;
        else if (imageId == u"voiceChangesOn")
            image = &m_voiceChangesOn;
        else if (imageId == u"detent")
            image = &m_detent;

        if (!image)
            return {};
        if (size)
            *size = image->size();
        if (!requestedSize.isEmpty())
            return image->scaled(requestedSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        return *image;
    }

    void setIcons(QImage velocity, QImage velocityOn, QImage automation, QImage automationOn,
                  QImage voiceChanges, QImage voiceChangesOn, QImage detent)
    {
        m_velocity = std::move(velocity);
        m_velocityOn = std::move(velocityOn);
        m_automation = std::move(automation);
        m_automationOn = std::move(automationOn);
        m_voiceChanges = std::move(voiceChanges);
        m_voiceChangesOn = std::move(voiceChangesOn);
        m_detent = std::move(detent);
    }

  private:
    QImage m_velocity;
    QImage m_velocityOn;
    QImage m_automation;
    QImage m_automationOn;
    QImage m_voiceChanges;
    QImage m_voiceChangesOn;
    QImage m_detent;
};

DrawerChromeInteraction::DrawerChromeInteraction(DrawerChrome &chrome, DrawerChromeTarget target)
    : m_chrome(chrome)
    , m_target(target)
{}

void DrawerChromeInteraction::attachInputHost(songview::TimelineInputHost &host)
{
    Q_ASSERT(!m_host);
    m_host = &host;
}

void DrawerChromeInteraction::detachInputHost(songview::TimelineInputHost &host)
{
    if (&host == m_host)
        m_host = nullptr;
}

bool DrawerChromeInteraction::pointerPress(const songview::TimelinePointerInput &input)
{
    return m_chrome.handlePress(m_target, input);
}

bool DrawerChromeInteraction::pointerMove(const songview::TimelinePointerInput &input)
{
    return m_chrome.handleMove(m_target, input);
}

bool DrawerChromeInteraction::pointerRelease(const songview::TimelinePointerInput &input)
{
    return m_chrome.handleRelease(m_target, input);
}

void DrawerChromeInteraction::pointerLeave()
{
    m_chrome.handleLeave(m_target);
}

void DrawerChromeInteraction::inputCancelled(songview::TimelineInputCancelReason reason)
{
    m_chrome.handleCancelled(m_target, reason);
}

void DrawerChromeInteraction::hostAppearanceChanged() {}

DrawerChrome::DrawerChrome(AutomationPage &page, EditorDrawer *parent)
    : QObject(parent)
    , m_page(page)
    , m_drawer(*parent)
    , m_interactions{DrawerChromeInteraction(*this, DrawerChromeTarget::VoiceChangesHandle),
                     DrawerChromeInteraction(*this, DrawerChromeTarget::VelocityHandle),
                     DrawerChromeInteraction(*this, DrawerChromeTarget::AutomationHandle),
                     DrawerChromeInteraction(*this, DrawerChromeTarget::Bar),
                     DrawerChromeInteraction(*this, DrawerChromeTarget::Detent)}
    , m_icons(new DrawerChromeIconProvider)
{
    connect(&m_page, &AutomationPage::scrollStateChanged, this, &DrawerChrome::scrollChanged);
}

DrawerChromeInteraction &DrawerChrome::interaction(DrawerChromeTarget target) noexcept
{
    return m_interactions[static_cast<std::size_t>(target)];
}

void DrawerChrome::setSnapshot(const DrawerChromeSnapshot &snapshot)
{
    m_snapshot = snapshot;
    emit chromeChanged();
}

QQuickImageProvider *DrawerChrome::releaseIconProvider()
{
    if (m_iconProviderReleased)
        return nullptr;
    m_iconProviderReleased = true;
    return m_icons;
}

void DrawerChrome::cancelInteraction()
{
    songview::TimelineInputHost *resizeHost = nullptr;
    if (m_resizeTarget)
        resizeHost = interaction(*m_resizeTarget).m_host;
    songview::TimelineInputHost *barHost =
        m_pressedToggle ? interaction(DrawerChromeTarget::Bar).m_host : nullptr;
    songview::TimelineInputHost *detentHost =
        m_pressedDetent ? interaction(DrawerChromeTarget::Detent).m_host : nullptr;

    m_resizeTarget.reset();
    m_resizeStartGlobalY = 0.0;
    m_resizeStartBodyHeight = 0;
    m_resizeOriginalBodyHeight.reset();
    m_pressedToggle.reset();
    m_pressedDetent = false;
    const bool hadHoveredHandle = m_hoveredHandle.has_value();
    m_hoveredHandle.reset();

    for (auto &interaction : m_interactions) {
        if (interaction.m_host)
            interaction.m_host->clearCursor();
    }
    if (resizeHost)
        resizeHost->releasePointerGrab();
    if (barHost && barHost != resizeHost)
        barHost->releasePointerGrab();
    if (detentHost && detentHost != resizeHost && detentHost != barHost)
        detentHost->releasePointerGrab();
    if (hadHoveredHandle) {
        QMetaObject::invokeMethod(this, [this] { emit chromeChanged(); }, Qt::QueuedConnection);
    }
}

void DrawerChrome::setAutomationScrollY(int value)
{
    m_page.setVerticalScroll(value);
}

void DrawerChrome::scrollAutomationByWheel(int pixelDeltaY, int angleDeltaY, bool inverted)
{
    m_page.scrollVertically(songview::TimelineWheelInput{
        .position = {},
        .globalPosition = {},
        .pixelDelta = QPoint(0, pixelDeltaY),
        .angleDelta = QPoint(0, angleDeltaY),
        .modifiers = Qt::NoModifier,
        .phase = Qt::NoScrollPhase,
        .inverted = inverted,
    });
}

void DrawerChrome::pageAutomationToward(int localY)
{
    const int viewportHeight = automationViewportHeight();
    if (viewportHeight <= 0)
        return;

    const int maximumScrollY = automationMaximumScrollY();
    const int contentHeight = std::max(automationContentHeight(), viewportHeight);
    const int thumbHeight =
        std::max(scrollbarMinimumThumbHeight(),
                 static_cast<int>(std::lround(static_cast<qreal>(viewportHeight) / contentHeight *
                                              viewportHeight)));
    const int thumbTravel = std::max(0, viewportHeight - thumbHeight);
    const int thumbY = maximumScrollY == 0
                           ? 0
                           : static_cast<int>(std::lround(static_cast<qreal>(automationScrollY()) /
                                                          maximumScrollY * thumbTravel));
    m_page.setVerticalScroll(m_page.verticalScroll() +
                             (localY < thumbY ? -viewportHeight : viewportHeight));
}

void DrawerChrome::activateToggle(int page)
{
    switch (page) {
    case static_cast<int>(EditorDrawerPage::Automations):
    case static_cast<int>(EditorDrawerPage::Velocity):
    case static_cast<int>(EditorDrawerPage::VoiceChanges):
        m_drawer.activatePage(static_cast<EditorDrawerPage>(page));
        break;
    default:
        break;
    }
}

void DrawerChrome::setDetentChecked(bool checked)
{
    m_drawer.velocityArea()->setUseDetents(checked);
    m_drawer.syncDetentChrome();
}

void DrawerChrome::adjustResizeHandle(int target, int direction)
{
    if (direction == 0 || target < static_cast<int>(DrawerChromeTarget::VoiceChangesHandle) ||
        target > static_cast<int>(DrawerChromeTarget::AutomationHandle) || m_resizeTarget) {
        return;
    }

    const DrawerChromeTarget resizeTarget = static_cast<DrawerChromeTarget>(target);
    const std::optional<EditorDrawerPage> page = resizePage(resizeTarget);
    if (!page || !handleVisible(m_snapshot, resizeTarget))
        return;

    const int current =
        std::max(m_drawer.resizeMinimumBodyHeight(), m_drawer.resizeBodyHeight(*page));
    const int step = layout::space(layout::Space::Two);
    const int requested =
        std::clamp(current + (direction > 0 ? step : -step), m_drawer.resizeMinimumBodyHeight(),
                   m_drawer.maximumResizeBodyHeight(*page));
    if (requested == current)
        return;

    m_drawer.setResizeBodyHeight(*page, requested);
    m_drawer.publishResizeState();
}

int DrawerChrome::scrollbarWidth() const noexcept
{
    return layout::space(layout::Space::Two);
}

int DrawerChrome::scrollbarMinimumThumbHeight() const noexcept
{
    return layout::space(layout::Space::Eight);
}

int DrawerChrome::automationScrollY() const noexcept
{
    return m_page.verticalScroll();
}

int DrawerChrome::automationContentHeight() const noexcept
{
    return m_page.automationContentHeight();
}

int DrawerChrome::automationViewportHeight() const noexcept
{
    return m_page.automationViewportSize().height();
}

int DrawerChrome::automationMaximumScrollY() const noexcept
{
    return std::max(0, automationContentHeight() - automationViewportHeight());
}

int DrawerChrome::hoveredHandle() const noexcept
{
    return m_hoveredHandle ? static_cast<int>(*m_hoveredHandle) : -1;
}

bool DrawerChrome::handlePress(DrawerChromeTarget target,
                               const songview::TimelinePointerInput &input)
{
    if (const std::optional<EditorDrawerPage> page = resizePage(target)) {
        if (input.button != Qt::LeftButton || !handleVisible(m_snapshot, target) || m_resizeTarget)
            return false;
        songview::TimelineInputHost *const host = interaction(target).m_host;
        if (!host)
            return false;

        host->setCursor(Qt::SizeVerCursor);
        m_resizeTarget = target;
        m_resizeStartGlobalY = input.globalPosition.y();
        m_resizeOriginalBodyHeight = m_drawer.resizeStoredBodyHeight(*page);
        m_resizeStartBodyHeight =
            std::max(m_drawer.resizeMinimumBodyHeight(), m_drawer.resizeBodyHeight(*page));
        return true;
    }

    if (target == DrawerChromeTarget::Bar) {
        if (input.button != Qt::LeftButton)
            return false;
        m_pressedToggle.reset();
        const std::optional<EditorDrawerPage> page =
            toggleAt(m_snapshot, m_snapshot.barRect.topLeft() + input.position);
        if (!page)
            return false;
        m_pressedToggle = *page;
        return true;
    }

    Q_ASSERT(target == DrawerChromeTarget::Detent);
    if (input.button != Qt::LeftButton || !m_snapshot.detentVisible || !m_snapshot.detentEnabled)
        return false;
    m_pressedDetent =
        m_snapshot.detentRect.contains(m_snapshot.detentRect.topLeft() + input.position);
    return m_pressedDetent;
}

bool DrawerChrome::handleMove(DrawerChromeTarget target,
                              const songview::TimelinePointerInput &input)
{
    if (const std::optional<EditorDrawerPage> page = resizePage(target)) {
        if (m_resizeTarget == target) {
            const int requested = std::clamp(
                m_resizeStartBodyHeight +
                    static_cast<int>(std::lround(m_resizeStartGlobalY - input.globalPosition.y())),
                m_drawer.resizeMinimumBodyHeight(), m_drawer.maximumResizeBodyHeight(*page));
            const std::optional<int> targetHeight = requested == m_resizeStartBodyHeight
                                                        ? m_resizeOriginalBodyHeight
                                                        : std::optional<int>{requested};
            if (m_drawer.resizeStoredBodyHeight(*page) != targetHeight)
                m_drawer.setResizeBodyHeight(*page, targetHeight);
            return true;
        }
        if (!handleVisible(m_snapshot, target))
            return false;
        if (songview::TimelineInputHost *const host = interaction(target).m_host)
            host->setCursor(Qt::SizeVerCursor);
        if (m_hoveredHandle == target)
            return true;
        m_hoveredHandle = target;
        emit chromeChanged();
        return true;
    }

    if (target == DrawerChromeTarget::Bar)
        return m_pressedToggle.has_value();
    Q_ASSERT(target == DrawerChromeTarget::Detent);
    return m_pressedDetent;
}

bool DrawerChrome::handleRelease(DrawerChromeTarget target,
                                 const songview::TimelinePointerInput &input)
{
    if (resizePage(target)) {
        if (input.button != Qt::LeftButton || m_resizeTarget != target)
            return false;

        m_resizeTarget.reset();
        m_resizeStartGlobalY = 0.0;
        m_resizeStartBodyHeight = 0;
        m_resizeOriginalBodyHeight.reset();
        if (songview::TimelineInputHost *const host = interaction(target).m_host)
            host->clearCursor();
        m_drawer.publishResizeState();
        return true;
    }

    if (target == DrawerChromeTarget::Bar) {
        if (input.button != Qt::LeftButton || !m_pressedToggle)
            return false;
        const EditorDrawerPage page = *m_pressedToggle;
        m_pressedToggle.reset();
        if (toggleRect(m_snapshot, page).contains(m_snapshot.barRect.topLeft() + input.position))
            activateToggle(static_cast<int>(page));
        return true;
    }

    Q_ASSERT(target == DrawerChromeTarget::Detent);
    if (input.button != Qt::LeftButton || !m_pressedDetent)
        return false;
    m_pressedDetent = false;
    if (m_snapshot.detentVisible && m_snapshot.detentEnabled &&
        m_snapshot.detentRect.contains(m_snapshot.detentRect.topLeft() + input.position))
        setDetentChecked(!m_snapshot.detentChecked);
    return true;
}

void DrawerChrome::handleLeave(DrawerChromeTarget target)
{
    if (!resizePage(target))
        return;
    if (m_resizeTarget != target) {
        if (songview::TimelineInputHost *const host = interaction(target).m_host)
            host->clearCursor();
    }
    if (m_hoveredHandle != target)
        return;
    m_hoveredHandle.reset();
    emit chromeChanged();
}

void DrawerChrome::handleCancelled(DrawerChromeTarget, songview::TimelineInputCancelReason reason)
{
    switch (reason) {
    case songview::TimelineInputCancelReason::FocusLost:
    case songview::TimelineInputCancelReason::PointerUngrabbed:
    case songview::TimelineInputCancelReason::Hidden:
    case songview::TimelineInputCancelReason::WindowDeactivated:
        cancelInteraction();
        break;
    }
}

void DrawerChrome::setIcons(QImage velocity, QImage velocityOn, QImage automation,
                            QImage automationOn, QImage voiceChanges, QImage voiceChangesOn,
                            QImage detent)
{
    m_icons->setIcons(std::move(velocity), std::move(velocityOn), std::move(automation),
                      std::move(automationOn), std::move(voiceChanges), std::move(voiceChangesOn),
                      std::move(detent));
}
