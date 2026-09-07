// -------------------------------------------------------------- VoicePicker
//
// The voice picker is a typed Quick-popup bridge. It keeps the 128 labels
// stable for one session, filters them only when search text changes, and
// pairs every held preview note-on with a release.

#include "ui/songview/voicepicker.h"

#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/theme/themeruntime.h"

#include <algorithm>

namespace lyt = ::layout;
using Space = lyt::Space;

namespace {

constexpr int cMaxVoiceProgram = int(songview::VoicePickerModel::cVoiceCount) - 1;

QVariantMap voicePickerAppearanceFor(const SongView &owner)
{
    QVariantMap appearance;
    appearance.insert(QStringLiteral("font"), owner.font());
    appearance.insert(QStringLiteral("background"), themes::color(themes::Role::window_background));
    appearance.insert(QStringLiteral("outline"), themes::color(themes::Role::palette_outline));
    appearance.insert(QStringLiteral("text"), themes::color(themes::Role::window_text));
    appearance.insert(QStringLiteral("focus"), themes::color(themes::Role::focus_outline));
    appearance.insert(QStringLiteral("buttonBackground"),
                      themes::color(themes::Role::button_background));
    appearance.insert(QStringLiteral("buttonText"), themes::color(themes::Role::button_text));
    appearance.insert(QStringLiteral("pressedBackground"),
                      themes::color(themes::Role::button_pressed_background));
    appearance.insert(QStringLiteral("borderWidth"), lyt::singlePixel());
    appearance.insert(QStringLiteral("radius"), lyt::space(Space::Half));
    appearance.insert(QStringLiteral("dialogPadding"), lyt::space(Space::One));
    appearance.insert(QStringLiteral("horizontalPadding"), lyt::space(Space::One));
    appearance.insert(QStringLiteral("verticalPadding"), lyt::space(Space::Half));
    appearance.insert(QStringLiteral("buttonPadding"), lyt::space(Space::One));
    appearance.insert(QStringLiteral("spacing"), lyt::space(Space::One));
    appearance.insert(QStringLiteral("minimumWidth"), lyt::fontPx(30.0));
    appearance.insert(QStringLiteral("listHeight"), lyt::fontPx(110.0 / 3.0));
    return appearance;
}

} // namespace

namespace songview {
using namespace songview::detail;

VoicePickerModel::VoicePickerModel(SongView &owner, QObject *parent) : QAbstractListModel(parent)
{
    m_visiblePrograms.reserve(m_entries.size());
    for (int program = 0; program < int(m_entries.size()); ++program) {
        m_entries[static_cast<std::size_t>(program)] = {
            program,
            QStringLiteral("%1  %2")
                .arg(program, 3, 10, QLatin1Char('0'))
                .arg(owner.voiceShortName(uint8_t(program))),
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

void VoicePickerModel::setFilter(const QString &filter)
{
    std::vector<int> visiblePrograms;
    visiblePrograms.reserve(m_entries.size());
    for (const Entry &entry : m_entries) {
        if (entry.label.contains(filter, Qt::CaseInsensitive))
            visiblePrograms.push_back(entry.program);
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

VoicePicker::VoicePicker(SongView &owner, QString title, int initialVoice, QObject *parent)
    : QObject(parent)
    , m_owner(owner)
    , m_model(owner, this)
    , m_title(std::move(title))
    , m_appearance(voicePickerAppearanceFor(owner))
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
    m_model.setFilter(m_filter);
    if (m_model.rowForProgram(m_soundingProgram) < 0)
        releaseHeld();
    setCurrentProgram(m_model.firstProgram());
    emit filterChanged();
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
}

} // namespace songview
