#pragma once

#include <QWidget>

#include <QString>

#include <memory>
#include <optional>

#include "core/miditimeline.h"
#include "core/songdocument.h"
#include "core/songhistory.h"
#include "project/projectidentity.h"
#include "project/voicegroupsource.h"
#include "ui/viewsidecar.h"

class SongView;

// One open song page: the passive, keyed owner of everything a single song
// edit needs. A SongTab is constructed for one SongName and permanently pairs
// one SongDocument with one SongView and one shared MidiTimeline projection
// of that document. Project operations never enter here: WorkspaceUi applies
// copied stage values through the apply* methods below and reads loaded state
// back through the narrow accessors; MainWindow reads the selected tab
// directly for audio handoff. History is the document's existing SongHistory
// subobject, re-exported unchanged; shared-bank requests route through
// WorkspaceUi's VoicegroupViewCache, never through a second stack.
//
// Load lifecycle: WorkspaceUi delivers MidiStage, SidecarStage, then terminal
// VoicegroupBound, whose lease was adopted from the preceding LoadedBankView;
// later LoadedBankView events replace that lease atomically. The view is
// interactive only once every stage has landed (isReady()). SongSaved adopts
// the save guards on the document; SongFailed records the presentation error
// without unbinding a loaded tab. Document edits rebuild the timeline at the
// copied sample rate and update the paired view, then emit edited() so the
// owner refreshes its titles and dirty chrome.
class SongTab final : public QWidget
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(SongTab)

  public:
    explicit SongTab(SongName name, QWidget *parent = nullptr);
    ~SongTab() override;

    const SongName &name() const { return m_name; }

    SongDocument &document() { return m_document; }
    const SongDocument &document() const { return m_document; }

    // The document's existing history subobject: the tab's only history
    // interface, over exactly its existing QUndoStack.
    SongHistory &history() { return m_document.history(); }

    SongView &view() { return *m_view; }
    const SongView &view() const { return *m_view; }

    // Shared so AudioEngine can retain the active projection across a
    // document-driven rebuild (callback handoff stays internal to audio).
    std::shared_ptr<const MidiTimeline> timeline() const { return m_timeline; }

    // True only after MidiStage, SidecarStage, and VoicegroupBound all landed.
    bool isReady() const { return m_ready; }
    // The last SongFailed message on this tab; empty otherwise.
    const QString &presentationError() const { return m_presentationError; }

    // Null until VoicegroupBound; the lease is empty until this tab's first
    // LoadedBankView arrives.
    const VoicegroupId *voicegroupId() const { return m_voicegroupId ? &*m_voicegroupId : nullptr; }
    VoicegroupLease voicegroupLease() const { return m_voicegroup; }

    // Copied audio sample rate for the timeline projection. A change rebuilds
    // the timeline and updates the paired view.
    void setSampleRate(double sampleRate);
    double sampleRate() const { return m_sampleRate; }

    // ---- Applied stage values (copied; WorkspaceUi unpacks SongUpdate) ----

    // MidiStage: adopts the detached SMF model as this tab's document.
    void applyMidiStage(SongInfo info, SmfFile smf, int trackBudget);
    // SidecarStage: a missing or corrupt sidecar arrives as loaded == false.
    void applySidecarStage(bool loaded, ViewSidecar::Snapshot snapshot);
    // VoicegroupBound: identity only; the lease came with the preceding
    // LoadedBankView.
    void applyVoicegroupBound(VoicegroupId id);
    // LoadedBankView: atomic shared-bank replacement for this tab's
    // voicegroup (initial bind and every later refresh).
    void applyBankView(LoadedBankView view);
    // SongSaved: adopts the save guards; sidecar status stays with the owner.
    void applySongSaved(SongSaveSnapshot snapshot, bool flagsWritten);
    // SongFailed: records the presentation error; a ready tab stays loaded.
    void applySongFailed(const QString &message);

    // ---- Captures for the semantic save seam ------------------------------

    SongSaveSnapshot captureSaveSnapshot() const { return m_document.captureSaveSnapshot(); }
    ViewSidecar::Snapshot captureViewSnapshot() const;

  signals:
    // Emitted after a document edit (including undo/redo) rebuilt the
    // timeline; the owner refreshes titles and dirty chrome.
    void edited();

  private:
    void rebuildTimeline();
    void updateReadiness();

    // Member order is destruction order's reverse: the paired view's raw
    // borrows (timeline, document) must not outlive what they point at.
    SongName m_name;
    SongDocument m_document;
    std::shared_ptr<const MidiTimeline> m_timeline;
    SongView *const m_view;
    std::optional<VoicegroupId> m_voicegroupId;
    VoicegroupLease m_voicegroup;
    double m_sampleRate = 0.0;
    QString m_presentationError;
    bool m_midiBound = false;
    bool m_sidecarBound = false;
    bool m_voicegroupBound = false;
    bool m_ready = false;
};
