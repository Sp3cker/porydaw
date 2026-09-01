#import <AppKit/AppKit.h>

#include <QPointF>
#include <QWidget>

bool postAutomationHoverMouseMove(QWidget &target, const QPointF &position)
{
    QWidget *const topLevel = target.window();
    if (!topLevel)
        return false;

    const WId nativeId = topLevel->winId();
    NSView *const contentView = nativeId ? reinterpret_cast<NSView *>(nativeId) : nil;
    NSWindow *const window = contentView.window;
    if (!contentView || !window)
        return false;

    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:nil];
    if (!NSApp.active)
        return false;

    const QPoint topLevelPoint = target.mapTo(topLevel, position.toPoint());
    const NSPoint windowPoint =
        [contentView convertPoint:NSMakePoint(topLevelPoint.x(), topLevelPoint.y()) toView:nil];
    NSEvent *const event = [NSEvent mouseEventWithType:NSEventTypeMouseMoved
                                              location:windowPoint
                                         modifierFlags:0
                                             timestamp:NSProcessInfo.processInfo.systemUptime
                                          windowNumber:window.windowNumber
                                               context:nil
                                           eventNumber:0
                                            clickCount:0
                                              pressure:0.0];
    if (!event)
        return false;

    [NSApp sendEvent:event];
    return true;
}
