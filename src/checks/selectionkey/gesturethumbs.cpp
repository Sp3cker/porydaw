// Scrollbar-thumb guard matrix for the selection-keyboard-routing Qt Test.
// The roll vertical thumb is driven end to end: the live native MouseArea grab
// blocks the shared Delete, Escape releases the grab, held-button movement
// stays inert, and a physically released then newly pressed drag works
// before the same binding deletes again.

#include "checks/selectionkey/gesturecheck.h"

#include <QGuiApplication>
#include <QPoint>
#include <QPointF>
#include <QQuickItem>
#include <QStyleHints>
#include <QtMath>
#include <QtTest>

void SelectionKeyGestureTest::scrollbarThumbGuardsSharedCommands_data()
{
    QTest::addColumn<QString>("barName");
    QTest::addColumn<QString>("thumbName");
    QTest::addColumn<QString>("inputName");
    QTest::addColumn<int>("band");
    QTest::addColumn<int>("victimIndex");

    QTest::newRow("roll scrollbar")
        << QStringLiteral("timelineRollScrollBar") << QStringLiteral("timelineRollScrollThumb")
        << QStringLiteral("timelineRollInput") << int(songview::TimelineBand::Roll) << 0;
}

void SelectionKeyGestureTest::scrollbarThumbGuardsSharedCommands()
{
    const auto deleteKey = selectionkey::firstBinding(QStringLiteral("roll.delete"));
    QVERIFY2(deleteKey.has_value(), "roll.delete has no single-key binding");
    if (!stageWorld("scrollbar-gesture", EditorDrawerPage::Automations,
                    kScrollbarAutomationSectionHeight))
        return;
    QVERIFY2(!mQuickWindow.isNull(), "scrollbar-gesture delivery surface is unavailable");

    QFETCH(QString, barName);
    QFETCH(QString, thumbName);
    QFETCH(QString, inputName);
    QFETCH(int, band);
    QFETCH(int, victimIndex);
    const auto scrollValue = [&]() -> qreal { return view().camera().scrollY(); };

    songview::TimelineInputItem *const bandInput =
        selectionkey::rigInput(*mWorld, inputName.toUtf8().constData());
    QVERIFY2(focusPointerSurface(bandInput, songview::TimelineBand(band)),
             "owning timeline band did not have live Quick and native focus");
    QPointer<QQuickItem> root;
    QPointer<QQuickItem> bar;
    QPointer<QQuickItem> thumb;
    const auto resolveControls = [&] {
        root = mWorld->rig->quickRoot();
        bar = root ? root->findChild<QQuickItem *>(barName) : nullptr;
        thumb = root ? root->findChild<QQuickItem *>(thumbName) : nullptr;
        return bar && thumb;
    };
    QVERIFY2(resolveControls() && bar->isVisible() && thumb->isVisible() &&
                 !thumb->boundingRect().isEmpty() && bar->property("thumbTravel").toReal() > 0.0,
             "registered scrollbar thumb was not draggable in the shown window");

    const NoteId victim = mWorld->notes[victimIndex];
    view().selectionModel().setNoteSelection({victim});
    const QByteArray beforeDrag = document().smf().write();
    const uint64_t revisionBefore = document().revision();
    const int undoDepthBefore = document().undoStack()->count();
    const qreal scrollBefore = scrollValue();
    const QPointF pressPosition = thumb->mapToScene(thumb->boundingRect().center());
    const qreal activation = QGuiApplication::styleHints()->startDragDistance() + 1.0;
    const QPoint activationPosition = (pressPosition + QPointF(1.0, activation)).toPoint();
    const QPoint dragPosition = activationPosition + QPoint(0, 1);
    mouseMove(pressPosition.toPoint());
    mousePress(Qt::LeftButton, pressPosition.toPoint());
    mouseMove(activationPosition);
    QTRY_VERIFY2(view().userGestureActive(), "thumb drag did not become a live gesture");
    // The smoothed native MouseArea drag establishes its threshold baseline
    // on this move. A distinct move after activation is the first one that
    // must displace the proxy and request a model value.
    mouseMove(dragPosition);
    QTRY_VERIFY2(scrollValue() > scrollBefore, "thumb drag did not move its owning scroll model");
    selectionkey::deliverKey(window(), deleteKey->key(), deleteKey->keyboardModifiers());
    QVERIFY2(document().smf().write() == beforeDrag && noteSelectionIs({victim}) &&
                 document().revision() == revisionBefore &&
                 document().undoStack()->count() == undoDepthBefore,
             "the registered live gesture did not block the shared Delete");
    selectionkey::deliverKey(window(), Qt::Key_Escape);
    QVERIFY2(!view().userGestureActive(),
             "Escape did not cancel the registered thumb drag by releasing its "
             "native mouse grab");
    const qreal scrollAfterCancel = scrollValue();
    const QPoint heldMove = dragPosition + QPoint(0, qCeil(activation) + 4);
    mouseMove(heldMove);
    QVERIFY2(scrollValue() == scrollAfterCancel,
             "movement with the button held after Escape changed the scroll model");
    mouseRelease(Qt::LeftButton, heldMove);
    QVERIFY2(!view().userGestureActive() && scrollValue() == scrollAfterCancel,
             "physical release after cancellation changed the scroll model");

    QVERIFY2(resolveControls() && bar->isVisible() && thumb->isVisible() &&
                 !thumb->boundingRect().isEmpty(),
             "registered scrollbar controls disappeared before the fresh drag");
    const qreal maximum = bar->property("maximum").toReal();
    const int restartDirection = scrollAfterCancel < maximum ? 1 : -1;
    const QPointF restartPress = thumb->mapToScene(thumb->boundingRect().center());
    const QPoint restartActivation =
        (restartPress + QPointF(1.0, restartDirection * activation)).toPoint();
    const QPoint restartDrag = restartActivation + QPoint(0, restartDirection);
    mouseMove(restartPress.toPoint());
    mousePress(Qt::LeftButton, restartPress.toPoint());
    mouseMove(restartActivation);
    mouseMove(restartDrag);
    QTRY_VERIFY2(view().userGestureActive() && scrollValue() != scrollAfterCancel,
                 "a fresh press after physical release did not start a new thumb drag");
    mouseRelease(Qt::LeftButton, restartDrag);
    QVERIFY2(!view().userGestureActive() && scrollValue() != scrollAfterCancel,
             "the fresh thumb drag did not end on physical release");
    selectionkey::deliverKey(window(), deleteKey->key(), deleteKey->keyboardModifiers());
    QVERIFY2(!selectionkey::noteExists(document(), victim) &&
                 document().smf().write() != beforeDrag,
             "the shared Delete did not resume after the thumb drag ended");
}
