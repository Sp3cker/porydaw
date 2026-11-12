#import <Cocoa/Cocoa.h>

@interface PorydawFixtureView : NSView
@property(nonatomic) void* callbackUser;
@property(nonatomic) void (*keyCallback)(void*);
@end
@implementation PorydawFixtureView
- (BOOL)acceptsFirstResponder { return YES; }
- (void)mouseDown:(NSEvent*)event { (void)event; [self.window makeFirstResponder:self]; }
- (void)keyDown:(NSEvent*)event { (void)event; if (self.keyCallback) self.keyCallback(self.callbackUser); }
- (void)drawRect:(NSRect)rect { [[NSColor colorWithCalibratedRed:0.15 green:0.25 blue:0.35 alpha:1.] setFill]; NSRectFill(rect); }
@end

void* pdphFixtureViewCreate(void* parent, int width, int height, void (*key)(void*), void* user, void*) {
    NSView* container = (__bridge NSView*)parent;
    PorydawFixtureView* view = [[PorydawFixtureView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
    view.keyCallback = key; view.callbackUser = user;
    [container addSubview:view];
    [container.window makeFirstResponder:view];
    return (__bridge_retained void*)view;
}
void pdphFixtureViewResize(void* handle, int width, int height) {
    NSView* view = (__bridge NSView*)handle;
    [view setFrameSize:NSMakeSize(width, height)];
}
void pdphFixtureViewDestroy(void* handle) {
    NSView* view = (__bridge_transfer NSView*)handle;
    [view removeFromSuperview];
}
