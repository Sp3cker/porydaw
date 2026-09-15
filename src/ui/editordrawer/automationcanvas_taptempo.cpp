// Tap-tempo gesture on the automation canvas's Tempo row, plus the idle
// commit. The session state lives in taptempo.h; this file is the canvas
// slice: input capture, the guarded single write to the tempo stream, and
// the shared view-state reset, following the direct-lane commit style of
// acceptNodeValuePrompt in automationcanvas.cpp.

#include "ui/editordrawer/automationcanvas.h"

#include <algorithm>

#include <QTimer>

#include "core/songdocument.h"
#include "ui/editordrawer/automationpage.h"

void AutomationCanvas::tapTempo()
{
    if (!parametersEnabled()) {
        resetTapTempo();
        return;
    }
    if (!m_tapClock.isValid())
        m_tapClock.start();
    const qint64 nowNs = m_tapClock.nsecsElapsed();
    m_tapTempo.registerTap(nowNs);
    if (m_tapTempo.tapCount() == 1) {
        // First tap of a fresh session: pin the document identity and start
        // revision here, so a later commit ignores any interim edit.
        m_tapDocument = &m_page.document();
        m_tapRevision = m_page.document().revision();
    }
    // One emission per tap: the draft Text also keys on tapCount > 0, so the
    // first tap (draft still 0) must notify too.
    emit tapTempoDraftChanged();
    m_tapIdleCommit.start();
}

void AutomationCanvas::commitTapTempo()
{
    m_tapIdleCommit.stop();
    if (!m_tapTempo.readyToCommit() || !parametersEnabled() || !m_tapDocument)
        return resetTapTempo();
    SongDocument *const document = m_tapDocument.data();
    if (&m_page.document() != document || document->revision() != m_tapRevision)
        return resetTapTempo();
    // Idempotent: only a difference from the tick-0 tempo writes.
    const int bpm = m_tapTempo.draftBpm();
    const auto &tempoPoints = document->tempoPoints();
    const auto point0 = std::find_if(tempoPoints.cbegin(), tempoPoints.cend(),
                                     [](const TempoPoint &point) { return point.tick == 0; });
    const uint32_t targetUspqn = CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(bpm);
    if (point0 != tempoPoints.cend() && point0->microsecondsPerQuarterNote == targetUspqn)
        return resetTapTempo();
    // One TempoEditCommand per session: the replaceSpan(0, 0, ...) writes a
    // single tempo point, removing any pre-existing tick-0 point. The shared
    // reset clears the draft (emitting draft-cleared) before committed fires.
    m_tempoLane.replaceSpan(0, 0, {{0, bpm}});
    resetTapTempo();
    emit tapTempoCommitted(bpm);
}

void AutomationCanvas::resetTapTempo()
{
    if (m_tapTempo.tapCount() == 0 && !m_tapIdleCommit.isActive())
        return;
    m_tapIdleCommit.stop();
    m_tapTempo.reset();
    m_tapDocument.clear();
    m_tapRevision = 0;
    emit tapTempoDraftChanged();
}
