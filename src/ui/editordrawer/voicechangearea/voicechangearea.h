#pragma once

#include <array>
#include <cstdint>
#include <optional>
#include <vector>

#include <QFont>
#include <QFontMetrics>
#include <QObject>
#include <QPoint>
#include <QPointF>
#include <QPointer>
#include <QRect>
#include <QRectF>
#include <QString>

#include "core/songdocument.h"
#include "ui/editordrawer/drawerpage.h"
#include "ui/layout.h"
#include "ui/songview/quick/timelineinput.h"

extern "C" {
#include "voicegroup_loader.h"
}

class SongView;

namespace songview {
class Grid;
class QuickMenuHost;
class QuickMenuModel;
class QuickPopupSession;
class TimeCamera;
class TimelineQuickScene;
class TimelineQuickView;
} // namespace songview

// The Voice Changes drawer page: a SongView-owned interaction module owning
// held program spans, change markers, hover, the voice picker, and
// DOC_CC_VOICE commits for the current primary track. SongView owns the
// shared camera and document; this module captures the primary track and
// live camera state on every refresh, so it never holds a persistent track
// identity. Plot input arrives plot-local; gutter input is used only for
// physical fixed-side behavior. The attached input host is always the plot
// host, which supplies plot bounds, fonts, DPR, focus, cursor, and coordinate
// mapping; native picker and menu popups anchor to SongView.
class VoiceChangeArea final : public QObject, public songview::TimelineBandInteraction
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(VoiceChangeArea)

  public:
    explicit VoiceChangeArea(SongView &owner, QObject *parent = nullptr);

    // Typed rows of the voice context menu. Production dispatch and the
    // checks that click rendered rows both read these.
    enum class VoiceMenuAction : int {
        ChangeVoice = 1,
        InsertVoiceChange = 2,
        DeleteMarker = 3,
    };

    // Binds the tab's shared Quick popup session; the typed voice menu in
    // voicechangemenu.cpp opens on it like every other band's menu.
    void setPopupSession(songview::QuickPopupSession *session);
    void songChanged();
    void refreshLiveState(const DrawerPageLiveState &liveState);
    void cancelInteraction() override;
    void documentChanged();
    void tracksRemapped(const TrackRemap &remap);
    void presentPlayhead(double tick);

    void attachInputHost(songview::TimelineInputHost &host) override;
    void detachInputHost(songview::TimelineInputHost &host) override;
    bool pointerPress(const songview::TimelinePointerInput &input) override;
    bool pointerDoubleClick(const songview::TimelinePointerInput &input) override;
    bool pointerMove(const songview::TimelinePointerInput &input) override;
    bool pointerRelease(const songview::TimelinePointerInput &input) override;
    void pointerLeave() override;
    bool wheel(const songview::TimelineWheelInput &input) override;
    bool keyPress(const songview::TimelineKeyInput &input) override;
    bool gestureActive() const override;
    void inputCancelled(songview::TimelineInputCancelReason reason) override;
    void hostAppearanceChanged() override;

  private:
    friend class songview::TimelineQuickView;

    enum class Interaction { None, Pan };
    struct VoiceDragState {
        enum class Phase : uint8_t {
            Pending,
            Active,
        };

        Phase phase = Phase::Pending;
        QPointF pressPosition;
        int engineTrack = -1;
        DocLanePoint point;
        uint64_t revision = 0;
        Tick previewTick = 0;
    };
    struct VoicePaintEntry {
        Tick tick = 0;
        int program = 0;
    };
    struct Geometry {
        int markerHitRadius = 0;
        int hoverPaintPadding = 0;
        int gridMinimumCellWidth = 0;
        void resolve();
    };
    // Resolved label text for one program slot. Cached until the voicegroup
    // pointer, the slot's type, or its source name changes; songChanged drops
    // the whole table because loader pointers do not survive a song swap.
    struct VoicePaintText {
        const LoadedVoiceGroup *group = nullptr;
        int type = -1;
        std::array<char, VG_VOICE_NAME_LEN> sourceName{};
        QString label;
        QString hoverLabel;
    };
    struct VoiceLabelLayout {
        const QString *text = nullptr;
        QString elidedText;
        QRectF rect;
        bool offscreen = true;
    };
    void requestQuickUpdate();
    void rebuildQuickScene(songview::TimelineQuickScene &scene, bool horizontalPan);
    void rebuildQuickHover(songview::TimelineQuickScene &scene);
    void rebuildVisualState();
    void clearHover();
    void updateHover(qreal x);
    QRectF bounds() const;
    QRectF gutterRect() const;
    qreal devicePixelRatio() const;
    bool ready() const noexcept;
    int primaryTrack() const noexcept;
    const VoicePaintText &paintTextFor(int program) const;
    int voiceSlotAt(Tick tick) const;
    QRect plotRect() const;
    bool voiceMarkerAt(qreal x, DocLanePoint *out) const;
    bool voiceDragActive() const noexcept;
    void resetVoiceDrag();
    void showPicker(qreal plotX);
    void showContextMenu(qreal plotX, const QPointF &globalPosition);
    // Menu/picker seam, owned by voicechangemenu.cpp: guarded capture of the
    // open-time target, typed menu rows, dispatch, and the shared
    // captured-target picker path behind both the double-click and the menu.
    struct PendingVoiceMenu {
        QPointer<SongDocument> document;
        uint64_t revision = 0;
        int track = -1;
        Tick tick = 0;
        // Present when the press hit an existing marker; carries the full
        // occurrence (tick and value) so a Change pick re-finds exactly it.
        std::optional<DocLanePoint> marker;
        int initialVoice = 0;
    };
    std::optional<PendingVoiceMenu> captureTargetAt(qreal plotX) const;
    void openPickerForTarget(const PendingVoiceMenu &target);
    void ensureMenuAdapters();
    void cancelMenuWithoutFocus();
    void handleMenuAction(int actionId);
    QPointF menuScenePosition(const QPointF &globalPosition) const;
    SongView &m_owner;
    const songview::TimeCamera &m_camera;
    const songview::Grid &m_grid;
    songview::TimelineInputHost *m_inputHost = nullptr;
    DrawerPageLiveState m_live;
    Geometry m_geometry;
    int m_engineTrack = -1;
    std::vector<DocLanePoint> m_voicePoints;
    std::vector<VoiceLabelLayout> m_labelLayouts;
    const SongDocument *m_voicePointsDocument = nullptr;
    uint64_t m_voicePointsRevision = 0;
    int m_voicePointsTrack = -1;
    Interaction m_interaction = Interaction::None;
    std::optional<VoiceDragState> m_voiceDrag;
    std::vector<VoicePaintEntry> m_previewEntries;
    QPointF m_previousPosition;
    bool m_hoverActive = false;
    qreal m_hoverX = 0.0;
    Tick m_hoverTick = 0;
    QString m_hoverLabel;
    QRectF m_hoverLabelRect;
    QFont m_titleFont;
    QFont m_captionFont;
    QFontMetricsF m_captionMetrics;
    QFont m_hoverLabelFont;
    layout::TwoLineTextLayout m_textLayout;
    mutable std::array<VoicePaintText, VOICEGROUP_SIZE> m_paintTexts;
    mutable QString m_secondary;
    // The shared canvas popup session and this band's typed menu adapter.
    songview::QuickMenuHost *m_menuHost = nullptr;
    songview::QuickMenuModel *m_menuModel = nullptr;
    QPointer<songview::QuickPopupSession> m_menuSession;
    std::optional<PendingVoiceMenu> m_pendingMenu;
    // Irreversible picker invalidation: advanced at every hard cancellation
    // boundary (hidden, window deactivated, detached, session replaced), so
    // a picker handed off from this band is dead once the serial moves and a
    // hide→show or detach→reattach cannot resurrect it. Self-inflicted
    // FocusLost/PointerUngrabbed from the menu or picker opening must not
    // advance it.
    uint64_t m_pickerSerial = 0;
    mutable int m_changeCount = -1;
    std::optional<double> m_lastPresentedPlayheadTick;
};
