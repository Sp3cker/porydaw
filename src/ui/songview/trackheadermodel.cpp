#include "ui/songview/trackheadermodel.h"

#include "core/songdocument.h"
#include "ui/keymap.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"

#include <QAction>
#include <QApplication>
#include <QCursor>
#include <QKeySequence>
#include <QMenu>
#include <QPalette>
#include <QPointer>
#include <QRect>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <utility>

namespace lyt = ::layout;
using Space = lyt::Space;

namespace songview {
namespace {

const QHash<int, QByteArray> &trackHeaderRoleNames()
{
    static const QHash<int, QByteArray> names = [] {
        QHash<int, QByteArray> result;
        result.insert(TrackHeaderModel::IsAddTrackRole, QByteArrayLiteral("isAddTrack"));
        result.insert(TrackHeaderModel::TrackRole, QByteArrayLiteral("track"));
        result.insert(TrackHeaderModel::TitleRole, QByteArrayLiteral("title"));
        result.insert(TrackHeaderModel::SubtitleRole, QByteArrayLiteral("subtitle"));
        result.insert(TrackHeaderModel::ToolTipRole, QByteArrayLiteral("toolTip"));
        result.insert(TrackHeaderModel::TitleRectRole, QByteArrayLiteral("titleRect"));
        result.insert(TrackHeaderModel::SubtitleRectRole, QByteArrayLiteral("subtitleRect"));
        result.insert(TrackHeaderModel::SelectedTitleOffsetRole,
                      QByteArrayLiteral("selectedTitleOffset"));
        result.insert(TrackHeaderModel::BaseColorRole, QByteArrayLiteral("baseColor"));
        result.insert(TrackHeaderModel::OverlayColorRole, QByteArrayLiteral("overlayColor"));
        result.insert(TrackHeaderModel::TitleColorRole, QByteArrayLiteral("titleColor"));
        result.insert(TrackHeaderModel::SubtitleColorRole, QByteArrayLiteral("subtitleColor"));
        result.insert(TrackHeaderModel::TitleFontRole, QByteArrayLiteral("titleFont"));
        result.insert(TrackHeaderModel::SubtitleFontRole, QByteArrayLiteral("subtitleFont"));
        result.insert(TrackHeaderModel::MuteCheckedRole, QByteArrayLiteral("muteChecked"));
        result.insert(TrackHeaderModel::SoloCheckedRole, QByteArrayLiteral("soloChecked"));
        result.insert(TrackHeaderModel::MuteHoveredRole, QByteArrayLiteral("muteHovered"));
        result.insert(TrackHeaderModel::MutePressedRole, QByteArrayLiteral("mutePressed"));
        result.insert(TrackHeaderModel::SoloHoveredRole, QByteArrayLiteral("soloHovered"));
        result.insert(TrackHeaderModel::SoloPressedRole, QByteArrayLiteral("soloPressed"));
        result.insert(TrackHeaderModel::AddHoveredRole, QByteArrayLiteral("addHovered"));
        result.insert(TrackHeaderModel::AddPressedRole, QByteArrayLiteral("addPressed"));
        result.insert(TrackHeaderModel::VoiceHoveredRole, QByteArrayLiteral("voiceHovered"));
        result.insert(TrackHeaderModel::VoicePressedRole, QByteArrayLiteral("voicePressed"));
        result.insert(TrackHeaderModel::ActivityDimColorRole,
                      QByteArrayLiteral("activityDimColor"));
        result.insert(TrackHeaderModel::ActivityActiveColorRole,
                      QByteArrayLiteral("activityActiveColor"));
        result.insert(TrackHeaderModel::ActivityLeftHeightRole,
                      QByteArrayLiteral("activityLeftHeight"));
        result.insert(TrackHeaderModel::ActivityRightHeightRole,
                      QByteArrayLiteral("activityRightHeight"));
        return result;
    }();
    return names;
}

const QList<int> kActivityRoles{TrackHeaderModel::ActivityLeftHeightRole,
                                TrackHeaderModel::ActivityRightHeightRole};
const QList<int> kMuteCheckedRoles{TrackHeaderModel::MuteCheckedRole};
const QList<int> kSoloCheckedRoles{TrackHeaderModel::SoloCheckedRole};

QString shortcutHint(const QString &id, const QString &name)
{
    const QKeySequence sequence = keymap::Registry::instance().bindings(id).value(0);
    return sequence.isEmpty()
               ? name
               : QStringLiteral("%1 (%2)").arg(name, sequence.toString(QKeySequence::NativeText));
}

} // namespace

TrackHeaderModel::Geometry TrackHeaderModel::Geometry::resolve()
{
    return {
        .rowHeight = lyt::fontPx(4.0),
        .activityWidth = lyt::space(Space::One),
        .buttonExtent = lyt::fontPx(1.5),
        .buttonColumnWidth = lyt::fontPx(2.0),
        .textLeft = lyt::fontPx(5.0 / 6.0),

        .renameEditorLeft = lyt::fontPx(0.5),
        .renameEditorTop = lyt::fontPx(1.0 / 6.0),
        .renameEditorRight = lyt::fontPx(8.0 / 3.0),
        .renameEditorHeight = lyt::fontPx(5.0 / 3.0),
        .reorderIndicatorHeight = lyt::fontPx(0.25),
        .separatorWidth = lyt::singlePixel(),
        .scrollbarWidth = lyt::space(Space::Two),
        .scrollbarMinimumThumbHeight = lyt::space(Space::Eight),
    };
}

TrackHeaderModel::TrackHeaderModel(SongView &owner, QObject *parent)
    : QAbstractListModel(parent)
    , m_owner(owner)
    , m_geometry(Geometry::resolve())
{
    setObjectName(QStringLiteral("trackHeaderModel"));
    connect(&m_owner, &SongView::muteMaskChanged, this, &TrackHeaderModel::syncMuteMask);
    connect(&m_owner, &SongView::soloMaskChanged, this, &TrackHeaderModel::syncSoloMask);
    connect(&keymap::Registry::instance(), &keymap::Registry::bindingsChanged, this, [this] {
        if (!m_toolTipVisible)
            return;
        const QString text = toolTipAt(m_toolTipPosition);
        if (text == m_toolTipText)
            return;
        m_toolTipText = text;
        m_toolTipVisible = !text.isEmpty();
        emit toolTipChanged();
    });
    syncAppearance();
}

TrackHeaderModel::~TrackHeaderModel() = default;

int TrackHeaderModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : static_cast<int>(m_rows.size());
}

QVariant TrackHeaderModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.parent().isValid() || index.column() != 0 || index.row() < 0 ||
        index.row() >= static_cast<int>(m_rows.size())) {
        return {};
    }

    const int row = index.row();
    const TrackHeaderRecord &record = m_rows[static_cast<std::size_t>(row)];
    const auto hovered = [this, row](HitTarget target) {
        return m_pointer.hoverRow == row && m_pointer.hoverTarget == target;
    };
    const auto pressed = [this, row, &hovered](HitTarget target) {
        return hovered(target) && m_pointer.pressedRow == row && m_pointer.pressedTarget == target;
    };

    switch (role) {
    case IsAddTrackRole:
        return record.isAddTrack;
    case TrackRole:
        return record.track;
    case TitleRole:
        return record.title;
    case SubtitleRole:
        return record.subtitle;
    case ToolTipRole:
        return record.toolTip;
    case TitleRectRole:
        return record.titleRect;
    case SubtitleRectRole:
        return record.subtitleRect;
    case SelectedTitleOffsetRole:
        return record.selectedTitleOffset;
    case BaseColorRole:
        return record.baseColor;
    case OverlayColorRole:
        return record.overlayColor;
    case TitleColorRole:
        return record.titleColor;
    case SubtitleColorRole:
        return record.subtitleColor;
    case TitleFontRole:
        return record.titleFont;
    case SubtitleFontRole:
        return record.subtitleFont;
    case MuteCheckedRole:
        return record.muted;
    case SoloCheckedRole:
        return record.soloed;
    case MuteHoveredRole:
        return !record.isAddTrack && hovered(HitTarget::Mute);
    case MutePressedRole:
        return !record.isAddTrack && pressed(HitTarget::Mute);
    case SoloHoveredRole:
        return !record.isAddTrack && hovered(HitTarget::Solo);
    case SoloPressedRole:
        return !record.isAddTrack && pressed(HitTarget::Solo);
    case AddHoveredRole:
        return record.isAddTrack && hovered(HitTarget::AddTrack);
    case AddPressedRole:
        return record.isAddTrack && pressed(HitTarget::AddTrack);
    case VoiceHoveredRole:
        return !record.isAddTrack && hovered(HitTarget::Voice);
    case VoicePressedRole:
        return !record.isAddTrack && pressed(HitTarget::Voice);
    case ActivityDimColorRole:
        return record.activityDimColor;
    case ActivityActiveColorRole:
        return record.activityActiveColor;
    case ActivityLeftHeightRole:
        return record.activityLeftHeight;
    case ActivityRightHeightRole:
        return record.activityRightHeight;
    }
    return {};
}

QHash<int, QByteArray> TrackHeaderModel::roleNames() const
{
    return trackHeaderRoleNames();
}

TrackHeaderModel::TrackHeaderRecord
TrackHeaderModel::makeTrackRecord(int track, const TrackActivity &activity, bool playing) const
{
    TrackHeaderRecord record;
    record.track = track;
    record.muted = m_owner.trackMuted(track);
    record.soloed = m_owner.trackSoloed(track);
    const track_activity_render::Colors colors =
        track_activity_render::colors(SongView::trackColor(track));
    record.activityDimColor = colors.dim;
    record.activityActiveColor = colors.active;
    record.activityState = {activity.intensity(track), playing};
    resolveRecordPresentation(record);
    if (m_inputHost) {
        const int meterHeight = std::max(0, rowHeight() - separatorWidth());
        const qreal dpr = m_inputHost->devicePixelRatio();
        record.activityRenderKey =
            track_activity_render::renderKey(record.activityState, meterHeight, dpr);
        record.activityLeftHeight = track_activity_render::snappedHeight(
            record.activityState, record.activityState.intensity.left, meterHeight, dpr);
        record.activityRightHeight = track_activity_render::snappedHeight(
            record.activityState, record.activityState.intensity.right, meterHeight, dpr);
    }
    return record;
}

TrackHeaderModel::TrackHeaderRecord TrackHeaderModel::makeAddTrackRecord() const
{
    TrackHeaderRecord record;
    record.isAddTrack = true;
    record.title = SongView::tr("+ Add track");
    record.toolTip = SongView::tr("Add a track (picks its voice first)");
    return record;
}

void TrackHeaderModel::resolveRecordColors(TrackHeaderRecord &record) const
{
    if (record.isAddTrack || !m_inputHost)
        return;

    const bool primary = m_owner.selectionModel().primaryTrack() == record.track;
    const bool inScope =
        m_owner.selectionModel().resolvedTrackScope(detail::usedTrackMask(m_owner.timeline())) &
        (uint32_t{1} << record.track);
    const QPalette palette = m_inputHost->palette();
    const QColor normalBackdrop = palette.color(QPalette::Window);
    QColor normalBase = normalBackdrop;
    normalBase.setAlpha(255);

    record.baseColor = normalBase;
    record.overlayColor = Qt::transparent;
    record.titleColor = themes::color(themes::Role::song_view_primary_text);
    record.subtitleColor = themes::color(themes::Role::song_view_secondary_text);
    QColor backdrop = normalBackdrop;
    qreal overBudgetMix = 0.6;
    if (primary) {
        backdrop = themes::color(themes::Role::song_view_track_header_selection);
        record.baseColor = backdrop;
        record.baseColor.setAlpha(255);
        record.titleColor = themes::color(themes::Role::song_view_track_header_selection_text);
        record.subtitleColor = record.titleColor;
        overBudgetMix = 0.35;
    } else if (inScope) {
        record.overlayColor = detail::trackHeaderAlsoSelectedColor();
        backdrop = record.overlayColor;
    }

    const SongDocument *document = m_owner.document();
    if (document && record.track >= document->trackBudget()) {
        record.titleColor = mixTowardOklab(record.titleColor, backdrop, overBudgetMix);
        record.subtitleColor = mixTowardOklab(record.subtitleColor, backdrop, overBudgetMix);
    }
}

void TrackHeaderModel::resolveRecordLabels(TrackHeaderRecord &record) const
{
    if (record.isAddTrack)
        return;

    const MidiTimeline *timeline = m_owner.timeline();
    QString name = timeline ? timeline->tracks[record.track].name : QString();
    if (name.isEmpty())
        name = SongView::tr("Track %1").arg(record.track + 1);
    const QString title = QStringLiteral("%1 · %2").arg(record.track + 1).arg(name);
    const QString subtitle = m_owner.instrumentLabel(record.track);
    if (!m_inputHost) {
        record.title = title;
        record.subtitle = subtitle;
        record.titleRect = {};
        record.subtitleRect = {};
        record.selectedTitleOffset = {};
        return;
    }

    const bool primary = m_owner.selectionModel().primaryTrack() == record.track;
    record.titleFont = primary ? m_boldTitleFont : m_normalTitleFont;
    record.subtitleFont = m_subtitleFont;
    const QFontMetrics &titleMetrics = primary ? m_boldTitleMetrics : m_normalTitleMetrics;
    const QRect bounds = textBounds();
    const int textWidth = bounds.width();
    record.title = titleMetrics.elidedText(title, Qt::ElideRight, textWidth);
    record.subtitle = m_subtitleMetrics.elidedText(subtitle, Qt::ElideRight, textWidth);
    const auto boxes = m_textLayout->align(bounds, lyt::VerticalAlignment::Center);
    record.selectedTitleOffset =
        primary ? typography::glyphCenteringOffset(m_normalTitleFont, m_boldTitleFont, record.title)
                : QPointF{};
    record.titleRect = QRectF(boxes.primary);
    record.subtitleRect = QRectF(boxes.secondary);
}

void TrackHeaderModel::resolveRecordToolTip(TrackHeaderRecord &record) const
{
    if (record.isAddTrack)
        return;

    const MidiTimeline *timeline = m_owner.timeline();
    if (!timeline) {
        record.toolTip.clear();
        return;
    }
    record.toolTip = SongView::tr("%1 notes · %2")
                         .arg(timeline->tracks[record.track].noteCount)
                         .arg(m_owner.instrumentLabel(record.track));
    const SongDocument *document = m_owner.document();
    if (document && record.track >= document->trackBudget()) {
        record.toolTip +=
            SongView::tr(
                "\nPossibly incompatible in-game: this song's music player only allocates %1 "
                "track(s) (sound/music_player_table.inc). The track stays audible here.")
                .arg(document->trackBudget());
    }
    if (document) {
        record.toolTip += SongView::tr(
            "\nDouble-click to rename · right-click to change voice, duplicate, or delete"
            " · drag to reorder"
            "\nClick the voice name to show it in the voicegroup dock · double-click it to "
            "change the voice");
    }
}

void TrackHeaderModel::resolveRecordPresentation(TrackHeaderRecord &record) const
{
    resolveRecordColors(record);
    resolveRecordLabels(record);
    resolveRecordToolTip(record);
}

void TrackHeaderModel::rebuild(const TrackActivity &activity, bool playing)
{
    cancelTransientState();

    std::vector<TrackHeaderRecord> next;
    const MidiTimeline *timeline = m_owner.timeline();
    SongDocument *document = m_owner.document();
    if (timeline) {
        next.reserve(17); // 16 engine tracks plus the optional add row.
        for (int track = 0; track < 16; ++track) {
            if (timeline->tracks[track].used)
                next.push_back(makeTrackRecord(track, activity, playing));
        }
        if (document && document->canAddTrack())
            next.push_back(makeAddTrackRecord());
    }

    const bool sameIdentities =
        next.size() == m_rows.size() &&
        std::equal(next.begin(), next.end(), m_rows.begin(),
                   [](const TrackHeaderRecord &left, const TrackHeaderRecord &right) {
                       return left.isAddTrack == right.isAddTrack && left.track == right.track;
                   });
    if (!sameIdentities) {
        beginResetModel();
        m_rows = std::move(next);
        endResetModel();
        emit geometryChanged();
    } else {
        for (std::size_t row = 0; row < m_rows.size(); ++row) {
            TrackHeaderRecord before = m_rows[row];
            m_rows[row] = std::move(next[row]);
            notifyRecordChange(static_cast<int>(row), before, m_rows[row]);
        }
    }
    clampScroll();
}

void TrackHeaderModel::syncSelection()
{
    if (!m_inputHost)
        return;
    for (std::size_t row = 0; row < m_rows.size(); ++row) {
        if (m_rows[row].isAddTrack)
            continue;
        TrackHeaderRecord before = m_rows[row];
        resolveRecordPresentation(m_rows[row]);
        notifyRecordChange(static_cast<int>(row), before, m_rows[row]);
    }
}

void TrackHeaderModel::syncVoices()
{
    for (std::size_t row = 0; row < m_rows.size(); ++row) {
        if (m_rows[row].isAddTrack)
            continue;
        TrackHeaderRecord before = m_rows[row];
        resolveRecordLabels(m_rows[row]);
        resolveRecordToolTip(m_rows[row]);
        notifyRecordChange(static_cast<int>(row), before, m_rows[row]);
    }
}

void TrackHeaderModel::syncActivity(const TrackActivity &activity, bool playing)
{
    refreshActivityHeights(&activity, playing);
}

void TrackHeaderModel::syncStoredActivityHeights()
{
    refreshActivityHeights(nullptr, false);
}

void TrackHeaderModel::refreshActivityHeights(const TrackActivity *activity, bool playing)
{
    const bool refreshState = activity != nullptr;
    if (!m_inputHost && !refreshState)
        return;

    const int meterHeight = m_inputHost ? std::max(0, rowHeight() - separatorWidth()) : 0;
    const qreal dpr = m_inputHost ? m_inputHost->devicePixelRatio() : 0.0;
    int firstChanged = -1;
    int lastChanged = -1;
    for (std::size_t row = 0; row < m_rows.size(); ++row) {
        TrackHeaderRecord &record = m_rows[row];
        if (record.isAddTrack)
            continue;

        if (refreshState) {
            const track_activity_render::State state{activity->intensity(record.track), playing};
            if (state != record.activityState)
                record.activityState = state;
        }
        if (!m_inputHost)
            continue;

        const auto key = track_activity_render::renderKey(record.activityState, meterHeight, dpr);
        if (key == record.activityRenderKey)
            continue;
        record.activityRenderKey = key;
        record.activityLeftHeight = track_activity_render::snappedHeight(
            record.activityState, record.activityState.intensity.left, meterHeight, dpr);
        record.activityRightHeight = track_activity_render::snappedHeight(
            record.activityState, record.activityState.intensity.right, meterHeight, dpr);
        if (firstChanged < 0)
            firstChanged = static_cast<int>(row);
        lastChanged = static_cast<int>(row);
    }
    if (firstChanged >= 0)
        emit dataChanged(index(firstChanged, 0), index(lastChanged, 0), kActivityRoles);
}

void TrackHeaderModel::syncMuteMask(uint32_t mask)
{
    syncCheckedMask(mask, &TrackHeaderRecord::muted, MuteCheckedRole);
}

void TrackHeaderModel::syncSoloMask(uint32_t mask)
{
    syncCheckedMask(mask, &TrackHeaderRecord::soloed, SoloCheckedRole);
}

void TrackHeaderModel::syncCheckedMask(uint32_t mask, bool TrackHeaderRecord::*member, int role)
{
    const QList<int> &roles = role == MuteCheckedRole ? kMuteCheckedRoles : kSoloCheckedRoles;
    int first = -1;
    for (std::size_t row = 0; row < m_rows.size(); ++row) {
        TrackHeaderRecord &record = m_rows[row];
        const bool checked = !record.isAddTrack && bool(mask & (uint32_t{1} << record.track));
        if (checked == (record.*member)) {
            if (first >= 0) {
                emit dataChanged(index(first, 0), index(static_cast<int>(row) - 1, 0), roles);
                first = -1;
            }
            continue;
        }
        (record.*member) = checked;
        if (first < 0)
            first = static_cast<int>(row);
    }
    if (first >= 0)
        emit dataChanged(index(first, 0), index(static_cast<int>(m_rows.size()) - 1, 0), roles);
}

void TrackHeaderModel::syncAppearance()
{
    QVariantMap next;
    next.insert(QStringLiteral("buttonBackground"), themes::color(themes::Role::button_background));
    next.insert(QStringLiteral("buttonText"), themes::color(themes::Role::button_text));
    next.insert(QStringLiteral("buttonHoverBackground"),
                themes::color(themes::Role::button_hover_background));
    next.insert(QStringLiteral("buttonHoverText"), themes::color(themes::Role::button_hover_text));
    next.insert(QStringLiteral("buttonPressedBackground"),
                themes::color(themes::Role::button_pressed_background));
    next.insert(QStringLiteral("buttonPressedText"),
                themes::color(themes::Role::button_pressed_text));
    next.insert(QStringLiteral("buttonOutline"), themes::color(themes::Role::button_outline));
    next.insert(QStringLiteral("focusOutline"), themes::color(themes::Role::focus_outline));
    next.insert(QStringLiteral("muteCheckedBackground"),
                themes::color(themes::Role::track_mute_checked_background));
    next.insert(QStringLiteral("muteCheckedText"),
                themes::color(themes::Role::track_mute_checked_text));
    next.insert(QStringLiteral("soloCheckedBackground"),
                themes::color(themes::Role::track_solo_checked_background));
    next.insert(QStringLiteral("soloCheckedText"),
                themes::color(themes::Role::track_solo_checked_text));
    next.insert(QStringLiteral("inputBackground"), themes::color(themes::Role::input_background));
    next.insert(QStringLiteral("inputText"), themes::color(themes::Role::input_text));
    next.insert(QStringLiteral("inputOutline"), themes::color(themes::Role::input_outline));
    next.insert(QStringLiteral("scrollbarHandle"), themes::color(themes::Role::scrollbar_handle));
    next.insert(QStringLiteral("scrollbarHandleHover"),
                themes::color(themes::Role::scrollbar_handle_hover_background));
    next.insert(QStringLiteral("toolTipBackground"),
                themes::color(themes::Role::tooltip_background));
    next.insert(QStringLiteral("toolTipText"), themes::color(themes::Role::tooltip_text));
    next.insert(QStringLiteral("toolTipOutline"), themes::color(themes::Role::tooltip_outline));
    next.insert(QStringLiteral("reorderIndicator"),
                m_inputHost ? m_inputHost->palette().color(QPalette::Highlight)
                            : QColor(Qt::transparent));
    if (next != m_appearance) {
        m_appearance = std::move(next);
        emit appearanceChanged();
    }

    if (!m_inputHost)
        return;
    for (std::size_t row = 0; row < m_rows.size(); ++row) {
        if (m_rows[row].isAddTrack)
            continue;
        TrackHeaderRecord before = m_rows[row];
        resolveRecordColors(m_rows[row]);
        notifyRecordChange(static_cast<int>(row), before, m_rows[row]);
    }
}

void TrackHeaderModel::beginRename(int track)
{
    SongDocument *document = m_owner.document();
    if (!document || track < 0 || track >= 16 || document->smfTrackFor(track) < 0 ||
        std::none_of(
            m_rows.begin(), m_rows.end(),
            [track](const TrackHeaderRecord &record) { return record.track == track; })) {
        return;
    }
    if (m_renamingTrack == track)
        return;
    cancelRename();
    m_renamingTrack = track;
    m_renameDraft = document->trackName(track);
    m_renamePlaceholder = SongView::tr("Track %1").arg(track + 1);
    emit renameChanged();
}

void TrackHeaderModel::finishRename(bool commit, bool restoreRollFocus)
{
    if (m_renamingTrack < 0 || m_finishingRename)
        return;

    m_finishingRename = true;
    const int track = m_renamingTrack;
    const QString draft = m_renameDraft;
    m_renamingTrack = -1;
    m_renameDraft.clear();
    m_renamePlaceholder.clear();
    emit renameChanged();
    if (restoreRollFocus)
        m_owner.focusContent();
    if (commit)
        m_owner.commitTrackRename(track, draft);
    m_finishingRename = false;
}

void TrackHeaderModel::cancelRename()
{
    if (m_renamingTrack < 0 || m_finishingRename)
        return;
    m_renamingTrack = -1;
    m_renameDraft.clear();
    m_renamePlaceholder.clear();
    emit renameChanged();
}

void TrackHeaderModel::activateMute(int track)
{
    if (std::none_of(m_rows.begin(), m_rows.end(), [track](const TrackHeaderRecord &record) {
            return !record.isAddTrack && record.track == track;
        })) {
        return;
    }
    m_owner.setTrackMute(track, !m_owner.trackMuted(track));
}

void TrackHeaderModel::activateSolo(int track)
{
    if (std::none_of(m_rows.begin(), m_rows.end(), [track](const TrackHeaderRecord &record) {
            return !record.isAddTrack && record.track == track;
        })) {
        return;
    }
    m_owner.setTrackSolo(track, !m_owner.trackSoloed(track));
}

void TrackHeaderModel::activateAddTrack()
{
    SongDocument *document = m_owner.document();
    if (!document || !document->canAddTrack())
        return;
    QPointer<SongView> owner(&m_owner);
    m_owner.queueHeaderMutation([owner] {
        if (owner)
            owner->addTrack();
    });
}

QRect TrackHeaderModel::textBounds() const
{
    Q_ASSERT(m_inputHost);
    if (!m_inputHost)
        return {};
    const int rowWidth = qRound(m_inputHost->bounds().width());
    const int textWidth = std::max(0, rowWidth - m_geometry.buttonColumnWidth -
                                          m_geometry.textLeft - lyt::space(Space::One));
    return {m_geometry.textLeft, 0, textWidth, std::max(0, rowHeight() - separatorWidth())};
}

int TrackHeaderModel::rowHeight() const noexcept
{
    return m_geometry.rowHeight;
}

int TrackHeaderModel::activityWidth() const noexcept
{
    return m_geometry.activityWidth;
}

int TrackHeaderModel::scrollbarWidth() const noexcept
{
    return m_geometry.scrollbarWidth;
}

int TrackHeaderModel::scrollbarMinimumThumbHeight() const noexcept
{
    return m_geometry.scrollbarMinimumThumbHeight;
}

int TrackHeaderModel::reorderIndicatorHeight() const noexcept
{
    return m_geometry.reorderIndicatorHeight;
}

int TrackHeaderModel::separatorWidth() const noexcept
{
    return m_geometry.separatorWidth;
}

QRectF TrackHeaderModel::muteButtonRect() const
{
    if (!m_inputHost)
        return {};
    const int gap = std::max(0, rowHeight() - separatorWidth() - 2 * m_geometry.buttonExtent);
    const int topGap = gap / 3;
    const qreal x =
        m_inputHost->bounds().width() - lyt::space(Space::One) - m_geometry.buttonExtent;
    return {x, qreal(topGap), qreal(m_geometry.buttonExtent), qreal(m_geometry.buttonExtent)};
}

QRectF TrackHeaderModel::soloButtonRect() const
{
    if (!m_inputHost)
        return {};
    const int gap = std::max(0, rowHeight() - separatorWidth() - 2 * m_geometry.buttonExtent);
    const int topGap = gap / 3;
    const int middleGap = gap / 3;
    const qreal x =
        m_inputHost->bounds().width() - lyt::space(Space::One) - m_geometry.buttonExtent;
    return {x, qreal(topGap + m_geometry.buttonExtent + middleGap), qreal(m_geometry.buttonExtent),
            qreal(m_geometry.buttonExtent)};
}

QRectF TrackHeaderModel::voiceLineRect() const
{
    if (!m_inputHost || !m_textLayout)
        return {};
    return QRectF(m_textLayout->align(textBounds(), lyt::VerticalAlignment::Center).secondary);
}

QRectF TrackHeaderModel::renameEditorRect() const
{
    if (!m_inputHost)
        return {};
    return {qreal(m_geometry.renameEditorLeft), qreal(m_geometry.renameEditorTop),
            std::max<qreal>(0.0, m_inputHost->bounds().width() - m_geometry.renameEditorRight),
            qreal(m_geometry.renameEditorHeight)};
}

int TrackHeaderModel::contentHeight() const noexcept
{
    return static_cast<int>(m_rows.size()) * rowHeight();
}

int TrackHeaderModel::renamingTrack() const noexcept
{
    return m_renamingTrack;
}

QString TrackHeaderModel::renameDraft() const
{
    return m_renameDraft;
}

void TrackHeaderModel::setRenameDraft(const QString &text)
{
    if (m_renameDraft == text)
        return;
    m_renameDraft = text;
    emit renameChanged();
}

QString TrackHeaderModel::renamePlaceholder() const
{
    return m_renamePlaceholder;
}

qreal TrackHeaderModel::scrollY() const noexcept
{
    return m_scrollY;
}

qreal TrackHeaderModel::maximumScrollY() const noexcept
{
    return m_inputHost ? std::max<qreal>(0.0, contentHeight() - viewportHeight()) : 0.0;
}

qreal TrackHeaderModel::viewportHeight() const noexcept
{
    return m_inputHost ? std::max<qreal>(0.0, m_inputHost->bounds().height()) : 0.0;
}

void TrackHeaderModel::clampScroll()
{
    clearToolTip();
    const qreal maximum = maximumScrollY();
    const qreal next = std::isfinite(m_scrollY) ? std::clamp(m_scrollY, qreal(0.0), maximum) : 0.0;
    if (next == m_scrollY)
        return;
    m_scrollY = next;
    emit scrollChanged();
}

void TrackHeaderModel::setScrollY(qreal value)
{
    clearToolTip();
    if (!std::isfinite(value))
        value = 0.0;
    const qreal next = std::clamp(value, qreal(0.0), maximumScrollY());
    if (next == m_scrollY)
        return;
    m_scrollY = next;
    emit scrollChanged();
}

bool TrackHeaderModel::reorderIndicatorVisible() const noexcept
{
    return m_reorderIndicatorVisible;
}

qreal TrackHeaderModel::reorderIndicatorY() const noexcept
{
    return m_reorderIndicatorY;
}

bool TrackHeaderModel::toolTipVisible() const noexcept
{
    return m_toolTipVisible;
}

QString TrackHeaderModel::toolTipText() const
{
    return m_toolTipText;
}

QPointF TrackHeaderModel::toolTipPosition() const noexcept
{
    return m_toolTipPosition;
}

QVariantMap TrackHeaderModel::appearance() const
{
    return m_appearance;
}

void TrackHeaderModel::cancelTransientState()
{
    finishReorder(false);
    clearPointerVisuals();
    cancelRename();
    clearToolTip();
    if (m_inputHost)
        m_inputHost->releasePointerGrab();
}

void TrackHeaderModel::attachInputHost(TimelineInputHost &host)
{
    Q_ASSERT(!m_inputHost);
    if (m_inputHost)
        return;

    m_inputHost = &host;
    m_normalTitleFont = host.font();
    m_boldTitleFont = typography::bold(m_normalTitleFont);
    m_subtitleFont = typography::caption(m_normalTitleFont);
    m_normalTitleMetrics = QFontMetrics(m_normalTitleFont);
    m_boldTitleMetrics = QFontMetrics(m_boldTitleFont);
    m_subtitleMetrics = QFontMetrics(m_subtitleFont);
    m_textLayout.emplace(
        lyt::twoLineText(m_normalTitleFont, m_boldTitleFont, m_subtitleFont, Space::Half));
    syncAppearance();
    syncRecordGeometry();
    syncStoredActivityHeights();
    emit geometryChanged();
    clampScroll();
    updateAccessibilityDescription();
}

void TrackHeaderModel::detachInputHost(TimelineInputHost &host)
{
    Q_ASSERT(m_inputHost == &host);
    if (m_inputHost != &host)
        return;
    cancelTransientState();
    host.clearCursor();
    m_inputHost = nullptr;
}

void TrackHeaderModel::hostAppearanceChanged()
{
    if (!m_inputHost)
        return;
    syncAppearance();
    syncRecordGeometry();
    syncStoredActivityHeights();
    emit geometryChanged();
    clampScroll();
}

int TrackHeaderModel::rowAt(qreal bandY) const
{
    if (rowHeight() <= 0)
        return -1;
    const qreal y = contentY(bandY);
    const int row = static_cast<int>(std::floor(y / rowHeight()));
    return row >= 0 && row < static_cast<int>(m_rows.size()) ? row : -1;
}

int TrackHeaderModel::trackAt(qreal bandY) const
{
    const int row = rowAt(bandY);
    return row >= 0 && !m_rows[static_cast<std::size_t>(row)].isAddTrack
               ? m_rows[static_cast<std::size_t>(row)].track
               : -1;
}
int TrackHeaderModel::trackRowCount() const noexcept
{
    int count = 0;
    while (count < static_cast<int>(m_rows.size()) &&
           !m_rows[static_cast<std::size_t>(count)].isAddTrack) {
        ++count;
    }
    return count;
}

qreal TrackHeaderModel::contentY(qreal bandY) const
{
    return bandY + m_scrollY;
}

QRectF TrackHeaderModel::rowLocalRect(const QRectF &rect, qreal bandY) const
{
    const int row = rowAt(bandY);
    return row < 0 ? QRectF{} : rect.translated(0.0, row * rowHeight() - m_scrollY);
}

TrackHeaderModel::HitTarget TrackHeaderModel::hitTarget(int row, const QPointF &bandPosition) const
{
    if (row < 0 || row >= static_cast<int>(m_rows.size()))
        return HitTarget::None;
    if (m_rows[static_cast<std::size_t>(row)].isAddTrack)
        return HitTarget::AddTrack;
    if (rowLocalRect(muteButtonRect(), bandPosition.y()).contains(bandPosition))
        return HitTarget::Mute;
    if (rowLocalRect(soloButtonRect(), bandPosition.y()).contains(bandPosition))
        return HitTarget::Solo;
    if (rowLocalRect(voiceLineRect(), bandPosition.y()).contains(bandPosition))
        return HitTarget::Voice;
    return HitTarget::Body;
}

void TrackHeaderModel::notifyPointerChanges(const PointerState &before)
{
    const auto visual = [](const PointerState &state, int row, HitTarget target, bool pressed) {
        return pressed ? state.pressedRow == row && state.pressedTarget == target &&
                             state.hoverRow == row && state.hoverTarget == target
                       : state.hoverRow == row && state.hoverTarget == target;
    };
    const std::array<int, 4> candidates{before.hoverRow, before.pressedRow, m_pointer.hoverRow,
                                        m_pointer.pressedRow};
    for (std::size_t i = 0; i < candidates.size(); ++i) {
        const int row = candidates[i];
        if (row < 0 || row >= static_cast<int>(m_rows.size()) ||
            std::find(candidates.begin(), candidates.begin() + static_cast<std::ptrdiff_t>(i),
                      row) != candidates.begin() + static_cast<std::ptrdiff_t>(i)) {
            continue;
        }
        QList<int> roles;
        if (visual(before, row, HitTarget::Mute, false) !=
            visual(m_pointer, row, HitTarget::Mute, false)) {
            roles.append(MuteHoveredRole);
        }
        if (visual(before, row, HitTarget::Mute, true) !=
            visual(m_pointer, row, HitTarget::Mute, true)) {
            roles.append(MutePressedRole);
        }
        if (visual(before, row, HitTarget::Solo, false) !=
            visual(m_pointer, row, HitTarget::Solo, false)) {
            roles.append(SoloHoveredRole);
        }
        if (visual(before, row, HitTarget::Solo, true) !=
            visual(m_pointer, row, HitTarget::Solo, true)) {
            roles.append(SoloPressedRole);
        }
        if (visual(before, row, HitTarget::AddTrack, false) !=
            visual(m_pointer, row, HitTarget::AddTrack, false)) {
            roles.append(AddHoveredRole);
        }
        if (visual(before, row, HitTarget::AddTrack, true) !=
            visual(m_pointer, row, HitTarget::AddTrack, true)) {
            roles.append(AddPressedRole);
        }
        if (visual(before, row, HitTarget::Voice, false) !=
            visual(m_pointer, row, HitTarget::Voice, false)) {
            roles.append(VoiceHoveredRole);
        }
        if (visual(before, row, HitTarget::Voice, true) !=
            visual(m_pointer, row, HitTarget::Voice, true)) {
            roles.append(VoicePressedRole);
        }
        if (!roles.isEmpty())
            emit dataChanged(index(row, 0), index(row, 0), roles);
    }
}

void TrackHeaderModel::updatePointerVisuals(int row, HitTarget target, bool pressed)
{
    PointerState before = m_pointer;
    m_pointer.hoverRow = row;
    m_pointer.hoverTarget = target;
    if (pressed) {
        m_pointer.pressedRow = row;
        m_pointer.pressedTarget = target;
    }
    notifyPointerChanges(before);
}

void TrackHeaderModel::clearPointerVisuals()
{
    PointerState before = m_pointer;
    m_pointer = {};
    notifyPointerChanges(before);
}

bool TrackHeaderModel::pointerPress(const TimelinePointerInput &input)
{
    Q_ASSERT(m_inputHost);
    if (!m_inputHost)
        return false;

    clearToolTip();
    const int row = rowAt(input.position.y());
    if (row < 0)
        return false;
    const HitTarget target = hitTarget(row, input.position);
    if (input.button == Qt::RightButton && (input.buttons & Qt::LeftButton))
        return true;

    clearPointerVisuals();
    if (target == HitTarget::AddTrack) {
        if (input.button != Qt::LeftButton)
            return true;
        m_pointer.pressedTrack = -1;
        m_pointer.pressPosition = input.position;
        updatePointerVisuals(row, target, true);
        return true;
    }
    if ((target == HitTarget::Mute || target == HitTarget::Solo) &&
        input.button == Qt::LeftButton) {
        m_pointer.pressedTrack = m_rows[static_cast<std::size_t>(row)].track;
        m_pointer.pressPosition = input.position;
        updatePointerVisuals(row, target, true);
        return true;
    }

    const int track = m_rows[static_cast<std::size_t>(row)].track;
    if (input.button == Qt::RightButton) {
        m_owner.selectTrack(track);
        showContextMenu(track, m_inputHost->mapToGlobal(input.position));
        return true;
    }

    m_owner.trackHeaderClicked(track, input.modifiers);
    const bool plainLeft = input.button == Qt::LeftButton &&
                           !(input.modifiers & (Qt::ControlModifier | Qt::ShiftModifier)) &&
                           m_owner.document();
    if (plainLeft) {
        m_pointer.pressedTrack = track;
        m_pointer.pressPosition = input.position;
        m_pointer.dragArmed = true;
        updatePointerVisuals(row, target, true);
    }
    return true;
}

bool TrackHeaderModel::pointerDoubleClick(const TimelinePointerInput &input)
{
    Q_ASSERT(m_inputHost);
    if (!m_inputHost)
        return false;

    clearToolTip();
    const int row = rowAt(input.position.y());
    if (row < 0)
        return false;
    const HitTarget target = hitTarget(row, input.position);
    clearPointerVisuals();
    if (target == HitTarget::AddTrack || target == HitTarget::Mute || target == HitTarget::Solo)
        return true;

    const int track = m_rows[static_cast<std::size_t>(row)].track;
    m_owner.selectTrack(track);
    if (target == HitTarget::Voice) {
        QPointer<SongView> owner(&m_owner);
        m_owner.queueHeaderMutation([owner, track] {
            if (owner)
                owner->editTrackVoice(track);
        });
    } else {
        beginRename(track);
    }
    return true;
}

bool TrackHeaderModel::pointerMove(const TimelinePointerInput &input)
{
    Q_ASSERT(m_inputHost);
    if (!m_inputHost)
        return false;

    const int row = rowAt(input.position.y());
    const HitTarget target = row >= 0 ? hitTarget(row, input.position) : HitTarget::None;
    updatePointerVisuals(row, target, false);
    if (m_pointer.dragging) {
        updateReorder(input.position);
        clearToolTip();
        return true;
    }
    if (m_pointer.dragArmed && (input.buttons & Qt::LeftButton) &&
        (input.position - m_pointer.pressPosition).manhattanLength() >=
            QApplication::startDragDistance()) {
        beginReorder(m_pointer.pressedTrack, input.position);
        return m_pointer.dragging;
    }
    if (row >= 0)
        updateToolTip(input);
    else
        clearToolTip();
    return row >= 0 || m_pointer.pressedRow >= 0;
}

bool TrackHeaderModel::pointerRelease(const TimelinePointerInput &input)
{
    Q_ASSERT(m_inputHost);
    if (!m_inputHost)
        return false;

    clearToolTip();
    if (m_pointer.dragging) {
        finishReorder(input.button == Qt::LeftButton);
        clearPointerVisuals();
        return true;
    }
    if (m_pointer.pressedRow < 0)
        return false;
    if (input.button != Qt::LeftButton) {
        clearPointerVisuals();
        return true;
    }

    const int pressedRow = m_pointer.pressedRow;
    const int pressedTrack = m_pointer.pressedTrack;
    const HitTarget pressedTarget = m_pointer.pressedTarget;
    const int row = rowAt(input.position.y());
    const HitTarget target = row >= 0 ? hitTarget(row, input.position) : HitTarget::None;
    clearPointerVisuals();
    if (row != pressedRow || target != pressedTarget)
        return true;

    switch (pressedTarget) {
    case HitTarget::AddTrack:
        activateAddTrack();
        break;
    case HitTarget::Mute:
        activateMute(pressedTrack);
        break;
    case HitTarget::Solo:
        activateSolo(pressedTrack);
        break;
    case HitTarget::Voice:
        m_owner.revealTrackVoice(pressedTrack);
        break;
    case HitTarget::None:
    case HitTarget::Body:
        break;
    }
    return true;
}

void TrackHeaderModel::pointerLeave()
{
    if (m_pointer.dragging) {
        PointerState before = m_pointer;
        m_pointer.hoverRow = -1;
        m_pointer.hoverTarget = HitTarget::None;
        notifyPointerChanges(before);
    } else {
        clearPointerVisuals();
    }
    clearToolTip();
}

bool TrackHeaderModel::scrollVertically(const TimelineWheelInput &input)
{
    const QPoint pixel = input.pixelDelta;
    const QPoint angle = input.angleDelta;
    qreal delta = 0.0;
    if (!pixel.isNull()) {
        if (std::abs(pixel.x()) > std::abs(pixel.y()) || pixel.y() == 0)
            return false;
        delta = pixel.y();
    } else {
        if (std::abs(angle.x()) > std::abs(angle.y()) || angle.y() == 0)
            return false;
        delta = qreal(angle.y()) / 120.0 * rowHeight();
    }
    setScrollY(m_scrollY + (input.inverted ? delta : -delta));
    return true;
}

bool TrackHeaderModel::wheel(const TimelineWheelInput &input)
{
    clearToolTip();
    return scrollVertically(input);
}

void TrackHeaderModel::inputCancelled(TimelineInputCancelReason)
{
    finishReorder(false);
    clearPointerVisuals();
    clearToolTip();
}

QString TrackHeaderModel::toolTipAt(const QPointF &bandPosition) const
{
    const int row = rowAt(bandPosition.y());
    if (row < 0)
        return {};
    switch (hitTarget(row, bandPosition)) {
    case HitTarget::Mute:
        return shortcutHint(QStringLiteral("roll.mute_tracks"), SongView::tr("Mute"));
    case HitTarget::Solo:
        return shortcutHint(QStringLiteral("roll.solo_tracks"), SongView::tr("Solo"));
    case HitTarget::AddTrack:
        return SongView::tr("Add a track (picks its voice first)");
    case HitTarget::None:
        return {};
    case HitTarget::Body:
    case HitTarget::Voice:
        return m_rows[static_cast<std::size_t>(row)].toolTip;
    }
    return {};
}

void TrackHeaderModel::updateToolTip(const TimelinePointerInput &input)
{
    const QString text = toolTipAt(input.position);
    if (text.isEmpty()) {
        clearToolTip();
        return;
    }
    if (m_toolTipVisible && m_toolTipText == text && m_toolTipPosition == input.position)
        return;
    m_toolTipVisible = true;
    m_toolTipText = text;
    m_toolTipPosition = input.position;
    emit toolTipChanged();
}

void TrackHeaderModel::clearToolTip()
{
    if (!m_toolTipVisible && m_toolTipText.isEmpty() && m_toolTipPosition.isNull())
        return;
    m_toolTipVisible = false;
    m_toolTipText.clear();
    m_toolTipPosition = {};
    emit toolTipChanged();
}

void TrackHeaderModel::beginReorder(int track, const QPointF &position)
{
    Q_ASSERT(m_inputHost);
    if (!m_inputHost || m_pointer.dragging || !m_owner.document() || track < 0)
        return;
    if (trackRowCount() < 2)
        return;
    m_pointer.dragging = true;
    m_pointer.dragArmed = false;
    m_inputHost->setCursor(QCursor(Qt::ClosedHandCursor));
    updateReorder(position);
}

void TrackHeaderModel::updateReorder(const QPointF &position)
{
    if (!m_pointer.dragging)
        return;
    const int trackRows = trackRowCount();
    int slot = 0;
    const qreal y = contentY(position.y());
    for (; slot < trackRows; ++slot) {
        if (y <= slot * rowHeight() + rowHeight() / 2.0)
            break;
    }
    const qreal indicatorY = slot * rowHeight() - m_scrollY;
    if (m_reorderIndicatorVisible && m_reorderIndicatorY == indicatorY)
        return;
    m_reorderIndicatorVisible = true;
    m_reorderIndicatorY = indicatorY;
    emit reorderChanged();
}

std::optional<int> TrackHeaderModel::reorderTarget(int fromTrack, int dropSlot) const
{
    const int trackRows = trackRowCount();
    if (dropSlot < 0 || dropSlot > trackRows)
        return std::nullopt;

    int fromIndex = -1;
    for (int row = 0; row < trackRows; ++row) {
        if (m_rows[static_cast<std::size_t>(row)].track == fromTrack) {
            fromIndex = row;
            break;
        }
    }
    if (fromIndex < 0 || dropSlot == fromIndex || dropSlot == fromIndex + 1)
        return std::nullopt;
    const int targetIndex = dropSlot > fromIndex ? dropSlot - 1 : dropSlot;
    return m_rows[static_cast<std::size_t>(targetIndex)].track;
}

void TrackHeaderModel::finishReorder(bool commit)
{
    if (!m_pointer.dragging)
        return;

    const int fromTrack = m_pointer.pressedTrack;
    const int dropSlot =
        m_reorderIndicatorVisible ? qRound((m_reorderIndicatorY + m_scrollY) / rowHeight()) : -1;
    m_pointer.dragging = false;
    m_pointer.dragArmed = false;
    if (m_reorderIndicatorVisible || m_reorderIndicatorY != 0.0) {
        m_reorderIndicatorVisible = false;
        m_reorderIndicatorY = 0.0;
        emit reorderChanged();
    }
    if (m_inputHost)
        m_inputHost->clearCursor();
    if (!commit)
        return;

    const std::optional<int> target = reorderTarget(fromTrack, dropSlot);
    if (!target)
        return;
    finishRename(true, false);
    QPointer<SongView> owner(&m_owner);
    m_owner.queueHeaderMutation([owner, fromTrack, target = *target] {
        if (owner)
            owner->moveTrack(fromTrack, target);
    });
}

void TrackHeaderModel::showContextMenu(int track, const QPointF &globalPosition)
{
    SongDocument *document = m_owner.document();
    if (!document)
        return;

    QPointer<SongView> owner(&m_owner);
    bool renameRequested = false;
    QMenu menu(&m_owner);
    QAction *changeVoice = menu.addAction(SongView::tr("Change voice..."));
    QAction *showVoice = menu.addAction(SongView::tr("Show voice in voicegroup"));
    QAction *rename = menu.addAction(SongView::tr("Rename track..."));
    QAction *duplicate = menu.addAction(SongView::tr("Duplicate track"));
    duplicate->setEnabled(document->canAddTrack());
    QAction *remove = menu.addAction(SongView::tr("Delete track"));
    connect(rename, &QAction::triggered, this, [&renameRequested] { renameRequested = true; });
    connect(showVoice, &QAction::triggered, this, [owner, track] {
        if (owner)
            owner->revealTrackVoice(track);
    });
    connect(changeVoice, &QAction::triggered, this, [owner, track] {
        if (!owner)
            return;
        owner->queueHeaderMutation([owner, track] {
            if (owner)
                owner->editTrackVoice(track);
        });
    });
    connect(duplicate, &QAction::triggered, this, [owner, track] {
        if (!owner)
            return;
        owner->queueHeaderMutation([owner, track] {
            if (owner)
                owner->duplicateTrack(track);
        });
    });
    connect(remove, &QAction::triggered, this, [owner, track] {
        if (!owner)
            return;
        owner->queueHeaderMutation([owner, track] {
            if (owner)
                owner->deleteTrack(track);
        });
    });
    menu.exec(globalPosition.toPoint());
    if (renameRequested)
        beginRename(track);
}

void TrackHeaderModel::syncRecordGeometry()
{
    if (!m_inputHost)
        return;
    for (std::size_t row = 0; row < m_rows.size(); ++row) {
        if (m_rows[row].isAddTrack)
            continue;
        TrackHeaderRecord before = m_rows[row];
        resolveRecordLabels(m_rows[row]);
        notifyRecordChange(static_cast<int>(row), before, m_rows[row]);
    }
}

void TrackHeaderModel::notifyRecordChange(int row, const TrackHeaderRecord &before,
                                          const TrackHeaderRecord &after)
{
    const auto voiceHovered = [this, row](const TrackHeaderRecord &record) {
        return !record.isAddTrack && m_pointer.hoverRow == row &&
               m_pointer.hoverTarget == HitTarget::Voice;
    };
    const auto voicePressed = [this, row, &voiceHovered](const TrackHeaderRecord &record) {
        return voiceHovered(record) && m_pointer.pressedRow == row &&
               m_pointer.pressedTarget == HitTarget::Voice;
    };
    QList<int> roles;
    if (before.isAddTrack != after.isAddTrack)
        roles.append(IsAddTrackRole);
    if (before.track != after.track)
        roles.append(TrackRole);
    if (before.title != after.title)
        roles.append(TitleRole);
    if (before.subtitle != after.subtitle)
        roles.append(SubtitleRole);
    if (before.toolTip != after.toolTip)
        roles.append(ToolTipRole);
    if (before.titleRect != after.titleRect)
        roles.append(TitleRectRole);
    if (before.subtitleRect != after.subtitleRect)
        roles.append(SubtitleRectRole);
    if (before.selectedTitleOffset != after.selectedTitleOffset)
        roles.append(SelectedTitleOffsetRole);
    if (before.baseColor != after.baseColor)
        roles.append(BaseColorRole);
    if (before.overlayColor != after.overlayColor)
        roles.append(OverlayColorRole);
    if (before.titleColor != after.titleColor)
        roles.append(TitleColorRole);
    if (before.subtitleColor != after.subtitleColor)
        roles.append(SubtitleColorRole);
    if (before.titleFont != after.titleFont)
        roles.append(TitleFontRole);
    if (before.subtitleFont != after.subtitleFont)
        roles.append(SubtitleFontRole);
    if (before.muted != after.muted)
        roles.append(MuteCheckedRole);
    if (before.soloed != after.soloed)
        roles.append(SoloCheckedRole);
    if (voiceHovered(before) != voiceHovered(after))
        roles.append(VoiceHoveredRole);
    if (voicePressed(before) != voicePressed(after))
        roles.append(VoicePressedRole);
    if (before.activityDimColor != after.activityDimColor)
        roles.append(ActivityDimColorRole);
    if (before.activityActiveColor != after.activityActiveColor)
        roles.append(ActivityActiveColorRole);
    if (before.activityLeftHeight != after.activityLeftHeight)
        roles.append(ActivityLeftHeightRole);
    if (before.activityRightHeight != after.activityRightHeight)
        roles.append(ActivityRightHeightRole);
    if (!roles.isEmpty())
        emit dataChanged(index(row, 0), index(row, 0), roles);
}

void TrackHeaderModel::updateAccessibilityDescription()
{
    if (m_inputHost)
        m_inputHost->setAccessibilityDescription(SongView::tr("Track headers"));
}

} // namespace songview
