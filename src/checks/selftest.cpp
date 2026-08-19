#include "mainwindow.h"

#include <algorithm>
#include <cmath>
#include <cstdint>

#include <QApplication>
#include <QEventLoop>
#include <QFile>
#include <QTimer>

#include "project/songregistry.h"
#include "ui/newsongwizard.h"
#include "ui/settingsdialog.h"
#include "ui/songview.h"
#include "ui/viewsidecar.h"
#include "ui/voicegroupbrowser.h"

bool MainWindow::runSelfTest(const QString &projectRoot, const QString &songLabel)
{
    m_persistSession = false;
    if (!m_audioOk) {
        qWarning("selftest: no audio device available");
        return false;
    }
    QString error;
    if (!m_project.open(projectRoot, &error)) {
        qWarning("selftest: %s", qUtf8Printable(error));
        return false;
    }
    const SongInfo *target = nullptr;
    for (const SongInfo &song : m_project.songs()) {
        if (song.label == songLabel) {
            target = &song;
            break;
        }
    }
    if (!target || !target->isPlayable()) {
        qWarning("selftest: song '%s' not found or has no MIDI source", qUtf8Printable(songLabel));
        return false;
    }
    qInfo("selftest: project opened, %lld songs", (long long)m_project.songs().size());

    loadSong(*target);
    SongSession *tab = m_active;
    if (!tab || !m_audio.songLoaded()) {
        qWarning("selftest: song failed to load");
        return false;
    }
    qInfo("selftest: loaded %s (%zu events, %d tracks)", qUtf8Printable(target->label),
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
    tab->doc.addNote(tab->view->selectionModel().primaryTrack(), 0, 60, 24, 100);
    tab->doc.addLanePoint(tab->view->selectionModel().primaryTrack(), 7, 0, 100);
    if (!tab->doc.isDirty()) {
        qWarning("selftest: document not dirty after edits");
        return false;
    }
    QTimer::singleShot(1500, &loop, &QEventLoop::quit);
    loop.exec();
    tab->doc.undoStack()->undo();
    tab->doc.undoStack()->undo();
    if (tab->doc.isDirty()) {
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

    // Voicegroup editing through the unified pipeline: a scalar edit pokes
    // the live ToneData, a sample swap goes through the .porydaw/vgpreview
    // shadow reload — both land on the song's undo stack, and undoing them
    // restores the on-disk state — all without changing project files.
    bool vgEditOk = true;
    if (tab->vgSource) {
        int dsSlot = -1, donorSlot = -1;
        for (int i = 0; i < VOICEGROUP_SIZE; i++) {
            const VgVoice *v = tab->vgSource->voiceAt(i);
            // DirectSound family only: keysplit/drumkit voices are non-CGB
            // too, but have no scalar fields and take sub-voicegroup symbols,
            // not samples.
            if (!v ||
                (v->macro != VgMacro::DirectSound && v->macro != VgMacro::DirectSoundNoResample &&
                 v->macro != VgMacro::DirectSoundAlt))
                continue;
            if (dsSlot < 0)
                dsSlot = i;
            else if (donorSlot < 0 && v->symbol != tab->vgSource->voiceAt(dsSlot)->symbol)
                donorSlot = i;
        }
        if (dsSlot >= 0) {
            m_vgBrowser->selectSlot(dsSlot); // exercises the editor panel too
            QByteArray fileBefore;
            {
                QFile in(tab->vgSource->filePath());
                if (!in.open(QIODevice::ReadOnly)) {
                    qWarning("selftest: cannot read voicegroup source %s",
                             qUtf8Printable(tab->vgSource->filePath()));
                    return false;
                }
                fileBefore = in.readAll();
            }
            const VgVoice original = *tab->vgSource->voiceAt(dsSlot);
            const QByteArray originalName(m_audio.voicegroup()->voiceNames[dsSlot]);
            int undosNeeded = 1;
            VgVoice v = original;
            v.release = v.release == 25 ? 26 : 25;
            onVoiceEditRequested(dsSlot, v, false);
            vgEditOk = tab->vgSource->dirty() && tab->doc.isDirty() &&
                       m_audio.voicegroup()->voices[dsSlot].release == uint8_t(v.release);
            if (donorSlot >= 0) {
                undosNeeded = 2; // structural edits never merge with scalar ones
                const QByteArray donorName(m_audio.voicegroup()->voiceNames[donorSlot]);
                v.symbol = tab->vgSource->voiceAt(donorSlot)->symbol;
                onVoiceEditRequested(dsSlot, v, true);
                vgEditOk = vgEditOk &&
                           QByteArray(m_audio.voicegroup()->voiceNames[dsSlot]) == donorName &&
                           m_audio.transport() == Transport::Playing;
            }
            // Voice edits ride the song's undo stack; undoing them all must
            // land back on the exact on-disk state (clean, nothing written).
            for (int i = 0; i < undosNeeded; i++)
                tab->doc.undoStack()->undo();
            QByteArray fileAfter;
            {
                QFile in(tab->vgSource->filePath());
                if (!in.open(QIODevice::ReadOnly)) {
                    qWarning("selftest: cannot read voicegroup source %s",
                             qUtf8Printable(tab->vgSource->filePath()));
                    return false;
                }
                fileAfter = in.readAll();
            }
            vgEditOk = vgEditOk && !tab->vgSource->dirty() && !tab->doc.isDirty() &&
                       fileAfter == fileBefore && *tab->vgSource->voiceAt(dsSlot) == original &&
                       m_audio.voicegroup()->voices[dsSlot].release == uint8_t(original.release) &&
                       QByteArray(m_audio.voicegroup()->voiceNames[dsSlot]) == originalName;
            if (vgEditOk)
                qInfo("selftest: voicegroup edit + preview reload + undo OK "
                      "(slot %d, donor %d)",
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
        NewSongWizard wizard(&m_project, vgCatalog().groupArgs, this);
        const auto songTarget = SongTarget{tab->doc.cfg(), tab->doc.label()};
        SettingsDialog settingsDialog(m_engineSettings, songTarget, vgCatalog().groupArgs,
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
        const double pausedViewTick = tab->view->playheadTick();
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

            tab->view->commitEditCursor(pausedTargetTick);
            const double immediateViewTick = tab->view->playheadTick();
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
        tab->view->commitEditCursor(seekTick); // transport is Playing: seeks
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
        SongRegistry::saveRegistrationMeta(m_project.root(), target->label,
                                           QStringLiteral("MUS_SELFTEST"),
                                           QStringLiteral("MUSIC_PLAYER_BGM"));
        tab->view->setGridMinDenom(8); // non-default grid must round-trip too
        tab->view->setGridFeel(SongView::GridFeel::Triplet);
        tab->view->setLaneDisplayRange(0, 0x01, 16); // MOD axis zoom, ditto
        const ViewSidecar::Snapshot saved{tab->view->viewState(), tab->view->editorViewState()};
        ok = ViewSidecar::save(m_project.root(), target->label, saved);
        tab->view->zoomAroundContentX(2.0, 0); // knock the view off the state
        tab->view->setGridMinDenom(0);
        tab->view->setGridFeel(SongView::GridFeel::Straight);
        tab->view->setLaneDisplayRange(0, 0x01, 0); // back to the MOD default
        ViewSidecar::Snapshot loaded;
        ok = ok && ViewSidecar::load(m_project.root(), target->label, &loaded);
        if (ok) {
            tab->view->applyViewState(loaded.view);
            loaded.editor.setDrawerState(m_editorDrawerState);
            tab->view->applyEditorViewState(loaded.editor);
            const ViewSidecar::Snapshot restored{tab->view->viewState(),
                                                 tab->view->editorViewState()};
            QString constant, player;
            ok = std::abs(restored.view.pxPerBeat - saved.view.pxPerBeat) < 0.001 &&
                 std::abs(restored.view.keyHeight - saved.view.keyHeight) < 0.001 &&
                 std::abs(restored.view.scrollPx - saved.view.scrollPx) < 0.001 &&
                 std::abs(restored.view.scrollY - saved.view.scrollY) < 0.001 &&
                 restored.view.selectedTrack == saved.view.selectedTrack &&
                 restored.view.editCursorTick == saved.view.editCursorTick &&
                 restored.view.gridMinDenom == 8 && restored.view.gridTriplet &&
                 restored.editor == saved.editor &&
                 SongRegistry::loadRegistrationMeta(m_project.root(), target->label, &constant,
                                                    &player) &&
                 constant == QLatin1String("MUS_SELFTEST");
        }
        QFile::remove(ViewSidecar::pathFor(m_project.root(), target->label));
        tab->view->setGridMinDenom(0);                        // don't leak the test grid into a
        tab->view->setGridFeel(SongView::GridFeel::Straight); // shutdown save
        tab->view->setLaneDisplayRange(0, 0x01, 0);           // nor the MOD axis zoom
        if (ok)
            qInfo("selftest: sidecar view-state round trip OK");
        else
            qWarning("selftest: sidecar view-state round trip FAILED");
    }
    if (ok) {
        destroySession(tab);
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
