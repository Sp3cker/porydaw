#pragma once

#include "project/voicegroupsource.h"
#include "core/m4asemantics.h"

#include <QVector>

#include <array>
#include <functional>
#include <optional>
#include <vector>

namespace songview {

struct VoicePickerEntry {
    VoiceFamily family = VoiceFamily::Sample;
    QString displayName;
    bool used = false;
};
using VoicePickerEntries = std::array<VoicePickerEntry, VOICEGROUP_SIZE>;

struct VoicePickerFilters {
    std::optional<VoiceFamily> family;
    bool usedOnly = false;
};

struct VisibleVoiceRows {
    std::array<bool, VOICEGROUP_SIZE> rows{};
    int matchingCount = 0;
    int nextRow = -1;
};

VisibleVoiceRows visibleVoiceRows(const VoicePickerEntries &entries,
                                  const VoicePickerFilters &filters, int currentRow);

struct VoicePickerProjectData {
    QStringList directSound;
    QStringList progWave;
    QList<QPair<QString, QString>> keysplits;
    QStringList drumkits;
    QStringList synths;
    QVector<VoicegroupSlotView> slotViews;
    VgAdsrDefaults adsrDefaults;
};

struct VoicePickerProjectVoice {
    QString symbol;
    QString displayName;
    VoiceFamily family = VoiceFamily::Sample;
    int existingSlot = -1;
    VgVoice replacement;
};

enum class ProjectVoiceMembership {
    All,
    InVoicegroup,
    AvailableToTrade,
};

struct ProjectVoiceFilters {
    ProjectVoiceMembership membership = ProjectVoiceMembership::All;
    std::optional<VoiceFamily> family;
    QString query;
};

struct VisibleProjectVoiceRows {
    std::vector<bool> rows;
    int matchingCount = 0;
    int nextRow = -1;
};

std::vector<VoicePickerProjectVoice> projectVoiceEntries(const VoicePickerProjectData &project);
bool projectVoiceMatches(const VoicePickerProjectVoice &voice, const QString &query);
VisibleProjectVoiceRows visibleProjectVoiceRows(const std::vector<VoicePickerProjectVoice> &voices,
                                                const ProjectVoiceFilters &filters, int currentRow);

struct VoicePickerSelection {
    int slot = -1;
};

struct VoicePickerServices {
    std::function<std::optional<VoicePickerProjectData>()> snapshot;
    std::function<bool(int, const VgVoice &, std::function<void(bool)>)> insert;
    std::function<void(const QString &, const VgAdsr &)> auditionSample;
    std::function<void()> stopSampleAudition;
};

} // namespace songview
