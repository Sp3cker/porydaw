#include "dragspinbox.h"

#include <QLineEdit>
#include <QMouseEvent>

namespace {
constexpr int kDragThreshold = 3;
constexpr qreal kNormalStepsPerPixel = 0.5;
constexpr qreal kShiftStepsPerPixel = 0.2;
} // namespace

DragSpinBox::DragSpinBox(QWidget *parent) : QSpinBox(parent)
{
    lineEdit()->installEventFilter(this);
    lineEdit()->setCursor(Qt::SizeVerCursor);
}

bool DragSpinBox::eventFilter(QObject *watched, QEvent *event)
{
    if (watched != lineEdit())
        return QSpinBox::eventFilter(watched, event);
    if (event->type() == QEvent::MouseButtonPress) {
        auto *mouse = static_cast<QMouseEvent *>(event);
        if (mouse->button() == Qt::LeftButton) {
            m_pressed = true;
            m_dragging = false;
            m_pressY = mouse->globalPosition().y();
            m_lastY = m_pressY;
            m_stepAccumulator = 0;
            event->accept();
            return true;
        }
    } else if (event->type() == QEvent::MouseMove && m_pressed) {
        auto *mouse = static_cast<QMouseEvent *>(event);
        if (!(mouse->buttons() & Qt::LeftButton)) {
            m_pressed = false;
            m_dragging = false;
            event->accept();
            return true;
        }
        const qreal currentY = mouse->globalPosition().y();
        const qreal distance = m_pressY - currentY;
        if (!m_dragging) {
            if (distance > -kDragThreshold && distance < kDragThreshold) {
                event->accept();
                return true;
            }
            m_dragging = true;
            m_lastY = m_pressY - (distance > 0 ? kDragThreshold : -kDragThreshold);
        }
        const qreal rate =
            mouse->modifiers() & Qt::ShiftModifier ? kShiftStepsPerPixel : kNormalStepsPerPixel;
        m_stepAccumulator += (m_lastY - currentY) * rate;
        m_lastY = currentY;
        const int steps = static_cast<int>(m_stepAccumulator);
        if (steps != 0) {
            m_stepAccumulator -= steps;
            setValue(value() + steps * singleStep());
        }
        event->accept();
        return true;
    } else if (event->type() == QEvent::MouseButtonRelease) {
        auto *mouse = static_cast<QMouseEvent *>(event);
        if (m_pressed && mouse->button() == Qt::LeftButton) {
            const bool dragged = m_dragging;
            m_pressed = false;
            m_dragging = false;
            if (!dragged) {
                lineEdit()->setFocus(Qt::MouseFocusReason);
                lineEdit()->selectAll();
            }
            event->accept();
            return true;
        }
    }
    return QSpinBox::eventFilter(watched, event);
}
