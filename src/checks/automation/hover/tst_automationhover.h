#pragma once

#include <memory>

#include <QObject>
#include <QStringList>

namespace automation_hover {
class Fixture;
}

class AutomationHoverTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(AutomationHoverTest)

  public:
    AutomationHoverTest();
    ~AutomationHoverTest() override;

  private slots:
    void init();
    void cleanup();
    void directInputHostRouting();
    void focusLostKeepsGrab();
    void deactivationClears();
    void hoverRevivesAfterCancellation();
    void idleCancellationsDoNotMutate();
    void guideGhostTextAndRing_data();
    void guideGhostTextAndRing();
    void repeatHoverDoesNotChurn();
    void leaveClearsRetainedHover();
    void tempoAndCcTopologyMatch();
    void rowRebuildStaleReleaseDoesNotMutate();

  private:
    std::unique_ptr<automation_hover::Fixture> m_fixture;
};

int runAutomationHoverCheck(const QStringList &qtArguments);
