#include "settingsdialog.h"

#include <QDialogButtonBox>
#include <QHBoxLayout>
#include <QPushButton>
#include <QTabWidget>
#include <QVBoxLayout>

#include "enginesettingsdialog.h"
#include "songsettingsdialog.h"

SettingsDialog::SettingsDialog(const EngineSettings &engineSettings,
                               const std::optional<SongTarget> &song,
                               const QStringList &voicegroupArgs, bool songFirst, QWidget *parent)
    : QDialog(parent)
{
    setWindowTitle(tr("Settings"));
    m_tabs = new QTabWidget(this);
    m_engineWidget = new EngineSettingsWidget(engineSettings, this);
    m_tabs->addTab(m_engineWidget, tr("Engine"));
    QWidget *songTab = nullptr;
    if (song) {
        m_songWidget = new SongSettingsWidget(song->cfg, voicegroupArgs, this);
        songTab = m_songWidget;
    } else {
        songTab = new QWidget(this);
    }
    const QString songTabTitle =
        song && !song->label.isEmpty() ? tr("Song (%1)").arg(song->label) : tr("Song");
    const int songTabIndex = m_tabs->addTab(songTab, songTabTitle);
    m_tabs->setTabEnabled(songTabIndex, song.has_value());
    m_tabs->setCurrentIndex(song && songFirst ? 1 : 0);
    auto *buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, this);
    auto *applyButton = new QPushButton(tr("Apply"), this);
    connect(buttons, &QDialogButtonBox::accepted, this, &QDialog::accept);
    connect(buttons, &QDialogButtonBox::rejected, this, &QDialog::reject);
    connect(applyButton, &QPushButton::clicked, this, &SettingsDialog::applyRequested);
    auto *layout = new QVBoxLayout(this);
    layout->addWidget(m_tabs);
    auto *buttonRow = new QHBoxLayout;
    buttonRow->addStretch();
    buttonRow->addWidget(applyButton);
    buttonRow->addWidget(buttons);
    layout->addLayout(buttonRow);
    resize(560, 580);
}

EngineSettings SettingsDialog::engineSettings() const
{
    return m_engineWidget->settings();
}

std::optional<SongCfg> SettingsDialog::songCfg() const
{
    if (!m_songWidget)
        return std::nullopt;
    return m_songWidget->cfg();
}
