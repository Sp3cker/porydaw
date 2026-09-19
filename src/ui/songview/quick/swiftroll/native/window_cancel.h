#pragma once

// Host-owned window cancel filter. Mirrors TimelineQuickView::eventFilter:
// QEvent::Hide → Hidden (2), QEvent::WindowDeactivate → WindowDeactivated (3).
// Raw values match songview::TimelineInputCancelReason.
//
// The filter QObject is parented to the QQuickWindow it watches. The sink is
// a typed input-cancel function pointer. No property handshake, no
// invokeMethod, no app-global event-filter singleton.

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*SgwInputCancelledFn)(int reason, void *context);

void sgw_installWindowCancelHost(SgwInputCancelledFn fn, void *context);

#ifdef __cplusplus
}
#endif
