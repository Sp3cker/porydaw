#include "ui/layout.h"
#include "ui/theme/themeresolver.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"

#include <QApplication>
#include <QFontInfo>
#include <QFontMetrics>
#include <QFontMetricsF>
#include <QLabel>
#include <QtGlobal>

#include <array>
#include <cstdio>

int runFontCheck(int expectedBaseFontPx) {
  auto *application = qobject_cast<QApplication *>(QApplication::instance());
  if (!application)
    return 1;
  auto failures = 0;
  const auto check = [&failures](bool condition, const char *message) {
    if (!condition) {
      std::fprintf(stderr, "fontcheck: FAIL: %s\n", message);
      ++failures;
    }
  };
  const auto baseFontPx = typography::baseFontPx();
  check(baseFontPx.has_value(),
        "Typography did not capture the base font pixel size");
  if (!baseFontPx)
    return 1;
  struct ExpectedSpace {
    layout::Space token;
    double multiplier;
  };
  constexpr auto expectedSpaces = std::array{
      ExpectedSpace{layout::Space::Zero, 0.0},
      ExpectedSpace{layout::Space::Half, 0.125},
      ExpectedSpace{layout::Space::One, 0.25},
      ExpectedSpace{layout::Space::Two, 0.5},
      ExpectedSpace{layout::Space::Three, 0.75},
      ExpectedSpace{layout::Space::Four, 1.0},
      ExpectedSpace{layout::Space::Six, 1.5},
      ExpectedSpace{layout::Space::Eight, 2.0},
  };
  const auto checkSpaces = [&] {
    for (const auto &expected : expectedSpaces) {
      const auto value = expected.multiplier == 0.0
                             ? 0
                             : qMax(1, qRound(*baseFontPx * expected.multiplier));
      check(layout::space(expected.token) == value,
            "Layout spacing token has the wrong resolved value");
    }
  };
  const auto styleSheet = application->styleSheet();
  checkSpaces();
  check(layout::initialize(*application, *baseFontPx),
        "Layout initialization is not idempotent");
  check(!layout::initialize(*application, 0),
        "Layout accepted an invalid base font pixel size");
  check(!layout::initialize(*application, *baseFontPx + 1),
        "Layout accepted a conflicting base font pixel size");
  check(application->styleSheet() == styleSheet,
        "Repeated Layout initialization changed established geometry");
  checkSpaces();
  check(expectedBaseFontPx > 0 && *baseFontPx == expectedBaseFontPx,
        "Typography did not preserve the pre-install application font size");
  const auto body = QApplication::font();
  const auto bodyInfo = QFontInfo(body);
  const auto expectedBodySize = qMax(1, qRound(*baseFontPx * 1.25));
  check(body.hintingPreference() == QFont::PreferFullHinting,
        "Body does not prefer fully hinted glyph outlines");
  check(bodyInfo.family() == QStringLiteral("Atkinson Hyperlegible Next") &&
            bodyInfo.pixelSize() == expectedBodySize &&
            bodyInfo.weight() == QFont::Normal,
        "Body has the wrong face, size, or weight");
  const auto mono = typography::bodyMono(body);
  const auto monoInfo = QFontInfo(mono);
  check(mono.hintingPreference() == QFont::PreferFullHinting,
        "Body Mono does not prefer fully hinted glyph outlines");
  check(monoInfo.family() == QStringLiteral("Atkinson Hyperlegible Mono") &&
            monoInfo.pixelSize() == expectedBodySize &&
            monoInfo.weight() == QFont::Normal,
        "Body Mono has the wrong face, size, or weight");
  const auto caption = typography::caption(body);
  const auto captionInfo = QFontInfo(caption);
  check(caption.hintingPreference() == QFont::PreferFullHinting,
        "Caption does not prefer fully hinted glyph outlines");
  check(captionInfo.family() == QStringLiteral("Atkinson Hyperlegible Next") &&
            captionInfo.pixelSize() == *baseFontPx &&
            captionInfo.weight() == QFont::Normal,
        "Caption has the wrong face, size, or weight");
  const auto bodyBoldInfo = QFontInfo(typography::bold(body));
  check(bodyBoldInfo.pixelSize() == bodyInfo.pixelSize() &&
            bodyBoldInfo.weight() == QFont::DemiBold,
        "Body Bold changed size or failed to resolve to the emphasis face");
  const auto captionBoldInfo = QFontInfo(typography::bold(caption));
  check(captionBoldInfo.pixelSize() == captionInfo.pixelSize() &&
            captionBoldInfo.weight() == QFont::DemiBold,
        "Caption Bold changed size or failed to resolve to the emphasis face");
  const auto captionHeight = QFontMetrics(caption).height();
  for (auto height = 0; height <= captionHeight + 4; ++height) {
    const auto fitted = typography::fitted(body, height);
    if (!fitted)
      continue;
    const auto size = QFontInfo(*fitted).pixelSize();
    const auto metrics = QFontMetrics(*fitted);
    check(size <= captionInfo.pixelSize() &&
              metrics.ascent() + metrics.descent() <= height,
          "Fitted text exceeds its size or height limit");
    if (size < captionInfo.pixelSize()) {
      auto larger = *fitted;
      larger.setPixelSize(size + 1);
      const auto largerMetrics = QFontMetrics(larger);
      check(largerMetrics.ascent() + largerMetrics.descent() > height,
            "Fitted text is not maximal");
    }
  }
  check(!typography::fitted(body, 0),
        "Fitted text exists without positive available height");
  const auto selected = typography::bold(body);
  const auto text = QStringLiteral("1 · Tést g̦");
  const auto referenceBounds = QFontMetricsF(body).tightBoundingRect(text);
  const auto displayedBounds = QFontMetricsF(selected).tightBoundingRect(text);
  check(displayedBounds
                .translated(
                    typography::glyphCenteringOffset(body, selected, text))
                .center() == referenceBounds.center(),
        "Displayed glyph bounds are not centered");
  // Desktop components (qt5ct/qt6ct-style platform themes, portal settings)
  // can reset the application font after startup. Widgets frozen by
  // stylesheet polish hide the reset until the next theme apply repolishes
  // them, so the apply must restore Body rather than cement the reset font.
  check(typography::bodyFont().has_value(),
        "Typography did not capture the installed Body font");
  QLabel probe(QStringLiteral("probe"));
  probe.show();
  probe.ensurePolished();
  check(QFontInfo(probe.font()).family() ==
            QStringLiteral("Atkinson Hyperlegible Next"),
        "A polished widget does not start on Body");
  auto reset = QApplication::font();
  reset.setFamily(QStringLiteral("Atkinson Hyperlegible Mono"));
  QApplication::setFont(reset);
  themes::apply(*application, themes::vanilla());
  check(QFontInfo(QApplication::font()).family() ==
            QStringLiteral("Atkinson Hyperlegible Next"),
        "Theme apply did not restore Body after an external font reset");
  check(QFontInfo(probe.font()).family() ==
            QStringLiteral("Atkinson Hyperlegible Next"),
        "Theme apply left a polished widget on the externally reset font");
  // The system-font preference swaps the semantic scale onto the platform
  // typeface captured before the bundled install; a theme reapply carries
  // the swap through already-polished widgets, and turning the preference
  // back off restores the bundled faces the same way.
  const auto platformFamily = typography::systemFontFamily();
  check(!platformFamily.isEmpty(),
        "Typography did not capture the platform font family");
  check(!typography::systemMonoFamily().isEmpty(),
        "Typography did not capture the platform fixed-pitch family");
  typography::setUseSystemFont(true);
  const auto systemBody = typography::bodyFont();
  check(systemBody.has_value() &&
            QFontInfo(*systemBody).family() == platformFamily &&
            QFontInfo(*systemBody).pixelSize() == *baseFontPx,
        "System-font Body is not the platform face at its native size");
  themes::apply(*application, themes::vanilla());
  check(QFontInfo(QApplication::font()).family() == platformFamily,
        "Theme apply did not install the system Body");
  check(QFontInfo(probe.font()).family() == platformFamily,
        "A polished widget did not follow the system-font preference");
  const auto systemCaption = typography::caption(QApplication::font());
  check(QFontInfo(systemCaption).family() == platformFamily &&
            QFontInfo(systemCaption).pixelSize() ==
                qMax(1, qRound(*baseFontPx / 1.25)),
        "System-font Caption is not the platform face a step below Body");
  check(typography::bodyMono(QApplication::font()).family() ==
            typography::systemMonoFamily(),
        "System-font Body Mono is not the platform fixed-pitch face");
  typography::setUseSystemFont(false);
  themes::apply(*application, themes::vanilla());
  check(QFontInfo(QApplication::font()).family() ==
                QStringLiteral("Atkinson Hyperlegible Next") &&
            QFontInfo(QApplication::font()).pixelSize() == expectedBodySize,
        "Disabling the system-font preference did not restore Body");
  check(QFontInfo(probe.font()).family() ==
            QStringLiteral("Atkinson Hyperlegible Next"),
        "A polished widget did not return to the bundled face");
  if (failures == 0)
    std::printf("fontcheck: PASS\n");
  return failures == 0 ? 0 : 1;
}
