#include "ui/editordrawer/drawersections.h"

#include <QCursor>
#include <QEvent>
#include <QFrame>
#include <QIcon>
#include <QMouseEvent>
#include <QPainter>
#include <QSignalBlocker>
#include <QToolButton>

#include <algorithm>
#include <cmath>
#include <optional>

#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/layout.h"
#include "ui/theme/themeruntime.h"

namespace {

#ifdef Q_OS_WIN
class DrawerToggle final : public QToolButton
{
  public:
    explicit DrawerToggle(QWidget *parent)
        : QToolButton(parent)
        , m_outline(themes::color(themes::Role::combo_outline), layout::singlePixel())
    {
        m_outline.setJoinStyle(Qt::MiterJoin);
        refreshOutlineRect();
    }

  protected:
    void paintEvent(QPaintEvent *event) override
    {
        QToolButton::paintEvent(event);
        QPainter painter(this);
        painter.setPen(m_outline);
        painter.setBrush(Qt::NoBrush);
        painter.drawRect(m_outlineRect);
    }

    void resizeEvent(QResizeEvent *event) override
    {
        QToolButton::resizeEvent(event);
        refreshOutlineRect();
    }

    void changeEvent(QEvent *event) override
    {
        QToolButton::changeEvent(event);
        if (event->type() == QEvent::StyleChange || event->type() == QEvent::ThemeChange ||
            event->type() == QEvent::PaletteChange ||
            event->type() == QEvent::ApplicationPaletteChange) {
            m_outline.setColor(themes::color(themes::Role::combo_outline));
        }
    }

  private:
    void refreshOutlineRect()
    {
        const qreal halfStroke = m_outline.widthF() / 2.0;
        m_outlineRect = QRectF(rect()).adjusted(halfStroke, halfStroke, -halfStroke, -halfStroke);
    }

    QPen m_outline;
    QRectF m_outlineRect;
};
#else
using DrawerToggle = QToolButton;
#endif

} // namespace

DrawerSections::DrawerSections(QWidget *parent, AutomationPage *automation, VelocityArea *velocity,
                               VoiceChangeArea *voiceChanges)
    : QWidget(parent)
    , m_automation(automation)
    , m_velocity(velocity)
    , m_voiceChanges(voiceChanges)
{
    setObjectName(QStringLiteral("drawerSections"));
    setFocusPolicy(Qt::NoFocus);

    m_automation->setParent(this);
    m_velocity->setParent(this);
    m_voiceChanges->setParent(this);
    m_automation->show();
    const auto makeToggle = [this](const QString &text, EditorDrawerPage page) {
        auto *button = new DrawerToggle(this);
        button->setCheckable(true);
        button->setChecked(true);
        button->setText(text);
        button->setToolButtonStyle(Qt::ToolButtonTextBesideIcon);
        button->setFocusPolicy(Qt::NoFocus);
        connect(button, &QToolButton::toggled, this, [this, page](bool) {
            m_activePage = page;
            emit statePublished(false);
        });
        return button;
    };
    m_velocityToggle = makeToggle(QString(), EditorDrawerPage::Velocity);
    m_velocityToggle->setObjectName(QStringLiteral("velocityDrawerToggle"));
    m_velocityToggle->setToolButtonStyle(Qt::ToolButtonIconOnly);
    m_velocityToggle->setAccessibleName(tr("Show or hide velocity (V)"));
    {
        QIcon icon(QStringLiteral(":/icons/velocity.svg"));
        icon.setIsMask(true);
        m_velocityToggle->setIcon(icon);
    }
    m_velocityToggle->setToolTip(tr("Show or hide velocity (V)"));
    m_voiceChangesToggle = makeToggle(QString(), EditorDrawerPage::VoiceChanges);
    m_voiceChangesToggle->setObjectName(QStringLiteral("voiceChangesDrawerToggle"));
    m_voiceChangesToggle->setToolButtonStyle(Qt::ToolButtonIconOnly);
    m_voiceChangesToggle->setAccessibleName(tr("Show or hide voice changes (P)"));
    {
        QIcon icon(QStringLiteral(":/icons/flat-music.svg"));
        icon.setIsMask(true);
        m_voiceChangesToggle->setIcon(icon);
    }
    m_voiceChangesToggle->setToolTip(tr("Show or hide voice changes (P)"));
    m_automationToggle = makeToggle(QString(), EditorDrawerPage::Automations);
    m_automationToggle->setObjectName(QStringLiteral("automationDrawerToggle"));
    m_automationToggle->setToolButtonStyle(Qt::ToolButtonIconOnly);
    m_automationToggle->setAccessibleName(tr("Show or hide automation (A)"));
    {
        QIcon icon(QStringLiteral(":/icons/automation.svg"));
        icon.setIsMask(true);
        m_automationToggle->setIcon(icon);
    }
    m_automationToggle->setToolTip(tr("Show or hide automation (A)"));
    m_detentToggle = new QToolButton(this);
    m_detentToggle->setObjectName(QStringLiteral("velocityDetentToggle"));
    m_detentToggle->setCheckable(true);
    m_detentToggle->setChecked(true);
    m_detentToggle->setToolButtonStyle(Qt::ToolButtonIconOnly);
    m_detentToggle->setFocusPolicy(Qt::NoFocus);
    m_detentToggle->setStyleSheet(
        QStringLiteral("QToolButton#velocityDetentToggle { background-color: transparent; "
                       "border: none; padding: 0; }"));
    m_detentToggle->setAccessibleName(tr("Use velocity detents"));
    refreshDetentIcon();
    m_detentToggle->setToolTip(tr("Turn velocity detents on or off"));
    connect(m_detentToggle, &QToolButton::toggled, this, [this](bool) {
        m_velocity->setUseDetents(m_detentToggle->isChecked());
        emit statePublished(false);
    });
    const QString toggleStyle =
        QStringLiteral("QToolButton { background-color:%1; color: palette(windowText); "
                       "padding:0; border:1px solid %2; }"
                       "QToolButton:hover { background-color:%1; }"
                       "QToolButton:checked { background-color: palette(highlight); "
                       "color: palette(highlightedText); }")
            .arg(themes::color(themes::Role::combo_background).name(),
                 themes::color(themes::Role::combo_outline).name());
    m_velocityToggle->setStyleSheet(toggleStyle);
    m_automationToggle->setStyleSheet(toggleStyle);
    m_voiceChangesToggle->setStyleSheet(toggleStyle);
    m_automationBar = new QFrame(this);
    m_automationBar->setObjectName(QStringLiteral("automationDrawerBar"));
    m_automationBar->setFocusPolicy(Qt::NoFocus);

    const auto makeResizeHandle = [this](const QString &name, const QString &toolTip) {
        auto *handle = new QFrame(this);
        handle->setObjectName(name);
        handle->setAccessibleName(toolTip);
        handle->setToolTip(toolTip);
        handle->setMouseTracking(true);
        handle->installEventFilter(this);
        return handle;
    };
    m_velocityHandle =
        makeResizeHandle(QStringLiteral("velocityResizeHandle"), tr("Resize velocity pane"));
    m_automationHandle =
        makeResizeHandle(QStringLiteral("automationResizeHandle"), tr("Resize automation pane"));
    m_voiceChangesHandle = makeResizeHandle(QStringLiteral("voiceChangesResizeHandle"),
                                            tr("Resize voice changes pane"));
    setStyleSheet(QStringLiteral(
        "QFrame#automationDrawerBar { border: 1px solid palette(mid); "
        "background: palette(window); }"
        "QFrame#velocityResizeHandle, QFrame#automationResizeHandle, "
        "QFrame#voiceChangesResizeHandle { background: palette(mid); }"
        "QFrame#velocityResizeHandle:hover, QFrame#automationResizeHandle:hover, "
        "QFrame#voiceChangesResizeHandle:hover { background: palette(highlight); }"));
    m_automationBar->stackUnder(m_automationToggle);
    m_automationBar->stackUnder(m_velocityToggle);
    m_automationBar->stackUnder(m_voiceChangesToggle);
    m_automationToggle->raise();
    m_velocityToggle->raise();
    m_voiceChangesToggle->raise();
    m_detentToggle->raise();
    m_velocity->setContextChangedCallback([this] { syncDetentToggle(); });
    syncDetentToggle();
}

void DrawerSections::ensureChrome() const
{
    if (!m_chromeDirty)
        return;
    m_chrome.header = layout::chromeRowHeight(font(), layout::space(layout::Space::Zero));
    m_chrome.handle = layout::fontPx(1.0 / 3.0);
    m_chrome.minBody = layout::fontPx(17.0 / 5.0);
    m_chrome.pianoRollReserve = layout::fontPx(10.0);
    m_chrome.plotOrigin = layout::fontPx(17.5 + 13.0 / 3.0);
    m_chromeDirty = false;
}

void DrawerSections::syncDetentToggle()
{
    const bool psg = m_velocity->isPsgContext();
    const bool visible = psg && m_velocityToggle->isChecked();
    if (m_detentToggle->isHidden() == visible)
        m_detentToggle->setVisible(visible);
    const bool wasEnabled = m_detentToggle->isEnabled();
    const bool useDetents = psg && (!wasEnabled || m_velocity->useDetents());
    {
        const QSignalBlocker blocker(m_detentToggle);
        m_detentToggle->setEnabled(psg);
        m_detentToggle->setChecked(useDetents);
    }
    if (psg && !wasEnabled)
        m_velocity->setUseDetents(true);
}

void DrawerSections::refreshDetentIcon()
{
    const QIcon sourceIcon(QStringLiteral(":/icons/velocity_labels.svg"));
    const auto tinted = [&sourceIcon](const QColor &color) {
        auto pixmap = sourceIcon.pixmap(QSize(512, 512));
        QPainter painter(&pixmap);
        painter.setCompositionMode(QPainter::CompositionMode_SourceIn);
        painter.fillRect(pixmap.rect(), color);
        return pixmap;
    };
    QIcon icon;
    icon.addPixmap(tinted(palette().color(QPalette::WindowText)));
    icon.addPixmap(tinted(palette().color(QPalette::Highlight)), QIcon::Normal, QIcon::On);
    icon.addPixmap(tinted(palette().color(QPalette::Highlight)), QIcon::Active, QIcon::On);
    const QColor disabled = palette().color(QPalette::Disabled, QPalette::WindowText);
    icon.addPixmap(tinted(disabled), QIcon::Disabled, QIcon::Off);
    icon.addPixmap(tinted(disabled), QIcon::Disabled, QIcon::On);
    m_detentToggle->setIcon(icon);
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
    const QSignalBlocker velocityBlocked(m_velocityToggle);
    const QSignalBlocker automationBlocked(m_automationToggle);
    const QSignalBlocker voiceChangesBlocked(m_voiceChangesToggle);
    m_velocityBodyHeight = velocity.height;
    m_automationBodyHeight = automation.height;
    m_voiceChangesBodyHeight = voiceChanges.height;
    setPageVisible(EditorDrawerPage::Velocity, velocity.visible);
    setPageVisible(EditorDrawerPage::Automations, automation.visible);
    setPageVisible(EditorDrawerPage::VoiceChanges, voiceChanges.visible);
    m_activePage = activePage;
    syncDetentToggle();
}

void DrawerSections::setPageVisible(EditorDrawerPage page, bool visible)
{
    QToolButton *toggle = pageToggle(page);
    if (toggle->isChecked() != visible)
        toggle->setChecked(visible);
}

QToolButton *DrawerSections::pageToggle(EditorDrawerPage page) const noexcept
{
    switch (page) {
    case EditorDrawerPage::VoiceChanges:
        return m_voiceChangesToggle;
    case EditorDrawerPage::Velocity:
        return m_velocityToggle;
    case EditorDrawerPage::Automations:
        return m_automationToggle;
    }
    Q_UNREACHABLE();
}

bool DrawerSections::pageVisible(EditorDrawerPage page) const noexcept
{
    switch (page) {
    case EditorDrawerPage::VoiceChanges:
        return m_voiceChangesToggle->isChecked();
    case EditorDrawerPage::Velocity:
        return m_velocityToggle->isChecked();
    case EditorDrawerPage::Automations:
        return m_automationToggle->isChecked();
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

QWidget *DrawerSections::pageResizeHandle(EditorDrawerPage page) const noexcept
{
    switch (page) {
    case EditorDrawerPage::VoiceChanges:
        return m_voiceChangesHandle;
    case EditorDrawerPage::Velocity:
        return m_velocityHandle;
    case EditorDrawerPage::Automations:
        return m_automationHandle;
    }
    Q_UNREACHABLE();
}

EditorDrawerPage DrawerSections::resizePageForHandle(const QWidget *handle) const noexcept
{
    if (handle == m_voiceChangesHandle)
        return EditorDrawerPage::VoiceChanges;
    if (handle == m_velocityHandle)
        return EditorDrawerPage::Velocity;
    Q_ASSERT(handle == m_automationHandle);
    return EditorDrawerPage::Automations;
}

void DrawerSections::focusActivePage()
{
    const auto canvasFor = [this](EditorDrawerPage page) -> QWidget * {
        switch (page) {
        case EditorDrawerPage::VoiceChanges:
            return m_voiceChanges;
        case EditorDrawerPage::Velocity:
            return m_velocity;
        case EditorDrawerPage::Automations:
            return m_automation->canvas();
        }
        Q_UNREACHABLE();
    };
    QWidget *target = canvasFor(m_activePage);
    if (!target || !target->isVisible()) {
        // Visual order: VoiceChanges above Velocity above Automations.
        for (const EditorDrawerPage page :
             {EditorDrawerPage::VoiceChanges, EditorDrawerPage::Velocity,
              EditorDrawerPage::Automations}) {
            QWidget *candidate = canvasFor(page);
            if (candidate && candidate->isVisible()) {
                target = candidate;
                break;
            }
        }
    }
    if (target && target->isVisible())
        target->setFocus(Qt::OtherFocusReason);
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

bool DrawerSections::eventFilter(QObject *watched, QEvent *event)
{
    if (watched != pageResizeHandle(EditorDrawerPage::VoiceChanges) &&
        watched != pageResizeHandle(EditorDrawerPage::Velocity) &&
        watched != pageResizeHandle(EditorDrawerPage::Automations))
        return QWidget::eventFilter(watched, event);

    ensureChrome();
    auto *handle = static_cast<QWidget *>(watched);
    const EditorDrawerPage page = resizePageForHandle(handle);
    if (event->type() == QEvent::Enter) {
        handle->setCursor(Qt::SizeVerCursor);
        return false;
    }
    if (event->type() == QEvent::Leave && m_resizeTarget != handle) {
        handle->unsetCursor();
        return false;
    }
    if (event->type() == QEvent::MouseButtonPress) {
        auto *mouse = static_cast<QMouseEvent *>(event);
        if (mouse->button() != Qt::LeftButton)
            return false;
        handle->setCursor(Qt::SizeVerCursor);
        m_resizeTarget = handle;
        m_resizeStartGlobalY = mouse->globalPosition().y();
        m_resizeOriginalBodyHeight = pageStoredHeight(page);
        m_resizeStartBodyHeight = std::max(m_chrome.minBody, pageBodyHeight(page));
        handle->grabMouse();
        return true;
    }
    if (event->type() == QEvent::MouseMove && m_resizeTarget == handle) {
        const auto *mouse = static_cast<QMouseEvent *>(event);
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
        // The drawer is currently sized to the existing requests, so using its current height
        // here would make every page saturate at its drag-start height.
        const int maximum =
            std::max(m_chrome.minBody, m_lastHostHeight - m_chrome.header -
                                           m_chrome.handle * visibleHandleCount - otherBodies);
        const int requested =
            std::clamp(m_resizeStartBodyHeight +
                           int(std::lround(m_resizeStartGlobalY - mouse->globalPosition().y())),
                       m_chrome.minBody, maximum);
        std::optional<int> &bodyHeight = pageStoredHeight(page);
        const std::optional<int> originalHeight = m_resizeOriginalBodyHeight;
        const std::optional<int> target =
            requested == m_resizeStartBodyHeight ? originalHeight : std::optional<int>{requested};
        if (bodyHeight != target) {
            bodyHeight = target;
            emit geometryChanged();
        }
        return true;
    }
    if (event->type() == QEvent::MouseButtonRelease && m_resizeTarget == handle) {
        auto *mouse = static_cast<QMouseEvent *>(event);
        if (mouse->button() != Qt::LeftButton)
            return false;
        m_resizeTarget = nullptr;
        handle->releaseMouse();
        handle->unsetCursor();
        emit statePublished(true);
        return true;
    }
    if (event->type() == QEvent::UngrabMouse && m_resizeTarget == handle) {
        m_resizeTarget = nullptr;
        handle->unsetCursor();
    }
    return QWidget::eventFilter(watched, event);
}

void DrawerSections::arrangeLocal()
{
    ensureChrome();
    syncDetentToggle();
    const int width = this->width();
    const int chrome = m_chrome.header;
    const int handleHeight = m_chrome.handle;
    const bool showVelocity = m_velocityToggle->isChecked();
    const bool showAutomation = m_automationToggle->isChecked();
    const bool showVoiceChanges = m_voiceChangesToggle->isChecked();
    const int fixedHeight =
        chrome + handleHeight * (int(showVelocity) + int(showAutomation) + int(showVoiceChanges));
    const int availableBodyHeight = std::max(0, height() - fixedHeight);
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

    const auto setVisibleIf = [](QWidget *widget, bool visible) {
        if (widget->isHidden() == visible)
            widget->setVisible(visible);
    };
    const auto setGeometryIf = [](QWidget *widget, const QRect &geometry) {
        if (widget->geometry() != geometry)
            widget->setGeometry(geometry);
    };

    const int velocityLeftInset = std::max(0, m_chrome.plotOrigin - m_velocity->plotOrigin());
    const int velocityLeft = std::min(velocityLeftInset, width);
    const int velocityWidth = width - velocityLeft;
    setVisibleIf(m_voiceChanges, showVoiceChanges);
    setVisibleIf(m_voiceChangesHandle, showVoiceChanges);
    setVisibleIf(m_voiceChangesToggle, true);
    setVisibleIf(m_velocity, showVelocity);
    setVisibleIf(m_velocityHandle, showVelocity);
    setVisibleIf(m_velocityToggle, true);
    setVisibleIf(m_detentToggle, showVelocity && m_velocity->isPsgContext());
    setVisibleIf(m_automation, showAutomation);
    setVisibleIf(m_automationHandle, showAutomation);
    setVisibleIf(m_automationBar, true);

    // Visual stack order, top to bottom: VoiceChanges, Velocity, Automations, bar.
    int y = 0;
    if (showVoiceChanges) {
        setGeometryIf(m_voiceChangesHandle, QRect(0, y, width, handleHeight));
        y += handleHeight;
        setGeometryIf(m_voiceChanges, QRect(0, y, width, voiceChangesHeight));
        y += voiceChangesHeight;
    }
    int velocityBottom = 0;
    if (showVelocity) {
        setGeometryIf(m_velocityHandle, QRect(velocityLeft, y, velocityWidth, handleHeight));
        y += handleHeight;
        setGeometryIf(m_velocity, QRect(velocityLeft, y, velocityWidth, velocityHeight));
        y += velocityHeight;
        velocityBottom = y;
    }
    if (showAutomation) {
        setGeometryIf(m_automationHandle, QRect(0, y, width, handleHeight));
        y += handleHeight;
        setGeometryIf(m_automation, QRect(0, y, width, automationHeight));
        y += automationHeight;
    }
    const int buttonInset = layout::space(layout::Space::One);
    const int buttonSize = std::max(layout::singlePixel(), chrome - 2 * buttonInset);
    const int iconSize = std::max(1, buttonSize - 2 * buttonInset);
    const int toggleGroupWidth = 3 * buttonSize + 2 * buttonInset;
    const int pianoKeysWidth =
        std::min(m_velocity->plotOrigin(), std::max(0, width - velocityLeft));
    const int voiceChangesButtonX =
        std::clamp(velocityLeft + (pianoKeysWidth - toggleGroupWidth) / 2, 0,
                   std::max(0, width - toggleGroupWidth));
    const int automationButtonX = voiceChangesButtonX + buttonSize + buttonInset;
    const int velocityButtonX = automationButtonX + buttonSize + buttonInset;
    setGeometryIf(m_automationBar, QRect(0, y, width, chrome));
    const QSize toggleIconSize(iconSize, iconSize);
    for (QToolButton *toggle : {m_voiceChangesToggle, m_automationToggle, m_velocityToggle}) {
        if (toggle->iconSize() != toggleIconSize)
            toggle->setIconSize(toggleIconSize);
    }
    setGeometryIf(m_voiceChangesToggle,
                  QRect(voiceChangesButtonX, y + buttonInset, buttonSize, buttonSize));
    setGeometryIf(m_automationToggle,
                  QRect(automationButtonX, y + buttonInset, buttonSize, buttonSize));
    setGeometryIf(m_velocityToggle,
                  QRect(velocityButtonX, y + buttonInset, buttonSize, buttonSize));
    const int velocityGutterWidth = std::min(m_velocity->plotOrigin(), velocityWidth);
    const int detentButtonSize = std::min(buttonSize, velocityGutterWidth);
    const QSize detentIconSize(std::max(1, detentButtonSize - buttonInset),
                               std::max(1, detentButtonSize - buttonInset));
    if (m_detentToggle->iconSize() != detentIconSize)
        m_detentToggle->setIconSize(detentIconSize);
    const int detentY = std::max(0, velocityBottom - detentButtonSize);
    setGeometryIf(m_detentToggle, QRect(velocityLeft, detentY, detentButtonSize, detentButtonSize));
}

QRegion DrawerSections::occupiedRegion() const
{
    QRegion occupied;
    const auto addVisible = [&occupied](const QWidget *widget) {
        if (!widget->isHidden() && !widget->geometry().isEmpty())
            occupied += widget->geometry();
    };
    addVisible(m_velocity);
    addVisible(m_velocityHandle);
    addVisible(m_voiceChanges);
    addVisible(m_voiceChangesHandle);
    addVisible(m_voiceChangesToggle);
    addVisible(m_detentToggle);
    addVisible(m_automation);
    addVisible(m_automationHandle);
    addVisible(m_automationBar);
    addVisible(m_velocityToggle);
    addVisible(m_automationToggle);
    return occupied;
}

void DrawerSections::changeEvent(QEvent *event)
{
    QWidget::changeEvent(event);
    if (m_detentToggle &&
        (event->type() == QEvent::StyleChange || event->type() == QEvent::ThemeChange ||
         event->type() == QEvent::PaletteChange ||
         event->type() == QEvent::ApplicationPaletteChange)) {
        refreshDetentIcon();
    }
    switch (event->type()) {
    case QEvent::FontChange:
    case QEvent::StyleChange:
    case QEvent::ThemeChange:
        m_chromeDirty = true;
        emit geometryChanged();
        break;
    default:
        break;
    }
}
