#include "checks/selectionkey/tst_selectionkeycore.h"

#include "checks/support/eventsynth.h"

#include <QGuiApplication>
#include <QQuickWindow>
#include <QStyleHints>
#include <QtTest>

#include <algorithm>
#include <array>
#include <cstdint>
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

// The core fixture's eligible selection is the first two notes; every
// scenario reads that fact only through this constant so it cannot drift
// apart between the note-matrix verdicts.
constexpr std::size_t kSelectedNotes = 2;

// The known musical lattice of the core fixture song (mus_route101):
// 24-tick 4/4 with an explicit second signature at tick 12, so the shipped
// default editing grid — straight 1/16 — is a 6-tick cell anchored at that
// segment origin. The fixture anchor sits inside the origin-governed
// segment.
constexpr int64_t kResizeSegmentOrigin = 12;
constexpr int64_t kResizeCellTicks = 6;

// Preconditions for those constants (the pitchbend suite's "no grid query
// supplies it" pattern): the live editing state and the fixture song's
// signature map must still match the known shape the expectations are
// computed from. Returns an empty string on an exact match, else a
// diagnostic naming the first divergence.
QString resizeLatticeMismatch(const SongView &songView)
{
    const songview::Grid &grid = songView.grid();
    const songview::Grid::Segment atOrigin = grid.segmentAt(uint64_t(kResizeSegmentOrigin));
    if (songView.gridSelection() == songview::GridSelection::musical(16) &&
        grid.feel() == songview::GridFeel::Straight &&
        atOrigin.start == uint64_t(kResizeSegmentOrigin) && atOrigin.beatTicks == uint64_t{24} &&
        atOrigin.beatsPerBar == uint64_t{4})
        return {};
    return QStringLiteral("expected straight 1/16 over 24-tick 4/4 anchored at tick 12: "
                          "musical16=%1 straight=%2 start=%3 beat-ticks=%4 beats-per-bar=%5")
        .arg(songView.gridSelection() == songview::GridSelection::musical(16) ? 1 : 0)
        .arg(grid.feel() == songview::GridFeel::Straight ? 1 : 0)
        .arg(QString::number(atOrigin.start), QString::number(atOrigin.beatTicks),
             QString::number(atOrigin.beatsPerBar));
}

// Independent expected duration delta for one resize press: the known
// lattice constants and the document snapshot are the only inputs, so a
// wrong production boundary formula fails the exact expectation instead of
// being mirrored by it. The selected notes' furthest right edge (the
// production anchor) is reduced against the segment origin: an on-lattice
// edge steps one full cell in either direction, otherwise lengthening
// climbs to the next cell edge while shortening falls to the one below;
// the shortening delta is then clamped once so the shortest selected note
// keeps its one-tick floor.
int64_t resizeDurationDelta(const std::array<DocNote, 3> &before, bool longer)
{
    uint64_t anchor = 0;
    uint32_t shortest = UINT32_MAX;
    for (std::size_t index = 0; index < kSelectedNotes; ++index) {
        const DocNote &note = before[index];
        anchor = std::max(anchor, note.tick + note.duration);
        shortest = std::min(shortest, note.duration);
    }
    const int64_t remainder = (int64_t(anchor) - kResizeSegmentOrigin) % kResizeCellTicks;
    if (longer)
        return remainder == 0 ? kResizeCellTicks : kResizeCellTicks - remainder;
    const int64_t step = remainder == 0 ? kResizeCellTicks : remainder;
    return std::max(-step, 1 - int64_t(shortest));
}

// The expected document shape after one resize delivery: every fixture note
// is still present under its NoteId, unselected notes keep every field, and
// the selected notes share exactly one duration delta. Returns an empty
// string on an exact match, else a diagnostic naming the first divergence.
QString resizeDocumentMismatch(const selectionkey::CoreFixture &fixture,
                               const std::array<DocNote, 3> &before, int64_t selectedDurationDelta)
{
    for (std::size_t index = 0; index < before.size(); ++index) {
        const DocNote &noteBefore = before[index];
        const bool isSelected = index < kSelectedNotes;
        const uint32_t expectedDuration =
            uint32_t(int64_t(noteBefore.duration) + (isSelected ? selectedDurationDelta : 0));
        const auto actual = fixture.note(index);
        if (actual && actual->tick == noteBefore.tick && actual->duration == expectedDuration &&
            actual->key == noteBefore.key && actual->velocity == noteBefore.velocity &&
            actual->channel == noteBefore.channel)
            continue;
        return QStringLiteral(
                   "note[%1] (%2): actual=(present=%3,tick=%4,duration=%5,key=%6,velocity=%7,"
                   "channel=%8) expected=(present=1,tick=%9,duration=%10,key=%11,velocity=%12,"
                   "channel=%13)")
            .arg(QString::number(index),
                 isSelected ? QStringLiteral("selected") : QStringLiteral("unselected"),
                 actual.has_value() ? QStringLiteral("1") : QStringLiteral("0"),
                 actual ? QString::number(actual->tick) : QStringLiteral("0"),
                 actual ? QString::number(actual->duration) : QStringLiteral("0"),
                 actual ? QString::number(int(actual->key)) : QStringLiteral("-1"),
                 actual ? QString::number(int(actual->velocity)) : QStringLiteral("0"),
                 actual ? QString::number(int(actual->channel)) : QStringLiteral("0"),
                 QString::number(noteBefore.tick), QString::number(expectedDuration),
                 QString::number(int(noteBefore.key)), QString::number(int(noteBefore.velocity)),
                 QString::number(int(noteBefore.channel)));
    }
    return {};
}

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
        const bool isSelected = index < kSelectedNotes;
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

void SelectionKeyCoreTest::arrowsResizeSelectedNotesAcrossBands_data()
{
    QTest::addColumn<int>("bandIndex");
    QTest::addColumn<bool>("longer");
    for (std::size_t index = 0; index < kCoreBands.size(); ++index) {
        QTest::newRow(qPrintable(
            QStringLiteral("%1: Shift Right").arg(QLatin1String(kCoreBands[index].label))))
            << int(index) << true;
        QTest::newRow(qPrintable(
            QStringLiteral("%1: Shift Left").arg(QLatin1String(kCoreBands[index].label))))
            << int(index) << false;
    }
}

void SelectionKeyCoreTest::arrowsResizeSelectedNotesAcrossBands()
{
    QFETCH(int, bandIndex);
    QFETCH(bool, longer);
    const BandProbe &probe = kCoreBands[std::size_t(bandIndex)];
    const QString direction = longer ? QStringLiteral("Shift Right") : QStringLiteral("Shift Left");

    m_fixture = createFixture(std::nullopt);
    QVERIFY2(m_fixture,
             qPrintable(QStringLiteral("could not create the cross-band resize fixture: %1")
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

    // The resize contract is proven entirely in the document: whichever band
    // or incidental drawer chrome holds focus, the shared policy must resolve
    // the same semantic operation, so focus state itself is never asserted.
    QVERIFY2(m_fixture->focusBand(probe.band),
             qPrintable(QStringLiteral("%1 band could not stage focus for resize chords")
                            .arg(QLatin1String(probe.label))));
    songView.selectionModel().setNoteSelection(selection);
    selectionkey::settle();

    const auto before = m_fixture->snapshotNotes();
    QVERIFY2(
        before.has_value(),
        qPrintable(QStringLiteral("%1 band: a cross-band resize fixture note vanished before a "
                                  "chord")
                       .arg(QLatin1String(probe.label))));

    // The chord follows the live registry instead of duplicating the shipped
    // default table (keymapcheck pins those defaults).
    const char *commandId = longer ? "roll.lengthen_note" : "roll.shorten_note";
    const auto binding = selectionkey::firstBinding(QLatin1String(commandId));
    QVERIFY2(binding.has_value(),
             qPrintable(QStringLiteral("%1 band %2: %3 has no single-key binding")
                            .arg(QLatin1String(probe.label), direction, QLatin1String(commandId))));
    QVERIFY2(selectionkey::deliverKey(quick, binding->key(), binding->keyboardModifiers()),
             qPrintable(QStringLiteral("%1 band %2: Quick window did not accept the key")
                            .arg(QLatin1String(probe.label), direction)));

    // The verdict stays exact but its expectation is now independent: the
    // lattice preconditions pin the known cell, the delta comes from the
    // constants plus the snapshot alone, and resizeDocumentMismatch holds
    // every note to the exact result.
    const QString latticeMismatch = resizeLatticeMismatch(songView);
    QVERIFY2(latticeMismatch.isEmpty(),
             qPrintable(QStringLiteral("%1 band %2 staged off the known resize lattice: %3")
                            .arg(QLatin1String(probe.label), direction, latticeMismatch)));
    const int64_t durationDelta = resizeDurationDelta(*before, longer);
    const QString mismatch = resizeDocumentMismatch(*m_fixture, *before, durationDelta);
    QVERIFY2(mismatch.isEmpty(),
             qPrintable(QStringLiteral("%1 band %2 resized the wrong notes or by the wrong "
                                       "delta: %3")
                            .arg(QLatin1String(probe.label), direction, mismatch)));
    QVERIFY2(songView.selectionModel().noteSelection() == selection,
             qPrintable(QStringLiteral("%1 band %2 disturbed the selection: actual=%3 "
                                       "intended=%4")
                            .arg(QLatin1String(probe.label), direction,
                                 describeNoteIds(songView.selectionModel().noteSelection()),
                                 describeNoteIds(selection))));
}

void SelectionKeyCoreTest::reboundResizeBindingReplacesDefaultChord()
{
    const auto original = selectionkey::firstBinding(QStringLiteral("roll.lengthen_note"));
    QVERIFY2(original.has_value(), "Lengthen Note has no single-key default binding");

    m_fixture = createFixture(std::nullopt);
    QVERIFY2(m_fixture, qPrintable(QStringLiteral("could not create the resize-rebind fixture: %1")
                                       .arg(m_lastFixtureError)));
    QQuickWindow *const quick = m_fixture->window();
    SongView &songView = m_fixture->view();
    const std::vector<NoteId> selection{m_fixture->notes()[0], m_fixture->notes()[1]};

    QVERIFY2(m_fixture->focusBand(songview::TimelineBand::OtherEvents),
             "could not stage band focus for the resize-rebind proof");
    songView.selectionModel().setNoteSelection(selection);
    selectionkey::settle();

    const auto before = m_fixture->snapshotNotes();
    QVERIFY2(before.has_value(), "a fixture note vanished before the resize-rebind proof");
    const QString latticeMismatch = resizeLatticeMismatch(songView);
    QVERIFY2(latticeMismatch.isEmpty(),
             qPrintable(QStringLiteral("the resize-rebind fixture staged off the known resize "
                                       "lattice: %1")
                            .arg(latticeMismatch)));
    const int64_t lengthenDelta = resizeDurationDelta(*before, true);

    // The shared route must resolve the live registry. This explicit
    // OverrideSnapshot scope holds the rebind for both halves of the proof;
    // its destructor restores every override even when an assertion returns
    // early (init()'s member guard is the outer backstop).
    const QKeySequence reboundSequence(QStringLiteral("Ctrl+Shift+Right"));
    {
        selectionkey::KeymapRestore rebindScope;
        QVERIFY2(rebindScope.registry()
                     .conflicts(QStringLiteral("roll.lengthen_note"), keymap::Context::Timeline,
                                reboundSequence)
                     .isEmpty(),
                 "Ctrl+Shift+Right is not an unused Timeline chord for the rebound resize proof");
        rebindScope.registry().setBinding(QStringLiteral("roll.lengthen_note"), reboundSequence);
        const auto rebound = selectionkey::firstBinding(QStringLiteral("roll.lengthen_note"));
        QVERIFY2(rebound.has_value() && *rebound == reboundSequence[0],
                 "Lengthen Note did not install the rebound Ctrl+Shift+Right chord");

        // The retired default chord must not resize anything.
        QVERIFY2(selectionkey::deliverKey(quick, original->key(), original->keyboardModifiers()),
                 "the retired Lengthen Note chord was not delivered");
        QString mismatch = resizeDocumentMismatch(*m_fixture, *before, 0);
        QVERIFY2(
            mismatch.isEmpty(),
            qPrintable(
                QStringLiteral("the retired Lengthen Note chord still resized: %1").arg(mismatch)));

        // The rebound chord routes through the same shared seam: exactly one
        // grid step, other notes untouched, selection preserved.
        QVERIFY2(selectionkey::deliverKey(quick, rebound->key(), rebound->keyboardModifiers()),
                 "the rebound Lengthen Note chord was not accepted");
        mismatch = resizeDocumentMismatch(*m_fixture, *before, lengthenDelta);
        QVERIFY2(mismatch.isEmpty(),
                 qPrintable(QStringLiteral("the rebound Lengthen Note chord did not resize by "
                                           "one grid step: %1")
                                .arg(mismatch)));
        QVERIFY2(songView.selectionModel().noteSelection() == selection,
                 qPrintable(QStringLiteral("the rebound resize disturbed the selection: "
                                           "actual=%1 intended=%2")
                                .arg(describeNoteIds(songView.selectionModel().noteSelection()),
                                     describeNoteIds(selection))));
    }

    // Scope closed: the default chord routes again.
    const auto restored = selectionkey::firstBinding(QStringLiteral("roll.lengthen_note"));
    QVERIFY2(restored.has_value() && *restored == *original,
             "the OverrideSnapshot scope did not restore the default Lengthen Note chord");
    const auto after = m_fixture->snapshotNotes();
    QVERIFY2(after.has_value(), "a fixture note vanished before the restored-chord proof");
    QVERIFY2(selectionkey::deliverKey(quick, restored->key(), restored->keyboardModifiers()),
             "the restored Lengthen Note chord was not accepted");
    const QString mismatch = resizeDocumentMismatch(*m_fixture, *after, lengthenDelta);
    QVERIFY2(mismatch.isEmpty(),
             qPrintable(QStringLiteral("the restored Lengthen Note chord did not resize by one "
                                       "grid step: %1")
                            .arg(mismatch)));
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
            const int expectedKey = int(noteBefore.key) + (index < kSelectedNotes ? keyShift : 0);
            const uint64_t expectedTick =
                uint64_t(int64_t(noteBefore.tick) + (index < kSelectedNotes ? tickShift : 0));
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
