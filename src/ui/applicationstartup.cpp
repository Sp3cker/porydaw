#include "applicationstartup.h"

#include "layout.h"
#include "theme/themeresolver.h"
#include "theme/themeruntime.h"
#include "typography.h"

#include <QApplication>
#include <QEventLoop>
#include <QWidget>

namespace ui {
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

void showCoveredWhileRestoring(QWidget &window,
                               const std::function<void()> &restore)
{
    QWidget cover(&window);
    cover.setAutoFillBackground(true);
    cover.setPalette(window.palette());
    cover.show();
    window.show();
    // Sized only after show(): a restored maximized state grows the window
    // during show(), and the cover must span the final geometry.
    cover.setGeometry(window.rect());
    cover.raise();
    // One event-loop pass paints the cover now, before restore blocks; user
    // input stays queued so nothing acts on the half-restored session.
    QApplication::processEvents(QEventLoop::ExcludeUserInputEvents);
    restore();
    // Falling out of scope removes the cover; the restored UI paints in
    // app.exec()'s first frame.
}

} // namespace ui
