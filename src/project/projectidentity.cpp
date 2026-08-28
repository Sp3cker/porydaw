#include "projectidentity.h"

#include <QDir>
#include <QHash>

#include <algorithm>

std::optional<SongName> SongName::create(QString value)
{
    if (value.isEmpty())
        return std::nullopt;
    return SongName{std::move(value)};
}

SongName::SongName(QString value) : m_value{std::move(value)} {}

size_t qHash(const SongName &name, size_t seed)
{
    return qHash(name.value(), seed);
}

std::optional<VoicegroupId> VoicegroupId::create(QString sourceRelativePath, QString sectionLabel)
{
    // Normalize the spelling ("./a", "a//b") while rejecting anything that
    // does not name a file inside the project: an absolute path, a
    // ".."-escape, or the project root itself (any spelling that cleans
    // down to ".").
    const QString normalized = QDir::cleanPath(sourceRelativePath);
    if (normalized.isEmpty() || normalized == QLatin1String(".") ||
        QDir::isAbsolutePath(normalized) || normalized == QLatin1String("..") ||
        normalized.startsWith(QLatin1String("../")))
        return std::nullopt;
    return VoicegroupId{normalized, std::move(sectionLabel)};
}

VoicegroupId::VoicegroupId(QString normalizedSourceRelativePath, QString sectionLabel)
    : m_sourceRelativePath{std::move(normalizedSourceRelativePath)}
    , m_sectionLabel{std::move(sectionLabel)}
{}

size_t qHash(const VoicegroupId &id, size_t seed)
{
    return qHashMulti(seed, id.sourceRelativePath(), id.sectionLabel());
}

SavedWorkspaceRecipe normalizeSavedRecipe(QString projectPath, QStringList labels,
                                          QString selectedLabel)
{
    QVector<SongName> ordered;
    for (QString &label : labels) {
        auto name = SongName::create(std::move(label));
        if (!name || std::find(ordered.cbegin(), ordered.cend(), *name) != ordered.cend())
            continue;
        ordered.push_back(std::move(*name));
    }

    auto selected = SongName::create(std::move(selectedLabel));
    if (selected && ordered.isEmpty()) {
        // Pre-tabs session generation: no tab list survived discarding, so
        // the selected song restores as the one tab.
        ordered.push_back(*selected);
    } else if (!selected ||
               std::find(ordered.cbegin(), ordered.cend(), *selected) == ordered.cend()) {
        // The selected label is empty, missing from the ordered list, or
        // discarded: fall back to the first name.
        selected = ordered.isEmpty() ? std::nullopt : std::optional<SongName>{ordered.front()};
    }
    return SavedWorkspaceRecipe{std::move(projectPath), std::move(ordered), std::move(selected)};
}
