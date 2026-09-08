// Track-header context menu over the shared Quick canvas session. These
// checks drive the real header right-press, click typed rows addressed by
// songview::TrackHeaderModel::HeaderMenuAction ids, and follow the two async
// transitions (voice picker, in-band rename), so close-before-activate
// ordering, guarded stale targets, and the dismissal contracts stay
// observable end to end.

#include "checks/trackheaders/tst_trackheaders.h"

#include "checks/quickpopupguard.h"
#include "checks/voicepickerdriver.h"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSignalSpy>
#include <QtTest>

#include <iterator>
#include <optional>

#include "checks/support/quickframebuffer.h"
#include "core/songdocument.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/trackheadermodel.h"

using HeaderMenuAction = songview::TrackHeaderModel::HeaderMenuAction;

namespace {

// One opened header menu: the shared session, its rendered panel's typed row
// model, and a diagnostic when the asynchronous open failed.
struct HeaderMenu {
    songview::QuickPopupSession *session = nullptr;
    songview::QuickMenuModel *model = nullptr;
    QString diagnostic = QStringLiteral("the header right-press did not open the shared menu");
};

// Right-clicks the row's title through the real canvas window and waits for
// the shared session to publish the typed menu panel. Callers address and
// click rendered rows rather than activating the model.
HeaderMenu openHeaderMenu(TrackHeadersFixture &fx, int row)
{
    HeaderMenu menu;
    songview::QuickPopupSession *const session = quick_popup::popupSession(fx.view());
    if (!session || !session->window()) {
        menu.diagnostic = QStringLiteral("the timeline Quick canvas has no popup session");
        return menu;
    }
    // The isolated band shows two rows; scrolling the target row to the top
    // keeps the title point inside the live input for every track index.
    fx.headers().setScrollY(qreal(row * fx.rowHeight()));
    checks::support::pumpQuick();
    const std::optional<QPointF> title = fx.titlePoint(row);
    if (!title) {
        menu.diagnostic = QStringLiteral("the header row title point is not visible");
        return menu;
    }
    const QPointer<songview::QuickPopupSession> live{session};
    QTest::mouseClick(session->window(), Qt::RightButton, Qt::NoModifier,
                      fx.input().mapToScene(*title).toPoint());
    if (!QTest::qWaitFor([&live] {
            return live && live->isOpen() && quick_popup::menuPanel(*live) &&
                   quick_popup::menuModel(*quick_popup::menuPanel(*live)) != nullptr;
        }))
        return menu;
    menu.session = live;
    menu.model = quick_popup::menuModel(*quick_popup::menuPanel(*live));
    menu.diagnostic.clear();
    return menu;
}

// Typed row addressing through the model; commands run through the rendered
// surface only.
int headerMenuRow(songview::QuickMenuModel &model, HeaderMenuAction action)
{
    return model.rowForId(static_cast<int>(action));
}

// An input-local header point the current menu frame does not cover, so the
// dismissal press provably lands on the band rather than the popup surface.
std::optional<QPointF> headerPointOutsideMenuFrame(TrackHeadersFixture &fx,
                                                   const QRectF &frameScene)
{
    for (int row = 0; row < fx.headers().rowCount(); ++row) {
        for (const qreal xFraction : {0.08, 0.5, 0.92}) {
            const QPointF local(fx.input().width() * xFraction,
                                qreal(row) * fx.rowHeight() + fx.rowHeight() / 2.0);
            if (!fx.input().bounds().contains(local))
                continue;
            if (!frameScene.contains(fx.input().mapToScene(local)))
                return local;
        }
    }
    return std::nullopt;
}

} // namespace

void TrackHeadersTest::headerMenuOpensWithTypedRowsAndDismissesWithoutWrite()
{
    TrackHeadersFixture &fx = fixture();
    SongDocument &doc = fx.tab().document();
    const std::optional<int> row = fx.rowForTrack(fx.sourceTrack());
    QVERIFY(row);
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const quick_popup::PromptGuard guard(fx.view());
    // Establish the pre-menu focus the session restores on dismissal.
    QVERIFY2(
        fx.view().focusTimelineBand(songview::TimelineBand::TrackHeaders, Qt::OtherFocusReason),
        "the Quick track-header band could not take focus");
    QTRY_VERIFY(fx.input().hasActiveFocus());

    const HeaderMenu opened = openHeaderMenu(fx, *row);
    QVERIFY2(opened.session, qUtf8Printable(opened.diagnostic));
    // The right-press selects its header before the menu opens and the
    // selection survives an ordinary dismissal.
    QCOMPARE(fx.view().selectionModel().primaryTrack(), fx.sourceTrack());

    // Availability and typed addressing stay pinned; wording is incidental.
    static constexpr HeaderMenuAction kMenuActions[] = {
        HeaderMenuAction::ChangeVoice, HeaderMenuAction::ShowVoiceInVoicegroup,
        HeaderMenuAction::RenameTrack, HeaderMenuAction::DuplicateTrack,
        HeaderMenuAction::DeleteTrack,
    };
    static_assert(std::size(kMenuActions) == 5);
    QCOMPARE(opened.model->rowCount(), 5);
    for (int i = 0; i < opened.model->rowCount(); ++i) {
        const songview::QuickMenuItem *const item = opened.model->itemAt(i);
        QVERIFY(item);
        QCOMPARE(item->id, static_cast<int>(kMenuActions[i]));
        QCOMPARE(opened.model->rowForId(item->id), i);
        const bool expectedEnabled =
            kMenuActions[i] != HeaderMenuAction::DuplicateTrack || doc.canAddTrack();
        QCOMPARE(item->enabled, expectedEnabled);
    }

    QTest::keyClick(opened.session->window(), Qt::Key_Escape);
    QCoreApplication::processEvents();
    QVERIFY2(!opened.session->isOpen(), "Escape did not dismiss the header menu");
    QTRY_VERIFY2(fx.input().hasActiveFocus(),
                 "Escape did not restore the pre-menu header band focus");
    QCOMPARE(doc.smf().write(), before);
    QCOMPARE(doc.undoStack()->index(), undo);
    QCOMPARE(fx.view().selectionModel().primaryTrack(), fx.sourceTrack());
}

void TrackHeadersTest::headerMenuChangeVoiceOpensPickerAfterMenuCloses()
{
    TrackHeadersFixture &fx = fixture();
    SongDocument &doc = fx.tab().document();
    const std::optional<int> row = fx.rowForTrack(fx.voiceTrack());
    QVERIFY(row);
    const uint64_t revision = doc.revision();
    const int undo = doc.undoStack()->index();
    const quick_popup::PromptGuard guard(fx.view());
    // Establish the pre-menu focus the session restores on dismissal.
    QVERIFY2(
        fx.view().focusTimelineBand(songview::TimelineBand::TrackHeaders, Qt::OtherFocusReason),
        "the Quick track-header band could not take focus");
    QTRY_VERIFY(fx.input().hasActiveFocus());

    const HeaderMenu opened = openHeaderMenu(fx, *row);
    QVERIFY2(opened.session, qUtf8Printable(opened.diagnostic));
    QCOMPARE(fx.view().selectionModel().primaryTrack(), fx.voiceTrack());
    QVERIFY2(quick_popup::clickMenuRow(*opened.session,
                                       headerMenuRow(*opened.model, HeaderMenuAction::ChangeVoice)),
             "the Change voice row did not receive a real click");
    QCoreApplication::processEvents();
    // The pick closes the menu before the queued mutation reopens the shared
    // session as the async voice picker; the panel is the menu observable.
    QVERIFY2(!quick_popup::menuPanel(*opened.session),
             "the Change voice pick left the header menu panel open");
    QCOMPARE(doc.revision(), revision);

    // The pick only transitions to the already-landed async picker; opening
    // it mutates nothing until an acceptance.
    QTRY_VERIFY(static_cast<bool>(checks::voicepicker::active(fx.view())));
    const checks::voicepicker::Picker picker = checks::voicepicker::active(fx.view());
    QTRY_VERIFY(picker.search->hasActiveFocus());
    // Keyboard continuity: filter keys land in the picker that took focus.
    checks::voicepicker::filter(picker, QStringLiteral("127"));
    QTRY_VERIFY(checks::voicepicker::row(picker, 127) &&
                checks::voicepicker::row(picker, 127)->isVisible());
    QCOMPARE(doc.revision(), revision);
    QVERIFY(checks::voicepicker::dismissOutside(picker));
    QTRY_VERIFY(!quick_popup::popupSession(fx.view())->isOpen());
    checks::support::pumpQuick();
    QCOMPARE(doc.revision(), revision);
    QCOMPARE(doc.undoStack()->index(), undo);
    QCOMPARE(fx.view().selectionModel().primaryTrack(), fx.voiceTrack());
}

void TrackHeadersTest::headerMenuRenameBeginsAfterCloseAndFocusesEditor()
{
    TrackHeadersFixture &fx = fixture();
    SongDocument &doc = fx.tab().document();
    const std::optional<int> row = fx.rowForTrack(fx.sourceTrack());
    QVERIFY(row);
    const QString original = doc.trackName(fx.sourceTrack());
    const uint64_t revision = doc.revision();
    const int undo = doc.undoStack()->index();
    const quick_popup::PromptGuard guard(fx.view());
    // Establish the pre-menu focus the session restores on dismissal.
    QVERIFY2(
        fx.view().focusTimelineBand(songview::TimelineBand::TrackHeaders, Qt::OtherFocusReason),
        "the Quick track-header band could not take focus");
    QTRY_VERIFY(fx.input().hasActiveFocus());

    const HeaderMenu opened = openHeaderMenu(fx, *row);
    QVERIFY2(opened.session, qUtf8Printable(opened.diagnostic));
    QVERIFY2(quick_popup::clickMenuRow(*opened.session,
                                       headerMenuRow(*opened.model, HeaderMenuAction::RenameTrack)),
             "the Rename track row did not receive a real click");
    // Rename begins synchronously once the menu closed, adopting the existing
    // in-band editor; no queued stash may reopen it after a cancellation.
    QCoreApplication::processEvents();
    QVERIFY2(!opened.session->isOpen(), "the Rename track pick left the header menu open");
    QCOMPARE(fx.headers().renamingTrack(), fx.sourceTrack());
    QVERIFY(fx.rename().isVisible());
    QTRY_VERIFY(fx.rename().hasActiveFocus());
    QCOMPARE(doc.revision(), revision);

    QTest::keyClick(&fx.window(), Qt::Key_Escape);
    checks::support::pumpQuick();
    QCOMPARE(fx.headers().renamingTrack(), -1);
    QCOMPARE(doc.trackName(fx.sourceTrack()), original);
    QVERIFY(!fx.rename().isVisible());
    QCOMPARE(doc.revision(), revision);
    QCOMPARE(doc.undoStack()->index(), undo);
    checks::support::pumpQuick();
    QCOMPARE(fx.headers().renamingTrack(), -1);
    QVERIFY(!fx.rename().isVisible());
}

void TrackHeadersTest::headerMenuRowsDispatchRevealDuplicateDelete()
{
    TrackHeadersFixture &fx = fixture();
    SongDocument &doc = fx.tab().document();
    const quick_popup::PromptGuard guard(fx.view());
    QVERIFY(doc.canAddTrack());

    // Show voice in voicegroup reveals the header's program without a write.
    const std::optional<int> voiceRow = fx.rowForTrack(fx.voiceTrack());
    QVERIFY(voiceRow);
    const HeaderMenu voiceMenu = openHeaderMenu(fx, *voiceRow);
    QVERIFY2(voiceMenu.session, qUtf8Printable(voiceMenu.diagnostic));
    const uint64_t beforeReveal = doc.revision();
    const int undoBeforeReveal = doc.undoStack()->index();
    QSignalSpy reveal(&fx.view(), &SongView::revealVoiceRequested);
    QVERIFY2(quick_popup::clickMenuRow(
                 *voiceMenu.session,
                 headerMenuRow(*voiceMenu.model, HeaderMenuAction::ShowVoiceInVoicegroup)),
             "the Show voice row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(!voiceMenu.session->isOpen(), "the Show voice pick left the header menu open");
    QCOMPARE(reveal.count(), 1);
    QCOMPARE(reveal.at(0).at(0).toInt(), fx.view().currentProgram(fx.voiceTrack()));
    QCOMPARE(doc.revision(), beforeReveal);
    QCOMPARE(doc.undoStack()->index(), undoBeforeReveal);
    QTRY_VERIFY2(fx.input().hasActiveFocus(),
                 "the reveal dispatch did not retain header band focus");

    // Duplicate runs the real queued command: one command, one engine slot,
    // and undo restores the song bytes.
    const std::optional<int> sourceRow = fx.rowForTrack(fx.sourceTrack());
    QVERIFY(sourceRow);
    const HeaderMenu duplicateMenu = openHeaderMenu(fx, *sourceRow);
    QVERIFY2(duplicateMenu.session, qUtf8Printable(duplicateMenu.diagnostic));
    const QByteArray beforeDuplicate = doc.smf().write();
    const int undoBeforeDuplicate = doc.undoStack()->index();
    const int tracksBefore = doc.engineTrackCount();
    const std::vector<DocNote> sourceNotes = doc.notesForTrack(fx.sourceTrack());
    QVERIFY2(!sourceNotes.empty(), "the duplicate fixture track carried no content to copy");
    QVERIFY2(quick_popup::clickMenuRow(
                 *duplicateMenu.session,
                 headerMenuRow(*duplicateMenu.model, HeaderMenuAction::DuplicateTrack)),
             "the Duplicate track row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(!duplicateMenu.session->isOpen(), "the Duplicate pick left the header menu open");
    QTRY_VERIFY2(fx.input().hasActiveFocus(),
                 "the duplicate dispatch did not retain header band focus");
    QTRY_COMPARE(doc.undoStack()->index(), undoBeforeDuplicate + 1);
    QCOMPARE(doc.engineTrackCount(), tracksBefore + 1);
    // The copy carries the targeted track's content, not a fresh empty slot.
    const std::vector<DocNote> copiedNotes = doc.notesForTrack(tracksBefore);
    QCOMPARE(copiedNotes.size(), sourceNotes.size());
    for (size_t i = 0; i < copiedNotes.size(); ++i) {
        QCOMPARE(copiedNotes[i].tick, sourceNotes[i].tick);
        QCOMPARE(copiedNotes[i].key, sourceNotes[i].key);
        QCOMPARE(copiedNotes[i].duration, sourceNotes[i].duration);
        QCOMPARE(copiedNotes[i].velocity, sourceNotes[i].velocity);
    }
    QVERIFY(doc.smf().write() != beforeDuplicate);
    doc.undoStack()->undo();
    QTRY_COMPARE(doc.smf().write(), beforeDuplicate);
    QCOMPARE(doc.engineTrackCount(), tracksBefore);
    QTRY_VERIFY(fx.rowForTrack(fx.sourceTrack()).has_value());

    // Delete drops the selected track's records; undo restores bytes and row.
    const std::optional<int> selectionRow = fx.rowForTrack(fx.selectionTrack());
    QVERIFY(selectionRow);
    const HeaderMenu deleteMenu = openHeaderMenu(fx, *selectionRow);
    QVERIFY2(deleteMenu.session, qUtf8Printable(deleteMenu.diagnostic));
    const QByteArray beforeDelete = doc.smf().write();
    const int undoBeforeDelete = doc.undoStack()->index();
    QVERIFY2(
        quick_popup::clickMenuRow(*deleteMenu.session,
                                  headerMenuRow(*deleteMenu.model, HeaderMenuAction::DeleteTrack)),
        "the Delete track row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(!deleteMenu.session->isOpen(), "the Delete pick left the header menu open");
    QTRY_VERIFY2(fx.input().hasActiveFocus(),
                 "the delete dispatch did not retain header band focus");
    QTRY_COMPARE(doc.undoStack()->index(), undoBeforeDelete + 1);
    QCOMPARE(doc.engineTrackCount(), tracksBefore - 1);
    QTRY_VERIFY(!fx.rowForTrack(fx.selectionTrack()).has_value());
    doc.undoStack()->undo();
    QTRY_COMPARE(doc.smf().write(), beforeDelete);
    QCOMPARE(doc.engineTrackCount(), tracksBefore);
    QTRY_VERIFY(fx.rowForTrack(fx.selectionTrack()).has_value());
}

void TrackHeadersTest::headerMenuStaleStructuralChangeCancelsWithoutWrite()
{
    TrackHeadersFixture &fx = fixture();
    SongDocument &doc = fx.tab().document();
    const std::optional<int> voiceRow = fx.rowForTrack(fx.voiceTrack());
    QVERIFY(voiceRow);
    const quick_popup::PromptGuard guard(fx.view());
    // Establish the pre-menu focus the session restores on dismissal, with
    // live window activation (focusTimelineBand plus focusWindow/focusObject
    // convergence), not just item-local focus.
    QVERIFY2(
        fx.view().focusTimelineBand(songview::TimelineBand::TrackHeaders, Qt::OtherFocusReason),
        "the Quick track-header band could not take focus");
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
    QTRY_VERIFY2(QGuiApplication::focusWindow() == &fx.window() &&
                     QGuiApplication::focusObject() == &fx.input() && fx.input().hasActiveFocus(),
                 "the Quick track-header band could not take focus");

    // A structural remap after the open cancels the menu synchronously
    // through the model's transient-state teardown: no focus theft into the
    // menu content, no rename, no picker, and exactly the move's write.
    const HeaderMenu opened = openHeaderMenu(fx, *voiceRow);
    QVERIFY2(opened.session, qUtf8Printable(opened.diagnostic));
    const int undo = doc.undoStack()->index();
    QVERIFY(doc.moveTrack(0, 1));
    QTRY_VERIFY2(!opened.session->isOpen(),
                 "a structural remap did not cancel the open header menu");
    checks::support::pumpQuick();
    const QQuickItem *const focus = fx.window().activeFocusItem();
    QVERIFY(focus);
    const QString focusName = focus->objectName();
    QVERIFY2(focusName != QLatin1String("quickMenuPanelRoot") &&
                 focusName != QLatin1String("quickMenuFrame"),
             "the remap cancellation left focus on the dismissed menu content");
    QCOMPARE(fx.headers().renamingTrack(), -1);
    QVERIFY(!static_cast<bool>(checks::voicepicker::active(fx.view())));
    QCOMPARE(doc.undoStack()->index(), undo + 1);

    // A queued pick that has not executed when the engine remaps must never
    // reinterpret its raw track index. The hook is connected after the host's
    // own activated handler (made at open time), so the real row click queues
    // the mutation first and this synchronous move lands before the event
    // loop delivers it. The move-only bytes are captured inside the emission,
    // before any queued command could fire, so the final byte equality cannot
    // absorb a misfired mutation.
    const std::optional<int> staleRow = fx.rowForTrack(fx.voiceTrack());
    QVERIFY(staleRow);
    // Remap real fixture-derived indices: the voice track is the queued
    // mutation's target and the destination is a genuinely different track.
    const int victim = fx.voiceTrack();
    int destination = fx.sourceTrack();
    if (destination == victim)
        destination = victim == 0 ? 1 : 0;
    QVERIFY2(destination != victim && destination >= 0 && destination < doc.engineTrackCount(),
             "the fixture needs a second track for the remap");
    const HeaderMenu stale = openHeaderMenu(fx, *staleRow);
    QVERIFY2(stale.session, qUtf8Printable(stale.diagnostic));
    QByteArray afterRemap;
    const int staleUndo = doc.undoStack()->index();
    QObject::connect(
        stale.model, &songview::QuickMenuModel::activated, stale.model,
        [&](int) {
            QVERIFY(doc.moveTrack(victim, destination));
            afterRemap = doc.smf().write();
        },
        static_cast<Qt::ConnectionType>(Qt::DirectConnection | Qt::SingleShotConnection));
    QVERIFY2(quick_popup::clickMenuRow(*stale.session,
                                       headerMenuRow(*stale.model, HeaderMenuAction::ChangeVoice)),
             "the stale Change voice row did not receive a real click");
    QVERIFY(!afterRemap.isEmpty());
    checks::support::pumpQuick();
    QVERIFY(!static_cast<bool>(checks::voicepicker::active(fx.view())));
    QCOMPARE(doc.undoStack()->index(), staleUndo + 1);
    QCOMPARE(doc.smf().write(), afterRemap);
    QCOMPARE(fx.headers().renamingTrack(), -1);

    // Cancellation leaves the host usable: a fresh open renders the menu.
    const std::optional<int> freshRow = fx.rowForTrack(fx.sourceTrack());
    QVERIFY(freshRow);
    const HeaderMenu fresh = openHeaderMenu(fx, *freshRow);
    QVERIFY2(fresh.session, qUtf8Printable(fresh.diagnostic));
    QCOMPARE(fresh.model->rowCount(), 5);
}

void TrackHeadersTest::headerMenuQueuedDestructiveMutationsDropAfterRemap()
{
    TrackHeadersFixture &fx = fixture();
    SongDocument &doc = fx.tab().document();
    const std::optional<int> voiceRow = fx.rowForTrack(fx.voiceTrack());
    QVERIFY(voiceRow);
    const quick_popup::PromptGuard guard(fx.view());
    const int tracks = doc.engineTrackCount();
    const QString voiceName = doc.trackName(fx.voiceTrack());
    // Remap real fixture-derived indices: the voice track is the queued
    // mutation's target and the destination is a genuinely different track.
    const int victim = fx.voiceTrack();
    int destination = fx.sourceTrack();
    if (destination == victim)
        destination = victim == 0 ? 1 : 0;
    QVERIFY2(destination != victim && destination >= 0 && destination < doc.engineTrackCount(),
             "the fixture needs a second track for the remap");

    // A Delete queued by a real row click, remapped before the queued command
    // executes, is dropped by the execution-time identity check: the raw
    // index never deletes the track that slid into the slot. Each hook is
    // one-shot because the persistent model would otherwise deliver an older
    // observer's remap again on a later menu's activation.
    const HeaderMenu deleteMenu = openHeaderMenu(fx, *voiceRow);
    QVERIFY2(deleteMenu.session, qUtf8Printable(deleteMenu.diagnostic));
    QByteArray afterRemap;
    const int deleteUndo = doc.undoStack()->index();
    QObject::connect(
        deleteMenu.model, &songview::QuickMenuModel::activated, deleteMenu.model,
        [&](int) {
            QVERIFY(doc.moveTrack(victim, destination));
            afterRemap = doc.smf().write();
        },
        static_cast<Qt::ConnectionType>(Qt::DirectConnection | Qt::SingleShotConnection));
    QVERIFY2(
        quick_popup::clickMenuRow(*deleteMenu.session,
                                  headerMenuRow(*deleteMenu.model, HeaderMenuAction::DeleteTrack)),
        "the stale Delete track row did not receive a real click");
    QVERIFY(!afterRemap.isEmpty());
    checks::support::pumpQuick();
    QVERIFY(!deleteMenu.session->isOpen());
    QCOMPARE(doc.engineTrackCount(), tracks);
    QCOMPARE(doc.undoStack()->index(), deleteUndo + 1);
    QCOMPARE(doc.smf().write(), afterRemap);
    QCOMPARE(doc.trackName(destination), voiceName);

    // A Duplicate queued across the same window drops instead of copying the
    // track that slid into the raw slot.
    const std::optional<int> duplicateRow = fx.rowForTrack(destination);
    QVERIFY(duplicateRow);
    const HeaderMenu duplicateMenu = openHeaderMenu(fx, *duplicateRow);
    QVERIFY2(duplicateMenu.session, qUtf8Printable(duplicateMenu.diagnostic));
    QByteArray duplicateAfterRemap;
    const int duplicateUndo = doc.undoStack()->index();
    QObject::connect(
        duplicateMenu.model, &songview::QuickMenuModel::activated, duplicateMenu.model,
        [&](int) {
            QVERIFY(doc.moveTrack(destination, victim));
            duplicateAfterRemap = doc.smf().write();
        },
        static_cast<Qt::ConnectionType>(Qt::DirectConnection | Qt::SingleShotConnection));
    QVERIFY2(quick_popup::clickMenuRow(
                 *duplicateMenu.session,
                 headerMenuRow(*duplicateMenu.model, HeaderMenuAction::DuplicateTrack)),
             "the stale Duplicate track row did not receive a real click");
    QVERIFY(!duplicateAfterRemap.isEmpty());
    checks::support::pumpQuick();
    QVERIFY(!duplicateMenu.session->isOpen());
    QCOMPARE(doc.engineTrackCount(), tracks);
    QCOMPARE(doc.undoStack()->index(), duplicateUndo + 1);
    QCOMPARE(doc.smf().write(), duplicateAfterRemap);
}

void TrackHeadersTest::headerMenuOutsidePressDismissesWithoutClickThrough()
{
    TrackHeadersFixture &fx = fixture();
    SongDocument &doc = fx.tab().document();
    const std::optional<int> row = fx.rowForTrack(fx.sourceTrack());
    QVERIFY(row);
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const quick_popup::PromptGuard guard(fx.view());
    // Establish the pre-menu focus the session restores on dismissal.
    QVERIFY2(
        fx.view().focusTimelineBand(songview::TimelineBand::TrackHeaders, Qt::OtherFocusReason),
        "the Quick track-header band could not take focus");
    QTRY_VERIFY(fx.input().hasActiveFocus());

    const HeaderMenu opened = openHeaderMenu(fx, *row);
    QVERIFY2(opened.session, qUtf8Printable(opened.diagnostic));
    QQuickItem *const frame = quick_popup::menuFrame(*opened.session);
    QVERIFY2(frame, "the header menu rendered no outside boundary frame");
    const QRectF frameScene = frame->mapRectToScene(frame->boundingRect());
    const std::optional<QPointF> outside = headerPointOutsideMenuFrame(fx, frameScene);
    QVERIFY2(outside, "no header point outside the menu frame stayed inside the live input");
    const QPoint outsideScene = fx.input().mapToScene(*outside).toPoint();

    // An outside left press dismisses through the frame: no selection change,
    // no document effect, and no new menu.
    QTest::mouseClick(opened.session->window(), Qt::LeftButton, Qt::NoModifier, outsideScene);
    QCoreApplication::processEvents();
    QVERIFY2(!opened.session->isOpen(), "an outside press did not dismiss the header menu");
    checks::support::pumpQuick();
    QVERIFY2(!quick_popup::popupSession(fx.view())->isOpen(),
             "the outside dismissal opened a new menu");
    QCOMPARE(fx.view().selectionModel().primaryTrack(), fx.sourceTrack());
    QCOMPARE(doc.smf().write(), before);
    QCOMPARE(doc.undoStack()->index(), undo);
    QTRY_VERIFY2(fx.input().hasActiveFocus(),
                 "the outside dismissal did not restore the header band focus");

    // An outside right press dismisses too; its paired release is swallowed
    // by the session instead of clicking through to the band.
    const HeaderMenu reopened = openHeaderMenu(fx, *row);
    QVERIFY2(reopened.session, qUtf8Printable(reopened.diagnostic));
    QTest::mousePress(reopened.session->window(), Qt::RightButton, Qt::NoModifier, outsideScene);
    QCoreApplication::processEvents();
    QVERIFY2(!reopened.session->isOpen(), "an outside right press did not dismiss the menu");
    QTest::mouseRelease(reopened.session->window(), Qt::RightButton, Qt::NoModifier, outsideScene);
    QCoreApplication::processEvents();
    checks::support::pumpQuick();
    QVERIFY2(!quick_popup::popupSession(fx.view())->isOpen(),
             "the swallowed release opened a new menu");
    QCOMPARE(fx.view().selectionModel().primaryTrack(), fx.sourceTrack());
    QCOMPARE(doc.smf().write(), before);
    QCOMPARE(doc.undoStack()->index(), undo);
}
