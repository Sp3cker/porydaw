#include "ui/transportbar.h"

#include <QAction>
#include <QComboBox>
#include <QDial>
#include <QEvent>
#include <QKeyEvent>
#include <QLabel>
#include <QLineEdit>
#include <QLinearGradient>
#include <QMouseEvent>
#include <QPainter>
#include <QPen>
#include <QSignalBlocker>
#include <QSizePolicy>
#include <QSpinBox>
#include <QStyle>
#include <QStyleOptionSlider>
#include <QToolButton>
#include <QtMath>
#include <array>

#include "core/songdocument.h"
#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/theme/themeruntime.h"

namespace {
constexpr int kDefaultOutputVolume = 100;
constexpr int kDialSweepDegrees = 300;
constexpr qreal kMinimumDegrees = 240.0;
constexpr qreal kNormalStepsPerPixel = 0.5;
constexpr qreal kFineStepsPerPixel = 0.2;

class OutputVolumeDial final : public QDial
{
  public:
    explicit OutputVolumeDial(QWidget *parent) : QDial(parent) {}

  protected:
    void mousePressEvent(QMouseEvent *event) override
    {
        if (event->button() != Qt::LeftButton) {
            QDial::mousePressEvent(event);
            return;
        }
        m_dragging = true;
        m_lastGlobalY = event->globalPosition().y();
        m_stepAccumulator = 0.0;
        setFocus(Qt::MouseFocusReason);
        setSliderDown(true);
        event->accept();
    }

    void mouseMoveEvent(QMouseEvent *event) override
    {
        if (!m_dragging) {
            QDial::mouseMoveEvent(event);
            return;
        }
        if (!(event->buttons() & Qt::LeftButton)) {
            finishDrag();
            event->accept();
            return;
        }
        const qreal currentY = event->globalPosition().y();
        const qreal rate =
            event->modifiers() & Qt::ShiftModifier ? kFineStepsPerPixel : kNormalStepsPerPixel;
        applyValueDelta((currentY - m_lastGlobalY) * rate);
        m_lastGlobalY = currentY;
        event->accept();
    }

    void mouseReleaseEvent(QMouseEvent *event) override
    {
        if (event->button() == Qt::LeftButton && m_dragging) {
            finishDrag();
            event->accept();
            return;
        }
        QDial::mouseReleaseEvent(event);
    }

    void paintEvent(QPaintEvent *) override
    {
        const int tickInset = layout::space(layout::Space::One);
        const QRect tickRect = rect().adjusted(tickInset, tickInset, -tickInset, -tickInset);
        QStyleOptionSlider option;
        initStyleOption(&option);

        QPainter painter(this);
        painter.setRenderHint(QPainter::Antialiasing);
        const auto center = QPointF(tickRect.center()) + QPointF(0.5, 0.5);
        const qreal horizontalRadius = std::min(center.x(), qreal(width() - 1) - center.x());
        const qreal verticalRadius = std::min(center.y(), qreal(height() - 1) - center.y());
        const qreal outerRadius =
            std::min(horizontalRadius, verticalRadius) - layout::singlePixel();

        const int pixel = layout::singlePixel();
        const qreal faceRadius = outerRadius - layout::space(layout::Space::One) - qreal(pixel);
        const QColor chrome = themes::color(themes::Role::toolbar_background);
        const QColor ink = themes::color(themes::Role::toolbar_text);
        const QColor outline = themes::color(themes::Role::toolbar_outline);
        const QColor button = themes::color(themes::Role::button_background);
        const bool darkChrome = qGray(chrome.rgb()) < qGray(ink.rgb());
        const auto mix = [](const QColor &from, const QColor &to, qreal amount) {
            return QColor::fromRgbF(from.redF() + (to.redF() - from.redF()) * amount,
                                    from.greenF() + (to.greenF() - from.greenF()) * amount,
                                    from.blueF() + (to.blueF() - from.blueF()) * amount);
        };
        QColor faceHi = darkChrome ? mix(chrome, ink, 0.75) : mix(button, ink, 0.08);
        QColor faceMid = darkChrome ? mix(chrome, ink, 0.62) : button;
        QColor faceLo = darkChrome ? mix(chrome, ink, 0.45) : mix(button, outline, 0.40);
        if (!isEnabled()) {
            faceHi = mix(faceHi, chrome, 0.55);
            faceMid = mix(faceMid, chrome, 0.55);
            faceLo = mix(faceLo, chrome, 0.55);
        }
        const bool pressed = isSliderDown();
        const QPointF faceCenter = center;
        if (pressed) {
            faceHi = mix(faceHi, faceMid, 0.45);
            faceLo = faceLo.darker(115);
        }

        if (isEnabled()) {
            QColor shadowColor = chrome.darker(200);
            shadowColor.setAlphaF((darkChrome ? 80.0 : 70.0) / 255.0 * (pressed ? 0.65 : 1.0));
            painter.setPen(Qt::NoPen);
            painter.setBrush(shadowColor);
            painter.drawEllipse(center + QPointF(0.0, faceRadius * 0.78), faceRadius * 0.72,
                                faceRadius * 0.22);
        }

        QLinearGradient faceGradient(faceCenter.x(), faceCenter.y() - faceRadius, faceCenter.x(),
                                     faceCenter.y() + faceRadius);
        faceGradient.setColorAt(0.0, faceHi);
        faceGradient.setColorAt(0.42, faceMid);
        faceGradient.setColorAt(1.0, faceLo);
        painter.setPen(Qt::NoPen);
        painter.setBrush(faceGradient);
        painter.drawEllipse(faceCenter, faceRadius, faceRadius);

        QLinearGradient bevelGradient(faceCenter.x(), faceCenter.y() - faceRadius, faceCenter.x(),
                                      faceCenter.y() + faceRadius);
        QColor bevelHi = ink;
        bevelHi.setAlpha(darkChrome ? 140 : 170);
        bevelGradient.setColorAt(0.0, bevelHi);
        bevelGradient.setColorAt(0.45, outline);
        bevelGradient.setColorAt(1.0, faceLo.darker(120));
        painter.setPen(QPen(QBrush(bevelGradient), pixel));
        painter.setBrush(Qt::NoBrush);
        const qreal bevelRadius = faceRadius - qreal(pixel) * 0.5;
        painter.drawEllipse(faceCenter, bevelRadius, bevelRadius);

        const qreal valueFraction =
            qreal(value() - minimum()) / qreal(std::max(1, maximum() - minimum()));
        const qreal indicatorDegrees = kMinimumDegrees - valueFraction * qreal(kDialSweepDegrees);
        const qreal indicatorRadians = qDegreesToRadians(indicatorDegrees);
        const QPointF indicatorDirection(qCos(indicatorRadians), -qSin(indicatorRadians));
        const QPointF indicatorCenter = faceCenter + indicatorDirection * (faceRadius * 0.50);
        const qreal indicatorRadius = std::max(qreal(pixel) * 1.5, faceRadius * 0.18);
        QColor indicatorFill = mix(faceMid, ink, 0.30);
        if (!isEnabled())
            indicatorFill = mix(indicatorFill, outline, 0.55);
        painter.setPen(QPen(faceLo.darker(130), pixel));
        painter.setBrush(indicatorFill);
        painter.drawEllipse(indicatorCenter, indicatorRadius, indicatorRadius);
        painter.setPen(Qt::NoPen);
        painter.setBrush(chrome.darker(125));
        painter.drawEllipse(indicatorCenter, indicatorRadius * 0.42, indicatorRadius * 0.42);

        QPen tickPen(themes::color(themes::Role::toolbar_outline), layout::singlePixel());
        tickPen.setCapStyle(Qt::RoundCap);
        painter.setPen(tickPen);
        painter.setBrush(Qt::NoBrush);
        constexpr int kTickIntervalCount = 10;
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
        for (int tick = 0; tick <= kTickIntervalCount; ++tick) {
            const bool endpoint = tick == 0 || tick == kTickIntervalCount;
            const qreal tickLength =
                endpoint ? layout::space(layout::Space::One) : layout::space(layout::Space::Half);
            const QPointF &direction = tickDirections[tick];
            painter.drawLine(center + direction * (outerRadius - tickLength),
                             center + direction * outerRadius);
        }
    }

  private:
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
        m_dragging = false;
        m_stepAccumulator = 0.0;
        setSliderDown(false);
    }

    bool m_dragging = false;
    qreal m_lastGlobalY = 0.0;
    qreal m_stepAccumulator = 0.0;
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
    m_resonanceAction = new QAction(tr("&Suppress Resonances"), this);
    m_resonanceAction->setCheckable(true);
    m_resonanceAction->setIconVisibleInMenu(false);
    m_resonanceAction->setToolTip(tr("Suppress harsh resonances"));
    connect(m_resonanceAction, &QAction::toggled, this, &TransportBar::resonanceSuppressionChanged);
    addAction(m_resonanceAction);

    m_timeLabel = new QLabel(QStringLiteral("--:--.- / --:--.-"), this);
    m_timeLabel->setObjectName(QStringLiteral("transportTimeLabel"));
    m_timeLabel->setContentsMargins(::layout::space(::layout::Space::Three), 0,
                                    ::layout::space(::layout::Space::Three), 0);
    m_timeLabel->setFixedWidth(m_timeLabel->sizeHint().width());
    addWidget(m_timeLabel);

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
    m_resonanceAction->setIcon(tintedStandardIcon(*this, QStyle::SP_MediaVolume, size));

    m_highlightButton->setIcon(
        tintedIcon(*this, QIcon(QStringLiteral(":/icons/flat-music.svg")), size));
}
