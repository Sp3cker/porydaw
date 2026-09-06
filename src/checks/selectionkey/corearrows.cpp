#include "checks/selectionkey/tst_selectionkeycore.h"

#include "checks/support/eventsynth.h"

#include <QGuiApplication>
#include <QQuickWindow>
#include <QStyleHints>
#include <QtTest>

#include <array>
#include <optional>
#include <vector>

using selectionkey::ClickTarget;
using selectionkey::describeNoteIds;
using selectionkey::describePoint;
using selectionkey::describeRect;
using selectionkey::drawerPageForBand;

namespace {

enum class CoreClick {
    AutomationLaneGap,
    SelectedVelocityStemDrag,
    PlainRuler,
    BandCenter,
};

struct BandProbe {
    songview::TimelineBand band;
    const char *item;
    const char *label;
    bool clickTakesFocus;
    CoreClick click;
};

constexpr std::array<BandProbe, 5> kCoreBands{{
    {songview::TimelineBand::Automation, "timelineAutomationInput", "automation", true,
     CoreClick::AutomationLaneGap},
    {songview::TimelineBand::Velocity, "timelineVelocityInput", "velocity", true,
     CoreClick::SelectedVelocityStemDrag},
    {songview::TimelineBand::VoiceChanges, "timelineVoiceChangesInput", "voice changes", true,
     CoreClick::BandCenter},
    {songview::TimelineBand::Ruler, "timelineRulerInput", "ruler", false, CoreClick::PlainRuler},
    {songview::TimelineBand::OtherEvents, "timelineOtherEventsInput", "other events", false,
     CoreClick::BandCenter},
}};

struct ArrowProbe {
    Qt::Key key;
    const char *label;
};

constexpr std::array<ArrowProbe, 4> kCoreArrows{{
    {Qt::Key_Up, "Up"},
    {Qt::Key_Down, "Down"},
    {Qt::Key_Right, "Right"},
    {Qt::Key_Left, "Left"},
}};

} // namespace

void SelectionKeyCoreTest::incidentalBandClickPreservesSelection_data()
{
    QTest::addColumn<int>("bandIndex");
    QTest::addColumn<int>("click");
    for (std::size_t index = 0; index < kCoreBands.size(); ++index) {
        QTest::newRow(
            qPrintable(QStringLiteral("%1 band").arg(QLatin1String(kCoreBands[index].label))))
            << int(index) << int(kCoreBands[index].click);
    }
}

void SelectionKeyCoreTest::incidentalBandClickPreservesSelection()
{
    QFETCH(int, bandIndex);
    QFETCH(int, click);
    const BandProbe &probe = kCoreBands[std::size_t(bandIndex)];
    const auto kind = CoreClick(click);

    // Automation uses an empty visible lane click. Velocity exercises the
    // intended selected-stem contract with a real threshold-crossing drag:
    // a press/release without relative movement intentionally becomes a
    // singleton selection. The remaining bands stage their plain production
    // clicks; every row proves the incidental click preserves the eligible
    // selection the keyboard contract will act on.
    m_fixture = createFixture(std::nullopt);
    QVERIFY2(m_fixture,
             qPrintable(QStringLiteral("could not create the cross-band note fixture: %1")
                            .arg(m_lastFixtureError)));
    QQuickWindow *const quick = m_fixture->window();
    SongView &songView = m_fixture->view();
    const std::vector<NoteId> selection{m_fixture->notes()[0], m_fixture->notes()[1]};

    m_fixture->configureDrawerSurface(drawerPageForBand(probe.band));
    songview::TimelineInputItem *const band = m_fixture->input(probe.item);
    QVERIFY2(band && QTest::qWaitFor([band, quick] {
                 return !band->bounds().isEmpty() && band->window() == quick;
             }),
             "Quick band input is unavailable");

    // The click begins from the same eligible note selection every row uses.
    songView.selectionModel().setNoteSelection(selection);
    selectionkey::settle();

    std::optional<QPoint> point;
    QString clickDiagnostics;
    switch (kind) {
    case CoreClick::AutomationLaneGap: {
        const ClickTarget target = m_fixture->emptyAutomationLanePoint();
        point = target.point;
        clickDiagnostics = target.diagnostics;
        break;
    }
    case CoreClick::SelectedVelocityStemDrag: {
        const ClickTarget target = m_fixture->selectedVelocityStemPoint();
        point = target.point;
        clickDiagnostics = target.diagnostics;
        break;
    }
    case CoreClick::PlainRuler:
        point = m_fixture->plainRulerPoint(band);
        break;
    case CoreClick::BandCenter:
        point = band->mapToScene(band->bounds().center()).toPoint();
        break;
    }
    if (clickDiagnostics.isEmpty()) {
        clickDiagnostics = QStringLiteral("input-bounds=%1; chosen-window=%2")
                               .arg(describeRect(band->bounds()))
                               .arg(point ? describePoint(*point) : QStringLiteral("unavailable"));
    }
    QVERIFY2(point.has_value(), qPrintable(QStringLiteral("%1 band click point is unavailable: %2")
                                               .arg(QLatin1String(probe.label), clickDiagnostics)));

    if (kind == CoreClick::SelectedVelocityStemDrag) {
        const QPointF pressPoint(*point);
        const QPointF inputPoint = band->mapFromScene(pressPoint);
        const qreal dragY =
            qMin(band->bounds().bottom() - 2.0,
                 inputPoint.y() + QGuiApplication::styleHints()->startDragDistance() + 4.0);
        const QPoint dragPoint = band->mapToScene(QPointF(inputPoint.x(), dragY)).toPoint();
        bool delivered = checks::events::primeMouseMove(*quick, *band, *point);
        if (delivered) {
            stageMousePress(Qt::LeftButton, *point);
            stageMouseMove(dragPoint);
            delivered = QTest::qWaitFor([&] {
                return songView.userGestureActive() &&
                       songView.selectionModel().noteSelection() == selection;
            });
            stageMouseRelease(Qt::LeftButton, dragPoint);
            selectionkey::settle();
        }
        QVERIFY2(delivered,
                 qPrintable(QStringLiteral("%1 band selected velocity-stem drag did not activate "
                                           "and retain the group: %2")
                                .arg(QLatin1String(probe.label), clickDiagnostics)));
    } else {
        QVERIFY2(selectionkey::clickTimelineInput(quick, band, *point),
                 qPrintable(QStringLiteral("%1 band click did not reach its target band: %2")
                                .arg(QLatin1String(probe.label), clickDiagnostics)));
    }

    // Ruler and other-events clicks intentionally do not focus.
    if (probe.clickTakesFocus)
        QVERIFY2(band->hasActiveFocus(), "Quick band input did not focus its band");
    if (kind == CoreClick::AutomationLaneGap) {
        QVERIFY2(!songView.selectionModel().timeSelection().active(),
                 "the incidental automation click made a replacement range");
    }
    QVERIFY2(songView.selectionModel().noteSelection() == selection,
             qPrintable(QStringLiteral("%1 band input disturbed the eligible selection: "
                                       "actual=%2 intended=%3 %4")
                            .arg(QLatin1String(probe.label),
                                 describeNoteIds(songView.selectionModel().noteSelection()),
                                 describeNoteIds(selection), clickDiagnostics)));
}

void SelectionKeyCoreTest::arrowsMoveSelectedNotesAcrossBands_data()
{
    QTest::addColumn<int>("bandIndex");
    QTest::addColumn<int>("arrow");
    QTest::addColumn<QString>("direction");
    for (std::size_t index = 0; index < kCoreBands.size(); ++index) {
        for (const ArrowProbe &arrow : kCoreArrows) {
            QTest::newRow(qPrintable(QStringLiteral("%1: %2").arg(
                QLatin1String(kCoreBands[index].label), QLatin1String(arrow.label))))
                << int(index) << int(arrow.key) << QString::fromLatin1(arrow.label);
        }
    }
}

void SelectionKeyCoreTest::arrowsMoveSelectedNotesAcrossBands()
{
    QFETCH(int, bandIndex);
    QFETCH(int, arrow);
    QFETCH(QString, direction);
    const BandProbe &probe = kCoreBands[std::size_t(bandIndex)];
    const auto key = Qt::Key(arrow);

    m_fixture = createFixture(std::nullopt);
    QVERIFY2(m_fixture,
             qPrintable(QStringLiteral("could not create the cross-band note fixture: %1")
                            .arg(m_lastFixtureError)));
    QQuickWindow *const quick = m_fixture->window();
    SongView &songView = m_fixture->view();
    const std::vector<NoteId> selection{m_fixture->notes()[0], m_fixture->notes()[1]};

    m_fixture->configureDrawerSurface(drawerPageForBand(probe.band));
    songview::TimelineInputItem *const band = m_fixture->input(probe.item);
    QVERIFY2(band && QTest::qWaitFor([band, quick] {
                 return !band->bounds().isEmpty() && band->window() == quick;
             }),
             "Quick band input is unavailable");

    // Focus is explicit for every band's keyboard contract rather than
    // accidentally inherited from an incidental click.
    QVERIFY2(m_fixture->focusBand(probe.band),
             qPrintable(QStringLiteral("%1 band could not stage focus for arrows")
                            .arg(QLatin1String(probe.label))));
    songView.selectionModel().setNoteSelection(selection);
    selectionkey::settle();

    const auto before = m_fixture->snapshotNotes();
    QVERIFY2(
        before.has_value(),
        qPrintable(QStringLiteral("%1 band: a cross-band fixture note vanished before an arrow")
                       .arg(QLatin1String(probe.label))));

    // Expected per-note deltas: only the two selected notes move. Horizontal
    // arrows snap one grid step from the first selected note's tick.
    const int64_t tick = int64_t(before->at(0).tick);
    const int64_t tickDelta =
        key == Qt::Key_Right  ? int64_t(songView.grid().snapTickUp(double(tick) + 1.0)) - tick
        : key == Qt::Key_Left ? int64_t(songView.grid().snapTickDown(double(tick) - 1.0)) - tick
                              : 0;
    const int keyDelta = key == Qt::Key_Up ? 1 : key == Qt::Key_Down ? -1 : 0;

    QVERIFY2(selectionkey::deliverKey(quick, key),
             qPrintable(QStringLiteral("%1 band %2 arrow: Quick window did not accept the key")
                            .arg(QLatin1String(probe.label), direction)));

    for (std::size_t index = 0; index < before->size(); ++index) {
        const DocNote &noteBefore = before->at(index);
        const bool isSelected = index < 2;
        const int expectedKey = int(noteBefore.key) + (isSelected ? keyDelta : 0);
        const uint64_t expectedTick =
            uint64_t(int64_t(noteBefore.tick) + (isSelected ? tickDelta : 0));
        const auto actual = m_fixture->note(index);
        QVERIFY2(
            actual && int(actual->key) == expectedKey && actual->tick == expectedTick,
            qPrintable(
                QStringLiteral("%1 band %2 arrow note[%3] (%4): "
                               "actual=(present=%5,key=%6,tick=%7) "
                               "expected=(key=%8,tick=%9)")
                    .arg(QLatin1String(probe.label), direction, QString::number(index),
                         isSelected ? QStringLiteral("selected") : QStringLiteral("unselected"),
                         actual.has_value() ? QStringLiteral("1") : QStringLiteral("0"),
                         actual ? QString::number(int(actual->key)) : QStringLiteral("-1"),
                         actual ? QString::number(actual->tick) : QStringLiteral("0"),
                         QString::number(expectedKey), QString::number(expectedTick))));
    }
    QVERIFY2(songView.selectionModel().noteSelection() == selection,
             qPrintable(QStringLiteral("%1 band %2 arrow disturbed the selection: actual=%3 "
                                       "intended=%4")
                            .arg(QLatin1String(probe.label), direction,
                                 describeNoteIds(songView.selectionModel().noteSelection()),
                                 describeNoteIds(selection))));
}

void SelectionKeyCoreTest::mergeableMoveHistorySupportsUndoRedoRoundTrip()
{
    // The arrows route through the production mergeable-move history. With
    // per-case isolation the history is pristine, so the undo proof runs
    // unconditionally; the old band loop gated it on every band's arrows
    // having been clean because a dirty history could have reverted an
    // unrelated leftover command.
    m_fixture = createFixture(std::nullopt);
    QVERIFY2(m_fixture,
             qPrintable(QStringLiteral("could not create the cross-band note fixture: %1")
                            .arg(m_lastFixtureError)));
    QQuickWindow *const quick = m_fixture->window();
    SongView &songView = m_fixture->view();
    const std::vector<NoteId> selection{m_fixture->notes()[0], m_fixture->notes()[1]};

    QVERIFY2(m_fixture->focusBand(songview::TimelineBand::OtherEvents),
             "could not stage band focus for the undo proof");
    songView.selectionModel().setNoteSelection(selection);
    selectionkey::settle();
    const auto beforeUndo = m_fixture->snapshotNotes();
    QVERIFY2(beforeUndo.has_value(), "the fixture notes vanished before the undo proof");

    // One transposing press proves increment/undo/redo preservation end to
    // end; the closing Down press cancels it through the same history.
    const auto expectShift = [this, &beforeUndo](const char *stage, int keyShift,
                                                 int64_t tickShift) {
        for (std::size_t index = 0; index < beforeUndo->size(); ++index) {
            const DocNote &noteBefore = beforeUndo->at(index);
            const int expectedKey = int(noteBefore.key) + (index < 2 ? keyShift : 0);
            const uint64_t expectedTick =
                uint64_t(int64_t(noteBefore.tick) + (index < 2 ? tickShift : 0));
            const auto actual = m_fixture->note(index);
            QVERIFY2(
                actual && int(actual->key) == expectedKey && actual->tick == expectedTick,
                qPrintable(
                    QStringLiteral("undo proof %1 note[%2] (%3): "
                                   "actual=(present=%4,key=%5,tick=%6) "
                                   "expected=(key=%7,tick=%8)")
                        .arg(QLatin1String(stage), QString::number(index),
                             index < 2 ? QStringLiteral("selected") : QStringLiteral("unselected"),
                             actual.has_value() ? QStringLiteral("1") : QStringLiteral("0"),
                             actual ? QString::number(int(actual->key)) : QStringLiteral("-1"),
                             actual ? QString::number(actual->tick) : QStringLiteral("0"),
                             QString::number(expectedKey), QString::number(expectedTick))));
        }
    };

    QVERIFY2(selectionkey::deliverKey(quick, Qt::Key_Up),
             "Quick window did not accept the undo-proof key");
    expectShift("Up", +1, 0);
    m_fixture->document().undoStack()->undo();
    expectShift("Undo", 0, 0);
    m_fixture->document().undoStack()->redo();
    expectShift("Redo", +1, 0);
    QVERIFY2(selectionkey::deliverKey(quick, Qt::Key_Down),
             "Quick window did not accept the undo-proof key");
    expectShift("Down", 0, 0);
}
