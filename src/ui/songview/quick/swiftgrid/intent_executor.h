#pragma once

#include <stdint.h>

#include "command_feed.h"

class SongView;

// The QObject-free executor behind sgc_submit for one SongView's document.
// Document intents become undoable SongDocument commands (one intent = one
// undo entry, a token batch = one entry); session intents become SongView
// state with no undo entries. All validation happens here before any
// mutation; a rejected intent changes nothing.
//
// Well-formed no-ops return EXECUTED with no undo entry: a zero-delta move,
// a same-duration resize, a from == to reorder, or a delete of an unmapped
// slot. The intent was valid; production simply had nothing to change.
//
// The view outlives this GUI-thread endpoint. Construct after the document
// feed exists (documentId is the feed's id) and destroy before the view so
// no submission can borrow a released context.
class SwiftGridIntentExecutor final
{
  public:
    SwiftGridIntentExecutor(SongView &view, uint64_t documentId);
    ~SwiftGridIntentExecutor();

    SwiftGridIntentExecutor(const SwiftGridIntentExecutor &) = delete;
    SwiftGridIntentExecutor &operator=(const SwiftGridIntentExecutor &) = delete;

    uint64_t documentId() const { return m_documentId; }
    SgcExecutor *executor() { return &m_executor; }

  private:
    static SgcResult execute(const SgcIntentCommand *command, SgcOutcome *outcome, void *context);
    SgcResult run(const SgcIntentCommand &command, SgcOutcome &outcome) const;

    SongView &m_view;
    const uint64_t m_documentId;
    SgcExecutor m_executor{};
};
