#pragma once

#include <QWidget>

class QLabel;
class QLineEdit;
class QPushButton;
class QTreeWidget;
class QTreeWidgetItem;

namespace scripting {

class ScriptHost;

// Settings → Plugins: every plugin found in the plugins folder with an
// enable checkbox (persisted, applies immediately), its state, and the
// reason when it failed to load; Reload / Reload All / Open Folder / Add
// Plugin… buttons; and the plugins folder itself (Change… / Use Default,
// applied and persisted at once; read-only while PORYDAW_PLUGINS_DIR
// overrides it).
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
    void applyFolder(const QString &dir);
    QString currentId() const;

    ScriptHost &m_host;
    QLineEdit *m_folder = nullptr;
    QPushButton *m_changeFolder = nullptr;
    QPushButton *m_defaultFolder = nullptr;
    QLabel *m_folderNote = nullptr;
    QTreeWidget *m_tree = nullptr;
    QLabel *m_detail = nullptr;
    QPushButton *m_reload = nullptr;
    QPushButton *m_reloadAll = nullptr;
    QPushButton *m_openFolder = nullptr;
    QPushButton *m_addPlugin = nullptr;
    bool m_rebuilding = false;
};

} // namespace scripting
