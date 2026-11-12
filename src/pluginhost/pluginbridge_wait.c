#include "pluginbridge.h"
#include <errno.h>
#include <limits.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <synchapi.h>
#include <wchar.h>
#else
#include <fcntl.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#ifdef __APPLE__
#include <os/os_sync_wait_on_address.h>
#else
#include <linux/futex.h>
#include <sys/syscall.h>
#endif
#endif
_Static_assert(sizeof(pdph_midi_event) == 16 && sizeof(pdph_process_context) == 72, "Task 6 POD ABI");
_Static_assert(sizeof(_Atomic(uint32_t)) == 4 && sizeof(_Atomic(uint64_t)) == 8, "Wire atomic ABI");
_Static_assert(_Alignof(_Atomic(uint32_t)) == 4 && _Alignof(_Atomic(uint64_t)) == 8 &&
    _Alignof(pdpb_shared) == 8, "Wire atomic alignment");
_Static_assert(offsetof(pdpb_shared, heartbeat) == 24 && offsetof(pdpb_shared, ctx) == 40 &&
    offsetof(pdpb_shared, in) == 116 && offsetof(pdpb_shared, out) == 65664 && sizeof(pdpb_shared) == 131200,
    "C shared-memory wire layout");
struct pdpb_channel {
    pdpb_shared* shared;
    int owner;
    char name[192];
    _Atomic(uint32_t) signal_count;
#ifdef _WIN32
    HANDLE mapping, request, reply;
#else
    int fd;
#endif
};
uint64_t pdpb_monotonic_ns(void) {
#ifdef _WIN32
    LARGE_INTEGER count, frequency;
    QueryPerformanceCounter(&count); QueryPerformanceFrequency(&frequency);
    return (uint64_t)(count.QuadPart / frequency.QuadPart) * 1000000000ull +
        (uint64_t)(count.QuadPart % frequency.QuadPart) * 1000000000ull / (uint64_t)frequency.QuadPart;
#else
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint64_t)now.tv_sec * 1000000000ull + (uint64_t)now.tv_nsec;
#endif
}
int32_t pdpb_terminate_process(uint32_t pid) {
    if (!pid || pid > INT32_MAX) return PDPB_ERROR;
#ifdef _WIN32
    HANDLE process = OpenProcess(PROCESS_TERMINATE, FALSE, pid);
    if (!process) return PDPB_ERROR;
    BOOL ok = TerminateProcess(process, 1); CloseHandle(process);
    return ok ? PDPB_OK : PDPB_ERROR;
#else
    return kill((pid_t)pid, SIGKILL) == 0 ? PDPB_OK : PDPB_ERROR;
#endif
}
int32_t pdpb_channel_unlink(pdpb_channel* channel) {
    if (!channel) return PDPB_ERROR;
#ifndef _WIN32
    if (shm_unlink(channel->name) != 0 && errno != ENOENT) return PDPB_ERROR;
#endif
    return PDPB_OK;
}
void pdpb_channel_close(pdpb_channel* channel) {
    if (!channel) return;
#ifdef _WIN32
    if (channel->shared) UnmapViewOfFile(channel->shared);
    if (channel->request) CloseHandle(channel->request);
    if (channel->reply) CloseHandle(channel->reply);
    if (channel->mapping) CloseHandle(channel->mapping);
#else
    if (channel->shared) munmap(channel->shared, sizeof(pdpb_shared));
    if (channel->fd >= 0) close(channel->fd);
    if (channel->owner) pdpb_channel_unlink(channel);
#endif
    free(channel);
}
static int32_t channel_map(const char* name, pdpb_channel** out, int create) {
    if (!out) return PDPB_ERROR;
    *out = NULL;
    if (!name || !name[0] || strlen(name) >= sizeof(((pdpb_channel*)0)->name)) return PDPB_ERROR;
    pdpb_channel* channel = calloc(1, sizeof(*channel));
    if (!channel) return PDPB_ERROR;
    strcpy(channel->name, name);
    atomic_init(&channel->signal_count, 0);
#ifndef _WIN32
    channel->fd = -1;
#endif
#ifdef _WIN32
    wchar_t base[192], object[200];
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, name, -1, base, 192)) goto failed;
    if (wcsncmp(base, L"Local\\porydaw-", 14) != 0) goto failed;
    swprintf(object, 200, L"%ls-shm", base);
    if (create) {
        channel->mapping = CreateFileMappingW(INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0, sizeof(pdpb_shared), object);
        if (!channel->mapping || GetLastError() == ERROR_ALREADY_EXISTS) goto failed;
    } else channel->mapping = OpenFileMappingW(FILE_MAP_ALL_ACCESS, FALSE, object);
    if (!channel->mapping) goto failed;
    swprintf(object, 200, L"%ls-req", base);
    channel->request = create ? CreateSemaphoreW(NULL, 0, 1, object) : OpenSemaphoreW(SYNCHRONIZE | SEMAPHORE_MODIFY_STATE, FALSE, object);
    if (!channel->request || (create && GetLastError() == ERROR_ALREADY_EXISTS)) goto failed;
    swprintf(object, 200, L"%ls-rep", base);
    channel->reply = create ? CreateSemaphoreW(NULL, 0, 1, object) : OpenSemaphoreW(SYNCHRONIZE | SEMAPHORE_MODIFY_STATE, FALSE, object);
    if (!channel->reply || (create && GetLastError() == ERROR_ALREADY_EXISTS)) goto failed;
    channel->shared = MapViewOfFile(channel->mapping, FILE_MAP_ALL_ACCESS, 0, 0, sizeof(pdpb_shared));
    if (!channel->shared) goto failed;
#else
    if (name[0] != '/' || strchr(name + 1, '/')) goto failed;
    channel->fd = shm_open(name, create ? O_RDWR | O_CREAT | O_EXCL : O_RDWR, 0600);
    if (channel->fd < 0) goto failed;
    channel->owner = create;
    if (create && ftruncate(channel->fd, sizeof(pdpb_shared)) != 0) goto failed;
    struct stat info;
    if (fstat(channel->fd, &info) != 0 || info.st_size < (off_t)sizeof(pdpb_shared)) goto failed;
    void* mapping = mmap(NULL, sizeof(pdpb_shared), PROT_READ | PROT_WRITE, MAP_SHARED, channel->fd, 0);
    if (mapping == MAP_FAILED) goto failed;
    channel->shared = mapping;
#endif
    channel->owner = create;
    // MSVC's C atomics report "sometimes lock-free"; require it for every actual object.
    if (!atomic_is_lock_free(&channel->shared->request_seq) || !atomic_is_lock_free(&channel->shared->reply_seq) ||
        !atomic_is_lock_free(&channel->shared->request_word) || !atomic_is_lock_free(&channel->shared->reply_word) ||
        !atomic_is_lock_free(&channel->shared->heartbeat) || !atomic_is_lock_free(&channel->signal_count)) goto failed;
    if (create) {
        memset(channel->shared, 0, sizeof(pdpb_shared));
        atomic_init(&channel->shared->request_seq, 0); atomic_init(&channel->shared->reply_seq, 0);
        atomic_init(&channel->shared->request_word, 0); atomic_init(&channel->shared->reply_word, 0);
        atomic_init(&channel->shared->heartbeat, 0);
        channel->shared->magic = PDPB_MAGIC; channel->shared->version = PDPB_VERSION;
    } else if (channel->shared->magic != PDPB_MAGIC || channel->shared->version != PDPB_VERSION) goto failed;
    *out = channel;
    return PDPB_OK;
failed:
    pdpb_channel_close(channel);
    return PDPB_ERROR;
}
int32_t pdpb_channel_create(const char* name, pdpb_channel** out) { return channel_map(name, out, 1); }
int32_t pdpb_channel_open(const char* name, pdpb_channel** out) { return channel_map(name, out, 0); }
pdpb_shared* pdpb_channel_shared(pdpb_channel* c) { return c->shared; }
uint32_t pdpb_request_sequence(const pdpb_channel* c) { return atomic_load_explicit(&c->shared->request_seq, memory_order_acquire); }
uint32_t pdpb_reply_sequence(const pdpb_channel* c) { return atomic_load_explicit(&c->shared->reply_seq, memory_order_acquire); }
uint64_t pdpb_heartbeat(const pdpb_channel* c) { return atomic_load_explicit(&c->shared->heartbeat, memory_order_relaxed); }
void pdpb_tick_heartbeat(pdpb_channel* c) { atomic_fetch_add_explicit(&c->shared->heartbeat, 1, memory_order_relaxed); }
pdph_process_context* pdpb_request_context(pdpb_channel* c) { return &c->shared->ctx; }
pdph_midi_event* pdpb_request_events(pdpb_channel* c) { return c->shared->in; }
const pdph_midi_event* pdpb_reply_events(const pdpb_channel* c) { return c->shared->out; }
void pdpb_set_request(pdpb_channel* c, int32_t frames, int32_t count) { c->shared->frames = frames; c->shared->in_count = count; }
int32_t pdpb_reply_status(const pdpb_channel* c) { return c->shared->status; }
int32_t pdpb_reply_written(const pdpb_channel* c) { return c->shared->out_written; }
int32_t pdpb_reply_total(const pdpb_channel* c) { return c->shared->out_total; }
enum { WORD_REQUEST, WORD_REPLY, WORD_SIGNAL };
static _Atomic(uint32_t)* channel_word(pdpb_channel* c, int which) {
    if (which == WORD_SIGNAL) return &c->signal_count;
    return which == WORD_REPLY ? &c->shared->reply_word : &c->shared->request_word;
}
static void wake_word(pdpb_channel* c, int which) {
    _Atomic(uint32_t)* word = channel_word(c, which);
    atomic_fetch_add_explicit(word, 1, memory_order_release);
#ifdef _WIN32
    if (which == WORD_SIGNAL) WakeByAddressAll((PVOID)word);
    else ReleaseSemaphore(which == WORD_REPLY ? c->reply : c->request, 1, NULL);
#elif defined(__APPLE__)
    if (which == WORD_SIGNAL) os_sync_wake_by_address_all(word, sizeof(*word), OS_SYNC_WAKE_BY_ADDRESS_NONE);
    else os_sync_wake_by_address_any(word, sizeof(*word), OS_SYNC_WAKE_BY_ADDRESS_SHARED);
#else
    if (which == WORD_SIGNAL) syscall(SYS_futex, word, FUTEX_WAKE_PRIVATE, INT_MAX, NULL, NULL, 0);
    else syscall(SYS_futex, word, FUTEX_WAKE, 1, NULL, NULL, 0);
#endif
}
static int wait_word(pdpb_channel* c, int which, uint32_t expected, uint64_t ns) {
#ifdef _WIN32
    DWORD ms = (DWORD)((ns + 999999) / 1000000);
    if (which == WORD_SIGNAL) {
        // Compares the private count with `expected` and sleeps atomically against WakeByAddressAll.
        uint32_t compare = expected;
        if (WaitOnAddress((volatile VOID*)channel_word(c, which), &compare, sizeof(compare), ms)) return PDPB_OK;
        return GetLastError() == ERROR_TIMEOUT ? PDPB_TIMEOUT : PDPB_ERROR;
    }
    DWORD result = WaitForSingleObject(which == WORD_REPLY ? c->reply : c->request, ms);
    return result == WAIT_OBJECT_0 ? PDPB_OK : (result == WAIT_TIMEOUT ? PDPB_TIMEOUT : PDPB_ERROR);
#else
    _Atomic(uint32_t)* word = channel_word(c, which);
#ifdef __APPLE__
    int result = os_sync_wait_on_address_with_timeout(word, expected, sizeof(*word),
        which == WORD_SIGNAL ? OS_SYNC_WAIT_ON_ADDRESS_NONE : OS_SYNC_WAIT_ON_ADDRESS_SHARED,
        OS_CLOCK_MACH_ABSOLUTE_TIME, ns);
#else
    struct timespec duration = {(time_t)(ns / 1000000000), (long)(ns % 1000000000)};
    int result = (int)syscall(SYS_futex, word, which == WORD_SIGNAL ? FUTEX_WAIT_PRIVATE : FUTEX_WAIT,
        expected, &duration, NULL, 0);
#endif
    if (result >= 0 || errno == EAGAIN || errno == EINTR) return PDPB_OK;
    return errno == ETIMEDOUT ? PDPB_TIMEOUT : PDPB_ERROR;
#endif
}
int32_t pdpb_post_request(pdpb_channel* c, uint32_t* sequence) {
    uint32_t current = pdpb_request_sequence(c);
    if (pdpb_reply_sequence(c) != current) return PDPB_BUSY;
    if (c->shared->frames <= 0 || c->shared->frames > PDPB_MAX_CHUNK ||
        c->shared->in_count < 0 || c->shared->in_count > PDPB_MAX_EVENTS || !sequence) return PDPB_ERROR;
    *sequence = current + 1;
    atomic_store_explicit(&c->shared->request_seq, *sequence, memory_order_release);
    wake_word(c, WORD_REQUEST);
    return PDPB_OK;
}
int32_t pdpb_wait_reply(pdpb_channel* c, uint32_t sequence, uint32_t timeout_us) {
    uint64_t deadline = pdpb_monotonic_ns() + (uint64_t)timeout_us * 1000;
    for (;;) {
        uint32_t word = atomic_load_explicit(&c->shared->reply_word, memory_order_acquire);
        if (pdpb_reply_sequence(c) == sequence) return PDPB_OK;
        uint64_t now = pdpb_monotonic_ns();
        if (now >= deadline) return PDPB_TIMEOUT;
        int result = wait_word(c, WORD_REPLY, word, deadline - now);
        if (result == PDPB_ERROR) return result;
    }
}
int32_t pdpb_wait_request(pdpb_channel* c, uint32_t timeout_ms, uint32_t* wake) {
    if (!wake) return PDPB_ERROR;
    uint64_t deadline = pdpb_monotonic_ns() + (uint64_t)timeout_ms * 1000000;
    for (;;) {
        uint32_t word = atomic_load_explicit(&c->shared->request_word, memory_order_acquire);
        if (pdpb_request_sequence(c) != pdpb_reply_sequence(c)) { *wake = word; return PDPB_OK; }
        if (word != *wake) { *wake = word; return PDPB_WOKEN; }
        uint64_t now = pdpb_monotonic_ns();
        if (now >= deadline) return PDPB_TIMEOUT;
        int result = wait_word(c, WORD_REQUEST, word, deadline - now);
        if (result == PDPB_ERROR) return result;
    }
}
void pdpb_wake_request(pdpb_channel* c) { wake_word(c, WORD_REQUEST); }
void pdpb_post_reply(pdpb_channel* c, uint32_t sequence) {
    atomic_store_explicit(&c->shared->reply_seq, sequence, memory_order_release);
    wake_word(c, WORD_REPLY);
}
uint32_t pdpb_signal_count(const pdpb_channel* c) { return atomic_load_explicit(&c->signal_count, memory_order_acquire); }
void pdpb_post_signal(pdpb_channel* c) { wake_word(c, WORD_SIGNAL); }
int32_t pdpb_wait_signal(pdpb_channel* c, uint32_t seen, uint32_t timeout_ms) {
    uint64_t deadline = pdpb_monotonic_ns() + (uint64_t)timeout_ms * 1000000;
    for (;;) {
        if (pdpb_signal_count(c) != seen) return PDPB_OK;
        uint64_t now = pdpb_monotonic_ns();
        if (now >= deadline) return PDPB_TIMEOUT;
        int result = wait_word(c, WORD_SIGNAL, seen, deadline - now);
        if (result == PDPB_ERROR) return result;
    }
}
