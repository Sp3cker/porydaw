#import <AppKit/AppKit.h>

#include "checks/support/nativeapplication.h"

namespace checks {

bool prepareNativeApplication()
{
    NSApplication *const application = NSApp;
    if (application.activationPolicy != NSApplicationActivationPolicyRegular &&
        ![application setActivationPolicy:NSApplicationActivationPolicyRegular])
        return false;
    if (application.activationPolicy != NSApplicationActivationPolicyRegular)
        return false;

    // QApplication's Cocoa bootstrap normally establishes the Regular policy
    // even for this unbundled check executable. It does not foreground a child
    // launched by the noninteractive runner, so window-level activation
    // requests remain pending until the AppKit application is activated.
    [application activateIgnoringOtherApps:YES];
    return true;
}

} // namespace checks
