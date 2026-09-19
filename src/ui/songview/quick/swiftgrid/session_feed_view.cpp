#include "session_feed_view.h"

#include <bit>
#include <cstdlib>
#include <limits>
#include <vector>

#include "ui/songview.h"
#include "ui/songview/editorselectionmodel.h"

namespace {

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

SwiftGridSessionFeed::SwiftGridSessionFeed(const SongView &view)
    : m_view(view)
    , m_sessionId(nextSessionId())
{
    sgs_register_feed(m_sessionId, &m_delivery);
    connect(&view, &SongView::selectionContextChanged, this, &SwiftGridSessionFeed::pushSnapshot);
    connect(&view, &SongView::muteMaskChanged, this, &SwiftGridSessionFeed::pushSnapshot);
    connect(&view, &SongView::soloMaskChanged, this, &SwiftGridSessionFeed::pushSnapshot);
}

SwiftGridSessionFeed::~SwiftGridSessionFeed()
{
    // Connections drop automatically when either endpoint is destroyed;
    // only the registry entry needs explicit teardown.
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
