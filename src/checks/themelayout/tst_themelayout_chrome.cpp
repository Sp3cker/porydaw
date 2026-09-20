#include "checks/themelayout/tst_themelayout.h"

#include "ui/theme/themeresolver.h"
#include "ui/theme/themeruntime.h"

#include <QAbstractItemView>
#include <QApplication>
#include <QCheckBox>
#include <QComboBox>
#include <QGroupBox>
#include <QImage>
#include <QLabel>
#include <QLineEdit>
#include <QPaintEvent>
#include <QPainter>
#include <QProgressBar>

#include <QPushButton>
#include <QRadioButton>
#include <QScrollBar>
#include <QStyle>
#include <QStyleOptionComboBox>
#include <QTabBar>
#include <QVBoxLayout>
#include <QtTest>

#include <cmath>

namespace {

constexpr QColor kDarkBaselinePoison(40, 0, 40);
constexpr int kDarkBaselinePoisonRgbManhattanTolerance = 24;

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
