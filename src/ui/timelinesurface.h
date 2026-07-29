#pragma once

#include <QPixmap>
#include <QRegion>
#include <QWidget>
#include <QtGlobal>

class QEvent;
class QPaintEvent;
class QResizeEvent;
class QPainter;

namespace songview {

struct TimelineSurfaceDiagnostics
{
    quint64 contentPaintCount = 0;
    quint64 contentPaintPixelCount = 0;
    quint64 estimatedContentCacheBytes = 0;

    friend bool operator==(const TimelineSurfaceDiagnostics &lhs,
                           const TimelineSurfaceDiagnostics &rhs) noexcept
    {
        return lhs.contentPaintCount == rhs.contentPaintCount
               && lhs.contentPaintPixelCount == rhs.contentPaintPixelCount
               && lhs.estimatedContentCacheBytes == rhs.estimatedContentCacheBytes;
    }

    friend bool operator!=(const TimelineSurfaceDiagnostics &lhs,
                           const TimelineSurfaceDiagnostics &rhs) noexcept
    {
        return !(lhs == rhs);
    }
};

class TimelineSurface : public QWidget
{
public:
    explicit TimelineSurface(QWidget *parent = nullptr);

    void invalidateContent();
    void invalidateContent(const QRegion &region);
    TimelineSurfaceDiagnostics diagnostics() const noexcept;

protected:
    virtual void paintContent(QPainter &painter) = 0;

private:
    void paintEvent(QPaintEvent *event) final;
    void changeEvent(QEvent *event) final;
    void resizeEvent(QResizeEvent *event) final;
    void countContentPaint(quint64 pixelCount) noexcept;

    QPixmap m_contentCache;
    QRegion m_dirtyContentRegion;
    TimelineSurfaceDiagnostics m_diagnostics;
};

struct TimelineBand
{
    QWidget &widget;
    int timelineOrigin;
};

struct CachedTimelineBand
{
    TimelineSurface &widget;
    int timelineOrigin;
};

struct TimelineSurfaces
{
    TimelineBand ruler;
    CachedTimelineBand roll;
    CachedTimelineBand lanes;
    CachedTimelineBand strip;
};

} // namespace songview
