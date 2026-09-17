#include "ui/soundbrowser/samplelibrarypanel.h"

#include <QComboBox>
#include <QDir>
#include <QFileDialog>
#include <QFileInfo>
#include <QFileSystemModel>
#include <QHBoxLayout>
#include <QLabel>
#include <QListView>
#include <QPushButton>
#include <QSettings>
#include <QVBoxLayout>

namespace {

const QLatin1String kFoldersKey("sampleLibraryFolders");

QString normalizeFolder(const QString &dir)
{
    return QDir::cleanPath(QDir(dir).absolutePath());
}

} // namespace

SampleLibraryPanel::SampleLibraryPanel(QWidget *parent) : QWidget(parent)
{
    setObjectName(QStringLiteral("sampleLibraryPanel"));

    auto *layout = new QVBoxLayout(this);
    layout->setContentsMargins(0, 0, 0, 0);

    auto *folderRow = new QHBoxLayout;
    m_folderCombo = new QComboBox(this);
    m_folderCombo->setObjectName(QStringLiteral("sampleLibraryFolders"));
    m_folderCombo->setToolTip(tr("Library folder"));
    m_folderCombo->setSizeAdjustPolicy(QComboBox::AdjustToContents);
    connect(m_folderCombo, &QComboBox::currentTextChanged, this,
            [this](const QString &dir) { navigateTo(dir); });
    folderRow->addWidget(m_folderCombo, 1);
    m_upButton = new QPushButton(tr("Up"), this);
    m_upButton->setObjectName(QStringLiteral("sampleLibraryUp"));
    m_upButton->setToolTip(tr("Go to the parent folder"));
    connect(m_upButton, &QPushButton::clicked, this, [this] {
        if (m_current.isEmpty())
            return;
        navigateTo(QDir(m_current).filePath(QStringLiteral("..")));
    });
    folderRow->addWidget(m_upButton);
    m_addButton = new QPushButton(tr("Add…"), this);
    m_addButton->setObjectName(QStringLiteral("sampleLibraryAdd"));
    m_addButton->setToolTip(tr("Add a sample folder to the library"));
    connect(m_addButton, &QPushButton::clicked, this, &SampleLibraryPanel::addFolder);
    folderRow->addWidget(m_addButton);
    m_removeButton = new QPushButton(tr("Remove"), this);
    m_removeButton->setObjectName(QStringLiteral("sampleLibraryRemove"));
    m_removeButton->setToolTip(tr("Remove the current folder from the library"));
    connect(m_removeButton, &QPushButton::clicked, this, [this] {
        if (m_current.isEmpty())
            return;
        QStringList folders = m_folders;
        folders.removeAll(m_current);
        setFolders(folders);
    });
    folderRow->addWidget(m_removeButton);
    layout->addLayout(folderRow);

    m_fileModel = new QFileSystemModel(this);
    m_fileModel->setFilter(QDir::AllDirs | QDir::Files | QDir::NoDotAndDotDot);
    m_fileModel->setNameFilters({QStringLiteral("*.wav"), QStringLiteral("*.aiff"),
                                 QStringLiteral("*.aif"), QStringLiteral("*.mp3"),
                                 QStringLiteral("*.flac"), QStringLiteral("*.ogg")});
    m_fileModel->setNameFilterDisables(false);
    m_files = new QListView(this);
    m_files->setObjectName(QStringLiteral("sampleLibraryFiles"));
    // QFileSystemModel items are editable (rename); this panel browses —
    // a lingering inline editor would swallow the next click.
    m_files->setEditTriggers(QAbstractItemView::NoEditTriggers);
    m_files->setModel(m_fileModel);
    connect(m_files, &QListView::clicked, this, [this](const QModelIndex &index) {
        const QFileInfo info = m_fileModel->fileInfo(index);
        if (info.isDir()) {
            navigateTo(info.absoluteFilePath());
            return;
        }
        if (info.isFile())
            emit previewRequested(info.absoluteFilePath());
    });
    connect(m_files, &QListView::doubleClicked, this, [this](const QModelIndex &index) {
        const QFileInfo info = m_fileModel->fileInfo(index);
        if (info.isDir()) {
            navigateTo(info.absoluteFilePath());
            return;
        }
        if (info.isFile())
            emit loadRequested(info.absoluteFilePath());
    });
    // The Up button navigates back out; double click enters subdirectories
    // in place. Single click previews audio, double click loads it.
    layout->addWidget(m_files, 1);

    m_status = new QLabel(this);
    m_status->setObjectName(QStringLiteral("sampleLibraryStatus"));
    m_status->setWordWrap(true);
    layout->addWidget(m_status);

    QSettings settings;
    setFolders(settings.value(kFoldersKey).toStringList());
}

void SampleLibraryPanel::addFolder()
{
    const QString dir = QFileDialog::getExistingDirectory(
        this, tr("Add Sample Library Folder"), QDir::homePath(), QFileDialog::ShowDirsOnly);
    if (dir.isEmpty())
        return;
    QStringList folders = savedFolders();
    folders.append(dir);
    setFolders(folders);
    navigateTo(normalizeFolder(dir));
}
void SampleLibraryPanel::refreshFolders()
{
    m_folderCombo->blockSignals(true);
    m_folderCombo->clear();
    m_folderCombo->addItems(m_folders);
    // The folder list changed: drop any in-place subdirectory navigation
    // and follow the saved selection.
    if (!m_folders.contains(m_current))
        m_current = m_folders.value(0);
    m_folderCombo->setCurrentIndex(m_folders.indexOf(m_current));
    m_folderCombo->blockSignals(false);
    refreshFiles();
}
void SampleLibraryPanel::refreshFiles()
{
    const bool exists = !m_current.isEmpty() && QDir(m_current).exists();
    m_files->setVisible(exists);
    m_upButton->setEnabled(!m_current.isEmpty());
    m_removeButton->setEnabled(m_folders.contains(m_current));
    if (!exists) {
        m_fileModel->setRootPath(QString());
        m_files->setRootIndex(QModelIndex());
        showMessage(m_current.isEmpty() ? QString()
                                        : tr("Library folder is missing: %1").arg(m_current));
        return;
    }
    showMessage(QString());
    m_files->setRootIndex(m_fileModel->setRootPath(m_current));
}

void SampleLibraryPanel::navigateTo(const QString &dir)
{
    const QString clean = normalizeFolder(dir);
    m_current = clean;
    const int saved = m_folders.indexOf(clean);
    if (saved >= 0) {
        m_folderCombo->blockSignals(true);
        m_folderCombo->setCurrentIndex(saved);
        m_folderCombo->blockSignals(false);
    } else {
        // Direct-child navigation below a saved folder: keep the saved
        // list as-is and show the subdirectory in place.
        m_folderCombo->blockSignals(true);
        m_folderCombo->setCurrentIndex(-1);
        m_folderCombo->blockSignals(false);
    }
    refreshFiles();
}

void SampleLibraryPanel::setFolders(const QStringList &dirs)
{
    QStringList normalized;
    for (const QString &dir : dirs) {
        const QString clean = normalizeFolder(dir);
        if (!clean.isEmpty() && !normalized.contains(clean))
            normalized.append(clean);
    }
    m_folders = normalized;
    QSettings settings;
    settings.setValue(kFoldersKey, m_folders);
    refreshFolders();
}

QStringList SampleLibraryPanel::savedFolders() const
{
    return m_folders;
}

void SampleLibraryPanel::showMessage(const QString &text)
{
    m_status->setText(text);
}
