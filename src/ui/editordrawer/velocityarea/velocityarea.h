#pragma once

#include <cstdint>
#include <functional>
#include <optional>
#include <vector>

#include <QFont>
#include <QObject>
#include <QPointF>
#include <QRectF>

#include "core/songdocument.h"
#include "core/velocitymodel.h"
#include "ui/editordrawer/drawerpage.h"
#include "ui/editordrawer/velocityaxis.h"
#include "ui/songview/quick/timelineinput.h"

class SongView;

namespace songview {
class TimeCamera;
class TimelineQuickScene;
class TimelineQuickView;
} // namespace songview

struct VelocityAreaDiagnostics {
    // Counts coalesced Quick scene rebuilds, not invalidation requests or
    // asynchronously rendered frames.
    uint64_t contentBuildCount = 0;
    uint64_t playheadPresentationCount = 0;
    double presentedPlayheadTick = 0.0;
};

// The velocity editor owns pointer geometry and gesture presentation while
// SongView owns the deferred document-bound velocity preview.
// Mouse movement never mutates the document; release commits or cancels it.
class VelocityArea final : public QObject, public songview::TimelineBandInteraction
{
  public:
    explicit VelocityArea(SongView &owner, QObject *parent = nullptr);

    void songChanged();
    void refreshLiveState(const DrawerPageLiveState &liveState);
    void cancelInteraction();
    void documentChanged();
    void tracksRemapped(const TrackRemap &remap);
    void setUseDetents(bool on);
    void setContextChangedCallback(std::function<void()> callback);

    VelocityAreaDiagnostics diagnostics() const noexcept;
    const VelocityAxis &axis() const noexcept { return m_axis; }
    int plotOrigin() const;
    int plotWidth() const;
    bool useDetents() const noexcept { return m_useDetents; }
    bool isPsgContext() const { return m_axis.map().isPsg(); }
    void clearTrackHeaderSelection();
    void presentPlayhead(double tick);
    void velocityGestureChanged();

    void attachInputHost(songview::TimelineInputHost &host) override;
    void detachInputHost(songview::TimelineInputHost &host) override;
    bool pointerPress(const songview::TimelinePointerInput &input) override;
    bool pointerMove(const songview::TimelinePointerInput &input) override;
    bool pointerRelease(const songview::TimelinePointerInput &input) override;
    void pointerLeave() override;
    bool wheel(const songview::TimelineWheelInput &input) override;
    bool keyPress(const songview::TimelineKeyInput &input) override;
    void inputCancelled(songview::TimelineInputCancelReason reason) override;
    void hostAppearanceChanged() override;

  private:
    friend class songview::TimelineQuickView;
    enum class Interaction {
        None,
        Relative,
        Paint,
        Ramp,
        PendingBand,
        Band,
        Pan,
    };
    struct Geometry {
        int plotOrigin = 0;
        int densityThresholdD1 = 0;
        int densityThresholdD2 = 0;
        int densityThresholdD3 = 0;
        int densityThresholdD4 = 0;
        int startNodeHitRadius = 0;
        int durationLineVerticalRadius = 0;
        int durationLineHorizontalSlop = 0;
        int relativeDragActivationDistance = 0;
        int defaultPixelsPerBeat = 0;
        qreal nodePaintRadius = 0.0;
        qreal nodeOutlineDipWidth = 0.0;
        qreal selectedNodeRingRadius = 0.0;
        qreal selectedNodeRingDipWidth = 0.0;
        qreal stemDipWidth = 0.0;
        qreal selectedStemDipWidth = 0.0;

        void resolve();
    };

    // Snapshot of one note taken when a gesture begins. Mouse movement must never
    // read the document, so every field the gesture needs is frozen here. `map`
    // in particular is the gesture-time voice resolution: contextForNote can
    // return a different map mid-gesture (hover changes, voicegroup swaps), and
    // the gesture must stay on the axis it started on.
    struct FrozenNote {
        NoteId noteId;
        uint64_t tick = 0;
        uint32_t duration = 0;
        uint8_t key = 0;
        uint8_t velocity = 1;
        VelocityMap map;
        uint8_t exactOrigin = 1;
    };

    void requestQuickUpdate();
    void rebuildQuickScene(songview::TimelineQuickScene &scene);
    void rebuildQuickChrome(songview::TimelineQuickScene &scene, const QRectF &full, int origin,
                            int separatorX);
    void rebuildQuickAxis(songview::TimelineQuickScene &scene, const QRectF &full, int separatorX);
    void rebuildQuickGrid(songview::TimelineQuickScene &scene, const QRectF &plot, int origin,
                          qreal dpr);
    void rebuildQuickPsgBands(songview::TimelineQuickScene &scene, const QRectF &plot);
    void rebuildQuickNotes(songview::TimelineQuickScene &scene, const QRectF &plot, qreal dpr);
    void rebuildQuickTransient(songview::TimelineQuickScene &scene, const QRectF &plot);
    void rebuildVisualState();
    void rebuildAxis();
    void publishAccessibleDescription();
    bool detentsUnlocked(Qt::KeyboardModifiers modifiers, bool allowShift) const;
    bool detentsDisabled() const;
    VelocityMap currentContext() const;
    VelocityMap contextForNote(const DocNote &note) const;
    std::vector<DocNote> selectedNotes() const;
    std::vector<DocNote> primaryTrackNotes() const;
    std::optional<DocNote> notesAt(const QPointF &position, bool includeStems) const;
    void setHoveredNote(std::optional<NoteId> noteId);
    void updateHoveredNote(const QPointF &position);
    QRectF nodeRect(const DocNote &note) const;
    QRectF stemRect(const DocNote &note) const;
    double xForTick(uint64_t tick) const;
    double yForVelocity(uint8_t velocity) const;
    double yForNote(const DocNote &note, uint8_t velocity) const;
    double levelBoundaryY(const VelocityMap &map, int lowerLevel) const;
    double levelCenterY(const VelocityMap &map, int level) const;
    uint8_t displayedVelocity(const DocNote &note) const;
    double pxPerBeat() const;
    bool inRuler(const QPointF &position) const;
    int rulerVelocityAt(const QPointF &position) const;
    void setSelection(const std::vector<NoteId> &selection);
    void appendFrozenNotes(const std::vector<DocNote> &notes);
    void beginVelocityPaint(const QPointF &position, bool detentUnlock);
    void paintSelectedNodesBetween(const QPointF &first, const QPointF &last);
    void beginFrozenGesture(const std::vector<DocNote> &notes, Interaction interaction,
                            const QPointF &position, bool detentUnlock);
    void updateRelativePreview(const QPointF &position);
    void updateBandPreview(const QPointF &position);
    void updateRampPreview(const QPointF &position);
    void finishGesture(bool commit);
    void announcePreview();
    void pauseFollowScroll(bool paused);
    void clearPreview();
    bool hasDocument() const;

    SongView &m_owner;
    const songview::TimeCamera &m_camera;
    songview::TimelineInputHost *m_inputHost = nullptr;
    DrawerPageLiveState m_live;
    VelocityAxis m_axis{VelocityMap::resolve(nullptr, std::nullopt), {}};
    Geometry m_geometry;
    QFont m_captionFont;
    QFont m_boldCaptionFont;
    int m_captionFontHeight = 0;

    std::function<void()> m_contextChanged;
    bool m_useDetents = true;
    std::vector<FrozenNote> m_frozen;
    std::vector<NoteId> m_bandPreview;
    std::optional<NoteId> m_hoveredNote;
    std::optional<NoteId> m_pressedNote;
    std::vector<NoteId> m_selectionBeforePress;
    bool m_controlPress = false;
    bool m_detentUnlock = false;
    QPointF m_pressPosition;
    QPointF m_previousPosition;
    QRectF m_bandRect;
    Interaction m_interaction = Interaction::None;
    bool m_relativeActivated = false;
    VelocityAreaDiagnostics m_diagnostics;
    std::optional<double> m_lastPresentedPlayheadTick;
    // One-note announcement invariant: regardless of how many notes a gesture
    // touches, only this note is spoken through the drawer status line, so a
    // multi-note drag does not flood announcements. Defaults to the pressed
    // note (or the first frozen note) and sticks for the gesture's lifetime;
    // clearPreview() resets it.
    NoteId m_announcedNote;
};
