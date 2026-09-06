#include "checks/pitchbend/tst_pitchbendediting.h"

#include <QCoreApplication>
#include <QEnterEvent>
#include <QKeyEvent>
#include <QSignalSpy>
#include <QtTest>

#include "checks/support/eventsynth.h"

namespace {
bool hover(QQuickWindow &window, QQuickItem &item)
{
    if (item.window() != &window || !item.isVisible() || item.width() <= 0 || item.height() <= 0)
        return false;
    const QPoint position = item.mapToScene(item.boundingRect().center()).toPoint();
    const QPointF windowPosition(position);
    QEnterEvent enter(windowPosition, windowPosition, QPointF(window.mapToGlobal(position)));
    QCoreApplication::sendEvent(&window, &enter);
    if (!checks::events::primeMouseMove(window, item, position))
        return false;
    QTest::mouseEvent(QTest::MouseMove, &window, Qt::NoButton, Qt::NoModifier, position);
    QCoreApplication::processEvents();
    return true;
}

bool spanIsDefault(const PitchBendFixture &fixture, uint8_t cc, int defaultValue)
{
    for (const DocLanePoint &point : fixture.document().lanePoints(0, cc)) {
        if (point.tick >= fixture.note().tick && point.tick < fixture.endTick() &&
            point.value != defaultValue) {
            return false;
        }
    }
    return true;
}
} // namespace

void PitchBendEditingTest::wheelScrollConfinesBendRangeToNoteSpan_data()
{
    QTest::addColumn<bool>("inside");
    QTest::addColumn<int>("delta");
    QTest::newRow("outside-graph-negative") << false << 1;
    QTest::newRow("inside-graph") << true << 1;
    QTest::newRow("inside-multiple-notches") << true << 2;
}

void PitchBendEditingTest::wheelScrollConfinesBendRangeToNoteSpan()
{
    QFETCH(bool, inside);
    QFETCH(int, delta);
    songview::PitchBendEditor *editorResult = popup();
    QVERIFY(editorResult);
    songview::PitchBendEditor &editor = *editorResult;
    songview::PitchBendGraph *graphResult = pitchGraph();
    QVERIFY(graphResult);
    songview::PitchBendGraph &graph = *graphResult;
    const int initialRange = editor.bendRange();
    const int index = m_fixture.document().undoStack()->index();
    const QPoint point =
        inside ? graph.canvasRect().center() : graph.canvasRect().topLeft() - QPoint(4, 4);
    QVERIFY(m_fixture.wheel(graph, point, QPoint(0, 120 * delta)));
    if (!inside) {
        QCOMPARE(m_fixture.document().undoStack()->index(), index);
        QCOMPARE(editor.bendRange(), initialRange);
        return;
    }
    QCOMPARE(m_fixture.document().undoStack()->index(), index + 1);
    QCOMPARE(editor.bendRange(), initialRange + delta);
    QVERIFY(
        editor.description().contains(QStringLiteral("%1 semitones").arg(initialRange + delta)));
    QVERIFY(m_fixture.hasLanePoint(0x14, m_fixture.note().tick, initialRange + delta));
    QVERIFY(m_fixture.hasLanePoint(0x14, m_fixture.endTick(), initialRange));
}

void PitchBendEditingTest::controllerInputsAdvertiseScrubCursor()
{
    songview::PitchBendEditor *editorResult = popup();
    QVERIFY(editorResult);
    songview::PitchBendEditor &editor = *editorResult;
    QQuickItem *bend = m_fixture.item(QStringLiteral("bendRangeSpin"));
    QQuickItem *lfo = m_fixture.item(QStringLiteral("lfoSpeedSpin"));
    QQuickWindow *view = editor.view();
    QVERIFY(bend);
    QVERIFY(lfo);
    QVERIFY(view);
    QVERIFY(QTest::qWaitFor([view] { return view->isVisible() && view->isExposed(); }));
    QVERIFY(hover(*view, *bend));
    QTRY_COMPARE(view->cursor().shape(), Qt::SizeVerCursor);
    QVERIFY(hover(*view, *lfo));
    QTRY_COMPARE(view->cursor().shape(), Qt::SizeVerCursor);
}

void PitchBendEditingTest::bendRangeScrubWritesNoteBoundedCC14()
{
    songview::PitchBendEditor *editorResult = popup();
    QVERIFY(editorResult);
    songview::PitchBendEditor &editor = *editorResult;
    QQuickItem *bend = m_fixture.item(QStringLiteral("bendRangeSpin"));
    QVERIFY(bend);
    const int before = editor.bendRange();
    const int endValue = m_fixture.effectiveLaneValue(0x14, m_fixture.endTick(), 2);
    const int index = m_fixture.document().undoStack()->index();
    QVERIFY(m_fixture.scrub(*bend, 1));
    QCOMPARE(m_fixture.document().undoStack()->index(), index + 1);
    QCOMPARE(editor.bendRange(), before + 1);
    QVERIFY(m_fixture.hasLanePoint(0x14, m_fixture.note().tick, before + 1));
    QVERIFY(m_fixture.hasLanePoint(0x14, m_fixture.endTick(), endValue));
    QVERIFY(editor.isOpen());
}

void PitchBendEditingTest::lfoSpeedShiftScrubWritesNoteBoundedCC15()
{
    songview::PitchBendEditor *editorResult = popup();
    QVERIFY(editorResult);
    songview::PitchBendEditor &editor = *editorResult;
    QQuickItem *lfo = m_fixture.item(QStringLiteral("lfoSpeedSpin"));
    QVERIFY(lfo);
    const int before = editor.lfoSpeed();
    const int endValue = m_fixture.effectiveLaneValue(0x15, m_fixture.endTick(), 22);
    const int index = m_fixture.document().undoStack()->index();
    QVERIFY(m_fixture.scrub(*lfo, 1, Qt::ShiftModifier));
    QCOMPARE(m_fixture.document().undoStack()->index(), index + 1);
    QCOMPARE(editor.lfoSpeed(), before + 1);
    QVERIFY(m_fixture.hasLanePoint(0x15, m_fixture.note().tick, before + 1));
    QVERIFY(m_fixture.hasLanePoint(0x15, m_fixture.endTick(), endValue));
    QVERIFY(editor.isOpen());
}

void PitchBendEditingTest::controllerStationaryClickFocusesAndSelectsText()
{
    songview::PitchBendEditor *editorResult = popup();
    QVERIFY(editorResult);
    songview::PitchBendEditor &editor = *editorResult;
    QQuickItem *input = m_fixture.item(QStringLiteral("lfoSpeedInput"));
    QVERIFY(input);
    const QByteArray before = m_fixture.smf();
    const int index = m_fixture.document().undoStack()->index();
    const int lfo = editor.lfoSpeed();
    QVERIFY(m_fixture.click(*input));
    QCoreApplication::processEvents();
    QCOMPARE(m_fixture.document().undoStack()->index(), index);
    QCOMPARE(m_fixture.smf(), before);
    QCOMPARE(editor.lfoSpeed(), lfo);
    QCOMPARE(editor.view()->activeFocusItem(), input);
    QVERIFY(!input->property("selectedText").toString().isEmpty());
}

void PitchBendEditingTest::controllerUndoChainingPreservesPopupSession()
{
    songview::PitchBendEditor *editorResult = popup();
    QVERIFY(editorResult);
    songview::PitchBendEditor &editor = *editorResult;
    QQuickItem *bend = m_fixture.item(QStringLiteral("bendRangeSpin"));
    QQuickItem *lfo = m_fixture.item(QStringLiteral("lfoSpeedSpin"));
    QVERIFY(bend);
    QVERIFY(lfo);
    const QByteArray baseline = m_fixture.smf();
    const int index = m_fixture.document().undoStack()->index();
    QVERIFY(m_fixture.scrub(*bend, 1));
    const QByteArray afterBend = m_fixture.smf();
    QVERIFY(m_fixture.scrub(*lfo, 1, Qt::ShiftModifier));
    QVERIFY(m_fixture.sendUndo());
    QCOMPARE(m_fixture.document().undoStack()->index(), index + 1);
    QCOMPARE(m_fixture.smf(), afterBend);
    QVERIFY(editor.isOpen());
    QVERIFY(m_fixture.sendUndo());
    QCOMPARE(m_fixture.document().undoStack()->index(), index);
    QCOMPARE(m_fixture.smf(), baseline);
    QVERIFY(editor.isOpen());
}

void PitchBendEditingTest::resetButtonZeroesCurveAndRestoresEndValue()
{
    songview::PitchBendEditor *editorResult = popup();
    QVERIFY(editorResult);
    songview::PitchBendEditor &editor = *editorResult;
    songview::PitchBendGraph *graph = pitchGraph();
    QVERIFY(graph);
    QVERIFY(drawPitchCurve(*graph));
    const int endValue = m_fixture.effectiveLaneValue(DOC_CC_BEND, m_fixture.endTick(), 0);
    const QByteArray beforeReset = m_fixture.smf();
    const int index = m_fixture.document().undoStack()->index();
    QQuickItem *reset = m_fixture.item(QStringLiteral("pitchBendReset"));
    QVERIFY(reset);
    QVERIFY(m_fixture.click(*reset));
    QCOMPARE(m_fixture.document().undoStack()->index(), index + 1);
    QVERIFY(spanIsDefault(m_fixture, DOC_CC_BEND, 0));
    QVERIFY(m_fixture.hasLanePoint(DOC_CC_BEND, m_fixture.endTick(), endValue));
    QVERIFY(editor.isOpen());
    m_fixture.document().undoStack()->undo();
    QCOMPARE(m_fixture.document().undoStack()->index(), index);
    QCOMPARE(m_fixture.smf(), beforeReset);
    QVERIFY(!spanIsDefault(m_fixture, DOC_CC_BEND, 0));
}

void PitchBendEditingTest::spaceAuditionsNoteFromStartTick()
{
    songview::PitchBendEditor *editorResult = popup();
    QVERIFY(editorResult);
    songview::PitchBendEditor &editor = *editorResult;
    const QByteArray before = m_fixture.smf();
    const int index = m_fixture.document().undoStack()->index();
    QSignalSpy audition(&m_fixture.view(), &SongView::playPauseFromRequested);
    QVERIFY(audition.isValid());
    QKeyEvent overrideEvent(QEvent::ShortcutOverride, Qt::Key_Space, Qt::NoModifier);
    QCoreApplication::sendEvent(editor.view(), &overrideEvent);
    QVERIFY(overrideEvent.isAccepted());
    QTest::keyClick(editor.view(), Qt::Key_Space);
    QCOMPARE(audition.count(), 1);
    QCOMPARE(audition.front().front().toULongLong(), m_fixture.note().tick);
    QCOMPARE(m_fixture.document().undoStack()->index(), index);
    QCOMPARE(m_fixture.smf(), before);
    QVERIFY(editor.isOpen());
}

void PitchBendEditingTest::soloAndMuteKeyArbitration()
{
    songview::PitchBendEditor *editorResult = popup();
    QVERIFY(editorResult);
    songview::PitchBendEditor &editor = *editorResult;
    const QByteArray before = m_fixture.smf();
    const int index = m_fixture.document().undoStack()->index();
    const uint32_t mute = m_fixture.view().muteMask();
    const uint32_t solo = m_fixture.view().soloMask();
    QTest::keyClick(editor.view(), Qt::Key_M);
    QCOMPARE(m_fixture.view().muteMask(), mute);
    QTest::keyClick(editor.view(), Qt::Key_S);
    QCOMPARE(m_fixture.view().soloMask(), solo ^ uint32_t{1});
    QTest::keyClick(editor.view(), Qt::Key_S);
    QCOMPARE(m_fixture.view().soloMask(), solo);
    QCOMPARE(m_fixture.document().undoStack()->index(), index);
    QCOMPARE(m_fixture.smf(), before);
}
