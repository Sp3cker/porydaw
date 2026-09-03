#include "pluginspage.h"

#include <QDesktopServices>
#include <QDir>
#include <QHBoxLayout>
#include <QHeaderView>
#include <QLabel>
#include <QPushButton>
#include <QTreeWidget>
#include <QUrl>
#include <QVBoxLayout>

#include "scripthost.h"
#include "ui/layout.h"

namespace scripting {

namespace {
constexpr int kIdRole = Qt::UserRole;
} // namespace

PluginsPage::PluginsPage(ScriptHost &host, QWidget *parent) : QWidget(parent), m_host(host)
{
    m_folder = new QLabel(this);
    m_folder->setObjectName(QStringLiteral("settingsPluginsFolder"));
    m_folder->setTextInteractionFlags(Qt::TextSelectableByMouse);
    m_folder->setWordWrap(true);

    m_tree = new QTreeWidget(this);
    m_tree->setObjectName(QStringLiteral("settingsPluginsTree"));
    m_tree->setColumnCount(3);
    m_tree->setHeaderLabels({tr("Plugin"), tr("Version"), tr("Status")});
    m_tree->setRootIsDecorated(false);
    m_tree->setSelectionMode(QAbstractItemView::SingleSelection);
    m_tree->setAllColumnsShowFocus(true);
    m_tree->header()->setStretchLastSection(true);
    m_tree->setMinimumHeight(::layout::fontPx(12));

    m_detail = new QLabel(this);
    m_detail->setObjectName(QStringLiteral("settingsPluginsDetail"));
    m_detail->setWordWrap(true);
    m_detail->setTextInteractionFlags(Qt::TextSelectableByMouse);

    m_reload = new QPushButton(tr("Reload"), this);
    m_reload->setObjectName(QStringLiteral("settingsPluginsReload"));
    m_reloadAll = new QPushButton(tr("Reload All"), this);
    m_reloadAll->setObjectName(QStringLiteral("settingsPluginsReloadAll"));
    m_openFolder = new QPushButton(tr("Open Plugins Folder"), this);
    m_openFolder->setObjectName(QStringLiteral("settingsPluginsOpenFolder"));

    auto *buttons = new QHBoxLayout;
    buttons->addWidget(m_reload);
    buttons->addWidget(m_reloadAll);
    buttons->addStretch(1);
    buttons->addWidget(m_openFolder);

    auto *layout = new QVBoxLayout(this);
    layout->addWidget(m_folder);
    layout->addWidget(m_tree, 1);
    layout->addWidget(m_detail);
    layout->addLayout(buttons);

    // Queued: pluginsChanged fires synchronously from setEnabled(), which
    // the checkbox's own itemChanged handler calls — a direct rebuild
    // would clear the tree while that item's setData frame is live.
    connect(&m_host, &ScriptHost::pluginsChanged, this, &PluginsPage::rebuild,
            Qt::QueuedConnection);
    connect(m_tree, &QTreeWidget::currentItemChanged, this, [this] { updateDetail(); });
    connect(m_tree, &QTreeWidget::itemChanged, this, [this](QTreeWidgetItem *item, int column) {
        if (m_rebuilding || column != 0)
            return;
        m_host.setEnabled(item->data(0, kIdRole).toString(), item->checkState(0) == Qt::Checked);
    });
    connect(m_reload, &QPushButton::clicked, this, [this] {
        const QString id = currentId();
        if (!id.isEmpty())
            m_host.reload(id);
    });
    connect(m_reloadAll, &QPushButton::clicked, this, [this] { m_host.loadAll(); });
    connect(m_openFolder, &QPushButton::clicked, this, [this] {
        QDir().mkpath(m_host.pluginsDir());
        QDesktopServices::openUrl(QUrl::fromLocalFile(m_host.pluginsDir()));
    });
    rebuild();
}

QString PluginsPage::currentId() const
{
    const QTreeWidgetItem *item = m_tree->currentItem();
    return item ? item->data(0, kIdRole).toString() : QString();
}

QTreeWidgetItem *PluginsPage::itemFor(const QString &pluginId) const
{
    for (int i = 0; i < m_tree->topLevelItemCount(); ++i) {
        if (m_tree->topLevelItem(i)->data(0, kIdRole).toString() == pluginId)
            return m_tree->topLevelItem(i);
    }
    return nullptr;
}

void PluginsPage::rebuild()
{
    m_rebuilding = true;
    const QString selected = currentId();
    m_folder->setText(tr("Plugins load from %1 — one folder per plugin, each with a "
                         "plugin.json. Edits reload automatically.")
                          .arg(QDir::toNativeSeparators(m_host.pluginsDir())));
    m_tree->clear();
    QTreeWidgetItem *reselect = nullptr;
    for (const QString &id : m_host.pluginIds()) {
        const Plugin *plugin = m_host.plugin(id);
        if (!plugin)
            continue;
        QString status;
        switch (plugin->state) {
        case PluginState::Loaded:
            status = tr("Loaded");
            break;
        case PluginState::Disabled:
            status = plugin->enabled ? tr("Not loaded") : tr("Disabled");
            break;
        case PluginState::Error:
            status = tr("Error");
            break;
        }
        auto *item =
            new QTreeWidgetItem(m_tree, {plugin->manifest.name, plugin->manifest.version, status});
        item->setData(0, kIdRole, id);
        item->setToolTip(0, id);
        item->setFlags(item->flags() | Qt::ItemIsUserCheckable);
        item->setCheckState(0, plugin->enabled ? Qt::Checked : Qt::Unchecked);
        if (plugin->state == PluginState::Error)
            item->setForeground(2, QColor(0xd0, 0x40, 0x40));
        if (id == selected)
            reselect = item;
    }
    m_tree->resizeColumnToContents(0);
    m_tree->resizeColumnToContents(1);
    if (reselect)
        m_tree->setCurrentItem(reselect);
    else if (m_tree->topLevelItemCount() > 0)
        m_tree->setCurrentItem(m_tree->topLevelItem(0));
    m_rebuilding = false;
    updateDetail();
}

void PluginsPage::updateDetail()
{
    const Plugin *plugin = m_host.plugin(currentId());
    m_reload->setEnabled(plugin != nullptr);
    if (!plugin) {
        m_detail->setText(m_host.pluginIds().isEmpty()
                              ? tr("No plugins installed. Drop a plugin folder into the plugins "
                                   "folder above and it appears here.")
                              : QString());
        return;
    }
    QString text = plugin->manifest.description;
    if (plugin->state == PluginState::Error && !plugin->error.isEmpty())
        text = (text.isEmpty() ? QString() : text + QLatin1Char('\n')) + plugin->error;
    m_detail->setText(text);
}

} // namespace scripting
