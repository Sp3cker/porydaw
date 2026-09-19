#include "font_metrics.h"

#include <QFont>
#include <QFontMetricsF>
#include <QString>

#include <utility>

struct SGFontMetrics {
    QFont font;
    QFontMetricsF metrics;

    explicit SGFontMetrics(QFont value) : font(std::move(value)), metrics(font) {}
};

SGFontMetrics *sgf_create(const char *family, int pixel_size, int weight, double letter_spacing)
{
    QFont font(QString::fromUtf8(family));
    font.setPixelSize(pixel_size);
    font.setWeight(QFont::Weight(weight));
    font.setLetterSpacing(QFont::AbsoluteSpacing, letter_spacing);
    return new SGFontMetrics(std::move(font));
}

void sgf_destroy(SGFontMetrics *metrics)
{
    delete metrics;
}

SGFontExtents sgf_extents(const SGFontMetrics *metrics)
{
    return {metrics->metrics.ascent(), metrics->metrics.height()};
}

double sgf_advance(const SGFontMetrics *metrics, const char *text)
{
    return metrics->metrics.horizontalAdvance(QString::fromUtf8(text));
}

int sgf_fit(const SGFontMetrics *metrics, double row_height)
{
    QFont font = metrics->font;
    for (int px = font.pixelSize(); px > 0; --px) {
        font.setPixelSize(px);
        const QFontMetricsF fitted(font);
        if (fitted.ascent() + fitted.descent() <= row_height)
            return px;
    }
    return 1;
}
