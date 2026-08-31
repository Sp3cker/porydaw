#include "applicationstartup.h"

#include "layout.h"
#include "theme/themeresolver.h"
#include "theme/themeruntime.h"
#include "typography.h"

#include <QApplication>
#include <QEventLoop>
#include <QFont>
#include <QGuiApplication>
#include <QIcon>
#include <QStyleHints>
#include <QWidget>

#ifdef Q_OS_WIN
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <dwmapi.h>
#include <windows.h>
#endif

namespace ui {

void installOffscreenSystemFont(QApplication &application)
{
#if defined(Q_OS_MACOS)
    // QOffscreen's generic family is absent from CoreText's family list. Do
    // not resolve application.font(): resolving its "Sans Serif" family is
    // exactly the expensive alias lookup this avoids.
    if (QGuiApplication::platformName() == QStringLiteral("offscreen")) {
        auto font = QFont{};
        font.setFamily(QStringLiteral(".AppleSystemUIFont"));
        application.setFont(font);
    }
#else
    Q_UNUSED(application);
#endif
}

bool initializePorydawApplication(QApplication &application)
{
#if defined(Q_OS_WIN) && QT_VERSION >= QT_VERSION_CHECK(6, 8, 0)
    application.styleHints()->setColorScheme(Qt::ColorScheme::Light);
#endif
    QApplication::setStyle(QStringLiteral("fusion"));
    QApplication::setApplicationName(QStringLiteral("porydaw"));
    QApplication::setApplicationVersion(QStringLiteral(PORYDAW_VERSION));
    QApplication::setOrganizationName(QStringLiteral("huderlem"));
    auto appIcon = QIcon{};
    for (const auto size : {16, 32, 48, 128, 256})
        appIcon.addFile(QStringLiteral(":/icons/porydaw-%1.png").arg(size));
    QApplication::setWindowIcon(appIcon);
    QGuiApplication::setDesktopFileName(QStringLiteral("porydaw"));
    return initializeApplication(application);
}

// Kept separate so startup ordering can be tested.
bool initializeApplication(QApplication &application)
{
    // Ordering is load-bearing: typography first captures the platform's
    // runtime font size before installing the bundled fonts. Using that size as
    // Layout's base font pixel size keeps controls and spacing proportional to
    // text across platform DPI and system text-scale settings. Layout installs
    // geometry and popup behavior, then Theme captures the resulting
    // application presentation baseline.
    if (!typography::installBundledFonts(application))
        return false;
    const auto baseFontPx = typography::baseFontPx();
    if (!baseFontPx || !layout::initialize(application, *baseFontPx))
        return false;
    themes::initialize(application);
    // Every code path that paints — including the --*check harnesses, which
    // never construct MainWindow or its ThemeController — needs a complete
    // theme behind themes::color(). Vanilla here is the baseline; the main
    // window's ThemeController::restore() replaces it with the stored choice.
    themes::apply(application, themes::vanilla());
    return true;
}

void showPreparedWindow(QWidget &window)
{
#ifdef Q_OS_WIN
    // Qt's Windows backend consumes WM_ERASEBKGND without painting it. Keep
    // DWM from presenting that uninitialized native surface while QWidget and
    // QQuickWidget prepare the first real backing-store frame.
    constexpr DWORD kDwmwaCloak = 13;
    const HWND hwnd = reinterpret_cast<HWND>(window.winId());
    const BOOL cloak = TRUE;
    const bool cloaked = SUCCEEDED(DwmSetWindowAttribute(hwnd, kDwmwaCloak, &cloak, sizeof(cloak)));
#endif

    window.show();
    QApplication::processEvents(QEventLoop::ExcludeUserInputEvents);

#ifdef Q_OS_WIN
    if (cloaked) {
        const BOOL uncloak = FALSE;
        if (SUCCEEDED(DwmSetWindowAttribute(hwnd, kDwmwaCloak, &uncloak, sizeof(uncloak))))
            DwmFlush();
    }
#endif
}

} // namespace ui
