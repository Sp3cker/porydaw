#pragma once

#include <QWidget>

extern "C" {
#include "m4a/m4a_driver.h"
}

class QCheckBox;
class QComboBox;
class QSpinBox;

// m4aSoundInit's selectable DirectSound rates (SOUND_MODE_FREQ_*), shared
// with the Sample Editor target-rate presets.
extern const int kGbaMixRates[12];

// Global poryaaaa GBA-accuracy knobs (SPEC §7), persisted per user via
// QSettings. Unlike Song Settings these never touch the project; reverb
// stays per-song (midi.cfg -R).
struct EngineSettings {
    M4APcmMixerMode pcmMixer = M4A_PCM_MIXER_IPATIX;
    int maxPcmChannels = 5;      // pokeemerald m4aSoundInit default
    float pcmMixRate = 13379.0f; // GBA DirectSound rate; 0 = follow host rate
    bool analogFilter = false;   // GBA analog output low-pass; niche, off by default

    static EngineSettings load();
    void save() const;
};

class EngineSettingsWidget : public QWidget
{
    Q_OBJECT

  public:
    explicit EngineSettingsWidget(const EngineSettings &settings, QWidget *parent = nullptr);

    EngineSettings settings() const;
    void applyToWidgets(const EngineSettings &settings);

  private:
    QSpinBox *m_polyphony = nullptr;
    QComboBox *m_mixer = nullptr;
    QComboBox *m_mixRate = nullptr;
    QCheckBox *m_analogFilter = nullptr;
};
