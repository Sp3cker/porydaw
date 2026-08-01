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
    QColor color = themes::color(themes::Role::song_view_selection_edge);
    painter.save();
    painter.setPen(QPen(color, layout::singlePixel(), Qt::DashLine));
    painter.setBrush(Qt::NoBrush);
    color.setAlpha(30);
    painter.fillRect(rect, QBrush(color));
    painter.drawRect(rect);
    painter.restore();
}

} // namespace songview
