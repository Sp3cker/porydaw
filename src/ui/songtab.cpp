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
    delete m_view;
    m_view = nullptr;
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
    // A ready reload reapplies the complete live view state after the swap;
    // a fresh open gets the canonical defaults. Capture before the view
    // detaches from the old song.
    std::optional<SongView::ViewState> restored;
    if (m_ready)
        restored = m_view->viewState();
    m_midiBound = false;
    m_voicegroupBound = false;
    m_ready = false;
    m_voicegroupId.reset();
    m_view->prepareForSongReplacement();
    m_view->setEnabled(false);
    m_presentationError.clear();
    QString error;
    if (!m_document.adoptSmf(std::move(smf), info, &error)) {
        m_presentationError = std::move(error);
        return;
    }
    m_document.setTrackBudget(trackBudget);
    m_midiBound = true;
    // Borrow-safe swap: the local owns the new timeline while the view still
    // borrows the old member-owned one, the member adopts the new timeline
    // only after setSong repoints the view, and the old voicegroup lease is
    // freed only once setSong(..., nullptr) dropped the view's borrow.
    std::shared_ptr<const MidiTimeline> newTimeline(m_document.buildTimeline(m_sampleRate));
    m_view->setDocument(&m_document);
    m_view->setSong(newTimeline.get(), nullptr);
    m_timeline = std::move(newTimeline);
    m_voicegroup = {};
    if (restored) {
        m_view->applyViewState(*restored);
    } else {
        // Canonical fresh defaults: a default-constructed ViewState already
        // carries the Geometry defaults; resetScrollPosition then lands the
        // pre-roll home and the default vertical scroll.
        SongView::ViewState fresh;
        fresh.valid = true;
        m_view->applyViewState(fresh);
        m_view->resetScrollPosition();
    }
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
    // Atomic at the publication seam: the parked old lease outlives the
    // view's borrow; the last lease holder frees the bank after the swap.
    VoicegroupLease oldLease = std::move(m_voicegroup);
    m_voicegroup = std::move(view.bank);
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

void SongTab::rebuildTimeline()
{
    m_timeline = std::shared_ptr<const MidiTimeline>(m_document.buildTimeline(m_sampleRate));
}

void SongTab::updateReadiness()
{
    if (!(m_midiBound && m_voicegroupBound))
        return;
    m_ready = true;
    m_view->setEnabled(true);
}
