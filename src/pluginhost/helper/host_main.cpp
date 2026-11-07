#include "host.h"
#include <QCoreApplication>
#include <QGuiApplication>
#include <QMetaObject>
#include <chrono>
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <utility>
#ifdef _WIN32
#include <windows.h>
#include <fcntl.h>
#include <io.h>
#else
#include <cerrno>
#include <csignal>
#include <poll.h>
#include <unistd.h>
#endif
#if defined(__linux__)
#include "pluginterfaces/gui/iplugview.h"
#include "pluginterfaces/base/funknownimpl.h"
#include <QSocketNotifier>
#include <map>
#include <memory>
#endif

namespace pdph::helper {
namespace {
using namespace std::chrono_literals;
#if defined(__linux__)
class RunLoop final : public Steinberg::U::Implements<Steinberg::U::Directly<Steinberg::Linux::IRunLoop>> {
    struct Event { Steinberg::IPtr<Steinberg::Linux::IEventHandler> handler; std::unique_ptr<QSocketNotifier> notifier; };
    struct Timer { Steinberg::IPtr<Steinberg::Linux::ITimerHandler> handler; std::unique_ptr<QTimer> timer; };
    std::map<int, Event> events;
    std::map<Steinberg::Linux::ITimerHandler*, Timer> timers;
public:
    Steinberg::tresult PLUGIN_API registerEventHandler(Steinberg::Linux::IEventHandler* handler, int fd) override {
        if (!handler || fd < 0 || events.count(fd)) return Steinberg::kInvalidArgument;
        auto notifier = std::make_unique<QSocketNotifier>(fd, QSocketNotifier::Read, QCoreApplication::instance());
        QObject::connect(notifier.get(), &QSocketNotifier::activated, QCoreApplication::instance(),
            [handler, fd] { Steinberg::IPtr<Steinberg::Linux::IEventHandler> retained(handler); retained->onFDIsSet(fd); });
        events.emplace(fd, Event{handler, std::move(notifier)});
        return Steinberg::kResultOk;
    }
    Steinberg::tresult PLUGIN_API unregisterEventHandler(Steinberg::Linux::IEventHandler* handler) override {
        bool removed = false;
        for (auto it = events.begin(); it != events.end();) {
            if (it->second.handler.get() != handler) { ++it; continue; }
            auto* notifier = it->second.notifier.release();
            notifier->setEnabled(false); notifier->disconnect(); notifier->deleteLater();
            it = events.erase(it); removed = true;
        }
        return removed ? Steinberg::kResultOk : Steinberg::kInvalidArgument;
    }
    Steinberg::tresult PLUGIN_API registerTimer(Steinberg::Linux::ITimerHandler* handler, Steinberg::Linux::TimerInterval interval) override {
        if (!handler || !interval || interval > INT32_MAX || timers.count(handler)) return Steinberg::kInvalidArgument;
        auto timer = std::make_unique<QTimer>(QCoreApplication::instance());
        QObject::connect(timer.get(), &QTimer::timeout, QCoreApplication::instance(),
            [handler] { Steinberg::IPtr<Steinberg::Linux::ITimerHandler> retained(handler); retained->onTimer(); });
        timer->start(std::chrono::milliseconds(interval));
        timers.emplace(handler, Timer{handler, std::move(timer)});
        return Steinberg::kResultOk;
    }
    Steinberg::tresult PLUGIN_API unregisterTimer(Steinberg::Linux::ITimerHandler* handler) override {
        const auto it = timers.find(handler);
        if (it == timers.end()) return Steinberg::kInvalidArgument;
        auto* timer = it->second.timer.release();
        timer->stop(); timer->disconnect(); timer->deleteLater(); timers.erase(it);
        return Steinberg::kResultOk;
    }
};
RunLoop* currentRunLoop = nullptr;
#endif
bool readExact(Host& host, char* bytes, size_t size) {
    while (size && !host.stopping.load(std::memory_order_acquire)) {
#ifdef _WIN32
        HANDLE input = GetStdHandle(STD_INPUT_HANDLE);
        DWORD available = 0, count = 0;
        if (!PeekNamedPipe(input, nullptr, 0, nullptr, &available, nullptr)) return false;
        if (!available) { std::this_thread::sleep_for(10ms); continue; }
        const DWORD wanted = static_cast<DWORD>((std::min)(size, static_cast<size_t>(available)));
        if (!ReadFile(input, bytes, wanted, &count, nullptr) || !count) return false;
#else
        pollfd input = {STDIN_FILENO, POLLIN, 0};
        const int ready = poll(&input, 1, 100);
        if (ready < 0) { if (errno == EINTR) continue; return false; }
        if (!ready) continue;
        const auto count = ::read(STDIN_FILENO, bytes, size);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return false;
#endif
        bytes += count; size -= count;
    }
    return size == 0;
}
uint32_t decode32(const unsigned char* bytes) {
    return uint32_t(bytes[0]) | (uint32_t(bytes[1]) << 8) | (uint32_t(bytes[2]) << 16) | (uint32_t(bytes[3]) << 24);
}
}
static bool inputClosed() {
#ifdef _WIN32
    DWORD available = 0;
    return !PeekNamedPipe(GetStdHandle(STD_INPUT_HANDLE), nullptr, 0, nullptr, &available, nullptr);
#else
    pollfd input = {STDIN_FILENO, POLLIN, 0};
    return poll(&input, 1, 0) > 0 && (input.revents & (POLLHUP | POLLERR | POLLNVAL));
#endif
}
#if defined(__linux__)
Steinberg::FUnknown* linuxRunLoop() { return currentRunLoop; }
#endif
Host::Host() {
    for (uint32_t index = 0; index < callbackSlots.size(); ++index) callbackSlots[index].sequence.store(index, std::memory_order_relaxed);
    QObject::connect(&callbackTimer, &QTimer::timeout, &context, [this] { drainCallbacks(); });
    callbackTimer.start(10ms);
}
Host::~Host() {
    stop(exitStatus.load(std::memory_order_relaxed));
    callbackTimer.stop();
    if (reader.joinable()) reader.join();
    if (realtime.joinable()) realtime.join();
    if (plugin) pdph_plugin_destroy(plugin);
    if (module) pdph_module_close(module);
    pdpb_channel_close(channel);
}
void Host::stop(int status) {
    if (status) exitStatus.store(status, std::memory_order_relaxed);
    stopping.store(true, std::memory_order_release);
    QMetaObject::invokeMethod(&context, [] { QCoreApplication::quit(); }, Qt::QueuedConnection);
}
void readControls(Host& host) {
    while (!host.stopping.load(std::memory_order_acquire)) {
        unsigned char header[12];
        if (!readExact(host, reinterpret_cast<char*>(header), sizeof(header))) { host.stop(0); return; }
        Frame frame = {decode32(header), decode32(header + 4), {}};
        const uint32_t size = decode32(header + 8);
        if (size > PDPB_MAX_CONTROL_BYTES || !frame.request) { host.stop(1); return; }
        frame.payload.resize(size);
        if (!readExact(host, frame.payload.data(), size)) { host.stop(0); return; }
        host.pendingControls.store(1, std::memory_order_release);
        if (!QMetaObject::invokeMethod(&host.context, [&host, frame = std::move(frame)]() mutable {
            try { if (!host.stopping.load(std::memory_order_acquire)) dispatch(host, std::move(frame)); }
            catch (...) { host.stop(1); }
            host.pendingControls.store(0, std::memory_order_release);
        }, Qt::QueuedConnection)) { host.stop(1); return; }
        while (host.pendingControls.load(std::memory_order_acquire) && !host.stopping.load(std::memory_order_acquire)) {
            if (inputClosed()) { host.stop(0); return; }
            std::this_thread::sleep_for(1ms);
        }
    }
}
int run(int argc, char** argv) {
    if (argc != 4 || std::strcmp(argv[2], "--channel") != 0) {
        std::fprintf(stderr, "Usage: porydaw-vst3-host host --channel <name>\n"); return 1;
    }
    const QByteArray channelName(argv[3]);
#ifdef _WIN32
    _setmode(_fileno(stdin), _O_BINARY); _setmode(_fileno(stdout), _O_BINARY);
#else
    std::signal(SIGPIPE, SIG_IGN);
#endif
    QGuiApplication app(argc, argv);
    app.setQuitOnLastWindowClosed(false);
#ifdef __APPLE__
    setAccessoryPolicy();
#endif
#if defined(__linux__)
    auto runLoop = Steinberg::owned(new RunLoop);
    currentRunLoop = runLoop.get();
#endif
    int result = 1;
    {
        Host host;
        if (pdpb_channel_open(channelName.constData(), &host.channel) != PDPB_OK) {
            std::fprintf(stderr, "Could not open plugin bridge channel\n"); return 1;
        }
        host.resume();
        host.realtime = std::thread([&host] { processRequests(host); });
        QByteArray ready(4, '\0'); ready[0] = PDPB_VERSION;
        if (!sendFrame(PDPB_READY, 0, ready)) return 1;
        host.reader = std::thread([&host] {
            try { readControls(host); } catch (...) { host.stop(1); }
        });
        app.exec();
        result = host.exitStatus.load(std::memory_order_relaxed);
    }
#if defined(__linux__)
    currentRunLoop = nullptr;
#endif
    return result;
}
}
