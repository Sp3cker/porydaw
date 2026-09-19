#include "session_feed.h"

#include <bit>
#include <cstdlib>
#include <limits>
#include <unordered_map>
#include <vector>

#include "ui/songview.h"
#include "ui/songview/editorselectionmodel.h"

namespace {

std::unordered_map<uint64_t, SgsDelivery *> &endpoints()
{
    static std::unordered_map<uint64_t, SgsDelivery *> registry;
    return registry;
}

uint64_t nextSessionId()
{
    static uint64_t lastId = 0;
    if (lastId == std::numeric_limits<uint64_t>::max())
        qFatal("Swift session feed identity exhausted");
    return ++lastId;
}

int32_t snapshotCount(size_t size)
{
    if (size > size_t(std::numeric_limits<int32_t>::max()))
        qFatal("Swift session snapshot exceeds the ABI count range");
    return int32_t(size);
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

SwiftGridSessionFeed::SwiftGridSessionFeed(const SongView &view)
    : m_view(view)
    , m_sessionId(nextSessionId())
{
    sgs_register_feed(m_sessionId, &m_delivery);
    m_selectionChanged = connect(&view, &SongView::selectionContextChanged, this,
                                 &SwiftGridSessionFeed::pushSnapshot);
    m_muteChanged =
        connect(&view, &SongView::muteMaskChanged, this, &SwiftGridSessionFeed::pushSnapshot);
    m_soloChanged =
        connect(&view, &SongView::soloMaskChanged, this, &SwiftGridSessionFeed::pushSnapshot);
}

SwiftGridSessionFeed::~SwiftGridSessionFeed()
{
    disconnect(m_selectionChanged);
    disconnect(m_muteChanged);
    disconnect(m_soloChanged);
    sgs_unregister_feed(m_sessionId);
}

void SwiftGridSessionFeed::pushSnapshot()
{
    if (!m_delivery.fn)
        return;

    const songview::EditorSelectionModel &selection = m_view.selectionModel();
    std::vector<uint64_t> noteIds;
    noteIds.reserve(selection.noteSelection().size());
    for (const NoteId id : selection.noteSelection())
        noteIds.push_back(std::bit_cast<uint64_t>(id));

    const auto &time = selection.timeSelection();
    std::vector<SgsLane> lanes;
    lanes.reserve(time.lanes.size());
    for (const auto &[track, controller] : time.lanes)
        lanes.push_back({track, controller});

    const SgsSessionState state{m_sessionId,
                                ++m_revision,
                                selection.primaryTrack(),
                                selection.storedTrackScope(),
                                snapshotCount(noteIds.size()),
                                {time.startTick, time.endTick,
                                 time.scope == songview::EditorSelectionModel::TimeSelection::Lanes
                                     ? int32_t(SGS_TIME_SELECTION_LANES)
                                     : int32_t(SGS_TIME_SELECTION_TRACKS),
                                 snapshotCount(lanes.size()), uint8_t(time.tempo)},
                                m_view.muteMask(),
                                m_view.soloMask()};
    // Copy the slot before calling out: the recipient may disconnect synchronously.
    const SgsDelivery recipient = m_delivery;
    recipient.fn(&state, noteIds.data(), lanes.data(), recipient.context);
}
