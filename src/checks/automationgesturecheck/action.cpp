#include "domains.h"

#include <QAction>
#include <QApplication>
#include <QCoreApplication>
#include <QCursor>
#include <QEvent>
#include <QKeyEvent>
#include <QKeySequence>
#include <QLineEdit>
#include <QPixmap>

#include "rig.h"
#include "ui/editordrawer/automationarea.h"
#include "ui/songview.h"

void checkAutomationPencilAction(AutomationGestureCheckRig &rig,
                                 const AutomationGestureCheck &check)
{
    QAction *const pencilModeAction = rig.pencilModeAction();
    check(pencilModeAction && pencilModeAction->shortcut() == QKeySequence(Qt::Key_B),
          QStringLiteral("automation page did not bind Pencil Mode to B"));
    if (!pencilModeAction)
        return;
    const bool pencilActionInitiallyDisabled = !pencilModeAction->isChecked();
    pencilModeAction->trigger();
    const bool pencilActionToggledOn = pencilModeAction->isChecked();
    const QPixmap pencilCursorPixmap = rig.area().cursor().pixmap();
    const bool pencilCursorInstalled = !pencilCursorPixmap.isNull();
    pencilModeAction->trigger();
    const bool pencilActionToggledOff = !pencilModeAction->isChecked();
    check(pencilModeAction->isCheckable() && pencilActionInitiallyDisabled &&
              pencilActionToggledOn && pencilCursorInstalled && pencilActionToggledOff,
          QStringLiteral("Pencil Mode action must be checkable, initially disabled, and toggle "
                         "on with a bitmap cursor then off"));
    QLineEdit editor(&rig.view());
    QApplication::setActiveWindow(&rig.view());
    editor.show();
    editor.setFocus();
    rig.pump();
    QKeyEvent typedB(QEvent::KeyPress, Qt::Key_B, Qt::NoModifier, QStringLiteral("b"));
    QCoreApplication::sendEvent(&editor, &typedB);
    check(editor.text() == QStringLiteral("b") && !pencilModeAction->isChecked(),
          QStringLiteral("Pencil shortcut consumed B from a focused text input"));
    editor.hide();
    rig.view().setFocus();
    rig.pump();
    const QKeySequence originalPencilShortcut = pencilModeAction->shortcut();
    constexpr int configuredPencilKey = Qt::Key_P;
    pencilModeAction->setShortcut(QKeySequence(configuredPencilKey));
    const auto sendPencilKeyToView = [&](QEvent::Type type, bool autoRepeat = false) {
        rig.keyToView(type, configuredPencilKey, Qt::NoModifier, autoRepeat);
        rig.pump();
    };
    const auto sendPencilKeyToWindow = [&](QEvent::Type type) {
        rig.keyToWindow(type, configuredPencilKey);
        rig.pump();
    };
    rig.setPersistentPencil(false);
    sendPencilKeyToView(QEvent::KeyPress);
    const bool tapWasMomentary = !pencilModeAction->isChecked();
    sendPencilKeyToView(QEvent::KeyRelease);
    const bool tapBecamePersistent = pencilModeAction->isChecked();
    check(tapWasMomentary && tapBecamePersistent,
          QStringLiteral("single-key Pencil tap did not become persistent on release"));
    rig.setPersistentPencil(false);
    sendPencilKeyToWindow(QEvent::KeyPress);
    const bool nativeWindowPressWasMomentary = !pencilModeAction->isChecked();
    sendPencilKeyToWindow(QEvent::KeyRelease);
    const bool nativeWindowTapBecamePersistent = pencilModeAction->isChecked();
    check(nativeWindowPressWasMomentary && nativeWindowTapBecamePersistent,
          QStringLiteral("native-window Pencil tap did not preserve persistent mode"));
    sendPencilKeyToView(QEvent::KeyPress);
    const bool repeatBaseline = pencilModeAction->isChecked();
    sendPencilKeyToView(QEvent::KeyPress, true);
    sendPencilKeyToView(QEvent::KeyRelease, true);
    const bool repeatWasConsumed = pencilModeAction->isChecked();
    sendPencilKeyToView(QEvent::KeyRelease);
    check(repeatBaseline && repeatWasConsumed && !pencilModeAction->isChecked(),
          QStringLiteral("Pencil shortcut auto-repeat retriggered or escaped consumption"));
    rig.setPersistentPencil(false);
    sendPencilKeyToView(QEvent::KeyPress);
    const bool longHoldWasMomentary = !pencilModeAction->isChecked();
    rig.waitForTimers(510);
    sendPencilKeyToView(QEvent::KeyRelease);
    check(longHoldWasMomentary && !pencilModeAction->isChecked(),
          QStringLiteral("Pencil shortcut hold past 500 ms did not restore persistent mode"));
    rig.setPersistentPencil(false);
    const auto shortHoldInput = rig.pointAt(rig.pan, 192, 64);
    sendPencilKeyToView(QEvent::KeyPress);
    const bool shortHoldWasMomentary = !pencilModeAction->isChecked();
    rig.mousePress(shortHoldInput.position);
    rig.mouseRelease(shortHoldInput.position);
    rig.pump();
    sendPencilKeyToView(QEvent::KeyRelease);
    check(shortHoldWasMomentary && !pencilModeAction->isChecked(),
          QStringLiteral("short Pencil hold used for a gesture became persistent"));
    rig.setPersistentPencil(false);
    pencilModeAction->trigger();
    const bool programmaticTriggerEnabled = pencilModeAction->isChecked();
    pencilModeAction->trigger();
    check(programmaticTriggerEnabled && !pencilModeAction->isChecked(),
          QStringLiteral("programmatic Pencil QAction trigger lost persistent toggle behavior"));
    const QKeySequence modifiedShortcut(Qt::CTRL | Qt::Key_B);
    pencilModeAction->setShortcut(modifiedShortcut);
    rig.setPersistentPencil(false);
    rig.keyToView(QEvent::KeyPress, Qt::Key_B, Qt::ControlModifier);
    rig.pump();
    const bool modifiedShortcutActivated = pencilModeAction->isChecked();
    rig.keyToView(QEvent::KeyRelease, Qt::Key_B, Qt::ControlModifier);
    rig.pump();
    rig.keyToView(QEvent::KeyPress, Qt::Key_B, Qt::ControlModifier);
    rig.pump();
    const bool modifiedShortcutToggled = !pencilModeAction->isChecked();
    rig.keyToView(QEvent::KeyRelease, Qt::Key_B, Qt::ControlModifier);
    rig.pump();
    check(pencilModeAction->shortcut() == modifiedShortcut && modifiedShortcutActivated &&
              modifiedShortcutToggled,
          QStringLiteral("modified Pencil shortcut did not activate and toggle the action"));
    pencilModeAction->setShortcut(originalPencilShortcut);
    rig.setPersistentPencil(false);
}
