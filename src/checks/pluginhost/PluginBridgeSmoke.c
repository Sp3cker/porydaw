#include "pluginbridge.h"
#include "pluginhost.h"
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>

int main(void) {
    pdpb_channel* owner = NULL;
    pdpb_channel* peer = NULL;
    char name[96];
    uint32_t sequence = 0, wake = 0;
    int result = 1;
    const char* failure = "create shared channel";
    snprintf(name, sizeof(name), "Local\\porydaw-bridge-smoke-%lu", (unsigned long)GetCurrentProcessId());
    if (pdpb_channel_create(name, &owner) != PDPB_OK) goto cleanup;
    failure = "open second shared view";
    if (pdpb_channel_open(name, &peer) != PDPB_OK) goto cleanup;

    pdpb_request_context(owner)->tempo = 123.0;
    pdph_midi_event* input = pdpb_request_events(owner);
    input[0] = (pdph_midi_event){.sample_offset = 7, .note_id = 42,
        .kind = PDPH_EVENT_NOTE_ON, .channel = 2, .pitch = 61, .velocity = 0.5f};
    pdpb_set_request(owner, 64, 1);
    failure = "post request";
    if (pdpb_post_request(owner, &sequence) != PDPB_OK || sequence != 1) goto cleanup;
    failure = "receive request through second view";
    if (pdpb_wait_request(peer, 100, &wake) != PDPB_OK || pdpb_request_sequence(peer) != sequence) goto cleanup;
    failure = "request payload visibility";
    pdpb_shared* shared = pdpb_channel_shared(peer);
    const pdph_midi_event* received = pdpb_request_events(peer);
    if (shared->frames != 64 || shared->in_count != 1 || pdpb_request_context(peer)->tempo != 123.0 ||
        received[0].sample_offset != 7 || received[0].note_id != 42 || received[0].kind != PDPH_EVENT_NOTE_ON ||
        received[0].channel != 2 || received[0].pitch != 61 || received[0].velocity != 0.5f) goto cleanup;

    atomic_store_explicit(&shared->heartbeat, UINT64_C(0xffffffff), memory_order_relaxed);
    pdpb_tick_heartbeat(peer);
    failure = "64-bit heartbeat visibility across views";
    if (pdpb_heartbeat(owner) != UINT64_C(0x100000000)) goto cleanup;
    shared->out[0] = received[0];
    shared->out[0].pitch = 73;
    shared->status = PDPH_OK;
    shared->out_written = 1;
    shared->out_total = 1;
    pdpb_post_reply(peer, sequence);
    failure = "receive reply through original view";
    if (pdpb_wait_reply(owner, sequence, 100000) != PDPB_OK || pdpb_reply_sequence(owner) != sequence ||
        pdpb_reply_status(owner) != PDPH_OK || pdpb_reply_written(owner) != 1 || pdpb_reply_total(owner) != 1 ||
        pdpb_reply_events(owner)[0].pitch != 73 || pdpb_reply_events(owner)[0].note_id != 42) goto cleanup;

    failure = "private signal count round trip";
    uint32_t signal = pdpb_signal_count(peer);
    pdpb_post_signal(peer);
    if (pdpb_signal_count(peer) != signal + 1 || pdpb_wait_signal(peer, signal, 100) != PDPB_OK) goto cleanup;
    result = 0;
cleanup:
    if (result) fprintf(stderr, "PluginBridgeSmoke: %s failed\n", failure);
    pdpb_channel_close(peer);
    pdpb_channel_close(owner);
    return result;
}
