#include "midiimport.h"

#include <QMap>
#include <QObject>
#include <algorithm>
#include <limits>
#include <utility>

#include "ui/m4asemantics.h"

namespace {

constexpr int kMaxEngineTracks = 16; // m4a MAX_TRACKS
constexpr int kDefaultPcmBudget = 5; // pokeemerald m4aSoundInit maxChans

bool isRealNoteOn(const SmfEvent &ev) {
  return ev.isChannel() && ev.isNoteOn();
}

bool hasRealNoteOn(const SmfTrack &track) {
  return std::any_of(track.events.begin(), track.events.end(), isRealNoteOn);
}

ImportTrackInfo inspectImportTrack(const SmfTrack &track, int smfTrack) {
  ImportTrackInfo info;
  info.smfTrack = smfTrack;
  SmfChannelPrefix prefix;
  bool nameSeen = false;
  for (const SmfEvent &ev : track.events) {
    prefix.observe(ev);
    if (ev.isMeta() && ev.metaType == 0x03 && !nameSeen && prefix.channel < 0) {
      nameSeen = true;
      info.name = QString::fromLatin1(ev.blob).trimmed();
    }
    if (!ev.isChannel())
      continue;
    if (std::find(info.channels.begin(), info.channels.end(), ev.channel()) ==
        info.channels.end())
      info.channels.push_back(ev.channel());
    switch (ev.typeNibble()) {
    case 0x9:
      if (ev.data1 != 0) {
        info.noteCount++;
        if (info.programs.empty())
          info.notesBeforeProgram = true;
      }
      break;
    case 0xC:
      if (std::find(info.programs.begin(), info.programs.end(), ev.data0) ==
          info.programs.end())
        info.programs.push_back(ev.data0);
      break;
    default:
      break;
    }
  }
  return info;
}

// Mirrors SongDocument::rebuildTrackMap / MidiTimeline::build: the first 16
// channel-bearing chunks, as chunk indices in file order.
std::vector<int> engineTrackMap(const SmfFile &smf, int *dropped)
{
    std::vector<int> map;
    *dropped = 0;
    for (size_t t = 0; t < smf.tracks.size(); t++) {
        for (const SmfEvent &ev : smf.tracks[t].events) {
            if (!ev.isChannel())
                continue;
            if (int(map.size()) < kMaxEngineTracks)
                map.push_back(int(t));
            else
                (*dropped)++;
            break;
        }
    }
    return map;
}

bool validTimeSignature(const SmfEvent &ev) {
  return ev.isMeta() && ev.metaType == 0x58 && ev.blob.size() >= 2;
}

bool validKeySignature(const SmfEvent &ev) {
  return ev.isMeta() && ev.metaType == 0x59 && ev.blob.size() >= 2;
}

// Returns whether this event is global when read as a source chunk. The
// first unprefixed 0x03 is always the chunk name, including marker-looking
// text; later unprefixed 0x03 markers are global.
bool isSourceGlobalEvent(const SmfEvent &ev, const SmfChannelPrefix &prefix,
                         bool *nameSeen) {
  if (!ev.isMeta())
    return false;
  if (ev.metaType == 0x03) {
    if (prefix.channel >= 0 && !smfMetaIsMarker(ev))
      return false;
    if (prefix.channel < 0 && !*nameSeen) {
      *nameSeen = true;
      return false;
    }
  }
  return (ev.metaType == 0x51 && ev.blob.size() == 3) ||
         validTimeSignature(ev) || validKeySignature(ev) || smfMetaIsMarker(ev);
}

SmfTrack appendableTrack(const SmfTrack &source) {
  SmfTrack result = source;
  result.events.clear();
  SmfChannelPrefix prefix;
  bool nameSeen = false;
  for (const SmfEvent &ev : source.events) {
    prefix.observe(ev);
    if (!isSourceGlobalEvent(ev, prefix, &nameSeen))
      result.events.push_back(ev);
  }
  return result;
}

struct RetainedGlobal {
  SmfEvent event;
  int sourceTrack = -1;
  size_t sourceEvent = 0;
  int prefixChannel = -1;
};

SmfEvent nameContextEvent(const SmfEvent *sourceName) {
  SmfEvent result;
  result.status = 0xFF;
  result.metaType = 0x03;
  if (sourceName != nullptr && !smfMetaIsMarker(*sourceName))
    result.blob = sourceName->blob;
  return result;
}

SmfEvent channelPrefixEvent(uint64_t tick, int channel) {
  SmfEvent result;
  result.tick = tick;
  result.status = 0xFF;
  result.metaType = 0x20;
  result.blob = QByteArray(1, char(channel));
  return result;
}

bool retainedGlobalOrder(const RetainedGlobal &a, const RetainedGlobal &b) {
  if (a.event.tick != b.event.tick)
    return a.event.tick < b.event.tick;
  if (a.sourceTrack != b.sourceTrack)
    return a.sourceTrack < b.sourceTrack;
  return a.sourceEvent < b.sourceEvent;
}

std::vector<bool> validatedSelection(const SmfFile &smf,
                                     const std::vector<int> &indices) {
  std::vector<bool> selected(smf.tracks.size(), false);
  for (const int index : indices) {
    if (index >= 0 && index < int(smf.tracks.size()))
      selected[index] = true;
  }
  return selected;
}

} // namespace

std::vector<ImportTrackInfo> noteBearingImportTracks(const SmfFile &smf) {
  std::vector<ImportTrackInfo> tracks;
  for (size_t i = 0; i < smf.tracks.size(); i++) {
    ImportTrackInfo info = inspectImportTrack(smf.tracks[i], int(i));
    if (info.noteCount > 0)
      tracks.push_back(std::move(info));
  }
  return tracks;
}

SmfFile selectedMidiForNewSong(const SmfFile &smf,
                               const std::vector<int> &selectedTracks) {
  SmfFile result;
  result.format = 1;
  result.division = smf.division;
  result.wasFormat0 = smf.wasFormat0;

  const std::vector<bool> selected = validatedSelection(smf, selectedTracks);
  std::vector<RetainedGlobal> globals;
  SmfEvent firstName;
  bool haveFirstName = false;
  bool needsNameContext = false;
  uint64_t globalEndTick = 0;
  for (size_t sourceTrack = 0; sourceTrack < smf.tracks.size(); sourceTrack++) {
    const SmfTrack &source = smf.tracks[sourceTrack];
    SmfChannelPrefix prefix;
    bool nameSeen = false;
    bool trackHasGlobal = false;
    for (size_t sourceEvent = 0; sourceEvent < source.events.size();
         sourceEvent++) {
      const SmfEvent &ev = source.events[sourceEvent];
      prefix.observe(ev);
      const bool firstUnprefixedName =
          ev.isMeta() && ev.metaType == 0x03 && prefix.channel < 0 && !nameSeen;
      if (firstUnprefixedName && !haveFirstName) {
        firstName = ev;
        haveFirstName = true;
      }
      if (!isSourceGlobalEvent(ev, prefix, &nameSeen))
        continue;
      trackHasGlobal = true;
      RetainedGlobal global;
      global.event = ev;
      global.sourceTrack = int(sourceTrack);
      global.sourceEvent = sourceEvent;
      if (ev.metaType == 0x03 && prefix.channel >= 0)
        global.prefixChannel = prefix.channel;
      else if (ev.metaType == 0x03)
        needsNameContext = true;
      globals.push_back(std::move(global));
    }
    if (trackHasGlobal)
      globalEndTick = std::max(globalEndTick, source.endTick);
  }
  std::stable_sort(globals.begin(), globals.end(), retainedGlobalOrder);

  SmfTrack globalTrack;
  globalTrack.endTick = globalEndTick;
  if (needsNameContext)
    globalTrack.events.push_back(
        nameContextEvent(haveFirstName ? &firstName : nullptr));
  for (const RetainedGlobal &global : globals) {
    if (global.prefixChannel >= 0)
      globalTrack.events.push_back(
          channelPrefixEvent(global.event.tick, global.prefixChannel));
    globalTrack.events.push_back(global.event);
  }
  result.tracks.push_back(std::move(globalTrack));

  for (size_t sourceTrack = 0; sourceTrack < smf.tracks.size(); sourceTrack++) {
    if (selected[sourceTrack] && hasRealNoteOn(smf.tracks[sourceTrack]))
      result.tracks.push_back(appendableTrack(smf.tracks[sourceTrack]));
  }
  return result;
}

SmfFile selectedMidiForAppend(const SmfFile &smf,
                              const std::vector<int> &selectedTracks) {
  SmfFile result;
  result.format = 1;
  result.division = smf.division;
  result.wasFormat0 = smf.wasFormat0;
  const std::vector<bool> selected = validatedSelection(smf, selectedTracks);
  for (size_t i = 0; i < smf.tracks.size(); i++) {
    if (selected[i] && hasRealNoteOn(smf.tracks[i]))
      result.tracks.push_back(appendableTrack(smf.tracks[i]));
  }
  return result;
}

uint64_t earliestNoteTick(const SmfFile &smf) {
  uint64_t earliest = std::numeric_limits<uint64_t>::max();
  for (const SmfTrack &track : smf.tracks) {
    for (const SmfEvent &ev : track.events) {
      if (isRealNoteOn(ev))
        earliest = std::min(earliest, ev.tick);
    }
  }
  return earliest;
}

ImportAnalysis analyzeForImport(const SmfFile &smf, int trackBudget,
                                const QString &playerName)
{
    ImportAnalysis a;
    a.division = smf.division;
    a.smfTrackCount = int(smf.tracks.size());

    const auto map = engineTrackMap(smf, &a.droppedTracks);
    a.mappedTracks = int(map.size());
    if (trackBudget >= 0 && trackBudget < kMaxEngineTracks)
        a.silentTracks = std::max(0, a.mappedTracks - trackBudget);

    QMap<uint8_t, int> ccCounts;
    // (engineTrack << 8 | key) -> depth, so overlapping same-key notes count
    // once per sounding instance.
    QMap<int, int> sounding;
    struct NoteEdge {
        uint64_t tick;
        bool on;
        int track;
        uint8_t key;
    };
    std::vector<NoteEdge> edges;

    for (int et = 0; et < int(map.size()); et++) {
        const int smfTrack = map[et];
        ImportTrackInfo info =
            inspectImportTrack(smf.tracks[smfTrack], smfTrack);
        for (const SmfEvent &ev : smf.tracks[smfTrack].events) {
            if (!ev.isChannel())
                continue;
            switch (ev.typeNibble()) {
            case 0x9:
                if (ev.data1 != 0) {
                    edges.push_back({ev.tick, true, et, ev.data0});
                    break;
                }
                [[fallthrough]];
            case 0x8:
                edges.push_back({ev.tick, false, et, ev.data0});
                break;
            case 0xB:
                ccCounts[ev.data0]++;
                break;
            default:
                break;
            }
        }
        a.tracks.push_back(info);
    }

    // Peak polyphony: note-ends first at equal ticks, as a note retriggered on
    // the same tick replaces rather than stacks.
    std::stable_sort(edges.begin(), edges.end(), [](const NoteEdge &x, const NoteEdge &y) {
        if (x.tick != y.tick)
            return x.tick < y.tick;
        return !x.on && y.on;
    });
    int active = 0;
    for (const NoteEdge &e : edges) {
        const int key = (e.track << 8) | e.key;
        if (e.on) {
            sounding[key]++;
            active++;
            a.peakConcurrentNotes = std::max(a.peakConcurrentNotes, active);
        } else if (sounding.value(key, 0) > 0) {
            sounding[key]--;
            active--;
        }
    }

    for (auto it = ccCounts.constBegin(); it != ccCounts.constEnd(); ++it) {
        const M4aCcInfo info = m4aClassifyCc(it.key());
        ImportCcUsage usage;
        usage.cc = it.key();
        usage.count = it.value();
        usage.audible = info.eventClass == M4aEventClass::AudibleLane;
        usage.label = QStringLiteral("%1 — %2").arg(QLatin1String(info.name),
                                                    QLatin1String(info.display));
        a.ccs.push_back(usage);
    }

    if (a.droppedTracks > 0)
        a.warnings.append(QObject::tr("%1 track(s) beyond the m4a 16-track limit "
                                      "will not play.")
                              .arg(a.droppedTracks));
    if (a.silentTracks > 0)
        a.warnings.append(
            QObject::tr("%1 track(s) beyond %2's %3-track allocation "
                        "(sound/music_player_table.inc) will be silent in-game.")
                .arg(a.silentTracks)
                .arg(playerName.isEmpty() ? QStringLiteral("the music player")
                                          : playerName)
                .arg(trackBudget));
    if (a.division % 24 != 0)
        a.warnings.append(
            QObject::tr("Division %1 is not a multiple of 24; mid2agb quantizes to "
                        "24 clocks per beat, so timing will shift slightly.")
                .arg(a.division));
    if (a.peakConcurrentNotes > kDefaultPcmBudget)
        a.warnings.append(
            QObject::tr("Up to %1 notes sound at once; the GBA mixes %2 sample-based "
                        "notes (CGB square/wave/noise voices don't count). Extra "
                        "notes will be dropped or stolen.")
                .arg(a.peakConcurrentNotes)
                .arg(kDefaultPcmBudget));
    for (const ImportTrackInfo &t : a.tracks) {
        if (t.noteCount > 0 && t.notesBeforeProgram) {
            a.warnings.append(
                QObject::tr("Some tracks play notes before any program change; those "
                            "notes use voice 0."));
            break;
        }
    }
    return a;
}

void rescaleDivision(SmfFile *smf, uint16_t newDivision)
{
    if (newDivision == 0 || smf->division == 0 || smf->division == newDivision)
        return;
    // Floor scaling is monotonic, so each track's non-decreasing tick order
    // (and same-tick event order) survives the rescale.
    const uint64_t oldDivision = smf->division;
    for (SmfTrack &track : smf->tracks) {
        for (SmfEvent &ev : track.events)
            ev.tick = ev.tick * newDivision / oldDivision;
        track.endTick = track.endTick * newDivision / oldDivision;
    }
    smf->division = newDivision;
}
