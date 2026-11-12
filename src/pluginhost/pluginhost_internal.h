#pragma once
#include "pluginhost.h"
#include "public.sdk/source/common/memorystream.h"
#include "public.sdk/source/vst/hosting/eventlist.h"
#include "public.sdk/source/vst/hosting/parameterchanges.h"
#include "public.sdk/source/vst/hosting/plugprovider.h"
#include "public.sdk/source/vst/hosting/processdata.h"
#include "pluginterfaces/base/funknownimpl.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"
#include <array>
#include <atomic>
#include <memory>
#include <vector>

namespace pdph {
constexpr int eventCapacity = 4096;
static_assert(std::atomic<uint32_t>::is_always_lock_free && std::atomic<bool>::is_always_lock_free,
    "Plugin processing callbacks require lock-free atomics");
struct ParameterEdit { Steinberg::Vst::ParamID id; Steinberg::Vst::ParamValue value; };
enum class PluginPhase {
    unprepared,
    prepared,
    active,
    processing,
};
class ComponentHandler final : public Steinberg::U::Implements<Steinberg::U::Directly<
    Steinberg::Vst::IComponentHandler, Steinberg::Vst::IComponentHandler2>> {
public:
    explicit ComponentHandler(pdph_host_callbacks callbacks) : callbacks(callbacks) {}
    Steinberg::tresult PLUGIN_API beginEdit(Steinberg::Vst::ParamID) override;
    Steinberg::tresult PLUGIN_API performEdit(Steinberg::Vst::ParamID, Steinberg::Vst::ParamValue) override;
    Steinberg::tresult PLUGIN_API endEdit(Steinberg::Vst::ParamID) override;
    Steinberg::tresult PLUGIN_API restartComponent(Steinberg::int32) override;
    Steinberg::tresult PLUGIN_API setDirty(Steinberg::TBool) override;
    Steinberg::tresult PLUGIN_API requestOpenEditor(Steinberg::FIDString) override;
    Steinberg::tresult PLUGIN_API startGroupEdit() override;
    Steinberg::tresult PLUGIN_API finishGroupEdit() override;
    uint32_t publishedEndpoint() const { return writeIndex.load(std::memory_order_acquire); }
    bool pop(ParameterEdit&, uint32_t endpoint);
    void detach();
    void editorClosed();
    void editorExposed(bool exposed);
    bool hasPendingEdits() const { return readIndex.load(std::memory_order_acquire) != writeIndex.load(std::memory_order_acquire); }
private:
    template<class F> void notify(F function) {
        inFlight.fetch_add(1, std::memory_order_seq_cst);
        if (enabled.load(std::memory_order_seq_cst)) function(callbacks);
        inFlight.fetch_sub(1, std::memory_order_seq_cst);
    }
    const pdph_host_callbacks callbacks;
    std::atomic<bool> enabled{true};
    std::atomic<uint32_t> inFlight{0};
    std::array<ParameterEdit, eventCapacity> edits{};
    alignas(64) std::atomic<uint32_t> writeIndex{0};
    alignas(64) std::atomic<uint32_t> readIndex{0};
};
class OutputEvents final : public Steinberg::Vst::EventList {
public:
    OutputEvents() : EventList(0) {}
    Steinberg::tresult PLUGIN_API addEvent(Steinberg::Vst::Event& event) override {
        ++total;
        return EventList::addEvent(event);
    }
    void reset() { clear(); total = 0; }
    int32_t total = 0;
};
struct HeldNote { bool used = false; int32_t id = -1; uint8_t channel = 0, pitch = 0; uint64_t order = 0; };
// SDK 3.8.1 logical reset: setSize(0) would release the reusable allocation.
class StateStream final : public Steinberg::MemoryStream {
public:
    StateStream() = default;
    StateStream(const StateStream&) = delete;
    StateStream& operator=(const StateStream&) = delete;
    void reset() { size = 0; cursor = 0; allocationError = false; }
};
pdph_result readState(pdph_plugin, int32_t which, StateStream&, bool* implemented = nullptr);
pdph_result sdkResult(Steinberg::tresult);
void error(pdph_error*, const char*);
extern Steinberg::tresult (*hostQuery)(const Steinberg::TUID, void**);
}
struct pdph_module_impl {
    VST3::Hosting::Module::Ptr module;
    std::vector<VST3::Hosting::ClassInfo> classes;
};
struct pdph_plugin_impl {
    // Provider dies before handler and module; processor references die before provider.
    VST3::Hosting::Module::Ptr module;
    Steinberg::IPtr<pdph::ComponentHandler> handler;
    std::unique_ptr<Steinberg::Vst::PlugProvider> provider;
    Steinberg::IPtr<Steinberg::Vst::IComponent> component;
    Steinberg::IPtr<Steinberg::Vst::IEditController> controller;
    Steinberg::IPtr<Steinberg::Vst::IAudioProcessor> processor;
    Steinberg::Vst::HostProcessData data;
    Steinberg::Vst::EventList inputEvents{0};
    pdph::OutputEvents outputEvents;
    Steinberg::Vst::ParameterChanges inputParameters{0};
    std::vector<Steinberg::Vst::ParamID> parameterIDs;
    std::array<pdph::HeldNote, pdph::eventCapacity> held{};
    uint64_t noteOrder = 0;
    int32_t nextNoteID = 0;
    int32_t maxBlock = 0;
    pdph::PluginPhase phase = pdph::PluginPhase::unprepared;
    pdph_editor editor = nullptr;
    void (*closeEditor)(pdph_editor) = nullptr;
    pdph_result prepareParameters();
    ~pdph_plugin_impl();
};
