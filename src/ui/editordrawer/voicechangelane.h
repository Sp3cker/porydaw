#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <vector>

#include <QFont>
#include <QFontMetrics>
#include <QPointF>
#include <QRect>
#include <QRectF>
#include <QString>

#include "core/songdocument.h"

extern "C" {
#include "voicegroup_loader.h"
}

class AutomationCanvas;
class AutomationPage;
class QMouseEvent;
class QPainter;
class QPoint;
struct AutomationGeometry;

namespace layout {
class TwoLineTextLayout;
}

// Non-node Voice Change strip. It owns held-segment painting, hover, picker,
// and DOC_CC_VOICE commits for one captured engine track.
class VoiceChangeLane final
{
  public:
    explicit VoiceChangeLane(AutomationPage *page) noexcept;

    void rebuild(int engineTrack, int width, int top, const AutomationGeometry &geometry);
    bool cancel();
    void clearHover(AutomationCanvas &area);
    void invalidateFontCache();

    QRect bounds() const noexcept { return m_bounds; }
    int height() const noexcept { return m_bounds.height(); }
    bool contains(const QPoint &position) const noexcept;
    int engineTrack() const noexcept { return m_engineTrack; }

    bool mousePress(AutomationCanvas &area, QMouseEvent *event, const AutomationGeometry &geometry);
    bool mouseDoubleClick(AutomationCanvas &area, QMouseEvent *event,
                          const AutomationGeometry &geometry);
    void mouseMove(AutomationCanvas &area, QMouseEvent *event, const AutomationGeometry &geometry);
    void mouseRelease(AutomationCanvas &area, QMouseEvent *event,
                      const AutomationGeometry &geometry);
    bool dragInProgress() const noexcept { return m_drag.has_value(); }
    void paint(QPainter &painter, AutomationCanvas &area, const AutomationGeometry &geometry,
               const QRect &labelGutter, const QFont &titleFont, const QFont &captionFont,
               const layout::TwoLineTextLayout &textLayout, qreal captionHeight);
    void updateHover(AutomationCanvas &area, const AutomationGeometry &geometry, qreal x, int y);

  private:
    struct DragState {
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
        std::size_t occurrenceRank = 0;
    };

    struct VoicePaintText {
        const LoadedVoiceGroup *group = nullptr;
        int type = -1;
        std::array<char, VG_VOICE_NAME_LEN> sourceName{};
        QString label;
        QString hoverLabel;
    };

    struct VoicePaintEntry {
        uint64_t effectiveTick = 0;
        int program = 0;
    };

    const VoicePaintText &paintTextFor(int program) const;
    int voiceSlotAt(uint64_t tick) const;
    void ensureHoverLabelFontCache(const QFont &font);
    QRect plotRect(const AutomationGeometry &geometry) const;
    bool voiceMarkerAt(const AutomationCanvas &area, qreal x, const AutomationGeometry &geometry,
                       DocLanePoint *out) const;
    bool dragActive() const noexcept;
    void resetDrag();
    std::optional<std::size_t> occurrenceRank(const DocLanePoint &point) const;
    void invalidatePreview(AutomationCanvas &area, const AutomationGeometry &geometry);
    void showPicker(AutomationCanvas &area, const QPoint &globalPosition,
                    const AutomationGeometry &geometry);
    void showContextMenu(AutomationCanvas &area, const QPoint &globalPosition,
                         const AutomationGeometry &geometry);

    AutomationPage *m_page = nullptr;
    int m_engineTrack = -1;
    QRect m_bounds;
    bool m_hoverActive = false;
    qreal m_hoverX = 0;
    uint64_t m_hoverTick = 0;
    QString m_hoverLabel;
    QRectF m_hoverLabelRect;
    QRect m_hoverLabelBounds;
    QFont m_hoverLabelFont;
    QFontMetrics m_hoverLabelMetrics{QFont{}};
    bool m_hoverLabelFontValid = false;
    QRect m_hoverDirtyBounds;
    std::optional<DragState> m_drag;
    std::vector<VoicePaintEntry> m_previewEntries;
    mutable std::array<VoicePaintText, VOICEGROUP_SIZE> m_paintTexts;
    mutable QString m_secondary;
    mutable int m_changeCount = -1;
};
