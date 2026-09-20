#pragma once

#include <QString>
#include <memory>

class QTemporaryDir;
namespace checks {

class ProjectFixture final
{
  public:
    static std::unique_ptr<ProjectFixture> copyOf(const QString &source, QString &error);
    ~ProjectFixture();

    ProjectFixture(const ProjectFixture &) = delete;
    ProjectFixture &operator=(const ProjectFixture &) = delete;
    ProjectFixture(ProjectFixture &&) = delete;
    ProjectFixture &operator=(ProjectFixture &&) = delete;

    const QString &root() const noexcept;

  private:
    ProjectFixture() = default;

    std::unique_ptr<QTemporaryDir> m_directory;
    QString m_root;
};

} // namespace checks
