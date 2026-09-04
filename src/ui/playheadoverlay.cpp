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

QRect PlayheadOverlay::timelineColumnRect() const
{
    const int timelineSplitX = m_owner.timelineSplitX();
    return QRect(timelineSplitX, 0, std::max(0, m_owner.width() - timelineSplitX),
                 m_owner.height());
}

void PlayheadOverlay::synchronizeGeometry()
{
#ifdef __APPLE__
    SongView &owner = m_owner;
    const QRect timelineColumn = timelineColumnRect();
    const QRect localTimelineColumn(0, 0, timelineColumn.width(), timelineColumn.height());
    const std::optional<TimelineBandGeometry> &rulerBand = m_layout.geometry(TimelineBand::Ruler);
    if (!rulerBand || rulerBand->plotRect.isEmpty()) {
        // Without a ruler plot nothing can be clipped to a timeline column.
        m_visibleSurfaceRegion = {};
        m_bodyGeometry = {};
        m_triangleClip = {};
    } else {
        const auto visibleBandRect = [&timelineColumn,
                                      &localTimelineColumn](const TimelineBandGeometry &band) {
            return band.plotRect.translated(-timelineColumn.x(), 0)
                .intersected(localTimelineColumn);
        };

        const QRect rulerVisible = visibleBandRect(*rulerBand);
        const int bodyTop = rulerVisible.top();
        m_bodyGeometry =
            QRect(0, bodyTop, timelineColumn.width(), std::max(0, owner.height() - bodyTop));

        m_visibleSurfaceRegion = {};
        for (const std::optional<TimelineBandGeometry> &band : m_layout.bands) {
            if (!band)
                continue;
            const QRect visible = visibleBandRect(*band);
            if (!visible.isEmpty())
                m_visibleSurfaceRegion += visible;
        }

        if (rulerVisible.isEmpty()) {
            m_triangleClip = {};
        } else {
            const int triangleHeight = playheadTriangleHeight();
            const int triangleHalfWidth = playheadTriangleHalfWidth();
            const int triangleTop = rulerVisible.bottom() - triangleHeight + layout::singlePixel();
            const QRect triangleBounds(rulerVisible.left() - triangleHalfWidth, rulerVisible.top(),
                                       rulerVisible.width() + triangleHalfWidth,
                                       rulerVisible.height());
            m_triangleClip = triangleBounds.intersected(
                QRect(triangleBounds.x(), triangleTop, triangleBounds.width(), triangleHeight));
        }
    }
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

bool PlayheadOverlay::effectiveVisible() const
{
    const std::optional<TimelineBandGeometry> &rulerBand = m_layout.geometry(TimelineBand::Ruler);
    return m_visible && rulerBand && !rulerBand->plotRect.isEmpty() && m_timelineX >= 0.0 &&
           m_timelineX < timelineColumnRect().width();
}

void PlayheadOverlay::updatePlayhead()
{
#ifdef __APPLE__
    if (m_platform)
        setPlatformPosition();
#else
    if (auto *quickView = m_owner.quickView()) {
        quickView->setPlayhead(m_timelineX, effectiveVisible(), m_playing, m_trianglePointsUp);
        quickView->setPlayheadColor(m_color);
    }
#endif
}

} // namespace songview
