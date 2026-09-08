#pragma once

// Core-scenario fixture for the selection-keyboard-routing check: the
// canonical standalone RigWorld plus the drawer-surface, focus, selection and
// click-target staging that every core case shares. Fixture methods locate and
// stage; the scenario slots in tst_selectionkeycore own every verdict, so this
// class deliberately holds no assertions. It is core-tier only: the gesture,
// window and local-input tiers keep using primitives.h directly.

#include "checks/selectionkey/primitives.h"
#include "ui/songview/editorselectionmodel.h"

#include <QPoint>
#include <QQuickItem>
#include <QString>

#include <array>
#include <cstdint>
#include <memory>
#include <optional>
#include <utility>
#include <vector>

namespace selectionkey {

// Reserved fixture ticks (plan scenario 1): notes at kFirstNoteTick{+48,+96},
// automation lane points at kFirstPointTick/kInsidePointTick/kSecondPointTick/
// kOutsidePointTick, paste probe at kPasteTick. Scenario slots own disjoint
// tick ranges so an edit to one cannot silently retarget another.
inline constexpr int kTrack = 0;
inline constexpr uint8_t kController = 10;
inline constexpr uint64_t kFirstNoteTick = 960;
inline constexpr uint64_t kFirstPointTick = 48;
inline constexpr uint64_t kInsidePointTick = 72;
inline constexpr uint64_t kSecondPointTick = 96;
inline constexpr uint64_t kOutsidePointTick = 144;
inline constexpr uint64_t kPasteTick = 1200;

// A located click point plus the geometry diagnostics that explain it when a
// delivery assertion fails.
struct ClickTarget {
    std::optional<QPoint> point;
    QString diagnostics;
};

QString describePoint(const QPointF &point);
QString describeRect(const QRectF &rect);
QString describeNoteIds(const std::vector<NoteId> &ids);

// Lane-scoped and track-scoped time selections used as staged inputs.
songview::EditorSelectionModel::TimeSelection coreLaneRange(uint64_t begin, uint64_t end);
songview::EditorSelectionModel::TimeSelection coreTrackRange(uint64_t begin, uint64_t end);

// The drawer page mirroring a timeline band; empty for bands outside the
// drawer (roll, ruler, other events).
std::optional<EditorDrawerPage> drawerPageForBand(songview::TimelineBand band);

class CoreFixture final
{
  public:
    static std::unique_ptr<CoreFixture> create(const QString &projectRoot, const QString &songLabel,
                                               std::optional<EditorDrawerPage> drawerPage,
                                               QString &error);

    CoreFixture(const CoreFixture &) = delete;
    CoreFixture &operator=(const CoreFixture &) = delete;

    SongView &view() noexcept { return rigView(*m_world); }
    SongDocument &document() noexcept { return rigDocument(*m_world); }
    QQuickWindow *window() noexcept { return rigWindow(*m_world); }
    QQuickItem *root() noexcept { return m_world->rig->quickRoot(); }
    songview::TimelineInputItem *input(const char *name) noexcept
    {
        return rigInput(*m_world, name);
    }
    const std::vector<NoteId> &notes() const noexcept { return m_world->notes; }

    // Runtime drawer-surface staging: hide every drawer section, then show
    // only the requested page (or none) at its canonical height.
    void configureDrawerSurface(std::optional<EditorDrawerPage> drawerPage);
    // Programmatic band focus; the conditions of a keyboard case, never its
    // subject. Delivered keys remain real QTest events into the shown window.
    bool focusBand(songview::TimelineBand band);

    std::optional<DocNote> note(std::size_t index) const;
    // All three fixture notes, or empty when one vanished before a command.
    std::optional<std::array<DocNote, 3>> snapshotNotes() const;

    // Real, visible-surface click targets for the incidental-click scenarios.
    ClickTarget emptyAutomationLanePoint() const;
    ClickTarget selectedVelocityStemPoint() const;
    std::optional<QPoint> plainRulerPoint(songview::TimelineInputItem *ruler) const;

    std::optional<QPoint> laneWindowPoint(uint64_t tick, int value,
                                          QString *diagnostics = nullptr) const;
    std::optional<std::vector<QPoint>>
    laneWindowPoints(const std::vector<std::pair<uint64_t, int>> &pointSpecs,
                     QString *diagnostics = nullptr) const;

  private:
    CoreFixture() = default;

    std::unique_ptr<RigWorld> m_world;
};

} // namespace selectionkey
