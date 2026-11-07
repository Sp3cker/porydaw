#include "public.sdk/source/vst/vstsinglecomponenteffect.h"
#include "public.sdk/source/main/pluginfactory.h"
#include "pluginterfaces/base/ibstream.h"
#include "pluginterfaces/vst/ivstevents.h"
#include "pluginterfaces/vst/ivstparameterchanges.h"
#include "pluginterfaces/vst/ivstprocesscontext.h"
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <thread>

using namespace Steinberg;
using namespace Steinberg::Vst;
namespace {
struct Pending { bool used = false; int64 sample = 0; uint64 order = 0; Event event{}; };
class TestGen final : public SingleComponentEffect {
public:
    explicit TestGen(int variant) : variant(variant) {}
    static FUnknown* create(void*) { return static_cast<IComponent*>(new TestGen(0)); }
    static FUnknown* createAudio(void*) { return static_cast<IComponent*>(new TestGen(1)); }
    static FUnknown* createRealtime(void*) { return static_cast<IComponent*>(new TestGen(2)); }
    static FUnknown* createAudioOnly(void*) { return static_cast<IComponent*>(new TestGen(3)); }
    tresult PLUGIN_API initialize(FUnknown* host) override {
        auto result = SingleComponentEffect::initialize(host);
        if (result != kResultOk) return result;
        parameters.addParameter(STR16("Pitch Offset"), STR16("semitones"), 12, 0., ParameterInfo::kCanAutomate, 0);
        if (variant != 3) { addEventInput(STR16("Input")); addEventOutput(STR16("Output")); }
        if (variant == 3) addAudioInput(STR16("Input"), SpeakerArr::kStereo);
        if (variant == 1 || variant == 3) addAudioOutput(STR16("Output"), SpeakerArr::kStereo);
        return kResultOk;
    }
    tresult PLUGIN_API setupProcessing(ProcessSetup& setup) override {
        if (setup.symbolicSampleSize != kSample32) return kResultFalse;
        processSetup = setup;
        return kResultOk;
    }
    tresult PLUGIN_API setProcessing(TBool) override { pending = {}; wasPlaying = false; return kResultOk; }
    uint32 PLUGIN_API getLatencySamples() override { return variant == 1 ? latency : 0; }
    tresult PLUGIN_API setState(IBStream* stream) override {
        std::array<uint8, 16> bytes{};
        int32 read = 0;
        if (!stream || stream->read(bytes.data(), 16, &read) != kResultOk || read < 8) return kResultFalse;
        auto field = [&](int index) {
            uint32 value = 0;
            for (int i = 0; i < 4; ++i) value |= uint32(bytes[index + i]) << (8 * i);
            return static_cast<int32>(value);
        };
        offset = std::clamp(field(0), 0, 12);
        auto oldLatency = latency;
        latency = std::max(0, field(4));
        fault = read >= 16 ? field(12) : 0;
        setParamNormalized(0, offset / 12.);
        if (variant == 1 && latency != oldLatency && componentHandler) componentHandler->restartComponent(kLatencyChanged);
        return kResultOk;
    }
    tresult PLUGIN_API getState(IBStream* stream) override {
        std::array<uint8, 16> bytes{};
        const int32 fields[] = {offset, latency, 0, fault};
        for (int field = 0; field < 4; ++field) for (int byte = 0; byte < 4; ++byte)
            bytes[field * 4 + byte] = static_cast<uint8>(uint32(fields[field]) >> (8 * byte));
        int32 written = 0;
        return stream && stream->write(bytes.data(), 16, &written) == kResultOk && written == 16 ? kResultOk : kResultFalse;
    }
    tresult PLUGIN_API setComponentState(IBStream* stream) override {
        if (variant == 2) {
            if (componentHandler) componentHandler->restartComponent(kParamValuesChanged);
            return kNotImplemented;
        }
        return setState(stream);
    }
    tresult PLUGIN_API setEditorState(IBStream* stream) override { return variant == 2 ? kNotImplemented : setState(stream); }
    tresult PLUGIN_API getEditorState(IBStream* stream) override { return variant == 2 ? kNotImplemented : getState(stream); }
    tresult PLUGIN_API process(ProcessData& data) override {
        if (fault == 1) std::abort();
        if (fault == 2) for (;;) std::this_thread::sleep_for(std::chrono::hours(24));
        if (data.inputParameterChanges) for (int32 i = 0; i < data.inputParameterChanges->getParameterCount(); ++i) {
            auto queue = data.inputParameterChanges->getParameterData(i);
            int32 sample = 0; ParamValue value = 0;
            if (queue && queue->getParameterId() == 0 && queue->getPointCount() &&
                queue->getPoint(queue->getPointCount() - 1, sample, value) == kResultOk)
                offset = static_cast<int32>(std::lround(std::clamp(value, 0., 1.) * 12));
        }
        if (!data.processContext || !(data.processContext->state & ProcessContext::kPlaying)) {
            pending = {}; wasPlaying = false; return kResultOk;
        }
        if (variant == 3 || (variant == 2 && data.processMode == kOffline)) return kResultOk;
        if (!data.outputEvents) return kResultOk;
        auto& context = *data.processContext;
        const int64 start = context.projectTimeSamples;
        const int64 delay = variant == 1 ? latency : 0;
        if (!wasPlaying) {
            Event cc{}; cc.type = Event::kLegacyMIDICCOutEvent;
            cc.midiCCOut.controlNumber = 1; cc.midiCCOut.channel = 0; cc.midiCCOut.value = 64;
            schedule(cc, start + delay);
            wasPlaying = true;
        }
        if (data.inputEvents) for (int32 i = 0; i < data.inputEvents->getEventCount(); ++i) {
            Event event{}; data.inputEvents->getEvent(i, event);
            if (event.type == Event::kNoteOnEvent) event.noteOn.pitch += 12;
            else if (event.type == Event::kNoteOffEvent) event.noteOff.pitch += 12;
            else continue;
            schedule(event, start + event.sampleOffset + delay);
        }
        if (context.tempo > 0 && context.sampleRate > 0) {
            const double samplesPerQuarter = context.sampleRate * 60. / context.tempo;
            const double endPPQ = context.projectTimeMusic + data.numSamples / samplesPerQuarter;
            auto step = static_cast<int64>(std::ceil(context.projectTimeMusic * 4. - 1e-9));
            for (; step / 4. < endPPQ - 1e-12; ++step) {
                const int64 onset = start + std::llround((step / 4. - context.projectTimeMusic) * samplesPerQuarter) + delay;
                Event on{}; on.type = Event::kNoteOnEvent;
                on.noteOn = {0, static_cast<int16>(60 + offset + 2 * ((step % 4 + 4) % 4)), 0.f, 0.8f, 0, nextID++};
                schedule(on, onset);
                Event off{}; off.type = Event::kNoteOffEvent;
                off.noteOff = {0, on.noteOn.pitch, 0.f, on.noteOn.noteId, 0.f};
                schedule(off, onset + std::llround(samplesPerQuarter / 8.));
            }
        }
        for (;;) {
            Pending* next = nullptr;
            for (auto& item : pending) if (item.used && item.sample < start + data.numSamples &&
                (!next || item.sample < next->sample || (item.sample == next->sample && item.order < next->order))) next = &item;
            if (!next) break;
            next->event.sampleOffset = static_cast<int32>(std::max<int64>(0, next->sample - start));
            data.outputEvents->addEvent(next->event);
            next->used = false;
        }
        return kResultOk;
    }
private:
    void schedule(const Event& event, int64 sample) {
        for (auto& item : pending) if (!item.used) { item = {true, sample, order++, event}; return; }
    }
    const int variant;
    int32 offset = 0, latency = 128, fault = 0, nextID = 100000;
    uint64 order = 0;
    bool wasPlaying = false;
    std::array<Pending, 4096> pending{};
};
}
BEGIN_FACTORY("Porydaw", "", "", PFactoryInfo::kNoFlags)
DEF_CLASS2(INLINE_UID(0x50445048, 0x54455354, 0x47454E00, 0x00000001), PClassInfo::kManyInstances,
    kVstAudioEffectClass, "TestGen", 0, "Instrument", "1.0.0", kVstVersionString, TestGen::create)
DEF_CLASS2(INLINE_UID(0x50445048, 0x54455354, 0x47454E00, 0x00000002), PClassInfo::kManyInstances,
    kVstAudioEffectClass, "TestGenAudio", 0, "Instrument", "1.0.0", kVstVersionString, TestGen::createAudio)
DEF_CLASS2(INLINE_UID(0x50445048, 0x54455354, 0x47454E00, 0x00000003), PClassInfo::kManyInstances,
    kVstAudioEffectClass, "TestGenRealtimeOnly", 0, "Instrument", "1.0.0", kVstVersionString, TestGen::createRealtime)
DEF_CLASS2(INLINE_UID(0x50445048, 0x54455354, 0x47454E00, 0x00000004), PClassInfo::kManyInstances,
    kVstAudioEffectClass, "TestAudioOnly", 0, "Fx", "1.0.0", kVstVersionString, TestGen::createAudioOnly)
END_FACTORY
