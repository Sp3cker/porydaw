#include "rollcheckpsgvelocity.h"
#include "rollcheckpsgvelocitymixed.h"

#include <QApplication>
#include <QCoreApplication>
#include <QEvent>
#include <QMouseEvent>

#include <QRectF>
#include <QWidget>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <optional>
#include <utility>
#include <vector>

#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/velocityarea.h"

namespace {

void sendMouse(QWidget *widget, QEvent::Type type, QPoint position,
               Qt::MouseButton button, Qt::MouseButtons buttons) {
  QMouseEvent event(type, QPointF(position),
                    QPointF(widget->mapToGlobal(position)), button, buttons,
                    Qt::NoModifier);
  QCoreApplication::sendEvent(widget, &event);
}

void click(QWidget *widget, QPoint position) {
  sendMouse(widget, QEvent::MouseButtonPress, position, Qt::LeftButton,
            Qt::LeftButton);
  sendMouse(widget, QEvent::MouseButtonRelease, position, Qt::LeftButton,
            Qt::NoButton);
}

struct SnappedRows {
  const SongView &view;
  const QWidget &roll;

  qreal dpr() const { return roll.devicePixelRatioF(); }
  qreal pixel() const { return 1.0 / dpr(); }
  qreal edge(int row) const {
    return std::round((row * view.keyHeight() - view.scrollY()) * dpr()) /
           dpr();
  }
  qreal top(int key) const { return edge(127 - key); }
  qreal bottom(int key) const { return edge(128 - key); }
  int centerY(int key) const {
    return int(std::floor((top(key) + bottom(key)) / 2));
  }
  QRectF noteRect(int x0, int x1, int key) const {
    return QRectF(x0, top(key) + pixel(), std::max(2, x1 - x0),
                  std::max(2.0 * pixel(), bottom(key) - top(key) - pixel()));
  }
};

struct Cell {
  uint64_t tick = 0;
  uint64_t dur = 0;
  int key = -1;
  QPoint center;
};

} // namespace

int runRollCheckPsgVelocity(const RollCheckPsgVelocityContext &context) {
  SongDocument &doc = context.document;
  SongView &view = context.view;
  const LoadedVoiceGroup *const voicegroup = context.voicegroup;
  const QString &songLabel = context.songLabel;
  const int track = context.track;
  auto *roll = view.findChild<QWidget *>(QStringLiteral("pianoRoll"));
  const SnappedRows rows{view, *roll};
  int failures = 0;
  const auto fail = [&](const char *what) {
    std::fprintf(stderr, "rollcheck: FAIL %s: %s\n", qUtf8Printable(songLabel),
                 what);
    ++failures;
  };
  const auto occupied = [&](uint64_t tick, uint64_t dur, int key,
                            bool checkAllTracks) {
    const int startTrack = checkAllTracks ? 0 : track;
    const int endTrack = checkAllTracks ? doc.engineTrackCount() : track + 1;
    for (int candidateTrack = startTrack; candidateTrack < endTrack;
         ++candidateTrack) {
      for (const DocNote &note : doc.notesForTrack(candidateTrack)) {
        if (int(note.key) != key)
          continue;
        const uint64_t end =
            note.unterminated() ? UINT64_MAX : note.tick + note.duration + dur;
        if (note.tick < tick + 2 * dur && end > tick)
          return true;
      }
    }
    return false;
  };
  const auto findFreeCell = [&](int firstProbe, bool checkAllTracks,
                                bool requireClearControls) {
    Cell cell;
    for (int key = 115; key >= 24; --key) {
      const qreal top = rows.top(key);
      const qreal bottom = rows.bottom(key);
      if (top < 0 || bottom > roll->height())
        continue;
      for (int probe = firstProbe;
           probe < roll->width() - songview::kKeyboardW - 40; probe += 24) {
        const uint64_t tick = view.snapTickDown(view.tickAtContentX(probe));
        const uint64_t dur = view.gridTicksAt(tick);
        const int x0 = songview::kKeyboardW + view.contentX(double(tick));
        const int x1 = songview::kKeyboardW + view.contentX(double(tick + dur));
        const int xs = songview::kKeyboardW +
                       view.contentX(double(tick + view.snapTicksAt(tick)));
        if (x0 < songview::kKeyboardW || x1 - x0 < 12 || xs - x0 < 8 ||
            x1 >= roll->width() || occupied(tick, dur, key, checkAllTracks)) {
          continue;
        }
        if (requireClearControls) {
          DocLanePoint point;
          if (doc.findLanePoint(track, DOC_CC_VOICE, tick, &point) ||
              doc.findLanePoint(track, 0x07, tick, &point) ||
              doc.findLanePoint(track, 0x0A, tick, &point)) {
            continue;
          }
        }
        cell.tick = tick;
        cell.dur = dur;
        cell.key = key;
        cell.center = QPoint((x0 + xs) / 2, rows.centerY(key));
        return cell;
      }
    }
    return cell;
  };

  // Hardware velocity detents are per resolved voice, not per selection:
  // one mixed drag must write each note's exact canonical value in one
  // undo command. Keep the real voicegroup attached only for this isolated
  // pass so the earlier generic gesture checks retain their original setup.
  {
    enum class DetentFamily { Wave, Cgb16, Pcm };
    struct SlotCase {
      DetentFamily family;
      int slot;
    };
    struct NoteCase {
      DetentFamily family;
      Cell cell;
    };

    int waveSlot = -1;
    int cgb16Slot = -1;
    int pcmSlot = -1;
    for (int slot = 0; slot < VOICEGROUP_SIZE; slot++) {
      const ToneData &tone = voicegroup->voices[slot];
      const uint8_t type = tone.type;
      if (type & (VOICE_KEYSPLIT | VOICE_KEYSPLIT_ALL))
        continue;
      const int cgbType = type & VOICE_TYPE_CGB_MASK;
      if (waveSlot < 0 && cgbType == VOICE_PROGRAMMABLE_WAVE &&
          tone.wavePointer) {
        waveSlot = slot;
      } else if (cgbType == VOICE_SQUARE_1) {
        cgb16Slot = slot;
      } else if (cgb16Slot < 0 &&
                 (cgbType == VOICE_SQUARE_2 || cgbType == VOICE_NOISE)) {
        cgb16Slot = slot;
      } else if (pcmSlot < 0 &&
                 (type == VOICE_DIRECTSOUND ||
                  type == VOICE_DIRECTSOUND_NO_RESAMPLE ||
                  type == VOICE_DIRECTSOUND_ALT) &&
                 tone.wav && tone.wav->size > 0) {
        pcmSlot = slot;
      }
    }

    std::vector<SlotCase> slotCases;
    if (waveSlot >= 0) {
      slotCases.push_back({DetentFamily::Wave, waveSlot});
    } else {
      std::printf("rollcheck: SKIP %s programmable-wave velocity detents "
                  "(no usable top-level slot)\n",
                  qUtf8Printable(songLabel));
    }
    if (cgb16Slot >= 0) {
      slotCases.push_back({DetentFamily::Cgb16, cgb16Slot});
    } else {
      std::printf("rollcheck: SKIP %s square/noise velocity detents "
                  "(no usable top-level slot)\n",
                  qUtf8Printable(songLabel));
    }
    if (pcmSlot >= 0) {
      slotCases.push_back({DetentFamily::Pcm, pcmSlot});
    } else {
      std::printf("rollcheck: SKIP %s DirectSound velocity continuity "
                  "(no usable top-level slot)\n",
                  qUtf8Printable(songLabel));
    }

    const int setupIndex = doc.undoStack()->index();
    const QByteArray setupBaseline = doc.smf().write();
    const int setupMaster = doc.cfg().masterVolume;
    view.setVoicegroup(voicegroup);

    std::vector<NoteCase> notes;
    if (!slotCases.empty()) {
      SongCfg fullVolume = doc.cfg();
      fullVolume.masterVolume = 127;
      doc.setCfg(fullVolume);

      for (const SlotCase &slot : slotCases) {
        const Cell cell = findFreeCell(8, false, true);
        if (cell.key < 0) {
          fail("no free grid cell for the velocity-detent batch");
          break;
        }
        // Override any earlier track state at the note's tick: these
        // are the mp2k defaults used by the canonical expectations.
        doc.addLanePoint(track, DOC_CC_VOICE, cell.tick, slot.slot);
        doc.addLanePoint(track, 0x07, cell.tick, 127);
        doc.addLanePoint(track, 0x0A, cell.tick, 64);
        doc.addNote(track, cell.tick, uint8_t(cell.key), uint32_t(cell.dur),
                    64);
        DocNote placed;
        if (!doc.findNote(track, cell.tick, uint8_t(cell.key), &placed) ||
            placed.velocity != 64) {
          fail("velocity-detent setup did not place its note");
          break;
        }
        notes.push_back({slot.family, cell});
      }
    }

    auto dragVelocity = [&](const NoteCase &note, int startVelocity,
                            int delta) {
      const QRectF rowRect = rows.noteRect(0, 1, note.cell.key);
      const QPoint handle(
          note.cell.center.x(),
          qRound(songview::velBarRect(rowRect, startVelocity, rows.dpr())
                     .center()
                     .y()));
      const QPoint target = handle - QPoint(0, delta);
      sendMouse(roll, QEvent::MouseButtonPress, handle, Qt::LeftButton,
                Qt::LeftButton);
      sendMouse(roll, QEvent::MouseMove, target, Qt::NoButton, Qt::LeftButton);
      sendMouse(roll, QEvent::MouseButtonRelease, target, Qt::LeftButton,
                Qt::NoButton);
    };

    if (!notes.empty()) {
      const auto initialSquare =
          std::find_if(notes.begin(), notes.end(), [](const NoteCase &note) {
            return note.family == DetentFamily::Cgb16;
          });
      if (initialSquare != notes.end()) {
        const SongView::DrawerPage initialDrawerPage = view.drawerPage();
        const bool initialDrawerVisible = view.drawerVisible();
        const SongCfg initialOpenFullVolume = doc.cfg();
        SongCfg initialOpenReducedVolume = initialOpenFullVolume;
        initialOpenReducedVolume.masterVolume = 50;
        doc.setCfg(initialOpenReducedVolume);
        view.setDrawerVisible(false);
        view.setDrawerPage(SongView::DrawerPage::Velocity);
        view.setEditCursorTick(initialSquare->cell.tick);
        view.clearSelection();
        view.setDrawerVisible(true);
        (void)view.grab();
        QCoreApplication::processEvents();
        auto *initialVelocityArea = static_cast<songview::VelocityArea *>(
            view.findChild<QWidget *>(QStringLiteral("velocityArea")));
        if (!initialVelocityArea) {
          fail("newly opened Square 1 velocity pane was unavailable");
        } else {
          QEvent leaveVelocityArea(QEvent::Leave);
          QApplication::sendEvent(initialVelocityArea, &leaveVelocityArea);

          const auto initialMaximumLevel =
              view.noteVelocityLevel(track, initialSquare->cell.tick,
                                     uint8_t(initialSquare->cell.key), 127);
          if (!initialMaximumLevel ||
              !initialVelocityArea->accessibleDescription().contains(
                  QStringLiteral("%1 levels")
                      .arg(int(*initialMaximumLevel) + 1))) {
            fail("idle velocity pane at Square 1 edit cursor did not supply "
                 "velocity graduations");
          }

          const auto initialPcm =
              std::find_if(notes.begin(), notes.end(), [](const NoteCase &note) {
                return note.family == DetentFamily::Pcm;
              });
          if (initialPcm != notes.end()) {
            view.setEditCursorTick(initialPcm->cell.tick);
            (void)initialVelocityArea->grab();
            QCoreApplication::processEvents();
            if (initialVelocityArea->accessibleDescription() !=
                QStringLiteral("Velocity")) {
              fail("stopped edit cursor at DirectSound note did not resolve "
                   "continuous velocity graduations");
            }
          }

          const auto initialWave =
              std::find_if(notes.begin(), notes.end(), [](const NoteCase &note) {
                return note.family == DetentFamily::Wave;
              });
          if (initialWave != notes.end()) {
            view.setEditCursorTick(initialWave->cell.tick);
            (void)initialVelocityArea->grab();
            QCoreApplication::processEvents();
            const auto waveMaxLevel =
                view.noteVelocityLevel(track, initialWave->cell.tick,
                                       uint8_t(initialWave->cell.key), 127);
            if (!waveMaxLevel ||
                !initialVelocityArea->accessibleDescription().contains(
                    QStringLiteral("%1 levels")
                        .arg(int(*waveMaxLevel) + 1))) {
              fail("stopped edit cursor at programmable-wave note did not "
                   "resolve wave velocity graduations");
            }
          }

          if (view.timeline()) {
            const uint64_t otherTick =
                initialPcm != notes.end() ? initialPcm->cell.tick : 0;
            view.setEditCursorTick(otherTick);

            const uint64_t squareSample =
                view.timeline()->sampleForTick(initialSquare->cell.tick);
            view.setPlayheadSample(squareSample, true);
            (void)initialVelocityArea->grab();
            QCoreApplication::processEvents();
            if (!initialMaximumLevel ||
                !initialVelocityArea->accessibleDescription().contains(
                    QStringLiteral("%1 levels")
                        .arg(int(*initialMaximumLevel) + 1))) {
              fail("playing playhead at Square 1 note did not resolve square "
                   "velocity graduations");
            }

            if (initialPcm != notes.end()) {
              const uint64_t pcmSample =
                  view.timeline()->sampleForTick(initialPcm->cell.tick);
              view.setPlayheadSample(pcmSample, true);
              (void)initialVelocityArea->grab();
              QCoreApplication::processEvents();
              if (initialVelocityArea->accessibleDescription() !=
                  QStringLiteral("Velocity")) {
                fail("playing playhead at DirectSound note did not resolve "
                     "continuous velocity graduations");
              }
            }

            if (initialWave != notes.end()) {
              const uint64_t waveSample =
                  view.timeline()->sampleForTick(initialWave->cell.tick);
              view.setPlayheadSample(waveSample, true);
              (void)initialVelocityArea->grab();
              QCoreApplication::processEvents();
              const auto waveMaxLevel =
                  view.noteVelocityLevel(track, initialWave->cell.tick,
                                         uint8_t(initialWave->cell.key), 127);
              if (!waveMaxLevel ||
                  !initialVelocityArea->accessibleDescription().contains(
                      QStringLiteral("%1 levels")
                          .arg(int(*waveMaxLevel) + 1))) {
                fail("playing playhead at programmable-wave note did not "
                     "resolve wave velocity graduations");
              }
            }

            view.setPlayheadSample(0, false);
          }
          view.setEditCursorTick(initialSquare->cell.tick);
        }
        view.setDrawerPage(initialDrawerPage);
        view.setDrawerVisible(initialDrawerVisible);
        doc.setCfg(initialOpenFullVolume);
      }
      std::vector<SongView::NoteId> ids;
      for (const NoteCase &note : notes)
        ids.push_back({uint32_t(note.cell.tick), uint8_t(note.cell.key)});
      view.setSelection(std::move(ids));

      const int batchIndex = doc.undoStack()->index();
      dragVelocity(notes.front(), 64, 1); // proposed stored velocity 65
      if (doc.undoStack()->index() != batchIndex + 1)
        fail("mixed velocity drag was not exactly one undo command");

      for (const NoteCase &note : notes) {
        DocNote committed;
        if (!doc.findNote(track, note.cell.tick, uint8_t(note.cell.key),
                          &committed)) {
          fail("mixed velocity drag lost a selected note");
          continue;
        }
        if (note.family == DetentFamily::Wave && committed.velocity != 64) {
          fail("programmable-wave proposal 65 did not commit at 64");
        } else if (note.family == DetentFamily::Cgb16 &&
                   committed.velocity != 68) {
          fail("square/noise proposal 65 did not commit at its "
               "16-level value 68");
        } else if (note.family == DetentFamily::Pcm &&
                   committed.velocity != 65) {
          fail("DirectSound proposal 65 did not remain continuous");
        }
      }

      const auto wave =
          std::find_if(notes.begin(), notes.end(), [](const NoteCase &note) {
            return note.family == DetentFamily::Wave;
          });
      if (wave != notes.end()) {
        view.setSelection(
            {{uint32_t(wave->cell.tick), uint8_t(wave->cell.key)}});
        const int crossingIndex = doc.undoStack()->index();
        // 81 is the first stored proposal in the next full-volume
        // programmable-wave class; its canonical midpoint is 96.
        dragVelocity(*wave, 64, 17);
        DocNote committed;
        if (doc.undoStack()->index() != crossingIndex + 1)
          fail("wave class-crossing drag was not one undo command");
        if (!doc.findNote(track, wave->cell.tick, uint8_t(wave->cell.key),
                          &committed) ||
            committed.velocity != 96) {
          fail("programmable-wave next-class proposal did not "
               "commit at 96");
        }
      }
      while (doc.undoStack()->index() > batchIndex)
        doc.undoStack()->undo();

      const SongView::DrawerPage drawerPageBefore = view.drawerPage();
      const bool drawerVisibleBefore = view.drawerVisible();
      view.setDrawerPage(SongView::DrawerPage::Velocity);
      view.setDrawerVisible(true);
      (void)view.grab();
      QCoreApplication::processEvents();
      auto *velocityArea = static_cast<songview::VelocityArea *>(
          view.findChild<QWidget *>(QStringLiteral("velocityArea")));
      if (!velocityArea || velocityArea->height() <= 0) {
        fail("velocity pane was not ready for detent gestures");
      } else {
        const int detentDisplayIndex = doc.undoStack()->index();
        SongCfg reducedVolume = doc.cfg();
        reducedVolume.masterVolume = 50;
        doc.setCfg(reducedVolume);
        QEvent leaveVelocityArea(QEvent::Leave);
        QApplication::sendEvent(velocityArea, &leaveVelocityArea);
        auto checkReducedDetents =
            [&](const NoteCase &note,
                std::size_t hardwareCapacity) -> std::size_t {
          const auto info = view.velocityAxisDetents(
              track, {{uint32_t(note.cell.tick), uint8_t(note.cell.key)}});
          const auto maximumLevel = view.noteVelocityLevel(
              track, note.cell.tick, uint8_t(note.cell.key), 127);
          if (!info || !maximumLevel) {
            fail("reduced-volume PSG detents were unavailable");
            return 0;
          }

          const std::size_t reachableCount = std::size_t(*maximumLevel) + 1;
          if (info->levels.size() != reachableCount) {
            fail("PSG detents exposed unreachable hardware levels");
          }
          if (reachableCount >= hardwareCapacity) {
            fail("reduced master volume did not reduce the "
                 "reachable PSG level count");
          }

          for (std::size_t level = 0; level < info->levels.size(); ++level) {
            const VelocityDetentLevel &detent = info->levels[level];
            if (detent.audible != (level != 0)) {
              fail("PSG detent audibility did not match its "
                   "hardware level");
            }
            const auto resolvedLevel = view.noteVelocityLevel(
                track, note.cell.tick, uint8_t(note.cell.key), detent.velocity);
            if (!resolvedLevel || *resolvedLevel != level) {
              fail("a reduced-volume PSG label was not a "
                   "current-mixer representative");
            }
            if (view.canonicalNoteVelocity(
                    track, note.cell.tick, uint8_t(note.cell.key),
                    detent.velocity) != detent.velocity) {
              fail("a reduced-volume PSG label was not the "
                   "canonical current-mixer midpoint");
            }
          }
          if (info->levels.empty() || info->levels.front().audible) {
            fail("PSG level zero was unavailable or audible");
            return reachableCount;
          }
          const auto clamped = view.velocityForLevel(
              track, note.cell.tick, uint8_t(note.cell.key),
              uint8_t(hardwareCapacity - 1));
          if (clamped != info->levels.back().velocity) {
            fail("an unreachable upper PSG level did not clamp "
                 "to the highest visible representative");
          }
          return reachableCount;
        };

        const auto waveAtCursor =
            std::find_if(notes.begin(), notes.end(), [](const NoteCase &note) {
              return note.family == DetentFamily::Wave;
            });
        if (waveAtCursor != notes.end()) {
          view.setEditCursorTick(waveAtCursor->cell.tick);
          view.setSelection({{uint32_t(waveAtCursor->cell.tick),
                              uint8_t(waveAtCursor->cell.key)}});
          (void)velocityArea->grab();
          QCoreApplication::processEvents();
          const std::size_t reachableCount =
              checkReducedDetents(*waveAtCursor, 5);
          if (reachableCount == 0 ||
              !velocityArea->accessibleDescription().contains(
                  QStringLiteral("%1 levels").arg(reachableCount))) {
            fail("velocity graduations exposed unreachable wave "
                 "levels");
          }
        }
        const auto square =
            std::find_if(notes.begin(), notes.end(), [](const NoteCase &note) {
              return note.family == DetentFamily::Cgb16;
            });
        if (square != notes.end()) {
          view.setEditCursorTick(square->cell.tick);
          view.setSelection(
              {{uint32_t(square->cell.tick), uint8_t(square->cell.key)}});
          (void)velocityArea->grab();
          QCoreApplication::processEvents();
          const std::size_t reachableCount = checkReducedDetents(*square, 16);
          if (reachableCount == 0 ||
              !velocityArea->accessibleDescription().contains(
                  QStringLiteral("%1 levels").arg(reachableCount))) {
            fail("velocity graduations exposed unreachable square "
                 "levels");
          }
        }

        // A note can precede its track's first explicit program
        // change. The timeline's canonical firstProgram must still
        // select that PSG voice; falling back to slot zero changes
        // both programAt and the note's typed detent resolution.
        int preProgramSlot = -1;
        for (int slot = 1; slot < VOICEGROUP_SIZE; ++slot) {
          const ToneData &tone = voicegroup->voices[slot];
          if (tone.type & (VOICE_KEYSPLIT | VOICE_KEYSPLIT_ALL))
            continue;
          const int cgbType = tone.type & VOICE_TYPE_CGB_MASK;
          if (cgbType == VOICE_PROGRAMMABLE_WAVE && tone.wavePointer) {
            preProgramSlot = slot;
            break;
          }
          if (cgbType == VOICE_SQUARE_1 || cgbType == VOICE_SQUARE_2 ||
              cgbType == VOICE_NOISE) {
            preProgramSlot = slot;
            break;
          }
        }
        if (preProgramSlot >= 0) {
          constexpr uint64_t noteTick = 0;
          constexpr uint64_t firstVoiceTick = 48;
          constexpr uint8_t noteKey = 60;
          SmfFile preProgramSmf;
          preProgramSmf.format = 1;
          preProgramSmf.division = 24;
          preProgramSmf.tracks.resize(2);
          preProgramSmf.tracks[0].endTick = 96;
          SmfTrack &preProgramTrack = preProgramSmf.tracks[1];
          SmfEvent noteOn;
          noteOn.tick = noteTick;
          noteOn.status = 0x90;
          noteOn.data0 = noteKey;
          noteOn.data1 = 64;
          SmfEvent noteOff = noteOn;
          noteOff.tick = 24;
          noteOff.status = 0x80;
          noteOff.data1 = 0;
          SmfEvent firstVoice;
          firstVoice.tick = firstVoiceTick;
          firstVoice.status = 0xC0;
          firstVoice.data0 = uint8_t(preProgramSlot);
          preProgramTrack.events = {noteOn, noteOff, firstVoice};
          preProgramTrack.endTick = 96;
          auto preProgramTimeline = MidiTimeline::build(preProgramSmf, 48000.0);
          if (!preProgramTimeline) {
            fail("could not build the pre-program PSG fixture");
          } else {
            SongView preProgramView;
            preProgramView.setSong(preProgramTimeline.get(), nullptr);
            preProgramView.setDocument(&doc);
            preProgramView.setVoicegroup(voicegroup);
            preProgramView.setEditCursorTick(noteTick);
            const auto beforeFirstProgram =
                preProgramView.noteVelocityLevel(0, noteTick, noteKey, 64);
            const auto atFirstProgram = preProgramView.noteVelocityLevel(
                0, firstVoiceTick, noteKey, 64);
            const auto detents = preProgramView.velocityAxisDetents(
                0, {{uint32_t(noteTick), noteKey}});
            const auto maximumBeforeFirstProgram =
                preProgramView.noteVelocityLevel(0, noteTick, noteKey, 127);
            preProgramView.setVoicegroup(nullptr);
            if (preProgramView.velocityAxisDetents(0, {}))
              fail("idle velocity axis retained stale voicegroup detents");
            preProgramView.setVoicegroup(voicegroup);
            const auto idleDetents = preProgramView.velocityAxisDetents(0, {});
            auto *preProgramVelocityArea =
                static_cast<songview::VelocityArea *>(
                    preProgramView.findChild<QWidget *>(
                        QStringLiteral("velocityArea")));
            if (preProgramVelocityArea) {
              preProgramView.setDrawerPage(SongView::DrawerPage::Velocity);
              (void)preProgramVelocityArea->grab();
              QCoreApplication::processEvents();
            }
            if (preProgramView.programAt(0, noteTick) != preProgramSlot) {
              fail("a pre-program PSG note resolved program "
                   "slot zero instead of firstProgram");
            }
            if (!beforeFirstProgram || beforeFirstProgram != atFirstProgram ||
                !maximumBeforeFirstProgram || !detents ||
                detents->levels.size() !=
                    std::size_t(*maximumBeforeFirstProgram) + 1) {
              fail("a pre-program PSG note did not resolve the "
                   "canonical firstProgram detent model");
            }
            if (!detents || !idleDetents ||
                !velocityDetentsCompatible(*detents, *idleDetents) ||
                !preProgramVelocityArea ||
                !preProgramVelocityArea->accessibleDescription().contains(
                    QStringLiteral("%1 levels")
                        .arg(int(idleDetents->levels.size())))) {
              fail("idle PSG track did not supply velocity graduations");
            }
          }
        } else {
          std::printf("rollcheck: SKIP %s pre-program PSG resolution "
                      "(no usable nonzero PSG slot)\n",
                      qUtf8Printable(songLabel));
        }
        while (doc.undoStack()->index() > detentDisplayIndex)
          doc.undoStack()->undo();
        const qreal dpr = velocityArea->devicePixelRatioF();
        for (const SlotCase &slot : slotCases) {
          if (slot.family == DetentFamily::Pcm)
            continue;
          const auto anchor = std::find_if(
              notes.begin(), notes.end(),
              [&](const NoteCase &note) { return note.family == slot.family; });
          if (anchor == notes.end())
            continue;

          const Cell partner = findFreeCell(8, false, true);
          if (partner.key < 0) {
            fail("no free grid cell for a homogeneous PSG "
                 "velocity selection");
            continue;
          }
          doc.addLanePoint(track, DOC_CC_VOICE, partner.tick, slot.slot);
          doc.addLanePoint(track, 0x07, partner.tick, 127);
          doc.addLanePoint(track, 0x0A, partner.tick, 64);
          doc.addNote(track, partner.tick, uint8_t(partner.key),
                      uint32_t(partner.dur), 64);

          const std::vector<SongView::NoteId> pair = {
              {uint32_t(anchor->cell.tick), uint8_t(anchor->cell.key)},
              {uint32_t(partner.tick), uint8_t(partner.key)}};
          view.setEditCursorTick(anchor->cell.tick);
          view.setSelection(pair);
          (void)velocityArea->grab();
          QCoreApplication::processEvents();

          const int expectedLevelCount =
              slot.family == DetentFamily::Wave ? 5 : 16;
          const auto detents = view.velocityAxisDetents(track, pair);
          if (!detents || int(detents->levels.size()) != expectedLevelCount ||
              !velocityArea->accessibleDescription().contains(
                  QStringLiteral("%1 levels").arg(expectedLevelCount))) {
            fail("homogeneous PSG multi-selection hid its "
                 "velocity detents");
            continue;
          }

          const auto startLevel = view.noteVelocityLevel(
              track, anchor->cell.tick, uint8_t(anchor->cell.key), 64);
          if (!startLevel || *startLevel >= detents->levels.size()) {
            fail("PSG velocity handle had no hardware level");
            continue;
          }
          const uint8_t targetLevel = *startLevel + 1 < detents->levels.size()
                                          ? uint8_t(*startLevel + 1)
                                          : uint8_t(*startLevel - 1);
          const int anchorX = qRound(view.displayX(double(anchor->cell.tick),
                                                   songview::kGutterW, dpr));
          const QPoint handle(anchorX,
                              qRound(songview::velocityLevelToY(
                                  int(*startLevel), int(detents->levels.size()),
                                  velocityArea->height())));
          const QPoint target(anchorX,
                              qRound(songview::velocityLevelToY(
                                  int(targetLevel), int(detents->levels.size()),
                                  velocityArea->height())));
          const bool staggerLabels = detents->levels.size() > 8;
          const qreal labelLeft = 8;
          const qreal labelRight = songview::kGutterW - 1 - 8;
          const qreal columnGap = 4;
          const qreal labelWidth =
              staggerLabels ? (labelRight - labelLeft - columnGap) / 2
                            : labelRight - labelLeft;
          const int column = staggerLabels ? targetLevel % 2 : 0;
          const qreal labelX = staggerLabels && column == 0
                                   ? labelLeft + labelWidth + columnGap
                                   : labelLeft;
          const QPoint graduation(qRound(labelX + labelWidth / 2), target.y());
          const int graduationIndex = doc.undoStack()->index();
          click(velocityArea, graduation);
          if (doc.undoStack()->index() != graduationIndex + 1) {
            fail("PSG velocity graduation click was not one undo command");
          }
          for (const SongView::NoteId &id : pair) {
            DocNote committed;
            const auto expected =
                view.velocityForLevel(track, id.tick, id.key, targetLevel);
            if (!expected ||
                !doc.findNote(track, id.tick, id.key, &committed) ||
                committed.velocity != *expected) {
              fail("PSG velocity graduation did not set its visible level");
            }
          }
          if (doc.undoStack()->index() > graduationIndex)
            doc.undoStack()->undo();

          const int relativeIndex = doc.undoStack()->index();
          sendMouse(velocityArea, QEvent::MouseButtonPress, handle,
                    Qt::LeftButton, Qt::LeftButton);
          sendMouse(velocityArea, QEvent::MouseMove, target, Qt::NoButton,
                    Qt::LeftButton);
          if (velocityArea->cursor().shape() != Qt::BlankCursor)
            fail("velocity node drag did not hide the cursor");
          for (const SongView::NoteId &id : pair) {
            const auto expected =
                view.velocityForLevel(track, id.tick, id.key, targetLevel);
            const auto rendered = std::find_if(
                view.model().notes.begin(), view.model().notes.end(),
                [&](const ViewNote &note) {
                  return note.track == track && note.startTick == id.tick &&
                         note.key == id.key;
                });
            if (!expected || rendered == view.model().notes.end() ||
                view.noteVelocityPreview(*rendered) != *expected) {
              fail("PSG handle drag did not expose its live velocity "
                   "to the note renderer");
            }
          }
          sendMouse(velocityArea, QEvent::MouseButtonRelease, target,
                    Qt::LeftButton, Qt::NoButton);
          if (velocityArea->cursor().shape() == Qt::BlankCursor)
            fail("velocity node drag did not restore the cursor");
          if (doc.undoStack()->index() != relativeIndex + 1) {
            fail("homogeneous PSG handle drag was not exactly one "
                 "batch undo command");
          }
          for (const SongView::NoteId &id : pair) {
            DocNote committed;
            const auto expected =
                view.velocityForLevel(track, id.tick, id.key, targetLevel);
            const bool found = doc.findNote(track, id.tick, id.key, &committed);
            const auto committedLevel =
                found ? view.noteVelocityLevel(track, id.tick, id.key,
                                               committed.velocity)
                      : std::nullopt;
            if (!found || !expected || committed.velocity != *expected ||
                committedLevel != targetLevel) {
              fail("PSG handle drag did not commit the targeted "
                   "visible hardware level");
            }
          }
          if (doc.undoStack()->index() > relativeIndex)
            doc.undoStack()->undo();

          if (slot.family == DetentFamily::Cgb16) {
            std::vector<uint8_t> originalVelocities;
            originalVelocities.reserve(pair.size());
            bool haveOriginals = true;
            for (const SongView::NoteId &id : pair) {
              DocNote original;
              if (!doc.findNote(track, id.tick, id.key, &original)) {
                fail("off-center PSG drag fixture lost a "
                     "selected note");
                haveOriginals = false;
                break;
              }
              originalVelocities.push_back(original.velocity);
            }

            if (haveOriginals) {
              // At this pane height adjacent 16-level centers
              // are two pixels apart. This one-pixel offset is
              // still within the rendered handle/stem hit area,
              // but pointer quantization favors targetLevel.
              const QPoint offsetHandle(
                  handle.x(), handle.y() + (target.y() < handle.y() ? -1 : 1));
              const int offsetIndex = doc.undoStack()->index();
              sendMouse(velocityArea, QEvent::MouseButtonPress, offsetHandle,
                        Qt::LeftButton, Qt::LeftButton);
              sendMouse(velocityArea, QEvent::MouseMove, target, Qt::NoButton,
                        Qt::LeftButton);
              sendMouse(velocityArea, QEvent::MouseButtonRelease, target,
                        Qt::LeftButton, Qt::NoButton);
              if (doc.undoStack()->index() != offsetIndex + 1) {
                fail("off-center square/noise handle drag was "
                     "not exactly one batch undo command");
              }
              for (const SongView::NoteId &id : pair) {
                DocNote committed;
                const auto expected =
                    view.velocityForLevel(track, id.tick, id.key, targetLevel);
                const bool found =
                    doc.findNote(track, id.tick, id.key, &committed);
                const auto committedLevel =
                    found ? view.noteVelocityLevel(track, id.tick, id.key,
                                                   committed.velocity)
                          : std::nullopt;
                if (!found || !expected || committed.velocity != *expected ||
                    committedLevel != targetLevel) {
                  fail("off-center square/noise handle drag "
                       "missed its requested hardware "
                       "level representative");
                }
              }
              if (doc.undoStack()->index() > offsetIndex)
                doc.undoStack()->undo();
              for (std::size_t i = 0; i < pair.size(); ++i) {
                DocNote restored;
                if (!doc.findNote(track, pair[i].tick, pair[i].key,
                                  &restored) ||
                    restored.velocity != originalVelocities[i]) {
                  fail("undo did not restore both notes "
                       "after the off-center square/noise "
                       "handle drag");
                }
              }
            }
          }

          view.setSelection(pair);
          (void)velocityArea->grab();
          QCoreApplication::processEvents();
          const uint8_t sweepLevel = targetLevel;
          const int sweepY = qRound(songview::velocityLevelToY(
              int(sweepLevel), int(detents->levels.size()),
              velocityArea->height()));
          const QPoint sweepStart(anchorX - 7, sweepY);
          const QPoint sweepEnd(anchorX + 7, sweepY);
          if (sweepStart.x() < songview::kGutterW) {
            fail("PSG velocity sweep fixture had no blank lead-in");
          } else {
            const int sweepIndex = doc.undoStack()->index();
            sendMouse(velocityArea, QEvent::MouseButtonPress, sweepStart,
                      Qt::LeftButton, Qt::LeftButton);
            sendMouse(velocityArea, QEvent::MouseMove, sweepEnd, Qt::NoButton,
                      Qt::LeftButton);
            sendMouse(velocityArea, QEvent::MouseButtonRelease, sweepEnd,
                      Qt::LeftButton, Qt::NoButton);
            DocNote committed;
            const auto expected =
                view.velocityForLevel(track, anchor->cell.tick,
                                      uint8_t(anchor->cell.key), sweepLevel);
            const bool found =
                doc.findNote(track, anchor->cell.tick,
                             uint8_t(anchor->cell.key), &committed);
            const auto committedLevel =
                found ? view.noteVelocityLevel(track, anchor->cell.tick,
                                               uint8_t(anchor->cell.key),
                                               committed.velocity)
                      : std::nullopt;
            if (doc.undoStack()->index() != sweepIndex + 1) {
              fail("PSG freehand sweep was not exactly one undo "
                   "command");
            }
            if (!found || !expected || committed.velocity != *expected ||
                committedLevel != sweepLevel) {
              fail("PSG freehand sweep missed its visible "
                   "hardware level");
            }
            if (doc.undoStack()->index() > sweepIndex)
              doc.undoStack()->undo();
          }
        }

        if (cgb16Slot >= 0) {
          failures += runRollCheckPsgVelocityMixed(
              {doc, view, songLabel, track, cgb16Slot});
        }

        const auto pcm =
            std::find_if(notes.begin(), notes.end(), [](const NoteCase &note) {
              return note.family == DetentFamily::Pcm;
            });
        if (pcm != notes.end()) {
          const SongView::NoteId pcmId{uint32_t(pcm->cell.tick),
                                       uint8_t(pcm->cell.key)};
          view.setEditCursorTick(pcm->cell.tick);
          view.setSelection({pcmId});
          (void)velocityArea->grab();
          QCoreApplication::processEvents();
          const int pcmX = qRound(
              view.displayX(double(pcm->cell.tick), songview::kGutterW, dpr));
          const QPoint handle(
              pcmX, qRound(songview::velocityToY(64, velocityArea->height())));
          const QPoint target(
              pcmX, qRound(songview::velocityToY(81, velocityArea->height())));
          const int linearTarget =
              songview::yToVelocity(target.y(), velocityArea->height());
          const int pcmIndex = doc.undoStack()->index();
          const QPoint onePixelStep = handle + QPoint(0, 1);
          const int onePixelVelocity = std::clamp(
              64 + songview::yToVelocity(onePixelStep.y(),
                                         velocityArea->height()) -
                  songview::yToVelocity(handle.y(), velocityArea->height()),
              1, 127);
          sendMouse(velocityArea, QEvent::MouseButtonPress, handle,
                    Qt::LeftButton, Qt::LeftButton);
          sendMouse(velocityArea, QEvent::MouseMove, onePixelStep, Qt::NoButton,
                    Qt::LeftButton);
          sendMouse(velocityArea, QEvent::MouseButtonRelease, onePixelStep,
                    Qt::LeftButton, Qt::NoButton);
          DocNote committed;
          if (doc.undoStack()->index() != pcmIndex + 1 ||
              !doc.findNote(track, pcm->cell.tick, uint8_t(pcm->cell.key),
                            &committed) ||
              committed.velocity != onePixelVelocity) {
            fail("one-pixel velocity node drag did not change velocity");
          }
          if (doc.undoStack()->index() > pcmIndex)
            doc.undoStack()->undo();
          sendMouse(velocityArea, QEvent::MouseButtonPress, handle,
                    Qt::LeftButton, Qt::LeftButton);
          sendMouse(velocityArea, QEvent::MouseMove, target, Qt::NoButton,
                    Qt::LeftButton);
          sendMouse(velocityArea, QEvent::MouseButtonRelease, target,
                    Qt::LeftButton, Qt::NoButton);
          if (doc.undoStack()->index() != pcmIndex + 1 ||
              !doc.findNote(track, pcm->cell.tick, uint8_t(pcm->cell.key),
                            &committed) ||
              committed.velocity != linearTarget ||
              view.noteVelocityLevel(track, pcm->cell.tick,
                                     uint8_t(pcm->cell.key),
                                     committed.velocity)) {
            fail("DirectSound velocity pane did not remain "
                 "continuous on its linear axis");
          }
          const QPoint graduation(
              songview::kGutterW - 27,
              qRound(songview::velocityToY(64, velocityArea->height())));
          click(velocityArea, graduation);
          if (doc.undoStack()->index() != pcmIndex + 2 ||
              !doc.findNote(track, pcm->cell.tick, uint8_t(pcm->cell.key),
                            &committed) ||
              committed.velocity != 64) {
            fail("continuous velocity graduation did not set velocity 64");
          }
          while (doc.undoStack()->index() > pcmIndex)
            doc.undoStack()->undo();
        }
      }
      view.setDrawerPage(drawerPageBefore);
      view.setDrawerVisible(drawerVisibleBefore);
    }

    while (doc.undoStack()->index() > setupIndex)
      doc.undoStack()->undo();
    view.setVoicegroup(nullptr);
    if (doc.undoStack()->index() != setupIndex ||
        doc.smf().write() != setupBaseline ||
        doc.cfg().masterVolume != setupMaster) {
      fail("velocity-detent setup or gestures leaked through undo");
    }
    click(roll,
          context
              .restoreLatchCenter); // restore the pre-check velocity latch (78)
  }

  return failures;
}
