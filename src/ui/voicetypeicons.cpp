#include "ui/voicetypeicons.h"

#include <QPainter>
#include <QPixmap>

namespace voicetypeicons {

QIcon tinted(const QString &svgPath, const QSize &size, qreal dpr, bool altChip, bool rotate180)
{
    const QIcon source(svgPath);
    const auto ink = [&](themes::Role role) {
        QPixmap glyph = source.pixmap(size, dpr);
        if (rotate180) {
            QPixmap flipped(glyph.size());
            flipped.setDevicePixelRatio(dpr);
            flipped.fill(Qt::transparent);
            QPainter flipPainter(&flipped);
            const QSizeF logical = glyph.deviceIndependentSize();
            flipPainter.translate(logical.width(), logical.height());
            flipPainter.rotate(180);
            flipPainter.drawPixmap(0, 0, glyph);
            flipPainter.end();
            glyph = flipped;
        }
        QPainter painter(&glyph);
        painter.setCompositionMode(QPainter::CompositionMode_SourceIn);
        painter.fillRect(QRectF(QPointF(0, 0), glyph.deviceIndependentSize()),
                         themes::color(altChip ? themes::Role::item_background : role));
        painter.end();
        if (!altChip)
            return glyph;
        // The chip: a rounded grey plate under the surface-inked glyph.
        QPixmap chipped(glyph.size());
        chipped.setDevicePixelRatio(dpr);
        chipped.fill(Qt::transparent);
        QPainter chipPainter(&chipped);
        chipPainter.setRenderHint(QPainter::Antialiasing);
        QColor chip = themes::color(themes::Role::secondary_text);
        chip.setAlphaF(0.35f);
        chipPainter.setBrush(chip);
        chipPainter.setPen(Qt::NoPen);
        const QRectF plate(QPointF(0, 0), chipped.deviceIndependentSize());
        chipPainter.drawRoundedRect(plate, plate.height() / 4.0, plate.height() / 4.0);
        chipPainter.drawPixmap(QPointF(0, 0), glyph);
        chipPainter.end();
        return chipped;
    };
    QIcon result(ink(themes::Role::item_text));
    result.addPixmap(ink(themes::Role::item_selected_text), QIcon::Selected, QIcon::Off);
    result.addPixmap(ink(themes::Role::item_selected_text), QIcon::Selected, QIcon::On);
    result.addPixmap(ink(themes::Role::disabled_text), QIcon::Disabled, QIcon::Off);
    result.addPixmap(ink(themes::Role::disabled_text), QIcon::Disabled, QIcon::On);
    return result;
}

} // namespace voicetypeicons
