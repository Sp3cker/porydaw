#include "host.h"
#import <AppKit/AppKit.h>

namespace pdph::helper {
void setAccessoryPolicy() {
    [NSApplication.sharedApplication setActivationPolicy:NSApplicationActivationPolicyAccessory];
}
}
