#pragma once

// Shared native widget-interop ABI for the Swift/QML song-tab prototype.
//
// The prototype keeps the real QML ApplicationWindow as the top-level window
// and opens real production widgets over it: the production NewSongWizard
// (populated from a detached in-memory catalog, so it never reads a project
// root) and a plain QMenu. Both launches are asynchronous: the call returns as
// soon as the widget is up, and the single outcome arrives later through the
// caller's callback.
//
// Threading: install and launch calls belong to the GUI thread. A launch that
// arrives from another thread is dispatched onto the GUI thread and the call
// still reports whether the widget started; the callback is always delivered on
// the GUI thread. `detail` is UTF-8 and only valid for the duration of the call
// (the receiver copies it).

#ifdef __cplusplus
extern "C" {
#endif

enum {
    SgwWidgetResultMenuAction = 3,    // detail: the triggered action's label
    SgwWidgetResultMenuDismissed = 4, // Escape or click away, no action taken
    SgwWidgetResultAccepted = 5,      // fixture accepted/confirmed (detail: window title)
    SgwWidgetResultCancelled = 6      // fixture rejected/cancelled (detail: window title)
};

typedef void (*SgwWidgetResultFn)(int kind, const char *detail, void *context);

// Prepares the host once: under QApplication it installs the production layout
// (src/ui/layout.cpp) and adopts the application's top-level QQuickWindow,
// whose platform window is the transient parent for every widget opened later.
// Standard output carries exactly "SWIFT_GRID_QUICK_HOST READY", printed once
// the adopted window is actually exposed on screen. Safe to call repeatedly.
void sgw_installWidgetInteropHost(void);

// Pops a real QMenu anchored at (windowX, windowY): a QQuickWindow-local point
// in logical pixels (top-left origin, content coordinates). The point is
// mapped to global logical pixels and clamped so the whole menu stays inside
// the available geometry of the screen under it; a device pixel ratio never
// enters that mapping. Returns nonzero only when the menu was started.
int sgw_openWidgetMenu(double windowX, double windowY, SgwWidgetResultFn fn, void *context);

// Opens a standalone window fixture by kind (see SgwWindowKind in
// widget_window_fixtures.h). The window is window-modal over the Quick window,
// carries the Quick window as its transient parent, and uses mock data with no
// project writes. Returns nonzero only when the fixture was started; its outcome
// arrives through `fn` as SgwWidgetResultAccepted (5) or SgwWidgetResultCancelled
// (6), with the dialog window title in `detail`.
int sgw_openWindowFixture(int kind, SgwWidgetResultFn fn, void *context);

// Returns the currently active bridge-owned widget, or NULL if none is active.
void *sgw_widgetInteropActiveWidget(void);

// Verification entry point: inert unless PORYDAW_SWIFT_WIDGET_SMOKE=1 or
// PORYDAW_SWIFT_WIDGET_PREVIEW=1. The bounded mode drives the scenario
// automation and exits after "SWIFT_GRID_WIDGET_SMOKE PASS"; the preview mode
// drives the same automation and leaves the application open.
void sgw_installWidgetInteropSmoke(void);

#ifdef __cplusplus
}
#endif
