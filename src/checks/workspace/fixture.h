#pragma once

#include <QString>

#include <memory>
#include <optional>
#include <utility>

#include "checks/support/asyncwait.h"
#include "checks/support/songfixture.h"
#include "project/projectidentity.h"
#include "ui/workspaceui.h"

class SongTab;

namespace workspace_test {

class ProjectCopy final
{
  public:
    explicit ProjectCopy(QString source) : m_source(std::move(source)) {}

    bool reset(QString &error)
    {
        m_copy.reset();
        m_copy = checks::ProjectFixture::copyOf(m_source, error);
        return m_copy != nullptr;
    }

    const QString &root() const noexcept { return m_copy->root(); }

  private:
    QString m_source;
    std::unique_ptr<checks::ProjectFixture> m_copy;
};

inline std::optional<SongName> songName(const QString &label)
{
    return SongName::create(label);
}

inline bool waitForProject(WorkspaceUi &workspace, int timeoutMs = 30000)
{
    return checks::async_wait::waitUntil(
               [&workspace] { return workspace.projectState().state != ProjectOpenState::Failed; },
               [&workspace] { return workspace.projectState().state == ProjectOpenState::Ready; },
               timeoutMs, 1) == checks::async_wait::Result::Ready;
}

SongTab *waitReady(WorkspaceUi &workspace, const SongName &name, int timeoutMs = 15000);
SongTab *openReady(WorkspaceUi &workspace, const SongName &name, bool newTab = false,
                   int timeoutMs = 15000);

} // namespace workspace_test
