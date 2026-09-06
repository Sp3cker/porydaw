#include "checks/themelayout/tst_themelayout.h"

#include "ui/layout.h"
#include "ui/theme/themeresolver.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"

#include <QApplication>
#include <QFontInfo>
#include <QFontMetrics>
#include <QFontMetricsF>
#include <QLabel>
#include <QtTest>

#include <array>
#include <optional>
#include <utility>

namespace {

bool hasTabularNumbers(const QFont &font)
{
    constexpr QFont::Tag tag{"tnum"};
    return font.isFeatureSet(tag) && font.featureValue(tag) == 1;
}

int resolvedSpace(int baseFontPx, double multiplier)
{
    return multiplier == 0.0 ? 0 : qMax(1, qRound(baseFontPx * multiplier));
}

} // namespace

void ThemeLayoutFontTest::typographyAndLayoutInitialization()
{
    const std::optional<int> baseFontPx = typography::baseFontPx();
    QVERIFY(baseFontPx.has_value());
    QVERIFY(m_expectedBaseFontPx > 0);
    QCOMPARE(*baseFontPx, m_expectedBaseFontPx);

    const std::array spaces{
        std::pair{layout::Space::Zero, 0.0},   std::pair{layout::Space::Half, 0.125},
        std::pair{layout::Space::One, 0.25},   std::pair{layout::Space::Two, 0.5},
        std::pair{layout::Space::Three, 0.75}, std::pair{layout::Space::Four, 1.0},
        std::pair{layout::Space::Six, 1.5},    std::pair{layout::Space::Eight, 2.0}};
    for (const auto &[token, multiplier] : spaces)
        QCOMPARE(layout::space(token), resolvedSpace(*baseFontPx, multiplier));

    const QString styleSheet = m_application->styleSheet();
    QVERIFY(layout::initialize(*m_application, *baseFontPx));
    QVERIFY(!layout::initialize(*m_application, 0));
    QVERIFY(!layout::initialize(*m_application, *baseFontPx + 1));
    QCOMPARE(m_application->styleSheet(), styleSheet);
    for (const auto &[token, multiplier] : spaces)
        QCOMPARE(layout::space(token), resolvedSpace(*baseFontPx, multiplier));
}

void ThemeLayoutFontTest::typographyFaceContracts()
{
    const std::optional<int> baseFontPx = typography::baseFontPx();
    QVERIFY(baseFontPx.has_value());
    const QFont body = QApplication::font();
    const QFontInfo bodyInfo(body);
    const int expectedBodySize = qMax(1, qRound(*baseFontPx * 1.125));
    QCOMPARE(body.hintingPreference(), QFont::PreferNoHinting);
    QCOMPARE(bodyInfo.family(), QStringLiteral("Atkinson Hyperlegible Next"));
    QCOMPARE(bodyInfo.pixelSize(), expectedBodySize);
    QCOMPARE(bodyInfo.weight(), static_cast<int>(QFont::Normal));
    QVERIFY(hasTabularNumbers(body));

    const QFont mono = typography::bodyMono(body);
    const QFontInfo monoInfo(mono);
    QCOMPARE(mono.hintingPreference(), QFont::PreferNoHinting);
    QCOMPARE(monoInfo.family(), QStringLiteral("Atkinson Hyperlegible Mono"));
    QCOMPARE(monoInfo.pixelSize(), expectedBodySize);
    QCOMPARE(monoInfo.weight(), static_cast<int>(QFont::Normal));
    QVERIFY(hasTabularNumbers(mono));

    const QFont tableMono = typography::tableMono(body);
    QCOMPARE(QFontInfo(tableMono).family(), monoInfo.family());
    QCOMPARE(tableMono.letterSpacingType(), QFont::AbsoluteSpacing);
    QCOMPARE(tableMono.letterSpacing(), -0.5);

    const QFont caption = typography::caption(body);
    const QFontInfo captionInfo(caption);
    QCOMPARE(caption.hintingPreference(), QFont::PreferNoHinting);
    QCOMPARE(captionInfo.family(), QStringLiteral("Atkinson Hyperlegible Next"));
    QCOMPARE(captionInfo.pixelSize(), *baseFontPx);
    QCOMPARE(captionInfo.weight(), static_cast<int>(QFont::Normal));
    QVERIFY(hasTabularNumbers(caption));

    const QFontInfo regularCaptionInfo(typography::regular(caption));
    QCOMPARE(regularCaptionInfo.family(), captionInfo.family());
    QCOMPARE(regularCaptionInfo.pixelSize(), captionInfo.pixelSize());
    QCOMPARE(regularCaptionInfo.weight(), static_cast<int>(QFont::Normal));
    const QFontInfo italicCaptionInfo(typography::italic(caption));
    QCOMPARE(italicCaptionInfo.family(), captionInfo.family());
    QCOMPARE(italicCaptionInfo.pixelSize(), captionInfo.pixelSize());
    QCOMPARE(italicCaptionInfo.style(), QFont::StyleItalic);
    const QFontInfo bodyBoldInfo(typography::bold(body));
    QCOMPARE(bodyBoldInfo.pixelSize(), bodyInfo.pixelSize());
    QCOMPARE(bodyBoldInfo.weight(), static_cast<int>(QFont::DemiBold));
    const QFontInfo captionBoldInfo(typography::bold(caption));
    QCOMPARE(captionBoldInfo.pixelSize(), captionInfo.pixelSize());
    QCOMPARE(captionBoldInfo.weight(), static_cast<int>(QFont::DemiBold));
}

void ThemeLayoutFontTest::fittedTypographyContracts()
{
    const QFont body = QApplication::font();
    const QFont caption = typography::caption(body);
    const QFontInfo captionInfo(caption);
    const int captionHeight = QFontMetrics(caption).height();
    QVERIFY(typography::fitted(body, captionHeight).has_value());
    for (int height = 1; height <= captionHeight + 4; ++height) {
        const std::optional<QFont> fitted = typography::fitted(body, height);
        if (!fitted)
            continue;
        const int size = QFontInfo(*fitted).pixelSize();
        const QFontMetrics metrics(*fitted);
        QVERIFY(size <= captionInfo.pixelSize());
        QVERIFY(metrics.ascent() + metrics.descent() <= height);
        if (size < captionInfo.pixelSize()) {
            auto larger = *fitted;
            larger.setPixelSize(size + 1);
            const QFontMetrics largerMetrics(larger);
            QVERIFY(largerMetrics.ascent() + largerMetrics.descent() > height);
        }
    }
    QVERIFY(!typography::fitted(body, 0).has_value());

    const QFont noteName = typography::noteName(body);
    const QFontInfo noteNameInfo(noteName);
    const QFontMetrics noteNameMetrics(noteName);
#ifdef Q_OS_MACOS
    const QString expectedNoteNameStyle = QStringLiteral("Regular");
#else
    const QString expectedNoteNameStyle = QStringLiteral("SemiBold");
#endif
    QCOMPARE(noteNameInfo.family(), QStringLiteral("Atkinson Hyperlegible Next"));
    QCOMPARE(noteNameInfo.styleName(), expectedNoteNameStyle);
    QCOMPARE(noteNameInfo.pixelSize(), captionInfo.pixelSize());
    QVERIFY(noteNameMetrics.ascent() + noteNameMetrics.descent() <= captionHeight);
    auto smallerNoteName = noteName;
    smallerNoteName.setPixelSize(noteNameInfo.pixelSize() - 2);
    const std::optional<QFont> fittedNoteName = typography::fitted(smallerNoteName, captionHeight);
    QVERIFY(fittedNoteName.has_value());
    QCOMPARE(QFontInfo(*fittedNoteName).pixelSize(), QFontInfo(smallerNoteName).pixelSize());

    const QFont selected = typography::bold(body);
    const QString text = QStringLiteral("1 · Tést g̦");
    const QRectF referenceBounds = QFontMetricsF(body).tightBoundingRect(text);
    const QRectF displayedBounds = QFontMetricsF(selected).tightBoundingRect(text);
    QCOMPARE(
        displayedBounds.translated(typography::glyphCenteringOffset(body, selected, text)).center(),
        referenceBounds.center());
}

void ThemeLayoutFontTest::themeApplyRestoresExternallyResetFont()
{
    QVERIFY(typography::bodyFont().has_value());
    QLabel probe(QStringLiteral("probe"));
    probe.show();
    probe.ensurePolished();
    QTRY_VERIFY(probe.isVisible());
    QCOMPARE(QFontInfo(probe.font()).family(), QStringLiteral("Atkinson Hyperlegible Next"));
    auto reset = QApplication::font();
    reset.setFamily(QStringLiteral("Atkinson Hyperlegible Mono"));
    QApplication::setFont(reset);
    themes::apply(*m_application, themes::vanilla());
    QCOMPARE(QFontInfo(QApplication::font()).family(),
             QStringLiteral("Atkinson Hyperlegible Next"));
    QCOMPARE(QFontInfo(probe.font()).family(), QStringLiteral("Atkinson Hyperlegible Next"));
}
