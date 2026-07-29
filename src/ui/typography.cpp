#include "typography.h"

#include <QApplication>
#include <QFontDatabase>
#include <QFontInfo>
#include <QFontMetrics>
#include <QFontMetricsF>

namespace typography {
namespace {

constexpr auto proportionalFamily = "Atkinson Hyperlegible Next";
constexpr auto monoFamily = "Atkinson Hyperlegible Mono";

std::optional<int> capturedBaseFontPx;
std::optional<QFont> installedBodyFont;

void setFace(QFont &font, QFont::Weight weight)
{
    font.setFamily(QString::fromLatin1(proportionalFamily));
    font.setStyleName({});
    font.setWeight(weight);
    font.setStyle(QFont::StyleNormal);
    font.setHintingPreference(QFont::PreferFullHinting);
}

int resolvedPixelSize(const QFont &font)
{
    return qMax(1, QFontInfo(font).pixelSize());
}

int occupiedHeight(const QFont &font)
{
    const auto metrics = QFontMetrics(font);
    return metrics.ascent() + metrics.descent();
}

} // namespace

bool installBundledFonts(QApplication &application)
{
    const auto baseFontPx = QFontInfo(application.font()).pixelSize();
    if (baseFontPx <= 0)
        return false;
    const auto regular = QFontDatabase::addApplicationFont(
        QStringLiteral(":/fonts/AtkinsonHyperlegibleNext-Regular.ttf"));
    const auto semibold = QFontDatabase::addApplicationFont(
        QStringLiteral(":/fonts/AtkinsonHyperlegibleNext-SemiBold.ttf"));
    const auto mono = QFontDatabase::addApplicationFont(
        QStringLiteral(":/fonts/AtkinsonHyperlegibleMono-Regular.ttf"));
    if (regular < 0 || semibold < 0 || mono < 0)
        return false;
    if (!capturedBaseFontPx)
        capturedBaseFontPx = baseFontPx;
    auto font = application.font();
    setFace(font, QFont::Normal);
    font.setPixelSize(qMax(1, qRound(*capturedBaseFontPx * 1.25)));
    application.setFont(font);
    const auto resolved = QFontInfo(application.font());
    const auto installed =
        resolved.family() == QString::fromLatin1(proportionalFamily) &&
        resolved.pixelSize() == qMax(1, qRound(*capturedBaseFontPx * 1.25));
    if (installed)
        installedBodyFont = font;
    return installed;
}

std::optional<int> baseFontPx()
{
    return capturedBaseFontPx;
}

std::optional<QFont> bodyFont()
{
    return installedBodyFont;
}

QFont bodyMono(const QFont &body)
{
    auto font = body;
    font.setFamily(QString::fromLatin1(monoFamily));
    font.setStyleName(QStringLiteral("Regular"));
    font.setWeight(QFont::Normal);
    font.setStyle(QFont::StyleNormal);
    font.setHintingPreference(QFont::PreferFullHinting);
    font.setPixelSize(resolvedPixelSize(body));
    return font;
}

QFont caption(const QFont &source)
{
    auto font = source;
    setFace(font, QFont::Normal);
    font.setPixelSize(capturedBaseFontPx.value_or(resolvedPixelSize(source)));
    return font;
}

QFont bold(const QFont &source)
{
    auto font = source;
    font.setStyleName({});
    font.setWeight(QFont::DemiBold);
    font.setPixelSize(resolvedPixelSize(source));
    return font;
}

std::optional<QFont> fitted(const QFont &base, int availableHeight)
{
    const auto maximum = resolvedPixelSize(caption(base));
    for (auto pixelSize = maximum; pixelSize > 0; --pixelSize) {
        auto candidate = base;
        candidate.setPixelSize(pixelSize);
        if (occupiedHeight(candidate) <= availableHeight)
            return candidate;
    }
    return std::nullopt;
}

QPointF glyphCenteringOffset(const QFont &reference, const QFont &displayed,
                             QStringView text)
{
    const auto string = text.toString();
    const auto referenceCenter =
        QFontMetricsF(reference).tightBoundingRect(string).center();
    const auto displayedCenter =
        QFontMetricsF(displayed).tightBoundingRect(string).center();
    return referenceCenter - displayedCenter;
}

} // namespace typography
