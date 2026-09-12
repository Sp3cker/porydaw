#include "checks/pitchbend/tst_pitchbendediting.h"

#include <QEvent>
#include <QtTest>

#include "checks/support/eventsynth.h"

#include <algorithm>

namespace {
QPoint canvasPoint(const songview::PitchBendGraph &graph, qreal xFraction, qreal yFraction)
{
    const QRect canvas = graph.canvasRect();
    return QPoint(qRound(canvas.left() + canvas.width() * xFraction),
                  qRound(canvas.top() + canvas.height() * yFraction));
}

bool sameLaneValues(const std::vector<SongDocument::LanePointValue> &left,
                    const std::vector<SongDocument::LanePointValue> &right)
{
    if (left.size() != right.size())
        return false;
    for (std::size_t index = 0; index < left.size(); ++index) {
        if (left[index].tick != right[index].tick || left[index].value != right[index].value)
            return false;
    }
    return true;
}
} // namespace
void PitchBendEditingTest::bendrFixtureUndoPreservation()
{
    const QByteArray before = m_fixture.smf();
    const int index = m_fixture.document().undoStack()->index();
    m_fixture.document().writeLanePoints(0, 0x14, m_fixture.note().tick, m_fixture.note().tick,
                                         {{m_fixture.note().tick, 12}});
    QCOMPARE(m_fixture.document().undoStack()->index(), index + 1);
    QVERIFY(m_fixture.hasLanePoint(0x14, m_fixture.note().tick, 12));
    m_fixture.document().undoStack()->undo();
    QCOMPARE(m_fixture.document().undoStack()->index(), index);
    QCOMPARE(m_fixture.smf(), before);
    QVERIFY(m_fixture.document().containsNoteSpan(0, m_fixture.note(), m_fixture.endTick()));
}

void PitchBendEditingTest::shiftDragDrawsLinearRamp()
{
    songview::PitchBendEditor *editorResult = popup();
    QVERIFY(editorResult);
    songview::PitchBendGraph *graphResult = pitchGraph();
    QVERIFY(graphResult);
    songview::PitchBendGraph &graph = *graphResult;
    const int index = m_fixture.document().undoStack()->index();
    const QByteArray before = m_fixture.smf();
    QVERIFY(m_fixture.stroke(graph, canvasPoint(graph, 0.15, 0.80), canvasPoint(graph, 0.85, 0.20),
                             Qt::ShiftModifier));
    QCOMPARE(m_fixture.document().undoStack()->index(), index + 1);
    // Rendering the Shift line can race a dismissed popup; assert liveness
    // instead of dereferencing a dead editor.
    QCoreApplication::processEvents();
    QPointer<songview::PitchBendEditor> alive = editorResult;
    QVERIFY2(alive && alive->isOpen(), "popup was dismissed while rendering its Shift line");
    const std::vector<DocLanePoint> interior = m_fixture.interiorPoints(DOC_CC_BEND);
    QVERIFY(interior.size() >= 2);
    QVERIFY(std::adjacent_find(interior.cbegin(), interior.cend(),
                               [](const DocLanePoint &a, const DocLanePoint &b) {
                                   return a.value == b.value;
                               }) == interior.cend());
    m_fixture.document().undoStack()->undo();
    QCOMPARE(m_fixture.smf(), before);
}

void PitchBendEditingTest::freehandStrokePushesSingleUndoCommand()
{
    songview::PitchBendEditor *editorResult = popup();
    QVERIFY(editorResult);
    songview::PitchBendGraph *graph = pitchGraph();
    QVERIFY(graph);
    const int index = m_fixture.document().undoStack()->index();
    QVERIFY(drawPitchCurve(*graph));
    QCOMPARE(m_fixture.document().undoStack()->index(), index + 1);
    QPointer<songview::PitchBendEditor> alive = editorResult;
    QVERIFY(alive && alive->isOpen());
    QTest::keyClick(&m_fixture.timelineWindow(), Qt::Key_Enter);
    QVERIFY(alive && alive->isOpen());
    QVERIFY(m_fixture.popup() == alive);
}

void PitchBendEditingTest::standardUndoShortcutRestoresCurve()
{
    songview::PitchBendEditor *editorResult = popup();
    QVERIFY(editorResult);
    songview::PitchBendGraph *graphResult = pitchGraph();
    QVERIFY(graphResult);
    songview::PitchBendGraph &graph = *graphResult;
    const QByteArray before = m_fixture.smf();
    const int index = m_fixture.document().undoStack()->index();
    QVERIFY(drawPitchCurve(graph));
    QVERIFY(m_fixture.sendUndo());
    QCOMPARE(m_fixture.document().undoStack()->index(), index);
    QCOMPARE(m_fixture.smf(), before);
    // Acquiring Undo focus can dismiss a closing popup; guard the liveness
    // assertions.
    QPointer<songview::PitchBendEditor> alive = editorResult;
    QPointer<songview::PitchBendGraph> guardedGraph = graphResult;
    QVERIFY(alive && alive->isOpen());
    QVERIFY(guardedGraph && guardedGraph->hasActiveFocus());
}

void PitchBendEditingTest::navigationKeysDoNotModifyCurve_data()
{
    QTest::addColumn<int>("key");
    QTest::addColumn<int>("modifiers");
    QTest::newRow("left") << int(Qt::Key_Left) << int(Qt::NoModifier);
    QTest::newRow("right") << int(Qt::Key_Right) << int(Qt::NoModifier);
    QTest::newRow("home") << int(Qt::Key_Home) << int(Qt::NoModifier);
    QTest::newRow("end") << int(Qt::Key_End) << int(Qt::NoModifier);
    QTest::newRow("up") << int(Qt::Key_Up) << int(Qt::NoModifier);
    QTest::newRow("shift-down") << int(Qt::Key_Down) << int(Qt::ShiftModifier);
    QTest::newRow("page-up") << int(Qt::Key_PageUp) << int(Qt::NoModifier);
    QTest::newRow("page-down") << int(Qt::Key_PageDown) << int(Qt::NoModifier);
    QTest::newRow("zero") << int(Qt::Key_0) << int(Qt::NoModifier);
}

void PitchBendEditingTest::navigationKeysDoNotModifyCurve()
{
    QFETCH(int, key);
    QFETCH(int, modifiers);
    songview::PitchBendEditor *editorResult = popup();
    QVERIFY(editorResult);
    songview::PitchBendEditor &editor = *editorResult;
    const QByteArray before = m_fixture.smf();
    const int index = m_fixture.document().undoStack()->index();
    QTest::keyClick(&m_fixture.timelineWindow(), Qt::Key(key), Qt::KeyboardModifiers(modifiers));
    QCOMPARE(m_fixture.document().undoStack()->index(), index);
    QCOMPARE(m_fixture.smf(), before);
    QVERIFY(editor.isOpen());
}

void PitchBendEditingTest::stackedStrokesPushIndependentUndoCommands()
{
    QVERIFY(popup());
    songview::PitchBendGraph *graphResult = pitchGraph();
    QVERIFY(graphResult);
    songview::PitchBendGraph &graph = *graphResult;
    const QByteArray baseline = m_fixture.smf();
    const int baselineIndex = m_fixture.document().undoStack()->index();
    QVERIFY(drawPitchCurve(graph));
    const QByteArray first = m_fixture.smf();
    const int firstIndex = m_fixture.document().undoStack()->index();
    QCOMPARE(firstIndex, baselineIndex + 1);
    QVERIFY(
        m_fixture.stroke(graph, canvasPoint(graph, 0.10, 0.25), canvasPoint(graph, 0.40, 0.75)));
    QCOMPARE(m_fixture.document().undoStack()->index(), firstIndex + 1);
    QVERIFY(m_fixture.smf() != first);
    m_fixture.document().undoStack()->undo();
    QCOMPARE(m_fixture.document().undoStack()->index(), firstIndex);
    QCOMPARE(m_fixture.smf(), first);
    m_fixture.document().undoStack()->undo();
    QCOMPARE(m_fixture.document().undoStack()->index(), baselineIndex);
    QCOMPARE(m_fixture.smf(), baseline);
}

void PitchBendEditingTest::freehandStrokeConfinedToNoteSpan()
{
    QVERIFY(popup());
    songview::PitchBendGraph *graph = pitchGraph();
    QVERIFY(graph);
    const int endValue = m_fixture.effectiveLaneValue(DOC_CC_BEND, m_fixture.endTick(), 0);
    const std::vector<DocLanePoint> before = m_fixture.document().lanePoints(0, DOC_CC_BEND);
    QVERIFY(drawPitchCurve(*graph));
    bool wroteInside = false;
    for (const DocLanePoint &point : m_fixture.document().lanePoints(0, DOC_CC_BEND)) {
        const bool existedBefore =
            std::any_of(before.cbegin(), before.cend(), [&point](const DocLanePoint &beforePoint) {
                return beforePoint.tick == point.tick && beforePoint.value == point.value;
            });
        if (existedBefore)
            continue;
        QVERIFY(point.tick >= m_fixture.note().tick);
        QVERIFY(point.tick <= m_fixture.endTick());
        if (point.tick < m_fixture.endTick() && point.value != 0)
            wroteInside = true;
    }
    QVERIFY(wroteInside);
    QVERIFY(m_fixture.hasLanePoint(DOC_CC_BEND, m_fixture.endTick(), endValue));
}

void PitchBendEditingTest::pitchWheelSerializesValidSmfEvents()
{
    QVERIFY(popup());
    songview::PitchBendGraph *graph = pitchGraph();
    QVERIFY(graph);
    QVERIFY(drawPitchCurve(*graph));
    const int smfTrack = m_fixture.document().smfTrackFor(0);
    QVERIFY(smfTrack >= 0);
    bool found = false;
    for (const SmfEvent &event : m_fixture.document().smf().tracks[size_t(smfTrack)].events) {
        if (event.tick >= m_fixture.note().tick && event.tick <= m_fixture.endTick() &&
            event.typeNibble() == 0xE) {
            found = true;
            QVERIFY(event.data0 <= 0x7F);
            QVERIFY(event.data1 <= 0x7F);
        }
    }
    QVERIFY(found);
}

void PitchBendEditingTest::duplicateNoteAtSameTickDoesNotAnchorStaleNote()
{
    m_fixture.tearDown();
    QVERIFY(m_fixture.setUp(false, true));

    const std::vector<DocNote> notes = m_fixture.document().notesForTrack(0);
    QCOMPARE(notes.size(), size_t{2});
    const DocNote selected = notes.front();
    const DocNote sameTickImpostor = notes.back();
    QVERIFY(selected.noteId.isAssigned());
    QVERIFY(sameTickImpostor.noteId.isAssigned());
    QVERIFY(selected.noteId != sameTickImpostor.noteId);
    QCOMPARE(sameTickImpostor.tick, selected.tick);
    QCOMPARE(sameTickImpostor.key, selected.key);

    const int index = m_fixture.document().undoStack()->index();
    const QByteArray before = m_fixture.smf();
    const uint64_t selectedEnd = m_fixture.document().noteEndTick(selected);
    m_fixture.view().selectionModel().setNoteSelection({selected.noteId});
    songview::PitchBendEditor *editor = m_fixture.openPopup();
    QVERIFY(editor);
    QCOMPARE(editor->endTick(), selectedEnd);

    QPointer<songview::PitchBendEditor> guardedEditor = editor;
    m_fixture.document().deleteNotes({selected});
    QTRY_VERIFY(!guardedEditor || !guardedEditor->isOpen());
    m_fixture.drainDeferredDeletes();
    QVERIFY(guardedEditor.isNull());

    DocNote survivingImpostor;
    QVERIFY(m_fixture.document().findNote(sameTickImpostor.noteId, &survivingImpostor));
    QVERIFY(!m_fixture.document().containsNoteSpan(0, selected, selectedEnd));

    m_fixture.document().undoStack()->undo();
    QCOMPARE(m_fixture.document().undoStack()->index(), index);
    QCOMPARE(m_fixture.smf(), before);
    QVERIFY(m_fixture.document().containsNoteSpan(0, selected, selectedEnd));
}

void PitchBendEditingTest::activeGesturePreservesPreviewAcrossExternalEdit()
{
    QPointer<songview::PitchBendEditor> editor = popup();
    QVERIFY(editor);
    QPointer<songview::PitchBendGraph> graph = pitchGraph();
    QVERIFY(graph);
    const QPoint start = canvasPoint(*graph, 0.25, 0.70);
    const QPoint finish = canvasPoint(*graph, 0.75, 0.30);
    QTest::mousePress(&m_fixture.timelineWindow(), Qt::LeftButton, Qt::NoModifier,
                      m_fixture.windowPoint(*graph, start));
    checks::events::sendMouse(*graph, QEvent::MouseMove, finish, Qt::NoButton, Qt::LeftButton,
                              Qt::NoModifier);
    QVERIFY(graph && graph->hasGesture());
    const auto preview = graph->curvePoints();
    const QByteArray beforeExternalEdit = m_fixture.smf();
    const int externalEditIndex = m_fixture.document().undoStack()->index();
    m_fixture.document().writeLanePoints(
        0, 0x15, m_fixture.note().tick, m_fixture.endTick(),
        {{m_fixture.note().tick, 23}, {Tick(m_fixture.endTick()), 22}});
    // The external edit pushes exactly one command and must not resolve the
    // live preview through a reentrant history push.
    QCOMPARE(m_fixture.document().undoStack()->index(), externalEditIndex + 1);
    QVERIFY(m_fixture.smf() != beforeExternalEdit);
    QVERIFY(graph && sameLaneValues(graph->curvePoints(), preview));
    // Undoing the real external lane edit restores the exact pre-edit SMF
    // while the pending preview stays live; redo re-applies it the same way.
    m_fixture.document().undoStack()->undo();
    QCOMPARE(m_fixture.document().undoStack()->index(), externalEditIndex);
    QCOMPARE(m_fixture.smf(), beforeExternalEdit);
    QVERIFY(graph && graph->hasGesture());
    QVERIFY(graph && sameLaneValues(graph->curvePoints(), preview));
    m_fixture.document().undoStack()->redo();
    QCOMPARE(m_fixture.document().undoStack()->index(), externalEditIndex + 1);
    QVERIFY(m_fixture.smf() != beforeExternalEdit);
    QVERIFY(graph && sameLaneValues(graph->curvePoints(), preview));
    if (editor)
        QTest::keyClick(&m_fixture.timelineWindow(), Qt::Key_Escape);
    m_fixture.drainDeferredDeletes();
    QVERIFY(!m_fixture.popup());
}

void PitchBendEditingTest::modWheelFreehandStrokeAndUndo()
{
    songview::PitchBendEditor *editorResult = popup();
    QVERIFY(editorResult);
    songview::PitchBendEditor &editor = *editorResult;
    songview::PitchBendGraph *graph = modGraph();
    QVERIFY(graph);
    const QByteArray before = m_fixture.smf();
    const int endValue = m_fixture.effectiveLaneValue(1, m_fixture.endTick(), 0);
    const int index = m_fixture.document().undoStack()->index();
    QVERIFY(drawModCurve(*graph));
    QCOMPARE(m_fixture.document().undoStack()->index(), index + 1);
    const std::vector<DocLanePoint> interior = m_fixture.interiorPoints(1);
    QVERIFY(std::any_of(interior.cbegin(), interior.cend(),
                        [](const DocLanePoint &point) { return point.value > 0; }));
    QVERIFY(m_fixture.hasLanePoint(1, m_fixture.endTick(), endValue));
    QVERIFY(m_fixture.sendUndo());
    QCOMPARE(m_fixture.smf(), before);
    QVERIFY(editor.isOpen());
}

void PitchBendEditingTest::altDragCreatesFineGridRamp()
{
    songview::PitchBendEditor *editorResult = popup();
    QVERIFY(editorResult);
    songview::PitchBendEditor &editor = *editorResult;
    songview::PitchBendGraph *graphResult = pitchGraph();
    QVERIFY(graphResult);
    songview::PitchBendGraph &graph = *graphResult;
    const QByteArray before = m_fixture.smf();
    const int index = m_fixture.document().undoStack()->index();
    QVERIFY(m_fixture.stroke(graph, canvasPoint(graph, 0.10, 0.85), canvasPoint(graph, 0.90, 0.15),
                             Qt::AltModifier));
    QCOMPARE(m_fixture.document().undoStack()->index(), index + 1);
    const std::vector<DocLanePoint> points = m_fixture.interiorPoints(DOC_CC_BEND);
    QVERIFY(points.size() >= 3);
    for (size_t i = 1; i < points.size(); ++i) {
        QVERIFY(points[i].tick - points[i - 1].tick <= m_fixture.view().grid().fineGridTicks());
        QVERIFY(points[i].value > points[i - 1].value);
    }
    m_fixture.document().undoStack()->undo();
    QCOMPARE(m_fixture.smf(), before);
    QVERIFY(editor.isOpen());
}

void PitchBendEditingTest::strokeAcrossSignatureBoundaryAlignsToDynamicGrid()
{
    constexpr Tick start = 288;
    constexpr uint32_t duration = 384;
    constexpr Tick boundary = start + duration / 2;
    m_fixture.document().addNote(0, start, 61, uint32_t(duration), 100);
    m_fixture.document().setTimeSig(boundary, 8, 3);
    DocNote boundaryNote;
    QVERIFY(m_fixture.document().findNote(0, start, 61, &boundaryNote));
    m_fixture.view().selectionModel().setNoteSelection({boundaryNote.noteId});
    m_fixture.rollInput().forceActiveFocus(Qt::OtherFocusReason);
    QTest::keyClick(&m_fixture.timelineWindow(), Qt::Key_G);
    QVERIFY(QTest::qWaitFor([this] { return m_fixture.popup() != nullptr; }));
    songview::PitchBendEditor *editor = m_fixture.popup();
    QVERIFY(editor);
    QCOMPARE(editor->endTick(), start + duration);
    songview::PitchBendGraph *graph = m_fixture.graph(QStringLiteral("pitchBendGraph"));
    QVERIFY(graph);
    const QRect canvas = graph->canvasRect();
    const double pixelsPerTick = double(canvas.width()) / double(duration);
    QVERIFY(
        m_fixture.stroke(*graph, canvasPoint(*graph, 0.10, 0.80), canvasPoint(*graph, 0.90, 0.20)));
    bool before = false;
    bool after = false;
    for (const DocLanePoint &point : m_fixture.document().lanePoints(0, DOC_CC_BEND)) {
        if (point.tick <= start || point.tick >= start + duration)
            continue;
        const songview::Grid::Segment segment = m_fixture.view().grid().segmentAt(point.tick);
        const Tick cell = m_fixture.view().grid().gridTicksAtScale(point.tick, pixelsPerTick);
        QVERIFY(cell > 0 && point.tick >= segment.start &&
                (point.tick - segment.start) % cell == 0);
        before |= point.tick < boundary;
        after |= point.tick > boundary;
    }
    QVERIFY(before);
    QVERIFY(after);
}

void PitchBendEditingTest::modWheelResetZeroesLane()
{
    songview::PitchBendEditor *editorResult = popup();
    QVERIFY(editorResult);
    songview::PitchBendEditor &editor = *editorResult;
    songview::PitchBendGraph *graph = modGraph();
    QVERIFY(graph);
    QVERIFY(drawModCurve(*graph));
    const int endValue = m_fixture.effectiveLaneValue(1, m_fixture.endTick(), 0);
    const int index = m_fixture.document().undoStack()->index();
    QQuickItem *reset = m_fixture.item(QStringLiteral("modWheelReset"));
    QVERIFY(reset);
    QVERIFY(m_fixture.click(*reset));
    QCOMPARE(m_fixture.document().undoStack()->index(), index + 1);
    for (const DocLanePoint &point : m_fixture.interiorPoints(1))
        QCOMPARE(point.value, 0);
    QVERIFY(m_fixture.hasLanePoint(1, m_fixture.endTick(), endValue));
    QVERIFY(editor.isOpen());
}

int runPitchBendEditingCheck(const QStringList &qtArguments)
{
    PitchBendEditingTest test;
    QStringList arguments{QStringLiteral("pitch-bend-editing")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
