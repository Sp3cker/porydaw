#ifndef PORYDAW_PLUGINBRIDGE_H
#define PORYDAW_PLUGINBRIDGE_H
#include <stdint.h>
#ifdef __cplusplus
#include <atomic>
#define PDPB_ATOMIC(T) std::atomic<T>
extern "C" {
#else
#include <stdatomic.h>
#define PDPB_ATOMIC(T) _Atomic(T)
#endif
#define PDPB_VERSION 2
#define PDPB_MAGIC 0x50445042u
#define PDPB_MAX_EVENTS 4096
#define PDPB_MAX_CHUNK 8192
#define PDPB_MAX_CONTROL_BYTES 67108864u
enum { PDPH_EVENT_NOTE_ON = 0, PDPH_EVENT_NOTE_OFF = 1, PDPH_EVENT_OTHER = 2 };
enum { PDPH_CTX_PLAYING = 1 << 1, PDPH_CTX_CYCLE_ACTIVE = 1 << 2,
       PDPH_CTX_PROJECT_TIME_MUSIC_VALID = 1 << 9, PDPH_CTX_TEMPO_VALID = 1 << 10,
       PDPH_CTX_BAR_POSITION_VALID = 1 << 11, PDPH_CTX_CYCLE_VALID = 1 << 12,
       PDPH_CTX_TIME_SIG_VALID = 1 << 13 };
typedef struct {
    uint32_t state_flags;
    double sample_rate, tempo, ppq_position, bar_start_ppq, cycle_start_ppq, cycle_end_ppq;
    int32_t time_sig_num, time_sig_den;
    int64_t project_samples;
} pdph_process_context;
typedef struct {
    int32_t sample_offset, note_id;
    uint8_t kind, channel, pitch;
    float velocity;
} pdph_midi_event;
typedef struct {
    uint32_t magic, version;
    PDPB_ATOMIC(uint32_t) request_seq, reply_seq, request_word, reply_word;
    PDPB_ATOMIC(uint64_t) heartbeat;
    int32_t frames;
    pdph_process_context ctx;
    int32_t in_count;
    pdph_midi_event in[PDPB_MAX_EVENTS];
    int32_t status, out_written, out_total;
    pdph_midi_event out[PDPB_MAX_EVENTS];
} pdpb_shared;
typedef struct pdpb_channel pdpb_channel;
enum { PDPB_OK = 0, PDPB_TIMEOUT = 1, PDPB_BUSY = 2, PDPB_WOKEN = 3, PDPB_ERROR = -1 };
enum {
    PDPB_CREATE_PLUGIN = 1, PDPB_SETUP_PROCESSING = 2, PDPB_SET_ACTIVE = 3,
    PDPB_SET_PROCESSING = 4, PDPB_GET_STATE = 5, PDPB_SET_STATE = 6,
    PDPB_GET_STATE_DIGEST = 7, PDPB_GET_LATENCY = 8, PDPB_OPEN_EDITOR = 9,
    PDPB_RAISE_EDITOR = 10, PDPB_CLOSE_EDITOR = 11, PDPB_SET_SHORTCUTS = 12,
    PDPB_QUIT = 13, PDPB_REPLY = 0x80000000u,
    PDPB_READY = 0x40000001u, PDPB_END_EDIT = 0x40000002u,
    PDPB_RESTART_COMPONENT = 0x40000003u, PDPB_SET_DIRTY = 0x40000004u,
    PDPB_EDITOR_CLOSED = 0x40000005u, PDPB_SHORTCUT = 0x40000006u, PDPB_EDITOR_EXPOSED = 0x40000007u,
};
// Control scalars are LE; strings/bytes are u32 length then raw UTF-8/bytes; no padding.
// Reply type is PDPB_REPLY, same requestId; payload u32 result (0 ok, 1 error), then data/error string.
// Create: string path + 16 UID bytes; reply four i32 buses (event in/out, audio in/out).
// Setup: u32 realtime + f64 rate + u32 maxBlock + u32 periodFrames. Booleans: u32 0/1.
// GetState: u32 which (0 component, 1 controller); reply u64 FNV-1a of exactly the returned bytes, then bytes.
// SetState: which + bytes. Digest reply: u64 FNV-1a of component bytes; latency reply: i32. OpenEditor: string title.
// SetShortcuts: u32 count + count pairs (u32 Qt key, u32 Qt modifiers), in registry order.
// Other requests empty. Ready: u32 version; EndEdit/Restart/Dirty/Shortcut: u32; EditorExposed: u32 0/1.
// Events have requestId 0. EditorClosed is empty. Editor actions are supplied by task 8.
int32_t pdpb_channel_create(const char* name, pdpb_channel** out);
int32_t pdpb_channel_open(const char* name, pdpb_channel** out);
// Close unmaps/releases handles and only auto-unlinks creators; explicit unlink also works on openers.
// POSIX unlink is idempotent; Windows named objects disappear after the last handle closes.
void pdpb_channel_close(pdpb_channel*);
int32_t pdpb_channel_unlink(pdpb_channel*);
pdpb_shared* pdpb_channel_shared(pdpb_channel*);
uint32_t pdpb_request_sequence(const pdpb_channel*);
uint32_t pdpb_reply_sequence(const pdpb_channel*);
uint64_t pdpb_heartbeat(const pdpb_channel*);
uint64_t pdpb_monotonic_ns(void);
pdph_process_context* pdpb_request_context(pdpb_channel*);
pdph_midi_event* pdpb_request_events(pdpb_channel*);
const pdph_midi_event* pdpb_reply_events(const pdpb_channel*);
void pdpb_set_request(pdpb_channel*, int32_t frames, int32_t in_count);
int32_t pdpb_terminate_process(uint32_t pid);
int32_t pdpb_reply_status(const pdpb_channel*);
int32_t pdpb_reply_written(const pdpb_channel*);
int32_t pdpb_reply_total(const pdpb_channel*);
// One producer owns request data until matching reply. Busy never posts or waits.
int32_t pdpb_post_request(pdpb_channel*, uint32_t* sequence);
int32_t pdpb_wait_reply(pdpb_channel*, uint32_t sequence, uint32_t timeout_us);
// *wake is the caller's last observed request word: returns OK for a pending request, WOKEN when the
// word changed without one (pdpb_wake_request, or a stale *wake), else TIMEOUT or ERROR. Updates *wake.
int32_t pdpb_wait_request(pdpb_channel*, uint32_t timeout_ms, uint32_t* wake);
void pdpb_wake_request(pdpb_channel*);
void pdpb_post_reply(pdpb_channel*, uint32_t sequence);
void pdpb_tick_heartbeat(pdpb_channel*);
// Helper-local count (never shared with Porydaw): waits return OK once it differs from `seen`.
uint32_t pdpb_signal_count(const pdpb_channel*);
void pdpb_post_signal(pdpb_channel*);
int32_t pdpb_wait_signal(pdpb_channel*, uint32_t seen, uint32_t timeout_ms);
#ifdef __cplusplus
}
#endif
#undef PDPB_ATOMIC
#endif
