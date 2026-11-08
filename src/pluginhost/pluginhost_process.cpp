#include "pluginhost_internal.h"
#include "pluginterfaces/vst/ivstprocesscontext.h"
#include <algorithm>
#include <cmath>
#include <limits>

using namespace Steinberg;
using namespace Steinberg::Vst;
namespace {
void silence(AudioBusBuffers* buses, int32 count, int32 frames) {
    for (int32 bus = 0; bus < count; ++bus) {
        buses[bus].silenceFlags = HostProcessData::kAllChannelsSilent;
        for (int32 channel = 0; channel < buses[bus].numChannels; ++channel)
            std::fill_n(buses[bus].channelBuffers32[channel], frames, 0.f);
    }
}
void pairNote(pdph_plugin plugin, pdph_midi_event& event) {
    if (event.kind == PDPH_EVENT_NOTE_ON) {
        if (event.note_id == -1) {
            bool collision;
            do {
                event.note_id = plugin->nextNoteID;
                plugin->nextNoteID = plugin->nextNoteID == std::numeric_limits<int32_t>::max() ? 0 : plugin->nextNoteID + 1;
                collision = false;
                for (const auto& held : plugin->held) if (held.used && held.id == event.note_id) collision = true;
            } while (collision);
        }
        for (auto& held : plugin->held) if (!held.used) {
            held = {true, event.note_id, event.channel, event.pitch, plugin->noteOrder++};
            break;
        }
    } else if (event.kind == PDPH_EVENT_NOTE_OFF) {
        pdph::HeldNote* match = nullptr;
        for (auto& held : plugin->held) {
            if (!held.used) continue;
            if (event.note_id != -1 ? held.id != event.note_id :
                (held.channel != event.channel || held.pitch != event.pitch)) continue;
            if (!match || held.order < match->order) match = &held;
        }
        if (match) { event.note_id = match->id; match->used = false; }
    }
}
}
pdph_result pdph_plugin_impl::prepareParameters() {
    parameterIDs.clear();
    const auto count = controller->getParameterCount();
    if (count < 0) return PDPH_ERR_SDK;
    parameterIDs.reserve(count);
    for (int32 index = 0; index < count; ++index) {
        ParameterInfo info{};
        if (controller->getParameterInfo(index, info) != kResultOk) return PDPH_ERR_SDK;
        parameterIDs.push_back(info.id);
    }
    inputParameters.setMaxParameters(count);
    inputParameters.clearQueue();
    for (auto id : parameterIDs) {
        int32 index = 0;
        auto* queue = inputParameters.addParameterData(id, index);
        queue->addPoint(0, 0., index);
    }
    inputParameters.clearQueue();
    return PDPH_OK;
}
extern "C" {
pdph_result pdph_plugin_setup_processing(pdph_plugin plugin, int32_t realtime, double sampleRate, int32_t maxBlock) {
    if (!plugin || !std::isfinite(sampleRate) || sampleRate <= 0 || maxBlock <= 0) return PDPH_ERR_ARGUMENT;
    if (plugin->active || plugin->processing) return PDPH_ERR_STATE;
    try {
        plugin->setup = false;
        ProcessSetup setup{realtime ? kRealtime : kOffline, kSample32, maxBlock, sampleRate};
        auto result = plugin->processor->setupProcessing(setup);
        if (result != kResultOk) return pdph::sdkResult(result);
        for (auto type : {kEvent, kAudio}) for (auto dir : {kInput, kOutput}) {
            auto count = plugin->component->getBusCount(type, dir);
            for (int32 index = 0; index < count; ++index) {
                BusInfo info{};
                result = plugin->component->getBusInfo(type, dir, index, info);
                if (result != kResultOk) return pdph::sdkResult(result);
                const bool active = type == kEvent || (info.flags & BusInfo::kDefaultActive) != 0;
                result = plugin->component->activateBus(type, dir, index, active);
                if (result != kResultOk) return pdph::sdkResult(result);
            }
        }
        plugin->data.unprepare();
        if (!plugin->data.prepare(*plugin->component, maxBlock, kSample32)) return PDPH_ERR_INTERNAL;
        plugin->data.processMode = setup.processMode;
        plugin->inputEvents.setMaxSize(pdph::eventCapacity);
        plugin->outputEvents.setMaxSize(pdph::eventCapacity);
        if (plugin->prepareParameters() != PDPH_OK) return PDPH_ERR_SDK;
        plugin->data.inputEvents = &plugin->inputEvents;
        plugin->data.outputEvents = &plugin->outputEvents;
        plugin->data.inputParameterChanges = &plugin->inputParameters;
        plugin->data.outputParameterChanges = nullptr;
        plugin->maxBlock = maxBlock;
        plugin->held = {};
        plugin->setup = true;
        return PDPH_OK;
    } catch (...) { return PDPH_ERR_INTERNAL; }
}
int32_t pdph_plugin_latency_samples(pdph_plugin plugin) {
    if (!plugin) return PDPH_ERR_ARGUMENT;
    if (!plugin->setup) return PDPH_ERR_STATE;
    try {
        auto latency = plugin->processor->getLatencySamples();
        if (latency > static_cast<uint32_t>(std::numeric_limits<int32_t>::max())) return PDPH_ERR_SDK;
        return static_cast<int32_t>(latency);
    } catch (...) { return PDPH_ERR_INTERNAL; }
}
pdph_result pdph_plugin_set_active(pdph_plugin plugin, int32_t active) {
    if (!plugin) return PDPH_ERR_ARGUMENT;
    if ((active && !plugin->setup) || (!active && plugin->processing)) return PDPH_ERR_STATE;
    try {
        auto result = plugin->component->setActive(active != 0);
        if (result == kResultOk) plugin->active = active != 0;
        return pdph::sdkResult(result);
    } catch (...) { return PDPH_ERR_INTERNAL; }
}
pdph_result pdph_plugin_set_processing(pdph_plugin plugin, int32_t processing) {
    if (!plugin) return PDPH_ERR_ARGUMENT;
    if (processing && !plugin->active) return PDPH_ERR_STATE;
    try {
        auto result = plugin->processor->setProcessing(processing != 0);
        if (result == kResultOk) plugin->processing = processing != 0;
        return pdph::sdkResult(result);
    } catch (...) { return PDPH_ERR_INTERNAL; }
}
pdph_result pdph_plugin_process(pdph_plugin plugin, int32_t frames, const pdph_process_context* context,
    const pdph_midi_event* input, int32_t inCount, pdph_midi_event* output, int32_t capacity,
    int32_t* written, int32_t* total) {
    if (!plugin || !context || !written || !total || frames < 0 || inCount < 0 ||
        inCount > pdph::eventCapacity || capacity < 0 || (inCount && !input) || (capacity && !output)) return PDPH_ERR_ARGUMENT;
    *written = 0; *total = 0;
    if (frames == 0 && inCount != 0) return PDPH_ERR_ARGUMENT;
    if (frames > 0 && (!plugin->processing || frames > plugin->maxBlock)) return PDPH_ERR_STATE;
    try {
        plugin->inputEvents.clear(); plugin->outputEvents.reset(); plugin->inputParameters.clearQueue();
        pdph::ParameterEdit edit{};
        while (plugin->handler->pop(edit)) {
            if (std::find(plugin->parameterIDs.begin(), plugin->parameterIDs.end(), edit.id) == plugin->parameterIDs.end()) continue;
            int32 index = 0;
            auto queue = plugin->inputParameters.addParameterData(edit.id, index);
            queue->addPoint(0, edit.value, index);
        }
        if (frames == 0) {
            if (!plugin->inputParameters.getParameterCount()) return PDPH_OK;
            ProcessData flush{};
            flush.processMode = plugin->setup ? plugin->data.processMode : kRealtime;
            flush.symbolicSampleSize = kSample32;
            flush.inputParameterChanges = &plugin->inputParameters;
            return pdph::sdkResult(plugin->processor->process(flush));
        }
        for (int32 i = 0; i < inCount; ++i) {
            const auto& source = input[i];
            if (source.kind != PDPH_EVENT_NOTE_ON && source.kind != PDPH_EVENT_NOTE_OFF) continue;
            Event event{};
            event.busIndex = 0; event.sampleOffset = source.sample_offset;
            if (source.kind == PDPH_EVENT_NOTE_ON) {
                event.type = Event::kNoteOnEvent;
                event.noteOn = {source.channel, source.pitch, 0.f, source.velocity, 0, source.note_id};
            } else {
                event.type = Event::kNoteOffEvent;
                event.noteOff = {source.channel, source.pitch, source.velocity, source.note_id, 0.f};
            }
            plugin->inputEvents.addEvent(event);
        }
        ProcessContext sdk{};
        sdk.state = context->state_flags;
        sdk.sampleRate = context->sample_rate; sdk.tempo = context->tempo;
        sdk.projectTimeMusic = context->ppq_position; sdk.barPositionMusic = context->bar_start_ppq;
        sdk.cycleStartMusic = context->cycle_start_ppq; sdk.cycleEndMusic = context->cycle_end_ppq;
        sdk.timeSigNumerator = context->time_sig_num; sdk.timeSigDenominator = context->time_sig_den;
        sdk.projectTimeSamples = context->project_samples;
        plugin->data.processContext = &sdk;
        plugin->data.numSamples = frames;
        silence(plugin->data.inputs, plugin->data.numInputs, frames);
        silence(plugin->data.outputs, plugin->data.numOutputs, frames);
        auto result = plugin->processor->process(plugin->data);
        plugin->data.processContext = nullptr;
        if (result != kResultOk) return pdph::sdkResult(result);
        *total = plugin->outputEvents.total;
        for (int32 i = 0; i < plugin->outputEvents.getEventCount(); ++i) {
            Event event{};
            plugin->outputEvents.getEvent(i, event);
            pdph_midi_event mapped{};
            mapped.sample_offset = event.sampleOffset; mapped.note_id = -1; mapped.kind = PDPH_EVENT_OTHER;
            if (event.type == Event::kNoteOnEvent) {
                mapped.kind = PDPH_EVENT_NOTE_ON; mapped.channel = static_cast<uint8_t>(event.noteOn.channel);
                mapped.pitch = static_cast<uint8_t>(event.noteOn.pitch); mapped.note_id = event.noteOn.noteId;
                mapped.velocity = std::isfinite(event.noteOn.velocity) ? std::clamp(event.noteOn.velocity, 0.f, 1.f) : 0.f;
            } else if (event.type == Event::kNoteOffEvent) {
                mapped.kind = PDPH_EVENT_NOTE_OFF; mapped.channel = static_cast<uint8_t>(event.noteOff.channel);
                mapped.pitch = static_cast<uint8_t>(event.noteOff.pitch); mapped.note_id = event.noteOff.noteId;
                mapped.velocity = std::isfinite(event.noteOff.velocity) ? std::clamp(event.noteOff.velocity, 0.f, 1.f) : 0.f;
            }
            pairNote(plugin, mapped);
            if (*written < capacity) output[(*written)++] = mapped;
        }
        return PDPH_OK;
    } catch (...) { plugin->data.processContext = nullptr; return PDPH_ERR_INTERNAL; }
}
}
