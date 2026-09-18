#include "swift_grid_document_feed.h"

#include <limits>
#include <vector>

#include "core/songdocument.h"

namespace {

uint64_t nextDocumentId()
{
    static uint64_t lastId = 0;
    if (lastId == std::numeric_limits<uint64_t>::max())
        qFatal("Swift document feed identity exhausted");
    return ++lastId;
}

int32_t snapshotCount(size_t size)
{
    if (size > size_t(std::numeric_limits<int32_t>::max()))
        qFatal("Swift document snapshot exceeds the ABI count range");
    return int32_t(size);
}

} // namespace

SwiftGridDocumentFeed::SwiftGridDocumentFeed(const SongDocument &document)
    : m_document(document)
    , m_documentId(nextDocumentId())
{
    sgd_register_feed(m_documentId, &m_delivery);
    m_documentChanged = connect(&document, &SongDocument::documentChanged, this,
                                &SwiftGridDocumentFeed::pushSnapshot);
}

SwiftGridDocumentFeed::~SwiftGridDocumentFeed()
{
    disconnect(m_documentChanged);
    sgd_unregister_feed(m_documentId);
}

void SwiftGridDocumentFeed::pushSnapshot()
{
    if (!m_delivery.fn)
        return;

    const int tracks = m_document.engineTrackCount();
    std::vector<SgdNote> notes;
    for (int track = 0; track < tracks; ++track) {
        const auto trackNotes = m_document.notesForTrack(track);
        if (trackNotes.size() > size_t(std::numeric_limits<int32_t>::max()) - notes.size())
            qFatal("Swift document snapshot exceeds the ABI note count range");
        for (const DocNote &note : trackNotes)
            notes.push_back({track, note.key, note.tick, note.duration, note.velocity});
    }
    const auto timeSigs = m_document.timeSigs();
    const int32_t signatureCount = snapshotCount(timeSigs.size());
    std::vector<SgdTimeSignature> signatures;
    signatures.reserve(timeSigs.size());
    for (const DocTimeSig &signature : timeSigs)
        signatures.push_back({signature.tick, signature.numerator, signature.denomPow2});

    const SgdDocumentHeader header{
        m_documentId, m_document.revision(),       m_document.smf().division,
        tracks,       snapshotCount(notes.size()), signatureCount};
    // Copy the slot before calling out: the recipient may disconnect synchronously.
    const SgdDelivery recipient = m_delivery;
    recipient.fn(&header, notes.data(), signatures.data(), recipient.context);
}
