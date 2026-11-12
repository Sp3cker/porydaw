#include "host.h"
#include "editor.h"
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

namespace pdph::helper {
namespace {
using namespace std::chrono_literals;
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
Host::Host() {
    for (uint32_t index = 0; index < callbackSlots.size(); ++index) callbackSlots[index].sequence.store(index, std::memory_order_relaxed);
    installEditors();
}
Host::~Host() {
    stop(exitStatus.load(std::memory_order_relaxed));
    if (reader.joinable()) reader.join();
    if (realtime.joinable()) realtime.join();
    if (plugin) pdph_plugin_destroy(plugin);
    shutdownEditors();
    if (module) pdph_module_close(module);
    pdpb_channel_close(channel);
}
void Host::stop(int status) {
    if (status) exitStatus.store(status, std::memory_order_relaxed);
    stopping.store(true, std::memory_order_seq_cst);
    if (channel) { pdpb_wake_request(channel); pdpb_post_signal(channel); }
    { std::lock_guard<std::mutex> lock(controlMutex); }
    controlDone.notify_all();
    QMetaObject::invokeMethod(&context, [] { QCoreApplication::quit(); }, Qt::QueuedConnection);
}
void Host::finishControl() {
    { std::lock_guard<std::mutex> lock(controlMutex); controlInFlight = false; }
    controlDone.notify_all();
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
        { std::lock_guard<std::mutex> lock(host.controlMutex); host.controlInFlight = true; }
        if (!QMetaObject::invokeMethod(&host.context, [&host, frame = std::move(frame)]() mutable {
            try { if (!host.stopping.load(std::memory_order_acquire)) dispatch(host, std::move(frame)); }
            catch (...) { host.stop(1); }
            host.finishControl();
        }, Qt::QueuedConnection)) { host.stop(1); return; }
        // Stop also notifies, so a frame the quitting loop never runs cannot strand the reader.
        std::unique_lock<std::mutex> lock(host.controlMutex);
        host.controlDone.wait(lock, [&host] {
            return !host.controlInFlight || host.stopping.load(std::memory_order_acquire);
        });
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
    int result = 1;
    {
        Host host;
        if (pdpb_channel_open(channelName.constData(), &host.channel) != PDPB_OK) {
            std::fprintf(stderr, "Could not open plugin bridge channel\n"); return 1;
        }
        host.resume();
        host.realtime = std::thread([&host] { processRequests(host); });
        const char ready[4] = {PDPB_VERSION, 0, 0, 0};
        if (!sendFrame(PDPB_READY, 0, {QByteArrayView(ready, 4)})) return 1;
        host.reader = std::thread([&host] {
            try { readControls(host); } catch (...) { host.stop(1); }
        });
        app.exec();
        result = host.exitStatus.load(std::memory_order_relaxed);
    }
    return result;
}
}
