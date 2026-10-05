/* Checks-only macOS recorder; never linked into the application. */
/* ABI: Apple libmalloc c49dafa25f1efe8607701ae6014a663ad2ee437f private/stack_logging.h and src/malloc.c. */
#define _DARWIN_C_SOURCE 1
#include <dlfcn.h>
#include <errno.h>
#include <inttypes.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
static FILE *g_report_output;
static FILE *pda_output(void) {
    if (!g_report_output) {
        const char *path = getenv("PORYDAW_PROFILE_OUTPUT");
        g_report_output = path ? fopen(path, "a") : stderr;
        if (!g_report_output) { perror("profile output"); _exit(74); }
    }
    return g_report_output;
}

#if !defined(__APPLE__)
#error This disposable helper requires Darwin.
#endif
_Static_assert(ATOMIC_POINTER_LOCK_FREE == 2, "Logger pointer operations must be lock-free");
_Static_assert(ATOMIC_BOOL_LOCK_FREE == 2, "Logger error flag must be lock-free");
#ifndef PDA_CPU_ONLY
#define PDA_CPU_ONLY 0
#endif
#define PDA_EXPORT __attribute__((visibility("default")))

/* Verified private ABI, not declared by the installed public malloc.h. */
typedef void pda_malloc_logger_t(uint32_t, uintptr_t, uintptr_t, uintptr_t,
                               uintptr_t, uint32_t);
enum { PDA_ALLOC = 2, PDA_DEALLOC = 4, PDA_ZONE = 8, PDA_CLEARED = 64 };
enum pda_error { PDA_OK, PDA_ABI, PDA_OVERFLOW, PDA_NESTED };
struct pda_state {
    bool enabled, cpuvalid;
    enum pda_error error;
    uint64_t allocations, allocatedbytes, frees, reallocations, reallocinplace;
    uint64_t failedallocations, failedreallocations, segments;
    uint64_t cpu_start_ns, cpu_ns, threadid;
};

static pthread_key_t g_state_key, g_disabled_key;
static bool g_keys_ready, g_runtime_validated;
static const bool g_disabled = true; /* Per-thread key points here when reentrant. */
static atomic_bool g_guard_failed;
static pda_malloc_logger_t **g_logger_slot;
static pda_malloc_logger_t *g_previous;
static const char *g_hook_reason = "constructor_not_completed";

PDA_EXPORT void pda_profile_reset(void);
PDA_EXPORT void pda_profile_begin(void);
PDA_EXPORT void pda_profile_pause(void);
PDA_EXPORT void pda_profile_report(const char *label, uint64_t operations);

static void pda_logger(uint32_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uint32_t);

static bool pda_hook_installed(void)
{
    return g_logger_slot &&
        __atomic_load_n(g_logger_slot, __ATOMIC_RELAXED) == pda_logger;
}

/* Used only by helper entry points, never by the malloc callback. */
static bool pda_cpu_read(uint64_t *result)
{
    struct timespec value;
    if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &value) != 0 || value.tv_sec < 0 ||
        value.tv_nsec < 0 || value.tv_nsec >= 1000000000L ||
        (uint64_t)value.tv_sec > (UINT64_MAX - (uint64_t)value.tv_nsec) / 1000000000) {
        return false;
    }
    *result = (uint64_t)value.tv_sec * 1000000000 + (uint64_t)value.tv_nsec;
    return true;
}

static struct pda_state *pda_state_get(bool create)
{
    if (!g_keys_ready) return NULL;
    struct pda_state *state = pthread_getspecific(g_state_key);
    if (!state && create) {
        /* All setup, including lazy dyld bindings, precedes capture. */
        state = calloc(1, sizeof(*state));
        if (!state) return NULL;
        state->cpuvalid = true;
        if (pthread_threadid_np(NULL, &state->threadid) != 0 ||
            pthread_setspecific(g_state_key, state) != 0) {
            free(state);
            return NULL;
        }
        uint64_t ignored;
        state->cpuvalid = pda_cpu_read(&ignored);
    }
    return state;
}

static void pda_add(struct pda_state *state, uint64_t *counter, uint64_t amount)
{
    if (UINT64_MAX - *counter < amount) {
        state->error = PDA_OVERFLOW;
    } else {
        *counter += amount;
    }
}

static void pda_count(struct pda_state *state, uint32_t type, uintptr_t arg2,
                      uintptr_t arg3, uintptr_t result)
{
    uint32_t operation = type & (PDA_ALLOC | PDA_DEALLOC);
    if (!operation) return; /* Not a heap allocation/deallocation event. */
    if (!(type & PDA_ZONE) || (type & ~(PDA_ALLOC | PDA_DEALLOC | PDA_ZONE | PDA_CLEARED))) {
        state->error = PDA_ABI; /* Do not guess another logger's argument layout. */
        return;
    }
    if (operation == (PDA_ALLOC | PDA_DEALLOC)) {
        /* realloc: arg2 = original pointer; arg3 = requested new size. */
        if (!result) {
            if (arg3 == 0 && arg2 != 0) {
                state->error = PDA_ABI; /* Direct zone zero-size result is ambiguous. */
            } else {
                pda_add(state, &state->failedallocations, 1);
                pda_add(state, &state->failedreallocations, 1);
            }
            return; /* Failure does not free the old object. */
        }
        pda_add(state, &state->allocations, 1);
        pda_add(state, &state->allocatedbytes, (uint64_t)arg3);
        pda_add(state, &state->reallocations, 1);
        if (arg2 && arg2 == result) pda_add(state, &state->reallocinplace, 1);
        if (arg2 && arg2 != result) pda_add(state, &state->frees, 1);
    } else if (operation == PDA_ALLOC) {
        /* malloc/calloc/valloc/memalign: arg2 = requested bytes. */
        if (result) {
            pda_add(state, &state->allocations, 1);
            pda_add(state, &state->allocatedbytes, (uint64_t)arg2);
        } else {
            pda_add(state, &state->failedallocations, 1);
        }
    } else if (arg2) {
        /* Free uses a bit mask, not type == 4: the zone flag is also set. */
        pda_add(state, &state->frees, 1);
    }
}

static __attribute__((noinline)) void
pda_logger(uint32_t type, uintptr_t arg1, uintptr_t arg2, uintptr_t arg3,
           uintptr_t result, uint32_t skip)
{
    /* Precreated pthread TSD avoids lazy Darwin language-TLS allocation.
     * No allocation, locks, clocks, I/O, Objective-C or stack walking in this callback. */
    const bool *disabled = pthread_getspecific(g_disabled_key);
    if (disabled && *disabled) return;
    if (pthread_setspecific(g_disabled_key, &g_disabled) != 0) {
        atomic_store_explicit(&g_guard_failed, true, memory_order_relaxed);
        return;
    }
    struct pda_state *state = pthread_getspecific(g_state_key);
    if (state && state->enabled) pda_count(state, type, arg2, arg3, result);
    if (g_previous) {
        /* One additional wrapper frame; keep original argument/event semantics. */
        g_previous(type, arg1, arg2, arg3, result, skip == UINT32_MAX ? skip : skip + 1);
    }
    if (pthread_setspecific(g_disabled_key, NULL) != 0) {
        atomic_store_explicit(&g_guard_failed, true, memory_order_relaxed);
    }
}

PDA_EXPORT void pda_profile_pause(void)
{
    struct pda_state *state = pda_state_get(false);
    if (!state || !state->enabled) return;
    state->enabled = false; /* Disable before any timing or reporting work. */
    uint64_t now;
    if (!pda_cpu_read(&now) || now < state->cpu_start_ns ||
        UINT64_MAX - state->cpu_ns < now - state->cpu_start_ns) {
        state->cpuvalid = false;
    } else {
        state->cpu_ns += now - state->cpu_start_ns;
    }
}

PDA_EXPORT void pda_profile_reset(void)
{
    pda_profile_pause();
    struct pda_state *state = pda_state_get(true);
    if (!state) return; /* Report emits unavailable, never zero. */
    uint64_t threadid = state->threadid;
    *state = (struct pda_state){ .cpuvalid = true, .threadid = threadid };
}

PDA_EXPORT void pda_profile_begin(void)
{
    struct pda_state *state = pda_state_get(true);
    if (!state) return;
    if (state->enabled) {
        pda_profile_pause();
        state->error = PDA_NESTED;
        return;
    }
    if ((!PDA_CPU_ONLY && !pda_hook_installed()) || !g_runtime_validated || state->error != PDA_OK ||
        atomic_load_explicit(&g_guard_failed, memory_order_relaxed)) return;
    pda_add(state, &state->segments, 1);
    if (state->error != PDA_OK) return;
    if (!pda_cpu_read(&state->cpu_start_ns)) state->cpuvalid = false;
    state->enabled = true; /* Begin app work only after helper setup/timing. */
}

static void pda_json_string(const char *string)
{
    fputc('"', pda_output());
    if (string) {
        for (const unsigned char *p = (const unsigned char *)string; *p; ++p) {
            if (*p == '"' || *p == '\\') fprintf(pda_output(), "\\%c", *p);
            else if (*p < 32) fprintf(pda_output(), "\\u%04x", (unsigned)*p);
            else fputc(*p, pda_output());
        }
    }
    fputc('"', pda_output());
}

PDA_EXPORT void pda_profile_report(const char *label, uint64_t operations)
{
    pda_profile_pause(); /* Reporting is always outside capture and CPU window. */
    struct pda_state *state = pda_state_get(false);
    bool installed = pda_hook_installed();
    const char *reason = "ok";
    if (!g_runtime_validated) reason = g_hook_reason;
    else if (!PDA_CPU_ONLY && !installed) reason = "hook_replaced";
    else if (atomic_load_explicit(&g_guard_failed, memory_order_relaxed)) reason = "reentrancy_guard_failed";
    else if (!state) reason = "thread_state_unavailable";
    else if (state->error == PDA_ABI) reason = "unsupported_event_abi";
    else if (state->error == PDA_OVERFLOW) reason = "counter_overflow";
    else if (state->error == PDA_NESTED) reason = "nested_begin";
    else if (!state->segments) reason = "no_capture_segment";
    bool valid = (PDA_CPU_ONLY || installed) && g_runtime_validated && state && state->segments &&
        state->error == PDA_OK && !atomic_load_explicit(&g_guard_failed, memory_order_relaxed);
    flockfile(pda_output());
    if (PDA_CPU_ONLY) {
        fputs("{\"pda\":\"cpu\",\"label\":", pda_output());
        pda_json_string(label);
        fprintf(pda_output(), ",\"operations\":%" PRIu64 ",\"threadid\":%" PRIu64
                ",\"hookinstalled\":false,\"runtimevalidated\":%s,\"valid\":%s,\"reason\":",
                operations, state ? state->threadid : 0,
                g_runtime_validated ? "true" : "false", valid ? "true" : "false");
        pda_json_string(reason);
        fputs(",\"capturedsegments\":", pda_output());
        if (valid) fprintf(pda_output(), "%" PRIu64, state->segments);
        else fputs("null", pda_output());
        fputs(",\"cpu_ns\":", pda_output());
        if (valid && state->cpuvalid) fprintf(pda_output(), "%" PRIu64, state->cpu_ns);
        else fputs("null", pda_output());
        fprintf(pda_output(), ",\"cpuvalid\":%s,\"cpu_instrumented\":true}\n",
                valid && state->cpuvalid ? "true" : "false");
        funlockfile(pda_output());
        return;
    }
    fputs("{\"pda\":\"phase\",\"label\":", pda_output());
    pda_json_string(label);
    fprintf(pda_output(), ",\"operations\":%" PRIu64 ",\"threadid\":%" PRIu64
            ",\"hookinstalled\":%s,\"runtimevalidated\":%s,\"previouslogger\":%s,\"valid\":%s,\"reason\":",
            operations, state ? state->threadid : 0, installed ? "true" : "false",
            g_runtime_validated ? "true" : "false", g_previous ? "true" : "false", valid ? "true" : "false");
    pda_json_string(reason);
    if (valid) {
        fprintf(pda_output(), ",\"allocations\":%" PRIu64 ",\"allocatedbytes\":%" PRIu64
                ",\"frees\":%" PRIu64 ",\"reallocations\":%" PRIu64 ",\"reallocinplace\":%" PRIu64
                ",\"failedallocations\":%" PRIu64 ",\"failedreallocations\":%" PRIu64
                ",\"capturedsegments\":%" PRIu64,
                state->allocations, state->allocatedbytes, state->frees, state->reallocations,
                state->reallocinplace, state->failedallocations, state->failedreallocations, state->segments);
    } else {
        fputs(",\"allocations\":null,\"allocatedbytes\":null,\"frees\":null,\"reallocations\":null,"
              "\"reallocinplace\":null,\"failedallocations\":null,\"failedreallocations\":null,"
              "\"capturedsegments\":null", pda_output());
    }
    fputs(",\"cpu_ns\":", pda_output());
    if (valid && state->cpuvalid) fprintf(pda_output(), "%" PRIu64, state->cpu_ns);
    else fputs("null", pda_output());
    fprintf(pda_output(), ",\"cpuvalid\":%s,\"cpu_instrumented\":true}\n",
            valid && state->cpuvalid ? "true" : "false");
    funlockfile(pda_output());
}

static __attribute__((constructor)) void pda_install(void)
{
    int error = pthread_key_create(&g_state_key, free);
    if (!error) error = pthread_key_create(&g_disabled_key, NULL);
    if (error) { g_hook_reason = "pthread_key_creation_failed"; goto report; }
    g_keys_ready = true;
    struct pda_state *state = pda_state_get(true);
    if (!state) { g_hook_reason = "thread_state_setup_failed"; goto report; }
    if (PDA_CPU_ONLY) {
        g_runtime_validated = state->cpuvalid;
        g_hook_reason = g_runtime_validated ? "ok" : "thread_clock_unavailable";
        goto report;
    }
    g_logger_slot = dlsym(RTLD_DEFAULT, "malloc_logger");
    void *(*allocate)(size_t) = (void *(*)(size_t))dlsym(RTLD_DEFAULT, "malloc");
    void *(*resize)(void *, size_t) = (void *(*)(void *, size_t))dlsym(RTLD_DEFAULT, "realloc");
    void (*deallocate)(void *) = (void (*)(void *))dlsym(RTLD_DEFAULT, "free");
    if (!g_logger_slot || !allocate || !resize || !deallocate) {
        g_hook_reason = "required_runtime_symbol_unavailable";
        goto report;
    }
    g_previous = __atomic_load_n(g_logger_slot, __ATOMIC_RELAXED);
    pda_malloc_logger_t *expected = g_previous;
    if (!__atomic_compare_exchange_n(g_logger_slot, &expected, pda_logger, false,
                                     __ATOMIC_RELAXED, __ATOMIC_RELAXED)) {
        g_hook_reason = "concurrent_logger_installation";
        goto report;
    }
    /* Warm allocator paths, then prove transient malloc/free and realloc ABI.
     * Dynamic function pointers prevent malloc/free-pair elimination. */
    void *warm = allocate(37);
    if (!warm) { g_hook_reason = "calibration_allocation_failed"; goto report; }
    deallocate(warm);
    state->enabled = true;
    void *pair = allocate(37);
    bool pair_allocated = pair != NULL;
    if (pair) deallocate(pair);
    state->enabled = false;
    bool pair_ok = pair_allocated && state->allocations == 1 && state->allocatedbytes == 37 &&
        state->frees == 1 && state->error == PDA_OK;
    pda_profile_reset();
    state->enabled = true;
    void *original = allocate(37);
    uintptr_t original_address = (uintptr_t)original;
    void *resized = original ? resize(original, 113) : NULL;
    bool resize_succeeded = resized != NULL;
    bool moved = resize_succeeded && original_address != (uintptr_t)resized;
    if (resized) deallocate(resized);
    else if (original) deallocate(original);
    state->enabled = false;
    g_runtime_validated = pair_ok && resize_succeeded && pda_hook_installed() &&
        state->allocations == 2 && state->allocatedbytes == 150 &&
        state->frees == (moved ? 2u : 1u) && state->reallocations == 1 &&
        state->reallocinplace == (moved ? 0u : 1u) && state->error == PDA_OK &&
        !atomic_load_explicit(&g_guard_failed, memory_order_relaxed);
    g_hook_reason = g_runtime_validated ? "ok" : "runtime_calibration_failed";
    pda_profile_reset();
report:
    fprintf(pda_output(), "{\"pda\":\"hook\",\"mode\":\"%s\",\"hookinstalled\":%s,\"runtimevalidated\":%s,"
            "\"previouslogger\":%s,\"reason\":\"%s\"}\n",
            PDA_CPU_ONLY ? "cpu" : "allocations", pda_hook_installed() ? "true" : "false",
            g_runtime_validated ? "true" : "false",
            g_previous ? "true" : "false", g_hook_reason);
}

