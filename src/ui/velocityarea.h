#pragma once

#include <cstdint>
#include <optional>
#include <vector>

#include <QPointF>
#include <QRect>
#include <QRectF>
#include <QWidget>

#include "core/songdocument.h"
#include "core/velocitymodel.h"
#include "ui/editorpage.h"
#include "ui/timelinesurface.h"
#include "ui/velocityaxis.h"

class SongView;
class QContextMenuEvent;
class QEvent;
class QFocusEvent;
class QKeyEvent;
class QMouseEvent;
class QWheelEvent;

class QPainter;

struct VelocityAreaDiagnostics {
    uint64_t contentBuildCount = 0;
    uint64_t playheadPresentationCount = 0;
    double presentedPlayheadTick = 0.0;
};

// The velocity editor keeps a revision-bound gesture snapshot while the
// owning SongView supplies document, selection, voice, and edit operations.
// Live refreshes do not change an active preview; a document revision change
// cancels the gesture before the owner applies the new state.
class VelocityArea final : public songview::TimelineSurface
{
  public:
    explicit VelocityArea(SongView &owner, QWidget *parent = nullptr);

    void songChanged();
    void refreshLiveState(const EditorPageLiveState &liveState);
    void cancelInteraction();
    void documentChanged();
    void tracksRemapped(const TrackRemap &remap);

    const VelocityAreaDiagnostics &diagnostics() const noexcept { return m_diagnostics; }
    const VelocityAxis &axis() const noexcept { return m_axis; }
    int plotOrigin() const;
    int plotWidth() const;
    void clearTrackHeaderSelection();
    void presentPlayhead(double tick);
    void presentPianoRollVelocityPreview(std::optional<int> delta);

  protected:
    bool event(QEvent *event) override;
    void paintContent(QPainter &painter) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;
    void keyPressEvent(QKeyEvent *event) override;
    void focusOutEvent(QFocusEvent *event) override;
    void contextMenuEvent(QContextMenuEvent *event) override;
    void contentGeometryChanged() override;

  private:
    enum class Interaction {
        None,
        Relative,
        Paint,
        PendingBand,
        Band,
        Pan,
    };

    struct FrozenNote {
        NoteId noteId;
        uint64_t tick = 0;
        uint32_t duration = 0;
        uint8_t key = 0;
        uint8_t velocity = 1;
        VelocityMap map;
        uint8_t exactOrigin = 1;
    };

    void invalidateContent(const QRect &rect = {});
    void rebuildVisualState();
    void rebuildAxis();
    void publishAccessibleDescription();
    VelocityMap currentContext() const;
    VelocityMap contextForNote(const DocNote &note) const;
    std::vector<DocNote> selectedNotes() const;
    std::vector<DocNote> primaryTrackNotes() const;
    std::vector<DocNote> notesAt(const QPointF &position, bool includeStems) const;
    QRectF nodeRect(const DocNote &note) const;
    QRectF stemRect(const DocNote &note) const;
    double xForTick(uint64_t tick) const;
    double yForVelocity(uint8_t velocity) const;
    double yForNote(const DocNote &note, uint8_t velocity) const;
    uint8_t displayedVelocity(const DocNote &note) const;
    double pxPerBeat() const;
    bool inRuler(const QPointF &position) const;
    int rulerVelocityAt(const QPointF &position) const;
    void setSelection(const std::vector<NoteId> &selection);
    std::vector<NoteId> toggledSelection(const std::vector<DocNote> &notes) const;
    void appendFrozenNotes(const std::vector<DocNote> &notes);
    void beginVelocityPaint(const QPointF &position);
    void paintSelectedNodesBetween(const QPointF &first, const QPointF &last);
    void beginFrozenGesture(const std::vector<DocNote> &notes, Interaction interaction,
                            const QPointF &position);
    void updateRelativePreview(const QPointF &position);
    void updateBandPreview(const QPointF &position);
    void finishGesture(bool commit);
    bool applyPreview();
    void restorePreview();
    void announcePreview();
    void pauseFollowScroll(bool paused);
    void clearPreview();
    bool hasDocument() const;

    SongView &m_owner;
    EditorPageLiveState m_live;
    VelocityAxis m_axis{VelocityMap::resolve(nullptr, std::nullopt), {}};
    VelocityAreaDiagnostics m_diagnostics;
    std::vector<FrozenNote> m_frozen;
    std::vector<uint8_t> m_previewVelocities;
    std::optional<int> m_pianoRollVelocityDelta;
    std::vector<NoteId> m_bandPreview;
    std::vector<NoteId> m_pressedHits;
    std::vector<NoteId> m_selectionBeforePress;
    bool m_controlPress = false;
    QPointF m_pressPosition;
    QPointF m_previousPosition;
    QRectF m_bandRect;
    bool m_committingPreview = false;
    uint64_t m_previewRevision = 0;
    uint64_t m_velocityGesture = 0;
    Interaction m_interaction = Interaction::None;
    bool m_relativeActivated = false;
    bool m_followScrollPaused = false;
    bool m_suppressContextMenu = false;
    NoteId m_announcedNote;
};
