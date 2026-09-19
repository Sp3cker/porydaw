#pragma once

#ifdef __cplusplus
extern "C" {
#endif

void installGridSmoke(void);

#ifdef __cplusplus
}
void verifyGridAudio();
class QObject;
class QQuickWindow;
void verifyGridInteractions(QQuickWindow *window, QObject *model);
void verifyGridUndo(QQuickWindow *window, QObject *model);
void verifyGridCancel(QQuickWindow *window, QObject *model);
void verifyGridEscape(QQuickWindow *window, QObject *model);
// Re-establishes OS window activation before a shortcut-dependent scenario:
// window-tier QML Shortcuts (Space, G) only fire while the window is active,
// synthetic QTest input cannot restore activation once the desktop
// deactivates the window mid-run, and macOS refuses focus steals while the
// user is actively typing elsewhere — so keep requesting across a bounded
// window instead of failing a scenario whose only unmet input is OS focus.
void ensureSmokeWindowActive(QQuickWindow *window);
#endif
