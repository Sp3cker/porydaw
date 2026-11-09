#include "pluginhost_internal.h"
#include <cstdio>

namespace {
bool expect(bool condition, const char* message) {
    if (!condition) std::fprintf(stderr, "pluginhost-parameter-batch: %s\n", message);
    return condition;
}
}

int runPluginHostParameterBatchCheck() {
    pdph::ComponentHandler handler(pdph_host_callbacks{});
    pdph::ParameterEdit edit{};
    if (!expect(!handler.pop(edit, handler.publishedEndpoint()), "an empty batch must be empty")) return 1;
    for (uint32_t id = 1; id <= 3; ++id) {
        if (!expect(handler.performEdit(id, id / 8.) == Steinberg::kResultOk, "initial publication failed")) return 1;
    }
    const auto firstEndpoint = handler.publishedEndpoint();
    if (!expect(handler.pop(edit, firstEndpoint) && edit.id == 1 && edit.value == 1. / 8., "first FIFO edit differs")) return 1;
    if (!expect(handler.performEdit(4, 0.5) == Steinberg::kResultOk, "later publication failed")) return 1;
    for (uint32_t id = 2; id <= 3; ++id) {
        if (!expect(handler.pop(edit, firstEndpoint) && edit.id == id && edit.value == id / 8., "initial batch lost FIFO order")) return 1;
    }
    if (!expect(!handler.pop(edit, firstEndpoint) && handler.hasPendingEdits(), "later publication escaped the fixed endpoint")) return 1;
    const auto nextEndpoint = handler.publishedEndpoint();
    if (!expect(handler.pop(edit, nextEndpoint) && edit.id == 4 && edit.value == 0.5, "next batch lost the later edit")) return 1;
    if (!expect(!handler.pop(edit, nextEndpoint) && !handler.hasPendingEdits(), "next batch did not finish")) return 1;

    for (uint32_t cycle = 0; cycle < 2; ++cycle) {
        for (uint32_t id = 0; id < pdph::eventCapacity - 1; ++id) {
            if (!expect(handler.performEdit(id, id / double(pdph::eventCapacity)) == Steinberg::kResultOk,
                "full-capacity publication failed before the reserved slot")) return 1;
        }
        const auto fullEndpoint = handler.publishedEndpoint();
        if (!expect(handler.performEdit(9000, 0.75) == Steinberg::kResultFalse, "a full ring accepted an extra edit")) return 1;
        if (!expect(handler.pop(edit, fullEndpoint) && edit.id == 0 && edit.value == 0., "wrapped batch first edit differs")) return 1;
        if (!expect(handler.performEdit(9000 + cycle, 0.75) == Steinberg::kResultOk, "a released slot was not reusable")) return 1;
        for (uint32_t id = 1; id < pdph::eventCapacity - 1; ++id) {
            if (!expect(handler.pop(edit, fullEndpoint) && edit.id == id && edit.value == id / double(pdph::eventCapacity),
                "wrapped batch lost an edit or FIFO order")) return 1;
        }
        if (!expect(!handler.pop(edit, fullEndpoint) && handler.hasPendingEdits(), "wrapped endpoint consumed a later publication")) return 1;
        const auto laterEndpoint = handler.publishedEndpoint();
        if (!expect(handler.pop(edit, laterEndpoint) && edit.id == 9000 + cycle && edit.value == 0.75,
            "wrapped next batch lost its edit")) return 1;
        if (!expect(!handler.pop(edit, laterEndpoint) && !handler.hasPendingEdits(), "wrapped next batch did not finish")) return 1;
    }
    return 0;
}
