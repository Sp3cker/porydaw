#pragma once

#include <QObject>

class ScaleCheckTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(ScaleCheckTest)

  public:
    ScaleCheckTest() = default;

  private slots:
    void table_data();
    void table();
    void rootsAndDefaults();
    void membershipAndNeighbors();
    void diatonicDestinations_data();
    void diatonicDestinations();
};
