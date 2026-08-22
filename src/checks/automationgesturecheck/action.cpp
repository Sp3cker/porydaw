#include "domains.h"

#include <QAction>
#include <QApplication>
#include <QCoreApplication>
#include <QEvent>
#include <QKeySequence>
#include <QLineEdit>

#include "checks/support/eventsynth.h"
#include "rig.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/songview.h"

namespace {

enum class Target { View, Window };

constexpr int kPencilShortcutKey = Qt::Key_P;

class ScopedShortcut final
{
  public:
    explicit ScopedShortcut(QAction *action) : m_action(action), m_previous(action->shortcut()) {}
    ~ScopedShortcut() { m_action->setShortcut(m_previous); }

    ScopedShortcut(const ScopedShortcut &) = delete;
    ScopedShortcut &operator=(const ScopedShortcut &) = delete;

  private:
    QAction *m_action;
    QKeySequence m_previous;
};

} // namespace

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
    pencilModeAction->trigger();
    const bool pencilActionToggledOff = !pencilModeAction->isChecked();
    check(pencilModeAction->isCheckable() && pencilActionInitiallyDisabled &&
              pencilActionToggledOn && pencilActionToggledOff,
          QStringLiteral("Pencil Mode action must be checkable and toggle between disabled and "
                         "enabled; the pencil cursor itself is position-scoped (see cursor "
                         "domain)"));
    QLineEdit editor(&rig.view());
    QApplication::setActiveWindow(&rig.view());
    editor.show();
    editor.setFocus();
    rig.pump();
    checks::events::sendKey(editor, QEvent::KeyPress, Qt::Key_B, Qt::NoModifier,
                            QStringLiteral("b"), false, 1);
    check(editor.text() == QStringLiteral("b") && !pencilModeAction->isChecked(),
          QStringLiteral("Pencil shortcut consumed B from a focused text input"));
    editor.hide();
    rig.view().setFocus();
    rig.pump();
    const ScopedShortcut scopedShortcut(pencilModeAction);
    pencilModeAction->setShortcut(QKeySequence(kPencilShortcutKey));
    const auto sendPencilKey = [&](Target target, QEvent::Type type, bool autoRepeat) {
        switch (target) {
        case Target::View:
            rig.keyToView(type, kPencilShortcutKey, Qt::NoModifier, autoRepeat);
            break;
        case Target::Window:
            rig.keyToWindow(type, kPencilShortcutKey, Qt::NoModifier, autoRepeat);
            break;
        }
        rig.pump();
    };
    rig.setPersistentPencil(false);
    sendPencilKey(Target::View, QEvent::KeyPress, false);
    const bool tapWasMomentary = !pencilModeAction->isChecked();
    sendPencilKey(Target::View, QEvent::KeyRelease, false);
    const bool tapBecamePersistent = pencilModeAction->isChecked();
    check(tapWasMomentary && tapBecamePersistent,
          QStringLiteral("single-key Pencil tap did not become persistent on release"));
    rig.setPersistentPencil(false);
    sendPencilKey(Target::Window, QEvent::KeyPress, false);
    const bool nativeWindowPressWasMomentary = !pencilModeAction->isChecked();
    sendPencilKey(Target::Window, QEvent::KeyRelease, false);
    const bool nativeWindowTapBecamePersistent = pencilModeAction->isChecked();
    check(nativeWindowPressWasMomentary && nativeWindowTapBecamePersistent,
          QStringLiteral("native-window Pencil tap did not preserve persistent mode"));
    sendPencilKey(Target::View, QEvent::KeyPress, false);
    const bool repeatBaseline = pencilModeAction->isChecked();
    sendPencilKey(Target::View, QEvent::KeyPress, true);
    sendPencilKey(Target::View, QEvent::KeyRelease, true);
    const bool repeatWasConsumed = pencilModeAction->isChecked();
    sendPencilKey(Target::View, QEvent::KeyRelease, false);
    check(repeatBaseline && repeatWasConsumed && !pencilModeAction->isChecked(),
          QStringLiteral("Pencil shortcut auto-repeat retriggered or escaped consumption"));
    rig.setPersistentPencil(false);
    sendPencilKey(Target::View, QEvent::KeyPress, false);
    const bool longHoldWasMomentary = !pencilModeAction->isChecked();
    rig.commitTimers(510);
    sendPencilKey(Target::View, QEvent::KeyRelease, false);
    check(longHoldWasMomentary && !pencilModeAction->isChecked(),
          QStringLiteral("Pencil shortcut hold past 500 ms did not restore persistent mode"));
    rig.setPersistentPencil(false);
    const auto shortHoldInput = rig.pointAt(rig.pan, 192, 64);
    sendPencilKey(Target::View, QEvent::KeyPress, false);
    const bool shortHoldWasMomentary = !pencilModeAction->isChecked();
    rig.mousePress(shortHoldInput.position);
    rig.mouseRelease(shortHoldInput.position);
    rig.pump();
    sendPencilKey(Target::View, QEvent::KeyRelease, false);
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
    rig.setPersistentPencil(false);
}
