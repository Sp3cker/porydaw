#include "checks/themelayout/tst_themelayout.h"

#include "ui/layout.h"
#include "ui/polyphonypanel.h"

#include <QApplication>
#include <QtGlobal>

#include <QtTest>

#include <cmath>
#include <utility>

namespace {

enum class ScaleOperation { FontPx, FontPxF, Space, SinglePixel };

int expectedIntegral(double multiplier, int baseFontPx)
{
    if (multiplier == 0.0)
        return 0;
    return qMax(1, qRound(baseFontPx * multiplier));
}

qreal expectedFractional(double multiplier, int baseFontPx)
{
    return qreal(baseFontPx) * multiplier;
}

double spaceMultiplier(layout::Space token)
{
    switch (token) {
    case layout::Space::Zero:
        return 0.0;
    case layout::Space::Half:
        return 0.125;
    case layout::Space::One:
        return 0.25;
    case layout::Space::Two:
        return 0.5;
    case layout::Space::Three:
        return 0.75;
    case layout::Space::Four:
        return 1.0;
    case layout::Space::Six:
        return 1.5;
    case layout::Space::Eight:
        return 2.0;
    }
    Q_UNREACHABLE();
}

} // namespace

void ThemeLayoutScaleTest::initializationIsProcessScoped()
{
    auto *application = qobject_cast<QApplication *>(QApplication::instance());
    QVERIFY(application);
    const QString styleSheet = application->styleSheet();
    QVERIFY(layout::initialize(*application, m_baseFontPx));
    QVERIFY(!layout::initialize(*application, 0));
    QVERIFY(!layout::initialize(*application, m_baseFontPx + 1));
    QCOMPARE(application->styleSheet(), styleSheet);
}

void ThemeLayoutScaleTest::layoutScale_data()
{
    QTest::addColumn<int>("operation");
    QTest::addColumn<double>("multiplier");
    QTest::addColumn<int>("spaceToken");
    const auto addFontPx = [](const char *name, double multiplier) {
        QTest::newRow(name) << static_cast<int>(ScaleOperation::FontPx) << multiplier << 0;
    };
    addFontPx("fontPx-clamped-positive-minimum", 1.0 / 48.0);
    addFontPx("fontPx-one-twelfth", 1.0 / 12.0);
    addFontPx("fontPx-one-sixth", 1.0 / 6.0);
    addFontPx("fontPx-one-third", 1.0 / 3.0);
    addFontPx("fontPx-five-twelfths", 5.0 / 12.0);
    addFontPx("fontPx-seven-twelfths", 7.0 / 12.0);
    addFontPx("fontPx-four-thirds", 4.0 / 3.0);
    addFontPx("fontPx-seventeen-and-one-half", 17.5);

    for (const auto &[name, multiplier] :
         {std::pair{"fontPxF-positive", 3.0}, std::pair{"fontPxF-fractional", 7.0 / 24.0},
          std::pair{"fontPxF-negative", -1.0 / 24.0}})
        QTest::newRow(name) << static_cast<int>(ScaleOperation::FontPxF) << multiplier << 0;

    for (const auto &[name, token] :
         {std::pair{"space-zero", layout::Space::Zero},
          std::pair{"space-half", layout::Space::Half}, std::pair{"space-one", layout::Space::One},
          std::pair{"space-two", layout::Space::Two},
          std::pair{"space-three", layout::Space::Three},
          std::pair{"space-four", layout::Space::Four}, std::pair{"space-six", layout::Space::Six},
          std::pair{"space-eight", layout::Space::Eight}})
        QTest::newRow(name) << static_cast<int>(ScaleOperation::Space) << 0.0
                            << static_cast<int>(token);
    QTest::newRow("single-pixel") << static_cast<int>(ScaleOperation::SinglePixel) << 0.0 << 0;
}

void ThemeLayoutScaleTest::layoutScale()
{
    QFETCH(int, operation);
    QFETCH(double, multiplier);
    QFETCH(int, spaceToken);
    switch (static_cast<ScaleOperation>(operation)) {
    case ScaleOperation::FontPx:
        QCOMPARE(layout::fontPx(multiplier), expectedIntegral(multiplier, m_baseFontPx));
        return;
    case ScaleOperation::FontPxF:
        QCOMPARE(layout::fontPxF(multiplier), expectedFractional(multiplier, m_baseFontPx));
        return;
    case ScaleOperation::Space: {
        const auto token = static_cast<layout::Space>(spaceToken);
        QCOMPARE(layout::space(token), expectedIntegral(spaceMultiplier(token), m_baseFontPx));
        return;
    }
    case ScaleOperation::SinglePixel:
        QCOMPARE(layout::singlePixel(), 1);
        return;
    }
}

void ThemeLayoutScaleTest::polyphonyLayoutScales()
{
    PolyphonyPanel panel;
    panel.setInvertChecked(true);
    AudioEngine::PolySnapshot snapshot;
    snapshot.maxPcmChannels = 5;
    snapshot.invert = true;
    snapshot.pcm[0] = {true, false, 0, 60};
    snapshot.pcm[MAX_PCM_CHANNELS] = {true, false, 1, 72};
    panel.updateSnapshot(snapshot);
    panel.resize(layout::fontPx(48), layout::fontPx(70));
    panel.show();
    QTRY_VERIFY(!panel.wideLayoutActive());
    QTRY_VERIFY(panel.overflowSectionRect().top() >= panel.usageSectionRect().bottom());
    QTRY_VERIFY(panel.gridFullyVisible());

    panel.resize(layout::fontPx(75), layout::fontPx(50));
    QTRY_VERIFY(panel.wideLayoutActive());
    QTRY_VERIFY(panel.overflowSectionRect().left() >= panel.usageSectionRect().right());
    QTRY_VERIFY(panel.gridFullyVisible());

    panel.resize(layout::fontPx(32), layout::fontPx(20));
    QTRY_VERIFY(!panel.wideLayoutActive());
    QTRY_VERIFY(panel.gridFullyVisible());
    QTRY_VERIFY(panel.vScrollRange() > 0);
}
