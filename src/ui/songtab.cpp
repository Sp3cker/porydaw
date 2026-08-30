#include "ui/songtab.h"

#include <QChildEvent>
#include <QEvent>
#include <QObject>
#include <QVBoxLayout>

#include <utility>

class SongTab::InputGate final : public QObject
{
  public:
    explicit InputGate(SongTab *tab) : QObject(tab), m_tab(tab) {}

    void watch(QObject *object)
    {
        object->installEventFilter(this);
        const auto children = object->children();
        for (QObject *child : children)
            watch(child);
    }
    void onReadinessChanged()
    {
        if (!m_tab->isReady())
            m_tab->view().cancelTransientInput();
    }

  protected:
    bool eventFilter(QObject *, QEvent *event) override
    {
        if (event->type() == QEvent::ChildAdded)
            watch(static_cast<QChildEvent *>(event)->child());
        if (isUserInputEvent(event->type()) && !m_tab->isReady())
            return true;
        return false;
    }

  private:
    static bool isUserInputEvent(QEvent::Type type)
    {
        switch (type) {
        case QEvent::MouseButtonPress:
        case QEvent::MouseButtonRelease:
        case QEvent::MouseButtonDblClick:
        case QEvent::MouseMove:
        case QEvent::Wheel:
        case QEvent::ContextMenu:
        case QEvent::KeyPress:
        case QEvent::KeyRelease:
        case QEvent::Shortcut:
        case QEvent::ShortcutOverride:
        case QEvent::InputMethod:
        case QEvent::InputMethodQuery:
        case QEvent::FocusIn:
        case QEvent::TabletPress:
        case QEvent::TabletMove:
        case QEvent::TabletRelease:
        case QEvent::TabletEnterProximity:
        case QEvent::TabletLeaveProximity:
        case QEvent::TouchBegin:
        case QEvent::TouchUpdate:
        case QEvent::TouchEnd:
        case QEvent::TouchCancel:
        case QEvent::Gesture:
        case QEvent::GestureOverride:
        case QEvent::NativeGesture:
        case QEvent::DragEnter:
        case QEvent::DragMove:
        case QEvent::DragLeave:
        case QEvent::Drop:
            return true;
        default:
            return false;
        }
    }

    SongTab *m_tab; // non-owning; SongTab owns this filter
};

SongTab::SongTab(SongName name, QWidget *parent)
    : QWidget(parent)
    , m_name(std::move(name))
    , m_document(this)
    , m_view(new SongView(this))
{
    auto *pageLayout = new QVBoxLayout(this);
    pageLayout->setContentsMargins(0, 0, 0, 0);
    pageLayout->addWidget(m_view);
    m_inputGate = new InputGate(this);
    m_inputGate->watch(m_view);
    connect(this, &SongTab::readinessChanged, m_inputGate, &InputGate::onReadinessChanged);

    // Keep the timeline projection and its audio publication ordered after
    // every real document mutation. Dirty-state publication stays on the
    // undo stack, whose index settles after command redo and merge handling.
    connect(&m_document, &SongDocument::documentChanged, this, [this] {
        if (!m_midiBound)
            return;
        rebuildTimeline();
        emit timelineChanged();
    });
    connect(m_document.undoStack(), &QUndoStack::indexChanged, this, [this] {
        if (m_midiBound)
            emit edited();
    });

    // Loading stages arrive asynchronously; the gate keeps presentation
    // enabled while only user input waits for both terminal facts.
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
    emit timelineChanged();
}

void SongTab::beginMidiReload()
{
    m_pendingReloadState = m_view->viewState();
    applyLoadEvent(LoadEvent::ReloadDispatched);
}

void SongTab::applyMidiStage(SongInfo info, SmfFile smf, int trackBudget)
{
    std::optional<SongView::ViewState> restored = std::move(m_pendingReloadState);
    m_pendingReloadState.reset();
    m_view->prepareForSongReplacement();
    m_presentationError.clear();
    QString error;
    if (!m_document.adoptSmf(std::move(smf), info, &error)) {
        m_presentationError = std::move(error);
        return;
    }
    m_document.setTrackBudget(trackBudget);
    // Borrow-safe swap: the local owns the new timeline while the view still
    // borrows the old member-owned one. The member adopts the new timeline
    // only after setSong repoints the view's timeline borrow.
    std::shared_ptr<const MidiTimeline> newTimeline(m_document.buildTimeline(m_sampleRate));
    const LoadedVoiceGroup *const voicegroup = m_voicegroupBound ? m_voicegroup.get() : nullptr;
    m_view->setDocument(&m_document);
    m_view->setSong(newTimeline.get(), voicegroup);
    m_timeline = std::move(newTimeline);
    // VoicegroupBound may arrive before MidiBound. In that order it already
    // identifies the replacement bank, so only clear the retained old bank
    // when its terminal fact has not landed.
    if (!m_voicegroupBound) {
        m_voicegroup = {};
        m_voicegroupId.reset();
    }
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
    applyLoadEvent(LoadEvent::MidiBound);
}

void SongTab::applyVoicegroupBound(VoicegroupId id)
{
    m_voicegroupId = std::move(id);
    if (!m_voicegroupBound)
        applyLoadEvent(LoadEvent::VoicegroupBound);
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
    std::shared_ptr<const MidiTimeline> newTimeline(m_document.buildTimeline(m_sampleRate));
    m_view->updateSong(newTimeline.get());
    m_timeline = std::move(newTimeline);
}

void SongTab::applyLoadEvent(LoadEvent event)
{
    const bool wasReady = isReady();
    switch (event) {
    case LoadEvent::ReloadDispatched:
        m_midiBound = false;
        m_voicegroupBound = false;
        break;
    case LoadEvent::MidiBound:
        m_midiBound = true;
        break;
    case LoadEvent::VoicegroupBound:
        m_voicegroupBound = true;
        break;
    }
    if (isReady() != wasReady)
        emit readinessChanged();
}
