#include "checks/rollcheck/tst_pianoroll.h"

#include <QAbstractItemModel>
#include <QByteArray>
#include <QCoreApplication>
#include <QEvent>
#include <QObject>
#include <QPointF>
#include <QtTest>
#include <algorithm>
#include <cstdint>
#include <optional>

#include "checks/rollcheck/headerchecksupport.h"
#include "checks/support/eventsynth.h"
#include "checks/trackheaders/trackheaderoracles.h"
#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/songview/editactions.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/trackheadermodel.h"
using namespace checks::rollcheck;

using checks::rollcheck::headercheck::model;
using checks::rollcheck::headercheck::renameInput;
using trackheaders_test::rowForTrack;

void PianoRollTest::headerPanFollow()
{
    PianoRollFixture &check = *m_fixture;
    SongDocument &doc = check.document();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    SongView &view = check.view();
    songview::TimelineInputItem &roll = check.rollInput();
    const qreal width = std::max<qreal>(50, roll.width());
    auto *automationQuick =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    auto *lanes = automationQuick && automationQuick->rootObject()
                      ? automationQuick->rootObject()->findChild<songview::TimelineInputItem *>(
                            QStringLiteral("timelineAutomationInput"))
                      : nullptr;
    if (!lanes) {
        QFAIL("automation input item not found");
        return;
    }
    const auto probe = [&](auto &surface) {
        const int home = view.camera().contentX(0.0);
        const Tick farTick =
            CoreTimeDefaults::tickFromDouble(view.camera().tickAtContentX(width * 2));
        const QPointF middle(surface.width() / 2.0, surface.height() / 2.0);
        checks::events::sendMouse(surface, QEvent::MouseButtonPress, middle, Qt::MiddleButton,
                                  Qt::MiddleButton, Qt::NoModifier);
        view.setPlayheadSample(check.timeline().sampleForTick(farTick), true);
        if (view.camera().contentX(0.0) != home)
            QFAIL("playhead follow-scroll moved the view during a pan gesture");
        checks::events::sendMouse(surface, QEvent::MouseButtonRelease, middle, Qt::MiddleButton,
                                  Qt::NoButton, Qt::NoModifier);
        view.setPlayheadSample(check.timeline().sampleForTick(farTick), true);
        if (view.camera().contentX(0.0) == home)
            QFAIL("playhead follow-scroll did not resume after the pan ended");
        view.setPlayheadSample(0, false);
        view.scrollByPx(view.camera().contentX(0.0) - home);
    };
    probe(roll);
    probe(*lanes);
    QCOMPARE(doc.undoStack()->index(), undo);
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::headerRename()
{
    PianoRollFixture &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto *headers = model(view);
    if (!headers) {
        QFAIL("Quick track-header model was not found");
        return;
    }
    const int track = check.track();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    QVERIFY2(view.focusTimelineBand(songview::TimelineBand::TrackHeaders, Qt::OtherFocusReason),
             "the Quick track-header input was unavailable");
    QTRY_VERIFY2(view.focusedTimelineBand() == songview::TimelineBand::TrackHeaders,
                 "the Quick track-header input did not take active focus");
    const auto renameIsOpen = [&] {
        QCoreApplication::processEvents();
        QObject *const field = renameInput(view);
        return headers->renamingTrack() == track && field && field->property("visible").toBool() &&
               field->property("activeFocus").toBool();
    };
    const auto typeDraft = [&](QObject &field, const QString &draft) {
        headers->setRenameDraft(draft);
        QCoreApplication::processEvents();
        if (field.property("text").toString() != draft)
            QFAIL("Quick rename input did not receive the model draft");
    };
    view.renameTrack(track);
    QTRY_VERIFY2(renameIsOpen(), "Quick rename input did not open");
    QObject *field = renameInput(view);
    typeDraft(*field, QStringLiteral("Rolled"));
    sendKeyStroke(*field, Qt::Key_Return, Qt::NoModifier, false);
    QCoreApplication::processEvents();
    if (doc.trackName(track) != QStringLiteral("Rolled")) {
        QFAIL("Quick Return did not commit the inline rename");
        return;
    }
    view.renameTrack(track);
    QTRY_VERIFY2(renameIsOpen(), "Quick rename input did not reopen");
    field = renameInput(view);
    typeDraft(*field, QStringLiteral("Discarded"));
    sendKeyStroke(*field, Qt::Key_Escape, Qt::NoModifier, false);
    QCoreApplication::processEvents();
    if (doc.trackName(track) != QStringLiteral("Rolled") || headers->renamingTrack() != -1) {
        QFAIL("Quick Escape did not discard the inline rename draft");
        return;
    }
    view.renameTrack(track);
    QTRY_VERIFY2(renameIsOpen(), "Quick rename input did not reopen for the loop-marker guard");
    const int commands = doc.undoStack()->count();
    field = renameInput(view);
    typeDraft(*field, QStringLiteral("["));
    sendKeyStroke(*field, Qt::Key_Return, Qt::NoModifier, false);
    QCoreApplication::processEvents();
    if (doc.trackName(track) != QStringLiteral("Rolled") || doc.undoStack()->count() != commands)
        QFAIL("loop-marker name was not refused");
    while (doc.undoStack()->index() > undo)
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::headerRevealNote()
{
    PianoRollFixture &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();

    // Polyphony-dock jump target: revealNote selects the losing track and
    // the lost note itself (the last note on (track, key) starting at or
    // before the event tick), without touching the undo stack.
    {
        const auto &notes = view.model().notes;
        if (notes.empty()) {
            QFAIL("no notes in the view model for revealNote");
        } else {
            const ViewNote target = notes[notes.size() / 2];
            if (!view.revealNote(target.track, target.key, target.startTick))
                QFAIL("revealNote did not find the note");
            if (view.selectionModel().primaryTrack() != int(target.track))
                QFAIL("revealNote did not select the track");
            const auto &sel = view.selectionModel().noteSelection();
            if (sel.size() != 1 || !(sel[0] == target.noteId))
                QFAIL("revealNote did not select the note");

            // A key the track never plays: no note found, but the track
            // selection sticks (the dock still switches context).
            bool used[128] = {};
            for (const ViewNote &note : notes) {
                if (note.track == target.track)
                    used[note.key] = true;
            }
            int freeKey = -1;
            for (int k = 0; k < 128 && freeKey < 0; k++) {
                if (!used[k])
                    freeKey = k;
            }
            if (freeKey >= 0) {
                if (view.revealNote(target.track, uint8_t(freeKey), target.startTick))
                    QFAIL("revealNote found a note on an unused key");
                if (view.selectionModel().primaryTrack() != int(target.track))
                    QFAIL("revealNote miss dropped the track selection");
            }
        }
    }
    QCOMPARE(doc.undoStack()->index(), undo);
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::headerKeyboardMuteSolo()
{
    PianoRollFixture &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem &roll = check.rollInput();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    auto *headers = model(view);
    QVERIFY2(headers, "Quick track-header model was not found");

    // Keyboard mute/solo changes view masks and the matching model roles
    // without resetting the retained Quick header structure.
    {
        const int preCount = doc.undoStack()->count();
        int headerResets = 0;
        const QMetaObject::Connection resetConnection = QObject::connect(
            headers, &QAbstractItemModel::modelReset, &view, [&headerResets] { ++headerResets; });
        const auto roleChecked = [&](int track, int role) {
            const std::optional<int> row = rowForTrack(*headers, track);
            return row && headers->data(headers->index(*row, 0), role).toBool();
        };
        // S is a Window-scope command: the isolated fixture owns no window
        // shortcut, so the canonical action is the stimulus (the same
        // treatment the spec gives the isolated Copy fixture stimulus).
        const songview::EditActions *const actions = view.editActions();
        QAction *const soloAction =
            actions ? actions->action(SongView::EditCommand::SoloTracks) : nullptr;
        if (!soloAction)
            QFAIL("canonical solo action was not bound to the view");

        const int selectedTrack = view.selectionModel().primaryTrack();
        if (view.muteMask() != 0 || view.soloMask() != 0)
            QFAIL("mute/solo masks not clean before the keyboard toggles");
        sendKeyStroke(roll, Qt::Key_M, Qt::NoModifier, false);
        if (!view.trackMuted(selectedTrack))
            QFAIL("M did not mute the selected track");
        if (!roleChecked(selectedTrack, songview::TrackHeaderModel::MuteCheckedRole))
            QFAIL("keyboard mute did not publish the checked Quick header role");
        sendKeyStroke(roll, Qt::Key_M, Qt::NoModifier, false);
        if (view.muteMask() != 0)
            QFAIL("second M did not unmute the selected track");
        if (roleChecked(selectedTrack, songview::TrackHeaderModel::MuteCheckedRole))
            QFAIL("keyboard unmute did not clear the checked Quick header role");
        soloAction->trigger();
        if (!view.trackSoloed(selectedTrack) ||
            !roleChecked(selectedTrack, songview::TrackHeaderModel::SoloCheckedRole)) {
            QFAIL("S did not publish the selected track's solo role");
        }
        soloAction->trigger();
        if (view.soloMask() != 0 ||
            roleChecked(selectedTrack, songview::TrackHeaderModel::SoloCheckedRole)) {
            QFAIL("second S did not clear the selected track's solo role");
        }

        // Multi-track scope + mixed state: with another track Ctrl-scoped
        // in and already muted, M mutes the rest (on wins), and the next M
        // clears the whole scope.
        const int other = selectedTrack == 0 ? 1 : 0;
        if (!rowForTrack(*headers, other)) {
            QFAIL("Quick header record was missing for the scoped keyboard probe");
        } else {
            view.trackHeaderClicked(other, Qt::ControlModifier);
            view.setTrackMute(other, true);
            sendKeyStroke(roll, Qt::Key_M, Qt::NoModifier, false);
            if (!view.trackMuted(selectedTrack) || !view.trackMuted(other) ||
                !roleChecked(selectedTrack, songview::TrackHeaderModel::MuteCheckedRole) ||
                !roleChecked(other, songview::TrackHeaderModel::MuteCheckedRole)) {
                QFAIL("M over a mixed scope did not mute every scoped track");
            }
            sendKeyStroke(roll, Qt::Key_M, Qt::NoModifier, false);
            if (view.muteMask() != 0)
                QFAIL("second M did not unmute the whole scope");
            view.trackHeaderClicked(selectedTrack, Qt::NoModifier); // collapse scope
        }
        if (headerResets != 0)
            QFAIL("keyboard mute/solo reset the TrackHeaderModel");
        if (doc.undoStack()->count() != preCount)
            QFAIL("keyboard mute/solo touched the undo stack");
        QObject::disconnect(resetConnection);
    }

    QCOMPARE(doc.undoStack()->index(), undo);
    QCOMPARE(doc.smf().write(), before);
}
