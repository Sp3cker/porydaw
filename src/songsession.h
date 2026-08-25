#pragma once

#include <QDateTime>
#include <QString>

#include <cstdint>
#include <map>
#include <memory>

#include "core/miditimeline.h"
#include "core/songdocument.h"
#include "project/voicegroupsource.h"

extern "C" {
#include "voicegroup_loader.h"
}

// One open song tab. Each tab is a complete, independent editing session:
// its own document (with its own undo stack — voicegroup edits ride it too),
// built timeline, and loaded voicegroup. AudioEngine shares ownership of the
// active timeline so callback handoff remains internal to audio.
//
// Two tabs sharing a -G voicegroup are deliberately independent copies:
// unsaved voice edits stay inside their tab, and a clean tab whose .inc was
// re-saved from another tab reloads it on activation (vgFileTime below).
// A session-owned Golden Sun synth descriptor: a zero-size WaveData whose
// bytes porydaw fills itself, for synth voices whose definition isn't on
// disk (pending param edits persist only on save) or whose loader-owned
// WaveData is shared and must not be mutated. ToneData.wav points here;
// bytes are patched in place so live tweaks are heard without a reload.
struct SynthToneBuf {
    WaveData wd;
    uint8_t bytes[17];
};

struct SongSession {
    // Must precede doc: reverse destruction then destroys the undo stack and
    // its commands before this stable voicegroup-edit target.
    VoicegroupSourceHolder vgSource;
    SongDocument doc;
    std::shared_ptr<MidiTimeline> timeline;
    LoadedVoiceGroup *voicegroup = nullptr;
    // Keyed by slot; entries outlive any one LoadedVoiceGroup (engine track
    // caches hold ToneData copies pointing here) and are re-installed into a
    // freshly loaded voicegroup by MainWindow::applyPendingSynthTones.
    // std::map: Qt 6.2's QHash can't hold move-only values.
    std::map<int, std::unique_ptr<SynthToneBuf>> synthTones;
    int songId = -1;
    uint64_t pendingMidiRequest = 0;
    uint64_t pendingVgRequest = 0;
    uint64_t pendingVgProbeRequest = 0;
    uint64_t pendingVgSaveRequest = 0;
    uint64_t pendingPreviewRequest = 0;
    // A save owns an immutable SongDocument snapshot; the callback must
    // confirm this request before touching the live session.
    uint64_t pendingSaveRequest = 0;
    // Sidecar load is cosmetic but gates interaction until it resolves.
    uint64_t pendingSidecarRequest = 0;
    bool midiBound = false;
    bool vgBound = false;
    bool sidecarBound = false;
    QString appliedVoicegroupArg;
    int appliedVolume = 127;
    int appliedReverb = -1;
    // On-disk mtime of the voicegroup source at open/save time; a clean tab
    // whose file changed underneath (saved from another tab) reloads it when
    // the tab is activated.
    QDateTime vgFileTime;

    // SongView interaction is available only after every asynchronous
    // binding has landed. The individual flags remain public because
    // loading can still be observed in its three independent states.
    bool isInteractive() const { return midiBound && vgBound && sidecarBound; }

    // The tab's unsaved-changes state: song and voicegroup edits are one
    // document to the user, so every dirty check (tab title, window title,
    // close prompts) must combine both.
    bool isDirty() const { return doc.isDirty() || (vgSource && vgSource->dirty()); }

    ~SongSession()
    {
        if (voicegroup)
            voicegroup_free(voicegroup);
    }
};
