#include "ui/selectionreticle.h"

#include <QBrush>
#include <QColor>
#include <QPainter>
#include <QPen>
#include <QRectF>

#include "ui/layout.h"
#include "ui/theme/themeruntime.h"

namespace songview {

void paintSelectionReticle(QPainter &painter, const QRectF &rect)
{
    const QColor edge = themes::color(themes::Role::song_view_selection_edge);
    QColor fill = themes::color(themes::Role::song_view_selection_fill);
    fill.setAlpha(30);
    painter.save();
    painter.setPen(QPen(edge, layout::singlePixel(), Qt::DashLine));
    painter.setBrush(Qt::NoBrush);
    painter.fillRect(rect, QBrush(fill));
    painter.drawRect(rect);
    painter.restore();
}

} // namespace songview
