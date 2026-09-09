#include "checks/themelayout/tst_themelayout.h"

#include "ui/typography.h"

#include "ui/applicationstartup.h"
#include "ui/layout.h"
#include "ui/theme/themeresolver.h"
#include "ui/theme/themeruntime.h"

#include <QApplication>
#include <QFontInfo>

#include <QPalette>
#include <QtTest>

namespace {

QStringList testArguments(const QString &suiteName, const QStringList &qtArguments)
{
    QStringList arguments{suiteName};
    arguments.append(qtArguments);
    return arguments;
}

void poisonPalette(QApplication &application)
{
    constexpr QColor poison(40, 0, 40);
    application.setStyle(QStringLiteral("fusion"));
    auto palette = application.palette();
    for (int group = 0; group < QPalette::NColorGroups; ++group) {
        for (int role = 0; role < QPalette::NColorRoles; ++role) {
            palette.setColor(static_cast<QPalette::ColorGroup>(group),
                             static_cast<QPalette::ColorRole>(role), poison);
        }
    }
    application.setPalette(palette);
}

} // namespace

void ThemeLayoutTest::init()
{
    m_application = qobject_cast<QApplication *>(QApplication::instance());
    QVERIFY(m_application);
    themes::apply(*m_application, themes::vanilla());
    m_font = m_application->font();
    m_palette = m_application->palette();
    m_styleSheet = m_application->styleSheet();
}

void ThemeLayoutTest::cleanup()
{
    if (!m_application)
        return;
    themes::apply(*m_application, themes::vanilla());
    m_application->setFont(m_font);
    m_application->setPalette(m_palette);
    m_application->setStyleSheet(m_styleSheet);
}

ThemeLayoutFontTest::ThemeLayoutFontTest(int expectedBaseFontPx)
    : m_expectedBaseFontPx(expectedBaseFontPx)
{}

void ThemeLayoutFontTest::init()
{
    m_application = qobject_cast<QApplication *>(QApplication::instance());
    QVERIFY(m_application);
    themes::apply(*m_application, themes::vanilla());
    m_font = m_application->font();
    m_palette = m_application->palette();
    m_styleSheet = m_application->styleSheet();
}

void ThemeLayoutFontTest::cleanup()
{
    if (!m_application)
        return;
    themes::apply(*m_application, themes::vanilla());
    m_application->setFont(m_font);
    m_application->setPalette(m_palette);
    m_application->setStyleSheet(m_styleSheet);
}

ThemeLayoutScaleTest::ThemeLayoutScaleTest(int baseFontPx) : m_baseFontPx(baseFontPx) {}

void ThemeLayoutDarkBaseTest::init()
{
    m_application = qobject_cast<QApplication *>(QApplication::instance());
    QVERIFY(m_application);
    m_font = m_application->font();
    m_palette = m_application->palette();
    m_styleSheet = m_application->styleSheet();
}

void ThemeLayoutDarkBaseTest::cleanup()
{
    if (!m_application)
        return;
    m_application->setFont(m_font);
    m_application->setPalette(m_palette);
    m_application->setStyleSheet(m_styleSheet);
}

int runThemeLayoutThemeCheck(QApplication &application, const QStringList &qtArguments)
{
    if (!ui::initializeApplication(application))
        return 1;
    ThemeLayoutTest test;
    return QTest::qExec(&test, testArguments(QStringLiteral("themelayout"), qtArguments));
}

int runThemeLayoutFontCheck(QApplication &application, const QStringList &qtArguments)
{
    const int expectedBaseFontPx = QFontInfo(application.font()).pixelSize();
    if (!ui::initializeApplication(application))
        return 1;
    ThemeLayoutFontTest test(expectedBaseFontPx);
    return QTest::qExec(&test, testArguments(QStringLiteral("themelayout-font"), qtArguments));
}

int runThemeLayoutDarkBaseCheck(QApplication &application, const QStringList &qtArguments)
{
    poisonPalette(application);
    if (!ui::initializeApplication(application))
        return 1;
    ThemeLayoutDarkBaseTest test;
    return QTest::qExec(&test, testArguments(QStringLiteral("themelayout-darkbase"), qtArguments));
}

int runThemeLayoutScaleCheck(QApplication &application, int baseFontPx,
                             const QStringList &qtArguments)
{
    if (baseFontPx <= 0)
        return 1;
    auto font = application.font();
    font.setPixelSize(baseFontPx);
    application.setFont(font);
    if (!ui::initializeApplication(application))
        return 1;
    ThemeLayoutScaleTest test(baseFontPx);
    return QTest::qExec(&test, testArguments(QStringLiteral("themelayout-scale"), qtArguments));
}
