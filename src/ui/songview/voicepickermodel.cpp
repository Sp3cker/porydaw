#include "voicepickermodel.h"

#include "ui/samplepicker.h"

namespace songview {
namespace {

bool isDirectSound(VgMacro macro)
{
    return macro == VgMacro::DirectSound || macro == VgMacro::DirectSoundNoResample ||
           macro == VgMacro::DirectSoundAlt;
}

VgVoice symbolVoice(VgMacro macro, const QString &symbol, const QString &keysplitTable,
                    const VgAdsrDefaults &defaults)
{
    VgVoice voice{macro, 60, 0, symbol, keysplitTable};
    if (macro == VgMacro::Keysplit || macro == VgMacro::KeysplitAll)
        return voice;
    const VgAdsr adsr = vgDefaultAdsr(defaults, macro, symbol);
    voice.attack = adsr.attack;
    voice.decay = adsr.decay;
    voice.sustain = adsr.sustain;
    voice.release = adsr.release;
    return voice;
}

bool matchesProjectVoice(const VoicePickerProjectVoice &candidate, const VgVoice &voice)
{
    if (candidate.symbol != voice.symbol)
        return false;
    switch (candidate.family) {
    case VoiceFamily::Sample:
        if (candidate.replacement.macro == VgMacro::Keysplit) {
            return voice.macro == VgMacro::Keysplit &&
                   voice.keysplitTable == candidate.replacement.keysplitTable;
        }
        return isDirectSound(voice.macro);
    case VoiceFamily::Wave:
        return voice.macro == VgMacro::ProgWave || voice.macro == VgMacro::ProgWaveAlt;
    case VoiceFamily::Drumkit:
        return voice.macro == VgMacro::KeysplitAll;
    case VoiceFamily::Synth:
        return isDirectSound(voice.macro);
    case VoiceFamily::Square1:
    case VoiceFamily::Square2:
    case VoiceFamily::Noise:
        return false;
    }
    return false;
}

} // namespace

VisibleVoiceRows visibleVoiceRows(const VoicePickerEntries &entries,
                                  const VoicePickerFilters &filters, int currentRow)
{
    VisibleVoiceRows result;
    int firstVisible = -1;
    for (int voice = 0; voice < VOICEGROUP_SIZE; ++voice) {
        const auto &entry = entries[static_cast<std::size_t>(voice)];
        const bool visible = (!filters.family || entry.family == *filters.family) &&
                             (!filters.usedOnly || entry.used);
        result.rows[static_cast<std::size_t>(voice)] = visible;
        if (!visible)
            continue;
        ++result.matchingCount;
        if (firstVisible < 0)
            firstVisible = voice;
    }
    result.nextRow = currentRow >= 0 && currentRow < VOICEGROUP_SIZE &&
                             result.rows[static_cast<std::size_t>(currentRow)]
                         ? currentRow
                         : firstVisible;
    return result;
}

std::vector<VoicePickerProjectVoice> projectVoiceEntries(const VoicePickerProjectData &project)
{
    std::vector<VoicePickerProjectVoice> entries;
    entries.reserve(static_cast<std::size_t>(project.directSound.size() + project.progWave.size() +
                                             project.keysplits.size() + project.drumkits.size() +
                                             project.synths.size()));
    const auto append = [&entries, &project](const QString &symbol, VoiceFamily family,
                                             VgMacro macro,
                                             const QString &keysplitTable = QString()) {
        VoicePickerProjectVoice entry;
        entry.symbol = symbol;
        entry.displayName = vgSampleDisplayName(symbol);
        entry.family = family;
        entry.replacement = symbolVoice(macro, symbol, keysplitTable, project.adsrDefaults);
        for (int slot = 0; slot < project.slotViews.size() && slot < VOICEGROUP_SIZE; ++slot) {
            const auto &voice = project.slotViews.at(slot).voice;
            if (voice && matchesProjectVoice(entry, *voice)) {
                entry.existingSlot = slot;
                break;
            }
        }
        entries.push_back(std::move(entry));
    };
    for (const QString &symbol : project.directSound)
        append(symbol, VoiceFamily::Sample, VgMacro::DirectSound);
    for (const auto &[symbol, table] : project.keysplits)
        append(symbol, VoiceFamily::Sample, VgMacro::Keysplit, table);
    for (const QString &symbol : project.progWave)
        append(symbol, VoiceFamily::Wave, VgMacro::ProgWave);
    for (const QString &symbol : project.drumkits)
        append(symbol, VoiceFamily::Drumkit, VgMacro::KeysplitAll);
    for (const QString &symbol : project.synths)
        append(symbol, VoiceFamily::Synth, VgMacro::DirectSound);
    return entries;
}

bool projectVoiceMatches(const VoicePickerProjectVoice &voice, const QString &query)
{
    const QString trimmed = query.trimmed();
    return trimmed.isEmpty() || voice.displayName.contains(trimmed, Qt::CaseInsensitive) ||
           voice.symbol.contains(trimmed, Qt::CaseInsensitive);
}

VisibleProjectVoiceRows visibleProjectVoiceRows(const std::vector<VoicePickerProjectVoice> &voices,
                                                const ProjectVoiceFilters &filters, int currentRow)
{
    VisibleProjectVoiceRows result;
    result.rows.resize(voices.size());
    int firstVisible = -1;
    for (std::size_t row = 0; row < voices.size(); ++row) {
        const auto &voice = voices[row];
        const bool membershipMatches =
            filters.membership == ProjectVoiceMembership::All ||
            (filters.membership == ProjectVoiceMembership::InVoicegroup &&
             voice.existingSlot >= 0) ||
            (filters.membership == ProjectVoiceMembership::AvailableToTrade &&
             voice.existingSlot < 0);
        const bool visible = membershipMatches &&
                             (!filters.family || voice.family == *filters.family) &&
                             projectVoiceMatches(voice, filters.query);
        result.rows[row] = visible;
        if (!visible)
            continue;
        ++result.matchingCount;
        if (firstVisible < 0)
            firstVisible = static_cast<int>(row);
    }
    result.nextRow = currentRow >= 0 && currentRow < static_cast<int>(voices.size()) &&
                             result.rows[static_cast<std::size_t>(currentRow)]
                         ? currentRow
                         : firstVisible;
    return result;
}

} // namespace songview
