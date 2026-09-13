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
    explicit SettingsDialog(const EngineSettings &engineSettings,
                            const std::optional<SongTarget> &song,
                            const QStringList &voicegroupArgs, bool songFirst = false,
                            QWidget *parent = nullptr);

    EngineSettings engineSettings() const;
    std::optional<SongCfg> songCfg() const;

  signals:
    void applyRequested();

  private:
    QTabWidget *m_tabs = nullptr;
    EngineSettingsWidget *m_engineWidget = nullptr;
    SongSettingsWidget *m_songWidget = nullptr;
};
