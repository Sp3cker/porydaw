#include "ui/outputvolumedial.h"

#include <QDial>
#include <QLinearGradient>
#include <QMouseEvent>
#include <QPainter>
#include <QPen>
#include <QStyleOptionSlider>
#include <QtMath>
#include <algorithm>
#include <array>

#include "ui/layout.h"
#include "ui/theme/themeruntime.h"

namespace {
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
} // namespace

QDial *createOutputVolumeDial(QWidget *parent)
{
    return new OutputVolumeDial(parent);
}
