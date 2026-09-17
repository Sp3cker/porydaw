#pragma once

#include <QStringList>
#include <QWidget>

class QComboBox;
class QFileSystemModel;
class QLabel;
class QListView;
class QPushButton;

// Folder browser for the Sample Editor's library-first import flow
// (sound-browser-consolidation spec, "Sample library panel"). Used only
// inside SampleEditorDialog: it lists saved folders' direct audio-file
// children for preview (single click) and load (double click). It never
// touches the audio engine; preview/load logic lives in the editor and
// the soundbrowser::SoundBrowser coordinator.
class SampleLibraryPanel : public QWidget
{
    Q_OBJECT

  public:
    explicit SampleLibraryPanel(QWidget *parent = nullptr);

    // Native directory dialog; appends/persists/navigates on accept.
    void addFolder();
    // Programmatic equivalent (used by addFolder and tests): absolute
    // QDir::cleanPath normalization, dedupe, persistence.
    void setFolders(const QStringList &dirs);
    QStringList savedFolders() const;
    // Status-line notice (missing folders, preview/load failures).
    void showMessage(const QString &text);

  signals:
    void previewRequested(const QString &path);
    void loadRequested(const QString &path);

  private:
    void refreshFolders();
    void refreshFiles();
    void navigateTo(const QString &dir);

    QStringList m_folders;
    QString m_current;

    QComboBox *m_folderCombo = nullptr;
    QPushButton *m_addButton = nullptr;
    QPushButton *m_removeButton = nullptr;
    QPushButton *m_upButton = nullptr;
    QListView *m_files = nullptr;
    QFileSystemModel *m_fileModel = nullptr;
    QLabel *m_status = nullptr;
};
