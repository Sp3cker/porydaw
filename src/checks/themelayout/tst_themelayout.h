#pragma once

#include <QFont>
#include <QPalette>
#include <QString>
#include <QStringList>

#include <QObject>

class QApplication;

class ThemeLayoutTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(ThemeLayoutTest)

  public:
    ThemeLayoutTest() = default;

  private slots:
    void init();
    void cleanup();
    void colorPairValidity();
    void colorMath_data();
    void colorMath();
    void themeCompleteness_data();
    void themeCompleteness();
    void gridContrast_data();
    void gridContrast();
    void laneAndWaveformLegibility_data();
    void laneAndWaveformLegibility();
    void startupChromePins();
    void settingsRepair();
    void themePersistence_data();
    void themePersistence();
    void dialogCommitAndRevert();
    void comboArrowAndPopup();
    void itemViewBrushes();
    void themeDialogGeometry();
    void gridRefreshTargets();

  private:
    QApplication *m_application = nullptr;
    QFont m_font;
    QPalette m_palette;
    QString m_styleSheet;
};

class ThemeLayoutFontTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(ThemeLayoutFontTest)

  public:
    explicit ThemeLayoutFontTest(int expectedBaseFontPx);

  private slots:
    void init();
    void cleanup();
    void typographyAndLayoutInitialization();
    void typographyFaceContracts();
    void fittedTypographyContracts();
    void themeApplyRestoresExternallyResetFont();

  private:
    QApplication *m_application = nullptr;
    QFont m_font;
    QPalette m_palette;
    QString m_styleSheet;
    int m_expectedBaseFontPx;
};

class ThemeLayoutScaleTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(ThemeLayoutScaleTest)

  public:
    explicit ThemeLayoutScaleTest(int baseFontPx);

  private slots:
    void layoutScale_data();
    void initializationIsProcessScoped();

    void layoutScale();

  private:
    int m_baseFontPx;
};

class ThemeLayoutDarkBaseTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(ThemeLayoutDarkBaseTest)

  public:
    ThemeLayoutDarkBaseTest() = default;

  private slots:
    void init();
    void cleanup();
    void darkBaselineMasksPoisonedPlatformPalette();

  private:
    QApplication *m_application = nullptr;
    QFont m_font;
    QPalette m_palette;
    QString m_styleSheet;
};

int runThemeLayoutThemeCheck(QApplication &application, const QStringList &qtArguments);
int runThemeLayoutFontCheck(QApplication &application, const QStringList &qtArguments);
int runThemeLayoutDarkBaseCheck(QApplication &application, const QStringList &qtArguments);
int runThemeLayoutScaleCheck(QApplication &application, int baseFontPx,
                             const QStringList &qtArguments);
