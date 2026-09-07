#pragma once

#include <memory>

#include <QObject>
#include <QString>
#include <QStringList>

class MainWindow;

namespace checks {

class PolyphonyGateTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(PolyphonyGateTest)

  public:
    explicit PolyphonyGateTest(QString screenshotPath);
    ~PolyphonyGateTest() override;

  private slots:
    void cleanup();

    void overflowCountersAndRing();
    void liveSentinelTick();
    void normalPlaybackKeepsShadowPoolOff();
    void invertSilencesUntilOverflowAndClearsShadow();
    void auditionRemainsAudibleWithInvert();
    void channelModeLeavesCompiledGateIntact_data();
    void channelModeLeavesCompiledGateIntact();

    void logOrderAndFormatting();
    void positionedLogRowJumpsAndLiveDoesNot();
    void resetRebasesLog();
    void logCapIs500();
    void responsiveLayout();
    void rasterSmoke();

    void hiddenDockCheckboxIsInert();
    void visibleCheckedDockInverts();
    void closingDockSuspendsAndReopenResumes();
    void uncheckingDockTurnsInvertOff();

  private:
    bool prepareGateWindow();

    QString m_screenshotPath;
    std::unique_ptr<MainWindow> m_window;
};

} // namespace checks

int runPolyCheck(const QString &screenshotPath, const QStringList &qtArguments);
