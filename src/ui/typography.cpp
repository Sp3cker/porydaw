#include "typography.h"
#include <algorithm>

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
// The pre-install platform font and fixed family back the user-facing
// system-font preference: the semantic scale swaps onto them wholesale.
std::optional<QFont> capturedPlatformFont;
QString capturedFixedFamily;
bool systemFontPreferred = false;

void setFace(QFont &font, QFont::Weight weight)
{
    font.setFamily(QString::fromLatin1(proportionalFamily));
    font.setStyleName({});
    font.setWeight(weight);
    font.setStyle(QFont::StyleNormal);
    font.setHintingPreference(QFont::PreferNoHinting);
    font.setStyleStrategy(QFont::StyleStrategy(font.styleStrategy() | QFont::PreferAntialias));
}

QFont bundledBody()
{
    auto font = *capturedPlatformFont;
    setFace(font, QFont::Normal);
    font.setPixelSize(qMax(1, qRound(*capturedBaseFontPx * 1.25)));
    return font;
}

// The platform face at its native size: what every other Qt application on
// the machine shows for body text. Caption keeps the bundled scale's 1.25
// ratio below it so the hierarchy survives the swap.
QFont systemBody()
{
    auto font = *capturedPlatformFont;
    font.setPixelSize(*capturedBaseFontPx);
    return font;
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

std::optional<QFont> fitFont(QFont font, int maximumPixelSize, int availableHeight)
{
    for (auto pixelSize = maximumPixelSize; pixelSize > 0; --pixelSize) {
        font.setPixelSize(pixelSize);
        if (occupiedHeight(font) <= availableHeight)
            return font;
    }
    return std::nullopt;
}

} // namespace

bool installBundledFonts(QApplication &application)
{
    const auto baseFontPx = QFontInfo(application.font()).pixelSize();
    if (baseFontPx <= 0)
        return false;
    if (!capturedPlatformFont) {
        capturedPlatformFont = application.font();
        capturedFixedFamily = QFontDatabase::systemFont(QFontDatabase::FixedFont).family();
    }
    const auto regular = QFontDatabase::addApplicationFont(
        QStringLiteral(":/fonts/AtkinsonHyperlegibleNext-Regular.ttf"));
    const auto light = QFontDatabase::addApplicationFont(
        QStringLiteral(":/fonts/AtkinsonHyperlegibleNext-Light.ttf"));
    const auto semibold = QFontDatabase::addApplicationFont(
        QStringLiteral(":/fonts/AtkinsonHyperlegibleNext-SemiBold.ttf"));
    const auto mono = QFontDatabase::addApplicationFont(
        QStringLiteral(":/fonts/AtkinsonHyperlegibleMono-Regular.ttf"));
    if (regular < 0 || light < 0 || semibold < 0 || mono < 0)
        return false;
    if (!capturedBaseFontPx)
        capturedBaseFontPx = baseFontPx;
    auto font = application.font();
    setFace(font, QFont::Normal);
    font.setPixelSize(qMax(1, qRound(*capturedBaseFontPx * 1.25)));
    application.setFont(font);
    const auto resolved = QFontInfo(application.font());
    const auto installed = resolved.family() == QString::fromLatin1(proportionalFamily) &&
                           resolved.pixelSize() == qMax(1, qRound(*capturedBaseFontPx * 1.25));
    if (installed)
        installedBodyFont = systemFontPreferred ? systemBody() : font;
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

void setUseSystemFont(bool preferred)
{
    systemFontPreferred = preferred;
    if (installedBodyFont)
        installedBodyFont = preferred ? systemBody() : bundledBody();
}

QString systemFontFamily()
{
    return capturedPlatformFont ? QFontInfo(*capturedPlatformFont).family() : QString();
}

QString systemMonoFamily()
{
    return capturedFixedFamily;
}
QFont bodyMono(const QFont &body)
{
    auto font = body;
    if (systemFontPreferred && !capturedFixedFamily.isEmpty()) {
        font.setFamily(capturedFixedFamily);
        font.setStyleName({});
        font.setWeight(QFont::Normal);
        font.setStyle(QFont::StyleNormal);
        font.setPixelSize(resolvedPixelSize(body));
        return font;
    }
    font.setFamily(QString::fromLatin1(monoFamily));
    font.setStyleName(QStringLiteral("Regular"));
    font.setWeight(QFont::Normal);
    font.setStyle(QFont::StyleNormal);
    font.setHintingPreference(QFont::PreferNoHinting);
    font.setStyleStrategy(QFont::StyleStrategy(font.styleStrategy() | QFont::PreferAntialias));
    font.setPixelSize(resolvedPixelSize(body));
    return font;
}

QFont caption(const QFont &source)
{
    if (systemFontPreferred && capturedPlatformFont && capturedBaseFontPx) {
        auto font = *capturedPlatformFont;
        font.setPixelSize(qMax(1, qRound(*capturedBaseFontPx / 1.25)));
        return font;
    }
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
    return fitFont(base, std::min(resolvedPixelSize(base), resolvedPixelSize(caption(base))),
                   availableHeight);
}

QFont noteName(const QFont &source)
{
    auto font = caption(source);
#ifdef Q_OS_MACOS
    // CoreText keeps the bundled Regular face crisp at the reduced label size.
    setFace(font, QFont::Normal);
#else
    // SemiBold keeps labels legible at the reduced size on 1x displays.
    setFace(font, QFont::DemiBold);
#endif
    return font;
}

QPointF glyphCenteringOffset(const QFont &reference, const QFont &displayed, QStringView text)
{
    const auto string = text.toString();
    const auto referenceCenter = QFontMetricsF(reference).tightBoundingRect(string).center();
    const auto displayedCenter = QFontMetricsF(displayed).tightBoundingRect(string).center();
    return referenceCenter - displayedCenter;
}

} // namespace typography
