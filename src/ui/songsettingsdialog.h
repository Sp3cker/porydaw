#pragma once

#include <QWidget>

#include "project/decompproject.h"

class QCheckBox;
class QComboBox;
class QSpinBox;

// Song Settings (SPEC.md §6.1): the song's mid2agb flags from its midi.cfg
// line, presented as friendly controls. Committed via SongDocument::setCfg so
// the change is undoable; written back only to the song's midi.cfg line.
class SongSettingsWidget : public QWidget
{
    Q_OBJECT

  public:
    explicit SongSettingsWidget(const SongCfg &cfg, const QStringList &voicegroupArgs,
                                QWidget *parent = nullptr);

    SongCfg cfg() const;

  private:
    SongCfg m_original;
    QStringList m_voicegroupArgs;
    QComboBox *m_voicegroup = nullptr;
    QSpinBox *m_volume = nullptr;
    QSpinBox *m_reverb = nullptr;
    QSpinBox *m_priority = nullptr;
    QCheckBox *m_exactGate = nullptr;
    QCheckBox *m_extendedClocks = nullptr;
    QCheckBox *m_noCompression = nullptr;
};
