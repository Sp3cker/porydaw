#include <QtCore/QCoreApplication>
#include <QtCore/QTimer>
#include <QtCore/QVariant>
#include <QtGui/QGuiApplication>
#include <QtGui/QWindow>
#include <QtQuick/QQuickWindow>

#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <dlfcn.h>
#include <mach/mach.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>

namespace {

using MallocLogger = void(uint32_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uint32_t);

std::atomic<uint64_t> allocationCount{0};
std::atomic<uint64_t> allocationBytes{0};
uint64_t constructorNs = 0;
uint64_t applicationNs = 0;
uint64_t firstFrameNs = 0;
uint64_t songOpenFrameNs = 0;
uint64_t settledFrameNs = 0;
uint64_t frameCount = 0;
uint64_t settleMs = 500;
uint64_t timeoutMs = 60000;
const char *outputPath = nullptr;
QTimer *settleTimer = nullptr;
QObject *session = nullptr;

uint64_t nowNs()
{
    return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
}

void countAllocation(uint32_t type, uintptr_t, uintptr_t size, uintptr_t reallocSize, uintptr_t,
                     uint32_t)
{
    constexpr uint32_t allocate = 2;
    constexpr uint32_t deallocate = 4;
    if (!(type & allocate))
        return;
    allocationCount.fetch_add(1, std::memory_order_relaxed);
    allocationBytes.fetch_add((type & deallocate) ? reallocSize : size, std::memory_order_relaxed);
}

uint64_t footprintBytes()
{
    task_vm_info_data_t info{};
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, reinterpret_cast<task_info_t>(&info), &count) !=
        KERN_SUCCESS)
        return 0;
    return info.phys_footprint;
}

[[noreturn]] void finish(const char *status)
{
    rusage usage{};
    getrusage(RUSAGE_SELF, &usage);
    const double cpuMs = (usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1000.0 +
                         (usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1000.0;
    FILE *file = std::fopen(outputPath, "w");
    if (file) {
        std::fprintf(file,
                     "{\"status\":\"%s\",\"constructor_ns\":%llu,\"application_ns\":%llu,"
                     "\"first_frame_ns\":%llu,\"song_open_frame_ns\":%llu,"
                     "\"settled_frame_ns\":%llu,\"frames\":%llu,\"cpu_ms\":%.3f,"
                     "\"maxrss_bytes\":%ld,\"footprint_bytes\":%llu,"
                     "\"allocations\":%llu,\"allocated_bytes\":%llu}\n",
                     status, static_cast<unsigned long long>(constructorNs),
                     static_cast<unsigned long long>(applicationNs),
                     static_cast<unsigned long long>(firstFrameNs),
                     static_cast<unsigned long long>(songOpenFrameNs),
                     static_cast<unsigned long long>(settledFrameNs),
                     static_cast<unsigned long long>(frameCount), cpuMs,
                     static_cast<long>(usage.ru_maxrss),
                     static_cast<unsigned long long>(footprintBytes()),
                     static_cast<unsigned long long>(allocationCount.load()),
                     static_cast<unsigned long long>(allocationBytes.load()));
        std::fclose(file);
    }
    std::fflush(nullptr);
    _exit(0);
}

bool songOpen(QQuickWindow *window)
{
    if (!session) {
        QObject *shell = window->findChild<QObject *>(QStringLiteral("shellPresenter"));
        if (!shell)
            return false;
        session = shell->property("session").value<QObject *>();
        if (!session)
            return false;
    }
    return session->property("songOpen").toBool();
}

void frameOnMainThread(QQuickWindow *window, uint64_t swappedNs)
{
    ++frameCount;
    if (!songOpenFrameNs) {
        if (!songOpen(window))
            return;
        songOpenFrameNs = swappedNs;
    }
    settledFrameNs = swappedNs;
    settleTimer->start();
}

class WindowWatcher final : public QObject
{
  public:
    using QObject::QObject;

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (event->type() == QEvent::Expose || event->type() == QEvent::Show) {
            if (auto *window = qobject_cast<QQuickWindow *>(watched))
                attach(window);
        }
        return false;
    }

  private:
    void attach(QQuickWindow *window)
    {
        if (attached)
            return;
        attached = window;
        QObject::connect(
            window, &QQuickWindow::frameSwapped, window,
            [window] {
                const uint64_t swapped = nowNs();
                if (!firstFrameNs)
                    firstFrameNs = swapped;
                QMetaObject::invokeMethod(
                    qApp, [window, swapped] { frameOnMainThread(window, swapped); },
                    Qt::QueuedConnection);
            },
            Qt::DirectConnection);
    }

    QQuickWindow *attached = nullptr;
};

void applicationConstructed()
{
    applicationNs = nowNs();
    auto *app = QCoreApplication::instance();
    app->installEventFilter(new WindowWatcher(app));
    settleTimer = new QTimer(app);
    settleTimer->setSingleShot(true);
    settleTimer->setInterval(static_cast<int>(settleMs));
    QObject::connect(settleTimer, &QTimer::timeout, app, [] { finish("ok"); });
    auto *deadline = new QTimer(app);
    deadline->setSingleShot(true);
    deadline->setInterval(static_cast<int>(timeoutMs));
    QObject::connect(deadline, &QTimer::timeout, app, [] { finish("timeout"); });
    deadline->start();
}

__attribute__((constructor)) void probeInit()
{
    constructorNs = nowNs();
    outputPath = std::getenv("PORYDAW_STARTUP_PROBE_OUT");
    if (!outputPath)
        return;
    if (const char *value = std::getenv("PORYDAW_STARTUP_PROBE_SETTLE_MS"))
        settleMs = std::strtoull(value, nullptr, 10);
    if (const char *value = std::getenv("PORYDAW_STARTUP_PROBE_TIMEOUT_MS"))
        timeoutMs = std::strtoull(value, nullptr, 10);
    if (std::getenv("PORYDAW_STARTUP_PROBE_COUNT_ALLOCATIONS")) {
        if (auto **logger = static_cast<MallocLogger **>(dlsym(RTLD_DEFAULT, "malloc_logger")))
            *logger = countAllocation;
    }
    qAddPreRoutine(applicationConstructed);
}

} // namespace
