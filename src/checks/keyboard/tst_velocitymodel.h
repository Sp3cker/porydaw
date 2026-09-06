#pragma once

#include <QObject>
#include <QStringList>

class VelocityModelTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(VelocityModelTest)

  public:
    VelocityModelTest() = default;

  private slots:
    void gestureLifecycle();
    void gestureAtomicity();
    void gestureCompletionAndDeltaFromOriginals();
    void gestureClampedDeltaAndCancellation();

    void resolvesVoiceKinds();
    void levelsCanonicalizeAndMove();
    void continuousAxisGeometryAndDensity();
    void intrinsicAxisRowsAndRoundTrip();
    void markerCapAndAccessibility();
};

int runVelocityModelCheck(const QStringList &qtArguments);
