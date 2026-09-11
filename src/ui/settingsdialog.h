#pragma once

#include <QDialog>
#include <optional>

#include "enginesettingsdialog.h"
#include "project/decompproject.h"

class QTabWidget;
class EngineSettingsWidget;
class SongSettingsWidget;

struct SongTarget {
    SongCfg cfg;
    QString label;
};

class SettingsDialog : public QDialog
{
    Q_OBJECT

  public:
    enum class Tab {
        Engine,
        Song,
    };

    explicit SettingsDialog(const EngineSettings &engineSettings,
                            const std::optional<SongTarget> &song,
                            const QStringList &voicegroupArgs, Tab initialTab = Tab::Engine,
                            QWidget *parent = nullptr);

    EngineSettings engineSettings() const;
    std::optional<SongCfg> songCfg() const;

    Tab currentTab() const;
    void setCurrentTab(Tab tab);

  signals:
    void applyRequested();

  private:
    void apply();
    QTabWidget *m_tabs = nullptr;
    EngineSettingsWidget *m_engineWidget = nullptr;
    QWidget *m_songTab = nullptr;
    SongSettingsWidget *m_songWidget = nullptr;
};
