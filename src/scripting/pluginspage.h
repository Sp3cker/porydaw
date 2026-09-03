#pragma once

#include <QWidget>

class QLabel;
class QPushButton;
class QTreeWidget;
class QTreeWidgetItem;

namespace scripting {

class ScriptHost;

// Settings → Plugins: every plugin found in the plugins folder with an
// enable checkbox (persisted, applies immediately), its state, and the
// reason when it failed to load; Reload / Open Folder buttons.
class PluginsPage : public QWidget
{
    Q_OBJECT
  public:
    explicit PluginsPage(ScriptHost &host, QWidget *parent = nullptr);

    QTreeWidget *tree() const { return m_tree; }
    QTreeWidgetItem *itemFor(const QString &pluginId) const;

  private:
    void rebuild();
    void updateDetail();
    QString currentId() const;

    ScriptHost &m_host;
    QLabel *m_folder = nullptr;
    QTreeWidget *m_tree = nullptr;
    QLabel *m_detail = nullptr;
    QPushButton *m_reload = nullptr;
    QPushButton *m_reloadAll = nullptr;
    QPushButton *m_openFolder = nullptr;
    bool m_rebuilding = false;
};

} // namespace scripting
