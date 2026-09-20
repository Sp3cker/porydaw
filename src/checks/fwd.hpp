#pragma once

#include <QString>
#include <QStringList>

class QApplication;

int runAudioCheck(const QStringList &qtArguments);
int runAudioBackendCheck(const QStringList &qtArguments);
int runClickCheck(const QStringList &qtArguments);
int runResonanceCheck(const QStringList &qtArguments);
int runResonanceTimingCheck(const QStringList &qtArguments);
int runScaleCheck(const QStringList &qtArguments);
int runTrackActivityCheck(const QStringList &qtArguments);
int runTransportCheck(const QStringList &qtArguments);
int runMidiEngineCheck(const QStringList &qtArguments);
int runVgBankCheck(const QString &projectRoot, const QString &songLabel,
                   const QStringList &qtArguments);

int runThemeLayoutThemeCheck(QApplication &application, const QStringList &qtArguments);
int runThemeLayoutFontCheck(QApplication &application, const QStringList &qtArguments);
int runThemeLayoutDarkBaseCheck(QApplication &application, const QStringList &qtArguments);
int runThemeLayoutScaleCheck(QApplication &application, int baseFontPx,
                             const QStringList &qtArguments);
#ifdef __APPLE__
int runSwiftCoreCheck(const QString &fixtureRoot, const QStringList &qtArguments);
#endif

int runSwiftGridBoundaryCheck(const QString &mode, const QString &projectRoot,
                              const QString &songLabel, const QStringList &qtArguments);

int runExportCheck(const QString &projectRoot, const QString &songLabel,
                   const QStringList &qtArguments);
