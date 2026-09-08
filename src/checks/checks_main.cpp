#include <cstdio>

#include <QApplication>
#include <QEvent>
#include <QScreen>
#include <QWindow>

#include "checkregistry.hpp"
#include "ui/applicationstartup.h"

namespace {

class NativeCheckWindowPlacement final : public QObject
{
  protected:
    bool eventFilter(QObject *object, QEvent *event) override
    {
        if (event->type() != QEvent::Show && event->type() != QEvent::Resize)
            return false;
        auto *window = qobject_cast<QWindow *>(object);
        if (!window || window->parent() || window->transientParent() ||
            (window->type() != Qt::Window && window->type() != Qt::Dialog) ||
            (event->type() == QEvent::Resize && !window->isVisible()))
            return false;
        const QScreen *screen = window->screen();
        if (!screen)
            return false;

        // Keep fixture sizes intact and transient menus attached to their owner.
        // Anchor native hosts at the bottom-right of the usable screen instead
        // of letting the platform cascade fresh windows under the user's cursor.
        const QRect available = screen->availableGeometry();
        const QMargins frame = window->frameMargins();
        const QSize size =
            window->size() + QSize(frame.left() + frame.right(), frame.top() + frame.bottom());
        window->setFramePosition({qMax(available.left(), available.right() + 1 - size.width()),
                                  qMax(available.top(), available.bottom() + 1 - size.height())});
        return false;
    }
};

} // namespace

int main(int argc, char *argv[])
{
    if (!qEnvironmentVariableIsSet("PORYDAW_AUDIO_BACKEND"))
        qputenv("PORYDAW_AUDIO_BACKEND", "null");
    auto application = QApplication{argc, argv};
    ui::installOffscreenSystemFont(application);

    const auto arguments = application.arguments();
    if (checks::writeManifest(arguments))
        return 0;
    NativeCheckWindowPlacement windowPlacement;
    if (QGuiApplication::platformName() != QLatin1String("offscreen"))
        application.installEventFilter(&windowPlacement);
    const auto result = checks::runRequested(application, arguments);
    if (result)
        return *result;
    std::fprintf(stderr, "porydaw_checks: no check command supplied\n");
    return 2;
}
