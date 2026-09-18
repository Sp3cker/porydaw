#include "ui/soundbrowser/samplelibrarypanel.h"

#include <QDir>
#include <QFileDialog>
#include <QFileInfo>
#include <QFileSystemModel>
#include <QHBoxLayout>
#include <QItemSelectionModel>
#include <QKeyEvent>
#include <QLabel>
#include <QListView>
#include <QPushButton>
#include <QSettings>
#include <QSignalBlocker>
#include <QTreeWidget>
#include <QVBoxLayout>
#include <utility>

#include "ui/layout.h"

namespace {
const QLatin1String kFoldersKey("sampleLibraryFolders");
QString normalizeFolder(const QString &dir)
{
    return QDir::cleanPath(QDir(dir).absolutePath());
}
QString folderName(const QString &path)
{
    const QString name = QFileInfo(path).fileName();
    return name.isEmpty() ? QDir::toNativeSeparators(path) : name;
}
} // namespace

SampleLibraryPanel::SampleLibraryPanel(QWidget *parent) : QWidget(parent)
{
    setObjectName(QStringLiteral("sampleLibraryPanel"));
    auto *column = new QVBoxLayout(this);
    column->setContentsMargins(0, 0, 0, 0);
    column->setSpacing(layout::space(layout::Space::One));
    column->addWidget(new QLabel(tr("Library"), this));
    const auto button = [this](const QString &text, const char *name) {
        auto *result = new QPushButton(text, this);
        result->setObjectName(QLatin1String(name));
        result->setAutoDefault(false);
        return result;
    };
    auto *add = button(tr("Add Folder…"), "sampleLibraryAdd");
    auto *open = button(tr("Open File…"), "sampleLibraryOpen");
    auto *sources = new QHBoxLayout;
    sources->addWidget(add);
    sources->addWidget(open);
    column->addLayout(sources);
    connect(add, &QPushButton::clicked, this, &SampleLibraryPanel::addFolder);
    connect(open, &QPushButton::clicked, this, [this] {
        QSettings settings;
        const QString startDir =
            settings.value(QStringLiteral("lastSampleDir"), QDir::homePath()).toString();
        const QString path = QFileDialog::getOpenFileName(
            this, tr("Open Sample"), startDir,
            tr("Audio files (*.wav *.aif *.aiff *.mp3 *.flac *.ogg *.WAV *.AIF *.AIFF *.MP3 *.FLAC "
               "*.OGG)"));
        if (!path.isEmpty()) {
            settings.setValue(QStringLiteral("lastSampleDir"), QFileInfo(path).path());
            showMessage(QString());
            emit loadRequested(path);
        }
    });
    m_folderTree = new QTreeWidget(this);
    m_folderTree->setObjectName(QStringLiteral("sampleLibraryFolders"));
    m_folderTree->setAccessibleName(tr("Library folders"));
    m_folderTree->setHeaderHidden(true);
    m_folderTree->setEditTriggers(QAbstractItemView::NoEditTriggers);
    column->addWidget(m_folderTree, 1);
    connect(m_folderTree, &QTreeWidget::itemExpanded, this, &SampleLibraryPanel::populateFolders);
    connect(m_folderTree, &QTreeWidget::currentItemChanged, this, [this](QTreeWidgetItem *item) {
        navigateTo(item ? item->data(0, Qt::UserRole).toString() : QString());
    });
    m_removeButton = button(tr("Remove from Library"), "sampleLibraryRemove");
    m_removeButton->setToolTip(
        tr("Remove the selected saved root from the library. No files are deleted."));
    column->addWidget(m_removeButton);
    connect(m_removeButton, &QPushButton::clicked, this, [this] {
        auto *item = m_folderTree->currentItem();
        if (!item)
            return;
        while (item->parent())
            item = item->parent();
        QStringList folders = m_folders;
        folders.removeAll(item->data(0, Qt::UserRole).toString());
        setFolders(folders);
    });
    column->addWidget(new QLabel(tr("Audio files"), this));
    m_fileModel = new QFileSystemModel(this);
    m_fileModel->setReadOnly(true);
    m_fileModel->setFilter(QDir::Files | QDir::NoDotAndDotDot);
    m_fileModel->setNameFilters({QStringLiteral("*.wav"), QStringLiteral("*.aif"),
                                 QStringLiteral("*.aiff"), QStringLiteral("*.mp3"),
                                 QStringLiteral("*.flac"), QStringLiteral("*.ogg")});
    m_fileModel->setNameFilterDisables(false);
    m_files = new QListView(this);
    m_files->setObjectName(QStringLiteral("sampleLibraryFiles"));
    m_files->setAccessibleName(tr("Library audio files"));
    m_files->setEditTriggers(QAbstractItemView::NoEditTriggers);
    m_files->setModel(m_fileModel);
    m_files->installEventFilter(this);
    column->addWidget(m_files, 2);
    connect(m_files->selectionModel(), &QItemSelectionModel::currentChanged, this, [this] {
        m_message.clear();
        updateState();
    });
    connect(m_files, &QListView::clicked, this, [this] {
        const QString path = selectedPath();
        if (!path.isEmpty()) {
            showMessage(QString());
            emit previewRequested(path);
        }
    });
    // activated covers the platform's native activation gesture (including
    // double click); Enter is intercepted below for explicit audition.
    connect(m_files, &QListView::activated, this, [this] { loadSelected(); });
    connect(m_fileModel, &QFileSystemModel::directoryLoaded, this, [this](const QString &path) {
        m_listedFolders.insert(normalizeFolder(path));
        if (normalizeFolder(path) == m_current) {
            m_listing = false;
            updateState();
        }
    });
    connect(m_fileModel, &QAbstractItemModel::rowsInserted, this, [this] { updateState(); });
    connect(m_fileModel, &QAbstractItemModel::rowsRemoved, this, [this] { updateState(); });
    auto *actions = new QHBoxLayout;
    m_previewButton = button(tr("Preview"), "sampleLibraryPreview");
    m_previewButton->setToolTip(
        tr("Preview the selected source file (Enter or Space in the file list)."));
    m_loadButton = button(tr("Load"), "sampleLibraryLoad");
    m_loadButton->setToolTip(tr("Replace the editor document with the selected file."));
    actions->addWidget(m_previewButton);
    actions->addWidget(m_loadButton);
    column->addLayout(actions);
    connect(m_previewButton, &QPushButton::clicked, this, &SampleLibraryPanel::togglePreview);
    connect(m_loadButton, &QPushButton::clicked, this, &SampleLibraryPanel::loadSelected);
    m_status = new QLabel(this);
    m_status->setObjectName(QStringLiteral("sampleLibraryStatus"));
    m_loaded = new QLabel(this);
    m_loaded->setObjectName(QStringLiteral("sampleLibraryLoaded"));
    m_previewing = new QLabel(this);
    m_previewing->setObjectName(QStringLiteral("sampleLibraryPreviewing"));
    for (auto *label : {m_status, m_loaded, m_previewing}) {
        label->setTextFormat(Qt::PlainText);
        label->setWordWrap(true);
        column->addWidget(label);
    }
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
    for (int i = 0; i < m_folderTree->topLevelItemCount(); ++i) {
        auto *item = m_folderTree->topLevelItem(i);
        if (item->data(0, Qt::UserRole).toString() == normalizeFolder(dir))
            m_folderTree->setCurrentItem(item);
    }
}

void SampleLibraryPanel::populateFolders(QTreeWidgetItem *item)
{
    if (item->data(0, Qt::UserRole + 1).toBool())
        return;
    item->setData(0, Qt::UserRole + 1, true);
    const QDir directory(item->data(0, Qt::UserRole).toString());
    // Symlink directories are excluded so descendants cannot escape a saved root.
    const QFileInfoList children = directory.entryInfoList(
        QDir::Dirs | QDir::NoDotAndDotDot | QDir::NoSymLinks, QDir::Name | QDir::IgnoreCase);
    for (const QFileInfo &info : children) {
        auto *child = new QTreeWidgetItem(item, {info.fileName()});
        child->setData(0, Qt::UserRole, info.absoluteFilePath());
        child->setToolTip(0, info.absoluteFilePath());
        child->setChildIndicatorPolicy(QTreeWidgetItem::ShowIndicator);
    }
    if (children.isEmpty())
        item->setChildIndicatorPolicy(QTreeWidgetItem::DontShowIndicatorWhenChildless);
}

void SampleLibraryPanel::refreshFolders()
{
    const QSignalBlocker blocker(m_folderTree);
    m_folderTree->clear();
    for (const QString &path : std::as_const(m_folders)) {
        auto *item = new QTreeWidgetItem(m_folderTree, {folderName(path)});
        item->setData(0, Qt::UserRole, path);
        item->setToolTip(0, path);
        item->setChildIndicatorPolicy(QTreeWidgetItem::ShowIndicator);
    }
    m_folderTree->setCurrentItem(m_folderTree->topLevelItem(0));
    navigateTo(m_folders.value(0));
}

void SampleLibraryPanel::refreshFiles()
{
    m_files->setCurrentIndex(QModelIndex());
    m_files->selectionModel()->clearSelection();
    const bool exists = !m_current.isEmpty() && QDir(m_current).exists();
    m_files->setVisible(exists);
    m_listing = exists && !m_listedFolders.contains(m_current);
    if (exists)
        m_files->setRootIndex(m_fileModel->setRootPath(m_current));
    updateState();
}

void SampleLibraryPanel::navigateTo(const QString &dir)
{
    m_current = dir.isEmpty() ? QString() : normalizeFolder(dir);
    if (auto *item = m_folderTree->currentItem()) {
        populateFolders(item);
        item->setExpanded(true);
    }
    m_message.clear();
    refreshFiles();
}

void SampleLibraryPanel::setFolders(const QStringList &dirs)
{
    QStringList normalized;
    for (const QString &dir : dirs) {
        if (dir.trimmed().isEmpty())
            continue;
        const QString clean = normalizeFolder(dir);
        if (!normalized.contains(clean))
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

QString SampleLibraryPanel::selectedPath() const
{
    if (m_current.isEmpty() || !QDir(m_current).exists())
        return QString();
    const QModelIndex index = m_files->currentIndex();
    if (!index.isValid() || index.parent() != m_files->rootIndex())
        return QString();
    const QFileInfo info = m_fileModel->fileInfo(index);
    return info.isFile() ? info.absoluteFilePath() : QString();
}

void SampleLibraryPanel::updateState()
{
    if (!m_status)
        return;
    const QString selected = selectedPath();
    m_removeButton->setEnabled(m_folderTree->currentItem() != nullptr);
    m_loadButton->setEnabled(!selected.isEmpty());
    m_previewButton->setEnabled(!selected.isEmpty() || !m_previewingPath.isEmpty());
    m_previewButton->setText(m_previewingPath.isEmpty() ? tr("Preview") : tr("Stop Preview"));
    QString state;
    if (m_folders.isEmpty())
        state = tr("No library folders. Add a folder or open a file.");
    else if (!QDir(m_current).exists())
        state = tr("Library folder is missing: %1").arg(m_current);
    else if (m_listing)
        state = tr("Listing audio files…");
    else if (m_fileModel->rowCount(m_files->rootIndex()) == 0)
        state = tr("No supported audio files in this folder.");
    else if (selected.isEmpty())
        state = tr("No file selected.");
    else
        state = tr("Selected: %1").arg(QFileInfo(selected).fileName());
    m_status->setText(m_message.isEmpty() ? state : m_message);
    m_status->setToolTip(selected);
    m_loaded->setText(m_loadedPath.isEmpty()
                          ? tr("Loaded: none")
                          : tr("Loaded: %1").arg(QFileInfo(m_loadedPath).fileName()));
    m_loaded->setToolTip(m_loadedPath);
    m_previewing->setText(
        m_previewingPath.isEmpty()
            ? tr("Preview source: none")
            : tr("Preview source: %1").arg(QFileInfo(m_previewingPath).fileName()));
    m_previewing->setToolTip(m_previewingPath);
}

void SampleLibraryPanel::showMessage(const QString &text)
{
    m_message = text;
    updateState();
}
void SampleLibraryPanel::setLoadedPath(const QString &path)
{
    m_loadedPath = path;
    showMessage(QString());
}
void SampleLibraryPanel::setPreviewingPath(const QString &path)
{
    m_previewingPath = path;
    updateState();
}
void SampleLibraryPanel::togglePreview()
{
    showMessage(QString());
    if (!m_previewingPath.isEmpty()) {
        emit previewStopRequested();
        return;
    }
    const QString path = selectedPath();
    if (!path.isEmpty())
        emit previewRequested(path);
}
void SampleLibraryPanel::loadSelected()
{
    const QString path = selectedPath();
    if (!path.isEmpty()) {
        showMessage(QString());
        emit loadRequested(path);
    }
}
bool SampleLibraryPanel::eventFilter(QObject *watched, QEvent *event)
{
    if (watched == m_files &&
        (event->type() == QEvent::KeyPress || event->type() == QEvent::KeyRelease ||
         event->type() == QEvent::ShortcutOverride)) {
        auto *key = static_cast<QKeyEvent *>(event);
        if (key->modifiers() == Qt::NoModifier &&
            (key->key() == Qt::Key_Space || key->key() == Qt::Key_Return ||
             key->key() == Qt::Key_Enter)) {
            if (event->type() == QEvent::KeyPress && !key->isAutoRepeat())
                togglePreview();
            event->accept();
            return true;
        }
    }
    return QWidget::eventFilter(watched, event);
}
