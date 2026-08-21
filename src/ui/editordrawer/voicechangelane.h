#pragma once

#include <array>
#include <cstdint>

#include <QFont>
#include <QRect>
#include <QRectF>
#include <QString>

extern "C" {
#include "voicegroup_loader.h"
}

class AutomationCanvas;
class AutomationPage;
class QMouseEvent;
class QPainter;
class QPoint;
struct AutomationGeometry;
struct DocLanePoint;

// Non-node Voice Change strip. It owns held-segment painting, hover, picker,
// and DOC_CC_VOICE commits for one captured engine track.
class VoiceChangeLane final
{
  public:
    explicit VoiceChangeLane(AutomationPage *page) noexcept;

    void rebuild(int engineTrack, int width, int top, int height);
    void cancel();
    void clearHover(AutomationCanvas &area);

    QRect bounds() const noexcept { return m_bounds; }
    int height() const noexcept { return m_bounds.height(); }
    bool contains(const QPoint &position) const noexcept;
    int engineTrack() const noexcept { return m_engineTrack; }

    bool mousePress(AutomationCanvas &area, QMouseEvent *event, const AutomationGeometry &geometry);
    bool mouseDoubleClick(AutomationCanvas &area, QMouseEvent *event,
                          const AutomationGeometry &geometry);
    void paint(QPainter &painter, AutomationCanvas &area, const AutomationGeometry &geometry,
               const QRect &labelGutter, const QFont &titleFont, const QFont &captionFont);
    void updateHover(AutomationCanvas &area, const AutomationGeometry &geometry, qreal x, int y);

  private:
    struct VoicePaintText {
        const LoadedVoiceGroup *group = nullptr;
        int type = -1;
        std::array<char, VG_VOICE_NAME_LEN> sourceName{};
        QString label;
        QString hoverLabel;
    };

    const VoicePaintText &paintTextFor(int program) const;
    int voiceSlotAt(uint64_t tick) const;
    QRect plotRect(const AutomationGeometry &geometry) const;
    bool voiceMarkerAt(const AutomationCanvas &area, qreal x, const AutomationGeometry &geometry,
                       DocLanePoint *out) const;
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
    QRect m_hoverDirtyBounds;
    mutable std::array<VoicePaintText, VOICEGROUP_SIZE> m_paintTexts;
    mutable QString m_secondary;
    mutable int m_changeCount = -1;
};
