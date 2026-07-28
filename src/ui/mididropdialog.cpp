#include "mididropdialog.h"

#include <QAbstractButton>
#include <QDialogButtonBox>
#include <QGroupBox>
#include <QHBoxLayout>
#include <QLabel>
#include <QListWidget>
#include <QPushButton>
#include <QRadioButton>
#include <QSignalBlocker>
#include <QVBoxLayout>

#include <algorithm>

MidiDropDialog::MidiDropDialog(const SmfFile &smf,
                               const std::vector<ImportTrackInfo> &tracks,
                               const QString &activeSongLabel,
                               int appendCapacity, int newSongCapacity,
                               uint16_t activeSongDivision, QWidget *parent)
    : QDialog(parent), m_smf(smf), m_tracks(tracks),
      m_activeSongLabel(activeSongLabel),
      m_appendCapacity(std::max(0, appendCapacity)),
      m_newSongCapacity(std::max(0, newSongCapacity)),
      m_activeSongDivision(activeSongDivision) {
  setObjectName(QStringLiteral("midiDropDialog"));
  setWindowTitle(tr("Import MIDI"));
  setModal(true);

  auto *layout = new QVBoxLayout(this);
  auto *intro = new QLabel(
      tr("Choose the note-bearing tracks to import and where they should go."),
      this);
  intro->setWordWrap(true);
  layout->addWidget(intro);

  if (!m_activeSongLabel.isEmpty()) {
    auto *destinationBox = new QGroupBox(tr("Destination"), this);
    auto *destinationLayout = new QVBoxLayout(destinationBox);
    m_appendDestination = new QRadioButton(
        tr("Append to active song (%1)").arg(m_activeSongLabel),
        destinationBox);
    m_appendDestination->setObjectName(QStringLiteral("appendDestination"));
    m_newSongDestination =
        new QRadioButton(tr("Create a new song"), destinationBox);
    m_newSongDestination->setObjectName(QStringLiteral("newSongDestination"));
    destinationLayout->addWidget(m_appendDestination);
    destinationLayout->addWidget(m_newSongDestination);
    m_appendReason = new QLabel(destinationBox);
    m_appendReason->setWordWrap(true);
    m_appendReason->setStyleSheet(QStringLiteral("color: #c08030;"));
    destinationLayout->addWidget(m_appendReason);
    layout->addWidget(destinationBox);

    connect(m_appendDestination, &QRadioButton::toggled, this,
            [this](bool checked) {
              if (checked)
                setDestination(Append);
            });
    connect(m_newSongDestination, &QRadioButton::toggled, this,
            [this](bool checked) {
              if (checked)
                setDestination(NewSong);
            });
    m_appendDestination->setEnabled(m_appendCapacity > 0);
    m_newSongDestination->setEnabled(m_newSongCapacity > 0);
    QSignalBlocker appendBlocker(m_appendDestination);
    QSignalBlocker newSongBlocker(m_newSongDestination);
    if (m_appendCapacity > 0) {
      m_appendReason->clear();
      m_appendDestination->setChecked(true);
      m_newSongDestination->setChecked(false);
      m_destination = Append;
    } else if (m_newSongCapacity > 0) {
      m_appendReason->setText(
          tr("The active song has no free track slots; choose a new song."));
      m_appendDestination->setChecked(false);
      m_newSongDestination->setChecked(true);
      m_destination = NewSong;
    } else {
      m_appendReason->setText(
          tr("No destination is available for the selected MIDI tracks."));
      m_appendDestination->setChecked(false);
      m_newSongDestination->setChecked(false);
      m_destination = NewSong;
    }
  } else {
    m_destination = NewSong;
  }

  m_trackList = new QListWidget(this);
  m_trackList->setObjectName(QStringLiteral("trackList"));
  m_trackList->setUniformItemSizes(true);
  m_trackList->setSelectionMode(QAbstractItemView::NoSelection);
  for (const ImportTrackInfo &track : m_tracks) {
    const QString name =
        track.name.trimmed().isEmpty() ? tr("Unnamed") : track.name.trimmed();
    QStringList channels;
    for (const uint8_t channel : track.channels)
      channels.append(QString::number(int(channel) + 1));
    const QString channelText =
        channels.isEmpty() ? tr("none") : channels.join(QStringLiteral(", "));
    auto *item =
        new QListWidgetItem(tr("Track %1 — %2 · Channels %3 · %4 note(s)")
                                .arg(track.smfTrack + 1)
                                .arg(name)
                                .arg(channelText)
                                .arg(track.noteCount),
                            m_trackList);
    item->setData(Qt::UserRole, track.smfTrack);
    if (m_tracks.size() >= 2) {
      item->setFlags(item->flags() | Qt::ItemIsUserCheckable);
      item->setCheckState(Qt::Unchecked);
    } else {
      item->setFlags(item->flags() & ~Qt::ItemIsUserCheckable);
    }
  }
  layout->addWidget(m_trackList, 1);

  if (m_tracks.size() >= 2) {
    auto *selectionButtons = new QHBoxLayout;
    auto *selectAll = new QPushButton(tr("Select All"), this);
    selectAll->setObjectName(QStringLiteral("selectAllTracks"));
    auto *clearAll = new QPushButton(tr("Clear All"), this);
    clearAll->setObjectName(QStringLiteral("clearAllTracks"));
    selectionButtons->addWidget(selectAll);
    selectionButtons->addWidget(clearAll);
    selectionButtons->addStretch(1);
    layout->addLayout(selectionButtons);
    connect(selectAll, &QPushButton::clicked, this,
            &MidiDropDialog::selectPrefix);
    connect(clearAll, &QPushButton::clicked, this, [this] {
      QSignalBlocker blocker(m_trackList);
      for (int row = 0; row < m_trackList->count(); ++row)
        m_trackList->item(row)->setCheckState(Qt::Unchecked);
      updateSelectionState();
    });
    connect(m_trackList, &QListWidget::itemChanged, this,
            [this](QListWidgetItem *) { updateSelectionState(); });
  }

  m_selectionSummary = new QLabel(this);
  m_selectionSummary->setWordWrap(true);
  layout->addWidget(m_selectionSummary);
  m_warningLabel = new QLabel(this);
  m_warningLabel->setObjectName(QStringLiteral("importWarnings"));
  m_warningLabel->setWordWrap(true);
  m_warningLabel->setStyleSheet(QStringLiteral("color: #c08030;"));
  layout->addWidget(m_warningLabel);

  m_buttonBox = new QDialogButtonBox(
      QDialogButtonBox::Ok | QDialogButtonBox::Cancel, this);
  m_buttonBox->button(QDialogButtonBox::Ok)->setText(tr("Import"));
  layout->addWidget(m_buttonBox);
  connect(m_buttonBox, &QDialogButtonBox::accepted, this, &QDialog::accept);
  connect(m_buttonBox, &QDialogButtonBox::rejected, this, &QDialog::reject);
  if (m_tracks.size() >= 2)
    selectPrefix();
  else
    updateSelectionState();
}

MidiDropDialog::MidiDropDestination MidiDropDialog::destination() const {
  return m_destination;
}

std::vector<int> MidiDropDialog::selectedTracks() const {
  std::vector<int> selected;
  if (m_tracks.size() == 1) {
    selected.push_back(m_tracks.front().smfTrack);
    return selected;
  }
  for (int row = 0; row < m_trackList->count(); ++row) {
    const QListWidgetItem *item = m_trackList->item(row);
    if (item->checkState() == Qt::Checked)
      selected.push_back(item->data(Qt::UserRole).toInt());
  }
  return selected;
}

int MidiDropDialog::currentCapacity() const {
  return m_destination == Append ? m_appendCapacity : m_newSongCapacity;
}

void MidiDropDialog::setDestination(MidiDropDestination destination) {
  const bool appendAvailable = m_appendDestination &&
                               m_appendDestination->isEnabled() &&
                               m_appendCapacity > 0;
  const bool newSongAvailable = m_newSongDestination
                                    ? m_newSongDestination->isEnabled()
                                    : m_newSongCapacity > 0;
  if (destination == Append && !appendAvailable)
    destination = NewSong;
  if (destination == NewSong && !newSongAvailable) {
    if (!appendAvailable)
      return;
    destination = Append;
  }
  m_destination = destination;
  if (m_appendDestination)
    m_appendDestination->setChecked(destination == Append);
  if (m_newSongDestination)
    m_newSongDestination->setChecked(destination == NewSong);
  if (m_tracks.size() >= 2)
    selectPrefix();
  updateSelectionState();
}

void MidiDropDialog::selectPrefix() {
  if (m_tracks.size() < 2)
    return;
  const int count = std::min(currentCapacity(), m_trackList->count());
  QSignalBlocker blocker(m_trackList);
  for (int row = 0; row < m_trackList->count(); ++row)
    m_trackList->item(row)->setCheckState(row < count ? Qt::Checked
                                                      : Qt::Unchecked);
  updateSelectionState();
}

void MidiDropDialog::updateSelectionState() {
  const int count = int(selectedTracks().size());
  const int capacity = currentCapacity();
  m_selectionSummary->setText(
      tr("Selected %1 track(s); capacity %2.").arg(count).arg(capacity));
  const bool valid = count > 0 && count <= capacity;
  m_buttonBox->button(QDialogButtonBox::Ok)->setEnabled(valid);
  updateWarnings();
}

void MidiDropDialog::updateWarnings() {
  if (destination() != Append) {
    m_warningLabel->clear();
    m_warningLabel->hide();
    return;
  }

  const std::vector<int> selected = selectedTracks();
  if (selected.empty()) {
    m_warningLabel->clear();
    m_warningLabel->hide();
    return;
  }
  QStringList warnings;
  QStringList programs;
  bool notesBeforeProgram = false;
  for (const ImportTrackInfo &track : m_tracks) {
    if (std::find(selected.begin(), selected.end(), track.smfTrack) ==
        selected.end())
      continue;
    for (const uint8_t program : track.programs) {
      const QString text = QString::number(program);
      if (!programs.contains(text))
        programs.append(text);
    }
    notesBeforeProgram = notesBeforeProgram || track.notesBeforeProgram;
  }
  if (!programs.isEmpty())
    warnings.append(tr("Program numbers %1 address active voicegroup slots.")
                        .arg(programs.join(QStringLiteral(", "))));
  if (notesBeforeProgram)
    warnings.append(
        tr("Some notes occur before a program change and use voice slot 0."));

  if (!selected.empty()) {
    const SmfFile selectedSmf = selectedMidiForAppend(m_smf, selected);
    const ImportAnalysis analysis = analyzeForImport(selectedSmf);
    QStringList silentControllers;
    for (const ImportCcUsage &cc : analysis.ccs) {
      if (!cc.audible)
        silentControllers.append(tr("CC %1").arg(cc.cc));
    }
    if (!silentControllers.isEmpty())
      warnings.append(tr("Kept-but-silent controllers: %1.")
                          .arg(silentControllers.join(QStringLiteral(", "))));
  }
  if (m_activeSongDivision != 0 && m_smf.division != m_activeSongDivision)
    warnings.append(
        tr("Source division %1 differs from the active song's division %2; "
           "timing will be rescaled on append.")
            .arg(m_smf.division)
            .arg(m_activeSongDivision));

  m_warningLabel->setText(warnings.join(QStringLiteral("\n")));
  m_warningLabel->setVisible(!warnings.isEmpty());
}
