#include "ui/transportbar.h"

#include <QAction>
#include <QComboBox>
#include <QDial>
#include <QEvent>
#include <QKeyEvent>
#include <QLabel>
#include <QLineEdit>
#include <QMouseEvent>
#include <QPainter>
#include <QPen>
#include <QSignalBlocker>
#include <QSizePolicy>
#include <QSpinBox>
#include <QStyle>
#include <QStyleOptionSlider>
#include <QStylePainter>
#include <QToolButton>
#include <QtMath>
#include <array>

#include "core/songdocument.h"
#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/theme/themeruntime.h"

namespace {
constexpr int kDefaultOutputVolume = 68;

class OutputVolumeDial final : public QDial
{
  public:
    explicit OutputVolumeDial(QWidget *parent)
        : QDial(parent)
        , m_tickPen(themes::color(themes::Role::toolbar_outline), layout::singlePixel())
    {
        m_tickPen.setCapStyle(Qt::RoundCap);
    }

  protected:
    void mousePressEvent(QMouseEvent *event) override
    {
        if (event->button() != Qt::LeftButton) {
            QDial::mousePressEvent(event);
            return;
        }
        m_dragMode = isNearArc(event->position()) ? DragMode::Rotary : DragMode::LinearPending;
        m_pressPosition = event->position();
        m_lastGlobalY = event->globalPosition().y();
        m_lastAngle = angleAt(event->position());
        m_dialRadius = dialRadius();
        m_stepAccumulator = 0.0;
        setFocus(Qt::MouseFocusReason);
        setSliderDown(true);
        event->accept();
    }

    void mouseMoveEvent(QMouseEvent *event) override
    {
        if (m_dragMode == DragMode::None) {
            QDial::mouseMoveEvent(event);
            return;
        }
        if (!(event->buttons() & Qt::LeftButton)) {
            finishDrag();
            event->accept();
            return;
        }
        if (m_dragMode == DragMode::Rotary) {
            const QPointF offset = event->position() - rect().center();
            if (QPointF::dotProduct(offset, offset) > m_dialRadius * m_dialRadius) {
                m_dragMode = DragMode::Linear;
                m_lastGlobalY = event->globalPosition().y();
                event->accept();
                return;
            }
            const qreal angle = angleAt(event->position());
            qreal delta = angle - m_lastAngle;
            if (delta > 180.0)
                delta -= 360.0;
            else if (delta < -180.0)
                delta += 360.0;
            m_lastAngle = angle;
            const qreal valuePerDegree = qreal(maximum() - minimum()) / qreal(kDialSweepDegrees);
            const qreal sensitivity =
                event->modifiers() & Qt::ShiftModifier ? kFineSensitivity : 1.0;
            applyValueDelta(delta * valuePerDegree * sensitivity);
            event->accept();
            return;
        }
        const qreal currentY = event->globalPosition().y();
        if (m_dragMode == DragMode::LinearPending) {
            const QPointF distance = event->position() - m_pressPosition;
            if (qAbs(distance.x()) < kDragThreshold && qAbs(distance.y()) < kDragThreshold) {
                event->accept();
                return;
            }
            m_dragMode = DragMode::Linear;
            if (qAbs(distance.y()) >= kDragThreshold)
                m_lastGlobalY += distance.y() > 0 ? kDragThreshold : -kDragThreshold;
            else
                m_lastGlobalY = currentY;
        }
        const qreal rate =
            event->modifiers() & Qt::ShiftModifier ? kFineStepsPerPixel : kNormalStepsPerPixel;
        applyValueDelta((m_lastGlobalY - currentY) * rate);
        m_lastGlobalY = currentY;
        event->accept();
    }

    void mouseReleaseEvent(QMouseEvent *event) override
    {
        if (event->button() == Qt::LeftButton && m_dragMode != DragMode::None) {
            finishDrag();
            event->accept();
            return;
        }
        QDial::mouseReleaseEvent(event);
    }

    void paintEvent(QPaintEvent *) override
    {
        const int tickInset = layout::space(layout::Space::One);
        QStyleOptionSlider option;
        initStyleOption(&option);
        option.rect = rect().adjusted(tickInset, tickInset, -tickInset, -tickInset);

        QStylePainter painter(this);
        painter.drawComplexControl(QStyle::CC_Dial, option);
        painter.setRenderHint(QPainter::Antialiasing);
        const auto &tickColor = themes::color(themes::Role::toolbar_outline);
        const int tickWidth = layout::singlePixel();
        if (m_tickPen.color() != tickColor)
            m_tickPen.setColor(tickColor);
        if (m_tickPen.width() != tickWidth)
            m_tickPen.setWidth(tickWidth);
        painter.setPen(m_tickPen);

        constexpr int kTickIntervalCount = 10;
        constexpr qreal kMinimumDegrees = 240.0;
        const int dialCenterX = option.rect.left() + option.rect.width() / 2;
        static const auto tickDirections = [] {
            auto directions = std::array<QPointF, kTickIntervalCount + 1>{};
            for (int tick = 0; tick <= kTickIntervalCount; ++tick) {
                const qreal degrees = kMinimumDegrees - qreal(tick) * qreal(kDialSweepDegrees) /
                                                            qreal(kTickIntervalCount);
                const qreal radians = qDegreesToRadians(degrees);
                directions[tick] = QPointF(qCos(radians), -qSin(radians));
            }
            return directions;
        }();
        const int dialCenterY = option.rect.top() + option.rect.height() / 2;
        const QPointF center(dialCenterX + 0.5, dialCenterY + 0.5);
        const qreal horizontalRadius = std::min(center.x(), qreal(width() - 1) - center.x());
        const qreal verticalRadius = std::min(center.y(), qreal(height() - 1) - center.y());
        const qreal outerRadius =
            std::min(horizontalRadius, verticalRadius) - layout::singlePixel();
        for (int tick = 0; tick <= kTickIntervalCount; ++tick) {
            const bool endpoint = tick == 0 || tick == kTickIntervalCount;
            const QPointF &direction = tickDirections[tick];
            const qreal tickLength =
                endpoint ? layout::space(layout::Space::One) : layout::space(layout::Space::Half);
            const qreal innerRadius = outerRadius - tickLength;
            painter.drawLine(center + direction * innerRadius, center + direction * outerRadius);
        }
    }

  private:
    enum class DragMode {
        None,
        Rotary,
        LinearPending,
        Linear,
    };

    static constexpr int kDialSweepDegrees = 300;
    static constexpr qreal kDragThreshold = 3.0;
    static constexpr qreal kNormalStepsPerPixel = 0.5;
    static constexpr qreal kFineStepsPerPixel = 0.2;
    static constexpr qreal kFineSensitivity = kFineStepsPerPixel / kNormalStepsPerPixel;
    static constexpr qreal kArcInnerRadiusFraction = 0.6;

    void applyValueDelta(qreal delta)
    {
        m_stepAccumulator += delta;
        const int steps = int(m_stepAccumulator);
        if (steps == 0)
            return;
        m_stepAccumulator -= steps;
        setValue(value() + steps);
    }

    void finishDrag()
    {
        m_dragMode = DragMode::None;
        m_stepAccumulator = 0.0;
        setSliderDown(false);
    }

    qreal angleAt(const QPointF &position) const
    {
        const QPointF offset = position - rect().center();
        return qRadiansToDegrees(qAtan2(offset.x(), -offset.y()));
    }

    qreal dialRadius() const
    {
        return qreal(std::min(width(), height())) / 2.0 - layout::singlePixel();
    }

    bool isNearArc(const QPointF &position) const
    {
        const QPointF offset = position - rect().center();
        const qreal radius = dialRadius();
        const qreal innerRadius = radius * kArcInnerRadiusFraction;
        const qreal distanceSquared = QPointF::dotProduct(offset, offset);
        return distanceSquared >= innerRadius * innerRadius && distanceSquared <= radius * radius;
    }

    DragMode m_dragMode = DragMode::None;
    QPointF m_pressPosition;
    qreal m_lastGlobalY = 0.0;
    qreal m_lastAngle = 0.0;
    qreal m_dialRadius = 0.0;
    qreal m_stepAccumulator = 0.0;
    QPen m_tickPen;
};

QIcon tintedIcon(QWidget &widget, const QIcon &source, const QSize &size)
{
    const auto tinted = [&](themes::Role role) {
        auto pixmap = source.pixmap(size, widget.devicePixelRatioF());
        QPainter painter(&pixmap);
        painter.setCompositionMode(QPainter::CompositionMode_SourceIn);
        painter.fillRect(pixmap.rect(), themes::color(role));
        painter.end();
        return pixmap;
    };
    QIcon result(tinted(themes::Role::transport_text));
    result.addPixmap(tinted(themes::Role::button_hover_text), QIcon::Active, QIcon::Off);
    result.addPixmap(tinted(themes::Role::button_pressed_text), QIcon::Normal, QIcon::On);
    result.addPixmap(tinted(themes::Role::button_pressed_text), QIcon::Active, QIcon::On);
    result.addPixmap(tinted(themes::Role::disabled_text), QIcon::Disabled, QIcon::Off);
    result.addPixmap(tinted(themes::Role::disabled_text), QIcon::Disabled, QIcon::On);
    return result;
}

QIcon tintedStandardIcon(QWidget &widget, QStyle::StandardPixmap icon, const QSize &size)
{
    return tintedIcon(widget, widget.style()->standardIcon(icon), size);
}
} // namespace

TransportBar::TransportBar(QWidget *parent) : QToolBar(tr("Transport"), parent)
{
    auto &keys = keymap::Registry::instance();
    setObjectName(QStringLiteral("transportToolbar"));
    setMovable(false);
    setToolButtonStyle(Qt::ToolButtonIconOnly);
    setIconSize(iconSize());

    m_goToStartAction = new QAction(tr("Go to Start"), this);
    keys.attach(QStringLiteral("transport.go_to_start"), m_goToStartAction);
    connect(m_goToStartAction, &QAction::triggered, this, &TransportBar::goToStartRequested);
    addAction(m_goToStartAction);

    m_playAction = new QAction(tr("Play"), this);
    keys.attach(QStringLiteral("transport.play"), m_playAction);
    connect(m_playAction, &QAction::triggered, this, &TransportBar::playRequested);
    addAction(m_playAction);

    // Space toggles play/pause at window scope; this action is intentionally
    // not shown in the toolbar because Play and Pause have separate buttons.
    m_playPauseAction = new QAction(tr("Play/Pause"), this);
    keys.attach(QStringLiteral("transport.play_pause"), m_playPauseAction);
    connect(m_playPauseAction, &QAction::triggered, this, &TransportBar::playPauseRequested);

    m_pauseAction = new QAction(tr("Pause"), this);
    keys.attach(QStringLiteral("transport.pause"), m_pauseAction);
    connect(m_pauseAction, &QAction::triggered, this, &TransportBar::pauseRequested);
    addAction(m_pauseAction);

    m_stopAction = new QAction(tr("Stop"), this);
    keys.attach(QStringLiteral("transport.stop"), m_stopAction);
    connect(m_stopAction, &QAction::triggered, this, &TransportBar::stopRequested);
    addAction(m_stopAction);

    m_loopAction = new QAction(tr("Loop"), this);
    keys.attach(QStringLiteral("transport.loop"), m_loopAction);
    m_loopAction->setCheckable(true);
    m_loopAction->setChecked(true);
    connect(m_loopAction, &QAction::toggled, this, &TransportBar::loopEnabledChanged);
    addAction(m_loopAction);

    m_followPlayheadAction = new QAction(tr("&Follow Playhead"), this);
    keys.attach(QStringLiteral("transport.follow_playhead"), m_followPlayheadAction);
    m_followPlayheadAction->setCheckable(true);
    m_followPlayheadAction->setIconVisibleInMenu(false);
    m_followPlayheadAction->setToolTip(
        tr("Scroll the view to keep the playhead visible during playback"));
    connect(m_followPlayheadAction, &QAction::toggled, this, &TransportBar::followPlayheadChanged);
    addAction(m_followPlayheadAction);

    m_timeLabel = new QLabel(QStringLiteral("--:--.- / --:--.-"), this);
    m_timeLabel->setObjectName(QStringLiteral("transportTimeLabel"));
    m_timeLabel->setContentsMargins(::layout::space(::layout::Space::Three), 0,
                                    ::layout::space(::layout::Space::Three), 0);
    addWidget(m_timeLabel);
    m_songLabel = new QLabel(this);
    addWidget(m_songLabel);

    m_rootCombo = new QComboBox(this);
    m_rootCombo->setObjectName(QStringLiteral("transportScaleRoot"));
    for (int root = 0; root < porydaw_scale::cRootCount; root++)
        m_rootCombo->addItem(QString::fromLatin1(porydaw_scale::rootDisplayName(root)), root);
    m_rootCombo->setCurrentIndex(0);
    m_rootCombo->setToolTip(tr("Scale root note"));
    m_rootCombo->setFocusPolicy(Qt::NoFocus);
    connect(m_rootCombo, &QComboBox::currentIndexChanged, this, [this](int index) {
        if (index >= 0)
            emit scaleRootChanged(m_rootCombo->itemData(index).toInt());
    });
    addWidget(m_rootCombo);

    m_scaleCombo = new QComboBox(this);
    m_scaleCombo->setObjectName(QStringLiteral("transportScaleType"));
    const auto *scaleOrder = porydaw_scale::displayOrder();
    for (int i = 0; i < porydaw_scale::cScaleCount; i++) {
        const auto id = scaleOrder[i];
        m_scaleCombo->addItem(QString::fromLatin1(porydaw_scale::scaleDisplayName(id)),
                              static_cast<int>(id));
    }
    m_scaleCombo->setCurrentIndex(0);
    m_scaleCombo->setToolTip(tr("Scale type"));
    m_scaleCombo->setFocusPolicy(Qt::NoFocus);
    connect(m_scaleCombo, &QComboBox::currentIndexChanged, this, [this](int index) {
        if (index >= 0) {
            emit scaleIdChanged(
                static_cast<porydaw_scale::ScaleId>(m_scaleCombo->itemData(index).toInt()));
        }
    });
    addWidget(m_scaleCombo);

    m_highlightButton = new QToolButton(this);
    m_highlightButton->setObjectName(QStringLiteral("transportScaleHighlight"));
    m_highlightButton->setCheckable(true);
    m_highlightButton->setAutoRaise(true);
    m_highlightButton->setFocusPolicy(Qt::NoFocus);
    m_highlightButton->setToolButtonStyle(Qt::ToolButtonIconOnly);
    m_highlightButton->setToolTip(tr("Highlight scale pitches"));
    m_highlightButton->setAccessibleName(tr("Highlight"));
    connect(m_highlightButton, &QToolButton::clicked, this, &TransportBar::scaleHighlightChanged);
    addWidget(m_highlightButton);

    m_foldButton = new QToolButton(this);
    m_foldButton->setObjectName(QStringLiteral("transportScaleFold"));
    m_foldButton->setText(tr("Fold"));
    m_foldButton->setCheckable(true);
    m_foldButton->setAutoRaise(true);
    m_foldButton->setFocusPolicy(Qt::NoFocus);
    m_foldButton->setToolButtonStyle(Qt::ToolButtonTextOnly);
    m_foldButton->setToolTip(tr("Fold piano roll to pitches used by the selected track"));
    connect(m_foldButton, &QToolButton::clicked, this, &TransportBar::scaleFoldChanged);
    addWidget(m_foldButton);

    auto *spacer = new QWidget(this);
    spacer->setObjectName(QStringLiteral("transportVolumeSpacer"));
    spacer->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Preferred);
    addWidget(spacer);
    addSeparator();

    const auto volumeTip = tr("Master volume (mid2agb -V): scales every track "
                              "volume (VOL × master ÷ 128). Saved with the "
                              "song's settings.");
    m_masterVolCaption = new QLabel(tr("Volume"), this);
    m_masterVolCaption->setObjectName(QStringLiteral("transportMasterVolumeCaption"));
    m_masterVolCaption->setContentsMargins(::layout::space(::layout::Space::Two), 0,
                                           ::layout::space(::layout::Space::One), 0);
    m_masterVolCaption->setToolTip(volumeTip);
    m_masterVolCaption->setEnabled(false);
    addWidget(m_masterVolCaption);

    m_masterVolSpin = new QSpinBox(this);
    m_masterVolSpin->setObjectName(QStringLiteral("transportMasterVolume"));
    m_masterVolSpin->setRange(0, 127);
    m_masterVolSpin->setValue(SongCfg().masterVolume);
    m_masterVolSpin->setToolTip(volumeTip);
    m_masterVolSpin->setEnabled(false);
    m_masterVolSpin->setKeyboardTracking(false);
    m_masterVolSpin->installEventFilter(this);
    if (auto *edit = m_masterVolSpin->findChild<QLineEdit *>())
        edit->installEventFilter(this);
    connect(m_masterVolSpin, &QSpinBox::valueChanged, this, &TransportBar::masterVolumeChanged);
    addWidget(m_masterVolSpin);
    addSeparator();
    const auto outputVolumeTip =
        tr("Application output volume. Does not change the song volume or saved song settings.");
    m_outputVolumeCaption = new QLabel(tr("Output"), this);
    m_outputVolumeCaption->setObjectName(QStringLiteral("transportOutputVolumeCaption"));
    m_outputVolumeCaption->setContentsMargins(::layout::space(::layout::Space::Two), 0,
                                              ::layout::space(::layout::Space::One), 0);
    m_outputVolumeCaption->setToolTip(outputVolumeTip);
    addWidget(m_outputVolumeCaption);

    m_outputVolumeDial = new OutputVolumeDial(this);
    m_outputVolumeDial->setObjectName(QStringLiteral("transportOutputVolume"));
    m_outputVolumeDial->setRange(0, 100);
    m_outputVolumeDial->setValue(kDefaultOutputVolume);
    m_outputVolumeDial->setPageStep(10);
    const auto dialExtent = ::layout::fontPx(5.0 / 3.0) + 2 * ::layout::space(::layout::Space::One);
    m_outputVolumeDial->setFixedSize(dialExtent, dialExtent);
    m_outputVolumeDial->setToolTip(outputVolumeTip);
    m_outputVolumeDial->setAccessibleName(tr("Application output volume"));
    m_outputVolumeDial->setAccessibleDescription(outputVolumeTip);
    connect(m_outputVolumeDial, &QDial::valueChanged, this, &TransportBar::outputVolumeChanged);
    addWidget(m_outputVolumeDial);
    refreshIcons();
}

bool TransportBar::followPlayhead() const
{
    return m_followPlayheadAction->isChecked();
}

void TransportBar::setPlaybackState(PlaybackState state)
{
    const bool loaded = state != PlaybackState::Unavailable;
    m_goToStartAction->setEnabled(loaded);
    m_playAction->setEnabled(loaded && state != PlaybackState::Playing);
    m_playPauseAction->setEnabled(loaded);
    m_pauseAction->setEnabled(state == PlaybackState::Playing);
    m_stopAction->setEnabled(loaded && state != PlaybackState::Stopped);
    m_loopAction->setEnabled(loaded);
}

void TransportBar::setSessionAvailable(bool available)
{
    m_rootCombo->setEnabled(available);
    m_scaleCombo->setEnabled(available);
    m_highlightButton->setEnabled(available);
    m_foldButton->setEnabled(available);
}

void TransportBar::setFollowPlayhead(bool enabled)
{
    m_followPlayheadAction->setChecked(enabled);
}

void TransportBar::setTimeText(const QString &text)
{
    if (m_lastTimeText == text)
        return;
    m_lastTimeText = text;
    m_timeLabel->setText(text);
}

void TransportBar::setSongName(const QString &name)
{
    m_songLabel->setText(name.isEmpty() ? QString() : QStringLiteral("  %1").arg(name));
}

void TransportBar::setMasterVolume(int value, bool enabled)
{
    m_masterVolCaption->setEnabled(enabled);
    m_masterVolSpin->setEnabled(enabled);
    const QSignalBlocker blocker(m_masterVolSpin);
    m_masterVolSpin->setValue(value);
}

void TransportBar::setOutputVolume(int value)
{
    const QSignalBlocker blocker(m_outputVolumeDial);
    m_outputVolumeDial->setValue(value);
}

void TransportBar::setScaleState(int root, porydaw_scale::ScaleId scale, bool highlight, bool fold)
{
    const QSignalBlocker rootBlocker(m_rootCombo);
    const QSignalBlocker scaleBlocker(m_scaleCombo);
    const QSignalBlocker highlightBlocker(m_highlightButton);
    const QSignalBlocker foldBlocker(m_foldButton);
    m_rootCombo->setCurrentIndex(m_rootCombo->findData(root));
    m_scaleCombo->setCurrentIndex(m_scaleCombo->findData(static_cast<int>(scale)));
    m_highlightButton->setChecked(highlight);
    m_foldButton->setChecked(fold);
}

void TransportBar::changeEvent(QEvent *event)
{
    QToolBar::changeEvent(event);
    if (event->type() == QEvent::ApplicationPaletteChange || event->type() == QEvent::StyleChange)
        refreshIcons();
}

bool TransportBar::eventFilter(QObject *watched, QEvent *event)
{
    if ((watched == m_masterVolSpin || watched->parent() == m_masterVolSpin) &&
        event->type() == QEvent::ShortcutOverride &&
        static_cast<QKeyEvent *>(event)->key() == Qt::Key_Space) {
        event->ignore();
        return true;
    }
    return QToolBar::eventFilter(watched, event);
}

void TransportBar::refreshIcons()
{
    const auto size = iconSize();
    m_goToStartAction->setIcon(tintedStandardIcon(*this, QStyle::SP_MediaSkipBackward, size));
    m_playAction->setIcon(tintedStandardIcon(*this, QStyle::SP_MediaPlay, size));
    m_pauseAction->setIcon(tintedStandardIcon(*this, QStyle::SP_MediaPause, size));
    m_stopAction->setIcon(tintedStandardIcon(*this, QStyle::SP_MediaStop, size));
    m_loopAction->setIcon(tintedStandardIcon(*this, QStyle::SP_BrowserReload, size));
    m_followPlayheadAction->setIcon(tintedStandardIcon(*this, QStyle::SP_MediaSeekForward, size));
    m_highlightButton->setIcon(
        tintedIcon(*this, QIcon(QStringLiteral(":/icons/flat-music.svg")), size));
}
