#include "checks/support/songfixture.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTemporaryDir>

namespace checks {

namespace {
bool copyTree(const QString &source, const QString &destination, QString &error)
{
    if (!QFileInfo(source).isDir()) {
        error = QStringLiteral("fixture source is not a directory: %1").arg(source);
        return false;
    }
    const QDir sourceDir(source);
    const auto entries =
        sourceDir.entryInfoList(QDir::NoDotAndDotDot | QDir::AllEntries | QDir::Hidden);
    for (const QFileInfo &entry : entries) {
        const QString target = destination + QLatin1Char('/') + entry.fileName();
        if (entry.isDir()) {
            if (!QDir().mkpath(target)) {
                error = QStringLiteral("could not create fixture directory: %1").arg(target);
                return false;
            }
            if (!copyTree(entry.absoluteFilePath(), target, error))
                return false;
        } else if (entry.isFile()) {
            if (!QFile::copy(entry.absoluteFilePath(), target)) {
                error =
                    QStringLiteral("could not copy fixture file: %1").arg(entry.absoluteFilePath());
                return false;
            }
        }
    }
    return true;
}
} // namespace

std::unique_ptr<ProjectFixture> ProjectFixture::copyOf(const QString &source, QString &error)
{
    error.clear();
    auto fixture = std::unique_ptr<ProjectFixture>(new ProjectFixture);
    fixture->m_directory = std::make_unique<QTemporaryDir>();
    if (!fixture->m_directory->isValid()) {
        error = QStringLiteral("could not create temporary fixture directory");
        return nullptr;
    }
    if (!copyTree(source, fixture->m_directory->path(), error))
        return nullptr;
    fixture->m_root = fixture->m_directory->path();
    return fixture;
}

ProjectFixture::~ProjectFixture() = default;

const QString &ProjectFixture::root() const noexcept
{
    return m_root;
}

} // namespace checks
