#include "session_feed.h"

#include <cstdlib>
#include <unordered_map>

namespace {

std::unordered_map<uint64_t, SgsDelivery *> &endpoints()
{
    static std::unordered_map<uint64_t, SgsDelivery *> registry;
    return registry;
}

} // namespace

void sgs_register_feed(uint64_t session_id, SgsDelivery *delivery)
{
    if (session_id == 0 || !delivery || delivery->fn || delivery->context ||
        !endpoints().emplace(session_id, delivery).second)
        std::abort();
}

void sgs_unregister_feed(uint64_t session_id)
{
    sgs_clear_delivery(session_id);
    endpoints().erase(session_id);
}

bool sgs_set_delivery(uint64_t session_id, SgsDeliveryFn fn, void *context)
{
    const auto it = endpoints().find(session_id);
    if (it == endpoints().end() || !fn || !context)
        return false;
    SgsDelivery &slot = *it->second;
    if (slot.fn || slot.context)
        return false;
    slot = {fn, context};
    return true;
}

void sgs_clear_delivery(uint64_t session_id)
{
    const auto it = endpoints().find(session_id);
    if (it != endpoints().end())
        *it->second = {};
}
