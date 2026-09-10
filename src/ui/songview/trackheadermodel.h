#pragma once

#include <QAbstractListModel>
#include <QColor>
#include <QFont>
#include <QFontMetrics>
#include <QHash>
#include <QList>
#include <QPointF>
#include <QPointer>
#include <QRect>
#include <QRectF>
#include <QString>
#include <QVariantMap>

#include <cstdint>
#include <optional>
#include <vector>

#include "ui/activity/trackactivity.h"
#include "ui/activity/trackactivityrender.h"
#include "ui/layout.h"
#include "ui/songview/quick/timelineinput.h"

class SongDocument;
class SongView;

namespace songview {

class QuickMenuHost;
class QuickMenuModel;
class QuickPopupSession;
struct QuickMenuItem;

class TrackHeaderModel final : public QAbstractListModel, public TimelineBandInteraction
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(TrackHeaderModel)

    Q_PROPERTY(int rowHeight READ rowHeight NOTIFY geometryChanged FINAL)
    Q_PROPERTY(int activityWidth READ activityWidth NOTIFY geometryChanged FINAL)
    Q_PROPERTY(int scrollbarWidth READ scrollbarWidth CONSTANT FINAL)
    Q_PROPERTY(int scrollbarMinimumThumbHeight READ scrollbarMinimumThumbHeight NOTIFY
                   geometryChanged FINAL)
    Q_PROPERTY(int reorderIndicatorHeight READ reorderIndicatorHeight NOTIFY geometryChanged FINAL)
    Q_PROPERTY(int separatorWidth READ separatorWidth NOTIFY geometryChanged FINAL)
    Q_PROPERTY(QRectF muteButtonRect READ muteButtonRect NOTIFY geometryChanged FINAL)
    Q_PROPERTY(QRectF soloButtonRect READ soloButtonRect NOTIFY geometryChanged FINAL)
    Q_PROPERTY(QRectF voiceLineRect READ voiceLineRect NOTIFY geometryChanged FINAL)
    Q_PROPERTY(QRectF renameEditorRect READ renameEditorRect NOTIFY geometryChanged FINAL)
    Q_PROPERTY(int renamingTrack READ renamingTrack NOTIFY renameChanged FINAL)
    Q_PROPERTY(QString renameDraft READ renameDraft WRITE setRenameDraft NOTIFY renameChanged FINAL)
    Q_PROPERTY(QString renamePlaceholder READ renamePlaceholder NOTIFY renameChanged FINAL)
    Q_PROPERTY(qreal scrollY READ scrollY WRITE setScrollY NOTIFY scrollChanged FINAL)
    Q_PROPERTY(int contentHeight READ contentHeight NOTIFY geometryChanged FINAL)
    Q_PROPERTY(qreal maximumScrollY READ maximumScrollY NOTIFY geometryChanged FINAL)
    Q_PROPERTY(qreal viewportHeight READ viewportHeight NOTIFY geometryChanged FINAL)
    Q_PROPERTY(
        bool reorderIndicatorVisible READ reorderIndicatorVisible NOTIFY reorderChanged FINAL)
    Q_PROPERTY(qreal reorderIndicatorY READ reorderIndicatorY NOTIFY reorderChanged FINAL)
    Q_PROPERTY(QVariantMap appearance READ appearance NOTIFY appearanceChanged FINAL)

  public:
    enum Role : int {
        IsAddTrackRole = Qt::UserRole + 1,
        TrackRole,
        TitleRole,
        SubtitleRole,
        TitleRectRole,
        SubtitleRectRole,
        SelectedTitleOffsetRole,
        BaseColorRole,
        OverlayColorRole,
        TitleColorRole,
        SubtitleColorRole,
        TitleFontRole,
        SubtitleFontRole,
        MuteCheckedRole,
        SoloCheckedRole,
        MuteHoveredRole,
        MutePressedRole,
        SoloHoveredRole,
        SoloPressedRole,
        AddHoveredRole,
        AddPressedRole,
        ActivityDimColorRole,
        ActivityActiveColorRole,
        ActivityLeftHeightRole,
        ActivityRightHeightRole,
    };

    // Typed rows of the header context menu; ids travel through
    // QuickMenuModel::activated(int) and are interpreted only here.
    enum class HeaderMenuAction : int {
        ChangeVoice = 1,
        ShowVoiceInVoicegroup = 2,
        RenameTrack = 3,
        DuplicateTrack = 4,
        DeleteTrack = 5,
    };

    explicit TrackHeaderModel(SongView &owner, QObject *parent = nullptr);
    ~TrackHeaderModel() override;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void rebuild(const TrackActivity &activity, bool playing);
    void syncSelection();
    void syncVoices();
    void syncActivity(const TrackActivity &activity, bool playing);
    void syncMuteMask(uint32_t mask);
    void syncSoloMask(uint32_t mask);
    void syncAppearance();
    void beginRename(int track);
    Q_INVOKABLE void finishRename(bool commit, bool restoreRollFocus);
    void cancelRename();
    Q_INVOKABLE void activateMute(int track);
    Q_INVOKABLE void activateSolo(int track);
    Q_INVOKABLE void activateAddTrack();

    int rowHeight() const noexcept;
    int activityWidth() const noexcept;
    int scrollbarWidth() const noexcept;
    int scrollbarMinimumThumbHeight() const noexcept;
    int reorderIndicatorHeight() const noexcept;
    int separatorWidth() const noexcept;
    QRectF muteButtonRect() const;
    QRectF soloButtonRect() const;
    // Matches the rendered subtitle/current-instrument line exactly.
    QRectF voiceLineRect() const;
    QRectF renameEditorRect() const;
    int contentHeight() const noexcept;
    int renamingTrack() const noexcept;
    QString renameDraft() const;
    void setRenameDraft(const QString &text);
    QString renamePlaceholder() const;
    qreal scrollY() const noexcept;
    qreal maximumScrollY() const noexcept;
    qreal viewportHeight() const noexcept;
    void setScrollY(qreal value);
    bool reorderIndicatorVisible() const noexcept;
    qreal reorderIndicatorY() const noexcept;
    QVariantMap appearance() const;
    void cancelTransientState();
    // Binds the shared canvas popup session once TimelineQuickView exists;
    // the header context menu is a typed QuickMenuHost adapter over it.
    void setPopupSession(QuickPopupSession *session);

    void attachInputHost(TimelineInputHost &host) override;
    void detachInputHost(TimelineInputHost &host) override;
    bool pointerPress(const TimelinePointerInput &input) override;
    bool pointerDoubleClick(const TimelinePointerInput &input) override;
    bool pointerMove(const TimelinePointerInput &input) override;
    bool pointerRelease(const TimelinePointerInput &input) override;
    void pointerLeave() override;
    bool wheel(const TimelineWheelInput &input) override;
    void inputCancelled(TimelineInputCancelReason reason) override;
    void hostAppearanceChanged() override;

  signals:
    void geometryChanged();
    void renameChanged();
    void scrollChanged();
    void reorderChanged();
    void appearanceChanged();

  private:
    enum class HitTarget : quint8 { None, Body, Voice, Mute, Solo, AddTrack };

    struct TrackHeaderRecord {
        bool isAddTrack = false;
        int track = -1;
        QString title;
        QString subtitle;
        QRectF titleRect;
        QRectF subtitleRect;
        QPointF selectedTitleOffset;
        QColor baseColor{Qt::transparent};
        QColor overlayColor{Qt::transparent};
        QColor titleColor{Qt::transparent};
        QColor subtitleColor{Qt::transparent};
        QFont titleFont;
        QFont subtitleFont;
        bool muted = false;
        bool soloed = false;
        QColor activityDimColor{Qt::transparent};
        QColor activityActiveColor{Qt::transparent};
        track_activity_render::State activityState;
        track_activity_render::RenderKey activityRenderKey{-1, -1, false};
        qreal activityLeftHeight = 0.0;
        qreal activityRightHeight = 0.0;
    };

    struct PointerState {
        int hoverRow = -1;
        HitTarget hoverTarget = HitTarget::None;
        int pressedRow = -1;
        int pressedTrack = -1;
        HitTarget pressedTarget = HitTarget::None;
        QPointF pressPosition;
        bool dragArmed = false;
        bool dragging = false;
    };

    // The raw engine track captured when the header menu opened, guarded by
    // document identity plus revision. The index is only stable until the
    // next remap or delete; any such mutation bumps the revision and the
    // rebuild cancels the menu before the target could go stale.
    struct PendingHeaderMenu {
        // Guarded so a queued snapshot can outlive a document swap safely.
        QPointer<SongDocument> document = nullptr;
        uint64_t documentRevision = 0;
        int track = -1;
    };

    struct Geometry {
        int rowHeight;
        int activityWidth;
        int buttonExtent;
        int buttonColumnWidth;
        int textLeft;
        // Voice-line geometry comes from the two-line subtitle layout, not fixed metrics.
        int renameEditorLeft;
        int renameEditorTop;
        int renameEditorRight;
        int renameEditorHeight;
        int reorderIndicatorHeight;
        int separatorWidth;
        int scrollbarWidth;
        int scrollbarMinimumThumbHeight;

        static Geometry resolve();
    };

    int trackRowCount() const noexcept;
    QRect textBounds() const;
    int rowAt(qreal bandY) const;
    int trackAt(qreal bandY) const;
    qreal contentY(qreal bandY) const;
    QRectF rowLocalRect(const QRectF &rect, qreal bandY) const;
    HitTarget hitTarget(int row, const QPointF &bandPosition) const;
    void updatePointerVisuals(int row, HitTarget target, bool pressed);
    void clearPointerVisuals();
    bool scrollVertically(const TimelineWheelInput &input);
    void showContextMenu(int track, const QPointF &scenePosition);
    // Global→scene bridge for the pointer caller: the shared session's Quick
    // window maps the header input host's global press position; null point
    // when no session is bound.
    QPointF headerMenuScenePosition(const QPointF &globalPosition) const;
    void ensureHeaderMenuAdapters();
    void cancelHeaderMenuWithoutFocus();
    void handleHeaderMenuAction(int actionId);
    std::vector<QuickMenuItem> buildHeaderMenuItems(const SongDocument &document) const;
    void beginReorder(int track, const QPointF &position);
    void updateReorder(const QPointF &position);
    void finishReorder(bool commit);
    std::optional<int> reorderTarget(int fromTrack, int dropSlot) const;

    TrackHeaderRecord makeTrackRecord(int track, const TrackActivity &activity, bool playing) const;
    TrackHeaderRecord makeAddTrackRecord() const;
    void resolveRecordPresentation(TrackHeaderRecord &record) const;
    void resolveRecordColors(TrackHeaderRecord &record) const;
    void resolveRecordLabels(TrackHeaderRecord &record) const;
    void syncCheckedMask(uint32_t mask, bool TrackHeaderRecord::*member, int role);
    void refreshActivityHeights(const TrackActivity *activity, bool playing);
    void syncStoredActivityHeights();
    void syncRecordGeometry();
    void clampScroll();
    void notifyRecordChange(int row, const TrackHeaderRecord &before,
                            const TrackHeaderRecord &after);
    void notifyPointerChanges(const PointerState &before);
    void updateAccessibilityDescription();

    SongView &m_owner;
    TimelineInputHost *m_inputHost = nullptr;
    std::vector<TrackHeaderRecord> m_rows;
    Geometry m_geometry;
    PointerState m_pointer;
    QFont m_normalTitleFont;
    QFont m_boldTitleFont;
    QFont m_subtitleFont;
    QFontMetrics m_normalTitleMetrics{QFont{}};
    QFontMetrics m_boldTitleMetrics{QFont{}};
    QFontMetrics m_subtitleMetrics{QFont{}};
    std::optional<layout::TwoLineTextLayout> m_textLayout;
    QString m_renameDraft;
    QString m_renamePlaceholder;
    int m_renamingTrack = -1;
    bool m_finishingRename = false;
    qreal m_scrollY = 0.0;
    bool m_reorderIndicatorVisible = false;
    qreal m_reorderIndicatorY = 0.0;
    QVariantMap m_appearance;
    // Persistent typed header-menu adapters; created in the constructor and
    // bound to the shared canvas popup session by TimelineQuickView.
    QuickMenuHost *m_headerMenuHost = nullptr;
    QuickMenuModel *m_headerMenuModel = nullptr;
    QPointer<QuickPopupSession> m_headerMenuSession;
    std::optional<PendingHeaderMenu> m_pendingHeaderMenu;
};

} // namespace songview
