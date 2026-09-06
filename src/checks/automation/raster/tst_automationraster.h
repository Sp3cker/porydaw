#pragma once

#include <memory>

#include <QObject>
#include <QString>

#include "checks/automation/raster/rasterfixture.h"

namespace checks {
class ProjectFixture;
}

class AutomationRasterTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(AutomationRasterTest)

  public:
    AutomationRasterTest(QString project, QString song);

  private slots:
    void init();
    void cleanup();

    void resizeBoundaryShowsSplitCursorWithoutPreview();
    void curvesNodesAndSelectedRingsRender_data();
    void curvesNodesAndSelectedRingsRender();
    void halfOpenTrackSelectionRendersOnlyIncludedNodes_data();
    void halfOpenTrackSelectionRendersOnlyIncludedNodes();

    void hoverGhostRingAndLeaveClear_data();
    void hoverGhostRingAndLeaveClear();

    void voicePressWithoutMoveHasNoPreview();
    void voiceDragPreviewsWithoutCommitUntilRelease();

  private:
    bool configurePainting();
    bool configureInteraction();
    AutomationRasterFixture &fixture() noexcept;
    const AutomationRasterFixture &fixture() const noexcept;

    QString m_projectPath;
    QString m_song;
    std::unique_ptr<checks::ProjectFixture> m_project;
    std::unique_ptr<AutomationRasterFixture> m_fixture;
};
