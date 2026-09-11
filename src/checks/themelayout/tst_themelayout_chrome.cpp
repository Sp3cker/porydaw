#include "checks/themelayout/tst_themelayout.h"

#include "ui/theme/color_math.h"

#include "ui/theme/themecontroller.h"
#include "ui/theme/themedialog.h"
#include "ui/theme/themeresolver.h"
#include "ui/theme/themeruntime.h"

#include <QApplication>
#include <QCheckBox>
#include <QComboBox>
#include <QGroupBox>
#include <QHeaderView>
#include <QImage>
#include <QLabel>
#include <QLineEdit>
#include <QList>
#include <QPaintEvent>
#include <QPainter>
#include <QPointer>
#include <QProgressBar>

#include <QPushButton>
#include <QRadioButton>
#include <QScrollBar>
#include <QSettings>
#include <QSlider>
#include <QStyle>
#include <QStyleOptionComboBox>
#include <QTabBar>
#include <QTableWidget>
#include <QTemporaryDir>
#include <QVBoxLayout>
#include <QtTest>

#include <cmath>
#include <memory>

namespace {

constexpr QColor kDarkBaselinePoison(40, 0, 40);
constexpr int kDarkBaselinePoisonRgbManhattanTolerance = 24;

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

class PoisonSwatch final : public QWidget
{
  protected:
    void paintEvent(QPaintEvent *event) override
    {
        Q_UNUSED(event);
        QPainter painter(this);
        painter.fillRect(rect(), kDarkBaselinePoison);
    }
};

bool matchesDarkBaselinePoison(const QColor &color)
{
    const int distance = std::abs(color.red() - kDarkBaselinePoison.red()) +
                         std::abs(color.green() - kDarkBaselinePoison.green()) +
                         std::abs(color.blue() - kDarkBaselinePoison.blue());
    return distance <= kDarkBaselinePoisonRgbManhattanTolerance;
}

int poisonPixelCount(const QImage &image)
{
    int count = 0;
    for (int y = 0; y < image.height(); ++y) {
        for (int x = 0; x < image.width(); ++x) {
            if (matchesDarkBaselinePoison(image.pixelColor(x, y)))
                ++count;
        }
    }
    return count;
}

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

void ThemeLayoutTest::comboArrowAndPopup()
{
    QComboBox combo;
    combo.addItem(QStringLiteral("Arrow"));
    combo.resize(120, 30);
    combo.show();
    combo.ensurePolished();
    QTRY_VERIFY(combo.isVisible());

    QStyleOptionComboBox option;
    option.initFrom(&combo);
    const QRect arrowRect = combo.style()->subControlRect(QStyle::CC_ComboBox, &option,
                                                          QStyle::SC_ComboBoxArrow, &combo);
    QVERIFY(!arrowRect.isEmpty());
    const QImage restingImage = combo.grab().toImage();
    QVERIFY(!restingImage.isNull());
    const QColor arrowColor = themes::color(themes::Role::combo_text);
    const QColor hoverColor = themes::color(themes::Role::combo_drop_down_hover_background);
    QVERIFY(containsColor(restingImage, arrowRect, arrowColor));
    QVERIFY(!containsColor(restingImage, arrowRect, hoverColor));

    const QPoint hoverPosition = arrowRect.center();
    QStyleOptionComboBox hoverOption;
    hoverOption.initFrom(&combo);
    hoverOption.state |= QStyle::State_MouseOver;
    const QRect hoverArrowRect = combo.style()->subControlRect(QStyle::CC_ComboBox, &hoverOption,
                                                               QStyle::SC_ComboBoxArrow, &combo);
    QVERIFY(hoverArrowRect.contains(hoverPosition));
    hoverOption.editable = combo.isEditable();
    hoverOption.frame = combo.hasFrame();
    hoverOption.currentIcon = combo.itemIcon(combo.currentIndex());
    hoverOption.currentText = combo.currentText();
    hoverOption.iconSize = combo.iconSize();
    hoverOption.subControls = QStyle::SC_All;
    hoverOption.activeSubControls = QStyle::SC_ComboBoxArrow;

    // Exercise the same stylesheet-backed drawComplexControl path used by the
    // production ComboBox painter. This verifies its hover raster, not the
    // production painter's native QCursor hit test.
    QImage hoveredImage(combo.size(), QImage::Format_ARGB32_Premultiplied);
    hoveredImage.fill(Qt::transparent);
    {
        QPainter painter(&hoveredImage);
        combo.style()->drawComplexControl(QStyle::CC_ComboBox, &hoverOption, &painter, &combo);
    }
    QVERIFY(containsColor(hoveredImage, hoverArrowRect, hoverColor));

    combo.showPopup();
    QWidget *popup = combo.view()->window();
    QVERIFY(popup != combo.window());
    QTRY_VERIFY(popup->isVisible());
    const QImage popupImage = popup->grab().toImage();
    QVERIFY(!popupImage.isNull());
    QCOMPARE(popupImage.pixelColor(0, 0), themes::color(themes::Role::menu_outline));
    combo.hidePopup();
}

void ThemeLayoutTest::itemViewBrushes()
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

void ThemeLayoutTest::themeDialogGeometry()
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

void ThemeLayoutTest::gridRefreshTargets()
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

void ThemeLayoutDarkBaseTest::darkBaselineMasksPoisonedPlatformPalette()
{
    const themes::Theme vanilla = themes::vanilla();
    QCOMPARE(m_application->palette().color(QPalette::Active, QPalette::Window),
             vanilla.color(themes::Role::window_background));
    QCOMPARE(m_application->palette().color(QPalette::Active, QPalette::WindowText),
             vanilla.color(themes::Role::window_text));
    QCOMPARE(m_application->palette().color(QPalette::Active, QPalette::Base),
             vanilla.color(themes::Role::item_background));

    PoisonSwatch calibration;
    calibration.resize(16, 16);
    calibration.show();
    QTRY_VERIFY(calibration.isVisible());
    const QImage calibrationImage = calibration.grab().toImage();
    QVERIFY(!calibrationImage.isNull());
    QVERIFY(poisonPixelCount(calibrationImage) > 0);

    QWidget zoo;
    auto *layout = new QVBoxLayout(&zoo);
    layout->addWidget(new QLabel(QStringLiteral("Label"), &zoo));
    layout->addWidget(new QPushButton(QStringLiteral("Button"), &zoo));
    auto *lineEdit = new QLineEdit(QStringLiteral("edit"), &zoo);
    layout->addWidget(lineEdit);
    auto *checkBox = new QCheckBox(QStringLiteral("Check"), &zoo);
    checkBox->setChecked(true);
    layout->addWidget(checkBox);
    auto *radio = new QRadioButton(QStringLiteral("Radio"), &zoo);
    radio->setChecked(true);
    layout->addWidget(radio);
    auto *combo = new QComboBox(&zoo);
    combo->addItem(QStringLiteral("Combo"));
    layout->addWidget(combo);
    auto *progress = new QProgressBar(&zoo);
    progress->setRange(0, 100);
    progress->setValue(60);
    layout->addWidget(progress);
    auto *slider = new QSlider(Qt::Horizontal, &zoo);
    slider->setValue(40);
    layout->addWidget(slider);
    auto *tabs = new QTabBar(&zoo);
    tabs->addTab(QStringLiteral("One"));
    tabs->addTab(QStringLiteral("Two"));
    layout->addWidget(tabs);
    auto *group = new QGroupBox(QStringLiteral("Group"), &zoo);
    auto *groupLayout = new QVBoxLayout(group);
    groupLayout->addWidget(new QLabel(QStringLiteral("inside"), group));
    layout->addWidget(group);
    auto *scroll = new QScrollBar(Qt::Horizontal, &zoo);
    scroll->setRange(0, 100);
    layout->addWidget(scroll);
    zoo.show();
    zoo.ensurePolished();
    QTRY_VERIFY(zoo.isVisible());
    const QImage zooImage = zoo.grab().toImage();
    QVERIFY(!zooImage.isNull());
    QVERIFY(zooImage.width() > 0 && zooImage.height() > 0);
    QCOMPARE(poisonPixelCount(zooImage), 0);
}
