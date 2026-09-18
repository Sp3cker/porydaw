#pragma once

// Native window eventFilter for the Swift grid prototype: mirrors the
// production TimelineQuickView::eventFilter Hide/WindowDeactivate entry
// (timelinequickview_window.cpp), which delivers one cancelActiveGestures
// pass for the grid surface. QML must not wire reason 3: isActive is app
// bookkeeping and is not synthesizable via sendEvent.

#ifdef __cplusplus
extern "C" {
#endif

// Installs the singleton filter on the application object (deferred via a
// pre-routine when called before QCoreApplication exists, as in App.init).
// Safe to call more than once; only the first call installs.
void sgw_installWindowCancelFilter(void);

#ifdef __cplusplus
}
#endif
