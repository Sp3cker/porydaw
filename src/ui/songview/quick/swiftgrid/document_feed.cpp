#include "document_feed.h"

#include <cstdlib>
#include <unordered_map>

namespace {

std::unordered_map<uint64_t, SgdDelivery *> &endpoints()
{
    static std::unordered_map<uint64_t, SgdDelivery *> registry;
    return registry;
}

} // namespace

void sgd_register_feed(uint64_t document_id, SgdDelivery *delivery)
{
    if (document_id == 0 || !delivery || delivery->fn || delivery->context ||
        !endpoints().emplace(document_id, delivery).second)
        std::abort();
}

void sgd_unregister_feed(uint64_t document_id)
{
    sgd_clear_delivery(document_id);
    endpoints().erase(document_id);
}

bool sgd_set_delivery(uint64_t document_id, SgdDeliveryFn fn, void *context)
{
    const auto it = endpoints().find(document_id);
    if (it == endpoints().end() || !fn || !context)
        return false;
    SgdDelivery &slot = *it->second;
    if (slot.fn || slot.context)
        return false;
    slot = {fn, context};
    return true;
}

void sgd_clear_delivery(uint64_t document_id)
{
    const auto it = endpoints().find(document_id);
    if (it != endpoints().end())
        *it->second = {};
}
