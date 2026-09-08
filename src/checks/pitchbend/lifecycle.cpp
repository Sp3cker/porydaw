#include "checks/pitchbend/tst_pitchbendediting.h"

#include <QCoreApplication>
#include <QEvent>
#include <QQuickItem>
#include <QtTest>

#include "checks/support/eventsynth.h"
#include "ui/songview/quick/quickpopupsession.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/trackheadermodel.h"

#include <optional>

namespace {
QPoint rollWindowPoint(const PitchBendFixture &fixture, QPoint local)
{
    return fixture.windowPoint(fixture.rollInput(), local);
}

QPoint noteEdgePoint(const PitchBendFixture &fixture)
{
    const qreal dpr = fixture.rollInput().devicePixelRatio();
    return QPoint(qRound(fixture.view().camera().displayX(double(fixture.note().tick), 0.0, dpr)),
                  fixture.notePoint().y());
}

// Window point over the given track's header row: the shared-scene target
// proving an outside press still reaches other UI after popup dismissal.
std::optional<QPoint> trackHeaderWindowPoint(const PitchBendFixture &fixture, int track)
{
    songview::TimelineQuickView *quick = fixture.view().quickView();
    QQuickItem *root = quick ? quick->rootObject() : nullptr;
    auto *input = root ? root->findChild<songview::TimelineInputItem *>(
                             QStringLiteral("timelineTrackHeadersInput"))
                       : nullptr;
    auto *model =
        fixture.view().findChild<songview::TrackHeaderModel *>(QStringLiteral("trackHeaderModel"));
    if (!input || !model)
        return std::nullopt;
    for (int row = 0; row < model->rowCount(); ++row) {
        if (model->data(model->index(row, 0), songview::TrackHeaderModel::Role::TrackRole)
                .toInt() != track) {
            continue;
        }
        const QPointF local(input->width() / 2.0,
                            row * model->rowHeight() + model->rowHeight() / 2.0);
        if (!input->boundingRect().contains(local))
            return std::nullopt;
        return fixture.windowPoint(*input, local);
    }
    return std::nullopt;
}
} // namespace

void PitchBendEditingTest::keyGAnchorsPopupToSelectedNoteWithinWindowBounds()
{
    m_fixture.view().selectionModel().setNoteSelection({m_fixture.note().noteId});
    m_fixture.rollInput().forceActiveFocus(Qt::OtherFocusReason);
    checks::events::sendMouse(m_fixture.rollInput(), QEvent::MouseMove, QPoint(1, 1), Qt::NoButton,
                              Qt::NoButton, Qt::NoModifier);
    QTest::keyClick(&m_fixture.timelineWindow(), Qt::Key_G);
    QVERIFY(QTest::qWaitFor([this] { return m_fixture.popup() != nullptr; }));
    QVERIFY(m_fixture.popup()->isOpen());
    QQuickItem *content = m_fixture.formContent();
    QVERIFY(content);
    // The shared canvas window hosts the form: the anchored placement policy
    // must keep it inside the viewport and centered on the selected note.
    QVERIFY(m_fixture.view().quickView()->popupSession()->window() == &m_fixture.timelineWindow());
    const QPointF contentScene = content->mapToScene(QPointF(0, 0));
    const QRect popupRect(contentScene.toPoint(),
                          QSize(qRound(content->width()), qRound(content->height())));
    const QRect hostRect(QPoint(0, 0), m_fixture.timelineWindow().size());
    const QPoint notePoint = rollWindowPoint(m_fixture, m_fixture.notePoint());
    QVERIFY(hostRect.intersects(popupRect));
    QVERIFY(std::abs(popupRect.center().x() - notePoint.x()) <= popupRect.width() / 2 + 12);
    QVERIFY(popupRect.top() >= hostRect.top());
    QVERIFY(popupRect.bottom() <= hostRect.bottom());
    // Restored: resizing the shared canvas window retains the editor and
    // re-clamps the anchored form instead of dismissing it.
    QPointer<songview::PitchBendEditor> editor = m_fixture.popup();
    QVERIFY(editor);
    const int heightBefore = m_fixture.timelineWindow().height();
    m_fixture.tab().resize(m_fixture.tab().width(), heightBefore - 160);
    QTRY_VERIFY(m_fixture.timelineWindow().height() < heightBefore);
    QTRY_VERIFY(editor && editor->isOpen());
    QCoreApplication::processEvents();
    QQuickItem *resizedContent = m_fixture.formContent();
    QVERIFY(resizedContent);
    const QPointF resizedScene = resizedContent->mapToScene(QPointF(0, 0));
    const QRect resizedPopup(resizedScene.toPoint(), QSize(qRound(resizedContent->width()),
                                                           qRound(resizedContent->height())));
    const QRect resizedHost(QPoint(0, 0), m_fixture.timelineWindow().size());
    QVERIFY(resizedHost.intersects(resizedPopup));
    QVERIFY(resizedPopup.top() >= resizedHost.top());
    QVERIFY(resizedPopup.bottom() <= resizedHost.bottom());
    m_fixture.assertNoteSelection();
}

void PitchBendEditingTest::popupDescriptionReflectsActiveBendr()
{
    m_fixture.document().writeLanePoints(0, 0x14, m_fixture.note().tick, m_fixture.note().tick,
                                         {{m_fixture.note().tick, 12}});
    songview::PitchBendEditor *editorResult = popup();
    QVERIFY(editorResult);
    songview::PitchBendEditor &editor = *editorResult;
    QCOMPARE(editor.bendRange(), 12);
    QVERIFY(editor.description().contains(QStringLiteral("12 semitones")));
}

void PitchBendEditingTest::idleMouseMovementPreservesPopup()
{
    songview::PitchBendEditor *editorResult = popup();
    QVERIFY(editorResult);
    QPointer<songview::PitchBendEditor> editor = editorResult;
    songview::PitchBendGraph *graphResult = pitchGraph();
    QVERIFY(graphResult);
    songview::PitchBendGraph &graph = *graphResult;
    // Idle hover follows the production path: the move lands on the shared
    // canvas window over the popup content, never directly on the graph item.
    QTest::mouseEvent(QTest::MouseMove, &m_fixture.timelineWindow(), Qt::NoButton, Qt::NoModifier,
                      m_fixture.windowPoint(graph, graph.canvasRect().center()));
    QVERIFY(editor && editor->isOpen());
    QVERIFY(m_fixture.popup() == editor);
}

void PitchBendEditingTest::enterKeyDoesNotDismissPopup()
{
    songview::PitchBendEditor *editorResult = popup();
    QVERIFY(editorResult);
    songview::PitchBendEditor &editor = *editorResult;
    QTest::keyClick(&m_fixture.timelineWindow(), Qt::Key_Enter);
    QVERIFY(editor.isOpen());
    QVERIFY(m_fixture.popup() == &editor);
}

void PitchBendEditingTest::internalEditsAndRefreshesKeepPopupOpen()
{
    songview::PitchBendEditor *editorResult = popup();
    QVERIFY(editorResult);
    songview::PitchBendEditor &editor = *editorResult;
    songview::PitchBendGraph *graphResult = pitchGraph();
    QVERIFY(graphResult);
    songview::PitchBendGraph &graph = *graphResult;
    QVERIFY(m_fixture.wheel(graph, graph.canvasRect().center(), QPoint(0, 120)));
    QQuickItem *bend = m_fixture.item(QStringLiteral("bendRangeSpin"));
    QVERIFY(bend);
    QVERIFY(m_fixture.scrub(*bend, 1));
    m_fixture.view().updateSong(m_fixture.view().timeline());
    QCoreApplication::processEvents();
    QVERIFY(editor.isOpen());
    QVERIFY(m_fixture.popup() == &editor);
}

void PitchBendEditingTest::externalNoteMutationDismissesPopup()
{
    songview::PitchBendEditor *openedEditor = popup();
    QVERIFY(openedEditor);
    QPointer<songview::PitchBendEditor> editor = openedEditor;
    m_fixture.document().moveNotes({m_fixture.note()}, 1, 0);
    QTRY_VERIFY(!editor || !editor->isOpen());
    m_fixture.drainDeferredDeletes();
    QVERIFY(editor.isNull());
}

void PitchBendEditingTest::escapeKeyDismissesPopupRetainingNoteSelection()
{
    songview::PitchBendEditor *openedEditor = popup();
    QVERIFY(openedEditor);
    QPointer<songview::PitchBendEditor> editor = openedEditor;
    m_fixture.closePopupViaEscape();
    QVERIFY(editor.isNull());
    m_fixture.assertNoteSelection();
}

void PitchBendEditingTest::rollClickDismissesPopupAndPreservesSelection()
{
    songview::PitchBendEditor *openedEditor = popup();
    QVERIFY(openedEditor);
    QPointer<songview::PitchBendEditor> editor = openedEditor;
    QTest::mouseClick(&m_fixture.timelineWindow(), Qt::LeftButton, Qt::NoModifier,
                      rollWindowPoint(m_fixture, m_fixture.notePoint()));
    QTRY_VERIFY(!editor || !editor->isOpen());
    m_fixture.drainDeferredDeletes();
    QVERIFY(editor.isNull());
    m_fixture.assertNoteSelection();

    // The note press itself is consumed by the original close policy: only
    // the press is eaten, the editor commits and restores roll focus, and
    // the press-move-release gesture never reaches the roll as a note drag.
    const auto pressMoveRelease = [this](const QPoint &origin) {
        QTest::mousePress(&m_fixture.timelineWindow(), Qt::LeftButton, Qt::NoModifier, origin);
        QTest::mouseEvent(QTest::MouseMove, &m_fixture.timelineWindow(), Qt::NoButton,
                          Qt::NoModifier, origin + QPoint(24, 0));
        QTest::mouseRelease(&m_fixture.timelineWindow(), Qt::LeftButton, Qt::NoModifier,
                            origin + QPoint(24, 0));
    };
    const auto outsideForm = [this](const QPoint &point) {
        QQuickItem *content = m_fixture.formContent();
        QVERIFY(content);
        const QRect formRect(content->mapToScene(QPointF(0, 0)).toPoint(),
                             QSize(qRound(content->width()), qRound(content->height())));
        QVERIFY2(!formRect.contains(point),
                 "the probe point must sit outside the popup form panel");
    };
    songview::PitchBendEditor *reopened = popup();
    QVERIFY(reopened);
    QPointer<songview::PitchBendEditor> anchored = reopened;
    const QByteArray beforeGesture = m_fixture.smf();
    const QPoint anchorPoint = rollWindowPoint(m_fixture, m_fixture.notePoint());
    outsideForm(anchorPoint);
    pressMoveRelease(anchorPoint);
    QTRY_VERIFY(!anchored || !anchored->isOpen());
    m_fixture.drainDeferredDeletes();
    QVERIFY(anchored.isNull());
    QTRY_VERIFY(m_fixture.rollInput().hasActiveFocus());
    QCOMPARE(m_fixture.smf(), beforeGesture);
    m_fixture.assertNoteSelection();

    // The original predicate consumed presses on any note under the cursor,
    // not just the anchored one: a stray press that would start a roll drag
    // on another note must be eaten the same way.
    const std::vector<DocNote> beforeInsert = m_fixture.document().notesForTrack(0);
    const std::vector<SongDocument::NewNote> straySpecs{{240, 64, 48, 48}};
    m_fixture.document().addNotes(0, straySpecs);
    const std::vector<NoteId> inserted = m_fixture.document().insertedNoteIds(0, beforeInsert);
    QVERIFY(inserted.size() == 1);
    DocNote strayNote;
    QVERIFY(m_fixture.document().findNote(inserted.front(), &strayNote));
    m_fixture.view().ensureRangeVisible(m_fixture.note().tick, strayNote.tick + strayNote.duration,
                                        false);
    songview::PitchBendEditor *strayEditor = popup();
    QVERIFY(strayEditor);
    QPointer<songview::PitchBendEditor> strayGuard = strayEditor;
    const QByteArray beforeStray = m_fixture.smf();
    const QPoint strayPoint = rollWindowPoint(m_fixture, m_fixture.notePoint(strayNote));
    outsideForm(strayPoint);
    pressMoveRelease(strayPoint);
    QTRY_VERIFY(!strayGuard || !strayGuard->isOpen());
    m_fixture.drainDeferredDeletes();
    QVERIFY(strayGuard.isNull());
    QTRY_VERIFY(m_fixture.rollInput().hasActiveFocus());
    QCOMPARE(m_fixture.smf(), beforeStray);
    // Original close-controller rule retargets selection to the consumed
    // note under the cursor: the stray note is now selected, not the anchor.
    QVERIFY(m_fixture.view().selectionModel().noteSelection() ==
            std::vector<NoteId>{inserted.front()});
}

void PitchBendEditingTest::rollCursorTracksAfterDismissal()
{
    QVERIFY(popup());
    m_fixture.closePopupViaEscape();
    checks::events::sendMouse(m_fixture.rollInput(), QEvent::MouseMove,
                              QPoint(1, m_fixture.notePoint().y()), Qt::NoButton, Qt::NoButton,
                              Qt::NoModifier);
    QCOMPARE(m_fixture.rollInput().cursor().shape(), Qt::ArrowCursor);
}

void PitchBendEditingTest::reopeningPopupRestoresActiveGraphFocus()
{
    songview::PitchBendEditor *openedEditor = popup();
    QVERIFY(openedEditor);
    QPointer<songview::PitchBendEditor> first = openedEditor;
    songview::TimelineQuickView *quick = m_fixture.view().quickView();
    QVERIFY(quick);
    QVERIFY(quick->focusBand(songview::TimelineBand::Roll, Qt::OtherFocusReason));
    QCoreApplication::processEvents();
    QVERIFY(quick->focusedBand() == songview::TimelineBand::Roll);
    // Restored: focus escaping to the roll alone retains the editor; the
    // re-anchor command, not focus loss, is what replaces it.
    QVERIFY(first && first->isOpen());
    QTest::keyClick(&m_fixture.timelineWindow(), Qt::Key_G);
    m_fixture.drainDeferredDeletes();
    QVERIFY(first.isNull());
    songview::PitchBendEditor *replacement = m_fixture.popup();
    QVERIFY(replacement);
    QVERIFY(replacement->isOpen());
    songview::PitchBendGraph *graph = m_fixture.graph(QStringLiteral("pitchBendGraph"));
    QVERIFY(graph);
    QTRY_VERIFY(graph->hasActiveFocus());
}

void PitchBendEditingTest::dismissalRestoresRollEdgeCursor()
{
    QVERIFY(popup());
    checks::events::sendMouse(m_fixture.rollInput(), QEvent::MouseMove, noteEdgePoint(m_fixture),
                              Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    QTRY_VERIFY(!m_fixture.rollInput().cursor().pixmap().isNull());
    m_fixture.closePopupViaEscape();
    checks::events::sendMouse(m_fixture.rollInput(), QEvent::MouseMove, noteEdgePoint(m_fixture),
                              Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    QTRY_VERIFY(!m_fixture.rollInput().cursor().pixmap().isNull());
}

void PitchBendEditingTest::insideClickRetainedOutsideClickDismisses()
{
    // Stage the real header target before opening either popup: structural
    // document edits correctly invalidate a live note-scoped editor.
    QVERIFY(m_fixture.document().canAddTrack());
    const int addedTrack = m_fixture.document().addTrack(0);
    QVERIFY(addedTrack > 0);
    QVERIFY(QTest::qWaitFor(
        [this, addedTrack] { return trackHeaderWindowPoint(m_fixture, addedTrack).has_value(); }));
    const std::optional<QPoint> headerPoint = trackHeaderWindowPoint(m_fixture, addedTrack);
    QVERIFY(headerPoint.has_value());

    songview::PitchBendEditor *openedEditor = popup();
    QVERIFY(openedEditor);
    QPointer<songview::PitchBendEditor> editor = openedEditor;
    QQuickItem *content = m_fixture.formContent();
    QVERIFY(content);
    QTest::mouseClick(&m_fixture.timelineWindow(), Qt::LeftButton, Qt::NoModifier,
                      m_fixture.windowPoint(*content, QPoint(4, 24)));
    QVERIFY(editor->isOpen());
    QTest::mouseClick(&m_fixture.timelineWindow(), Qt::LeftButton, Qt::NoModifier,
                      rollWindowPoint(m_fixture, QPoint(1, 1)));
    QTRY_VERIFY(!editor || !editor->isOpen());
    m_fixture.drainDeferredDeletes();
    QVERIFY(editor.isNull());

    songview::PitchBendEditor *reopened = popup();
    QVERIFY(reopened);
    QPointer<songview::PitchBendEditor> forwarded = reopened;
    // The pass-through probe must click a real other-UI header and select it.
    QQuickItem *panel = m_fixture.formContent();
    QVERIFY(panel);
    const QRect panelRect(panel->mapToScene(QPointF(0, 0)).toPoint(),
                          QSize(qRound(panel->width()), qRound(panel->height())));
    QVERIFY2(!panelRect.contains(*headerPoint),
             "the header probe point must sit outside the popup form panel");
    QTest::mouseClick(&m_fixture.timelineWindow(), Qt::LeftButton, Qt::NoModifier, *headerPoint);
    QTRY_VERIFY(!forwarded || !forwarded->isOpen());
    m_fixture.drainDeferredDeletes();
    QVERIFY(forwarded.isNull());
    QTRY_COMPARE(m_fixture.view().selectionModel().primaryTrack(), addedTrack);
    m_fixture.view().selectTrack(0);
}

void PitchBendEditingTest::popupDismissalReturnsFocusToRollInputItem()
{
    QVERIFY(popup());
    m_fixture.closePopupViaEscape();
    QTRY_VERIFY(m_fixture.rollInput().hasActiveFocus());
}

void PitchBendEditingTest::windowDeactivateCommitsWithoutFocusRestore()
{
    songview::PitchBendEditor *editorResult = popup();
    QVERIFY(editorResult);
    songview::PitchBendGraph *graphResult = pitchGraph();
    QVERIFY(graphResult);
    songview::PitchBendGraph &graph = *graphResult;
    const int index = m_fixture.document().undoStack()->index();
    const QPoint start = graph.canvasRect().center();
    QTest::mousePress(&m_fixture.timelineWindow(), Qt::LeftButton, Qt::NoModifier,
                      m_fixture.windowPoint(graph, start));
    checks::events::sendMouse(graph, QEvent::MouseMove, start + QPoint(20, -12), Qt::NoButton,
                              Qt::LeftButton, Qt::NoModifier);
    QVERIFY(graph.hasGesture());
    // The shared session cancels on shared-window deactivation; the live
    // editor commits its pending stroke without restoring roll focus.
    QEvent deactivate(QEvent::WindowDeactivate);
    QCoreApplication::sendEvent(&m_fixture.timelineWindow(), &deactivate);
    QTRY_VERIFY(!m_fixture.popup());
    QCOMPARE(m_fixture.document().undoStack()->index(), index + 1);
    QVERIFY(!m_fixture.rollInput().hasActiveFocus());
}

void PitchBendEditingTest::unterminatedNoteSpanRejectsEditing()
{
    m_fixture.tearDown();
    QVERIFY(m_fixture.setUp(true));
    QVERIFY(m_fixture.note().unterminated());
    QCOMPARE(m_fixture.document().noteEndTick(m_fixture.note()), m_fixture.note().tick);
    QCOMPARE(m_fixture.endTick(), m_fixture.note().tick);
    const QByteArray before = m_fixture.smf();
    m_fixture.rollInput().forceActiveFocus(Qt::OtherFocusReason);
    QTest::keyClick(&m_fixture.timelineWindow(), Qt::Key_G);
    m_fixture.drainDeferredDeletes();
    QVERIFY(!m_fixture.popup());
    QCOMPARE(m_fixture.smf(), before);
}
