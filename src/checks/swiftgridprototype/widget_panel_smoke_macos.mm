// AppKit owns native QFileDialog panels; their QWidget backing windows do not
// receive exposure events. Observe the actual panel instead of weakening the
// smoke's shown-window requirement. This never changes focus or window state.
#import <AppKit/AppKit.h>

extern "C" bool sgw_nativeFilePanelVisible()
{
    for (NSWindow *window in NSApp.windows) {
        // NSOpenPanel derives from NSSavePanel (including directory pickers).
        if ([window isKindOfClass:[NSSavePanel class]] && window.isVisible)
            return true;
    }
    return false;
}
