#include "settingsdialog.h"

#include <QDialogButtonBox>
#include <QHBoxLayout>
#include <QPushButton>
#include <QTabWidget>
#include <QVBoxLayout>

#include "enginesettingsdialog.h"
#include "keyboardshortcutsdialog.h"
#include "songsettingsdialog.h"

SettingsDialog::SettingsDialog(const EngineSettings &engineSettings,
                               const std::optional<SongTarget> &song,
                               const QStringList &voicegroupArgs, Tab initialTab, QWidget *parent)
    : QDialog(parent)
    , m_keymapSnapshot(keymap::Registry::instance().snapshotOverrides())
{
    setWindowTitle(tr("Settings"));
    m_tabs = new QTabWidget(this);
    m_engineWidget = new EngineSettingsWidget(engineSettings, this);
    m_tabs->addTab(m_engineWidget, tr("Engine"));
    if (song) {
        m_songWidget = new SongSettingsWidget(song->cfg, voicegroupArgs, this);
        m_songTab = m_songWidget;
    } else {
        m_songTab = new QWidget(this);
    }
    const QString songTabTitle =
        song && !song->label.isEmpty() ? tr("Song (%1)").arg(song->label) : tr("Song");
    const int songTabIndex = m_tabs->addTab(m_songTab, songTabTitle);
    m_tabs->setTabEnabled(songTabIndex, song.has_value());
    m_keyboardWidget = new KeyboardShortcutsWidget(this);
    m_tabs->addTab(m_keyboardWidget, tr("Keyboard"));
    setCurrentTab(initialTab);
    auto *buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, this);
    auto *applyButton = new QPushButton(tr("Apply"), this);
    connect(buttons, &QDialogButtonBox::accepted, this, &QDialog::accept);
    connect(buttons, &QDialogButtonBox::rejected, this, &SettingsDialog::reject);
    connect(applyButton, &QPushButton::clicked, this, &SettingsDialog::apply);
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

SettingsDialog::Tab SettingsDialog::currentTab() const
{
    const QWidget *current = m_tabs->currentWidget();
    if (current == m_engineWidget)
        return Tab::Engine;
    if (current == m_songTab)
        return Tab::Song;
    Q_ASSERT(current == m_keyboardWidget);
    return Tab::Keyboard;
}

void SettingsDialog::setCurrentTab(Tab tab)
{
    switch (tab) {
    case Tab::Engine:
        m_tabs->setCurrentWidget(m_engineWidget);
        break;
    case Tab::Song:
        if (m_songWidget)
            m_tabs->setCurrentWidget(m_songTab);
        break;
    case Tab::Keyboard:
        m_tabs->setCurrentWidget(m_keyboardWidget);
        break;
    }
}

void SettingsDialog::apply()
{
    m_keymapSnapshot = keymap::Registry::instance().snapshotOverrides();
    emit applyRequested();
}

void SettingsDialog::reject()
{
    if (m_keymapSnapshot) {
        keymap::Registry::instance().restoreOverrides(*m_keymapSnapshot);
        m_keymapSnapshot.reset();
    }
    QDialog::reject();
}
