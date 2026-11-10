#include "editor.h"
#include "pluginhost_internal.h"
#include "pluginterfaces/gui/iplugview.h"
#include "pluginterfaces/gui/iplugviewcontentscalesupport.h"
#include <QCoreApplication>
#include <QEvent>
#include <QGuiApplication>
#include <QResizeEvent>
#include <QScreen>
#include <QScopedValueRollback>
#include <QSocketNotifier>
#include <QTimer>
#include <algorithm>
#include <chrono>
#include <map>
#include <memory>
#include <cstdio>
#include <exception>
#include <utility>
#include <vector>

using namespace Steinberg;
namespace {
std::vector<pdph_editor> editors;
#if defined(__linux__)
class RunLoop final : public U::Implements<U::Directly<Linux::IRunLoop>> {
    struct Event { IPtr<Linux::IEventHandler> handler; std::unique_ptr<QSocketNotifier> notifier; };
    struct Timer { IPtr<Linux::ITimerHandler> handler; std::unique_ptr<QTimer> timer; };
    std::map<int, Event> events;
    std::map<Linux::ITimerHandler*, Timer> timers;
public:
    ~RunLoop() override { clear(); }
    void clear() {
        for (auto& entry : events) {
            auto* notifier = entry.second.notifier.release();
            notifier->setEnabled(false); notifier->disconnect(); notifier->deleteLater();
        }
        events.clear();
        for (auto& entry : timers) {
            auto* timer = entry.second.timer.release();
            timer->stop(); timer->disconnect(); timer->deleteLater();
        }
        timers.clear();
    }
    tresult PLUGIN_API registerEventHandler(Linux::IEventHandler* handler, int fd) override {
        if (!handler || fd < 0 || events.count(fd)) return kInvalidArgument;
        auto notifier = std::make_unique<QSocketNotifier>(fd, QSocketNotifier::Read, QCoreApplication::instance());
        QObject::connect(notifier.get(), &QSocketNotifier::activated, notifier.get(),
            [handler, fd] { IPtr<Linux::IEventHandler> retained(handler); retained->onFDIsSet(fd); });
        events.emplace(fd, Event{handler, std::move(notifier)});
        return kResultOk;
    }
    tresult PLUGIN_API unregisterEventHandler(Linux::IEventHandler* handler) override {
        bool removed = false;
        for (auto it = events.begin(); it != events.end();) {
            if (it->second.handler.get() != handler) { ++it; continue; }
            auto* notifier = it->second.notifier.release();
            notifier->setEnabled(false); notifier->disconnect(); notifier->deleteLater();
            it = events.erase(it); removed = true;
        }
        return removed ? kResultOk : kInvalidArgument;
    }
    tresult PLUGIN_API registerTimer(Linux::ITimerHandler* handler, Linux::TimerInterval interval) override {
        if (!handler || !interval || interval > INT32_MAX || timers.count(handler)) return kInvalidArgument;
        auto timer = std::make_unique<QTimer>(QCoreApplication::instance());
        QObject::connect(timer.get(), &QTimer::timeout, timer.get(),
            [handler] { IPtr<Linux::ITimerHandler> retained(handler); retained->onTimer(); });
        timer->start(std::chrono::milliseconds(interval));
        timers.emplace(handler, Timer{handler, std::move(timer)});
        return kResultOk;
    }
    tresult PLUGIN_API unregisterTimer(Linux::ITimerHandler* handler) override {
        const auto it = timers.find(handler);
        if (it == timers.end()) return kInvalidArgument;
        auto* timer = it->second.timer.release();
        timer->stop(); timer->disconnect(); timer->deleteLater(); timers.erase(it);
        return kResultOk;
    }
};
IPtr<RunLoop> factoryRunLoop;
tresult queryRunLoop(const TUID iid, void** object) {
    return factoryRunLoop ? factoryRunLoop->queryInterface(iid, object) : kNoInterface;
}
#endif
}

struct pdph_editor_impl final : public QWindow, public IPlugFrame {
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(pdph_editor_impl)
public:
    pdph_editor_impl(pdph_plugin plugin, IPtr<IPlugView>&& view) : plugin(plugin), view(std::move(view)) {}
    ~pdph_editor_impl() noexcept override {
        detach(false);
        editors.erase(std::remove(editors.begin(), editors.end(), this), editors.end());
    }
    void detach(bool userClosed) noexcept {
        if (!plugin) return;
        auto* owner = plugin;
        plugin = nullptr;
        if (owner->editor == this) { owner->editor = nullptr; owner->closeEditor = nullptr; }
        try { pdph::helper::refreshShortcutWindows(); } catch (...) { std::fprintf(stderr, "Could not refresh editor shortcuts during detach\n"); }
#ifdef __APPLE__
        try { pdph::helper::refreshMacEditorWindows(); } catch (...) { std::fprintf(stderr, "Could not refresh editor ordering during detach\n"); }
#endif
        if (attached) {
            attached = false;
            try { view->removed(); } catch (...) { std::fprintf(stderr, "Plugin editor removed() threw during detach\n"); }
        }
        if (view) {
            try { view->setFrame(nullptr); } catch (...) { std::fprintf(stderr, "Plugin editor setFrame(nullptr) threw during detach\n"); }
            auto* released = view.take();
            try { released->release(); } catch (...) { std::fprintf(stderr, "Plugin editor release() threw during detach\n"); }
        }
#if defined(__linux__)
        if (runLoop) {
            try { runLoop->clear(); } catch (...) { std::fprintf(stderr, "Could not clear editor run loop during detach\n"); }
        }
        runLoop = nullptr;
#endif
        if (userClosed) {
            try { owner->handler->editorClosed(); } catch (...) { std::fprintf(stderr, "Could not notify editor close\n"); }
        }
    }
    tresult PLUGIN_API queryInterface(const TUID iid, void** object) override {
        if (!object) return kInvalidArgument;
        *object = nullptr;
        if (FUnknownPrivate::iidEqual(iid, IPlugFrame::iid) || FUnknownPrivate::iidEqual(iid, FUnknown::iid)) {
            *object = static_cast<IPlugFrame*>(this); addRef(); return kResultOk;
        }
#if defined(__linux__)
        return runLoop ? runLoop->queryInterface(iid, object) : kNoInterface;
#else
        return kNoInterface;
#endif
    }
    uint32 PLUGIN_API addRef() override { return ++references; }
    uint32 PLUGIN_API release() override { return --references; }
    tresult PLUGIN_API resizeView(IPlugView* source, ViewRect* rect) override {
        if (!view || source != view.get() || !rect || rect->getWidth() <= 0 || rect->getHeight() <= 0) return kInvalidArgument;
        if (resizing) return kResultOk;
        QScopedValueRollback<bool> guard(resizing, true);
        ViewRect constrained = *rect;
        if (view->canResize() == kResultTrue) view->checkSizeConstraint(&constrained);
        if (constrained.getWidth() <= 0 || constrained.getHeight() <= 0) return kInvalidArgument;
        const QSize logical(qCeil(constrained.getWidth() / scale()), qCeil(constrained.getHeight() / scale()));
        if (size() != logical) {
            if (view->canResize() != kResultTrue) { setMinimumSize(logical); setMaximumSize(logical); }
            resize(logical);
        }
        ViewRect current;
        if (view->getSize(&current) != kResultOk || current.getWidth() != constrained.getWidth() || current.getHeight() != constrained.getHeight())
            return view->onSize(&constrained);
        return kResultOk;
    }
    double scale() const {
#ifdef __APPLE__
        return 1.;
#else
        return devicePixelRatio();
#endif
    }
    void updateScale() {
#ifndef __APPLE__
        if (!view) return;
        if (auto support = U::cast<IPlugViewContentScaleSupport>(view)) support->setContentScaleFactor(devicePixelRatio());
#endif
    }
    pdph_plugin plugin;
    IPtr<IPlugView> view;
    bool attached = false, resizing = false;
#if defined(__linux__)
    IPtr<RunLoop> runLoop = owned(new RunLoop);
#endif
protected:
    bool event(QEvent* event) override {
        if (event->type() == QEvent::Close) {
            event->accept(); hide();
            detach(true);
            deleteLater();
            return true;
        }
        if (event->type() == QEvent::DevicePixelRatioChange) updateScale();
        return QWindow::event(event);
    }
    void resizeEvent(QResizeEvent* event) override {
        QWindow::resizeEvent(event);
        if (!attached || resizing) return;
        ViewRect rect(0, 0, qRound(event->size().width() * scale()), qRound(event->size().height() * scale()));
        resizeView(view, &rect);
    }
private:
    uint32 references = 1;
};

namespace pdph::helper {
#ifndef __APPLE__
void* editorParent(QWindow& window) { return reinterpret_cast<void*>(window.winId()); }
#endif
bool isEditorWindow(uintptr_t handle) {
    return std::any_of(editors.cbegin(), editors.cend(), [handle](auto* editor) { return editor->plugin && uintptr_t(editor->winId()) == handle; });
}
QVarLengthArray<uintptr_t, 1> editorWindows() {
    QVarLengthArray<uintptr_t, 1> windows;
    for (const auto* editor : editors) if (editor->plugin) windows.push_back(uintptr_t(editor->winId()));
    return windows;
}
void shutdownEditors() {
    pdph_editor_set_shortcuts(nullptr, 0, nullptr, nullptr);
    while (!editors.empty()) pdph_editor_close(editors.back());
#if defined(__linux__)
    if (factoryRunLoop) factoryRunLoop->clear();
    pdph::hostQuery = nullptr; factoryRunLoop = nullptr;
#endif
}
void installEditors() {
#if defined(__linux__)
    if (!factoryRunLoop) factoryRunLoop = owned(new RunLoop);
    pdph::hostQuery = queryRunLoop;
#endif
}
}
extern "C" {
pdph_result pdph_editor_open(pdph_plugin plugin, const char* title, pdph_editor* out, pdph_error* error) {
    if (out) *out = nullptr;
    if (!plugin || !title || !out) return PDPH_ERR_ARGUMENT;
    try {
    if (plugin->editor) {
        auto* editor = plugin->editor;
        editor->show(); editor->raise(); editor->requestActivate();
#ifdef __APPLE__
        pdph::helper::refreshMacEditorWindows();
#endif
        *out = editor; return PDPH_OK;
    }
#if defined(__linux__)
    if (QGuiApplication::platformName() != QStringLiteral("xcb")) {
        pdph::error(error, "Plugin editors need X11 (QT_QPA_PLATFORM=xcb)"); return PDPH_ERR_UNSUPPORTED_PLATFORM;
    }
    const auto type = kPlatformTypeX11EmbedWindowID;
#elif defined(_WIN32)
    const auto type = kPlatformTypeHWND;
#else
    if (QGuiApplication::platformName() != QStringLiteral("cocoa")) {
        pdph::error(error, "Plugin editors need Cocoa (QT_QPA_PLATFORM=cocoa)"); return PDPH_ERR_UNSUPPORTED_PLATFORM;
    }
    const auto type = kPlatformTypeNSView;
#endif
    IPtr<IPlugView> ownedView = owned(plugin->controller->createView(Steinberg::Vst::ViewType::kEditor));
    if (!ownedView) { pdph::error(error, "Plugin has no editor (PDPH_ERR_NO_EDITOR)"); return PDPH_ERR_NO_EDITOR; }
    auto* view = ownedView.get();
    auto editor = std::make_unique<pdph_editor_impl>(plugin, std::move(ownedView));
    if (view->isPlatformTypeSupported(type) != kResultTrue) {
        pdph::error(error, "Plugin editor does not support this platform"); return PDPH_ERR_UNSUPPORTED_PLATFORM;
    }
    ViewRect rect;
    if (view->getSize(&rect) != kResultOk || rect.getWidth() <= 0 || rect.getHeight() <= 0) {
        pdph::error(error, "Plugin editor returned an invalid size"); return PDPH_ERR_SDK;
    }
    editor->setTitle(QString::fromUtf8(title));
    editor->setFlags(Qt::Window | Qt::WindowTitleHint | Qt::WindowCloseButtonHint | Qt::WindowMinimizeButtonHint);
    editor->resize(QSize(qCeil(rect.getWidth() / editor->scale()), qCeil(rect.getHeight() / editor->scale())));
    editor->create();
    if (view->setFrame(editor.get()) != kResultOk) {
        pdph::error(error, "Could not set plugin editor frame"); return PDPH_ERR_SDK;
    }
    editor->updateScale();
    if (view->getSize(&rect) != kResultOk || editor->resizeView(view, &rect) != kResultOk) {
        pdph::error(error, "Could not size plugin editor"); return PDPH_ERR_SDK;
    }
    editor->attached = true;
    if (view->attached(pdph::helper::editorParent(*editor), type) != kResultOk) {
        pdph::error(error, "Could not attach plugin editor"); return PDPH_ERR_SDK;
    }
    if (view->canResize() != kResultTrue) { editor->setMinimumSize(editor->size()); editor->setMaximumSize(editor->size()); }
    QObject::connect(editor.get(), &QWindow::screenChanged, editor.get(), [target = editor.get()] { target->updateScale(); });
    plugin->editor = editor.get(); plugin->closeEditor = pdph_editor_close;
    editors.push_back(editor.get());
    pdph::helper::refreshShortcutWindows();
    editor->show(); editor->requestActivate();
#ifdef __APPLE__
    pdph::helper::refreshMacEditorWindows();
#endif
    *out = editor.release();
    return PDPH_OK;
    } catch (const std::exception& exception) {
        pdph::error(error, exception.what()); return PDPH_ERR_INTERNAL;
    } catch (...) {
        pdph::error(error, "Plugin editor operation threw an exception"); return PDPH_ERR_INTERNAL;
    }
}
void pdph_editor_raise(pdph_editor editor) {
    if (!editor) return;
    try {
        editor->show(); editor->raise(); editor->requestActivate();
#ifdef __APPLE__
        pdph::helper::refreshMacEditorWindows();
#endif
    } catch (...) { std::fprintf(stderr, "Could not raise plugin editor\n"); }
}
void pdph_editor_close(pdph_editor editor) { delete editor; }
pdph_result pdph_editor_set_shortcuts(const int32_t* strokes, int32_t count, void (*callback)(void*, int32_t), void* user) {
    struct StrokeArray { const int32_t* values; } source{strokes};
    const pdph::helper::ShortcutStrokeReader readStroke = [](void* context, int32_t index) noexcept {
        return static_cast<const StrokeArray*>(context)->values[index];
    };
    return pdph::helper::setEditorShortcuts(count, strokes ? readStroke : nullptr, &source, callback, user);
}
}
#include "editor.moc"
