#include "checks/rollcheck/rollcheck.h"

#include <QCoreApplication>
#include <QEvent>
#include <QLineEdit>
#include <QPointer>
#include <QPushButton>
#include <QToolButton>
#include <QWidget>
#include <vector>

#include "core/songdocument.h"
#include "ui/songview.h"

namespace checks::rollcheck {

ScenarioContinuation runHeaderReconciliationScenarios(Harness &check, const SongInfo &song)
{
    auto fail = [&](const char *what) { check.fail(what); };
    // Header rows reconcile by engine index: a slot used on both sides of
    // a rebuild keeps its row QObject, only added slots allocate, only
    // dropped slots are retired, and the Add Track button survives every
    // eligible rebuild.
    {
        SongDocument reconcileDoc;
        QString reconcileError;
        if (!reconcileDoc.load(song, &reconcileError)) {
            fail("could not load header reconciliation fixture");
        } else {
            auto current = reconcileDoc.buildTimeline(48000.0);
            SongView reconcileView;
            reconcileView.resize(800, 480);
            reconcileView.setSong(current.get(), nullptr);
            reconcileView.setDocument(&reconcileDoc);
            (void)reconcileView.grab(); // layout pass: rows need real geometry
            const auto rowAt = [&reconcileView](int track) -> QPointer<QWidget> {
                return reconcileView.findChild<QWidget *>(
                    QStringLiteral("trackHeaderRow%1").arg(track));
            };
            const auto addButton = [&reconcileView]() -> QPointer<QPushButton> {
                for (QPushButton *button : reconcileView.findChildren<QPushButton *>()) {
                    if (button->text() == SongView::tr("+ Add track"))
                        return button;
                }
                return {};
            };
            std::vector<QPointer<QWidget>> before;
            for (int track = 0; track < 16; ++track)
                before.push_back(rowAt(track));
            int firstUsed = -1;
            int lastUsed = -1;
            for (int track = 0; track < 16; ++track) {
                if (!current->tracks[track].used)
                    continue;
                if (firstUsed < 0)
                    firstUsed = track;
                lastUsed = track;
            }
            const QPointer<QPushButton> addBefore = addButton();
            if (firstUsed < 0 || firstUsed == lastUsed || !before[firstUsed] || !before[lastUsed] ||
                addBefore.isNull()) {
                fail("header reconciliation fixture lacks two rows and an Add Track button");
            } else {
                // Same content again: every same-index row keeps identity.
                reconcileView.setSong(current.get(), nullptr);
                for (int track = 0; track < 16; ++track) {
                    if (current->tracks[track].used && before[track] != rowAt(track)) {
                        fail("same-index header row lost identity across a rebuild");
                        break;
                    }
                }
                if (addButton() != addBefore)
                    fail("Add Track button did not survive an eligible rebuild");
                // Song replacement dropping the last used slot: the kept
                // slot's row survives, the dropped slot's row is
                // anonymized, hidden, and collected.
                const QPointer<QWidget> retained = before[firstUsed];
                const QPointer<QWidget> dropped = before[lastUsed];
                reconcileDoc.deleteTrack(lastUsed);
                auto replacement = reconcileDoc.buildTimeline(48000.0);
                if (replacement->tracks[lastUsed].used || !replacement->tracks[firstUsed].used) {
                    fail("replacement fixture did not drop exactly the last used slot");
                } else {
                    reconcileView.setSong(replacement.get(), nullptr);
                    if (retained != rowAt(firstUsed))
                        fail("used header row lost identity across song replacement");
                    if (!dropped->isHidden() || !dropped->objectName().isEmpty())
                        fail("dropped header row kept its live identity");
                    if (!rowAt(lastUsed).isNull())
                        fail("dropped slot still resolves a header row");
                    QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
                    if (!dropped.isNull())
                        fail("dropped header row was not collected");
                    // Undo restores the slot: its row is newly allocated.
                    reconcileDoc.undoStack()->undo();
                    current = reconcileDoc.buildTimeline(48000.0);
                    reconcileView.setSong(current.get(), nullptr);
                    (void)reconcileView.grab();
                    const QPointer<QWidget> fresh = rowAt(lastUsed);
                    if (fresh.isNull() || fresh->isHidden() ||
                        fresh->objectName() != QStringLiteral("trackHeaderRow%1").arg(lastUsed)) {
                        fail("re-added track did not get a live named header row");
                    }
                    if (retained != rowAt(firstUsed))
                        fail("retained header row lost identity across the re-add");
                    if (addButton() != addBefore)
                        fail("Add Track button did not survive the replacement cycle");
                    int previousY = -1;
                    for (int track = 0; track < 16; ++track) {
                        if (!current->tracks[track].used)
                            continue;
                        const QPointer<QWidget> row = rowAt(track);
                        if (row.isNull() || row->y() <= previousY) {
                            fail("header rows lost ascending layout order");
                            break;
                        }
                        previousY = row->y();
                    }
                    if (addBefore->y() <= previousY)
                        fail("Add Track button is not the last header widget");
                    // A replacement under an open rename editor cancels it
                    // without committing, and a retained row keeps exactly
                    // one live connection per signal.
                    reconcileView.renameTrack(firstUsed);
                    auto *editor =
                        retained->findChild<QLineEdit *>(QStringLiteral("trackRenameEditor"));
                    const bool editorOpen = editor != nullptr;
                    if (!editorOpen)
                        fail("rename editor did not open on a retained row");
                    if (editorOpen)
                        editor->setText(QStringLiteral("zzz"));
                    reconcileView.setSong(replacement.get(), nullptr);
                    QCoreApplication::processEvents();
                    if (retained->findChild<QLineEdit *>(QStringLiteral("trackRenameEditor")))
                        fail("rename editor leaked across song replacement");
                    if (editorOpen && reconcileDoc.trackName(firstUsed) == QStringLiteral("zzz")) {
                        fail("cancelled rename committed across song replacement");
                    }
                    auto *muteButton =
                        retained->findChild<QToolButton *>(QStringLiteral("trackMuteButton"));
                    int toggles = 0;
                    const QMetaObject::Connection count =
                        QObject::connect(muteButton, &QToolButton::toggled, &reconcileView,
                                         [&toggles](bool) { toggles++; });
                    reconcileView.setSong(current.get(), nullptr);
                    if (toggles != 0)
                        fail("rebuild re-emitted mute state on a retained row");
                    reconcileView.setTrackMute(firstUsed, true);
                    QObject::disconnect(count);
                    if (toggles != 1 || !muteButton->isChecked() ||
                        !reconcileView.trackMuted(firstUsed)) {
                        fail("retained row's mute connection did not fire exactly once");
                    }
                }
            }
        }
    }

    return ScenarioContinuation::Continue;
}

} // namespace checks::rollcheck
