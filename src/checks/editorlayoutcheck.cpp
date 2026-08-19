#include "ui/layout.h"

#include <QApplication>
#include <QtGlobal>

#include <array>
#include <cstdio>

namespace {

class Reporter
{
  public:
    void check(bool condition, const char *value, const char *invariant)
    {
        if (condition)
            return;
        std::fprintf(stderr, "editor-layout-check: FAIL: %s: %s\n", value, invariant);
        ++m_failures;
    }

    int finish(int valueCount) const
    {
        std::printf(m_failures == 0 ? "editor-layout-check: PASS (%d values)\n"
                                    : "editor-layout-check: FAIL (%d values)\n",
                    valueCount);
        return m_failures == 0 ? 0 : 1;
    }

  private:
    int m_failures = 0;
};

struct IntegralValue {
    const char *id;
    double factor;
    int at12;
    int at16;
};

struct FractionalValue {
    const char *id;
    qreal factor;
};

struct SpaceValue {
    layout::Space token;
    double factor;
};

int resolveFontFactor(int baseFontPx, double factor)
{
    if (factor == 0.0)
        return 0;
    return qMax(1, qRound(baseFontPx * factor));
}

void checkIntegral(Reporter &reporter, const IntegralValue &value, int baseFontPx)
{
    reporter.check(value.at12 == resolveFontFactor(12, value.factor), value.id,
                   "12px expectation does not use qRound then qMax");
    reporter.check(value.at16 == resolveFontFactor(16, value.factor), value.id,
                   "16px expectation does not use qRound then qMax");
    reporter.check(layout::fontPx(value.factor) == resolveFontFactor(baseFontPx, value.factor),
                   value.id, "fontPx has the wrong integral rounded value");
}

int runCheck(QApplication &application, int baseFontPx)
{
    const auto initialized = layout::initialize(application, baseFontPx);
    Reporter reporter;
    reporter.check(initialized, "layout initialization",
                   "did not accept the requested clean-process scale");
    if (!initialized)
        return reporter.finish(0);

    const auto integralValues = std::array{
        IntegralValue{"clamped positive minimum", 1.0 / 48.0, 1, 1},
        IntegralValue{"one twelfth", 1.0 / 12.0, 1, 1},
        IntegralValue{"one sixth", 1.0 / 6.0, 2, 3},
        IntegralValue{"one third", 1.0 / 3.0, 4, 5},
        IntegralValue{"five twelfths", 5.0 / 12.0, 5, 7},
        IntegralValue{"seven twelfths", 7.0 / 12.0, 7, 9},
        IntegralValue{"four thirds", 4.0 / 3.0, 16, 21},
        IntegralValue{"seventeen and one-half", 17.5, 210, 280},
    };
    for (const auto &value : integralValues)
        checkIntegral(reporter, value, baseFontPx);

    const auto boundaryValues = std::array{
        IntegralValue{"base18 seven twelfths", 7.0 / 12.0, 11, 11},
        IntegralValue{"base18 one twelfth", 1.0 / 12.0, 2, 2},
    };
    for (const auto &value : boundaryValues) {
        reporter.check(value.at12 == resolveFontFactor(18, value.factor), value.id,
                       "18px half-pixel boundary has the wrong rounded value");
        if (baseFontPx == 18)
            reporter.check(layout::fontPx(value.factor) == value.at12, value.id,
                           "fontPx has the wrong 18px boundary value");
    }

    const auto fractionalValues = std::array{
        FractionalValue{"positive fontPxF", 3.0},
        FractionalValue{"fractional fontPxF", 7.0 / 24.0},
        FractionalValue{"negative fontPxF", -1.0 / 24.0},
    };
    for (const auto &value : fractionalValues) {
        const qreal expected = qreal(baseFontPx) * value.factor;
        reporter.check(layout::fontPxF(value.factor) == expected, value.id,
                       "fontPxF is not the exact unrounded signed product");
    }

    const auto spaceValues = std::array{
        SpaceValue{layout::Space::Zero, 0.0},   SpaceValue{layout::Space::Half, 0.125},
        SpaceValue{layout::Space::One, 0.25},   SpaceValue{layout::Space::Two, 0.5},
        SpaceValue{layout::Space::Three, 0.75}, SpaceValue{layout::Space::Four, 1.0},
        SpaceValue{layout::Space::Six, 1.5},    SpaceValue{layout::Space::Eight, 2.0},
    };
    for (const auto &value : spaceValues)
        reporter.check(layout::space(value.token) == resolveFontFactor(baseFontPx, value.factor),
                       "spacing token", "does not use the resolved font-relative scale");
    reporter.check(layout::singlePixel() == 1, "singlePixel",
                   "is not invariant at one physical pixel");

    const int expectedPlotOrigin = resolveFontFactor(baseFontPx, 17.5 + 13.0 / 3.0);
    reporter.check(layout::fontPx(17.5 + 13.0 / 3.0) == expectedPlotOrigin, "plot arithmetic",
                   "does not resolve the combined plot origin");
    if (baseFontPx == 12)
        reporter.check(expectedPlotOrigin == 262, "12px plot arithmetic",
                       "does not preserve the expected plot origin");
    if (baseFontPx == 16)
        reporter.check(expectedPlotOrigin == 349, "16px plot arithmetic",
                       "does not preserve the expected plot origin");
    if (baseFontPx == 18)
        reporter.check(expectedPlotOrigin == 393, "18px plot arithmetic",
                       "does not preserve the expected plot origin");
    return reporter.finish(int(integralValues.size() + boundaryValues.size() +
                               fractionalValues.size() + spaceValues.size() + 5));
}

} // namespace

int runEditorLayoutCheck(QApplication &application, int baseFontPx)
{
    return runCheck(application, baseFontPx);
}
