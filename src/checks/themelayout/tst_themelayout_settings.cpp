// Deferred UI reference cases. This file is intentionally absent from the
// rewrite check target until the corresponding widgets return.

#include "ui/layout.h"
#include "ui/polyphonypanel.h"
#include "ui/theme/color_math.h"
#include "ui/theme/themecontroller.h"
#include "ui/theme/themedialog.h"
#include "ui/theme/themeresolver.h"
#include "ui/theme/themeruntime.h"
#include "ui/theme/trackidentitycolors.h"

#include <QApplication>
#include <QHeaderView>
#include <QImage>
#include <QList>
#include <QPaintEvent>
#include <QPointer>
#include <QPushButton>
#include <QRadioButton>
#include <QSettings>
#include <QSlider>
#include <QTabBar>
#include <QTableWidget>
#include <QTemporaryDir>
#include <QWidget>
#include <QWizard>
#include <QtTest>

#include <cstddef>
#include <memory>

namespace deferred_theme_layout {
namespace {

struct DialogControls {
    QRadioButton *vanilla = nullptr;
    QRadioButton *darkNeutralHigh = nullptr;
    QRadioButton *immaterial = nullptr;
    QSlider *gridLineContrast = nullptr;
    QPushButton *apply = nullptr;
    QPushButton *close = nullptr;
};

DialogControls dialogControls(themes::ThemeDialog &dialog)
{
    return {dialog.findChild<QRadioButton *>(QStringLiteral("vanillaModeButton")),
            dialog.findChild<QRadioButton *>(QStringLiteral("darkNeutralHighModeButton")),
            dialog.findChild<QRadioButton *>(QStringLiteral("immaterialModeButton")),
            dialog.findChild<QSlider *>(QStringLiteral("gridLineContrastSlider")),
            dialog.findChild<QPushButton *>(QStringLiteral("themeApplyButton")),
            dialog.findChild<QPushButton *>(QStringLiteral("themeCloseButton"))};
}

bool controlsPresent(const DialogControls &controls)
{
    return controls.vanilla && controls.darkNeutralHigh && controls.immaterial &&
           controls.gridLineContrast && controls.apply && controls.close;
}

class StyleChangeCounter final : public QObject
{
  public:
    int count = 0;

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override
    {
        Q_UNUSED(watched);
        if (event && event->type() == QEvent::StyleChange)
            ++count;
        return false;
    }
};

class ThemeRefreshProbe final : public QWidget
{
  public:
    int themeChangeCount = 0;
    int paintCount = 0;
    QColor gridColor;

  protected:
    bool event(QEvent *event) override
    {
        if (event && event->type() == QEvent::ThemeChange) {
            ++themeChangeCount;
            gridColor = themes::color(themes::Role::song_view_grid);
        }
        return QWidget::event(event);
    }

    void paintEvent(QPaintEvent *event) override
    {
        Q_UNUSED(event);
        ++paintCount;
    }
};

bool containsColor(const QImage &image, const QRect &rect, const QColor &color)
{
    for (int y = rect.top(); y <= rect.bottom(); ++y) {
        for (int x = rect.left(); x <= rect.right(); ++x) {
            if (image.pixelColor(x, y) == color)
                return true;
        }
    }
    return false;
}

} // namespace

class DeferredThemeLayoutTest final
{
  public:
    void trackIdentityContrast();
    void startupChromePins();
    void dialogCommitAndRevert();
    void itemViewBrushes();
    void themeDialogGeometry();
    void gridRefreshTargets();
    void polyphonyLayoutScales();

  private:
    QApplication *m_application = qobject_cast<QApplication *>(QApplication::instance());
};

void DeferredThemeLayoutTest::trackIdentityContrast()
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

void DeferredThemeLayoutTest::startupChromePins()
{
    QVERIFY(
        m_application->styleSheet().contains(QStringLiteral("QHeaderView::section{border:0;}")));
    QWizard wizard;
    wizard.ensurePolished();
    QCOMPARE(wizard.wizardStyle(), QWizard::ClassicStyle);

    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    QSettings settings(directory.filePath(QStringLiteral("settings.ini")), QSettings::IniFormat);
    themes::ThemeController controller(*m_application, settings);
    controller.restore();
    QVERIFY(
        m_application->styleSheet().contains(QStringLiteral("QHeaderView::section{border:0;}")));
}

void DeferredThemeLayoutTest::dialogCommitAndRevert()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    QSettings settings(directory.filePath(QStringLiteral("settings.ini")), QSettings::IniFormat);
    themes::ThemeController controller(*m_application, settings);
    controller.restore();
    themes::ThemeDialog dialog(controller);
    const DialogControls controls = dialogControls(dialog);
    QVERIFY(controlsPresent(controls));
    dialog.show();
    QTRY_VERIFY(dialog.isVisible());

    controls.darkNeutralHigh->click();
    controls.gridLineContrast->setValue(80);
    controls.apply->click();

    const themes::ThemeSelection &committed = controller.committedSelection();
    QCOMPARE(committed.mode, themes::ThemeMode::DarkNeutralHigh);
    QCOMPARE(committed.gridLineContrast, 80);

    controls.darkNeutralHigh->click();
    QCOMPARE(themes::color(themes::Role::toolbar_background),
             themes::darkNeutralHigh().color(themes::Role::toolbar_background));
    controls.immaterial->click();
    QCOMPARE(themes::color(themes::Role::toolbar_background),
             themes::immaterial().color(themes::Role::toolbar_background));
    controls.gridLineContrast->setValue(10);
    controls.close->click();

    const auto committedTheme = themes::withGridLineContrast(themes::darkNeutralHigh(), 80);
    QCOMPARE(themes::color(themes::Role::link_text), committedTheme.color(themes::Role::link_text));
    QCOMPARE(themes::color(themes::Role::song_view_grid),
             committedTheme.color(themes::Role::song_view_grid));
}

void DeferredThemeLayoutTest::itemViewBrushes()
{
    QTableWidget table(2, 1);
    table.horizontalHeader()->hide();
    table.verticalHeader()->hide();
    table.setShowGrid(false);
    table.setAlternatingRowColors(true);
    table.setItem(0, 0, new QTableWidgetItem);
    table.setItem(1, 0, new QTableWidgetItem);
    table.resize(80, 80);
    table.setFocusPolicy(Qt::NoFocus);
    table.show();
    table.ensurePolished();
    QTRY_VERIFY(table.isVisible());

    const auto cellColor = [&table](int row) {
        const QRect rect = table.visualItemRect(table.item(row, 0));
        const QImage image = table.viewport()->grab().toImage();
        return image.pixelColor(rect.center());
    };
    QCOMPARE(cellColor(0), themes::color(themes::Role::item_background));
    QCOMPARE(cellColor(1), themes::color(themes::Role::item_alternate_background));

    const QColor flash(255, 0, 0);
    QVERIFY(cellColor(0) != flash);
    table.item(0, 0)->setBackground(flash);
    QCOMPARE(cellColor(0), flash);

    const QColor ink(255, 0, 255);
    table.item(1, 0)->setText(QStringLiteral("XXXX"));
    table.item(1, 0)->setForeground(ink);
    auto inkFont = table.font();
    inkFont.setPixelSize(24);
    inkFont.setStyleStrategy(QFont::NoAntialias);
    table.item(1, 0)->setFont(inkFont);
    table.viewport()->update();
    QTRY_VERIFY(containsColor(table.viewport()->grab().toImage(), table.viewport()->rect(), ink));
}

void DeferredThemeLayoutTest::themeDialogGeometry()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    QSettings settings(directory.filePath(QStringLiteral("settings.ini")), QSettings::IniFormat);
    themes::ThemeController controller(*m_application, settings);
    controller.restore();
    themes::ThemeDialog dialog(controller);
    dialog.show();
    dialog.ensurePolished();
    QTRY_VERIFY(dialog.isVisible());

    const auto modeButtons = dialog.findChildren<QRadioButton *>();
    QCOMPARE(modeButtons.size(), 3);
    const QSize initialSize = dialog.size();
    QList<QRect> initialGeometry;
    initialGeometry.reserve(modeButtons.size());
    for (const QRadioButton *button : modeButtons)
        initialGeometry.append(QRect(button->mapTo(&dialog, QPoint()), button->size()));

    QRadioButton *darkNeutralHigh =
        dialog.findChild<QRadioButton *>(QStringLiteral("darkNeutralHighModeButton"));
    QVERIFY(darkNeutralHigh);
    darkNeutralHigh->click();
    QTRY_COMPARE(dialog.size(), initialSize);
    for (qsizetype index = 0; index < modeButtons.size(); ++index)
        QTRY_COMPARE(
            QRect(modeButtons[index]->mapTo(&dialog, QPoint()), modeButtons[index]->size()),
            initialGeometry.at(index));
}

void DeferredThemeLayoutTest::gridRefreshTargets()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    QSettings settings(directory.filePath(QStringLiteral("settings.ini")), QSettings::IniFormat);
    themes::ThemeController controller(*m_application, settings);
    controller.restore();
    themes::ThemeDialog dialog(controller);
    QSlider *gridLineContrast =
        dialog.findChild<QSlider *>(QStringLiteral("gridLineContrastSlider"));
    QVERIFY(gridLineContrast);
    dialog.show();
    QTRY_VERIFY(dialog.isVisible());

    QTabBar tabBar;
    tabBar.addTab(QStringLiteral("Open Song"));
    tabBar.show();
    tabBar.ensurePolished();
    QTRY_VERIFY(tabBar.isVisible());
    ThemeRefreshProbe gridPaintTarget;
    gridPaintTarget.resize(10, 10);
    gridPaintTarget.show();
    QTRY_VERIFY(gridPaintTarget.isVisible());
    themes::registerGridLineRefreshTarget(gridPaintTarget);
    themes::registerGridLineRefreshTarget(gridPaintTarget);
    gridPaintTarget.paintCount = 0;
    gridPaintTarget.themeChangeCount = 0;
    StyleChangeCounter tabStyleChanges;
    tabBar.installEventFilter(&tabStyleChanges);
    const QImage tabBefore = tabBar.grab().toImage();
    QVERIFY(!tabBefore.isNull());
    const QPalette paletteBefore = m_application->palette();
    const QString styleSheetBefore = m_application->styleSheet();
    const QColor defaultGrid = themes::color(themes::Role::song_view_grid);
    const QColor background = themes::color(themes::Role::song_view_piano_roll_background);

    gridLineContrast->setValue(100);
    const QColor strengthened = themes::color(themes::Role::song_view_grid);
    QCOMPARE(gridPaintTarget.themeChangeCount, 1);
    QCOMPARE(gridPaintTarget.gridColor, strengthened);
    gridLineContrast->setValue(0);
    const QColor softened = themes::color(themes::Role::song_view_grid);
    QCOMPARE(gridPaintTarget.themeChangeCount, 2);
    QCOMPARE(gridPaintTarget.gridColor, softened);
    QVERIFY(themes::contrastRatio(strengthened, background) >
            themes::contrastRatio(defaultGrid, background));
    QVERIFY(themes::contrastRatio(softened, background) <
            themes::contrastRatio(defaultGrid, background));

    auto destroyedTarget = std::make_unique<ThemeRefreshProbe>();
    QPointer<ThemeRefreshProbe> destroyedGuard(destroyedTarget.get());
    themes::registerGridLineRefreshTarget(*destroyedTarget);
    destroyedTarget.reset();
    QVERIFY(destroyedGuard.isNull());
    const int refreshCountBeforeCleanup = gridPaintTarget.themeChangeCount;
    gridLineContrast->setValue(10);
    QCOMPARE(gridPaintTarget.themeChangeCount, refreshCountBeforeCleanup + 1);
    gridLineContrast->setValue(themes::defaultGridLineContrast);
    QCoreApplication::processEvents();
    QVERIFY(tabStyleChanges.count == 0);
    QVERIFY(tabBar.grab().toImage() == tabBefore);
    QCOMPARE(m_application->palette(), paletteBefore);
    QCOMPARE(m_application->styleSheet(), styleSheetBefore);
    QVERIFY(gridPaintTarget.paintCount > 0);
}

void DeferredThemeLayoutTest::polyphonyLayoutScales()
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

} // namespace deferred_theme_layout
