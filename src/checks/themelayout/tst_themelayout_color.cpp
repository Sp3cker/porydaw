#include "checks/themelayout/tst_themelayout.h"

#include "ui/theme/color_math.h"
#include "ui/theme/themecontroller.h"

#include "ui/theme/themeresolver.h"
#include "ui/theme/trackidentitycolors.h"

#include <QColor>
#include <QtTest>

#include <cstddef>

#include <array>
#include <cmath>
#include <utility>

namespace {

constexpr auto kContrastEpsilon = 1e-12;

const themes::Theme themeForName(const QString &name)
{
    if (name == QStringLiteral("vanilla"))
        return themes::vanilla();
    if (name == QStringLiteral("dark-neutral-high"))
        return themes::darkNeutralHigh();
    if (name == QStringLiteral("immaterial"))
        return themes::immaterial();
    QTest::qFail(qPrintable(QStringLiteral("unknown theme name: %1").arg(name)), __FILE__,
                 __LINE__);
    return themes::vanilla();
}

bool completeTheme(const themes::Theme &theme)
{
    for (std::size_t index = 0; index < theme.colors.size(); ++index) {
        const QColor color = theme.colors[index];
        const auto role = static_cast<themes::Role>(index);
        if (!color.isValid() || (role != themes::Role::song_view_grid && color.alpha() != 255))
            return false;
    }
    return true;
}

void verifyMenuAndControlContracts(const themes::Theme &theme)
{
    QVERIFY(themes::contrastRatio(theme.color(themes::Role::menu_bar_text),
                                  theme.color(themes::Role::menu_bar_background)) >= 4.5);
    QVERIFY(themes::contrastRatio(theme.color(themes::Role::button_hover_text),
                                  theme.color(themes::Role::button_hover_background)) >= 4.5);
    QVERIFY(themes::contrastRatio(theme.color(themes::Role::button_pressed_text),
                                  theme.color(themes::Role::button_pressed_background)) >= 4.5);
    QCOMPARE(theme.color(themes::Role::combo_drop_down_pressed_background),
             theme.color(themes::Role::button_pressed_background));
    QCOMPARE(theme.color(themes::Role::menu_background),
             theme.color(themes::Role::item_background));
    QCOMPARE(theme.color(themes::Role::menu_text), theme.color(themes::Role::item_text));
    QCOMPARE(theme.color(themes::Role::menu_item_hover_background),
             theme.color(themes::Role::item_hover_background));
    QCOMPARE(theme.color(themes::Role::menu_item_hover_text),
             theme.color(themes::Role::item_hover_text));
    QVERIFY(themes::contrastRatio(theme.color(themes::Role::menu_item_hover_text),
                                  theme.color(themes::Role::menu_item_hover_background)) >= 4.5);
    QCOMPARE(theme.color(themes::Role::splitter_handle_hover_background),
             theme.color(themes::Role::button_pressed_background));
    QCOMPARE(theme.color(themes::Role::input_background),
             theme.color(themes::Role::combo_background));
    QCOMPARE(theme.color(themes::Role::input_text), theme.color(themes::Role::combo_text));
    QCOMPARE(theme.color(themes::Role::input_outline), theme.color(themes::Role::combo_outline));
    QCOMPARE(theme.color(themes::Role::spin_box_background),
             theme.color(themes::Role::combo_background));
    QCOMPARE(theme.color(themes::Role::spin_box_text), theme.color(themes::Role::combo_text));
    QCOMPARE(theme.color(themes::Role::spin_box_outline), theme.color(themes::Role::combo_outline));
    QVERIFY(themes::contrastRatio(theme.color(themes::Role::combo_text),
                                  theme.color(themes::Role::combo_background)) >= 4.5);
}

double srgbToLinearReference(double component)
{
    return component <= 0.04045 ? component / 12.92 : std::pow((component + 0.055) / 1.055, 2.4);
}

themes::Oklab oklabReference(const QColor &color)
{
    const QColor rgb = color.toRgb();
    const double red = srgbToLinearReference(static_cast<double>(rgb.red()) / 255.0);
    const double green = srgbToLinearReference(static_cast<double>(rgb.green()) / 255.0);
    const double blue = srgbToLinearReference(static_cast<double>(rgb.blue()) / 255.0);
    const double l = std::cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue);
    const double m = std::cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue);
    const double s = std::cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue);
    return {0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s};
}

} // namespace

void ThemeLayoutTest::trackIdentityContrast()
{
    const themes::Theme vanilla = themes::vanilla();
    const QColor light = vanilla.color(themes::Role::song_view_piano_keyboard_natural_key);
    const QColor dark = vanilla.color(themes::Role::song_view_piano_keyboard_black_key);
    for (std::size_t index = 0; index < themes::trackIdentityColorCount; ++index) {
        const QColor fill = themes::trackIdentityColor(index);
        QVERIFY(fill.isValid());
        QCOMPARE(fill.alpha(), 255);
        QVERIFY(themes::contrastRatio(fill, light) >= 3.0 ||
                themes::contrastRatio(fill, dark) >= 3.0);
    }
}

void ThemeLayoutTest::colorMath_data()
{
    QTest::addColumn<QColor>("color");
    const std::array colors{QColor(0, 0, 0),     QColor(255, 255, 255), QColor(128, 128, 128),
                            QColor(255, 0, 0),   QColor(0, 255, 0),     QColor(0, 0, 255),
                            QColor(24, 88, 192), QColor(200, 150, 50),  QColor(33, 33, 33)};
    for (const QColor &color : colors)
        QTest::newRow(color.name().toLatin1().constData()) << color;
}

void ThemeLayoutTest::colorMath()
{
    QFETCH(QColor, color);
    const themes::Oklab actual = themes::oklabFromColor(color);
    const themes::Oklab expected = oklabReference(color);
    QVERIFY(std::abs(actual.lightness - expected.lightness) < kContrastEpsilon);
    QVERIFY(std::abs(actual.a - expected.a) < kContrastEpsilon);
    QVERIFY(std::abs(actual.b - expected.b) < kContrastEpsilon);
    const QColor rgb = color.toRgb();
    const double expectedLuminance =
        0.2126 * srgbToLinearReference(static_cast<double>(rgb.red()) / 255.0) +
        0.7152 * srgbToLinearReference(static_cast<double>(rgb.green()) / 255.0) +
        0.0722 * srgbToLinearReference(static_cast<double>(rgb.blue()) / 255.0);
    QVERIFY(std::abs(themes::relativeLuminance(color) - expectedLuminance) < kContrastEpsilon);
}

void ThemeLayoutTest::themeCompleteness_data()
{
    QTest::addColumn<QString>("themeName");
    const std::array names{QStringLiteral("vanilla"), QStringLiteral("dark-neutral-high"),
                           QStringLiteral("immaterial")};
    for (const QString &name : names)
        QTest::newRow(name.toLatin1().constData()) << name;
}

void ThemeLayoutTest::themeCompleteness()
{
    QFETCH(QString, themeName);
    const themes::Theme theme = themeForName(themeName);
    QVERIFY(completeTheme(theme));
    verifyMenuAndControlContracts(theme);
    QVERIFY(themes::contrastRatio(theme.color(themes::Role::disabled_text),
                                  theme.color(themes::Role::window_text)) >= 1.3);
    QCOMPARE(theme.color(themes::Role::combo_drop_down_hover_background),
             theme.color(themes::Role::button_hover_background));
    QCOMPARE(theme.color(themes::Role::focus_outline), theme.color(themes::Role::palette_outline));
    QCOMPARE(theme.color(themes::Role::tab_pane_background),
             theme.color(themes::Role::toolbar_background));
    if (themeName == QStringLiteral("vanilla"))
        QCOMPARE(theme.color(themes::Role::song_view_grid),
                 QColor::fromRgb(0x04, 0x00, 0x00, 0x3F));
    if (themeName == QStringLiteral("dark-neutral-high"))
        QCOMPARE(theme.color(themes::Role::song_view_grid),
                 QColor::fromRgb(0x03, 0x03, 0x03, 0x54));
    if (themeName == QStringLiteral("immaterial"))
        QCOMPARE(theme.color(themes::Role::song_view_grid),
                 QColor::fromRgb(0x03, 0x06, 0x06, 0x54));
}

void ThemeLayoutTest::gridContrast_data()
{
    QTest::addColumn<QString>("themeName");
    QTest::addColumn<int>("contrast");
    const std::array names{QStringLiteral("vanilla"), QStringLiteral("dark-neutral-high"),
                           QStringLiteral("immaterial")};
    for (const QString &name : names) {
        for (const int contrast : {0, 50, 100})
            QTest::newRow(
                (name + QStringLiteral("-") + QString::number(contrast)).toLatin1().constData())
                << name << contrast;
    }
}

void ThemeLayoutTest::gridContrast()
{
    QFETCH(QString, themeName);
    QFETCH(int, contrast);
    const themes::Theme theme = themeForName(themeName);
    const themes::Theme adjusted = themes::withGridLineContrast(theme, contrast);
    QVERIFY(completeTheme(adjusted));
    const QColor originalGrid = theme.color(themes::Role::song_view_grid);
    const QColor adjustedGrid = adjusted.color(themes::Role::song_view_grid);
    const QColor background = theme.color(themes::Role::song_view_piano_roll_background);
    if (contrast == themes::defaultGridLineContrast) {
        QCOMPARE(adjustedGrid, originalGrid);
        return;
    }
    const double originalContrast = themes::contrastRatio(originalGrid, background);
    const double adjustedContrast = themes::contrastRatio(adjustedGrid, background);
    if (contrast == 0)
        QVERIFY(adjustedContrast < originalContrast);
    else
        QVERIFY(adjustedContrast > originalContrast);
    if (contrast == 0)
        QVERIFY(adjustedGrid.alpha() < originalGrid.alpha());
    else
        QVERIFY(adjustedGrid.alpha() > originalGrid.alpha());
    if (contrast == 100) {
        const double originalLuminance = themes::relativeLuminance(originalGrid);
        const double backgroundLuminance = themes::relativeLuminance(background);
        const double adjustedLuminance = themes::relativeLuminance(adjustedGrid);
        if (originalLuminance <= backgroundLuminance)
            QVERIFY(adjustedLuminance < originalLuminance);
        else
            QVERIFY(adjustedLuminance > originalLuminance);
    }
}

void ThemeLayoutTest::laneAndWaveformLegibility_data()
{
    QTest::addColumn<QString>("themeName");
    QTest::addColumn<int>("role");
    QTest::addColumn<int>("surface");
    const std::array names{QStringLiteral("vanilla"), QStringLiteral("dark-neutral-high"),
                           QStringLiteral("immaterial")};
    const std::array checks{
        std::pair{themes::Role::song_view_edit_preview_outline,
                  themes::Role::song_view_piano_roll_background},
        std::pair{themes::Role::song_view_add_automation_lane_action,
                  themes::Role::song_view_piano_roll_background},
        std::pair{themes::Role::tab_selected_text,
                  themes::Role::song_view_automation_tab_active_background},
        std::pair{themes::Role::sample_waveform_ink, themes::Role::item_background},
        std::pair{themes::Role::sample_crop_handle, themes::Role::item_background},
        std::pair{themes::Role::sample_loop_handle, themes::Role::item_background},
        std::pair{themes::Role::sample_loop_handle, themes::Role::item_alternate_background},
        std::pair{themes::Role::sample_seam_end_ink, themes::Role::item_alternate_background},
    };
    for (const QString &name : names) {
        for (const auto &[role, surface] : checks) {
            const auto row = name + QStringLiteral("-") + QString::number(static_cast<int>(role)) +
                             QStringLiteral("-") + QString::number(static_cast<int>(surface));
            QTest::newRow(row.toLatin1().constData())
                << name << static_cast<int>(role) << static_cast<int>(surface);
        }
    }
}

void ThemeLayoutTest::laneAndWaveformLegibility()
{
    QFETCH(QString, themeName);
    QFETCH(int, role);
    QFETCH(int, surface);
    const themes::Theme theme = themeForName(themeName);
    QVERIFY(themes::contrastRatio(theme.color(static_cast<themes::Role>(role)),
                                  theme.color(static_cast<themes::Role>(surface))) >= 3.0);
}
