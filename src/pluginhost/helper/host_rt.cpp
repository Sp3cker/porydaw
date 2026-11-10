#include "host.h"
#include "pluginhost_internal.h"
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstddef>
#ifdef __APPLE__
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <mach/thread_policy.h>
#elif defined(_WIN32)
#include <windows.h>
#include <avrt.h>
#else
#include <pthread.h>
#include <sched.h>
#endif
namespace pdph::helper {
static_assert(std::atomic<uint32_t>::is_always_lock_free && std::atomic<uint64_t>::is_always_lock_free &&
    std::atomic<bool>::is_always_lock_free, "Bridge processing requires lock-free atomics");
static_assert(sizeof(std::atomic<uint32_t>) == 4 && sizeof(std::atomic<uint64_t>) == 8 &&
    alignof(std::atomic<uint32_t>) == 4 && alignof(std::atomic<uint64_t>) == 8 &&
    alignof(pdpb_shared) == 8, "C++ wire atomic size and alignment");
static_assert(sizeof(pdph_midi_event) == 16 && sizeof(pdph_process_context) == 72);
static_assert(offsetof(pdpb_shared, heartbeat) == 24 && offsetof(pdpb_shared, ctx) == 40 &&
    offsetof(pdpb_shared, in) == 116 && offsetof(pdpb_shared, out) == 65664 && sizeof(pdpb_shared) == 131200,
    "C++ helper must match the C shared-memory layout");
void setRealtimePriority(double rate, uint32_t periodFrames) {
#ifdef __APPLE__
    mach_timebase_info_data_t timebase = {};
    mach_timebase_info(&timebase);
    const double ticks = (static_cast<double>(periodFrames) / rate) * 1e9 * timebase.denom / timebase.numer;
    thread_time_constraint_policy_data_t policy = {};
    policy.period = static_cast<uint32_t>((std::min)(ticks, static_cast<double>(UINT32_MAX)));
    policy.computation = (std::max)(1u, policy.period / 2);
    policy.constraint = (std::max)(policy.computation, policy.period);
    policy.preemptible = true;
    const auto thread = mach_thread_self();
    thread_policy_set(thread, THREAD_TIME_CONSTRAINT_POLICY, reinterpret_cast<thread_policy_t>(&policy), THREAD_TIME_CONSTRAINT_POLICY_COUNT);
    mach_port_deallocate(mach_task_self(), thread);
#elif defined(_WIN32)
    (void)rate; (void)periodFrames;
    // The returned task handle is released when this processing thread exits.
#else
    (void)rate; (void)periodFrames;
    sched_param priority = {};
    priority.sched_priority = 80;
    if (pthread_setschedparam(pthread_self(), SCHED_FIFO, &priority) != 0)
        pthread_setschedparam(pthread_self(), SCHED_RR, &priority);
#endif
}
void processRequests(Host& host) {
#ifdef _WIN32
    DWORD taskIndex = 0;
    HANDLE priorityTask = AvSetMmThreadCharacteristicsW(L"Pro Audio", &taskIndex);
#endif
    std::array<pdph_midi_event, PDPB_MAX_EVENTS> input{};
    double configuredRate = 0;
    uint32_t configuredPeriod = 0;
    auto* shared = pdpb_channel_shared(host.channel);
    while (!host.stopping.load(std::memory_order_acquire)) {
        pdpb_tick_heartbeat(host.channel);
        const auto wait = pdpb_wait_request(host.channel, 100);
        if (wait == PDPB_ERROR) {
            host.exitStatus.store(1, std::memory_order_relaxed);
            host.stopping.store(true, std::memory_order_release);
            break;
        }
        if (host.stopping.load(std::memory_order_acquire)) break;
        if (host.parameterFlushRequested.load(std::memory_order_acquire)) {
            uint32_t owner = 0;
            if (host.processingOwner.compare_exchange_strong(owner, 1, std::memory_order_acquire)) {
                pdph_process_context context = {};
                int32_t written = 0, total = 0;
                host.parameterFlushResult = pdph_plugin_process(host.plugin, 0, &context, nullptr, 0, nullptr, 0, &written, &total);
                host.processingOwner.store(2, std::memory_order_release);
                host.parameterFlushRequested.store(false, std::memory_order_release);
            }
        }
        if (wait != PDPB_OK) continue;
        if (host.controlPending.load(std::memory_order_acquire)) {
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
            continue;
        }
        uint32_t expected = 0;
        if (!host.processingOwner.compare_exchange_strong(expected, 1, std::memory_order_acquire)) {
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
            continue;
        }
        const uint32_t sequence = pdpb_request_sequence(host.channel);
        if (sequence == pdpb_reply_sequence(host.channel)) {
            host.processingOwner.store(0, std::memory_order_release);
            continue;
        }
        if (configuredRate != host.sampleRate || configuredPeriod != host.periodFrames) {
            setRealtimePriority(host.sampleRate, host.periodFrames);
            configuredRate = host.sampleRate; configuredPeriod = host.periodFrames;
        }
        shared->status = PDPH_OK; shared->out_written = 0; shared->out_total = 0;
        if (!host.plugin || host.plugin->phase != pdph::PluginPhase::processing) shared->status = PDPH_ERR_STATE;
        else if (shared->frames <= 0 || shared->frames > PDPB_MAX_CHUNK ||
            shared->in_count < 0 || shared->in_count > PDPB_MAX_EVENTS) shared->status = PDPH_ERR_ARGUMENT;
        else {
            if (shared->ctx.project_samples > INT64_MAX - shared->frames) shared->status = PDPH_ERR_ARGUMENT;
            for (int32_t index = 0; index < shared->in_count; ++index) {
                if (shared->in[index].sample_offset < 0 || shared->in[index].sample_offset >= shared->frames) {
                    shared->status = PDPH_ERR_ARGUMENT; break;
                }
            }
            for (int32_t offset = 0; offset < shared->frames && shared->status == PDPH_OK;) {
                const int32_t frames = (std::min)(shared->frames - offset, host.plugin->maxBlock);
                int32_t count = 0;
                for (int32_t index = 0; index < shared->in_count; ++index) {
                    const auto& event = shared->in[index];
                    if (event.sample_offset < offset || event.sample_offset >= offset + frames) continue;
                    input[count] = event; input[count++].sample_offset -= offset;
                }
                auto context = shared->ctx;
                context.project_samples += offset;
                const double advance = offset / host.sampleRate * context.tempo / 60.;
                if (context.state_flags & PDPH_CTX_PROJECT_TIME_MUSIC_VALID) context.ppq_position += advance;
                if ((context.state_flags & PDPH_CTX_BAR_POSITION_VALID) && context.time_sig_num > 0 && context.time_sig_den > 0) {
                    const double barLength = context.time_sig_num * 4. / context.time_sig_den;
                    context.bar_start_ppq += std::floor((context.ppq_position - context.bar_start_ppq) / barLength) * barLength;
                }
                int32_t written = 0, total = 0;
                const int32_t start = shared->out_written;
                shared->status = pdph_plugin_process(host.plugin, frames, &context, input.data(), count,
                    shared->out + start, PDPB_MAX_EVENTS - start, &written, &total);
                for (int32_t index = 0; index < written; ++index) {
                    auto& event = shared->out[start + index];
                    if (event.sample_offset < 0 || event.sample_offset >= frames) {
                        shared->status = PDPH_ERR_SDK; break;
                    }
                    event.sample_offset += offset;
                }
                shared->out_written += written;
                shared->out_total = static_cast<int32_t>((std::min)(static_cast<int64_t>(INT32_MAX),
                    static_cast<int64_t>(shared->out_total) + total));
                offset += frames;
            }
        }
        if (shared->status != PDPH_OK) { shared->out_written = 0; shared->out_total = 0; }
        pdpb_post_reply(host.channel, sequence);
        host.processingOwner.store(0, std::memory_order_release);
    }
#ifdef _WIN32
    if (priorityTask) AvRevertMmThreadCharacteristics(priorityTask);
#endif
}
}
