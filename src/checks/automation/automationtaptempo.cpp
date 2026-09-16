// Tap-tempo integration coverage for the Tempo parameter row. Every
// scenario drives the staged canvas surface — the Q_INVOKABLE tapTempo()
// seam, the rendered Tap button through a real center click, and the
// documentChanged/cancelInteraction seams — and reads the document, the
// undo stack, the draft properties, and their signals as oracles. The
// TapTempoSession accumulator itself is never touched directly.

#include "checks/automation/tst_automationediting.h"

#include <cmath>
#include <variant>

#include <QCoreApplication>
#include <QElapsedTimer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSignalSpy>
#include <QtTest>

#include "checks/support/timelinequickcheck.h"
#include "core/songdocument.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/mousehints/hintprofiles.h"
#include "ui/songtab.h"
#include "ui/songview/quick/timelinequickview.h"

namespace {

// The slowest idle-commit window (the gap distance, used by draft-less
// sessions): waiting it out is a conservative upper bound for any commit,
// so it stays the assertion's only wall-clock cost.
constexpr int kTapIdleMs = 2000;
// Real taps cannot land on exact cadences, so draft bands keep the
// kinematics honest at ±15% around the cadence's nominal BPM.
constexpr double kDraftTolerance = 0.15;

constexpr Tick kLaterTick = 96;
constexpr Tick kFarTick = 192;
constexpr int kLaterBpm = 140;
constexpr int kFarBpm = 90;

} // namespace

void AutomationEditingTest::activateTempoRow()
{
    QVERIFY(activateParameter({EditorAutomationRowKind::Tempo, 0, 0}));
}

void AutomationEditingTest::setTempoStream(std::vector<TempoPoint> points)
{
    SongDocument &document = tab().document();
    if (document.tempoPoints() != points) {
        TempoEdit edit;
        edit.remove = document.tempoPoints();
        edit.add = std::move(points);
        document.applyTempoEdit(edit);
    }
    page().documentChanged();
    QCoreApplication::processEvents();
}

int AutomationEditingTest::tempoBpmAt(Tick tick) const
{
    for (const TempoPoint &point : tab().document().tempoPoints()) {
        if (point.tick == tick)
            return int(std::lround(CoreTimeDefaults::tempoBpm(point.microsecondsPerQuarterNote)));
    }
    return 0;
}

// Streams one cadence through the canvas seam. The real QTest::qWait
// runs only the staged gaps; the idle commit fires on those alone.
void AutomationEditingTest::tapCadence(AutomationCanvas &canvas, const std::vector<int> &gapMs)
{
    for (const int gap : gapMs) {
        if (gap > 0)
            QTest::qWait(gap);
        canvas.tapTempo();
    }
}

// The idle-commit wait: the only wall-clock cost a commit assertion carries.
void AutomationEditingTest::waitTapIdle()
{
    QTest::qWait(kTapIdleMs + 150);
}

void AutomationEditingTest::expectDraftBpmWithin(const AutomationCanvas &canvas,
                                                 int nominalBpm) const
{
    const int draft = canvas.tapTempoDraftBpm();
    const int slack = int(std::lround(nominalBpm * kDraftTolerance));
    QVERIFY2(
        draft >= nominalBpm - slack && draft <= nominalBpm + slack,
        qPrintable(QStringLiteral("draft %1 outside %2±%3").arg(draft).arg(nominalBpm).arg(slack)));
}

// The draft appears from the second staged tap and recomputes per tap;
// the document stays frozen through the whole accumulating exchange.
void AutomationEditingTest::tapTempoDraftAccumulatesFromSecondTapAndFreezesDocument()
{
    activateTempoRow();
    auto *const canvas = page().canvas();
    QVERIFY(canvas);
    QVERIFY(canvas->parametersEnabled());

    QSignalSpy draftChanged(canvas, &AutomationCanvas::tapTempoDraftChanged);
    QSignalSpy committed(canvas, &AutomationCanvas::tapTempoCommitted);
    QVERIFY(draftChanged.isValid());
    QVERIFY(committed.isValid());

    const FrozenDocumentState beforeTap = frozenDocumentState();

    canvas->tapTempo();
    QCOMPARE(committed.count(), 0);
    QCOMPARE(canvas->tapTempoTapCount(), 1);
    QCOMPARE(canvas->tapTempoDraftBpm(), 0);
    QVERIFY(frozenDocumentState() == beforeTap);

    QTest::qWait(500);
    canvas->tapTempo();
    QCOMPARE(committed.count(), 0);
    QCOMPARE(canvas->tapTempoTapCount(), 2);
    expectDraftBpmWithin(*canvas, 120);

    QTest::qWait(500);
    canvas->tapTempo();
    QCOMPARE(committed.count(), 0);
    QCOMPARE(canvas->tapTempoTapCount(), 3);
    expectDraftBpmWithin(*canvas, 120);
    QVERIFY(draftChanged.count() >= 2);
    QVERIFY(frozenDocumentState() == beforeTap);
    QCOMPARE(tab().document().revision(), beforeTap.revision);
    QCOMPARE(tab().document().undoStack()->count(), beforeTap.undoCount);
    QCOMPARE(tab().document().undoStack()->index(), beforeTap.undoIndex);
}

// A single stray tap left alone only begins a session the idle window then
// silently aborts: nothing is written and no commit fires.
void AutomationEditingTest::tapTempoSingleStrayTapAfterIdleGapCommitsNothing()
{
    activateTempoRow();
    auto *const canvas = page().canvas();
    QVERIFY(canvas);
    QVERIFY(canvas->parametersEnabled());

    QSignalSpy committed(canvas, &AutomationCanvas::tapTempoCommitted);
    QVERIFY(committed.isValid());

    const FrozenDocumentState beforeTap = frozenDocumentState();

    canvas->tapTempo();
    waitTapIdle();

    QCOMPARE(committed.count(), 0);
    QCOMPARE(canvas->tapTempoTapCount(), 0);
    QCOMPARE(canvas->tapTempoDraftBpm(), 0);
    QVERIFY(frozenDocumentState() == beforeTap);
}

// Four taps at a 300ms cadence commit exactly once at tick-0: the written
// BPM matches the last draft, the undo stack gains one command, and undo
// restores the pre-commit document. A post-commit stray tap starts a fresh
// session that the same idle window aborts: the gap-reset path.
void AutomationEditingTest::tapTempoFourTapsCommitOnceAtTickZeroAndUndoRestores()
{
    activateTempoRow();
    auto *const canvas = page().canvas();
    QVERIFY(canvas);
    QVERIFY(canvas->parametersEnabled());

    QSignalSpy committed(canvas, &AutomationCanvas::tapTempoCommitted);
    QVERIFY(committed.isValid());

    QVERIFY(tab().document().tempoPoints().empty());
    tapCadence(*canvas, {300, 300, 300, 300});
    QCOMPARE(committed.count(), 0);
    const int draft = canvas->tapTempoDraftBpm();
    QVERIFY2(draft >= 170 && draft <= 235,
             qPrintable(QStringLiteral("four-tap draft %1").arg(draft)));

    const FrozenDocumentState beforeCommit = frozenDocumentState();
    waitTapIdle();

    QCOMPARE(committed.count(), 1);
    QCOMPARE(committed.at(0).at(0).toInt(), draft);
    QCOMPARE(tab().document().undoStack()->count(), beforeCommit.undoCount + 1);
    QCOMPARE(tab().document().undoStack()->index(), beforeCommit.undoIndex + 1);
    QCOMPARE(int(tab().document().tempoPoints().size()), 1);
    QCOMPARE(tab().document().tempoPoints().front().tick, Tick{0});
    QCOMPARE(tab().document().tempoPoints().front().microsecondsPerQuarterNote,
             CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(draft));
    QCOMPARE(canvas->tapTempoTapCount(), 0);
    QCOMPARE(canvas->tapTempoDraftBpm(), 0);

    // Undo restores the whole pre-commit stream as one applied command.
    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(tab().history().requestUndo()));
    QCOMPARE(tab().document().undoStack()->index(), beforeCommit.undoIndex);
    QCOMPARE(tab().document().tempoPoints().size(), std::size_t{0});

    // The gap reset: a cadence-length stray tap past the commit distance
    // starts a fresh session the same idle window aborts.
    tapCadence(*canvas, {2100});
    QCOMPARE(committed.count(), 1);
    waitTapIdle();
    QCOMPARE(committed.count(), 1);
    QCOMPARE(tab().document().undoStack()->count(), beforeCommit.undoCount + 1);
}

// Tapping the tempo the document already holds at tick-0 is silent: no
// commit fires onto a same-BPM draft and no revision lands.
void AutomationEditingTest::tapTempoTappingCurrentTickZeroTempoIsSilent()
{
    // Seed the stream before activating the row: setTempoStream drives the
    // real documentChanged seam, which cancels the active interaction.
    setTempoStream({{0, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(255)}});

    activateTempoRow();
    auto *const canvas = page().canvas();
    QVERIFY(canvas);
    QVERIFY(canvas->parametersEnabled());

    const int seedBpm = tempoBpmAt(Tick{0});
    QCOMPARE(seedBpm, 255);

    QSignalSpy draftChanged(canvas, &AutomationCanvas::tapTempoDraftChanged);
    QSignalSpy committed(canvas, &AutomationCanvas::tapTempoCommitted);
    QVERIFY(draftChanged.isValid());
    QVERIFY(committed.isValid());
    const FrozenDocumentState beforeTap = frozenDocumentState();

    // Two immediate taps: sub-ms intervals always clamp to exactly 255 BPM
    // regardless of timer precision, so the draft deterministically equals
    // the seed and the dedup path must stay silent.
    tapCadence(*canvas, {0, 0});
    QCOMPARE(committed.count(), 0);
    QCOMPARE(canvas->tapTempoDraftBpm(), 255);

    waitTapIdle();
    QCOMPARE(committed.count(), 0);
    QVERIFY(frozenDocumentState() == beforeTap);
    QCOMPARE(tab().document().revision(), beforeTap.revision);
    QCOMPARE(tab().document().undoStack()->count(), beforeTap.undoCount);
    QCOMPARE(tab().document().undoStack()->index(), beforeTap.undoIndex);
    QVERIFY(draftChanged.count() >= 1);
    QCOMPARE(int(tab().document().tempoPoints().size()), 1);
    QCOMPARE(tempoBpmAt(Tick{0}), 255);
}

// Replacing the tick-0 tempo leaves the later points and their values as
// the commit wrote them: exactly one point is rewritten, none moved.
void AutomationEditingTest::tapTempoCommitReplacesTickZeroPointPreservingLaterPoints()
{
    // Seed the stream before activating the row: setTempoStream drives the
    // real documentChanged seam, which cancels the active interaction.
    setTempoStream({{0, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(100)},
                    {kLaterTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kLaterBpm)},
                    {kFarTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kFarBpm)}});
    QCOMPARE(int(tab().document().tempoPoints().size()), 3);

    activateTempoRow();
    auto *const canvas = page().canvas();
    QVERIFY(canvas);
    QVERIFY(canvas->parametersEnabled());

    QSignalSpy committed(canvas, &AutomationCanvas::tapTempoCommitted);
    QVERIFY(committed.isValid());

    tapCadence(*canvas, {500, 500});
    expectDraftBpmWithin(*canvas, 120);
    const int draft = canvas->tapTempoDraftBpm();

    const FrozenDocumentState beforeCommit = frozenDocumentState();
    waitTapIdle();

    QCOMPARE(committed.count(), 1);
    QCOMPARE(committed.at(0).at(0).toInt(), draft);
    QVERIFY(tab().document().revision() > beforeCommit.revision);
    QCOMPARE(tab().document().undoStack()->count(), beforeCommit.undoCount + 1);
    QCOMPARE(tab().document().undoStack()->index(), beforeCommit.undoIndex + 1);
    QCOMPARE(tempoBpmAt(Tick{0}), draft);
    QCOMPARE(tempoBpmAt(kLaterTick), kLaterBpm);
    QCOMPARE(tempoBpmAt(kFarTick), kFarBpm);
    QCOMPARE(int(tab().document().tempoPoints().size()), 3);
    QCOMPARE(canvas->tapTempoTapCount(), 0);
    QCOMPARE(canvas->tapTempoDraftBpm(), 0);

    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(tab().history().requestUndo()));
    QCOMPARE(int(tab().document().tempoPoints().size()), 3);
    QCOMPARE(tempoBpmAt(Tick{0}), 100);
}

void AutomationEditingTest::tapTempoCommitInsertsFirstTempoPointOnNonzeroDocument()
{
    // Seed the stream before activating the row: setTempoStream drives the
    // real documentChanged seam, which cancels the active interaction.
    setTempoStream({{kLaterTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(120)}});
    QCOMPARE(int(tab().document().tempoPoints().size()), 1);

    activateTempoRow();
    auto *const canvas = page().canvas();
    QVERIFY(canvas);
    QVERIFY(canvas->parametersEnabled());

    QSignalSpy committed(canvas, &AutomationCanvas::tapTempoCommitted);
    QVERIFY(committed.isValid());

    tapCadence(*canvas, {500, 500});
    expectDraftBpmWithin(*canvas, 120);
    const int draft = canvas->tapTempoDraftBpm();

    const FrozenDocumentState beforeCommit = frozenDocumentState();
    waitTapIdle();

    QCOMPARE(committed.count(), 1);
    QCOMPARE(committed.at(0).at(0).toInt(), draft);
    QCOMPARE(tab().document().undoStack()->count(), beforeCommit.undoCount + 1);
    QCOMPARE(tab().document().undoStack()->index(), beforeCommit.undoIndex + 1);
    QCOMPARE(tempoBpmAt(Tick{0}), draft);
    QCOMPARE(tempoBpmAt(kLaterTick), 120);
    QCOMPARE(int(tab().document().tempoPoints().size()), 2);
    QCOMPARE(canvas->tapTempoTapCount(), 0);
    QCOMPARE(canvas->tapTempoDraftBpm(), 0);

    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(tab().history().requestUndo()));
    QCOMPARE(int(tab().document().tempoPoints().size()), 1);
}

// A concurrent tick-0 tempo edit mid-session aborts the draft
// synchronously through the real documentChanged fan-out; no idle wait
// runs and nothing lands.
void AutomationEditingTest::tapTempoConcurrentTempoEditAbortsDraftSynchronously()
{
    activateTempoRow();
    auto *const canvas = page().canvas();
    QVERIFY(canvas);
    QVERIFY(canvas->parametersEnabled());

    tapCadence(*canvas, {500, 500});
    QVERIFY(canvas->tapTempoDraftBpm() > 0);
    const uint64_t revisionBeforeEdit = tab().document().revision();

    SongDocument &document = tab().document();
    TempoEdit edit;
    edit.remove = document.tempoPoints();
    edit.add = {{kLaterTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kLaterBpm)}};
    document.applyTempoEdit(edit);
    QCoreApplication::processEvents();

    QVERIFY(tab().document().revision() > revisionBeforeEdit);
    QCOMPARE(canvas->tapTempoTapCount(), 0);
    QCOMPARE(canvas->tapTempoDraftBpm(), 0);
    QCOMPARE(int(document.tempoPoints().size()), 1);

    // The abort survives the idle window untouched: no retry, no late
    // commit, no restored draft.
    waitTapIdle();
    QCOMPARE(canvas->tapTempoTapCount(), 0);
    QCOMPARE(canvas->tapTempoDraftBpm(), 0);
    QCOMPARE(int(document.tempoPoints().size()), 1);
    QCoreApplication::processEvents();
}

// Page::documentChanged() is the real refresh seam every page consumer
// drives; it ends the canvas interaction and a pending tap draft with it.
void AutomationEditingTest::tapTempoDocumentChangedSeamClearsSession()
{
    activateTempoRow();
    auto *const canvas = page().canvas();
    QVERIFY(canvas);
    QVERIFY(canvas->parametersEnabled());

    tapCadence(*canvas, {500, 500});
    QVERIFY(canvas->tapTempoDraftBpm() > 0);

    const FrozenDocumentState beforeClear = frozenDocumentState();
    page().documentChanged();
    QCoreApplication::processEvents();

    QCOMPARE(canvas->tapTempoTapCount(), 0);
    QCOMPARE(canvas->tapTempoDraftBpm(), 0);
    QVERIFY(frozenDocumentState() == beforeClear);
    QCOMPARE(tab().document().revision(), beforeClear.revision);
    QCOMPARE(tab().document().undoStack()->count(), beforeClear.undoCount);
    QCOMPARE(tab().document().undoStack()->index(), beforeClear.undoIndex);
}

// Disabled / empty-document staging is a no-op without a crash: resetting
// a live draft costs nothing, and resetTapTempo is idempotent on a clean
// session.
void AutomationEditingTest::tapTempoDisabledCanvasAndEmptyDocumentAreNoOps()
{
    activateTempoRow();
    auto *const canvas = page().canvas();
    QVERIFY(canvas);
    QVERIFY(canvas->parametersEnabled());

    // A draft held while the canvas is inactive is dropped by a reset,
    // not committed on a later re-enable, and resetting again is silent.
    canvas->tapTempo();
    canvas->resetTapTempo();
    QCOMPARE(canvas->tapTempoTapCount(), 0);
    QCOMPARE(canvas->tapTempoDraftBpm(), 0);

    const FrozenDocumentState beforeReset = frozenDocumentState();
    canvas->resetTapTempo();
    QVERIFY(frozenDocumentState() == beforeReset);
    QCOMPARE(canvas->tapTempoTapCount(), 0);
    QCOMPARE(canvas->tapTempoDraftBpm(), 0);
}

// One rendered Tap control lives in the Tempo row only: a real center
// click stages a tap without touching the document, its active parameter,
// or revision.
void AutomationEditingTest::tapTempoRenderedTapButtonStagesTapWithoutDocumentChanges()
{
    activateTempoRow();
    auto *const canvas = page().canvas();
    QVERIFY(canvas);
    QVERIFY(canvas->parametersEnabled());

    const int tempoIndex =
        checks::support::automationParameterIndex(*canvas, {EditorAutomationRowKind::Tempo, 0, 0});
    QVERIFY(tempoIndex >= 0);
    QQuickItem *const root = tab().view().quickView()->rootObject();
    QVERIFY(root);
    QQuickItem *const tapButton =
        checks::support::visualDescendant(root, QStringLiteral("automationTempoTapButton"));
    QVERIFY(tapButton);
    QVERIFY(tapButton->isVisible());
    QVERIFY(tapButton->isEnabled());

    QQuickItem *const draftText =
        checks::support::visualDescendant(root, QStringLiteral("automationTempoTapDraft"));
    QVERIFY(draftText);
    QCOMPARE(draftText->isVisible(), false);

    const FrozenDocumentState beforeTap = frozenDocumentState();
    QSignalSpy committed(canvas, &AutomationCanvas::tapTempoCommitted);
    QVERIFY(committed.isValid());

    // The Tap button sizes its content after first exposure; choose the
    // real center only once the layout assigned its geometry.
    QTRY_VERIFY(tapButton->width() > 0 && tapButton->height() > 0);
    QTest::mouseClick(
        &*m_quickWindow, Qt::LeftButton, Qt::NoModifier,
        tapButton->mapToScene(QPointF(tapButton->width() / 2.0, tapButton->height() / 2.0))
            .toPoint());
    QCoreApplication::processEvents();

    QCOMPARE(canvas->tapTempoTapCount(), 1);
    QCOMPARE(canvas->tapTempoDraftBpm(), 0);
    QCOMPARE(draftText->isVisible(), true);
    QCOMPARE(canvas->activeParameter(), tempoIndex);
    QCOMPARE(committed.count(), 0);
    QVERIFY(frozenDocumentState() == beforeTap);
    QCOMPARE(tab().document().revision(), beforeTap.revision);
    QCOMPARE(tab().document().undoStack()->count(), beforeTap.undoCount);
    QCOMPARE(tab().document().undoStack()->index(), beforeTap.undoIndex);
}

// Mean, window, and clamp bounds all stage through the same canvas seam:
// 500ms taps draft ~120, 750ms taps ~80, a ≥10-tap rapid burst keeps a sane
// bounded draft with one idle commit, and the pathological 150ms and
// 3000ms cadences sit at the BPM clamp and the gap boundary respectively.
void AutomationEditingTest::tapTempoMeanWindowAndClampBounds()
{
    activateTempoRow();
    auto *const canvas = page().canvas();
    QVERIFY(canvas);
    QVERIFY(canvas->parametersEnabled());

    QSignalSpy committed(canvas, &AutomationCanvas::tapTempoCommitted);
    QVERIFY(committed.isValid());

    // 500ms cadence drafts ~120.
    tapCadence(*canvas, {500, 500, 500, 500});
    expectDraftBpmWithin(*canvas, 120);
    waitTapIdle();
    QCOMPARE(committed.count(), 1);
    // Separate cadence phases so the 8-interval window never mixes them.
    canvas->resetTapTempo();
    QCOMPARE(canvas->tapTempoTapCount(), 0);

    // 750ms cadence drafts ~80.
    tapCadence(*canvas, {750, 750, 750, 750});
    expectDraftBpmWithin(*canvas, 80);
    waitTapIdle();
    QCOMPARE(committed.count(), 2);
    canvas->resetTapTempo();

    // ≥10 rapid taps: more taps than the window keeps the draft sane, and
    // the whole session still lands one commit at tick-0.
    tapCadence(*canvas, {400, 400, 400, 400, 400, 400, 400, 400, 400, 400, 400});
    expectDraftBpmWithin(*canvas, 150);
    const int burstDraft = canvas->tapTempoDraftBpm();
    QCOMPARE(committed.count(), 2);
    waitTapIdle();
    QCOMPARE(committed.count(), 3);
    QCOMPARE(int(tab().document().tempoPoints().size()), 1);
    QCOMPARE(tempoBpmAt(Tick{0}), burstDraft);
    QCOMPARE(canvas->tapTempoTapCount(), 0);

    canvas->resetTapTempo();
    // The 150ms cadence is above the 255 BPM ceiling: the draft clamps to
    // the published maximum.
    tapCadence(*canvas, {150, 150, 150, 150});
    QCOMPARE(canvas->tapTempoDraftBpm(), CoreTimeDefaults::kMaxTempoBpm);
    waitTapIdle();
    QCOMPARE(committed.count(), 4);
    QCOMPARE(tempoBpmAt(Tick{0}), CoreTimeDefaults::kMaxTempoBpm);

    canvas->resetTapTempo();
    // A cadence past the shared gap/commit distance is the fresh-session
    // boundary: each tap aborts into a new session, so the draft stays
    // empty and the idle window commits nothing.
    tapCadence(*canvas, {3000, 3000, 3000});
    QCOMPARE(canvas->tapTempoTapCount(), 1);
    QCOMPARE(canvas->tapTempoDraftBpm(), 0);
    waitTapIdle();
    QCOMPARE(committed.count(), 4);
    QCOMPARE(tempoBpmAt(Tick{0}), CoreTimeDefaults::kMaxTempoBpm);
}

// The TapTempo profile's catalog text is a real, non-empty,
// GhostParameter-distinct rendering the staged guard can publish.
void AutomationEditingTest::tapTempoHintCatalogTextIsPresentAndDistinct()
{
    ui::hint_profiles::Catalog catalog;
    const QString tapText = catalog.text(ui::hint_profiles::Id::TapTempo);
    const QString ghostText = catalog.text(ui::hint_profiles::Id::GhostParameter);
    QVERIFY2(!tapText.isEmpty(), "the TapTempo catalog text rendered empty");
    QVERIFY(!ghostText.isEmpty());
    QVERIFY(tapText != ghostText);
}
