// -------------------------------------------------------------- VoicePicker
//
// The voice picker is a typed Quick-popup bridge. It keeps the 128 labels
// stable for one session, filters them only when search text changes, and
// pairs every held preview note-on with a release.

#include "ui/songview/voicepicker.h"

#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/songview/quick/promptappearance.h"

#include <QGuiApplication>
#include <algorithm>
namespace lyt = ::layout;
using Space = lyt::Space;


namespace songview::detail {

VisibleRows visibleVoiceRows(const std::array<VoiceFamily, VOICEGROUP_SIZE> &families,
                             const QStringList &displayNames, const QSet<int> &usedSlots,
                             std::optional<VoiceFamily> family, bool usedOnly, bool namedOnly,
                             int currentRow)
{
    VisibleRows result;
    int firstVisible = -1;
    for (int voice = 0; voice < VOICEGROUP_SIZE; ++voice) {
        const bool visible = (!family || families[voice] == *family) &&
                             (!usedOnly || usedSlots.contains(voice)) &&
                             (!namedOnly || !displayNames.at(voice).isEmpty());
        result.rows[voice] = visible;
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

} // namespace songview::detail

namespace {

constexpr int cMaxVoiceProgram = int(songview::VoicePickerModel::cVoiceCount) - 1;
constexpr std::array kFamilies = {
    VoiceFamily::Sample, VoiceFamily::Square1, VoiceFamily::Square2, VoiceFamily::Wave,
    VoiceFamily::Noise, VoiceFamily::Drumkit, VoiceFamily::Synth,
};

QString familyLabel(VoiceFamily family)
{
    switch (family) {
    case VoiceFamily::Sample:
        return songview::VoicePicker::tr("Sample");
    case VoiceFamily::Square1:
        return songview::VoicePicker::tr("Square 1");
    case VoiceFamily::Square2:
        return songview::VoicePicker::tr("Square 2");
    case VoiceFamily::Wave:
        return songview::VoicePicker::tr("Wave");
    case VoiceFamily::Noise:
        return songview::VoicePicker::tr("Noise");
    case VoiceFamily::Drumkit:
        return songview::VoicePicker::tr("Drumkit");
    case VoiceFamily::Synth:
        return songview::VoicePicker::tr("Synth (Golden Sun)");
    }
    return {};
}

QVariantMap voicePickerAppearanceFor()
{
    QVariantMap appearance = songview::promptDialogAppearance(QGuiApplication::font());
    // Picker-local sizing: the search-field floor and the list viewport.
    appearance.insert(QStringLiteral("minimumWidth"), lyt::fontPx(30.0));
    appearance.insert(QStringLiteral("listHeight"), lyt::fontPx(110.0 / 3.0));
    return appearance;
}

} // namespace

namespace songview {
using namespace songview::detail;

VoicePickerModel::VoicePickerModel(SongView &owner, QObject *parent) : QAbstractListModel(parent)
{
    const QSet<int> used = owner.usedVoices();
    m_visiblePrograms.reserve(m_entries.size());
    for (int program = 0; program < int(m_entries.size()); ++program) {
        const QString displayName = owner.voiceDisplayName(uint8_t(program));
        const VoiceFamily family = owner.voiceFamily(uint8_t(program));
        m_entries[static_cast<std::size_t>(program)] = {
            program,
            QStringLiteral("%1  %2")
                .arg(program, 3, 10, QLatin1Char('0'))
                .arg(owner.voiceShortName(uint8_t(program))),
            displayName,
            family,
            used.contains(program),
        };
        m_visiblePrograms.push_back(program);
    }
}

int VoicePickerModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_visiblePrograms.size());
}

QVariant VoicePickerModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= int(m_visiblePrograms.size()))
        return {};

    const Entry &entry = m_entries[static_cast<std::size_t>(m_visiblePrograms[index.row()])];
    switch (role) {
    case Program:
        return entry.program;
    case Label:
        return entry.label;
    }
    return {};
}

QHash<int, QByteArray> VoicePickerModel::roleNames() const
{
    static const QHash<int, QByteArray> roles = {
        {Program, "program"},
        {Label, "label"},
    };
    return roles;
}

void VoicePickerModel::setFilters(const QString &filter, std::optional<VoiceFamily> family,
                                  bool usedOnly, bool namedOnly)
{
    std::vector<int> visiblePrograms;
    visiblePrograms.reserve(m_entries.size());
    for (const Entry &entry : m_entries) {
        if (entry.label.contains(filter, Qt::CaseInsensitive) &&
            (!family || entry.family == *family) && (!usedOnly || entry.used) &&
            (!namedOnly || !entry.displayName.isEmpty())) {
            visiblePrograms.push_back(entry.program);
        }
    }
    if (visiblePrograms == m_visiblePrograms)
        return;
    beginResetModel();
    m_visiblePrograms = std::move(visiblePrograms);
    endResetModel();
}

int VoicePickerModel::firstProgram() const noexcept
{
    return m_visiblePrograms.empty() ? -1 : m_visiblePrograms.front();
}

int VoicePickerModel::programAt(int row) const noexcept
{
    return row >= 0 && row < int(m_visiblePrograms.size()) ? m_visiblePrograms[row] : -1;
}

int VoicePickerModel::rowForProgram(int program) const noexcept
{
    const auto it = std::find(m_visiblePrograms.cbegin(), m_visiblePrograms.cend(), program);
    return it == m_visiblePrograms.cend() ? -1 : int(it - m_visiblePrograms.cbegin());
}
int VoicePickerModel::familyCount(VoiceFamily family) const
{
    return int(std::count_if(m_entries.cbegin(), m_entries.cend(),
                             [family](const Entry &entry) { return entry.family == family; }));
}

int VoicePickerModel::namedCount() const noexcept
{
    return int(std::count_if(m_entries.cbegin(), m_entries.cend(),
                             [](const Entry &entry) { return !entry.displayName.isEmpty(); }));
}

int VoicePickerModel::usedCount() const noexcept
{
    return int(std::count_if(m_entries.cbegin(), m_entries.cend(),
                             [](const Entry &entry) { return entry.used; }));
}


VoicePicker::VoicePicker(SongView &owner, QString title, int initialVoice, QObject *parent)
    : QObject(parent)
    , m_owner(owner)
    , m_model(owner, this)
    , m_title(std::move(title))
    , m_appearance(voicePickerAppearanceFor())
{
    const int clampedInitial = std::clamp(initialVoice, 0, cMaxVoiceProgram);
    setCurrentProgram(m_model.rowForProgram(clampedInitial) >= 0 ? clampedInitial
                                                                 : m_model.firstProgram());
}

VoicePicker::~VoicePicker()
{
    releaseHeld();
}

QVariantMap VoicePicker::voicePickerAppearance() const
{
    return m_appearance;
}
QVariantList VoicePicker::familyFacets() const
{
    QVariantList facets;
    facets.reserve(int(kFamilies.size()) + 1);
    facets.append(QVariantMap{{QStringLiteral("index"), -1},
                              {QStringLiteral("label"), tr("All families")},
                              {QStringLiteral("count"), int(VoicePickerModel::cVoiceCount)}});
    for (std::size_t index = 0; index < kFamilies.size(); ++index) {
        const VoiceFamily family = kFamilies[index];
        facets.append(QVariantMap{{QStringLiteral("index"), int(index)},
                                  {QStringLiteral("label"), familyLabel(family)},
                                  {QStringLiteral("count"), m_model.familyCount(family)}});
    }
    return facets;
}


int VoicePicker::currentRow() const noexcept
{
    return m_model.rowForProgram(m_currentProgram);
}

bool VoicePicker::hasMatch() const noexcept
{
    return m_currentProgram >= 0;
}

void VoicePicker::setFilter(const QString &filter)
{
    if (filter == m_filter)
        return;
    m_filter = filter;
    applyFilters();
}

void VoicePicker::setSelectedFamily(int family)
{
    const int normalized = family >= 0 && family < int(kFamilies.size()) ? family : -1;
    if (normalized == m_selectedFamily)
        return;
    m_selectedFamily = normalized;
    applyFilters();
}

void VoicePicker::setUsedOnly(bool enabled)
{
    if (enabled == m_usedOnly)
        return;
    m_usedOnly = enabled;
    applyFilters();
}

void VoicePicker::setNamedOnly(bool enabled)
{
    if (enabled == m_namedOnly)
        return;
    m_namedOnly = enabled;
    applyFilters();
}

void VoicePicker::clearFilters()
{
    if (m_filter.isEmpty() && m_selectedFamily < 0 && !m_usedOnly && !m_namedOnly)
        return;
    m_filter.clear();
    m_selectedFamily = -1;
    m_usedOnly = false;
    m_namedOnly = false;
    applyFilters();
}

void VoicePicker::applyFilters()
{
    const std::optional<VoiceFamily> family =
        m_selectedFamily >= 0 ? std::optional<VoiceFamily>(kFamilies[m_selectedFamily])
                              : std::nullopt;
    m_model.setFilters(m_filter, family, m_usedOnly, m_namedOnly);
    if (m_model.rowForProgram(m_soundingProgram) < 0)
        releaseHeld();
    setCurrentProgram(m_model.firstProgram());
    emit filtersChanged();
}

void VoicePicker::selectRow(int row)
{
    setCurrentProgram(m_model.programAt(row));
}

void VoicePicker::pressAndHold(int program)
{
    if (!m_owner.isCurrentVoicePicker(this) || m_model.rowForProgram(program) < 0)
        return;

    releaseHeld();
    m_soundingProgram = program;
    emit m_owner.auditionVoice(program, kVoiceAuditionKey, kVoiceAuditionVel);
}

void VoicePicker::releaseHeld()
{
    if (m_soundingProgram < 0)
        return;

    emit m_owner.auditionVoice(m_soundingProgram, kVoiceAuditionKey, 0);
    m_soundingProgram = -1;
}

void VoicePicker::accept()
{
    if (!hasMatch())
        return;

    releaseHeld();
    emit accepted(m_currentProgram);
}

void VoicePicker::cancel()
{
    releaseHeld();
    emit rejected();
}

void VoicePicker::setCurrentProgram(int program)
{
    if (program == m_currentProgram)
        return;

    m_currentProgram = program;
    emit currentRowChanged();
    if (m_currentProgram >= 0)
        emit selectionChanged(m_currentProgram);
}

} // namespace songview
