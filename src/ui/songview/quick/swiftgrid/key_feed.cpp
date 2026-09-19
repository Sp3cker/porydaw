#include "key_feed.h"

#include <cstdlib>
#include <limits>
#include <unordered_map>

namespace {

std::unordered_map<uint64_t, SgkDelivery *> &endpoints()
{
    static std::unordered_map<uint64_t, SgkDelivery *> registry;
    return registry;
}

uint64_t nextTargetId()
{
    static uint64_t lastId = 0;
    if (lastId == std::numeric_limits<uint64_t>::max())
        std::abort();
    return ++lastId;
}

} // namespace

void sgk_register_delivery(uint64_t target_id, SgkDelivery *delivery)
{
    if (target_id == 0 || !delivery || delivery->fn || delivery->context ||
        !endpoints().emplace(target_id, delivery).second)
        std::abort();
}

void sgk_unregister_delivery(uint64_t target_id)
{
    sgk_clear_delivery(target_id);
    endpoints().erase(target_id);
}

bool sgk_set_delivery(uint64_t target_id, SgcKeyDeliveryFn fn, void *context)
{
    const auto it = endpoints().find(target_id);
    if (it == endpoints().end() || !fn || !context)
        return false;
    SgkDelivery &slot = *it->second;
    if (slot.fn || slot.context)
        return false;
    slot = {fn, context};
    return true;
}

void sgk_clear_delivery(uint64_t target_id)
{
    const auto it = endpoints().find(target_id);
    if (it != endpoints().end())
        *it->second = {};
}

bool sgk_deliver(uint64_t target_id, const SgkKeyFacts *facts)
{
    if (!facts)
        return false;
    const auto it = endpoints().find(target_id);
    if (it == endpoints().end() || !it->second->fn)
        return false;
    // Copy the slot before calling out: the recipient may disconnect
    // synchronously.
    const SgkDelivery recipient = *it->second;
    return recipient.fn(facts, recipient.context) != 0;
}
namespace songview {

SwiftGridKeyRouter::SwiftGridKeyRouter() : m_targetId(nextTargetId())
{
    sgk_register_delivery(m_targetId, &m_delivery);
}

SwiftGridKeyRouter::~SwiftGridKeyRouter()
{
    sgk_unregister_delivery(m_targetId);
}

bool SwiftGridKeyRouter::deliver(const SgkKeyFacts &facts) const
{
    return sgk_deliver(m_targetId, &facts);
}

} // namespace songview
