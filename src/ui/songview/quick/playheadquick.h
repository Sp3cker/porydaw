#pragma once

#include <QColor>
#include <QQuickItem>
#include <QRectF>
#include <QVariantList>

class QSGGeometry;

namespace songview {

// The one Qt Quick playhead for the default Windows/Linux renderer. A single
// QSGGeometryNode paints the quadratic bloom, the 1px core, and the ruler
// triangle as ColoredPoint2D triangles with premultiplied vertex colors —
// the quadratic alpha ramp is baked directly into the vertex colors, so there
// are no gradient materials and no inline GLSL — nothing to compile through
// runtime QSB.
//
// Motion is the QML transform's job: the item's geometry stays anchored at
// x: 0 and a Translate moves it to (coreRootX - glowLeft, y) in parent
// coordinates. Bloom vertices stay in that local frame (core at glowLeft).
// Plot-strip clips live on QSGClipNode scissors, remapped when coreRootX
// changes, so gutters get no pixels and a position-only tick does not
// rewrite the bloom mesh.
class TimelinePlayheadItem : public QQuickItem
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(TimelinePlayheadItem)

    // Quick-root X of the playhead core; bind timelineQuickView.playheadRootX.
    Q_PROPERTY(qreal coreRootX READ coreRootX WRITE setCoreRootX NOTIFY coreRootXChanged FINAL)
    // Peak alpha rides with color: both are appearance, never shape.
    Q_PROPERTY(QColor color READ color WRITE setColor NOTIFY colorChanged FINAL)
    Q_PROPERTY(qreal peakAlpha READ peakAlpha WRITE setPeakAlpha NOTIFY colorChanged FINAL)
    // Shared metrics from ui/playheadoverlay.h, in device-independent pixels.
    Q_PROPERTY(qreal glowLeft READ glowLeft WRITE setGlowLeft NOTIFY shapeChanged FINAL)
    Q_PROPERTY(qreal glowRight READ glowRight WRITE setGlowRight NOTIFY shapeChanged FINAL)
    Q_PROPERTY(qreal lineWidthPx READ lineWidthPx WRITE setLineWidthPx NOTIFY shapeChanged FINAL)
    Q_PROPERTY(bool trianglePointsUp READ trianglePointsUp WRITE setTrianglePointsUp NOTIFY
                   shapeChanged FINAL)
    Q_PROPERTY(int triangleHalfWidthPx READ triangleHalfWidthPx WRITE setTriangleHalfWidthPx NOTIFY
                   shapeChanged FINAL)
    Q_PROPERTY(int triangleHeightPx READ triangleHeightPx WRITE setTriangleHeightPx NOTIFY
                   shapeChanged FINAL)
    // Ruler band in parent coordinates; the triangle sits on its continuous
    // bottom edge (QRectF, no inclusive-QRect pixel correction).
    Q_PROPERTY(QRectF triangleBandRect READ triangleBandRect WRITE setTriangleBandRect NOTIFY
                   bandsChanged FINAL)
    // Visible plot strips in parent coordinates (one per band, origin-clipped).
    Q_PROPERTY(QVariantList plotRects READ plotRects WRITE setPlotRects NOTIFY bandsChanged FINAL)

  public:
    explicit TimelinePlayheadItem(QQuickItem *parent = nullptr);

    qreal coreRootX() const noexcept;
    void setCoreRootX(qreal x) noexcept;

    QColor color() const;
    void setColor(const QColor &color);
    qreal peakAlpha() const noexcept;
    void setPeakAlpha(qreal alpha) noexcept;

    qreal glowLeft() const noexcept;
    void setGlowLeft(qreal extent) noexcept;
    qreal glowRight() const noexcept;
    void setGlowRight(qreal extent) noexcept;
    qreal lineWidthPx() const noexcept;
    void setLineWidthPx(qreal width) noexcept;
    bool trianglePointsUp() const noexcept;
    void setTrianglePointsUp(bool pointsUp) noexcept;
    int triangleHalfWidthPx() const noexcept;
    void setTriangleHalfWidthPx(int halfWidth) noexcept;
    int triangleHeightPx() const noexcept;
    void setTriangleHeightPx(int height) noexcept;

    QRectF triangleBandRect() const;
    void setTriangleBandRect(const QRectF &rect);
    QVariantList plotRects() const;
    void setPlotRects(const QVariantList &rects);

  signals:
    void coreRootXChanged();
    // Appearance: theme color and the playing-dependent bloom peak.
    void colorChanged();
    // Static-per-theme metrics plus the triangle orientation.
    void shapeChanged();
    // Parent-coordinate masks from the published band layout.
    void bandsChanged();

  protected:
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *data) override;

  private:
    void markClipDirty();
    void markGeometryDirty();
    void syncLocalClips();
    int playheadVertexCount() const;
    void writePlayheadGeometry(QSGGeometry *geometry) const;

    qreal m_coreRootX = 0.0;
    QColor m_color = Qt::transparent;
    qreal m_glowLeft = 0.0;
    qreal m_glowRight = 0.0;
    qreal m_peakAlpha = 0.0;
    qreal m_lineWidthPx = 0.0;
    bool m_trianglePointsUp = false;
    int m_triangleHalfWidthPx = 0;
    int m_triangleHeightPx = 0;
    QRectF m_triangleBandRect;
    // Property value pre-converted to QRectF so neither paint traversal pays
    // for QVariant unwrapping.
    QList<QRectF> m_plotRects;
    // Plot strips in item-local space, including the current Translate.
    QList<QRectF> m_localClips;
    bool m_clipDirty = true;
    bool m_geometryDirty = true;
};

} // namespace songview
