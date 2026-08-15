#pragma once

#include <QSpinBox>

class DragSpinBox final : public QSpinBox
{
    Q_OBJECT
  public:
    explicit DragSpinBox(QWidget *parent = nullptr);

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    bool m_pressed = false;
    bool m_dragging = false;
    qreal m_pressY = 0;
    qreal m_lastY = 0;
    qreal m_stepAccumulator = 0;
};
