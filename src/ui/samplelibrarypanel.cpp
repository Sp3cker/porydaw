#include "samplelibrarypanel.h"

#include <QDir>
#include <QFileDialog>
#include <QFileInfo>
#include <QHBoxLayout>
#include <QLabel>
#include <QListWidget>
#include <QPushButton>
#include <QSettings>
#include <QSignalBlocker>
#include <QVBoxLayout>

#include "ui/layout.h"

namespace {

// QSettings key this panel owns: the folder list, in item order.
const QString kFoldersKey = QStringLiteral("sampleLibraryFolders");

// Audio containers the Sample Editor imports; matched case-insensitively so
// a ".WAV" from an older session still lists.
const QStringList kAudioSuffixes = {
    QStringLiteral("wav"), QStringLiteral("aif"),  QStringLiteral("aiff"),
    QStringLiteral("mp3"), QStringLiteral("flac"), QStringLiteral("ogg"),
};

bool isCompatibleAudio(const QString &fileName)
{
    return kAudioSuffixes.contains(QFileInfo(fileName).suffix().toLower());
}

} // namespace

SampleLibraryPanel::SampleLibraryPanel(QWidget *parent) : QWidget(parent)
{
    setObjectName(QStringLiteral("sampleLibraryPanel"));

    auto *layout = new QVBoxLayout(this);

    auto *buttons = new QHBoxLayout;
    m_addFolder = new QPushButton(this);
    m_addFolder->setObjectName(QStringLiteral("sampleLibraryAddFolder")); // findChild for tests
    m_addFolder->setText(tr("Add Folder…"));
    connect(m_addFolder, &QPushButton::clicked, this, [this] {
        // Browse beside the library's last folder; without one, the home dir.
        const QString startDir = m_folders->count() > 0
                                     ? m_folders->item(m_folders->count() - 1)->text()
                                     : QDir::homePath();
        const QString folder =
            QFileDialog::getExistingDirectory(this, tr("Add Sample Folder"), startDir);
        if (!folder.isEmpty())
            addFolder(folder);
    });
    buttons->addWidget(m_addFolder);

    m_removeFolder = new QPushButton(this);
    m_removeFolder->setObjectName(QStringLiteral("sampleLibraryRemoveFolder"));
    m_removeFolder->setText(tr("Remove"));
    m_removeFolder->setEnabled(false); // nothing selected yet
    connect(m_removeFolder, &QPushButton::clicked, this, &SampleLibraryPanel::removeCurrentFolder);
    buttons->addWidget(m_removeFolder);
    buttons->addStretch(1);
    layout->addLayout(buttons);

    m_folders = new QListWidget(this);
    m_folders->setObjectName(QStringLiteral("sampleLibraryFolders"));
    ::layout::configureListPositionIndicator(*m_folders->verticalScrollBar());
    // Every selection change (programmatic or user) refreshes the panes below.
    connect(m_folders, &QListWidget::currentItemChanged, this,
            [this](QListWidgetItem *, QListWidgetItem *) { refreshDirectories(); });
    layout->addWidget(m_folders, 1);

    auto *directoriesLabel = new QLabel(tr("Directories"), this);
    layout->addWidget(directoriesLabel);

    m_directories = new QListWidget(this);
    m_directories->setObjectName(QStringLiteral("sampleLibraryDirectories"));
    ::layout::configureListPositionIndicator(*m_directories->verticalScrollBar());
    connect(m_directories, &QListWidget::currentItemChanged, this,
            [this](QListWidgetItem *, QListWidgetItem *) { refreshFiles(); });
    layout->addWidget(m_directories, 1);

    auto *filesLabel = new QLabel(tr("Files"), this);
    layout->addWidget(filesLabel);

    m_files = new QListWidget(this);
    m_files->setObjectName(QStringLiteral("sampleLibraryFiles"));
    ::layout::configureListPositionIndicator(*m_files->verticalScrollBar());
    connect(m_files, &QListWidget::itemClicked, this, [this](QListWidgetItem *item) {
        emit previewRequested(item->data(Qt::UserRole).toString());
    });
    connect(m_files, &QListWidget::itemDoubleClicked, this, [this](QListWidgetItem *item) {
        emit loadRequested(item->data(Qt::UserRole).toString());
    });
    layout->addWidget(m_files, 1);

    m_status = new QLabel(this);
    m_status->setObjectName(QStringLiteral("sampleLibraryStatus"));
    layout->addWidget(m_status);
    m_status->setWordWrap(true);

    // Restore the library; folders that vanished from disk stay listed. The
    // first selection below starts the initial refresh through
    // currentItemChanged, so missing paths report themselves right away.
    const QSettings settings;
    const QStringList stored = settings.value(kFoldersKey).toStringList();
    for (const QString &path : stored)
        m_folders->addItem(path);
    if (m_folders->count() > 0)
        m_folders->setCurrentRow(0);
}

void SampleLibraryPanel::addFolder(const QString &path)
{
    if (path.trimmed().isEmpty())
        return;
    // Normalize once: absolute, cleaned, and stable across restarts.
    const QString absolute = QDir(path).absolutePath();
    const QList<QListWidgetItem *> existing = m_folders->findItems(absolute, Qt::MatchExactly);
    if (!existing.isEmpty()) {
        if (m_folders->currentItem() == existing.first())
            refreshDirectories();
        else
            m_folders->setCurrentItem(existing.first());
        return;
    }
    m_folders->addItem(absolute);
    persistFolders(); // item order is the library order
    m_folders->setCurrentItem(m_folders->item(m_folders->count() - 1));
}

void SampleLibraryPanel::showMessage(const QString &message)
{
    m_status->setText(message);
}

void SampleLibraryPanel::removeCurrentFolder()
{
    const int row = m_folders->currentRow();
    if (row < 0)
        return;
    {
        QSignalBlocker blocker(m_folders); // exactly one refresh, below
        delete m_folders->takeItem(row);
        persistFolders();
        m_folders->setCurrentIndex(QModelIndex()); // removal never selects a successor
    }
    refreshDirectories(); // no folder selected: the panes and status clear
}

// Mirrors the selected saved root into its directory list, file list, status
// line, and Remove button — the single place that keeps those in sync.
void SampleLibraryPanel::refreshDirectories()
{
    m_directories->clear();
    m_files->clear();
    m_status->clear();
    QListWidgetItem *folder = m_folders->currentItem();
    if (!folder) {
        m_removeFolder->setEnabled(false);
        return;
    }
    m_removeFolder->setEnabled(true);

    const QString path = folder->text();
    if (!QDir(path).exists()) {
        m_status->setText(tr("Folder not found: %1").arg(path));
        return;
    }

    const QDir dir(path);
    auto *thisFolder = new QListWidgetItem(tr("This Folder"), m_directories);
    thisFolder->setData(Qt::UserRole, dir.absolutePath());
    thisFolder->setToolTip(dir.absolutePath());
    const QStringList names = dir.entryList(QDir::Dirs | QDir::Readable | QDir::NoDotAndDotDot,
                                            QDir::Name | QDir::IgnoreCase);
    for (const QString &name : names) {
        const QString absolutePath = dir.absoluteFilePath(name);
        auto *item = new QListWidgetItem(name, m_directories);
        item->setData(Qt::UserRole, absolutePath);
        item->setToolTip(absolutePath);
    }
    m_directories->setCurrentRow(0);
}

// Mirrors the selected directory into the compatible audio file list. Files
// are deliberately non-recursive: child directories are selected above.
void SampleLibraryPanel::refreshFiles()
{
    m_files->clear();
    m_status->clear();
    QListWidgetItem *directory = m_directories->currentItem();
    if (!directory)
        return;

    const QDir dir(directory->data(Qt::UserRole).toString());
    const QStringList names =
        dir.entryList(QDir::Files | QDir::Readable, QDir::Name | QDir::IgnoreCase);
    for (const QString &name : names) {
        if (!isCompatibleAudio(name))
            continue;
        const QString absolutePath = dir.absoluteFilePath(name);
        auto *item = new QListWidgetItem(name, m_files);
        item->setData(Qt::UserRole, absolutePath);
        item->setToolTip(absolutePath);
    }
    if (m_files->count() == 0)
        m_status->setText(tr("No compatible audio files in this folder."));
}

void SampleLibraryPanel::persistFolders() const
{
    QStringList paths;
    paths.reserve(m_folders->count());
    for (int i = 0; i < m_folders->count(); ++i)
        paths.append(m_folders->item(i)->text());
    QSettings settings;
    settings.setValue(kFoldersKey, paths);
}
