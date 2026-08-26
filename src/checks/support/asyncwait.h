#pragma once

#include <QEventLoop>
#include <QTimer>
#include <atomic>
#include <memory>

namespace checks::async_wait {

enum class Result {
    Ready,
    Destroyed,
    TimedOut,
};

template <typename IsLive, typename IsReady>
Result waitUntil(IsLive isLive, IsReady isReady, int timeoutMs = 30000, int pollMs = 10)
{
    QEventLoop loop;
    QTimer poll;
    QTimer timeout;
    Result result = Result::TimedOut;
    const auto check = [&] {
        if (!isLive())
            result = Result::Destroyed;
        else if (isReady())
            result = Result::Ready;
        else
            return;
        loop.quit();
    };
    QObject::connect(&poll, &QTimer::timeout, &loop, check);
    QObject::connect(&timeout, &QTimer::timeout, &loop, &QEventLoop::quit);
    timeout.setSingleShot(true);
    poll.start(pollMs);
    timeout.start(timeoutMs);
    check();
    if (result == Result::TimedOut)
        loop.exec();
    poll.stop();
    timeout.stop();
    return result;
}

template <typename Start>
bool waitForBoolCompletion(Start start, int timeoutMs = 30000, int pollMs = 1)
{
    struct CompletionState {
        std::atomic_bool completed = false;
        std::atomic_bool succeeded = false;
    };
    const auto state = std::make_shared<CompletionState>();
    start([state](bool succeeded) {
        state->succeeded.store(succeeded, std::memory_order_relaxed);
        state->completed.store(true, std::memory_order_release);
    });
    const auto result = waitUntil(
        [] { return true; }, [state] { return state->completed.load(std::memory_order_acquire); },
        timeoutMs, pollMs);
    return result == Result::Ready && state->succeeded.load(std::memory_order_relaxed);
}

} // namespace checks::async_wait
