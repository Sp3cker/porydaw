#include "songsettingsdialog.h"

#include "project/songregistry.h"

#include <QCheckBox>
#include <QComboBox>
#include <QFormLayout>
#include <QLabel>
#include <QLineEdit>
#include <QSpinBox>
#include <QVBoxLayout>

SongSettingsWidget::SongSettingsWidget(const SongCfg &cfg, const QStringList &voicegroupArgs,
                                       QWidget *parent)
    : QWidget(parent)
    , m_original(cfg)
    , m_voicegroupArgs(voicegroupArgs)
{
    auto *layout = new QVBoxLayout(this);
    auto *form = new QFormLayout;

    m_voicegroup = new QComboBox(this);
    m_voicegroup->setEditable(true);
    for (const QString &arg : m_voicegroupArgs)
        m_voicegroup->addItem(SongRegistry::voicegroupDisplayName(arg));
    m_voicegroup->setCurrentText(SongRegistry::voicegroupDisplayName(cfg.voicegroupArg));
    m_voicegroup->lineEdit()->setPlaceholderText(QStringLiteral("dummy"));
    m_voicegroup->setToolTip(tr("The symbol is \"voicegroup_\" + this name (mid2agb -G), "
                                "e.g. \"abandoned_ship\" → voicegroup_abandoned_ship."));
    form->addRow(tr("&Voicegroup:"), m_voicegroup);

    m_volume = new QSpinBox(this);
    m_volume->setRange(0, 127);
    m_volume->setValue(cfg.masterVolume);
    m_volume->setToolTip(tr("mid2agb -V: scales every track volume (VOL × master ÷ 128)."));
    form->addRow(tr("&Master volume (-V):"), m_volume);

    m_reverb = new QSpinBox(this);
    m_reverb->setRange(-1, 127);
    m_reverb->setSpecialValueText(tr("Default (%1)").arg(SongCfg::kDefaultReverb));
    m_reverb->setValue(cfg.reverb);
    m_reverb->setToolTip(tr("mid2agb -R: song reverb level. Default leaves -R unspecified (%1).")
                             .arg(SongCfg::kDefaultReverb));
    form->addRow(tr("&Reverb (-R):"), m_reverb);

    m_priority = new QSpinBox(this);
    m_priority->setRange(0, 127);
    m_priority->setValue(cfg.priority);
    m_priority->setToolTip(tr("mid2agb -P: player priority (fanfares interrupt music)."));
    form->addRow(tr("&Priority (-P):"), m_priority);

    m_exactGate = new QCheckBox(tr("Exact gate time (-E)"), this);
    m_exactGate->setChecked(cfg.exactGate);
    m_exactGate->setToolTip(
        tr("Keep note lengths exact instead of snapping through mid2agb's duration table."));

    m_extendedClocks = new QCheckBox(tr("48 clocks per beat (-X)"), this);
    m_extendedClocks->setChecked(cfg.extendedClocks);
    m_extendedClocks->setToolTip(tr("Doubles timing resolution (default is 24 clocks/beat)."));

    m_noCompression = new QCheckBox(tr("Disable compression (-N)"), this);
    m_noCompression->setChecked(cfg.noCompression);
    m_noCompression->setToolTip(tr("Skip mid2agb's repeated-pattern compression."));

    layout->addLayout(form);
    layout->addWidget(m_exactGate);
    layout->addWidget(m_extendedClocks);
    layout->addWidget(m_noCompression);

    auto *note = new QLabel(tr("Saved to this song's mid2agb flags (midi.cfg or songs.mk)."), this);
    note->setStyleSheet(QStringLiteral("color: gray;"));
    layout->addWidget(note);
    layout->addStretch(1);
}

SongCfg SongSettingsWidget::cfg() const
{
    SongCfg cfg = m_original; // keeps rawFlags and unknown options
    cfg.voicegroupArg = SongRegistry::voicegroupArgFromDisplay(
        m_voicegroup->currentText().trimmed(), m_voicegroupArgs);
    cfg.masterVolume = m_volume->value();
    cfg.reverb = m_reverb->value();
    cfg.priority = m_priority->value();
    cfg.exactGate = m_exactGate->isChecked();
    cfg.extendedClocks = m_extendedClocks->isChecked();
    cfg.noCompression = m_noCompression->isChecked();
    return cfg;
}
