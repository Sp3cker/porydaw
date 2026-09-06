#include "checks/pitchbend/tst_pitchbendediting.h"

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
} // namespace
void PitchBendEditingTest::vertexCreation_data()
{
    QTest::addColumn<QString>("name");
    QTest::newRow("pitch") << QStringLiteral("pitchBendGraph");
    QTest::newRow("mod-wheel") << QStringLiteral("modWheelGraph");
}

void PitchBendEditingTest::vertexCreation()
{
    QFETCH(QString, name);
    QVERIFY(popup());
    songview::PitchBendGraph *graph = m_fixture.graph(name);
    QVERIFY(graph);
    const uint8_t cc = graph->lane() == songview::PitchBendGraph::Lane::PitchBend ? DOC_CC_BEND : 1;
    const int index = m_fixture.document().undoStack()->index();
    QVERIFY(
        m_fixture.stroke(*graph, canvasPoint(*graph, 0.20, 0.80), canvasPoint(*graph, 0.80, 0.20)));
    QCOMPARE(m_fixture.document().undoStack()->index(), index + 1);
    QVERIFY(!m_fixture.interiorPoints(cc).empty());
}

void PitchBendEditingTest::vertexHitTestAndSelection_data()
{
    vertexCreation_data();
}

void PitchBendEditingTest::vertexHitTestAndSelection()
{
    QFETCH(QString, name);
    songview::PitchBendEditor *editor = popup();
    QVERIFY(editor);
    songview::PitchBendGraph *graph = m_fixture.graph(name);
    QVERIFY(graph);
    const uint8_t cc = graph->lane() == songview::PitchBendGraph::Lane::PitchBend ? DOC_CC_BEND : 1;
    QVERIFY(
        m_fixture.stroke(*graph, canvasPoint(*graph, 0.20, 0.80), canvasPoint(*graph, 0.80, 0.20)));
    const std::vector<DocLanePoint> interior = m_fixture.interiorPoints(cc);
    QVERIFY(!interior.empty());
    const DocLanePoint target = interior[interior.size() / 2];
    const QPoint position = graph->vertexPosition(target.tick, target.value);
    const auto hit = graph->hitTest(position);
    QVERIFY(hit.has_value());
    QCOMPARE(hit->first, target.tick);
    QTest::mouseClick(editor->view(), Qt::LeftButton, Qt::NoModifier,
                      m_fixture.windowPoint(*graph, position));
    QVERIFY(graph->selectedTick().has_value());
    QCOMPARE(*graph->selectedTick(), target.tick);
}

void PitchBendEditingTest::vertexAltDragMovesPoint_data()
{
    vertexCreation_data();
}

void PitchBendEditingTest::vertexAltDragMovesPoint()
{
    QFETCH(QString, name);
    songview::PitchBendEditor *editor = popup();
    QVERIFY(editor);
    songview::PitchBendGraph *graph = m_fixture.graph(name);
    QVERIFY(graph);
    const uint8_t cc = graph->lane() == songview::PitchBendGraph::Lane::PitchBend ? DOC_CC_BEND : 1;
    QVERIFY(
        m_fixture.stroke(*graph, canvasPoint(*graph, 0.20, 0.80), canvasPoint(*graph, 0.80, 0.20)));
    const DocLanePoint target = m_fixture.interiorPoints(cc).at(0);
    const QPoint source = graph->vertexPosition(target.tick, target.value);
    const QRect canvas = graph->canvasRect();
    const QPoint destination(std::clamp(source.x() + 20, canvas.left() + 2, canvas.right() - 2),
                             std::clamp(source.y() - 10, canvas.top() + 2, canvas.bottom() - 2));
    const int index = m_fixture.document().undoStack()->index();
    QTest::mousePress(editor->view(), Qt::LeftButton, Qt::AltModifier,
                      m_fixture.windowPoint(*graph, source));
    checks::events::sendMouse(*graph, QEvent::MouseMove, destination, Qt::NoButton, Qt::LeftButton,
                              Qt::AltModifier);
    QTest::mouseRelease(editor->view(), Qt::LeftButton, Qt::AltModifier,
                        m_fixture.windowPoint(*graph, destination));
    QCOMPARE(m_fixture.document().undoStack()->index(), index + 1);
    QVERIFY(graph->selectedTick().has_value());
    QVERIFY(*graph->selectedTick() != target.tick);
    QVERIFY(!m_fixture.document().findLanePoint(0, cc, target.tick, nullptr));
    m_fixture.document().undoStack()->undo();
    QVERIFY(m_fixture.document().findLanePoint(0, cc, target.tick, nullptr));
}

void PitchBendEditingTest::vertexDeleteRemovesInteriorPoint_data()
{
    QTest::addColumn<QString>("name");
    QTest::addColumn<int>("key");
    QTest::newRow("pitch-delete") << QStringLiteral("pitchBendGraph") << int(Qt::Key_Delete);
    QTest::newRow("mod-backspace") << QStringLiteral("modWheelGraph") << int(Qt::Key_Backspace);
}

void PitchBendEditingTest::vertexDeleteRemovesInteriorPoint()
{
    QFETCH(QString, name);
    QFETCH(int, key);
    songview::PitchBendEditor *editor = popup();
    QVERIFY(editor);
    songview::PitchBendGraph *graph = m_fixture.graph(name);
    QVERIFY(graph);
    const uint8_t cc = graph->lane() == songview::PitchBendGraph::Lane::PitchBend ? DOC_CC_BEND : 1;
    QVERIFY(
        m_fixture.stroke(*graph, canvasPoint(*graph, 0.20, 0.80), canvasPoint(*graph, 0.80, 0.20)));
    const DocLanePoint target = m_fixture.interiorPoints(cc).at(0);
    QTest::mouseClick(
        editor->view(), Qt::LeftButton, Qt::NoModifier,
        m_fixture.windowPoint(*graph, graph->vertexPosition(target.tick, target.value)));
    const int index = m_fixture.document().undoStack()->index();
    QTest::keyClick(editor->view(), Qt::Key(key));
    QCOMPARE(m_fixture.document().undoStack()->index(), index + 1);
    QVERIFY(!m_fixture.document().findLanePoint(0, cc, target.tick, nullptr));
    QVERIFY(m_fixture.document().findLanePoint(0, cc, m_fixture.note().tick, nullptr));
    QVERIFY(m_fixture.document().findLanePoint(0, cc, m_fixture.endTick(), nullptr));
    m_fixture.document().undoStack()->undo();
    QVERIFY(m_fixture.document().findLanePoint(0, cc, target.tick, nullptr));
}

void PitchBendEditingTest::vertexEndpointDeletionIsRejected_data()
{
    QTest::addColumn<QString>("name");
    QTest::addColumn<bool>("end");
    QTest::addColumn<int>("key");
    QTest::newRow("pitch-start-delete")
        << QStringLiteral("pitchBendGraph") << false << int(Qt::Key_Delete);
    QTest::newRow("pitch-end-delete")
        << QStringLiteral("pitchBendGraph") << true << int(Qt::Key_Delete);
    QTest::newRow("mod-start-delete")
        << QStringLiteral("modWheelGraph") << false << int(Qt::Key_Delete);
    QTest::newRow("mod-end-delete")
        << QStringLiteral("modWheelGraph") << true << int(Qt::Key_Delete);
}

void PitchBendEditingTest::vertexEndpointDeletionIsRejected()
{
    QFETCH(QString, name);
    QFETCH(bool, end);
    QFETCH(int, key);
    songview::PitchBendEditor *editor = popup();
    QVERIFY(editor);
    songview::PitchBendGraph *graph = m_fixture.graph(name);
    QVERIFY(graph);
    const uint8_t cc = graph->lane() == songview::PitchBendGraph::Lane::PitchBend ? DOC_CC_BEND : 1;
    QVERIFY(
        m_fixture.stroke(*graph, canvasPoint(*graph, 0.20, 0.80), canvasPoint(*graph, 0.80, 0.20)));
    const uint64_t tick = end ? m_fixture.endTick() : m_fixture.note().tick;
    const int value = m_fixture.effectiveLaneValue(cc, tick, 0);
    QVERIFY(m_fixture.document().findLanePoint(0, cc, m_fixture.note().tick, nullptr));
    QVERIFY(m_fixture.document().findLanePoint(0, cc, m_fixture.endTick(), nullptr));
    QTest::mouseClick(editor->view(), Qt::LeftButton, Qt::NoModifier,
                      m_fixture.windowPoint(*graph, graph->vertexPosition(tick, value)));
    QVERIFY(graph->selectedTick().has_value());
    QCOMPARE(*graph->selectedTick(), tick);
    const QByteArray before = m_fixture.smf();
    const int index = m_fixture.document().undoStack()->index();
    QTest::keyClick(editor->view(), Qt::Key(key));
    QCOMPARE(m_fixture.document().undoStack()->index(), index);
    QCOMPARE(m_fixture.smf(), before);
}
