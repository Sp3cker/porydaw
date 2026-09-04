#include "playheadoverlay.h"
#include "layout.h"
#include "songview.h"
#include "theme/themeruntime.h"
#ifndef __APPLE__
#include "ui/songview/quick/timelinequickview.h"
#endif

#include <QtGlobal>
#include <algorithm>

namespace songview {

int playheadGlowRadius()
{
    return layout::fontPx(0.625);
}

int playheadTriangleHalfWidth()
{
    return layout::fontPx(0.25);
}

int playheadTriangleHeight()
{
    return layout::fontPx(0.5);
}

qreal playheadLineWidth()
{
    return layout::singlePixel();
}

namespace {

constexpr qreal kPlayheadPeakPlaying = 0.13;
constexpr qreal kPlayheadPeakPaused = 0.06;

} // namespace

qreal playheadGlowLeftExtent(bool playing)
{
    return playing ? qreal(playheadGlowRadius()) - playheadLineWidth()
                   : qreal(playheadGlowRadius());
}

qreal playheadGlowRightExtent(bool playing)
{
    return playing ? (playheadLineWidth() / 2.0) : qreal(playheadGlowRadius());
}

qreal playheadPeakAlpha(bool playing)
{
    return playing ? kPlayheadPeakPlaying : kPlayheadPeakPaused;
}

PlayheadOverlay::PlayheadOverlay(SongView &owner, const TimelineBandLayout &layout)
    : QObject(&owner)
    , m_owner(owner)
    , m_layout(layout)
    , m_color(themes::color(themes::Role::song_view_playhead))
{
    synchronizeGeometry();
}

PlayheadOverlay::~PlayheadOverlay() = default;

void PlayheadOverlay::setPlayhead(qreal timelineX, bool visible, bool playing)
{
    if (m_timelineX == timelineX && m_visible == visible && m_playing == playing)
        return;

    m_timelineX = timelineX;
    m_visible = visible;
    m_playing = playing;

    updatePlayhead();
}

void PlayheadOverlay::updateBands(const TimelineBandLayout &layout)
{
    m_layout = layout;
    synchronizeGeometry();
}

void PlayheadOverlay::syncAppearance()
{
    const QColor newColor = themes::color(themes::Role::song_view_playhead);
    if (m_color == newColor)
        return;
    m_color = newColor;
#ifdef __APPLE__
    if (m_platform)
        setPlatformImages();
#endif
    updatePlayhead();
}

void PlayheadOverlay::synchronizeGeometry()
{
#ifdef __APPLE__
    SongView &owner = m_owner;

    const std::optional<TimelineBandGeometry> &rulerBand = m_layout.geometry(TimelineBand::Ruler);
    if (!rulerBand) {
        // Without a ruler row nothing can be clipped to a timeline column.
        m_visibleSurfaceRegion = {};
        m_bodyGeometry = {};
        m_triangleClip = {};
    } else {
        const QRect &rulerRect = rulerBand->rect;
        const int bodyTop = rulerRect.top();
        m_bodyGeometry = QRect(0, bodyTop, owner.width(), std::max(0, owner.height() - bodyTop));

        // Canonical entries are SongView-local and omit hidden bands; each clip
        // rect starts at its band's timeline origin. Producer contract
        // (timelinebandlayout.h): band rects are already clipped to what their
        // layout owner shows, and this overlay's owner is SongView, so one
        // intersected(owner.rect()) bounds the surface — no ancestor walk.
        const auto visibleBandRect = [&owner](const TimelineBandGeometry &band) {
            if (band.timelineOrigin >= band.rect.width())
                return QRect();
            const QRect visible(band.rect.x() + band.timelineOrigin, band.rect.y(),
                                band.rect.width() - band.timelineOrigin, band.rect.height());
            return visible.intersected(owner.rect());
        };

        const QRect rulerVisible = visibleBandRect(*rulerBand);
        const int triangleTop =
            rulerRect.bottom() - playheadTriangleHeight() + layout::singlePixel();
        m_triangleClip = rulerVisible.intersected(QRect(
            rulerVisible.left(), triangleTop, rulerVisible.width(), playheadTriangleHeight()));

        m_visibleSurfaceRegion = rulerVisible;
        for (std::size_t index = 0; index < m_layout.bands.size(); ++index) {
            if (index == timelineBandIndex(TimelineBand::Ruler))
                continue;
            const std::optional<TimelineBandGeometry> &band = m_layout.bands[index];
            if (band)
                m_visibleSurfaceRegion += visibleBandRect(*band);
        }
        m_timelineOrigin = rulerRect.x() + rulerBand->timelineOrigin;
    }
#else
    if (const std::optional<TimelineBandGeometry> &rulerBand =
            m_layout.geometry(TimelineBand::Ruler))
        m_timelineOrigin = rulerBand->rect.x() + rulerBand->timelineOrigin;
#endif
    m_trianglePointsUp = !m_layout.geometry(TimelineBand::Roll).has_value();

#ifdef __APPLE__
    m_devicePixelRatio = owner.devicePixelRatioF();
    if (!m_platform && owner.isVisible())
        initializePlatform(owner);
    if (m_platform) {
        setPlatformImages();
        setPlatformLayout();
    }
#endif
    updatePlayhead();
}

void PlayheadOverlay::updatePlayhead()
{
#ifdef __APPLE__
    if (m_platform)
        setPlatformPosition();
#else
    if (auto *quickView = m_owner.quickView()) {
        quickView->setPlayhead(finalX(), m_visible, m_playing, m_trianglePointsUp);
        quickView->setPlayheadColor(m_color);
    }
#endif
}

} // namespace songview
