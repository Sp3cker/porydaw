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
class TimeCamera;
class TimelineQuickScene;
class TimelineQuickView;
} // namespace songview

// The Voice Changes drawer page: a SongView-owned interaction module owning
// held program spans, change markers, hover, the voice picker, and
// DOC_CC_VOICE commits for the current primary track. SongView owns the
// shared camera and document; this module captures the primary track and
// live camera state on every refresh, so it never holds a persistent track
// identity. Input arrives normalized from the attached TimelineInputHost,
// which also supplies bounds, fonts, DPR, focus, cursor, and coordinate
// mapping; native picker and menu popups anchor to SongView.
class VoiceChangeArea final : public QObject, public songview::TimelineBandInteraction
{
    Q_OBJECT

  public:
    explicit VoiceChangeArea(SongView &owner, QObject *parent = nullptr);
    void songChanged();
    void refreshLiveState(const DrawerPageLiveState &liveState);
    void cancelInteraction();
    void documentChanged();
    void tracksRemapped(const TrackRemap &remap);
    int plotOrigin() const;
    int plotWidth() const;
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
        uint64_t previewTick = 0;
    };
    struct VoicePaintEntry {
        uint64_t tick = 0;
        int program = 0;
    };
    struct Geometry {
        int plotOrigin = 0;
        int markerHitRadius = 0;
        int hoverPaintPadding = 0;
        int gridMinimumCellWidth = 0;
        void resolve(int timelineSplitX);
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
    void rebuildQuickScene(songview::TimelineQuickScene &scene);
    void rebuildQuickHover(songview::TimelineQuickScene &scene);
    void rebuildVisualState();
    void clearHover();
    void updateHover(qreal x);
    QRectF bounds() const;
    qreal devicePixelRatio() const;
    bool ready() const noexcept;
    int primaryTrack() const noexcept;
    const VoicePaintText &paintTextFor(int program) const;
    int voiceSlotAt(uint64_t tick) const;
    QRect plotRect() const;
    bool voiceMarkerAt(qreal x, DocLanePoint *out) const;
    bool voiceDragActive() const noexcept;
    void resetVoiceDrag();
    void showPicker(const QPoint &globalPosition);
    void showContextMenu(const QPoint &globalPosition);
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
    uint64_t m_hoverTick = 0;
    QString m_hoverLabel;
    QRectF m_hoverLabelRect;
    QFont m_titleFont;
    QFont m_captionFont;
    QFontMetricsF m_captionMetrics;
    QFont m_hoverLabelFont;
    layout::TwoLineTextLayout m_textLayout;
    mutable std::array<VoicePaintText, VOICEGROUP_SIZE> m_paintTexts;
    mutable QString m_secondary;
    mutable int m_changeCount = -1;
    std::optional<double> m_lastPresentedPlayheadTick;
};
