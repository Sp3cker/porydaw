#include "pluginterfaces/base/funknownimpl.h"
#include "pluginterfaces/gui/iplugview.h"
#include <xcb/xcb.h>
#include <cstdlib>
#include <cstdint>
namespace {
class FixtureWindow final : public Steinberg::U::Implements<Steinberg::U::Directly<Steinberg::Linux::IEventHandler>> {
public:
    Steinberg::IPtr<Steinberg::Linux::IRunLoop> loop;
    xcb_connection_t* connection = nullptr;
    xcb_window_t window = XCB_WINDOW_NONE;
    void (*key)(void*) = nullptr;
    void* user = nullptr;
    bool needsInitialFocus = true;
    void PLUGIN_API onFDIsSet(int) override {
        while (auto* event = xcb_poll_for_event(connection)) {
            const auto kind = event->response_type & 0x7f;
            if (kind == XCB_KEY_PRESS && key) key(user);
            if (kind == XCB_VISIBILITY_NOTIFY && needsInitialFocus) {
                needsInitialFocus = false;
                xcb_set_input_focus(connection, XCB_INPUT_FOCUS_PARENT, window, XCB_CURRENT_TIME); xcb_flush(connection);
            }
            if (kind == XCB_BUTTON_PRESS) { xcb_set_input_focus(connection, XCB_INPUT_FOCUS_PARENT, window, XCB_CURRENT_TIME); xcb_flush(connection); }
            std::free(event);
        }
    }
};
}
void* pdphFixtureViewCreate(void* parent, int width, int height, void (*key)(void*), void* user, void* runLoop) {
    if (!runLoop) return nullptr;
    auto view = Steinberg::owned(new FixtureWindow);
    view->loop = static_cast<Steinberg::Linux::IRunLoop*>(runLoop);
    view->key = key; view->user = user;
    view->connection = xcb_connect(nullptr, nullptr);
    if (xcb_connection_has_error(view->connection)) { xcb_disconnect(view->connection); return nullptr; }
    view->window = xcb_generate_id(view->connection);
    const uint32_t values[] = {0x264059, XCB_EVENT_MASK_KEY_PRESS | XCB_EVENT_MASK_KEY_RELEASE | XCB_EVENT_MASK_BUTTON_PRESS | XCB_EVENT_MASK_EXPOSURE | XCB_EVENT_MASK_VISIBILITY_CHANGE};
    xcb_create_window(view->connection, XCB_COPY_FROM_PARENT, view->window, xcb_window_t(reinterpret_cast<uintptr_t>(parent)), 0, 0,
        uint16_t(width), uint16_t(height), 0, XCB_WINDOW_CLASS_INPUT_OUTPUT, XCB_COPY_FROM_PARENT, XCB_CW_BACK_PIXEL | XCB_CW_EVENT_MASK, values);
    constexpr char property[] = "_XEMBED_INFO";
    auto* atom = xcb_intern_atom_reply(view->connection, xcb_intern_atom(view->connection, false, sizeof(property) - 1, property), nullptr);
    if (atom) { const uint32_t info[] = {0, 1}; xcb_change_property(view->connection, XCB_PROP_MODE_REPLACE, view->window, atom->atom, atom->atom, 32, 2, info); std::free(atom); }
    xcb_map_window(view->connection, view->window);
    xcb_flush(view->connection);
    if (view->loop->registerEventHandler(view, xcb_get_file_descriptor(view->connection)) != Steinberg::kResultOk) {
        xcb_disconnect(view->connection); return nullptr;
    }
    return view.take();
}
void pdphFixtureViewResize(void* handle, int width, int height) {
    auto* view = static_cast<FixtureWindow*>(handle);
    const uint32_t size[] = {uint32_t(width), uint32_t(height)};
    xcb_configure_window(view->connection, view->window, XCB_CONFIG_WINDOW_WIDTH | XCB_CONFIG_WINDOW_HEIGHT, size); xcb_flush(view->connection);
}
void pdphFixtureViewDestroy(void* handle) {
    auto* view = static_cast<FixtureWindow*>(handle);
    view->loop->unregisterEventHandler(view);
    xcb_destroy_window(view->connection, view->window); xcb_flush(view->connection); xcb_disconnect(view->connection);
    view->release();
}
