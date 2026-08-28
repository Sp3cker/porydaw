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

    // Keep the timeline projection and its audio publication ordered after
    // every real document mutation. Dirty-state publication stays on the
    // undo stack, whose index settles after command redo and merge handling.
    connect(&m_document, &SongDocument::documentChanged, this, [this] {
        if (!m_midiBound)
            return;
        rebuildTimeline();
        m_view->updateSong(m_timeline.get());
        emit timelineChanged();
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
    emit timelineChanged();
}

void SongTab::applyMidiStage(SongInfo info, SmfFile smf, int trackBudget)
{
    std::optional<ScrollPosition> scroll;
    if (m_ready) {
        const SongView::ViewState state = m_view->viewState();
        scroll = ScrollPosition{state.scrollPx, state.scrollY};
    }
    m_pendingLoad = PendingLoad{std::move(info), std::move(smf), trackBudget, std::move(scroll)};
    m_midiBound = false;
    m_sidecarBound = false;
    m_voicegroupBound = false;
    m_ready = false;
    m_voicegroupId.reset();
    m_view->prepareForSongReplacement();
    m_view->setEnabled(false);
    m_presentationError.clear();
}

void SongTab::applySidecarStage(bool loaded, ViewSidecar::Snapshot snapshot)
{
    Q_ASSERT(m_pendingLoad.has_value());
    PendingLoad pending = std::move(*m_pendingLoad);
    m_pendingLoad.reset();

    QString error;
    if (!m_document.adoptSmf(std::move(pending.smf), pending.info, &error)) {
        m_presentationError = std::move(error);
        return;
    }
    m_document.setTrackBudget(pending.trackBudget);
    m_midiBound = true;

    std::shared_ptr<const MidiTimeline> timeline(m_document.buildTimeline(m_sampleRate));
    m_view->setDocument(&m_document);
    m_view->setSong(timeline.get(), nullptr);
    m_timeline = std::move(timeline);
    m_voicegroup = {};

    if (loaded) {
        snapshot.editor.setDrawerState(m_view->editorViewState().drawerState());
        m_view->applyEditorViewState(snapshot.editor);
        m_view->applyViewState(snapshot.view);
    }
    if (pending.scroll) {
        SongView::ViewState state = m_view->viewState();
        state.scrollPx = pending.scroll->horizontal;
        state.scrollY = pending.scroll->vertical;
        m_view->applyViewState(state);
    } else if (loaded) {
        m_view->resetScrollPosition();
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
