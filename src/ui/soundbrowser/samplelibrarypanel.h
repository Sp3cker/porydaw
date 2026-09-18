#pragma once

#include <QSet>
#include <QStringList>
#include <QWidget>

class QFileSystemModel;
class QLabel;
class QListView;
class QPushButton;
class QTreeWidget;
class QTreeWidgetItem;

// Saved roots and their descendants are navigation only. Audio is requested
// explicitly and remains owned by the editor's SoundBrowser coordinator.
class SampleLibraryPanel : public QWidget
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(SampleLibraryPanel)

  public:
    explicit SampleLibraryPanel(QWidget *parent = nullptr);
    void addFolder();
    void setFolders(const QStringList &dirs);
    QStringList savedFolders() const;
    void showMessage(const QString &text);
    void setLoadedPath(const QString &path);
    void setPreviewingPath(const QString &path);

  signals:
    void previewRequested(const QString &path);
    void previewStopRequested();
    void loadRequested(const QString &path);

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    void refreshFolders();
    void refreshFiles();
    void navigateTo(const QString &dir);
    void populateFolders(QTreeWidgetItem *item);
    QString selectedPath() const;
    void updateState();
    void togglePreview();
    void loadSelected();

    QStringList m_folders;
    QString m_current;
    QString m_loadedPath;
    QString m_previewingPath;
    QString m_message;
    QSet<QString> m_listedFolders;
    bool m_listing = false;
    QTreeWidget *m_folderTree = nullptr;
    QPushButton *m_removeButton = nullptr;
    QPushButton *m_previewButton = nullptr;
    QPushButton *m_loadButton = nullptr;
    QListView *m_files = nullptr;
    QFileSystemModel *m_fileModel = nullptr;
    QLabel *m_status = nullptr;
    QLabel *m_loaded = nullptr;
    QLabel *m_previewing = nullptr;
};
