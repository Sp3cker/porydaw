#pragma once

// Private vocabulary shared by the non-ARC macOS CoreAnimation renderers
// (playhead overlay + track activity). Objective-C++ only: include from .mm
// translation units built without ARC.

#include <memory>

#if !defined(__OBJC__)
#error nativelayerutils_macos_p.h is Objective-C++ only
#endif

#import <QuartzCore/QuartzCore.h>

#if __has_feature(objc_arc)
#error nativelayerutils_macos_p.h requires manual retain/release (no ARC)
#endif

namespace native_layer {

// unique_ptr deleter releasing a retained Objective-C object.
struct ReleaseObject {
    template <class T>
    void operator()(T *object) const noexcept
    {
        [object release];
    }
};

template <class T>
using RetainedObject = std::unique_ptr<T, ReleaseObject>;

// unique_ptr deleter releasing a retained CoreFoundation object.
struct ReleaseCoreFoundation {
    template <class T>
    void operator()(T *object) const noexcept
    {
        if (object) {
            CFRelease(object);
        }
    }
};

template <class T>
using RetainedCoreFoundation = std::unique_ptr<T, ReleaseCoreFoundation>;

// Transaction scope with implicit layer actions disabled; commits on exit.
class DisabledActionTransaction final
{
  public:
    DisabledActionTransaction()
    {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
    }

    ~DisabledActionTransaction() { [CATransaction commit]; }

    DisabledActionTransaction(const DisabledActionTransaction &) = delete;
    DisabledActionTransaction(DisabledActionTransaction &&) = delete;
    DisabledActionTransaction &operator=(const DisabledActionTransaction &) = delete;
    DisabledActionTransaction &operator=(DisabledActionTransaction &&) = delete;
};

// Places a layer by its top-left corner: bounds sized to the rect, origin at
// the rect position.
inline void setLayerRect(CALayer *layer, const CGRect &rect)
{
    layer.bounds = CGRectMake(0.0, 0.0, rect.size.width, rect.size.height);
    layer.position = rect.origin;
}

} // namespace native_layer
