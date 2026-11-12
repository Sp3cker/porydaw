#include "pluginhost_internal.h"
#include "public.sdk/source/common/memorystream.h"
#include "public.sdk/source/vst/hosting/hostclasses.h"
#include "pluginterfaces/base/ustring.h"
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <ostream>
#include <streambuf>
#include <string>
#include <thread>

using namespace Steinberg;
using namespace Steinberg::Vst;
namespace {
class PorydawHost final : public HostApplication {
    tresult PLUGIN_API getName(String128 name) override {
        UString(name, 128).fromAscii("Porydaw");
        return kResultOk;
    }
public:
    tresult PLUGIN_API queryInterface(const TUID iid, void** object) override {
        if (pdph::hostQuery && pdph::hostQuery(iid, object) == kResultOk) return kResultOk;
        return HostApplication::queryInterface(iid, object);
    }
};
HostApplication& hostContext() {
    static PorydawHost host;
    static const bool installed = [&] {
        PluginContextFactory::instance().setPluginContext(&host);
        return true;
    }();
    (void)installed;
    return host;
}
template<size_t N> void copyText(char (&to)[N], const std::string& from) {
    std::snprintf(to, N, "%s", from.c_str());
}
template<size_t N> void copySubCategories(char (&to)[N], const VST3::Hosting::ClassInfo::SubCategories& categories) {
    size_t position = 0;
    for (size_t index = 0; index < categories.size(); ++index) {
        if (index) {
            if (position == N - 1) break;
            to[position++] = '|';
        }
        for (const auto byte : categories[index]) {
            if (byte == '\0' || position == N - 1) { to[position] = '\0'; return; }
            to[position++] = byte;
        }
    }
    to[position] = '\0';
}
class ProviderErrors final : private std::streambuf {
public:
    ProviderErrors() : stream(this) { PlugProvider::setErrorStream(&stream); }
    ~ProviderErrors() override { PlugProvider::setErrorStream(nullptr); }
    ProviderErrors(const ProviderErrors&) = delete;
    ProviderErrors& operator=(const ProviderErrors&) = delete;
    const char* message() const {
        return emitted ? prefix : "PlugProvider initialization or connection failed";
    }
private:
    std::streamsize xsputn(const char* bytes, std::streamsize count) override {
        if (count > 0) {
            emitted = true;
            const auto copied = static_cast<size_t>((std::min)(count, static_cast<std::streamsize>(sizeof(prefix) - 1 - used)));
            std::memcpy(prefix + used, bytes, copied);
            used += copied;
            prefix[used] = '\0';
        }
        return count;
    }
    int_type overflow(int_type value) override {
        if (!traits_type::eq_int_type(value, traits_type::eof())) {
            const char byte = traits_type::to_char_type(value);
            xsputn(&byte, 1);
        }
        return traits_type::not_eof(value);
    }
    char prefix[sizeof(pdph_error::message)] = {};
    size_t used = 0;
    bool emitted = false;
    std::ostream stream;
};
bool stateSucceeded(tresult result) {
    return result == kResultOk || result == kNotImplemented;
}
pdph_result sdkFailure(pdph_error* error, const char* operation, tresult result) {
    if (error) std::snprintf(error->message, sizeof(error->message), "%s failed (SDK result %d)", operation, static_cast<int>(result));
    return PDPH_ERR_SDK;
}
}
namespace pdph {
tresult (*hostQuery)(const TUID, void**) = nullptr;
pdph_result sdkResult(tresult result) { return result == kResultOk ? PDPH_OK : PDPH_ERR_SDK; }
void error(pdph_error* out, const char* message) {
    if (out) std::snprintf(out->message, sizeof(out->message), "%s", message);
}
pdph_result readState(pdph_plugin plugin, int32_t which, StateStream& stream, bool* implemented) {
    stream.reset();
    if (implemented) *implemented = false;
    if (!plugin || (which != 0 && which != 1)) return PDPH_ERR_ARGUMENT;
    try {
        const auto result = which == 0 ? plugin->component->getState(&stream) : plugin->controller->getState(&stream);
        if (result == kResultOk) { if (implemented) *implemented = true; return PDPH_OK; }
        stream.reset();
        return stateSucceeded(result) ? PDPH_OK : PDPH_ERR_SDK;
    } catch (...) { stream.reset(); return PDPH_ERR_INTERNAL; }
}
tresult PLUGIN_API ComponentHandler::beginEdit(ParamID) { return kResultOk; }
tresult PLUGIN_API ComponentHandler::performEdit(ParamID id, ParamValue value) {
    auto write = writeIndex.load(std::memory_order_relaxed);
    auto next = (write + 1) % eventCapacity;
    if (next == readIndex.load(std::memory_order_acquire)) return kResultFalse;
    edits[write] = {id, value};
    writeIndex.store(next, std::memory_order_release);
    return kResultOk;
}
bool ComponentHandler::pop(ParameterEdit& edit, uint32_t endpoint) {
    auto read = readIndex.load(std::memory_order_relaxed);
    if (read == endpoint) return false;
    edit = edits[read];
    readIndex.store((read + 1) % eventCapacity, std::memory_order_release);
    return true;
}
tresult PLUGIN_API ComponentHandler::endEdit(ParamID id) {
    notify([id](const pdph_host_callbacks& c) { if (c.end_edit) c.end_edit(c.user, id); });
    return kResultOk;
}
tresult PLUGIN_API ComponentHandler::restartComponent(int32 flags) {
    notify([flags](const pdph_host_callbacks& c) { if (c.restart_component) c.restart_component(c.user, flags); });
    return kResultOk;
}
tresult PLUGIN_API ComponentHandler::setDirty(TBool dirty) {
    notify([dirty](const pdph_host_callbacks& c) { if (c.set_dirty) c.set_dirty(c.user, dirty); });
    return kResultOk;
}
tresult PLUGIN_API ComponentHandler::requestOpenEditor(FIDString) { return kNotImplemented; }
tresult PLUGIN_API ComponentHandler::startGroupEdit() { return kResultOk; }
tresult PLUGIN_API ComponentHandler::finishGroupEdit() { return kResultOk; }
void ComponentHandler::editorClosed() {
    notify([](const pdph_host_callbacks& c) { if (c.editor_closed) c.editor_closed(c.user); });
}
void ComponentHandler::editorExposed(bool exposed) {
    notify([exposed](const pdph_host_callbacks& c) { if (c.editor_exposed) c.editor_exposed(c.user, exposed); });
}
void ComponentHandler::detach() {
    enabled.store(false, std::memory_order_seq_cst);
    while (inFlight.load(std::memory_order_seq_cst) != 0) std::this_thread::yield();
}
}
pdph_plugin_impl::~pdph_plugin_impl() {
    if (editor && closeEditor) closeEditor(editor);
    if (handler) handler->detach();
    try {
        if (controller) controller->setComponentHandler(nullptr);
        if (processor && phase == pdph::PluginPhase::processing) processor->setProcessing(false);
        if (component && (phase == pdph::PluginPhase::active || phase == pdph::PluginPhase::processing)) component->setActive(false);
    } catch (...) {}
}
extern "C" {
pdph_result pdph_module_open(const char* path, pdph_module* out, pdph_error* error) {
    if (!path || !out) { pdph::error(error, "Null module path or output"); return PDPH_ERR_ARGUMENT; }
    *out = nullptr;
    try {
        std::string reason;
        auto module = VST3::Hosting::Module::create(path, reason);
        if (!module) { pdph::error(error, reason.c_str()); return PDPH_ERR_SDK; }
        auto result = std::make_unique<pdph_module_impl>();
        result->module = std::move(module);
        result->classes = result->module->getFactory().classInfos();
        auto& classes = result->classes;
        classes.erase(std::remove_if(classes.begin(), classes.end(),
            [](const auto& info) { return info.category() != kVstAudioEffectClass; }), classes.end());
        *out = result.release();
        return PDPH_OK;
    } catch (const std::exception& e) { pdph::error(error, e.what()); return PDPH_ERR_INTERNAL; }
    catch (...) { pdph::error(error, "Unexpected module loader exception"); return PDPH_ERR_INTERNAL; }
}
void pdph_module_close(pdph_module module) { try { delete module; } catch (...) {} }
int32_t pdph_module_class_count(pdph_module module) {
    return module ? static_cast<int32_t>(module->classes.size()) : PDPH_ERR_ARGUMENT;
}
pdph_result pdph_module_class_info(pdph_module module, int32_t index, pdph_class_info* out) {
    if (!module || !out || index < 0 || index >= pdph_module_class_count(module)) return PDPH_ERR_ARGUMENT;
    try {
        const auto& info = module->classes[index];
        *out = {};
        std::memcpy(out->uid, info.ID().data(), 16);
        copyText(out->name, info.name()); copyText(out->category, info.category());
        copySubCategories(out->sub_categories, info.subCategories()); copyText(out->vendor, info.vendor());
        copyText(out->version, info.version()); copyText(out->sdk_version, info.sdkVersion());
        return PDPH_OK;
    } catch (...) { return PDPH_ERR_INTERNAL; }
}
pdph_result pdph_module_class_buses(pdph_module module, int32_t index, pdph_bus_counts* out, pdph_error* error) {
    if (!module || !out || index < 0 || index >= pdph_module_class_count(module)) {
        pdph::error(error, "Null module, class index or output"); return PDPH_ERR_ARGUMENT;
    }
    *out = {};
    try {
        const auto& info = module->classes[index];
        auto& host = hostContext();
        module->module->getFactory().setHostContext(&host);
        auto component = module->module->getFactory().createInstance<IComponent>(info.ID());
        const auto failure = [&](const char* what) {
            if (error) std::snprintf(error->message, sizeof(error->message), "%s of %s!", what, info.name().c_str());
            return PDPH_ERR_SDK;
        };
        if (!component) return failure("Failed to create component instance");
        if (component->initialize(&host) != kResultOk) return failure("Failed to initialize component");
        struct Terminate {
            IComponent* component;
            ~Terminate() { try { component->terminate(); } catch (...) {} }
        } terminate{component.get()};
        *out = {component->getBusCount(kEvent, kInput), component->getBusCount(kEvent, kOutput),
                component->getBusCount(kAudio, kInput), component->getBusCount(kAudio, kOutput)};
        return PDPH_OK;
    } catch (const std::exception& e) { pdph::error(error, e.what()); return PDPH_ERR_INTERNAL; }
    catch (...) { pdph::error(error, "Unexpected component discovery exception"); return PDPH_ERR_INTERNAL; }
}
pdph_result pdph_plugin_create(pdph_module module, const uint8_t uid[16], pdph_host_callbacks callbacks,
    pdph_plugin* out, pdph_error* error) {
    if (!module || !uid || !out) { pdph::error(error, "Null module, UID or output"); return PDPH_ERR_ARGUMENT; }
    *out = nullptr;
    try {
        auto info = std::find_if(module->classes.begin(), module->classes.end(),
            [uid](const auto& item) { return std::memcmp(item.ID().data(), uid, 16) == 0; });
        if (info == module->classes.end()) { pdph::error(error, "Audio effect class UID not found"); return PDPH_ERR_ARGUMENT; }
        auto plugin = std::make_unique<pdph_plugin_impl>();
        plugin->module = module->module;
        plugin->handler = owned(new pdph::ComponentHandler(callbacks));
        auto& host = hostContext();
        module->module->getFactory().setHostContext(&host);
        ProviderErrors errors;
        plugin->provider = std::make_unique<PlugProvider>(module->module->getFactory(), *info, true);
        if (!plugin->provider->initialize()) {
            pdph::error(error, errors.message());
            return PDPH_ERR_SDK;
        }
        plugin->component = plugin->provider->getComponentPtr();
        plugin->controller = plugin->provider->getControllerPtr();
        if (!plugin->component || !plugin->controller) { pdph::error(error, "Plugin has no component or controller"); return PDPH_ERR_SDK; }
        plugin->processor = U::cast<IAudioProcessor>(plugin->component);
        if (!plugin->processor) { pdph::error(error, "Plugin has no audio processor"); return PDPH_ERR_SDK; }
        auto result = plugin->controller->setComponentHandler(plugin->handler);
        if (result != kResultOk) return sdkFailure(error, "IEditController::setComponentHandler", result);
        MemoryStream state;
        result = plugin->component->getState(&state);
        if (!stateSucceeded(result)) return sdkFailure(error, "IComponent::getState", result);
        if (result == kResultOk) {
            state.seek(0, IBStream::kIBSeekSet, nullptr);
            result = plugin->controller->setComponentState(&state);
            if (!stateSucceeded(result)) return sdkFailure(error, "IEditController::setComponentState", result);
        }
        if (plugin->prepareParameters() != PDPH_OK) {
            pdph::error(error, "Could not prepare plugin parameter queues"); return PDPH_ERR_SDK;
        }
        *out = plugin.release();
        return PDPH_OK;
    } catch (const std::exception& e) { pdph::error(error, e.what()); return PDPH_ERR_INTERNAL; }
    catch (...) { pdph::error(error, "Unexpected plugin creation exception"); return PDPH_ERR_INTERNAL; }
}
void pdph_plugin_destroy(pdph_plugin plugin) { try { delete plugin; } catch (...) {} }
pdph_result pdph_plugin_buses(pdph_plugin plugin, pdph_bus_counts* out) {
    if (!plugin || !out) return PDPH_ERR_ARGUMENT;
    try {
        *out = {plugin->component->getBusCount(kEvent, kInput), plugin->component->getBusCount(kEvent, kOutput),
                plugin->component->getBusCount(kAudio, kInput), plugin->component->getBusCount(kAudio, kOutput)};
        return PDPH_OK;
    } catch (...) { return PDPH_ERR_INTERNAL; }
}
pdph_result pdph_plugin_get_state(pdph_plugin plugin, int32_t which, uint8_t** bytes, int64_t* size) {
    if (!plugin || !bytes || !size || (which != 0 && which != 1)) return PDPH_ERR_ARGUMENT;
    *bytes = nullptr; *size = 0;
    try {
        pdph::StateStream stream;
        bool implemented = false;
        const auto result = pdph::readState(plugin, which, stream, &implemented);
        if (result != PDPH_OK) return result;
        if (!implemented) return PDPH_OK;
        *size = stream.getSize();
        *bytes = reinterpret_cast<uint8_t*>(stream.detachData());
        return PDPH_OK;
    } catch (...) { return PDPH_ERR_INTERNAL; }
}
pdph_result pdph_plugin_set_state(pdph_plugin plugin, int32_t which, const uint8_t* bytes, int64_t size) {
    if (!plugin || size < 0 || (!bytes && size != 0) || (which != 0 && which != 1)) return PDPH_ERR_ARGUMENT;
    try {
        MemoryStream stream(const_cast<uint8_t*>(bytes), size);
        auto result = which == 0 ? plugin->component->setState(&stream) : plugin->controller->setState(&stream);
        if (!stateSucceeded(result)) return PDPH_ERR_SDK;
        if (which == 0) {
            stream.seek(0, IBStream::kIBSeekSet, nullptr);
            result = plugin->controller->setComponentState(&stream);
        }
        return stateSucceeded(result) ? PDPH_OK : PDPH_ERR_SDK;
    } catch (...) { return PDPH_ERR_INTERNAL; }
}
void pdph_free_buffer(uint8_t* bytes) { std::free(bytes); }
}
