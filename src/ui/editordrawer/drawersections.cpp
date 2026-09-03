#include "ui/editordrawer/drawersections.h"

#include <algorithm>
#include <optional>
#include <utility>

#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/typography.h"

DrawerSections::DrawerSections(SongView &owner, QObject *parent, AutomationPage *automation,
                               VelocityArea *velocity, VoiceChangeArea *voiceChanges)
    : QObject(parent)
    , m_owner(owner)
    , m_automation(automation)
    , m_velocity(velocity)
    , m_voiceChanges(voiceChanges)
{
    Q_ASSERT(parent);
    m_velocity->setContextChangedCallback([this] {
        syncDetentState();
        emit geometryChanged();
    });
    syncDetentState();
}

void DrawerSections::ensureChrome() const
{
    if (!m_chromeDirty)
        return;

    m_chrome.header =
        layout::chromeRowHeight(*typography::bodyFont(), layout::space(layout::Space::Zero));
    m_chrome.handle = layout::fontPx(1.0 / 3.0);
    m_chrome.minBody = layout::fontPx(17.0 / 5.0);
    m_chrome.pianoRollReserve = layout::fontPx(10.0);
    m_chrome.plotOrigin = layout::fontPx(17.5 + 13.0 / 3.0);
    m_chromeDirty = false;
}

void DrawerSections::syncDetentState()
{
    const bool psg = m_velocity->isPsgContext();
    if (psg && !m_detentEnabled)
        m_velocity->setUseDetents(true);
    m_detentEnabled = psg;
}

int DrawerSections::velocityBodyHeight(int hostHeight) const
{
    return m_velocityBodyHeight.value_or(
        std::clamp(hostHeight / 6, layout::fontPx(8.0), layout::fontPx(12.0)));
}

int DrawerSections::effectiveAutomationBodyHeight() const
{
    return m_automationBodyHeight.value_or(
        m_preferredAutomationBodyHeight.value_or(m_chrome.minBody));
}

int DrawerSections::effectiveVoiceChangesBodyHeight() const
{
    return m_voiceChangesBodyHeight.value_or(m_chrome.minBody);
}

const DrawerMetrics &DrawerSections::metrics() const
{
    ensureChrome();
    return m_chrome;
}

void DrawerSections::updateHostContext(int hostHeight, int defaultAutomationHeight)
{
    ensureChrome();
    m_lastHostHeight = std::max(0, hostHeight);
    m_preferredAutomationBodyHeight = std::max(m_chrome.minBody, defaultAutomationHeight);
}

int DrawerSections::preferredHeight() const
{
    ensureChrome();

    const bool showVelocity = velocityVisible();
    const bool showAutomation = automationVisible();
    const bool showVoiceChanges = voiceChangesVisible();
    const int handles =
        m_chrome.handle * (int(showVelocity) + int(showAutomation) + int(showVoiceChanges));
    const int bodies = (showVoiceChanges ? effectiveVoiceChangesBodyHeight() : 0) +
                       (showVelocity ? velocityBodyHeight(m_lastHostHeight) : 0) +
                       (showAutomation ? effectiveAutomationBodyHeight() : 0);
    return std::min(m_lastHostHeight, m_chrome.header + handles + bodies);
}

std::optional<int> DrawerSections::velocityHeight() const noexcept
{
    return m_velocityBodyHeight;
}

std::optional<int> DrawerSections::automationHeight() const noexcept
{
    return m_automationBodyHeight;
}

std::optional<int> DrawerSections::voiceChangesHeight() const noexcept
{
    return m_voiceChangesBodyHeight;
}

bool DrawerSections::velocityVisible() const noexcept
{
    return pageVisible(EditorDrawerPage::Velocity);
}

bool DrawerSections::automationVisible() const noexcept
{
    return pageVisible(EditorDrawerPage::Automations);
}

bool DrawerSections::voiceChangesVisible() const noexcept
{
    return pageVisible(EditorDrawerPage::VoiceChanges);
}

EditorDrawerPage DrawerSections::activePage() const noexcept
{
    return m_activePage;
}

void DrawerSections::applyState(DrawerSectionState velocity, DrawerSectionState automation,
                                DrawerSectionState voiceChanges, EditorDrawerPage activePage)
{
    m_velocityBodyHeight = velocity.height;
    m_automationBodyHeight = automation.height;
    m_voiceChangesBodyHeight = voiceChanges.height;
    m_velocityVisible = velocity.visible;
    m_automationVisible = automation.visible;
    m_voiceChangesVisible = voiceChanges.visible;
    m_activePage = activePage;
    syncDetentState();
}

bool DrawerSections::pageVisible(EditorDrawerPage page) const noexcept
{
    switch (page) {
    case EditorDrawerPage::VoiceChanges:
        return m_voiceChangesVisible;
    case EditorDrawerPage::Velocity:
        return m_velocityVisible;
    case EditorDrawerPage::Automations:
        return m_automationVisible;
    }
    Q_UNREACHABLE();
}

int DrawerSections::pageBodyHeight(EditorDrawerPage page) const
{
    switch (page) {
    case EditorDrawerPage::VoiceChanges:
        return effectiveVoiceChangesBodyHeight();
    case EditorDrawerPage::Velocity:
        return velocityBodyHeight(m_lastHostHeight);
    case EditorDrawerPage::Automations:
        return effectiveAutomationBodyHeight();
    }
    Q_UNREACHABLE();
}

std::optional<int> &DrawerSections::pageStoredHeight(EditorDrawerPage page) noexcept
{
    switch (page) {
    case EditorDrawerPage::VoiceChanges:
        return m_voiceChangesBodyHeight;
    case EditorDrawerPage::Velocity:
        return m_velocityBodyHeight;
    case EditorDrawerPage::Automations:
        return m_automationBodyHeight;
    }
    Q_UNREACHABLE();
}

const std::optional<int> &DrawerSections::pageStoredHeight(EditorDrawerPage page) const noexcept
{
    switch (page) {
    case EditorDrawerPage::VoiceChanges:
        return m_voiceChangesBodyHeight;
    case EditorDrawerPage::Velocity:
        return m_velocityBodyHeight;
    case EditorDrawerPage::Automations:
        return m_automationBodyHeight;
    }
    Q_UNREACHABLE();
}

int DrawerSections::resizeBodyHeight(EditorDrawerPage page) const
{
    ensureChrome();
    return std::max(m_chrome.minBody, pageBodyHeight(page));
}

int DrawerSections::maximumResizeBodyHeight(EditorDrawerPage page) const
{
    ensureChrome();

    int otherBodies = 0;
    int visibleHandleCount = 0;
    for (const EditorDrawerPage candidate :
         {EditorDrawerPage::VoiceChanges, EditorDrawerPage::Velocity,
          EditorDrawerPage::Automations}) {
        if (!pageVisible(candidate))
            continue;
        ++visibleHandleCount;
        if (candidate != page)
            otherBodies += pageBodyHeight(candidate);
    }

    return std::max(m_chrome.minBody, m_lastHostHeight - m_chrome.header -
                                          m_chrome.handle * visibleHandleCount - otherBodies);
}

void DrawerSections::setResizeBodyHeight(EditorDrawerPage page, std::optional<int> height)
{
    std::optional<int> &bodyHeight = pageStoredHeight(page);
    if (bodyHeight == height)
        return;
    bodyHeight = height;
    emit geometryChanged();
}

void DrawerSections::publishResizeState()
{
    emit statePublished(true);
}

void DrawerSections::focusActivePage()
{
    const auto focusPage = [this](EditorDrawerPage page) {
        switch (page) {
        case EditorDrawerPage::VoiceChanges:
            return voiceChangesVisible() &&
                   m_owner.focusTimelineBand(songview::TimelineBand::VoiceChanges,
                                             Qt::OtherFocusReason);
        case EditorDrawerPage::Velocity:
            return velocityVisible() && m_owner.focusTimelineBand(songview::TimelineBand::Velocity,
                                                                  Qt::OtherFocusReason);
        case EditorDrawerPage::Automations:
            return automationVisible() &&
                   m_owner.focusTimelineBand(songview::TimelineBand::Automation,
                                             Qt::OtherFocusReason);
        }
        Q_UNREACHABLE();
    };
    if (focusPage(m_activePage))
        return;

    // Visual order: VoiceChanges above Velocity above Automations.
    for (const EditorDrawerPage page : {EditorDrawerPage::VoiceChanges, EditorDrawerPage::Velocity,
                                        EditorDrawerPage::Automations}) {
        if (focusPage(page))
            return;
    }
}

void DrawerSections::cancelVisibleInteractions()
{
    if (voiceChangesVisible())
        m_voiceChanges->cancelInteraction();
    if (velocityVisible())
        m_velocity->cancelInteraction();
    if (automationVisible())
        m_automation->cancelInteraction();
}

void DrawerSections::arrangeLocal(const QSize &overlaySize)
{
    ensureChrome();
    syncDetentState();

    const int width = std::max(0, overlaySize.width());
    const int height = std::max(0, overlaySize.height());
    const int chrome = m_chrome.header;
    const int handleHeight = m_chrome.handle;
    const bool showVelocity = velocityVisible();
    const bool showAutomation = automationVisible();
    const bool showVoiceChanges = voiceChangesVisible();
    const int fixedHeight =
        chrome + handleHeight * (int(showVelocity) + int(showAutomation) + int(showVoiceChanges));
    const int availableBodyHeight = std::max(0, height - fixedHeight);
    const int requestedAutomationHeight = effectiveAutomationBodyHeight();

    // Under the host clamp, allocate VoiceChanges first, preserve the
    // Automation drawer's height second, and give Velocity the remainder.
    const int voiceChangesHeight =
        showVoiceChanges ? std::min(effectiveVoiceChangesBodyHeight(), availableBodyHeight) : 0;
    const int automationHeight =
        showAutomation ? std::min(requestedAutomationHeight,
                                  std::max(0, availableBodyHeight - voiceChangesHeight))
                       : 0;
    const int velocityHeight =
        showVelocity
            ? std::min(velocityBodyHeight(m_lastHostHeight),
                       std::max(0, availableBodyHeight - voiceChangesHeight - automationHeight))
            : 0;

    const int velocityLeftInset = std::max(0, m_chrome.plotOrigin - m_velocity->plotOrigin());
    const int velocityLeft = std::min(velocityLeftInset, width);
    const int velocityWidth = width - velocityLeft;

    // Canonical body rectangles are overlay-local. Hidden pages hold no stale rectangle.
    int y = 0;
    std::optional<QRect> voiceChangesBodyRect;
    std::optional<QRect> velocityBodyRect;
    std::optional<QRect> automationBodyRect;
    if (showVoiceChanges) {
        voiceChangesBodyRect = QRect(0, y + handleHeight, width, voiceChangesHeight);
        y += handleHeight + voiceChangesHeight;
    }
    if (showVelocity) {
        velocityBodyRect = QRect(velocityLeft, y + handleHeight, velocityWidth, velocityHeight);
        y += handleHeight + velocityHeight;
    }
    if (showAutomation) {
        automationBodyRect = QRect(0, y + handleHeight, width, automationHeight);
        y += handleHeight + automationHeight;
    }
    m_voiceChangesBodyRect = voiceChangesBodyRect;
    m_velocityBodyRect = velocityBodyRect;
    m_automationBodyRect = automationBodyRect;

    DrawerChromeSnapshot snapshot;
    snapshot.voiceChangesHandleVisible = showVoiceChanges;
    snapshot.velocityHandleVisible = showVelocity;
    snapshot.automationHandleVisible = showAutomation;
    snapshot.detentEnabled = m_detentEnabled;
    snapshot.detentChecked = m_detentEnabled && m_velocity->useDetents();
    snapshot.velocityChecked = showVelocity;
    snapshot.automationChecked = showAutomation;
    snapshot.voiceChangesChecked = showVoiceChanges;

    if (voiceChangesBodyRect) {
        snapshot.voiceChangesHandleRect =
            QRectF(0, voiceChangesBodyRect->top() - handleHeight, width, handleHeight);
    }
    if (velocityBodyRect) {
        snapshot.velocityHandleRect = QRectF(velocityLeft, velocityBodyRect->top() - handleHeight,
                                             velocityWidth, handleHeight);
    }
    if (automationBodyRect) {
        snapshot.automationHandleRect =
            QRectF(0, automationBodyRect->top() - handleHeight, width, handleHeight);
        snapshot.automationScrollbarRect =
            QRectF(automationBodyRect->x(), automationBodyRect->y(),
                   layout::space(layout::Space::Two), automationBodyRect->height());
    }

    snapshot.barRect = QRectF(0, y, width, chrome);
    const int buttonInset = layout::space(layout::Space::One);
    const int buttonSize = std::max(layout::singlePixel(), chrome - 2 * buttonInset);
    const int toggleGroupWidth = 3 * buttonSize + 2 * buttonInset;
    const int pianoKeysWidth =
        std::min(m_velocity->plotOrigin(), std::max(0, width - velocityLeft));
    const int voiceChangesButtonX =
        std::clamp(velocityLeft + (pianoKeysWidth - toggleGroupWidth) / 2, 0,
                   std::max(0, width - toggleGroupWidth));
    const int automationButtonX = voiceChangesButtonX + buttonSize + buttonInset;
    const int velocityButtonX = automationButtonX + buttonSize + buttonInset;
    snapshot.voiceChangesToggleRect =
        QRectF(voiceChangesButtonX, y + buttonInset, buttonSize, buttonSize);
    snapshot.automationToggleRect =
        QRectF(automationButtonX, y + buttonInset, buttonSize, buttonSize);
    snapshot.velocityToggleRect = QRectF(velocityButtonX, y + buttonInset, buttonSize, buttonSize);

    snapshot.detentVisible = showVelocity && m_detentEnabled;
    if (snapshot.detentVisible && velocityBodyRect) {
        const int velocityGutterWidth = std::min(m_velocity->plotOrigin(), velocityWidth);
        const int detentButtonSize = std::min(buttonSize, velocityGutterWidth);
        const int detentY = velocityBodyRect->bottom() + 1 - detentButtonSize;
        snapshot.detentRect =
            QRectF(velocityBodyRect->left(), detentY, detentButtonSize, detentButtonSize);
    }

    m_chromeSnapshot = std::move(snapshot);
}

std::optional<QRect> DrawerSections::bodyRect(EditorDrawerPage page) const noexcept
{
    switch (page) {
    case EditorDrawerPage::Automations:
        return m_automationBodyRect;
    case EditorDrawerPage::Velocity:
        return m_velocityBodyRect;
    case EditorDrawerPage::VoiceChanges:
        return m_voiceChangesBodyRect;
    }
    Q_UNREACHABLE();
}
