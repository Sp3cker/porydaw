#include "checks/support/asyncwait.h"
#include "checks/support/voicegroupbrowserdriver.h"
#include "mainwindow.h"

#include <algorithm>
#include <cmath>
#include <cstdint>

#include <QApplication>
#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QLineEdit>
#include <QTimer>

#include "project/songregistry.h"
#include "ui/dragspinbox.h"
#include "ui/newsongwizard.h"
#include "ui/settingsdialog.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/viewsidecar.h"
#include "ui/voicegroupbrowser.h"
#include "ui/workspaceui.h"

bool MainWindow::runSelfTest(const QString &projectRoot, const QString &songLabel)
{
    m_persistSession = false;
    if (!m_audioOk) {
        qWarning("selftest: no audio device available");
        return false;
    }
    // Open through the production seam and settle on the published
    // ProjectState instead of request bookkeeping.
    m_workspace->requestProjectOpenAt(projectRoot);
    if (checks::async_wait::waitUntil([] { return true; },
                                      [this] {
                                          const ProjectOpenState state =
                                              m_workspace->projectState().state;
                                          return state == ProjectOpenState::Ready ||
                                                 state == ProjectOpenState::Failed;
                                      }) != checks::async_wait::Result::Ready ||
        m_workspace->projectState().state != ProjectOpenState::Ready) {
        qWarning("selftest: project failed to open");
        return false;
    }
    const QString rootDir = m_workspace->projectState().snapshot.root();
    const QVector<SongInfo> &songs = m_workspace->projectState().snapshot.songs();
    const SongInfo *target = nullptr;
    for (const SongInfo &song : songs) {
        if (song.label == songLabel) {
            target = &song;
            break;
        }
    }
    if (!target || !target->isPlayable()) {
        qWarning("selftest: song '%s' not found or has no MIDI source", qUtf8Printable(songLabel));
        return false;
    }
    const SongInfo targetSong = *target;
    qInfo("selftest: project opened, %lld songs", (long long)songs.size());

    const auto songName = SongName::create(targetSong.label);
    if (!songName) {
        qWarning("selftest: invalid song label '%s'", qUtf8Printable(targetSong.label));
        return false;
    }
    m_workspace->requestSongOpen(*songName);
    SongTab *tab = m_workspace->songTabFor(*songName);
    const auto loadWait = checks::async_wait::waitUntil(
        [this, tab] { return tab && m_workspace->songTabFor(tab->name()) == tab; },
        [tab] { return tab->isReady(); });
    if (loadWait != checks::async_wait::Result::Ready) {
        const char *reason = loadWait == checks::async_wait::Result::Destroyed
                                 ? "tab destroyed before async load completed"
                                 : "timed out waiting for SongTab::isReady()";
        qWarning("selftest: %s for '%s'", reason, qUtf8Printable(targetSong.label));
        return false;
    }
    if (!tab || !m_audio.songLoaded()) {
        qWarning("selftest: song failed to load");
        return false;
    }
    SongView &view = tab->view();
    qInfo("selftest: loaded %s (%zu events, %d tracks)", qUtf8Printable(targetSong.label),
          m_audio.timeline()->events.size(), m_audio.timeline()->usedTrackCount);
    // Realize the shown window before timed playback, especially under
    // profilers where deferred widget setup may otherwise consume the run.
    QApplication::processEvents();

    startPlayback();
    QEventLoop loop;
    QTimer::singleShot(1500, &loop, &QEventLoop::quit);
    loop.exec();

    // M2: edit during playback — exercises the documentChanged plumbing
    // (timeline rebuild, playhead-preserving audio swap, view refresh).
    const uint64_t posBeforeEdit = m_audio.playheadSamples();
    view.document()->addNote(view.selectionModel().primaryTrack(), 0, 60, 24, 100);
    view.document()->addLanePoint(view.selectionModel().primaryTrack(), 7, 0, 100);
    if (!tab->document().isDirty()) {
        qWarning("selftest: document not dirty after edits");
        return false;
    }
    QTimer::singleShot(1500, &loop, &QEventLoop::quit);
    loop.exec();
    m_workspace->requestUndo();
    m_workspace->requestUndo();
    if (tab->document().isDirty()) {
        qWarning("selftest: document still dirty after undoing all edits");
        return false;
    }
    qInfo("selftest: edit + undo during playback OK (playhead %.2fs at edit)",
          double(posBeforeEdit) / m_audio.sampleRate());

    // M3: audition a voicegroup entry mid-playback — exercises the preview
    // engine instance (program change + note on a separate engine).
    m_audio.previewVoice(0, 60, 112);
    QTimer::singleShot(300, &loop, &QEventLoop::quit);
    loop.exec();
    m_audio.previewVoice(0, 60, 0);
    qInfo("selftest: voice audition through the preview engine OK");

    VoicegroupBrowser *const browser = findChild<VoicegroupBrowser *>();
    if (!browser) {
        qWarning("selftest: voicegroup browser not found");
        return false;
    }
    // Voicegroup editing through the production picker pipeline: the browser
    // editor submits the edited voice, ProjectWorkspace re-renders and
    // reloads the shared bank, and each applied edit lands on the song's
    // undo stack — undoing them restores the on-disk state — all without
    // changing project files.
    bool vgEditOk = true;
    const LoadedVoiceGroup *const bank = m_audio.voicegroup();
    if (tab->voicegroupId() && bank) {
        checks::VoicegroupBrowserDriver voicegroupDriver(*m_workspace);
        // The slot tree's first column renders "%03d  symbol-or-name".
        const auto rowSymbol = [&voicegroupDriver](int slot) {
            return voicegroupDriver.slotRowText(slot).value(0).mid(5);
        };
        int dsSlot = -1, donorSlot = -1;
        for (int i = 0; i < VOICEGROUP_SIZE; i++) {
            const ToneData &tone = bank->voices[i];
            // DirectSound family only: keysplit/drumkit voices are non-CGB
            // too, but have no scalar fields and take sub-voicegroup symbols,
            // not samples. The loader pads undefined slots with zeroed
            // DirectSound tones whose names are empty.
            const bool directSound = tone.type == VOICE_DIRECTSOUND ||
                                     tone.type == VOICE_DIRECTSOUND_NO_RESAMPLE ||
                                     tone.type == VOICE_DIRECTSOUND_ALT;
            if (!directSound || QByteArray(bank->voiceNames[i]).isEmpty())
                continue;
            if (dsSlot < 0)
                dsSlot = i;
            else if (donorSlot < 0 && rowSymbol(i) != rowSymbol(dsSlot))
                donorSlot = i;
        }
        if (dsSlot >= 0) {
            const auto tabLive = [this, tab] {
                return tab && m_workspace->songTabFor(tab->name()) == tab;
            };
            // A bank transition settles when the shared-bank gate reopens
            // and the engine carries the reloaded bank.
            const auto waitForBank = [this, &tabLive](const auto &applied) {
                return checks::async_wait::waitUntil(tabLive, [this, &applied] {
                    return m_workspace->bankActionsEnabled() && applied();
                });
            };
            browser->selectSlot(dsSlot); // exercises the editor panel too
            DragSpinBox *const releaseSpin = voicegroupDriver.releaseSpinBox();
            if (!releaseSpin || releaseSpin->value() != int(bank->voices[dsSlot].release)) {
                qWarning("selftest: voicegroup editor did not show slot %d", dsSlot);
                return false;
            }
            const int originalRelease = bank->voices[dsSlot].release;
            const ToneData originalTone = bank->voices[dsSlot];
            const QByteArray originalName(bank->voiceNames[dsSlot]);
            const QString sourcePath =
                QDir(rootDir).filePath(tab->voicegroupId()->sourceRelativePath());
            QByteArray fileBefore;
            {
                QFile in(sourcePath);
                if (!in.open(QIODevice::ReadOnly)) {
                    qWarning("selftest: cannot read voicegroup source %s",
                             qUtf8Printable(sourcePath));
                    return false;
                }
                fileBefore = in.readAll();
            }
            int undosNeeded = 1;
            const int flippedRelease = originalRelease == 25 ? 26 : 25;
            releaseSpin->setValue(flippedRelease);
            const auto scalarWait = waitForBank(
                [&] { return m_audio.voicegroup()->voices[dsSlot].release == flippedRelease; });
            vgEditOk = m_workspace->selectedSongDirty() && !tab->document().isDirty() &&
                       scalarWait == checks::async_wait::Result::Ready &&
                       m_audio.voicegroup()->voices[dsSlot].release == flippedRelease;
            if (donorSlot >= 0) {
                const QByteArray donorName(bank->voiceNames[donorSlot]);
                const QString donorSymbol = rowSymbol(donorSlot);
                voicegroupDriver.openSamplePickerPopup();
                QLineEdit *const search = voicegroupDriver.samplePickerFilterField();
                if (search && voicegroupDriver.samplePickerPopupIsVisible()) {
                    search->setText(donorSymbol);
                    if (voicegroupDriver.currentPickerRowSymbol() == donorSymbol) {
                        undosNeeded = 2; // structural edits never merge with scalar ones
                        voicegroupDriver.clickCurrentPickerRow(); // first click selects
                        voicegroupDriver.clickCurrentPickerRow(); // second click commits
                        const auto structuralWait = waitForBank([&] {
                            return QByteArray(m_audio.voicegroup()->voiceNames[dsSlot]) ==
                                   donorName;
                        });
                        vgEditOk =
                            vgEditOk && structuralWait == checks::async_wait::Result::Ready &&
                            QByteArray(m_audio.voicegroup()->voiceNames[dsSlot]) == donorName &&
                            m_audio.transport() == Transport::Playing;
                    } else {
                        voicegroupDriver.hideSamplePickerPopup();
                        qInfo("selftest: structural voicegroup edit skipped "
                              "(donor row not selectable)");
                    }
                } else {
                    voicegroupDriver.hideSamplePickerPopup();
                    qInfo("selftest: structural voicegroup edit skipped (picker unavailable)");
                }
            }
            // Voice edits ride the song's undo stack; undoing them all must
            // land back on the exact on-disk state (clean, nothing written).
            if (undosNeeded == 2) {
                m_workspace->requestUndo(); // revert the symbol swap first
                vgEditOk =
                    vgEditOk &&
                    waitForBank([&] {
                        return QByteArray(m_audio.voicegroup()->voiceNames[dsSlot]) == originalName;
                    }) == checks::async_wait::Result::Ready;
            }
            m_workspace->requestUndo(); // then the release poke
            vgEditOk =
                vgEditOk &&
                waitForBank([&] {
                    return m_audio.voicegroup()->voices[dsSlot].release == originalRelease &&
                           QByteArray(m_audio.voicegroup()->voiceNames[dsSlot]) == originalName;
                }) == checks::async_wait::Result::Ready;
            QByteArray fileAfter;
            {
                QFile in(sourcePath);
                if (!in.open(QIODevice::ReadOnly)) {
                    qWarning("selftest: cannot read voicegroup source %s",
                             qUtf8Printable(sourcePath));
                    return false;
                }
                fileAfter = in.readAll();
            }
            const ToneData &restored = m_audio.voicegroup()->voices[dsSlot];
            vgEditOk =
                vgEditOk && !m_workspace->selectedSongDirty() && !tab->document().isDirty() &&
                fileAfter == fileBefore && restored.type == originalTone.type &&
                restored.key == originalTone.key && restored.length == originalTone.length &&
                restored.panSweep == originalTone.panSweep &&
                restored.attack == originalTone.attack && restored.decay == originalTone.decay &&
                restored.sustain == originalTone.sustain &&
                restored.release == originalTone.release &&
                QByteArray(m_audio.voicegroup()->voiceNames[dsSlot]) == originalName;
            if (vgEditOk)
                qInfo("selftest: voicegroup edit + bank reload + undo OK (slot %d, donor %d)",
                      dsSlot, donorSlot);
            else
                qWarning("selftest: voicegroup edit FAILED (slot %d, donor %d)", dsSlot, donorSlot);
        } else {
            qInfo("selftest: voicegroup edit skipped (no sample voices)");
        }
    } else {
        qInfo("selftest: voicegroup edit skipped (no editable source)");
    }

    // App settings: the global engine knobs (SPEC §7) re-applied mid-playback
    // through updateSettings — mixer, polyphony clamp, mix-rate rebuild
    // (reverb delay line resize), and analog filter — must keep the transport
    // running.
    {
        SongSettings tweaked = songSettingsFor(*tab);
        tweaked.pcmMixer =
            tweaked.pcmMixer == M4A_PCM_MIXER_IPATIX ? M4A_PCM_MIXER_SAPPY : M4A_PCM_MIXER_IPATIX;
        tweaked.maxPcmChannels = 8;
        tweaked.pcmMixRate = 21024.0f;
        tweaked.analogFilter = !tweaked.analogFilter;
        m_audio.updateSettings(tweaked);
        const uint64_t before = m_audio.playheadSamples();
        QTimer::singleShot(300, &loop, &QEventLoop::quit);
        loop.exec();
        const bool engineOk =
            m_audio.pcmMixerMode() == tweaked.pcmMixer && m_audio.maxPcmChannels() == 8 &&
            m_audio.playheadSamples() != before && m_audio.transport() == Transport::Playing;
        m_audio.updateSettings(songSettingsFor(*tab));
        if (!engineOk) {
            qWarning("selftest: engine-settings update mid-playback FAILED "
                     "(mixer %d, maxPcm %d, transport %d)",
                     int(m_audio.pcmMixerMode()), m_audio.maxPcmChannels(),
                     int(m_audio.transport()));
            return false;
        }
        qInfo("selftest: engine-settings update mid-playback OK");
    }

    // M3: the onboarding UI must at least construct against a live project
    // (wizard pages enumerate voicegroups/players). Registration itself is
    // write-through now, exercised by --onboardcheck against a scratch copy.
    {
        const ProjectState &project = m_workspace->projectState();
        NewSongWizard::ProjectData projectData;
        projectData.songs = project.snapshot.songs();
        projectData.players = project.snapshot.players();
        projectData.voicegroupArgs = project.catalog.groupArgs;
        projectData.canCreateVoicegroup = project.catalog.perFileVoicegroups;
        NewSongWizard wizard(projectData, this);
        const SongTarget songTarget{tab->document().cfg(), tab->document().label()};
        SettingsDialog settingsDialog(m_engineSettings, songTarget, project.catalog.groupArgs,
                                      SettingsDialog::Tab::Engine, this);
        qInfo("selftest: New Song wizard + unified settings dialog constructed");
    }

    const double playedSeconds = double(m_audio.playheadSamples()) / m_audio.sampleRate();
    qInfo("selftest: after 3s wall clock — playhead %.2fs, transport %d, PCM %d/%d active",
          playedSeconds, int(m_audio.transport()), m_audio.activePcmChannels(),
          m_audio.maxPcmChannels());

    bool ok = m_audio.transport() == Transport::Playing && playedSeconds > 1.0 &&
              m_audio.playheadSamples() >= posBeforeEdit && vgEditOk;
    if (ok) {
        pausePlayback();
        QTimer::singleShot(150, &loop, &QEventLoop::quit);
        loop.exec();
        const uint64_t pausedSample = m_audio.playheadSamples();
        const double pausedViewTick = view.playheadTick();
        const double pausedEngineTick = m_audio.timeline()->tickForSample(pausedSample);
        constexpr double kPausedPlayheadToleranceTicks = 0.25;
        ok = std::abs(pausedViewTick - pausedEngineTick) <= kPausedPlayheadToleranceTicks;
        if (!ok) {
            qWarning("selftest: paused playhead reconciliation FAILED "
                     "(view %.3f ticks, engine %.3f ticks at %llu samples)",
                     pausedViewTick, pausedEngineTick,
                     static_cast<unsigned long long>(pausedSample));
        }

        if (ok) {
            const MidiTimeline *tl = m_audio.timeline();
            const uint64_t maxTick = (tl && tl->lengthTicks > 0) ? tl->lengthTicks - 1 : 9600;
            const uint64_t pausedTargetTick =
                (pausedViewTick >= 960.0)
                    ? static_cast<uint64_t>(pausedViewTick - 480.0)
                    : std::min<uint64_t>(static_cast<uint64_t>(pausedViewTick + 960.0), maxTick);

            view.commitEditCursor(pausedTargetTick);
            const double immediateViewTick = view.playheadTick();
            const bool pausedViewOk = std::abs(immediateViewTick - double(pausedTargetTick)) <=
                                      kPausedPlayheadToleranceTicks;
            if (!pausedViewOk) {
                qWarning("selftest: paused edit-cursor visible playhead FAILED "
                         "(target %llu ticks, view %.3f ticks)",
                         static_cast<unsigned long long>(pausedTargetTick), immediateViewTick);
            }

            QTimer::singleShot(200, &loop, &QEventLoop::quit);
            loop.exec();
            const uint64_t afterPausedSeekSample = m_audio.playheadSamples();
            const double afterPausedSeekEngineTick =
                m_audio.timeline()->tickForSample(afterPausedSeekSample);
            const bool pausedEngineOk =
                std::abs(afterPausedSeekEngineTick - double(pausedTargetTick)) <=
                kPausedPlayheadToleranceTicks;
            if (!pausedEngineOk) {
                qWarning("selftest: paused edit-cursor engine seek FAILED "
                         "(target %llu ticks, engine %.3f ticks at %llu samples)",
                         static_cast<unsigned long long>(pausedTargetTick),
                         afterPausedSeekEngineTick,
                         static_cast<unsigned long long>(afterPausedSeekSample));
            }

            ok = pausedViewOk && pausedEngineOk;
            if (ok) {
                qInfo("selftest: paused edit-cursor seek OK "
                      "(target %llu ticks, view %.3f ticks, engine %.3f ticks)",
                      static_cast<unsigned long long>(pausedTargetTick), immediateViewTick,
                      afterPausedSeekEngineTick);
            }
        }

        if (ok)
            startPlayback();
    }

    // M2 polish: edit-cursor seek mid-playback, then play-from-cursor out of
    // Stopped (both go through AudioEngine::seek + chase). Loop disabled so
    // a wrap can't drop the playhead below the seek target.
    if (ok) {
        m_audio.setLoopEnabled(false);
        const MidiTimeline *tl = m_audio.timeline();
        const uint64_t seekTick =
            std::min<uint64_t>(tl->lengthTicks / 2, uint64_t(tl->ticksPerBeat) * 16);
        const uint64_t seekSample = tl->sampleForTick(seekTick);
        view.commitEditCursor(seekTick); // transport is Playing: seeks
        QTimer::singleShot(300, &loop, &QEventLoop::quit);
        loop.exec();
        const uint64_t afterSeek = m_audio.playheadSamples();
        stopPlayback();
        QTimer::singleShot(200, &loop, &QEventLoop::quit);
        loop.exec();
        startPlayback(); // Stopped: must seek back to the edit cursor
        QTimer::singleShot(300, &loop, &QEventLoop::quit);
        loop.exec();
        const uint64_t afterRestart = m_audio.playheadSamples();
        ok = afterSeek >= seekSample && m_audio.transport() == Transport::Playing &&
             afterRestart >= seekSample;
        if (ok)
            qInfo("selftest: edit-cursor seek + play-from-cursor OK (cursor %.2fs)",
                  double(seekSample) / m_audio.sampleRate());
        else
            qWarning("selftest: edit-cursor seek FAILED (cursor %.2fs, playhead %.2fs "
                     "after seek, %.2fs after restart)",
                     double(seekSample) / m_audio.sampleRate(),
                     double(afterSeek) / m_audio.sampleRate(),
                     double(afterRestart) / m_audio.sampleRate());

        // M2 polish: Space out of Paused restarts at the edit cursor rather
        // than resuming from the pause point (the Play button resumes). The
        // playhead had ~300ms past the cursor before the pause; a 150ms
        // check after the restart must land back inside that window.
        if (ok) {
            pausePlayback();
            QTimer::singleShot(200, &loop, &QEventLoop::quit);
            loop.exec();
            const uint64_t pausedAt = m_audio.playheadSamples();
            startPlayback(/*fromEditCursor=*/true); // the Space binding's path
            QTimer::singleShot(150, &loop, &QEventLoop::quit);
            loop.exec();
            const uint64_t afterSpace = m_audio.playheadSamples();
            ok = m_audio.transport() == Transport::Playing && afterSpace >= seekSample &&
                 afterSpace < pausedAt;
            if (ok)
                qInfo("selftest: Space-from-pause restarted at edit cursor OK "
                      "(paused %.2fs, restarted to %.2fs)",
                      double(pausedAt) / m_audio.sampleRate(),
                      double(afterSpace) / m_audio.sampleRate());
            else
                qWarning("selftest: Space-from-pause FAILED (cursor %.2fs, paused "
                         "%.2fs, playhead %.2fs after restart)",
                         double(seekSample) / m_audio.sampleRate(),
                         double(pausedAt) / m_audio.sampleRate(),
                         double(afterSpace) / m_audio.sampleRate());
        }
        m_audio.setLoopEnabled(true);
    }
    // M2 polish: sidecar view-state round trip (SPEC §4.4). Save the live
    // view, mutate it, then confirm applying the loaded state restores it —
    // and that SongRegistry's registration key coexists in the same file.
    if (ok) {
        SongRegistry::saveRegistrationMeta(rootDir, targetSong.label,
                                           QStringLiteral("MUS_SELFTEST"),
                                           QStringLiteral("MUSIC_PLAYER_BGM"));
        view.setGridMinDenom(8); // non-default grid must round-trip too
        view.setGridFeel(SongView::GridFeel::Triplet);
        view.setLaneDisplayRange(0, 0x01, 16); // MOD axis zoom, ditto
        const ViewSidecar::Snapshot saved{view.viewState(), view.editorViewState()};
        ok = ViewSidecar::save(rootDir, targetSong.label, saved);
        view.zoomAroundContentX(2.0, 0); // knock the view off the state
        view.setGridMinDenom(0);
        view.setGridFeel(SongView::GridFeel::Straight);
        view.setLaneDisplayRange(0, 0x01, 0); // back to the MOD default
        ViewSidecar::Snapshot loaded;
        ok = ok && ViewSidecar::load(rootDir, targetSong.label, &loaded);
        if (ok) {
            view.applyViewState(loaded.view);
            loaded.editor.setDrawerState(m_editorDrawerState);
            view.applyEditorViewState(loaded.editor);
            const ViewSidecar::Snapshot restored{view.viewState(), view.editorViewState()};
            QString constant, player;
            ok =
                std::abs(restored.view.pxPerBeat - saved.view.pxPerBeat) < 0.001 &&
                std::abs(restored.view.keyHeight - saved.view.keyHeight) < 0.001 &&
                std::abs(restored.view.scrollPx - saved.view.scrollPx) < 0.001 &&
                std::abs(restored.view.scrollY - saved.view.scrollY) < 0.001 &&
                restored.view.selectedTrack == saved.view.selectedTrack &&
                restored.view.editCursorTick == saved.view.editCursorTick &&
                restored.view.gridMinDenom == 8 && restored.view.gridTriplet &&
                restored.editor == saved.editor &&
                SongRegistry::loadRegistrationMeta(rootDir, targetSong.label, &constant, &player) &&
                constant == QLatin1String("MUS_SELFTEST");
        }
        QFile::remove(ViewSidecar::pathFor(rootDir, targetSong.label));
        view.setGridMinDenom(0);                        // don't leak the test grid into a
        view.setGridFeel(SongView::GridFeel::Straight); // shutdown save
        view.setLaneDisplayRange(0, 0x01, 0);           // nor the MOD axis zoom
        if (ok)
            qInfo("selftest: sidecar view-state round trip OK");
        else
            qWarning("selftest: sidecar view-state round trip FAILED");
    }
    if (ok) {
        // The production close gate prompts when anything is unsaved — which
        // would block a headless run — so prove the unified dirty state
        // (document and shared bank) settled clean before requesting it.
        ok = !m_workspace->selectedSongDirty();
        if (!ok)
            qWarning("selftest: song still dirty before closing its tab");
    }
    if (ok) {
        m_workspace->requestCloseSelectedTab();
        ok = !m_playheadTimer->isActive();
        if (ok)
            qInfo("selftest: closing final tab stopped playhead timer");
        else
            qWarning("selftest: closing final tab left playhead timer active");
    }
    stopPlayback();
    qInfo("selftest: %s", ok ? "PASS" : "FAIL");
    return ok;
}
