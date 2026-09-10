#include "plugininstaller.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileInfoList>
#include <QTemporaryDir>

namespace scripting {

namespace {

constexpr const char *kContext = "PluginInstaller";
constexpr const char *kManifest = "plugin.json";
// Hidden: the host lists non-hidden directories only, so a plugin under
// construction is never seen (nor loaded) halfway.
constexpr const char *kStaging = ".porydaw-install-XXXXXX";

bool copyRegularFile(const QString &from, const QString &to, QString *error)
{
    if (QFile::copy(from, to))
        return true;
    if (error)
        *error = QCoreApplication::translate(kContext, "Could not copy %1.")
                     .arg(QDir::toNativeSeparators(from));
    return false;
}

// Copies the contents of `from` into `to` (created here). Symlinks are never
// walked: a link to a file is copied as the file it names, every other link
// is refused, so a link loop or a link back to a parent cannot send the walk
// round forever and a link to a folder is never read as a file.
bool copyTree(const QString &from, const QString &to, QString *error)
{
    if (!QDir().mkpath(to)) {
        if (error)
            *error = QCoreApplication::translate(kContext, "Could not create %1.")
                         .arg(QDir::toNativeSeparators(to));
        return false;
    }
    // System, so a broken link is an entry here (and refused) instead of a
    // file the listing quietly drops.
    const QDir::Filters listed =
        QDir::AllEntries | QDir::System | QDir::Hidden | QDir::NoDotAndDotDot;
    const QFileInfoList entries = QDir(from).entryInfoList(listed);
    for (const QFileInfo &entry : entries) {
        const QString target = QDir(to).filePath(entry.fileName());
        if (entry.isSymLink()) {
            // exists()/isFile() read through the link, so a link to a folder
            // looks like a folder here: name it, do not follow it.
            if (entry.exists() && entry.isFile()) {
                if (!copyRegularFile(entry.absoluteFilePath(), target, error))
                    return false;
                continue;
            }
            if (error) {
                *error = QCoreApplication::translate(
                             kContext, entry.exists() ? "%1 is a link to a folder; add the folder "
                                                        "itself."
                                                      : "%1 is a broken link.")
                             .arg(QDir::toNativeSeparators(entry.absoluteFilePath()));
            }
            return false;
        }
        if (entry.isDir()) {
            if (!copyTree(entry.absoluteFilePath(), target, error))
                return false;
            continue;
        }
        if (!entry.isFile()) {
            if (error)
                *error = QCoreApplication::translate(kContext, "%1 is not a regular file.")
                             .arg(QDir::toNativeSeparators(entry.absoluteFilePath()));
            return false;
        }
        if (!copyRegularFile(entry.absoluteFilePath(), target, error))
            return false;
    }
    return true;
}

// A broken link reports exists() == false, yet its name is still taken.
bool occupied(const QFileInfo &info)
{
    return info.exists() || info.isSymLink();
}

} // namespace

bool installPlugin(const QString &selection, const QString &pluginsRoot, QString *error)
{
    if (error)
        error->clear();
    auto fail = [error](const QString &reason) {
        if (error)
            *error = reason;
        return false;
    };

    const QFileInfo picked(QFileInfo(selection).absoluteFilePath());
    QString sourcePath = picked.absoluteFilePath();
    if (picked.isFile()) {
        if (picked.fileName() != QLatin1String(kManifest) || !picked.isReadable())
            return fail(QCoreApplication::translate(
                            kContext, "%1 is not a readable plugin folder or plugin.json.")
                            .arg(QDir::toNativeSeparators(sourcePath)));
        sourcePath = picked.absolutePath();
    }

    const QFileInfo source(sourcePath);
    if (!source.isDir() || !source.isReadable())
        return fail(QCoreApplication::translate(
                        kContext, "%1 is not a readable plugin folder or plugin.json.")
                        .arg(QDir::toNativeSeparators(sourcePath)));
    // The real path: on macOS the folder the user picked and the plugins
    // folder can be the same place under two names (/tmp and /private/tmp,
    // say), so containment is decided on these and not on the paths as
    // written.
    const QString realSource = source.canonicalFilePath();
    if (realSource.isEmpty())
        return fail(QCoreApplication::translate(
                        kContext, "%1 is not a readable plugin folder or plugin.json.")
                        .arg(QDir::toNativeSeparators(sourcePath)));

    const QString name = source.fileName();
    if (name.isEmpty() || name == QLatin1String(".") || name == QLatin1String(".."))
        return fail(QCoreApplication::translate(kContext, "%1 is not a plugin folder.")
                        .arg(QDir::toNativeSeparators(sourcePath)));

    const QDir pluginsRootDir(pluginsRoot);
    const QString rootPath = pluginsRootDir.absolutePath();
    if (!pluginsRootDir.exists() && !QDir().mkpath(rootPath))
        return fail(QCoreApplication::translate(kContext, "Could not create the plugins folder %1.")
                        .arg(QDir::toNativeSeparators(rootPath)));
    const QString realRoot = QFileInfo(rootPath).canonicalFilePath();
    if (realRoot.isEmpty())
        return fail(QCoreApplication::translate(kContext, "%1 is not a plugins folder.")
                        .arg(QDir::toNativeSeparators(rootPath)));

    // The plugins folder is the source or sits inside it: staging — and so
    // the copy — would land under the very folder being copied.
    if (realRoot == realSource || realRoot.startsWith(realSource + QLatin1Char('/')))
        return fail(QCoreApplication::translate(
                        kContext, "The plugins folder is inside %1, so installing it would copy "
                                  "it into itself.")
                        .arg(QDir::toNativeSeparators(realSource)));

    const QFileInfo manifest(QDir(sourcePath).filePath(QLatin1String(kManifest)));
    if (!manifest.isFile() || !manifest.isReadable())
        return fail(QCoreApplication::translate(kContext, "%1 has no %2.")
                        .arg(QDir::toNativeSeparators(sourcePath), QLatin1String(kManifest)));

    const QString destPath = pluginsRootDir.filePath(name);
    const QFileInfo dest(destPath);
    if (occupied(dest))
        return fail(
            dest.canonicalFilePath() == realSource
                ? QCoreApplication::translate(kContext, "%1 is already installed.").arg(name)
                : QCoreApplication::translate(kContext,
                                              "A plugin folder named %1 already exists in %2.")
                      .arg(name, QDir::toNativeSeparators(rootPath)));

    QTemporaryDir staging(pluginsRootDir.filePath(QLatin1String(kStaging)));
    if (!staging.isValid())
        return fail(
            QCoreApplication::translate(kContext, "Could not create a staging folder in %1.")
                .arg(QDir::toNativeSeparators(rootPath)));
    if (!copyTree(sourcePath, staging.path(), error))
        return false; // staging goes away with it; the destination was never touched
    QDir renamer;
    if (!renamer.rename(staging.path(), destPath))
        return fail(QCoreApplication::translate(kContext, "Could not install %1 into %2.")
                        .arg(name, QDir::toNativeSeparators(rootPath)));
    staging.setAutoRemove(false); // the staging folder *is* the installed plugin now
    return true;
}

} // namespace scripting
