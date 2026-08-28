#include "ui/songtab.h"

#include <QVBoxLayout>

#include <utility>

#include "ui/songview.h"

SongTab::SongTab(SongName name, QWidget *parent)
    : QWidget(parent)
    , m_name(std::move(name))
    , m_document(this)
    , m_view(new SongView(this))
{
    auto *pageLayout = new QVBoxLayout(this);
    pageLayout->setContentsMargins(0, 0, 0, 0);
    pageLayout->addWidget(m_view);

    // The paired view consumes the document directly; the tab's remaining
    // document reaction is the timeline projection below.
    connect(&m_document, &SongDocument::documentChanged, this, [this] {
        if (!m_midiBound)
            return;
        rebuildTimeline();
        m_view->updateSong(m_timeline.get());
    });
    connect(m_document.undoStack(), &QUndoStack::indexChanged, this, [this] {
        if (m_midiBound)
            emit edited();
    });

    // Loading stages arrive asynchronously; interaction waits for all of them.
    m_view->setEnabled(false);
}
SongTab::~SongTab()
{
    QObject::disconnect(m_document.undoStack(), nullptr, this, nullptr);
}

void SongTab::setSampleRate(double sampleRate)
{
    if (m_sampleRate == sampleRate)
        return;
    m_sampleRate = sampleRate;
    if (!m_midiBound)
        return;
    rebuildTimeline();
    m_view->updateSong(m_timeline.get());
}

void SongTab::applyMidiStage(SongInfo info, SmfFile smf, int trackBudget)
{
    // A staged load replaces everything the tab showed before. Clear the
    // bound state first so adoptSmf's documentChanged does not rebuild the
    // outgoing timeline.
    m_midiBound = false;
    m_sidecarBound = false;
    m_voicegroupBound = false;
    m_ready = false;
    m_voicegroupId.reset();
    m_voicegroup = {};
    m_view->setVoicegroup(nullptr);
    m_view->setEnabled(false);
    m_presentationError.clear();

    QString error;
    if (!m_document.adoptSmf(std::move(smf), info, &error)) {
        m_presentationError = error;
        return;
    }
    m_document.setTrackBudget(trackBudget);
    m_midiBound = true;

    rebuildTimeline();
    m_view->setSong(m_timeline.get(), nullptr);
    m_view->setDocument(&m_document);
}

void SongTab::applySidecarStage(bool loaded, ViewSidecar::Snapshot snapshot)
{
    if (loaded) {
        snapshot.editor.setDrawerState(m_view->editorViewState().drawerState());
        m_view->applyViewState(snapshot.view);
        m_view->applyEditorViewState(snapshot.editor);
    }
    m_sidecarBound = true;
    updateReadiness();
}

void SongTab::applyVoicegroupBound(VoicegroupId id)
{
    m_voicegroupId = std::move(id);
    m_voicegroupBound = true;
    updateReadiness();
}

void SongTab::applyBankView(LoadedBankView view)
{
    // Atomic at the publication seam: adopt the new lease, then swap the
    // paired view's borrow. The old bank is freed by the last lease holder.
    m_voicegroup = view.bank;
    m_view->setVoicegroup(m_voicegroup.get());
}

void SongTab::applySongSaved(SongSaveSnapshot snapshot, bool flagsWritten)
{
    m_document.didSave(snapshot, flagsWritten);
    m_presentationError.clear();
}

void SongTab::applySongFailed(const QString &message)
{
    m_presentationError = message;
}

ViewSidecar::Snapshot SongTab::captureViewSnapshot() const
{
    return ViewSidecar::Snapshot{m_view->viewState(), m_view->editorViewState()};
}

void SongTab::rebuildTimeline()
{
    m_timeline = std::shared_ptr<const MidiTimeline>(m_document.buildTimeline(m_sampleRate));
}

void SongTab::updateReadiness()
{
    if (!(m_midiBound && m_sidecarBound && m_voicegroupBound))
        return;
    m_ready = true;
    m_view->setEnabled(true);
}
