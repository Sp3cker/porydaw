#pragma once

#include <QColor>
#include <QWidget>

#include "audio/trackactivitylevel.h"

class TrackActivityMeter final : public QWidget
{
  public:
    struct State {
        TrackActivityIntensity intensity{0.0f, 0.0f};
        bool playing = true;
        float maximumIntensity = 1.0f;
    };

    explicit TrackActivityMeter(QColor identityColor, QWidget *parent);

    void setState(State state);

  protected:
    void paintEvent(QPaintEvent *event) override;

  private:
    QColor m_identityColor;
    State m_state;
};
