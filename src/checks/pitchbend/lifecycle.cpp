#include "checks/pitchbend/tst_pitchbendediting.h"

#include <QApplication>
#include <QCoreApplication>
#include <QEvent>
#include <QtTest>

#include "checks/support/eventsynth.h"
#include "ui/songview/quick/timelinequickview.h"

#include <cstdlib>
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
} // namespace

void PitchBendEditingTest::keyGAnchorsPopupToSelectedNoteWithinWindowBounds()
{
    m_fixture.view().selectionModel().setNoteSelection({m_fixture.note().noteId});
    m_fixture.rollInput().forceActiveFocus(Qt::OtherFocusReason);
    checks::events::sendMouse(m_fixture.rollInput(), QEvent::MouseMove, QPoint(1, 1), Qt::NoButton,
                              Qt::NoButton, Qt::NoModifier);
    QTest::keyClick(&m_fixture.timelineWindow(), Qt::Key_G);
    QVERIFY(QTest::qWaitFor([this] { return m_fixture.popup() != nullptr; }));
    songview::PitchBendEditor &editor = *m_fixture.popup();
    const QRect popupRect = editor.view()->geometry();
    const QRect hostRect = m_fixture.tab().window()->geometry();
    const QPoint noteGlobal =
        m_fixture.timelineWindow().mapToGlobal(rollWindowPoint(m_fixture, m_fixture.notePoint()));
    QVERIFY(hostRect.intersects(popupRect));
    QVERIFY(std::abs(popupRect.center().x() - noteGlobal.x()) <= popupRect.width() / 2 + 12);
    QVERIFY(popupRect.top() >= hostRect.top());
    QVERIFY(popupRect.bottom() <= hostRect.bottom());
    QVERIFY(editor.view()->flags().testFlag(Qt::Tool));
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
    songview::PitchBendEditor &editor = *editorResult;
    songview::PitchBendGraph *graphResult = pitchGraph();
    QVERIFY(graphResult);
    songview::PitchBendGraph &graph = *graphResult;
    checks::events::sendMouse(graph, QEvent::MouseMove, graph.canvasRect().center(), Qt::NoButton,
                              Qt::NoButton, Qt::NoModifier);
    QVERIFY(editor.isOpen());
    QVERIFY(m_fixture.popup() == &editor);
}

void PitchBendEditingTest::enterKeyDoesNotDismissPopup()
{
    songview::PitchBendEditor *editorResult = popup();
    QVERIFY(editorResult);
    songview::PitchBendEditor &editor = *editorResult;
    QTest::keyClick(editor.view(), Qt::Key_Enter);
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
    songview::PitchBendEditor *openedEditor = popup();
    QVERIFY(openedEditor);
    QPointer<songview::PitchBendEditor> editor = openedEditor;
    QTest::mouseClick(editor->view(), Qt::LeftButton, Qt::NoModifier, QPoint(4, 24));
    QVERIFY(editor->isOpen());
    QTest::mouseClick(&m_fixture.timelineWindow(), Qt::LeftButton, Qt::NoModifier,
                      rollWindowPoint(m_fixture, QPoint(1, 1)));
    QTRY_VERIFY(!editor || !editor->isOpen());
    m_fixture.drainDeferredDeletes();
    QVERIFY(editor.isNull());
}

void PitchBendEditingTest::popupDismissalReturnsFocusToRollInputItem()
{
    QVERIFY(popup());
    m_fixture.closePopupViaEscape();
    QTRY_VERIFY(m_fixture.rollInput().hasActiveFocus());
}

void PitchBendEditingTest::applicationDeactivateCommitsWithoutFocusRestore()
{
    songview::PitchBendEditor *editorResult = popup();
    QVERIFY(editorResult);
    songview::PitchBendEditor &editor = *editorResult;
    songview::PitchBendGraph *graphResult = pitchGraph();
    QVERIFY(graphResult);
    songview::PitchBendGraph &graph = *graphResult;
    const int index = m_fixture.document().undoStack()->index();
    const QPoint start = graph.canvasRect().center();
    QTest::mousePress(editor.view(), Qt::LeftButton, Qt::NoModifier,
                      m_fixture.windowPoint(graph, start));
    checks::events::sendMouse(graph, QEvent::MouseMove, start + QPoint(20, -12), Qt::NoButton,
                              Qt::LeftButton, Qt::NoModifier);
    QVERIFY(graph.hasGesture());
    QEvent event(QEvent::ApplicationDeactivate);
    QCoreApplication::sendEvent(qApp, &event);
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
