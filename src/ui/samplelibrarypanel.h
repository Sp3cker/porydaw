#pragma once

#include <QWidget>

class QLabel;
class QListWidget;
class QPushButton;

// The Sample Editor's folder library: a persisted list of sample folders
// (QSettings key "sampleLibraryFolders", kept in item order), each with its
// direct readable child directories and compatible audio files. Clicking a
// file asks the embedding dialog for a preview, double-clicking for a load —
// both carry the file's absolute path. Folders missing on disk stay listed
// (removing them is the user's call) and are reported on the status line,
// which also relays messages through showMessage().
class SampleLibraryPanel : public QWidget
{
    Q_OBJECT

  public:
    explicit SampleLibraryPanel(QWidget *parent = nullptr);

    // Normalizes the path to an absolute, cleaned form and keeps the list
    // duplicate-free: an already-listed folder is reselected, or refreshed
    // to This Folder when it is already current. The library persists
    // immediately after the list changes.
    void addFolder(const QString &path);
    // Relays a message onto the status line (an empty string clears it).
    void showMessage(const QString &message);

  signals:
    // A file was clicked for preview / double-clicked for loading; the
    // argument is the file's absolute path.
    void previewRequested(const QString &path);
    void loadRequested(const QString &path);

  private:
    void removeCurrentFolder();
    void refreshDirectories();
    void refreshFiles();
    void persistFolders() const;

    QPushButton *m_addFolder = nullptr;
    QPushButton *m_removeFolder = nullptr;
    QListWidget *m_folders = nullptr;
    QListWidget *m_directories = nullptr;
    QListWidget *m_files = nullptr;
    QLabel *m_status = nullptr;
};
