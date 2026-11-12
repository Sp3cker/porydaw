#include <windows.h>
#include <memory>
namespace {
struct FixtureWindow { HWND window = nullptr; void (*key)(void*) = nullptr; void* user = nullptr; };
LRESULT CALLBACK fixtureProcedure(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    if (message == WM_NCCREATE) SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams));
    auto* state = reinterpret_cast<FixtureWindow*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    switch (message) {
    case WM_LBUTTONDOWN: SetFocus(window); return 0;
    case WM_SHOWWINDOW: if (wparam) SetFocus(window); break;
    case WM_KEYDOWN: case WM_SYSKEYDOWN: if (state && state->key) state->key(state->user); return 0;
    case WM_PAINT: {
        PAINTSTRUCT paint{}; HDC dc = BeginPaint(window, &paint);
        HBRUSH brush = CreateSolidBrush(RGB(38, 64, 89)); FillRect(dc, &paint.rcPaint, brush); DeleteObject(brush);
        EndPaint(window, &paint); return 0;
    }
    case WM_NCDESTROY: SetWindowLongPtrW(window, GWLP_USERDATA, 0); break;
    default: break;
    }
    return DefWindowProcW(window, message, wparam, lparam);
}
}
void* pdphFixtureViewCreate(void* parent, int width, int height, void (*key)(void*), void* user, void*) {
    HMODULE module = nullptr;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        reinterpret_cast<LPCWSTR>(&fixtureProcedure), &module)) return nullptr;
    WNDCLASSW cls{}; cls.lpfnWndProc = fixtureProcedure; cls.hInstance = module; cls.lpszClassName = L"PorydawFixtureView";
    if (!RegisterClassW(&cls) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return nullptr;
    auto state = std::make_unique<FixtureWindow>(); state->key = key; state->user = user;
    state->window = CreateWindowExW(0, cls.lpszClassName, L"", WS_CHILD | WS_VISIBLE, 0, 0, width, height,
        static_cast<HWND>(parent), nullptr, module, state.get());
    if (!state->window) { UnregisterClassW(cls.lpszClassName, module); return nullptr; }
    SetFocus(state->window);
    return state.release();
}
void pdphFixtureViewResize(void* handle, int width, int height) {
    const auto* state = static_cast<FixtureWindow*>(handle);
    SetWindowPos(state->window, nullptr, 0, 0, width, height, SWP_NOZORDER | SWP_NOACTIVATE);
}
void pdphFixtureViewDestroy(void* handle) {
    std::unique_ptr<FixtureWindow> state(static_cast<FixtureWindow*>(handle));
    const auto module = reinterpret_cast<HINSTANCE>(GetWindowLongPtrW(state->window, GWLP_HINSTANCE));
    DestroyWindow(state->window);
    UnregisterClassW(L"PorydawFixtureView", module);
}
