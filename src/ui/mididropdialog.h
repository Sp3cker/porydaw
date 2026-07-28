#pragma once

#include <QDialog>

#include <cstdint>
#include <vector>

#include "core/midiimport.h"
#include "core/smf.h"

class QDialogButtonBox;
class QLabel;
class QListWidget;
class QListWidgetItem;
class QPushButton;
class QRadioButton;

class MidiDropDialog : public QDialog {
  Q_OBJECT

public:
  enum MidiDropDestination {
    Append,
    NewSong,
  };
  Q_ENUM(MidiDropDestination)

  MidiDropDialog(const SmfFile &smf, const std::vector<ImportTrackInfo> &tracks,
                 const QString &activeSongLabel, int appendCapacity,
                 int newSongCapacity, uint16_t activeSongDivision,
                 QWidget *parent = nullptr);

  MidiDropDestination destination() const;
  std::vector<int> selectedTracks() const;

private:
  int currentCapacity() const;
  void setDestination(MidiDropDestination destination);
  void selectPrefix();
  void updateSelectionState();
  void updateWarnings();

  const SmfFile &m_smf;
  std::vector<ImportTrackInfo> m_tracks;
  QString m_activeSongLabel;
  int m_appendCapacity = 0;
  int m_newSongCapacity = 0;
  uint16_t m_activeSongDivision = 0;
  MidiDropDestination m_destination = NewSong;
  QRadioButton *m_appendDestination = nullptr;
  QRadioButton *m_newSongDestination = nullptr;
  QLabel *m_appendReason = nullptr;
  QListWidget *m_trackList = nullptr;
  QLabel *m_selectionSummary = nullptr;
  QLabel *m_warningLabel = nullptr;
  QDialogButtonBox *m_buttonBox = nullptr;
};
