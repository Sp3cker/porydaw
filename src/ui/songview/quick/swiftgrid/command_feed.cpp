#include "command_feed.h"

#include <cstdlib>
#include <unordered_map>

namespace {

std::unordered_map<uint64_t, SgcExecutor *> &endpoints()
{
    static std::unordered_map<uint64_t, SgcExecutor *> registry;
    return registry;
}

} // namespace

void sgc_register_executor(uint64_t document_id, SgcExecutor *executor)
{
    if (document_id == 0 || !executor || executor->fn || executor->context ||
        !endpoints().emplace(document_id, executor).second)
        std::abort();
}

void sgc_unregister_executor(uint64_t document_id)
{
    sgc_clear_executor(document_id);
    endpoints().erase(document_id);
}

bool sgc_set_executor(uint64_t document_id, SgcExecuteFn fn, void *context)
{
    const auto it = endpoints().find(document_id);
    if (it == endpoints().end() || !fn || !context)
        return false;
    SgcExecutor &slot = *it->second;
    if (slot.fn || slot.context)
        return false;
    slot = {fn, context};
    return true;
}

void sgc_clear_executor(uint64_t document_id)
{
    const auto it = endpoints().find(document_id);
    if (it != endpoints().end())
        *it->second = {};
}

SgcResult sgc_submit(const SgcIntentCommand *command, SgcOutcome *outcome)
{
    if (outcome)
        *outcome = {};
    SgcResult result = SGC_REJECTED_INVALID;
    if (command) {
        const auto it = endpoints().find(command->documentId);
        if (it == endpoints().end() || !it->second->fn) {
            result = SGC_REJECTED_UNAVAILABLE;
        } else {
            // Copy the slot before calling out: the executor may unbind
            // synchronously.
            const SgcExecutor executor = *it->second;
            result = executor.fn(command, outcome, executor.context);
        }
    }
    if (outcome)
        outcome->result = result;
    return result;
}
