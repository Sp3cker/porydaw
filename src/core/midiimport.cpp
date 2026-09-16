#include "midiimport.h"

#include <QMap>
#include <QObject>
#include <algorithm>
#include <map>

#include "core/m4asemantics.h"
#include "core/timedefaults.h"
#include "core/tracklimits.h"
#include "core/xcmd.h"

namespace {

constexpr int kDefaultPcmBudget = 5; // pokeemerald m4aSoundInit maxChans

// The report's single verdict vocabulary, mapped from both verdict sources.
ImportSupport importSupport(M4aExportSupport support)
{
    switch (support) {
    case M4aExportSupport::Supported:
        return ImportSupport::Supported;
    case M4aExportSupport::NotExported:
        return ImportSupport::NotExported;
    case M4aExportSupport::NeedsReview:
        return ImportSupport::NeedsReview;
    }
    return ImportSupport::NeedsReview;
}

ImportSupport importSupport(xcmd::ExportClass exportClass)
{
    switch (exportClass) {
    case xcmd::ExportClass::Supported:
        return ImportSupport::Supported;
    case xcmd::ExportClass::NotExported:
        return ImportSupport::NotExported;
    case xcmd::ExportClass::NeedsReview:
        return ImportSupport::NeedsReview;
    }
    return ImportSupport::NeedsReview;
}

// The three coupled-protocol CCs: collected for the XCMD assessment instead
// of the per-CC histogram.
bool isXcmdPlumbingCc(uint8_t cc)
{
    return cc == xcmd::kSelectorController || cc == xcmd::kPayloadController ||
           cc == xcmd::kAlternatePayloadController;
}

} // namespace

ImportAnalysis analyzeForImport(const SmfFile &smf, int trackBudget, const QString &playerName)
{
    ImportAnalysis a;
    a.division = smf.division;
    a.sampleNoteLimit = kDefaultPcmBudget;
    a.smfTrackCount = track_limits::checkedTrackInt(smf.tracks.size());

    const SmfEngineTrackMapping map = mapSmfEngineTracks(smf);
    a.droppedTracks = map.droppedTracks;
    a.mappedTracks = map.usedTrackCount;
    if (trackBudget >= 0 && trackBudget < track_limits::kHardwareCapacity)
        a.silentTracks = std::max(0, a.mappedTracks - trackBudget);

    QMap<uint8_t, int> ccCounts;
    // XCMD plumbing CCs (0x1D/0x1E/0x1F) in scan order, adapted for
    // xcmd::assessTraffic; `index` is the running ordinal in this list.
    std::vector<xcmd::Event> xcmdTraffic;
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

    for (int et = 0; et < map.usedTrackCount; et++) {
        const int smfTrack = map.tracks[et].smfTrack;
        ImportTrackInfo info;
        info.smfTrack = smfTrack;

        // Name rule mirrors trackNameLoc/MidiTimeline: the chunk's first
        // unprefixed 0x03 — a Channel-Prefix-scoped 0x03 is never its name.
        SmfChannelPrefix prefix;
        for (const SmfEvent &ev : smf.tracks[smfTrack].events) {
            prefix.observe(ev);
            if (ev.isMeta() && ev.metaType == 0x03 && info.name.isEmpty() && prefix.channel < 0)
                info.name = QString::fromLatin1(ev.blob).trimmed();
            if (!ev.isChannel())
                continue;
            switch (ev.typeNibble()) {
            case 0x9:
                if (ev.data1 != 0) {
                    info.noteCount++;
                    if (info.programs.empty())
                        info.notesBeforeProgram = true;
                    edges.push_back({ev.tick, true, et, ev.data0});
                    break;
                }
                [[fallthrough]];
            case 0x8:
                edges.push_back({ev.tick, false, et, ev.data0});
                break;
            case 0xB:
                if (isXcmdPlumbingCc(ev.data0))
                    xcmdTraffic.push_back({xcmdTraffic.size(), ev.tick, uint8_t(et), ev.data0,
                                           ev.data1, ev.channel()});
                else
                    ccCounts[ev.data0]++;
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
        usage.support = importSupport(m4aExportSupport(it.key()));
        usage.label =
            QStringLiteral("%1 — %2").arg(QLatin1String(info.name), QLatin1String(info.display));
        a.ccs.push_back(usage);
    }

    // Logical XCMD rows take over where the histogram stops: assessTraffic
    // parses the coupled 0x1D/0x1E/0x1F traffic collected above and hands
    // back per-selector point counts plus one block per unresolved run.
    // Counts stay logical — points and payload bytes — never raw CC events.
    const xcmd::TrafficAssessment traffic = xcmd::assessTraffic(xcmdTraffic);
    for (const xcmd::Descriptor &descriptor : xcmd::kLaneDescriptors) {
        // Completed pairs split per selector (0x08 -> volume, 0x09 -> length).
        const uint32_t points =
            descriptor.selector == 0x08 ? traffic.echoPoints.volume : traffic.echoPoints.length;
        if (points == 0)
            continue;
        ImportXcmdUsage usage;
        usage.label = QLatin1String(descriptor.displayName);
        usage.count = points;
        usage.support = ImportSupport::Supported; // a complete pair always exports
        a.xcmds.push_back(usage);
    }

    // Group the remaining blocks per selector; all blocks of one kind share
    // one verdict, carried here from each block's own exportClass.
    struct XcmdGroup {
        uint32_t count = 0;
        ImportSupport support = ImportSupport::Supported;
    };
    QMap<uint8_t, XcmdGroup> unknownEpochs; // selector -> payload bytes
    QMap<uint8_t, XcmdGroup> danglingLanes; // selector -> payload-less epochs
    XcmdGroup strayPayloads;
    for (const xcmd::TrafficBlock &block : traffic.blocks) {
        switch (block.kind) {
        case xcmd::TrafficKind::CompleteEchoPoints:
            break; // summarized per descriptor from echoPoints above
        case xcmd::TrafficKind::UnknownSelectorEpoch: {
            XcmdGroup &group = unknownEpochs[block.selector];
            group.count += block.payloadCount;
            group.support = importSupport(block.exportClass);
            break;
        }
        case xcmd::TrafficKind::DanglingSelector: {
            XcmdGroup &group = danglingLanes[block.selector];
            group.count++;
            group.support = importSupport(block.exportClass);
            break;
        }
        case xcmd::TrafficKind::StrayPayloads:
            strayPayloads.count += block.payloadCount;
            strayPayloads.support = importSupport(block.exportClass);
            break;
        }
    }
    for (auto it = unknownEpochs.constBegin(); it != unknownEpochs.constEnd(); ++it) {
        ImportXcmdUsage usage;
        usage.label =
            QObject::tr("Unknown XCMD selector 0x%1").arg(it.key(), 2, 16, QLatin1Char('0'));
        usage.count = it.value().count;
        usage.support = it.value().support;
        a.xcmds.push_back(usage);
    }
    for (auto it = danglingLanes.constBegin(); it != danglingLanes.constEnd(); ++it) {
        // assessTraffic reports dangling epochs for known selectors only, so
        // the descriptor lookup always lands.
        const xcmd::Descriptor *descriptor = xcmd::descriptorForSelector(it.key());
        ImportXcmdUsage usage;
        usage.label = QLatin1String(descriptor ? descriptor->displayName : "XCMD selector");
        usage.count = it.value().count;
        usage.support = it.value().support;
        a.xcmds.push_back(usage);
    }
    if (strayPayloads.count > 0) {
        ImportXcmdUsage usage;
        usage.label = QObject::tr("XCMD payload without a selector");
        usage.count = strayPayloads.count;
        usage.support = strayPayloads.support;
        a.xcmds.push_back(usage);
    }

    if (a.droppedTracks > 0)
        a.warnings.append(
            QObject::tr("Porydaw will not import %1. The MIDI file contains more than 16 tracks.")
                .arg(trackCountPhrase(a.droppedTracks)));
    if (a.silentTracks > 0) {
        const QString displayName = playerName.isEmpty() ? QObject::tr("the selected audio player")
                                                         : playerRoleName(playerName, true);
        a.warnings.append(
            QObject::tr("The game will not play %1 for %2. This player can play %3.")
                .arg(trackCountPhrase(a.silentTracks), displayName, trackCountPhrase(trackBudget)));
    }
    if (a.division % 24 != 0)
        a.warnings.append(
            QObject::tr("Porydaw will adjust the note timing. The source timing value is %1.")
                .arg(a.division));
    if (a.peakConcurrentNotes > kDefaultPcmBudget)
        a.warnings.append(concurrencyNoticeText(a.peakConcurrentNotes, kDefaultPcmBudget));
    for (const ImportTrackInfo &t : a.tracks) {
        if (t.noteCount > 0 && t.notesBeforeProgram) {
            a.warnings.append(instrumentFallbackNoticeText());
            break;
        }
    }
    return a;
}

QString playerRoleName(const QString &symbol, bool includeSymbol)
{
    const QString sePrefix = QStringLiteral("MUSIC_PLAYER_SE");
    QString role;
    if (symbol == QStringLiteral("MUSIC_PLAYER_BGM")) {
        role = QObject::tr("Background music");
    } else if (symbol.startsWith(sePrefix)) {
        const QString number = symbol.mid(sePrefix.size());
        role = number.isEmpty() ? QObject::tr("Sound effect")
                                : QObject::tr("Sound effect %1").arg(number);
    } else {
        return symbol;
    }
    return includeSymbol ? QStringLiteral("%1 (%2)").arg(role, symbol) : role;
}

QString trackCountPhrase(int count)
{
    return count == 1 ? QObject::tr("1 track") : QObject::tr("%1 tracks").arg(count);
}

QString concurrencyNoticeText(int peakNotes, int sampleNoteLimit)
{
    return QObject::tr("%1 notes play at the same time in one part of the song. The Game Boy "
                       "Advance can mix %2 sample notes at the same time. Square, wave, and noise "
                       "sounds do not use this limit. The game can stop some sample notes.")
        .arg(peakNotes)
        .arg(sampleNoteLimit);
}

QString instrumentFallbackNoticeText()
{
    return QObject::tr("Some notes start before the MIDI data selects an instrument. These notes "
                       "use instrument 0.");
}

namespace {

// The engine slot a pure state-setter writes, or -1 for events where every
// occurrence matters. Slots are per channel; CCs get one slot per controller
// number (the m4a CC vocabulary has no cross-CC coupling outside the excluded
// protocols, and CCs it ignores set no state at all), poly aftertouch one per
// key. CC numbers follow tools/mid2agb/agb.cpp via m4aClassifyCc's table.
int setterSlot(const SmfEvent &ev)
{
    if (ev.isMeta()) {
        // Tempo and time signature; other metas (text, markers, ports) are
        // identities, not values — two on one tick can both be meant.
        if (ev.metaType == 0x51 || ev.metaType == 0x58)
            return 0x10000 | ev.metaType;
        return -1;
    }
    if (!ev.isChannel())
        return -1;
    const int channel = ev.status & 0x0F;
    switch (ev.typeNibble()) {
    case 0xB:
        switch (ev.data0) {
        case 0x0C: // MEMACC plumbing: an op CC fires using state stashed by
        case 0x0D: // its neighbors, and the ops include conditional branches —
        case 0x0E: // every occurrence is an action.
        case 0x0F:
        case 0x10:
        case 0x11: // loop Label
        case 0x1D: // XCMD: same stash-then-fire shape as MEMACC
        case 0x1E:
        case 0x1F:
            return -1;
        default:
            return (0xB << 12) | (channel << 7) | ev.data0;
        }
    case 0xA: // poly aftertouch: one slot per key
        return (0xA << 12) | (channel << 7) | ev.data0;
    case 0xC:
    case 0xD:
    case 0xE:
        return (ev.typeNibble() << 12) | (channel << 7);
    default: // notes
        return -1;
    }
}

} // namespace

int removeRedundantSetterEvents(SmfFile *smf)
{
    int removed = 0;
    for (SmfTrack &track : smf->tracks) {
        std::vector<SmfEvent> &evs = track.events;
        std::vector<char> drop(evs.size(), 0);
        std::map<int, size_t> lastForSlot; // within the current tick only
        uint64_t runTick = 0;
        for (size_t i = 0; i < evs.size(); i++) {
            if (i == 0 || evs[i].tick != runTick) {
                lastForSlot.clear();
                runTick = evs[i].tick;
            }
            const int slot = setterSlot(evs[i]);
            if (slot < 0)
                continue;
            const auto it = lastForSlot.find(slot);
            if (it != lastForSlot.end()) {
                drop[it->second] = 1;
                removed++;
            }
            lastForSlot[slot] = i;
        }
        size_t out = 0;
        for (size_t i = 0; i < evs.size(); i++) {
            if (!drop[i])
                evs[out++] = std::move(evs[i]);
        }
        evs.resize(out);
    }
    return removed;
}

bool rescaleDivision(SmfFile *smf, uint16_t newDivision, QString *error)
{
    if (newDivision == 0 || smf->division == 0 || smf->division == newDivision)
        return true;
    // Floor scaling is monotonic, so each track's non-decreasing tick order
    // (and same-tick event order) survives the rescale.
    const uint64_t oldDivision = smf->division;
    // Preflight the largest tick before touching anything: reject, never clamp.
    uint64_t maxTick = 0;
    for (const SmfTrack &track : smf->tracks) {
        for (const SmfEvent &ev : track.events)
            maxTick = std::max(maxTick, uint64_t(ev.tick));
        maxTick = std::max(maxTick, uint64_t(track.endTick));
    }
    if (maxTick * newDivision / oldDivision > CoreTimeDefaults::kMaxTick) {
        if (error)
            *error = QObject::tr("Tick rescale to division %1 exceeds 32-bit tick range")
                         .arg(newDivision);
        return false;
    }
    for (SmfTrack &track : smf->tracks) {
        for (SmfEvent &ev : track.events)
            ev.tick = Tick(uint64_t(ev.tick) * newDivision / oldDivision);
        track.endTick = Tick(uint64_t(track.endTick) * newDivision / oldDivision);
    }
    smf->division = newDivision;
    return true;
}
