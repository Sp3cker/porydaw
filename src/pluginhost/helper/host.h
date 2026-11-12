#pragma once
#include "pluginhost_internal.h"
#include <QByteArray>
#include <QByteArrayView>
#include <QObject>
#include <QString>
#include <array>
#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <initializer_list>
#include <mutex>
#include <thread>
namespace pdph::helper {
struct Frame { uint32_t type = 0, request = 0; QByteArray payload; };
struct CallbackEvent { uint32_t type = 0, value = 0; };
struct CallbackSlot { std::atomic<uint32_t> sequence{0}; CallbackEvent event; };
struct Host {
    Host();
    ~Host();
    Host(const Host&) = delete;
    Host& operator=(const Host&) = delete;
    QObject context;
    pdpb_channel* channel = nullptr;
    pdph_module module = nullptr;
    pdph_plugin plugin = nullptr;
    pdph::StateStream stateStream;
    std::thread reader, realtime;
    std::atomic<bool> stopping{false}, controlPending{false}, drainPosted{false};
    std::atomic<int> exitStatus{0};
    // 0 idle, 1 RT processes, 2 a main lifecycle lease excludes processing; other control runs beside RT.
    std::atomic<uint32_t> processingOwner{2};
    // Main thread only: a drain nested in a lease defers until the lease ends.
    bool leaseHeld = false, drainAfterLease = false;
    // The reader blocks here until the main thread finishes the frame it posted.
    std::mutex controlMutex;
    std::condition_variable controlDone;
    bool controlInFlight = false;
    std::array<CallbackSlot, PDPB_MAX_EVENTS> callbackSlots{};
    std::atomic<uint32_t> callbackWrite{0};
    uint32_t callbackRead = 0;
    std::atomic<bool> callbacksOverflowed{false};
    std::atomic<bool> parameterFlushRequested{false};
    int32_t parameterFlushResult = PDPH_OK;
    double sampleRate = 48000;
    uint32_t periodFrames = 256;
    bool quiesce();
    void resume();
    void releaseProcessing();
    bool flushParameters();
    void enqueue(uint32_t type, uint32_t value);
    void scheduleDrain();
    void drainCallbacks();
    void finishControl();
    void stop(int status);
};
bool sendFrame(uint32_t type, uint32_t request, std::initializer_list<QByteArrayView> payloads);
void dispatch(Host&, Frame);
void readControls(Host&);
void processRequests(Host&);
void setRealtimePriority(double rate, uint32_t periodFrames);
int run(int argc, char** argv);
#ifdef __APPLE__
void setAccessoryPolicy();
#endif
}
