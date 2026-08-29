#include "harness.h"

#include "checks/support/asyncwait.h"
#include "mainwindow.h"

#include <QEventLoop>
#include <QTimer>

#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/workspaceui.h"

namespace checks {

bool SelfTestHarness::runTimelineScenario()
{
    if (!beginObservedPlayback())
        return false;
    const int editedTrack = m_view->selectionModel().primaryTrack();
    const uint64_t beforeEdit = m_window.m_audio.playheadSamples();
    m_view->document()->addNote(editedTrack, 0, 60, 24, 100);
    m_view->document()->addLanePoint(editedTrack, 7, 0, 100);
    if (!m_tab->document().isDirty()) {
        qWarning("selftest-timeline: document not dirty after edits");
        return false;
    }
    const auto audioUsesTabTimeline = [this] {
        return m_window.m_audio.timeline() == m_tab->timeline().get();
    };
    if (async_wait::waitUntil([this] { return tabIsLive(); },
                              [this, beforeEdit, &audioUsesTabTimeline] {
                                  return audioUsesTabTimeline() &&
                                         m_window.m_audio.transport() == Transport::Playing &&
                                         m_window.m_audio.playheadSamples() > beforeEdit;
                              },
                              2000) != async_wait::Result::Ready) {
        qWarning("selftest-timeline: audio did not adopt the edited timeline while playing");
        return false;
    }
    DocNote moved;
    if (!m_tab->document().findNote(editedTrack, 0, 60, &moved)) {
        qWarning("selftest-timeline: added note was not available for the live-move check");
        return false;
    }
    if (!beginObservedPlayback())
        return false;
    const MidiTimeline *const beforeMoveTimeline = m_tab->timeline().get();
    const uint64_t beforeMove = m_window.m_audio.playheadSamples();
    m_tab->document().moveNotes({moved}, 24, 1);
    if (async_wait::waitUntil([this] { return tabIsLive(); },
                              [this, beforeMoveTimeline, beforeMove, &audioUsesTabTimeline] {
                                  return m_tab->timeline().get() != beforeMoveTimeline &&
                                         audioUsesTabTimeline() &&
                                         m_window.m_audio.transport() == Transport::Playing &&
                                         m_window.m_audio.playheadSamples() > beforeMove;
                              },
                              2000) != async_wait::Result::Ready) {
        qWarning("selftest-timeline: audio did not adopt the moved-note timeline while playing");
        return false;
    }
    if (!beginObservedPlayback())
        return false;
    const uint64_t beforeUndo = m_window.m_audio.playheadSamples();
    m_window.m_workspace->requestUndo();
    m_window.m_workspace->requestUndo();
    m_window.m_workspace->requestUndo();
    if (async_wait::waitUntil([this] { return tabIsLive(); },
                              [this, beforeUndo, &audioUsesTabTimeline] {
                                  return !m_tab->document().isDirty() && audioUsesTabTimeline() &&
                                         m_window.m_audio.transport() == Transport::Playing &&
                                         m_window.m_audio.playheadSamples() > beforeUndo;
                              },
                              2000) != async_wait::Result::Ready) {
        qWarning("selftest-timeline: undo did not restore the live timeline while playing");
        return false;
    }
    qInfo("selftest-timeline: edit + move + undo OK (playhead %.2fs at edit)",
          double(beforeEdit) / m_window.m_audio.sampleRate());
    if (!beginObservedPlayback())
        return false;
    const uint64_t beforePreview = m_window.m_audio.playheadSamples();
    m_window.m_audio.previewVoice(0, 60, 112);
    QEventLoop previewWait;
    QTimer::singleShot(300, &previewWait, &QEventLoop::quit);
    previewWait.exec();
    m_window.m_audio.previewVoice(0, 60, 0);
    if (m_window.m_audio.transport() != Transport::Playing ||
        m_window.m_audio.playheadSamples() <= beforePreview) {
        qWarning("selftest-timeline: voice preview did not preserve playback");
        return false;
    }
    qInfo("selftest-timeline: voice audition through the preview engine OK");
    return closeCleanly();
}

} // namespace checks
