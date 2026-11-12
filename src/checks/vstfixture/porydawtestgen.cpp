#include "public.sdk/source/vst/vstsinglecomponenteffect.h"
#include "public.sdk/source/common/pluginview.h"
#include "public.sdk/source/main/pluginfactory.h"
#include "pluginterfaces/base/ibstream.h"
#include "pluginterfaces/vst/ivstevents.h"
#include "pluginterfaces/vst/ivstparameterchanges.h"
#include "pluginterfaces/vst/ivstprocesscontext.h"
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <thread>
#include <type_traits>
#include <stdexcept>

using namespace Steinberg;
using namespace Steinberg::Vst;
void* pdphFixtureViewCreate(void*, int, int, void (*)(void*), void*, void*);
void pdphFixtureViewResize(void*, int, int);
void pdphFixtureViewDestroy(void*);
namespace {
constexpr uint32 diagnosticMagic = 0x44584450u, diagnosticVersion = 1;
constexpr std::size_t diagnosticBytes = 112;
// Diagnostic opt-in uses fault bit 30; component word 8 counts editor key-downs.
constexpr uint32 diagnosticFlag = 0x40000000u;
// Scanner regression opt-in: controller-only APIs abort, so discovery must stay component-only.
bool componentOnlyProbe() {
    static const bool enabled = std::getenv("PORYDAW_TESTGEN_COMPONENT_ONLY") != nullptr;
    return enabled;
}
struct Pending { bool used = false; int64 sample = 0; uint64 order = 0; Event event{}; };
struct Diagnostics {
    uint64 calls = 0;
    int32 maxFrames = 0, lastFrames = 0;
    ProcessContext context = {};
    int32 inCount = 0, firstInKind = -1, firstInOffset = -1, firstInNoteId = -1;
};
static_assert(std::is_trivially_copyable_v<Diagnostics> && sizeof(double) == 8);
class FixtureView final : public CPluginView {
public:
    FixtureView(IEditController* owner, void (*attached)(void*), void (*key)(void*), void* user,
        uint32 fault, std::atomic<int32>& cleanup)
        : owner(owner), onAttached(attached), onKey(key), user(user), fault(fault), cleanup(cleanup) {
        rect = ViewRect(0, 0, 320, 200);
    }
    ~FixtureView() override {
        if (native) pdphFixtureViewDestroy(native);
        if (fault >= 6 && fault <= 9) cleanup.fetch_or(4, std::memory_order_relaxed);
    }
    tresult PLUGIN_API getSize(ViewRect* size) override {
        if (fault == 6) throw std::runtime_error("Fixture editor getSize failure");
        return CPluginView::getSize(size);
    }
    tresult PLUGIN_API setFrame(IPlugFrame* frame) override {
        const auto result = CPluginView::setFrame(frame);
        if (!frame && fault >= 6 && fault <= 9) {
            cleanup.fetch_or(2, std::memory_order_relaxed);
            throw std::runtime_error("Fixture editor setFrame cleanup failure");
        }
        return result;
    }
    tresult PLUGIN_API isPlatformTypeSupported(FIDString type) override {
#ifdef __APPLE__
        return type && std::strcmp(type, kPlatformTypeNSView) == 0 ? kResultTrue : kResultFalse;
#elif defined(_WIN32)
        return type && std::strcmp(type, kPlatformTypeHWND) == 0 ? kResultTrue : kResultFalse;
#else
        return type && std::strcmp(type, kPlatformTypeX11EmbedWindowID) == 0 ? kResultTrue : kResultFalse;
#endif
    }
    tresult PLUGIN_API attached(void* parent, FIDString type) override {
        if (!parent || native || isPlatformTypeSupported(type) != kResultTrue) return kResultFalse;
        void* loop = nullptr;
#if defined(__linux__)
        if (!plugFrame || plugFrame->queryInterface(Linux::IRunLoop::iid, &loop) != kResultOk) return kResultFalse;
#endif
        native = pdphFixtureViewCreate(parent, rect.getWidth(), rect.getHeight(), onKey, user, loop);
#if defined(__linux__)
        if (loop) static_cast<Linux::IRunLoop*>(loop)->release();
#endif
        if (!native) return kResultFalse;
        systemWindow = parent;
        ViewRect requested(0, 0, 400, 240);
        if (plugFrame) plugFrame->resizeView(this, &requested);
        if (fault == 7) throw std::runtime_error("Fixture editor attached failure");
        if (fault == 8) return kResultFalse;
        onAttached(user);
        return kResultOk;
    }
    tresult PLUGIN_API removed() override {
        if (native) { pdphFixtureViewDestroy(native); native = nullptr; }
        systemWindow = nullptr;
        if (fault >= 7 && fault <= 9) {
            cleanup.fetch_or(1, std::memory_order_relaxed);
            throw std::runtime_error("Fixture editor removed cleanup failure");
        }
        return kResultOk;
    }
    tresult PLUGIN_API onSize(ViewRect* size) override {
        if (!size) return kInvalidArgument;
        rect = *size;
        if (native) pdphFixtureViewResize(native, rect.getWidth(), rect.getHeight());
        return kResultOk;
    }
    tresult PLUGIN_API canResize() override { return kResultTrue; }
    tresult PLUGIN_API checkSizeConstraint(ViewRect* size) override {
        if (!size) return kInvalidArgument;
        size->right = size->left + (std::max)(1, size->getWidth());
        size->bottom = size->top + (std::max)(1, size->getHeight());
        return kResultOk;
    }
private:
    IPtr<IEditController> owner;
    void (*onAttached)(void*);
    void (*onKey)(void*);
    void* user;
    void* native = nullptr;
    const uint32 fault;
    std::atomic<int32>& cleanup;
};
class TestGen final : public SingleComponentEffect {
public:
    explicit TestGen(int variant) : variant(variant) {}
    static FUnknown* create(void*) { return static_cast<IComponent*>(new TestGen(0)); }
    static FUnknown* createAudio(void*) { return static_cast<IComponent*>(new TestGen(1)); }
    static FUnknown* createRealtime(void*) { return static_cast<IComponent*>(new TestGen(2)); }
    static FUnknown* createAudioOnly(void*) { return static_cast<IComponent*>(new TestGen(3)); }
    IPlugView* PLUGIN_API createView(FIDString name) override {
        if (variant == 2 || !name || std::strcmp(name, ViewType::kEditor) != 0) return nullptr;
        if (faultCode() == 5) throw std::runtime_error("Fixture editor createView failure");
        const auto attached = [](void* user) {
            auto& plugin = *static_cast<TestGen*>(user);
            if (!plugin.componentHandler) return;
            plugin.componentHandler->beginEdit(0);
            plugin.setParamNormalized(0, 5. / 12.);
            plugin.componentHandler->performEdit(0, 5. / 12.);
            plugin.componentHandler->endEdit(0);
        };
        const auto key = [](void* user) { static_cast<TestGen*>(user)->keysReceived.fetch_add(1, std::memory_order_relaxed); };
        return new FixtureView(this, attached, key, this, faultCode(), keysReceived);
    }
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
        latency = (std::max)(0, field(4));
        fault = read >= 16 ? field(12) : 0;
        keysReceived.store(read >= 12 ? field(8) : 0, std::memory_order_relaxed);
        diagnostics = {};
        delayPending = faultCode() == 3;
        setParamNormalized(0, offset / 12.);
        if (variant == 1 && latency != oldLatency && componentHandler) componentHandler->restartComponent(kLatencyChanged);
        if (componentHandler && faultCode() == 4)
            for (uint32 index = 0; index < 4097; ++index) componentHandler->endEdit(index);
        if (componentHandler && faultCode() == 10)
            for (const int32 value : {2, 7, 11}) componentHandler->performEdit(0, value / 12.);
        return kResultOk;
    }
    tresult PLUGIN_API getState(IBStream* stream) override {
        std::array<uint8, 16> bytes{};
        int32 observed = keysReceived.load(std::memory_order_relaxed);
        if (faultCode() == 11) {
            // Bounded snapshot gate: word 8 reports whether a processed block arrived during this read.
            const auto start = processedBlocks.load(std::memory_order_acquire);
            const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
            while (processedBlocks.load(std::memory_order_acquire) == start && std::chrono::steady_clock::now() < deadline)
                std::this_thread::sleep_for(std::chrono::milliseconds(1));
            observed = processedBlocks.load(std::memory_order_acquire) != start ? 1 : 0;
        }
        const int32 fields[] = {offset, latency, observed, fault};
        for (int field = 0; field < 4; ++field) for (int byte = 0; byte < 4; ++byte)
            bytes[field * 4 + byte] = static_cast<uint8>(uint32(fields[field]) >> (8 * byte));
        int32 written = 0;
        return stream && stream->write(bytes.data(), 16, &written) == kResultOk && written == 16 ? kResultOk : kResultFalse;
    }
    tresult PLUGIN_API setComponentState(IBStream* stream) override {
        if (componentOnlyProbe()) std::abort();
        if (variant == 2) {
            if (componentHandler) componentHandler->restartComponent(kParamValuesChanged);
            return kNotImplemented;
        }
        return setState(stream);
    }
    int32 PLUGIN_API getParameterCount() override {
        if (componentOnlyProbe()) std::abort();
        return SingleComponentEffect::getParameterCount();
    }
    tresult PLUGIN_API setEditorState(IBStream* stream) override {
        if (diagnosticsEnabled()) return setDiagnosticState(stream);
        return variant == 2 ? kNotImplemented : setState(stream);
    }
    tresult PLUGIN_API getEditorState(IBStream* stream) override {
        if (diagnosticsEnabled()) return getDiagnosticState(stream);
        return variant == 2 ? kNotImplemented : getState(stream);
    }
    tresult PLUGIN_API process(ProcessData& data) override {
        const auto code = faultCode();
        if (code == 1) std::abort();
        if (code == 2) for (;;) std::this_thread::sleep_for(std::chrono::hours(24));
        if (delayPending && data.numSamples > 0) {
            delayPending = false;
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
        if (diagnosticsEnabled()) recordDiagnostics(data);
        if (data.inputParameterChanges) for (int32 i = 0; i < data.inputParameterChanges->getParameterCount(); ++i) {
            auto queue = data.inputParameterChanges->getParameterData(i);
            int32 sample = 0; ParamValue value = 0;
            if (queue && queue->getParameterId() == 0 && queue->getPointCount() &&
                queue->getPoint(queue->getPointCount() - 1, sample, value) == kResultOk)
                offset = static_cast<int32>(std::lround(std::clamp(value, 0., 1.) * 12));
            if (faultCode() == 10 && queue && queue->getPointCount()) {
                keysReceived.fetch_add(sample == 0 ? 1 : -1000, std::memory_order_relaxed);
            }
        }
        if (data.numSamples == 0) return kResultOk;
        processedBlocks.fetch_add(1, std::memory_order_release);
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
    uint32 faultCode() const { return static_cast<uint32>(fault) & ~diagnosticFlag; }
    bool diagnosticsEnabled() const { return (static_cast<uint32>(fault) & diagnosticFlag) != 0; }
    void recordDiagnostics(const ProcessData& data) {
        ++diagnostics.calls;
        diagnostics.maxFrames = (std::max)(diagnostics.maxFrames, data.numSamples);
        diagnostics.lastFrames = data.numSamples;
        diagnostics.context = data.processContext ? *data.processContext : ProcessContext{};
        diagnostics.inCount = data.inputEvents ? data.inputEvents->getEventCount() : 0;
        diagnostics.firstInKind = -1; diagnostics.firstInOffset = -1; diagnostics.firstInNoteId = -1;
        Event event = {};
        if (diagnostics.inCount > 0 && data.inputEvents->getEvent(0, event) == kResultOk) {
            diagnostics.firstInKind = event.type;
            diagnostics.firstInOffset = event.sampleOffset;
            if (event.type == Event::kNoteOnEvent) diagnostics.firstInNoteId = event.noteOn.noteId;
            else if (event.type == Event::kNoteOffEvent) diagnostics.firstInNoteId = event.noteOff.noteId;
        }
    }
    tresult getDiagnosticState(IBStream* stream) {
        std::array<uint8, diagnosticBytes> bytes = {};
        const auto write32 = [&](int index, uint32 value) {
            for (int byte = 0; byte < 4; ++byte) bytes[index + byte] = static_cast<uint8>(value >> (8 * byte));
        };
        const auto write64 = [&](int index, uint64 value) {
            for (int byte = 0; byte < 8; ++byte) bytes[index + byte] = static_cast<uint8>(value >> (8 * byte));
        };
        const auto writeDouble = [&](int index, double value) {
            uint64 bits = 0;
            std::memcpy(&bits, &value, sizeof(bits)); write64(index, bits);
        };
        write32(0, diagnosticMagic); write32(4, diagnosticVersion); write64(8, diagnostics.calls);
        write32(16, diagnostics.maxFrames); write32(20, diagnostics.lastFrames);
        const auto& context = diagnostics.context;
        write32(24, context.state); write32(28, 0);
        writeDouble(32, context.sampleRate); writeDouble(40, context.tempo);
        writeDouble(48, context.projectTimeMusic); writeDouble(56, context.barPositionMusic);
        writeDouble(64, context.cycleStartMusic); writeDouble(72, context.cycleEndMusic);
        write32(80, context.timeSigNumerator); write32(84, context.timeSigDenominator);
        write64(88, static_cast<uint64>(context.projectTimeSamples));
        write32(96, diagnostics.inCount); write32(100, diagnostics.firstInKind);
        write32(104, diagnostics.firstInOffset); write32(108, diagnostics.firstInNoteId);
        int32 written = 0;
        return stream && stream->write(bytes.data(), static_cast<int32>(bytes.size()), &written) == kResultOk &&
            written == static_cast<int32>(bytes.size()) ? kResultOk : kResultFalse;
    }
    tresult setDiagnosticState(IBStream* stream) {
        std::array<uint8, diagnosticBytes> bytes = {};
        int32 read = 0;
        if (!stream || stream->read(bytes.data(), static_cast<int32>(bytes.size()), &read) != kResultOk ||
            read != static_cast<int32>(bytes.size())) return kResultFalse;
        uint8 extra = 0;
        if (stream->read(&extra, 1, &read) != kResultOk || read != 0) return kResultFalse;
        const auto read32 = [&](int index) {
            uint32 value = 0;
            for (int byte = 0; byte < 4; ++byte) value |= uint32(bytes[index + byte]) << (8 * byte);
            return value;
        };
        const auto read64 = [&](int index) {
            uint64 value = 0;
            for (int byte = 0; byte < 8; ++byte) value |= uint64(bytes[index + byte]) << (8 * byte);
            return value;
        };
        const auto readDouble = [&](int index) {
            const uint64 bits = read64(index);
            double value = 0;
            std::memcpy(&value, &bits, sizeof(value)); return value;
        };
        if (read32(0) != diagnosticMagic || read32(4) != diagnosticVersion || read32(28) != 0) return kResultFalse;
        Diagnostics restored = {};
        restored.calls = read64(8);
        restored.maxFrames = static_cast<int32>(read32(16)); restored.lastFrames = static_cast<int32>(read32(20));
        auto& context = restored.context;
        context.state = read32(24);
        context.sampleRate = readDouble(32); context.tempo = readDouble(40);
        context.projectTimeMusic = readDouble(48); context.barPositionMusic = readDouble(56);
        context.cycleStartMusic = readDouble(64); context.cycleEndMusic = readDouble(72);
        context.timeSigNumerator = static_cast<int32>(read32(80)); context.timeSigDenominator = static_cast<int32>(read32(84));
        context.projectTimeSamples = static_cast<int64>(read64(88));
        restored.inCount = static_cast<int32>(read32(96)); restored.firstInKind = static_cast<int32>(read32(100));
        restored.firstInOffset = static_cast<int32>(read32(104)); restored.firstInNoteId = static_cast<int32>(read32(108));
        diagnostics = restored;
        return kResultOk;
    }
    void schedule(const Event& event, int64 sample) {
        for (auto& item : pending) if (!item.used) { item = {true, sample, order++, event}; return; }
    }
    const int variant;
    int32 offset = 0, latency = 128, fault = 0, nextID = 100000;
    std::atomic<int32> keysReceived{0};
    std::atomic<uint64> processedBlocks{0};
    uint64 order = 0;
    bool wasPlaying = false;
    bool delayPending = false;
    Diagnostics diagnostics = {};
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
