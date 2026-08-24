#include "ui/editordrawer/drawersections.h"

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

DrawerSections::DrawerSections(QWidget *parent, AutomationPage *automation, VelocityArea *velocity)
    : QWidget(parent)
    , m_automation(automation)
    , m_velocity(velocity)
{
    setObjectName(QStringLiteral("drawerSections"));
    setFocusPolicy(Qt::NoFocus);

    m_automation->setParent(this);
    m_velocity->setParent(this);
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
    m_automationBar = new QFrame(this);
    m_automationBar->setObjectName(QStringLiteral("automationDrawerBar"));
    m_automationBar->setFocusPolicy(Qt::NoFocus);

    const auto makeResizeHandle = [this](const QString &name, const QString &toolTip) {
        auto *handle = new QFrame(this);
        handle->setObjectName(name);
        handle->setAccessibleName(toolTip);
        handle->setToolTip(toolTip);
        handle->setCursor(Qt::SizeVerCursor);
        handle->setMouseTracking(true);
        handle->installEventFilter(this);
        return handle;
    };
    m_velocityHandle =
        makeResizeHandle(QStringLiteral("velocityResizeHandle"), tr("Resize velocity pane"));
    m_automationHandle =
        makeResizeHandle(QStringLiteral("automationResizeHandle"), tr("Resize automation pane"));
    setStyleSheet(QStringLiteral(
        "QFrame#automationDrawerBar { border: 1px solid palette(mid); "
        "background: palette(window); }"
        "QFrame#velocityResizeHandle, QFrame#automationResizeHandle { background: palette(mid); }"
        "QFrame#velocityResizeHandle:hover, QFrame#automationResizeHandle:hover { "
        "background: palette(highlight); }"));
    m_automationBar->stackUnder(m_automationToggle);
    m_automationBar->stackUnder(m_velocityToggle);
    m_automationToggle->raise();
    m_velocityToggle->raise();
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
    m_chrome.minBody = layout::fontPx(17.0 / 3.0);
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
    const int automationHeight = effectiveAutomationBodyHeight();
    const int handles = m_chrome.handle * (int(showVelocity) + int(showAutomation));
    const int bodies = (showVelocity ? velocityBodyHeight(m_lastHostHeight) : 0) +
                       (showAutomation ? automationHeight : 0);
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

bool DrawerSections::velocityVisible() const noexcept
{
    return m_velocityToggle->isChecked();
}

bool DrawerSections::automationVisible() const noexcept
{
    return m_automationToggle->isChecked();
}

EditorDrawerPage DrawerSections::activePage() const noexcept
{
    return m_activePage;
}

void DrawerSections::applyState(DrawerSectionState velocity, DrawerSectionState automation,
                                EditorDrawerPage activePage)
{
    const QSignalBlocker velocityBlocked(m_velocityToggle);
    const QSignalBlocker automationBlocked(m_automationToggle);
    m_velocityBodyHeight = velocity.height;
    m_automationBodyHeight = automation.height;
    setPageVisible(EditorDrawerPage::Velocity, velocity.visible);
    setPageVisible(EditorDrawerPage::Automations, automation.visible);
    m_activePage = activePage;
    syncDetentToggle();
}

void DrawerSections::setPageVisible(EditorDrawerPage page, bool visible)
{
    QToolButton *toggle =
        page == EditorDrawerPage::Velocity ? m_velocityToggle : m_automationToggle;
    if (toggle->isChecked() != visible)
        toggle->setChecked(visible);
}

void DrawerSections::focusActivePage()
{
    const auto canvasFor = [this](EditorDrawerPage page) {
        return page == EditorDrawerPage::Velocity ? static_cast<QWidget *>(m_velocity)
                                                  : static_cast<QWidget *>(m_automation->canvas());
    };
    QWidget *target = canvasFor(m_activePage);
    if (!target || !target->isVisible()) {
        const EditorDrawerPage fallback = m_activePage == EditorDrawerPage::Velocity
                                              ? EditorDrawerPage::Automations
                                              : EditorDrawerPage::Velocity;
        target = canvasFor(fallback);
    }
    if (target && target->isVisible())
        target->setFocus(Qt::OtherFocusReason);
}

void DrawerSections::cancelVisibleInteractions()
{
    if (m_velocityToggle->isChecked())
        m_velocity->cancelInteraction();
    if (m_automationToggle->isChecked())
        m_automation->cancelInteraction();
}

bool DrawerSections::eventFilter(QObject *watched, QEvent *event)
{
    if (watched != m_velocityHandle && watched != m_automationHandle)
        return QWidget::eventFilter(watched, event);

    ensureChrome();
    auto *handle = static_cast<QWidget *>(watched);
    if (event->type() == QEvent::MouseButtonPress) {
        auto *mouse = static_cast<QMouseEvent *>(event);
        if (mouse->button() != Qt::LeftButton)
            return false;
        m_resizeTarget = handle;
        m_resizeStartGlobalY = mouse->globalPosition().y();
        const bool velocity = handle == m_velocityHandle;
        const int automationHeight = effectiveAutomationBodyHeight();
        m_resizeOriginalBodyHeight = velocity ? m_velocityBodyHeight : m_automationBodyHeight;
        const int bodyHeight = velocity ? velocityBodyHeight(m_lastHostHeight) : automationHeight;
        m_resizeStartBodyHeight = std::max(m_chrome.minBody, bodyHeight);
        handle->grabMouse();
        return true;
    }
    if (event->type() == QEvent::MouseMove && m_resizeTarget == handle) {
        const auto *mouse = static_cast<QMouseEvent *>(event);
        const bool velocity = handle == m_velocityHandle;
        const int automationHeight = effectiveAutomationBodyHeight();
        const int otherBody =
            velocity ? (m_automationToggle->isChecked() ? automationHeight : 0)
                     : (m_velocityToggle->isChecked() ? velocityBodyHeight(m_lastHostHeight) : 0);
        const int visibleHandles = m_chrome.handle * (int(m_velocityToggle->isChecked()) +
                                                      int(m_automationToggle->isChecked()));
        const int maximum = std::max(m_chrome.minBody, m_lastHostHeight - m_chrome.header -
                                                           visibleHandles - otherBody);
        const int requested =
            std::clamp(m_resizeStartBodyHeight +
                           int(std::lround(m_resizeStartGlobalY - mouse->globalPosition().y())),
                       m_chrome.minBody, maximum);
        std::optional<int> &bodyHeight = velocity ? m_velocityBodyHeight : m_automationBodyHeight;
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
        emit statePublished(true);
        return true;
    }
    if (event->type() == QEvent::UngrabMouse && m_resizeTarget == handle) {
        m_resizeTarget = nullptr;
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
    const int fixedHeight = chrome + handleHeight * (int(showVelocity) + int(showAutomation));
    const int availableBodyHeight = std::max(0, height() - fixedHeight);
    const int requestedAutomationHeight = effectiveAutomationBodyHeight();

    // Preserve the existing Automation drawer's height when Velocity opens.
    const int automationHeight =
        showAutomation ? std::min(requestedAutomationHeight, availableBodyHeight) : 0;
    const int velocityHeight = showVelocity
                                   ? std::min(velocityBodyHeight(m_lastHostHeight),
                                              std::max(0, availableBodyHeight - automationHeight))
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
    setVisibleIf(m_velocity, showVelocity);
    setVisibleIf(m_velocityHandle, showVelocity);
    setVisibleIf(m_velocityToggle, true);
    setVisibleIf(m_detentToggle, showVelocity && m_velocity->isPsgContext());
    setVisibleIf(m_automation, showAutomation);
    setVisibleIf(m_automationHandle, showAutomation);
    setVisibleIf(m_automationBar, true);

    int y = 0;
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
    const int toggleGroupWidth = 2 * buttonSize + buttonInset;
    const int pianoKeysWidth =
        std::min(m_velocity->plotOrigin(), std::max(0, width - velocityLeft));
    const int automationButtonX = std::clamp(velocityLeft + (pianoKeysWidth - toggleGroupWidth) / 2,
                                             0, std::max(0, width - toggleGroupWidth));
    const int velocityButtonX = automationButtonX + buttonSize + buttonInset;
    setGeometryIf(m_automationBar, QRect(0, y, width, chrome));
    const QSize toggleIconSize(iconSize, iconSize);
    if (m_automationToggle->iconSize() != toggleIconSize)
        m_automationToggle->setIconSize(toggleIconSize);
    setGeometryIf(m_automationToggle,
                  QRect(automationButtonX, y + buttonInset, buttonSize, buttonSize));
    if (m_velocityToggle->iconSize() != toggleIconSize)
        m_velocityToggle->setIconSize(toggleIconSize);
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
