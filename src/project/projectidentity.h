#pragma once

#include <QString>
#include <QStringList>
#include <QVector>

#include <cstddef>
#include <optional>

// The stable project-domain identities and the saved workspace recipe, in one
// low-level home so the worker, project I/O, and UI layers can all include it
// without circular ownership. Equality and qHash stay value-based: copies of
// the same value are the same identity, and no identity leaks an address.

// SongName is the stable identity of one song: the project-relative
// SongInfo::label. SongInfo::id is snapshot-local, and loader names are
// aliases, not identity. An empty value is the only invalid name, and the
// validating factory is the only way to construct one.
class SongName
{
  public:
    static std::optional<SongName> create(QString value);
    const QString &value() const { return m_value; }

    friend bool operator==(const SongName &, const SongName &) = default;

  private:
    explicit SongName(QString value);

    QString m_value;
};

size_t qHash(const SongName &name, size_t seed = 0);

// VoicegroupId is the stable identity of one voicegroup: a non-empty
// project-relative source path plus the optional section label (empty for a
// per-file voicegroup). The factory normalizes the source path spelling and
// rejects absolute paths, ".."-escapes, and the project root itself.
class VoicegroupId
{
  public:
    static std::optional<VoicegroupId> create(QString sourceRelativePath, QString sectionLabel);
    const QString &sourceRelativePath() const { return m_sourceRelativePath; }
    const QString &sectionLabel() const { return m_sectionLabel; }

    friend bool operator==(const VoicegroupId &, const VoicegroupId &) = default;

  private:
    VoicegroupId(QString normalizedSourceRelativePath, QString sectionLabel);

    QString m_sourceRelativePath;
    QString m_sectionLabel;
};

size_t qHash(const VoicegroupId &id, size_t seed = 0);

// std::unordered_map hasher over the same value-based hash as qHash, for
// containers that must own move-only values without default construction.
struct VoicegroupIdHash {
    size_t operator()(const VoicegroupId &id) const { return qHash(id); }
};

// The last workspace as recorded in QSettings, before normalization.
struct SavedWorkspaceRecipe {
    QString projectPath;              // QSettings key: "lastProjectDir"
    QVector<SongName> orderedSongs;   // QSettings key: "lastOpenSongs"
    std::optional<SongName> selected; // QSettings key: "lastSongLabel"
};

// The one pure normalization shared by both settings readers: discards empty
// labels, keeps the first duplicate, and preserves order. An ordered list
// empty after discarding with a non-empty selected label restores as selected
// alone (the pre-tabs session generation, one tab). Selection falls back to
// the first name when the selected label is empty, missing from the ordered
// list, or discarded.
SavedWorkspaceRecipe normalizeSavedRecipe(QString projectPath, QStringList labels,
                                          QString selectedLabel);
