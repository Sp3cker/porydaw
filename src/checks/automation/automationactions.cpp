#include "checks/automation/tst_automationediting.h"

#include <QAction>
#include <QEvent>
#include <QGuiApplication>

#include <QKeySequence>
#include <QLineEdit>
#include <QtTest>

#include "core/miditimeline.h"

#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/nodelane/hover.h"
#include "ui/songview.h"

namespace {

constexpr uint8_t kPanController = 10;
constexpr uint8_t kLfoController = 21;

class ScopedShortcut final
{
  public:
    explicit ScopedShortcut(QAction &action) : m_action(action), m_previous(action.shortcut()) {}
    ~ScopedShortcut() { m_action.setShortcut(m_previous); }

    ScopedShortcut(const ScopedShortcut &) = delete;
    ScopedShortcut &operator=(const ScopedShortcut &) = delete;

  private:
    QAction &m_action;
    QKeySequence m_previous;
};

QKeyCombination singleShortcut(const QAction &action)
{
    const QKeySequence shortcut = action.shortcut();
    return shortcut.count() == 1 ? shortcut[0] : QKeyCombination{};
}

} // namespace

void AutomationEditingTest::actionShortcutLatching()
{
    QAction *const action = pencilModeAction();
    QVERIFY(action);
    const QKeyCombination shortcut = singleShortcut(*action);
    QVERIFY(shortcut.key() != Qt::Key_unknown);

    action->setChecked(false);
    keyPress(shortcut.key(), shortcut.keyboardModifiers());
    QVERIFY(action->isChecked());
    keyRelease(shortcut.key(), shortcut.keyboardModifiers());
    QVERIFY(action->isChecked());

    keyPress(shortcut.key(), shortcut.keyboardModifiers());
    QVERIFY(!action->isChecked());
    keyRelease(shortcut.key(), shortcut.keyboardModifiers());
    QVERIFY(!action->isChecked());
}

void AutomationEditingTest::actionTextInputImmunity()
{
    QAction *const action = pencilModeAction();
    QVERIFY(action);
    const QKeyCombination shortcut = singleShortcut(*action);
    QVERIFY(shortcut.key() != Qt::Key_unknown);

    action->setChecked(false);
    QLineEdit editor(&tab());
    editor.show();
    editor.setFocus(Qt::OtherFocusReason);
    QTRY_VERIFY(editor.hasFocus());

    QTest::keyClick(&editor, shortcut.key(), shortcut.keyboardModifiers());

    QCOMPARE(editor.text(), QStringLiteral("b"));
    QVERIFY(!action->isChecked());
}

void AutomationEditingTest::actionRepeatImmunity()
{
    QAction *const action = pencilModeAction();
    QVERIFY(action);
    const QKeyCombination shortcut = singleShortcut(*action);
    QVERIFY(shortcut.key() != Qt::Key_unknown);

    action->setChecked(false);
    keyPress(shortcut.key(), shortcut.keyboardModifiers());
    QVERIFY(action->isChecked());

    keyEvent(QEvent::KeyPress, shortcut.key(), shortcut.keyboardModifiers(), true);
    keyEvent(QEvent::KeyRelease, shortcut.key(), shortcut.keyboardModifiers(), true);
    QVERIFY(action->isChecked());

    keyRelease(shortcut.key(), shortcut.keyboardModifiers());
    QVERIFY(action->isChecked());
}

void AutomationEditingTest::actionCustomBinding()
{
    QAction *const action = pencilModeAction();
    QVERIFY(action);
    const ScopedShortcut restore(*action);
    const QKeyCombination customShortcut(Qt::ControlModifier, Qt::Key_P);
    action->setShortcut(QKeySequence(customShortcut));
    action->setChecked(false);

    keyClick(customShortcut.key(), customShortcut.keyboardModifiers());
    QVERIFY(action->isChecked());
    keyClick(customShortcut.key(), customShortcut.keyboardModifiers());
    QVERIFY(!action->isChecked());
}

void AutomationEditingTest::actionHeldKeyGestures()
{
    QAction *const action = pencilModeAction();
    QVERIFY(action);
    const QKeyCombination shortcut = singleShortcut(*action);
    QVERIFY(shortcut.key() != Qt::Key_unknown);

    action->setChecked(false);
    keyPress(shortcut.key(), shortcut.keyboardModifiers());
    QVERIFY(action->isChecked());
    QTest::qWait(510);
    keyRelease(shortcut.key(), shortcut.keyboardModifiers());
    QVERIFY(action->isChecked());

    action->setChecked(false);
    keyPress(shortcut.key(), shortcut.keyboardModifiers());
    QVERIFY(action->isChecked());
    const LaneHandle pan = findRow({EditorAutomationRowKind::ControlChange, 0, kPanController});
    QVERIFY(pan.valid());
    const QPointF start = inputPoint(pan, 144, 64);
    QVERIFY(automationInput().bounds().contains(
        QPointF(start.x(), start.y() - page().verticalScroll())));
    mousePress(Qt::LeftButton, automationWindowPoint(start));
    mouseRelease(Qt::LeftButton, automationWindowPoint(start));
    keyRelease(shortcut.key(), shortcut.keyboardModifiers());
    QVERIFY(action->isChecked());
}

void AutomationEditingTest::projectionPartialCell()
{
    const AutomationProjection projection(AutomationGeometry::resolve(), &page());
    const MidiTimeline *const timeline = tab().view().timeline();
    QVERIFY(timeline);

    const AutomationGridCell finalCell = projection.snapCellAt(double(timeline->lengthTicks));
    QVERIFY(finalCell.tickBegin < finalCell.tickEnd);
    QCOMPARE(finalCell.tickEnd, timeline->lengthTicks);
}

void AutomationEditingTest::projectionValueBounds()
{
    const EditorAutomationRowId panRow{EditorAutomationRowKind::ControlChange, 0, kPanController};
    const EditorAutomationRowId lfoRow{EditorAutomationRowKind::ControlChange, 0, kLfoController};
    tab().document().addLanePoint(0, kLfoController, 0, 0);
    QTRY_VERIFY(findRow(panRow).valid());
    QTRY_VERIFY(findRow(lfoRow).valid());
    const LaneHandle pan = findRow(panRow);
    const LaneHandle lfo = findRow(lfoRow);
    const AutomationGeometry geometry = AutomationGeometry::resolve();
    for (const LaneHandle lane : {pan, lfo}) {
        const QRect body = laneBody(lane);
        QVERIFY(!body.isEmpty());
        const QPointF minimum = inputPoint(lane, 0, 0);
        const QPointF maximum = inputPoint(lane, 0, 127);
        QCOMPARE(qRound(AutomationProjection::valueAtY(body, geometry, 0, 127, minimum.y())), 0);
        QCOMPARE(qRound(AutomationProjection::valueAtY(body, geometry, 0, 127, maximum.y())), 127);
    }
}

void AutomationEditingTest::projectionCanvasOrigin()
{
    const auto &rows = page().canvas()->rows();
    QVERIFY(!rows.empty());
    const LaneHandle firstRow{1};
    const QRect body = laneBody(firstRow);
    QVERIFY(!body.isEmpty());
    QCOMPARE(body.top(), 0);
    QVERIFY(rows.front().id.kind == EditorAutomationRowKind::ControlChange);

    const QPointF input = inputPoint(firstRow, 48, 64);
    QVERIFY(input.y() >= qreal(body.top()));
    QVERIFY(input.y() < qreal(body.bottom()));
    QCOMPARE(qRound(AutomationProjection::valueAtY(body, AutomationGeometry::resolve(), 0, 127,
                                                   input.y())),
             64);
}

void AutomationEditingTest::projectionInsertionTiming()
{
    const EditorAutomationRowId panRow{EditorAutomationRowKind::ControlChange, 0, kPanController};
    const LaneHandle pan = findRow(panRow);
    QVERIFY(pan.valid());
    const AutomationProjection projection(AutomationGeometry::resolve(), &page());
    const AutomationGridCell cell = projection.snapCellAt(24.0);
    const double intermediateTick =
        double(cell.tickBegin) + 0.4 * double(tab().view().grid().fineGridTicks());
    const QPointF input = inputPoint(pan, intermediateTick, 72);
    const double rawTick = projection.rawTickAt(input.x());
    const AutomationGridCell mappedCell = projection.snapCellAt(rawTick);
    const double caretTick = double(tab().view().grid().snapTick(rawTick, true));

    NodeLaneHoverState indicator(QGuiApplication::font());
    indicator.hover.lane = pan;
    indicator.hover.pos = input;

    QVERIFY(rawTick != double(mappedCell.tickBegin));
    QVERIFY(rawTick != caretTick);
    QCOMPARE(indicator.insertionTick(projection, true), double(mappedCell.tickBegin));
    QCOMPARE(indicator.insertionTick(projection, false), caretTick);
}

void AutomationEditingTest::pencilClickHalfOpenQuantization()
{
    const EditorAutomationRowId panRow{EditorAutomationRowKind::ControlChange, 0, kPanController};
    const LaneHandle pan = findRow(panRow);
    QVERIFY(pan.valid());
    setPencilMode(true);
    const AutomationProjection projection(AutomationGeometry::resolve(), &page());
    const AutomationGridCell cell = projection.snapCellAt(24.0);
    const double intermediateTick =
        double(cell.tickBegin) + 0.4 * double(tab().view().grid().fineGridTicks());
    const QPointF click = inputPoint(pan, intermediateTick, 72);
    const AutomationGridCell mappedCell = projection.snapCellAt(projection.rawTickAt(click.x()));

    mousePress(Qt::LeftButton, automationWindowPoint(click));
    mouseRelease(Qt::LeftButton, automationWindowPoint(click));

    DocLanePoint first;
    QTRY_VERIFY(tab().document().findLanePoint(0, kPanController, mappedCell.tickBegin, &first));
    QCOMPARE(first.value, 72);

    const AutomationGridCell following = projection.snapCellAt(double(mappedCell.tickEnd));
    QVERIFY(following.tickBegin < following.tickEnd);
    const QPointF boundary = inputPoint(pan, following.tickBegin, 96);
    mousePress(Qt::LeftButton, automationWindowPoint(boundary));
    mouseRelease(Qt::LeftButton, automationWindowPoint(boundary));

    DocLanePoint followingPoint;
    QTRY_VERIFY(
        tab().document().findLanePoint(0, kPanController, following.tickBegin, &followingPoint));
    QCOMPARE(first.value, 72);
    QCOMPARE(followingPoint.value, 96);
}
