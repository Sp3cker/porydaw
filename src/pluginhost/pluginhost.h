#ifndef PORYDAW_PLUGINHOST_H
#define PORYDAW_PLUGINHOST_H
#include "pluginbridge.h"
#ifdef __cplusplus
extern "C" {
#endif

typedef struct pdph_module_impl* pdph_module;
typedef struct pdph_plugin_impl* pdph_plugin;
typedef struct pdph_editor_impl* pdph_editor;
typedef int32_t pdph_result;
enum { PDPH_OK = 0, PDPH_ERR_ARGUMENT = -1, PDPH_ERR_STATE = -2,
       PDPH_ERR_SDK = -3, PDPH_ERR_INTERNAL = -4, PDPH_ERR_NO_EDITOR = -5,
       PDPH_ERR_UNSUPPORTED_PLATFORM = -6 };
enum { PDPH_RESTART_RELOAD_COMPONENT = 1 << 0, PDPH_RESTART_IO_CHANGED = 1 << 1,
       PDPH_RESTART_PARAM_VALUES_CHANGED = 1 << 2, PDPH_RESTART_LATENCY_CHANGED = 1 << 3,
       PDPH_RESTART_PARAM_TITLES_CHANGED = 1 << 4, PDPH_RESTART_MIDI_CC_ASSIGNMENT_CHANGED = 1 << 5 };
typedef struct { char message[512]; } pdph_error;
typedef struct {
    uint8_t uid[16];
    char name[128], category[128], sub_categories[128], vendor[128], version[128], sdk_version[128];
} pdph_class_info;
typedef struct { int32_t event_in, event_out, audio_in, audio_out; } pdph_bus_counts;
// Plugin-chosen threads: callbacks must only flip atomics or enqueue; never throw.
typedef struct {
    void* user;
    void (*end_edit)(void*, uint32_t param_id);
    void (*restart_component)(void*, int32_t flags);
    void (*set_dirty)(void*, int32_t dirty);
    void (*editor_closed)(void*);
    void (*editor_exposed)(void*, int32_t exposed);
} pdph_host_callbacks;

// Main thread. Instances retain the loaded module independently of the module handle.
pdph_result pdph_module_open(const char* utf8_path, pdph_module*, pdph_error*);
void pdph_module_close(pdph_module);
int32_t pdph_module_class_count(pdph_module);
pdph_result pdph_module_class_info(pdph_module, int32_t index, pdph_class_info*);
// Main thread discovery: initializes, counts and terminates only the class's component; no controller,
// state synchronization or parameters. Actual creation still validates the controller.
pdph_result pdph_module_class_buses(pdph_module, int32_t index, pdph_bus_counts*, pdph_error*);
// Main thread. Callback user storage must survive until destroy returns.
pdph_result pdph_plugin_create(pdph_module, const uint8_t uid[16], pdph_host_callbacks, pdph_plugin*, pdph_error*);
// Main thread, after detaching the insert and joining processing; no callbacks after return.
void pdph_plugin_destroy(pdph_plugin);
// Main thread: bus queries, setup, activation, latency and state are control operations.
pdph_result pdph_plugin_buses(pdph_plugin, pdph_bus_counts*);
// Inactive only. Live: realtime/device rate/1024; Render: offline/48000/256.
pdph_result pdph_plugin_setup_processing(pdph_plugin, int32_t realtime, double sample_rate, int32_t max_block);
// Main thread, valid only after setup; negative values are PDPH_ERR_*.
int32_t pdph_plugin_latency_samples(pdph_plugin);
pdph_result pdph_plugin_set_active(pdph_plugin, int32_t active);
// Main thread. which=0 component, 1 controller; returned bytes use pdph_free_buffer.
// SDK-unimplemented state returns PDPH_OK with null bytes and zero size.
pdph_result pdph_plugin_get_state(pdph_plugin, int32_t which, uint8_t** bytes, int64_t* size);
// Main thread, processing quiescent. Component restore also synchronizes the controller.
// SDK-unimplemented state is accepted; other SDK failures return PDPH_ERR_SDK.
pdph_result pdph_plugin_set_state(pdph_plugin, int32_t which, const uint8_t*, int64_t);
void pdph_free_buffer(uint8_t*);
// Helper main thread control path; never overlaps process.
pdph_result pdph_plugin_set_processing(pdph_plugin, int32_t processing);
// Dedicated processing thread, live OR Render, never concurrent; borrowed buffers last this call.
pdph_result pdph_plugin_process(pdph_plugin, int32_t frames, const pdph_process_context*,
    const pdph_midi_event* in, int32_t in_count, pdph_midi_event* out, int32_t out_capacity,
    int32_t* out_written, int32_t* out_total);
// Helper GUI thread only; editor implementation is not linked into the headless engine.
pdph_result pdph_editor_open(pdph_plugin, const char* utf8_title, pdph_editor*, pdph_error*);
void pdph_editor_raise(pdph_editor);
void pdph_editor_close(pdph_editor);
pdph_result pdph_editor_set_shortcuts(const int32_t* qt_strokes, int32_t count,
    void (*on_shortcut)(void*, int32_t), void* user);
#ifdef __cplusplus
}
#endif
#endif
