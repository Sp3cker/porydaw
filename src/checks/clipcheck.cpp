// Cross-view system-clipboard checks: two SongViews + two SongDocuments in
// one process share the real QClipboard, exercised through the same key
// events (roll.copy / roll.paste) and public selection/cursor APIs the app
// uses. Covers cross-table note paste with primary-track retargeting, TPB
// conversion, merge time-paste semantics (notes, lanes, tempo), the single
// undo covering a merge, empty-merge no-ops, tiled repeated paste, and the
// ordinary additive note paste — from the roll and, for plain clips, from
// the SongView edit-key path a drawer canvas keys bubble through.
// Deterministic under the offscreen QApplication the checks harness runs;
// no project fixture needed.
#include "core/miditimeline.h"
#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/songview/clip.h"
#include "ui/songview/clipmime.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"

#include <QApplication>
#include <QClipboard>
#include <QEvent>
#include <QKeyEvent>
#include <QMimeData>
#include <QSettings>
#include <QTemporaryDir>

#include <cstdio>
#include <memory>
#include <optional>
#include <vector>

#include "checks/clipcheck_support.h"

namespace {

using clipcheck_support::checkClipboardClip;
using songview::Clip;
using songview::DecodedClip;
using songview::kClipMimeType;
using songview::writeClipboard;

constexpr uint8_t kCcModulation = 0x01;
constexpr uint8_t kCcVolume = 0x07;

struct NoteSpec {
    uint64_t tick = 0;
    uint8_t key = 0;
    uint32_t duration = 0;
    uint8_t velocity = 0;

    bool operator==(const NoteSpec &) const = default;
};

struct LaneSpec {
    uint64_t tick = 0;
    int value = 0;

    bool operator==(const LaneSpec &) const = default;
};

struct TempoSpec {
    uint64_t tick = 0;
    uint32_t microsecondsPerQuarterNote = 0;

    bool operator==(const TempoSpec &) const = default;
};

std::vector<NoteSpec> notesOf(const SongDocument &doc, int engineTrack)
{
    std::vector<NoteSpec> result;
    for (const DocNote &note : doc.notesForTrack(engineTrack))
        result.push_back({note.tick, note.key, note.duration, note.velocity});
    return result;
}

std::vector<LaneSpec> lanesOf(const SongDocument &doc, int engineTrack, uint8_t cc)
{
    std::vector<LaneSpec> result;
    for (const DocLanePoint &point : doc.lanePoints(engineTrack, cc))
        result.push_back({point.tick, point.value});
    return result;
}

std::vector<TempoSpec> tempoOf(const SongDocument &doc)
{
    std::vector<TempoSpec> result;
    for (const TempoPoint &point : doc.tempoPoints())
        result.push_back({point.tick, point.microsecondsPerQuarterNote});
    return result;
}

// A song view with its own document and timeline, wired the way the app
// keeps the projection fresh after every edit.
struct Rig {
    QTemporaryDir temporary;
    SongDocument doc;
    std::unique_ptr<MidiTimeline> timeline;
    SongView view;
    QStringList announcements;
    songview::TimelineInputItem *roll = nullptr;

    Rig()
    {
        auto smf = SmfFile{};
        smf.format = 1;
        smf.division = 24;
        smf.tracks.push_back({{}, 0});
        const auto midPath = temporary.path() + QStringLiteral("/clipcheck.mid");
        auto info = SongInfo{};
        info.label = QStringLiteral("clipcheck");
        info.midPath = midPath;
        info.hasMid = true;
        auto error = QString{};
        if (temporary.isValid() && smf.writeFile(midPath, &error))
            (void)doc.load(info, &error);
    }

    void attach(uint32_t forcedTicksPerBeat = 0)
    {
        timeline = doc.buildTimeline(48000.0);
        if (forcedTicksPerBeat != 0)
            timeline->ticksPerBeat = forcedTicksPerBeat;
        view.resize(1280, 800);
        view.setSong(timeline.get(), nullptr);
        view.setDocument(&doc);
        (void)view.grab();
        {
            auto *quick = view.findChild<songview::TimelineQuickView *>(
                QStringLiteral("timelineQuickCanvas"));
            roll = quick && quick->rootObject()
                       ? quick->rootObject()->findChild<songview::TimelineInputItem *>(
                             QStringLiteral("timelineRollInput"))
                       : nullptr;
        }
        QObject::connect(&view, &SongView::statusMessage, &view,
                         [this](const QString &text) { announcements.push_back(text); });
        if (forcedTicksPerBeat == 0) {
            QObject::connect(&doc, &SongDocument::documentChanged, &view, [this] {
                auto rebuilt = doc.buildTimeline(48000.0);
                view.updateSong(rebuilt.get());
                timeline = std::move(rebuilt);
            });
        }
    }

    bool sendKey(int key, Qt::KeyboardModifiers modifiers)
    {
        if (!roll)
            return false;
        QKeyEvent press(QEvent::KeyPress, key, modifiers);
        QCoreApplication::sendEvent(roll, &press);
        QKeyEvent release(QEvent::KeyRelease, key, modifiers);
        QCoreApplication::sendEvent(roll, &release);
        return true;
    }
};

bool announced(const Rig &rig, const QString &needle)
{
    for (const QString &text : rig.announcements)
        if (text.contains(needle))
            return true;
    return false;
}

std::vector<NoteId> noteIds(const SongDocument &doc, int engineTrack)
{
    std::vector<NoteId> ids;
    for (const DocNote &note : doc.notesForTrack(engineTrack))
        ids.push_back(note.noteId);
    return ids;
}

} // namespace

int runClipCheck()
{
    // The roll consults keymap::Registry for the copy/paste bindings; keep a
    // user's QSettings rebinds out of this harness (same as rollcheck).
    QTemporaryDir settingsDir;
    if (settingsDir.isValid()) {
        QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, settingsDir.path());
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, settingsDir.path());
        QSettings::setDefaultFormat(QSettings::IniFormat);
    }

    auto failures = 0;
    const auto fail = [&failures](const char *what) {
        std::fprintf(stderr, "clipcheck: FAIL %s\n", what);
        failures++;
    };
    const auto expect = [&fail](bool condition, const char *what) {
        if (!condition)
            fail(what);
    };

    // Copy notes in view A; paste in view B: the clip travels through the
    // system clipboard, lands on B's primary track (stored source track is
    // ignored), advances the edit cursor past the pasted notes, selects
    // them, and never touches B's other track.
    {
        Rig a;
        if (a.doc.addTrack(0) < 0) {
            fail("could not add source track in view A");
        } else {
            a.doc.addNotes(0, {{24, 60, 24, 100}, {36, 64, 12, 80}});
            a.attach();
            a.view.selectionModel().setNoteSelection(noteIds(a.doc, 0));
            expect(a.sendKey(Qt::Key_C, Qt::ControlModifier),
                   "view A copy key did not reach the roll");
        }
        const auto copied = checkClipboardClip();
        expect(copied.has_value(), "view A copy did not publish a clip");
        if (copied) {
            expect(copied->ticksPerBeat == 24, "view A clip carries the wrong ticks per beat");
            expect(copied->clip.span == 0, "note copy is not a span-0 clip");
            const auto &tracks = copied->clip.tracks;
            expect(tracks.size() == 1 && tracks[0].track == 0 && tracks[0].notes.size() == 2 &&
                       tracks[0].notes[0].relTick == 0 && tracks[0].notes[0].key == 60 &&
                       tracks[0].notes[0].duration == 24 && tracks[0].notes[0].velocity == 100 &&
                       tracks[0].notes[1].relTick == 12 && tracks[0].notes[1].key == 64 &&
                       tracks[0].notes[1].duration == 12 && tracks[0].notes[1].velocity == 80,
                   "note copy did not encode the selected notes relative to their start");
        }

        Rig target;
        if (!copied || target.doc.addTrack(0) < 0 || target.doc.addTrack(1) < 0) {
            fail("could not build the destination view B");
        } else {
            target.doc.addNotes(0, {{0, 70, 24, 90}});
            target.attach();
            target.view.selectTrack(1);
            target.view.selectionModel().clearNoteSelection();
            target.view.commitEditCursor(48);
            const auto beforePaste = notesOf(target.doc, 0);
            expect(target.sendKey(Qt::Key_V, Qt::ControlModifier),
                   "view B paste roll has no roll widget");
            expect(notesOf(target.doc, 1) ==
                       std::vector<NoteSpec>{{48, 60, 24, 100}, {60, 64, 12, 80}},
                   "notes did not paste onto view B's primary track");
            expect(notesOf(target.doc, 0) == beforePaste,
                   "paste onto the primary track disturbed another track");
            expect(target.view.selectionModel().noteSelection().size() == 2,
                   "pasted notes were not selected");
            expect(target.view.editCursorTick() == 72,
                   "note paste did not advance the edit cursor past the pasted notes");
            expect(announced(target, QStringLiteral("Pasted 2 note(s)")),
                   "note paste did not announce itself");
        }
    }

    // A note clip copied at 24 TPB pastes into a 48-TPB view in destination
    // tick units while preserving its musical position and duration.
    {
        Rig source;
        source.doc.addTrack(0);
        source.doc.addNotes(0, {{0, 60, 24, 100}});
        source.attach();
        source.view.selectionModel().setNoteSelection(noteIds(source.doc, 0));
        if (!source.sendKey(Qt::Key_C, Qt::ControlModifier))
            fail("cross-TPB source copy did not reach the roll");

        Rig target;
        if (target.doc.addTrack(0) < 0) {
            fail("cross-TPB destination could not add a track");
        } else {
            target.doc.addNotes(0, {{0, 70, 24, 90}});
            target.attach(/*forcedTicksPerBeat=*/48);
            target.view.commitEditCursor(24);
            const int undoCountBefore = target.doc.undoStack()->count();
            expect(target.sendKey(Qt::Key_V, Qt::ControlModifier),
                   "cross-TPB paste did not reach the roll");
            expect(notesOf(target.doc, 0) ==
                       std::vector<NoteSpec>{{0, 70, 24, 90}, {24, 60, 48, 100}},
                   "cross-TPB note paste did not use destination tick units");
            expect(target.doc.undoStack()->count() == undoCountBefore + 1,
                   "cross-TPB note paste did not push one undo command");
            expect(target.view.editCursorTick() == 72,
                   "cross-TPB note paste parked the cursor at the wrong musical time");
            expect(announced(target, QStringLiteral("Pasted 1 note(s)")),
                   "cross-TPB note paste was not announced");
            expect(!announced(target, QStringLiteral("ticks per beat differ")),
                   "cross-TPB note paste emitted the obsolete mismatch error");
        }
    }

    // Merge time-paste: destination notes stay (only same-key overlaps
    // trim), a MOD point at another tick in the span stays, a MOD point at
    // the clip's exact tick is replaced, and clip tempo merges even though
    // no time selection is active.
    {
        Rig rig;
        if (rig.doc.addTrack(0) < 0) {
            fail("merge destination could not add a track");
        } else {
            rig.doc.addNotes(0, {{24, 60, 24, 100}, {48, 64, 24, 100}});
            rig.doc.addLanePoint(0, kCcModulation, 36, 40);
            rig.doc.addLanePoint(0, kCcModulation, 60, 70);
            rig.doc.addLanePoint(0, kCcModulation, 96, 40);
            rig.doc.applyTempoEdit({{}, {{0, 500000}, {25, 600000}, {60, 700000}}});
            rig.attach();
            rig.view.commitEditCursor(24);
            rig.view.selectionModel().clearNoteSelection();

            const int undoBeforeMerge = rig.doc.undoStack()->count();
            Clip clip;
            clip.span = 48;
            clip.tracks = {{0, {{0, 60, 24, 120}}}};
            clip.lanes = {{0, kCcModulation, {{23, 110}, {24, 120}}}};
            clip.tempo = {{1, 300000}, {2, 400000}};
            writeClipboard(clip, 48);
            expect(rig.sendKey(Qt::Key_V, Qt::ControlModifier),
                   "merge paste did not reach the roll");
            expect(notesOf(rig.doc, 0) == std::vector<NoteSpec>{{24, 60, 12, 120},
                                                                {36, 60, 12, 100},
                                                                {48, 64, 24, 100}},
                   "converted merge did not keep destination notes and trim overlaps");
            expect(lanesOf(rig.doc, 0, kCcModulation) ==
                       std::vector<LaneSpec>{{36, 120}, {60, 70}, {96, 40}},
                   "converted merge did not coalesce or merge MOD points");
            expect(tempoOf(rig.doc) ==
                       std::vector<TempoSpec>{{0, 500000}, {25, 400000}, {60, 700000}},
                   "converted merge did not coalesce or merge tempo points");
            expect(!rig.view.selectionModel().timeSelection().active(),
                   "merge paste required a live time selection");
            expect(rig.view.editCursorTick() == 48,
                   "converted merge did not park the edit cursor at the scaled span end");
            expect(rig.doc.undoStack()->count() == undoBeforeMerge + 1,
                   "merge paste did not push exactly one undo command");
            expect(announced(rig, QStringLiteral("Merged range")),
                   "merge paste did not announce a merge");

            // One undo reverts the whole merge: notes, lanes, and tempo all
            // return to their pre-paste state.
            rig.doc.undoStack()->undo();
            expect(notesOf(rig.doc, 0) ==
                       std::vector<NoteSpec>{{24, 60, 24, 100}, {48, 64, 24, 100}},
                   "converted merge undo did not restore the destination notes");
            expect(lanesOf(rig.doc, 0, kCcModulation) ==
                       std::vector<LaneSpec>{{36, 40}, {60, 70}, {96, 40}},
                   "converted merge undo did not restore the destination MOD points");
            expect(tempoOf(rig.doc) ==
                       std::vector<TempoSpec>{{0, 500000}, {25, 600000}, {60, 700000}},
                   "converted merge undo did not restore the destination tempo");
        }
    }

    // A clip holding only empty lanes merges nothing: no undo command or
    // cursor move, a useful no-op announcement, and destination notes untouched.
    {
        Rig rig;
        if (rig.doc.addTrack(0) < 0) {
            fail("empty-merge rig could not add a track");
        } else {
            rig.doc.addNotes(0, {{24, 62, 24, 100}});
            rig.doc.addLanePoint(0, kCcVolume, 144, 90);
            rig.attach();
            rig.view.commitEditCursor(120);
            const int undoBefore = rig.doc.undoStack()->count();
            Clip clip;
            clip.span = 48;
            clip.lanes = {{0, kCcVolume, {}}};
            writeClipboard(clip, 24);
            expect(rig.sendKey(Qt::Key_V, Qt::ControlModifier),
                   "empty-merge paste did not reach the roll");
            expect(notesOf(rig.doc, 0) == std::vector<NoteSpec>{{24, 62, 24, 100}},
                   "empty merge touched destination notes");
            expect(lanesOf(rig.doc, 0, kCcVolume) == std::vector<LaneSpec>{{144, 90}},
                   "empty lane cleared an existing in-span volume point");
            expect(rig.doc.undoStack()->count() == undoBefore,
                   "empty merge pushed an undo command");
            expect(rig.view.editCursorTick() == 120, "empty merge moved the edit cursor");
            expect(announced(rig, QStringLiteral("Nothing useful to paste")),
                   "empty merge did not announce the no-op");
        }
    }

    // Repeated Cmd+V of a time clip tiles: each paste lands at the edit
    // cursor, which the previous paste parked at its span end.
    {
        Rig rig;
        if (rig.doc.addTrack(0) < 0) {
            fail("tiling rig could not add a track");
        } else {
            rig.attach();
            rig.view.commitEditCursor(0);
            const int undoBefore = rig.doc.undoStack()->count();
            Clip clip;
            clip.span = 96;
            clip.tracks = {{0, {{0, 60, 24, 100}}}};
            writeClipboard(clip, 24);
            expect(rig.sendKey(Qt::Key_V, Qt::ControlModifier),
                   "first tiling paste did not reach the roll");
            expect(notesOf(rig.doc, 0) == std::vector<NoteSpec>{{0, 60, 24, 100}},
                   "first tiled paste landed at the wrong tick");
            expect(rig.view.editCursorTick() == 96,
                   "first tiled paste parked the cursor at the wrong tick");
            expect(rig.sendKey(Qt::Key_V, Qt::ControlModifier),
                   "second tiling paste did not reach the roll");
            expect(notesOf(rig.doc, 0) ==
                       std::vector<NoteSpec>{{0, 60, 24, 100}, {96, 60, 24, 100}},
                   "repeated time paste did not tile at the span end");
            expect(rig.view.editCursorTick() == 192,
                   "repeated time paste did not advance past the second tile");
            expect(rig.doc.undoStack()->count() == undoBefore + 2,
                   "tiled pastes did not stay one undo command each");
        }
    }

    // Ordinary note copy/paste in one view stays additive, stays span 0 on
    // the clipboard, and lands on the primary track.
    {
        Rig rig;
        if (rig.doc.addTrack(0) < 0) {
            fail("ordinary-paste rig could not add a track");
        } else {
            rig.doc.addNotes(0, {{24, 60, 24, 100}});
            rig.attach();
            rig.view.selectionModel().setNoteSelection(noteIds(rig.doc, 0));
            expect(rig.sendKey(Qt::Key_C, Qt::ControlModifier),
                   "ordinary copy did not reach the roll");
            const auto copied = checkClipboardClip();
            expect(copied.has_value(), "ordinary note copy published no clip");
            if (copied) {
                expect(copied->ticksPerBeat == 24, "ordinary copy carries the wrong TPB");
                expect(copied->clip.span == 0, "ordinary note copy is not a span-0 clip");
                const auto &tracks = copied->clip.tracks;
                expect(tracks.size() == 1 && tracks[0].track == 0 && tracks[0].notes.size() == 1 &&
                           tracks[0].notes[0].relTick == 0 && tracks[0].notes[0].key == 60 &&
                           tracks[0].notes[0].duration == 24 && tracks[0].notes[0].velocity == 100,
                       "ordinary note copy lost the selected note");
            }
            rig.view.selectionModel().clearNoteSelection();
            rig.view.commitEditCursor(48);
            expect(rig.sendKey(Qt::Key_V, Qt::ControlModifier),
                   "ordinary paste did not reach the roll");
            expect(notesOf(rig.doc, 0) ==
                       std::vector<NoteSpec>{{24, 60, 24, 100}, {48, 60, 24, 100}},
                   "ordinary note paste was not additive");
            expect(rig.view.selectionModel().noteSelection().size() == 1,
                   "ordinary paste did not select the inserted note");
            expect(rig.view.editCursorTick() == 72,
                   "ordinary note paste did not advance the cursor past the paste");
            expect(announced(rig, QStringLiteral("Pasted 1 note(s)")),
                   "ordinary note paste did not announce itself");
        }
    }

    // A plain note clip pastes from a non-roll surface too: the SongView
    // edit-key path drawer canvases bubble keys through owns the span-0
    // dispatch as well, so focus on a canvas no longer silently drops it.
    {
        Rig rig;
        if (rig.doc.addTrack(0) < 0) {
            fail("drawer-focus paste rig could not add a track");
        } else {
            rig.doc.addNotes(0, {{24, 60, 24, 100}});
            rig.attach();
            rig.view.selectionModel().setNoteSelection(noteIds(rig.doc, 0));
            expect(rig.sendKey(Qt::Key_C, Qt::ControlModifier),
                   "drawer-focus copy did not reach the roll");
            rig.view.selectionModel().clearNoteSelection();
            rig.view.commitEditCursor(48);
            QKeyEvent press(QEvent::KeyPress, Qt::Key_V, Qt::ControlModifier);
            QCoreApplication::sendEvent(&rig.view, &press);
            QKeyEvent release(QEvent::KeyRelease, Qt::Key_V, Qt::ControlModifier);
            QCoreApplication::sendEvent(&rig.view, &release);
            expect(notesOf(rig.doc, 0) ==
                       std::vector<NoteSpec>{{24, 60, 24, 100}, {48, 60, 24, 100}},
                   "plain clip did not paste through the SongView edit-key path");
            expect(rig.view.selectionModel().noteSelection().size() == 1,
                   "edit-key paste did not select the inserted note");
            expect(rig.view.editCursorTick() == 72,
                   "edit-key paste did not advance the cursor past the paste");
            expect(announced(rig, QStringLiteral("Pasted 1 note(s)")),
                   "edit-key paste did not announce itself");
        }
    }

    // A real time-selection copy also travels through the system clipboard:
    // the span and the in-range notes survive in the payload.
    {
        Rig rig;
        if (rig.doc.addTrack(0) < 0) {
            fail("time-copy rig could not add a track");
        } else {
            rig.doc.addNotes(0, {{0, 60, 24, 100}});
            rig.attach();
            songview::EditorSelectionModel::TimeSelection selection;
            selection.startTick = 0;
            selection.endTick = 96;
            rig.view.selectionModel().setTimeSelection(selection);
            expect(rig.sendKey(Qt::Key_C, Qt::ControlModifier),
                   "time-selection copy did not reach the roll");
            const auto copied = checkClipboardClip();
            expect(copied.has_value(), "time-selection copy published no clip");
            if (copied) {
                expect(copied->clip.span == 96, "time-selection copy lost its span");
                const auto &tracks = copied->clip.tracks;
                expect(tracks.size() == 1 && tracks[0].track == 0 && tracks[0].notes.size() == 1 &&
                           tracks[0].notes[0].relTick == 0 && tracks[0].notes[0].key == 60 &&
                           tracks[0].notes[0].duration == 24 && tracks[0].notes[0].velocity == 100,
                       "time-selection copy did not encode the in-range note");
            }
            expect(announced(rig, QStringLiteral("Copied range")),
                   "time-selection copy did not announce the range");
        }
    }

    // A Tracks time-selection copy keeps notes and MOD lanes from every scoped
    // track. Pasting into a one-track song creates the missing tracks in one
    // undoable range edit.
    {
        Rig source;
        if (source.doc.addTrack(0) < 0 || source.doc.addTrack(0) < 0 ||
            source.doc.addTrack(0) < 0) {
            fail("multi-track copy rig could not add three tracks");
        } else {
            source.doc.addNotes(0, {{12, 60, 12, 90}});
            source.doc.addNotes(1, {{24, 64, 24, 100}});
            source.doc.addNotes(2, {{36, 68, 36, 110}});
            source.doc.addLanePoint(0, kCcModulation, 18, 11);
            source.doc.addLanePoint(1, kCcModulation, 30, 22);
            source.doc.addLanePoint(2, kCcModulation, 42, 33);
            source.attach();
            songview::EditorSelectionModel::TimeSelection selection;
            selection.startTick = 0;
            selection.endTick = 96;
            selection.scope = songview::EditorSelectionModel::TimeSelection::Tracks;
            source.view.selectionModel().setTimeSelectionAndTrackScope(selection, 0x7);
            expect(source.sendKey(Qt::Key_C, Qt::ControlModifier),
                   "multi-track time copy did not reach the roll");
            expect(source.view.selectionModel().timeSelection().active() &&
                       source.view.selectionModel().storedTrackScope() == 0x7,
                   "multi-track time selection did not cover tracks 0..2");
            const auto copied = checkClipboardClip();
            expect(copied.has_value(), "multi-track time copy published no clip");
            if (copied) {
                const auto &tracks = copied->clip.tracks;
                const auto &lanes = copied->clip.lanes;
                expect(copied->clip.span == 96 && tracks.size() == 3 && lanes.size() == 6 &&
                           tracks[0].track == 0 && tracks[0].notes.size() == 1 &&
                           tracks[0].notes[0].relTick == 12 && tracks[0].notes[0].key == 60 &&
                           tracks[0].notes[0].duration == 12 && tracks[0].notes[0].velocity == 90 &&
                           tracks[1].track == 1 && tracks[1].notes.size() == 1 &&
                           tracks[1].notes[0].relTick == 24 && tracks[1].notes[0].key == 64 &&
                           tracks[1].notes[0].duration == 24 &&
                           tracks[1].notes[0].velocity == 100 && tracks[2].track == 2 &&
                           tracks[2].notes.size() == 1 && tracks[2].notes[0].relTick == 36 &&
                           tracks[2].notes[0].key == 68 && tracks[2].notes[0].duration == 36 &&
                           tracks[2].notes[0].velocity == 110 && lanes[0].track == 0 &&
                           lanes[0].cc == kCcModulation &&
                           lanes[0].points == std::vector<std::pair<uint32_t, int>>{{18, 11}} &&
                           lanes[2].track == 1 && lanes[2].cc == kCcModulation &&
                           lanes[2].points == std::vector<std::pair<uint32_t, int>>{{30, 22}} &&
                           lanes[4].track == 2 && lanes[4].cc == kCcModulation &&
                           lanes[4].points == std::vector<std::pair<uint32_t, int>>{{42, 33}},
                       "multi-track time copy lost a note or MOD lane stream");
            }

            Rig target;
            if (target.doc.addTrack(0) < 0) {
                fail("multi-track paste rig could not add its initial track");
            } else {
                target.attach();
                target.view.commitEditCursor(0);
                const int undoBeforePaste = target.doc.undoStack()->count();
                expect(target.doc.engineTrackCount() == 1,
                       "multi-track paste rig did not start with one track");
                expect(target.sendKey(Qt::Key_V, Qt::ControlModifier),
                       "multi-track paste did not reach the roll");
                expect(target.doc.engineTrackCount() == 3,
                       "multi-track paste did not create missing tracks");
                expect(notesOf(target.doc, 0) == std::vector<NoteSpec>{{12, 60, 12, 90}} &&
                           notesOf(target.doc, 1) == std::vector<NoteSpec>{{24, 64, 24, 100}} &&
                           notesOf(target.doc, 2) == std::vector<NoteSpec>{{36, 68, 36, 110}},
                       "multi-track paste lost a note stream");
                expect(lanesOf(target.doc, 0, kCcModulation) == std::vector<LaneSpec>{{18, 11}} &&
                           lanesOf(target.doc, 1, kCcModulation) ==
                               std::vector<LaneSpec>{{30, 22}} &&
                           lanesOf(target.doc, 2, kCcModulation) == std::vector<LaneSpec>{{42, 33}},
                       "multi-track paste lost a MOD lane stream");
                expect(target.doc.undoStack()->count() == undoBeforePaste + 1,
                       "multi-track paste did not push one undo command");
                target.doc.undoStack()->undo();
                expect(target.doc.engineTrackCount() == 1 && notesOf(target.doc, 0).empty() &&
                           lanesOf(target.doc, 0, kCcModulation).empty(),
                       "multi-track paste undo did not remove tracks and content");
            }
        }
    }

    // Delete and cut of a time selection apply one RangeEdit to the source.
    // The selection band remains active, and undo restores every stream.
    {
        Rig rig;
        if (rig.doc.addTrack(0) < 0) {
            fail("time-delete rig could not add a track");
        } else {
            rig.doc.addNotes(0, {{24, 60, 24, 100}, {96, 64, 24, 80}});
            rig.doc.addLanePoint(0, DOC_CC_VOICE, 24, 3);
            rig.doc.addLanePoint(0, DOC_CC_VOICE, 96, 5);
            rig.doc.applyTempoEdit({{}, {{24, 600000}, {96, 400000}}});
            rig.attach();
            songview::EditorSelectionModel::TimeSelection selection;
            selection.startTick = 0;
            selection.endTick = 48;
            rig.view.selectionModel().setTimeSelection(selection);

            const int undoBeforeDelete = rig.doc.undoStack()->count();
            expect(rig.sendKey(Qt::Key_Delete, Qt::NoModifier),
                   "time-selection delete did not reach the roll");
            expect(notesOf(rig.doc, 0) == std::vector<NoteSpec>{{96, 64, 24, 80}},
                   "time-selection delete did not remove only the in-range note");
            expect(lanesOf(rig.doc, 0, DOC_CC_VOICE) == std::vector<LaneSpec>{{96, 5}},
                   "time-selection delete did not remove only the in-range lane point");
            expect(tempoOf(rig.doc) == std::vector<TempoSpec>{{96, 400000}},
                   "time-selection delete did not remove only the in-range tempo point");
            expect(rig.doc.undoStack()->count() == undoBeforeDelete + 1,
                   "time-selection delete did not create one undo command");
            expect(rig.view.selectionModel().timeSelection().active(),
                   "time-selection delete cleared the selection band");
            expect(announced(rig, QStringLiteral("Deleted range")),
                   "time-selection delete did not announce itself");

            rig.doc.undoStack()->undo();
            expect(notesOf(rig.doc, 0) ==
                       std::vector<NoteSpec>{{24, 60, 24, 100}, {96, 64, 24, 80}},
                   "time-selection delete undo did not restore notes");
            expect(lanesOf(rig.doc, 0, DOC_CC_VOICE) ==
                       std::vector<LaneSpec>{{0, 0}, {24, 3}, {96, 5}},
                   "time-selection delete undo did not restore lane points");
            expect(tempoOf(rig.doc) == std::vector<TempoSpec>{{24, 600000}, {96, 400000}},
                   "time-selection delete undo did not restore tempo");

            const int undoIndexBeforeCut = rig.doc.undoStack()->index();
            expect(rig.sendKey(Qt::Key_X, Qt::ControlModifier),
                   "time-selection cut did not reach the roll");
            const auto cut = checkClipboardClip();
            expect(cut && cut->clip.span == 48, "time-selection cut did not copy its range");
            expect(notesOf(rig.doc, 0) == std::vector<NoteSpec>{{96, 64, 24, 80}},
                   "time-selection cut did not remove the source note");
            expect(lanesOf(rig.doc, 0, DOC_CC_VOICE) == std::vector<LaneSpec>{{96, 5}},
                   "time-selection cut did not remove the source lane point");
            expect(tempoOf(rig.doc) == std::vector<TempoSpec>{{96, 400000}},
                   "time-selection cut did not remove the source tempo point");
            expect(rig.doc.undoStack()->index() == undoIndexBeforeCut + 1,
                   "time-selection cut did not create one source undo command");
        }
    }

    return failures == 0 ? 0 : 1;
}