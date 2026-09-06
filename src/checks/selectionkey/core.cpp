#include "checks/selectionkey/automationprobe.h"
#include "checks/selectionkey/primitives.h"
#include "checks/support/eventsynth.h"

#include "core/songdocument.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/keymap.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"

#include <QtTest>

#include <QGuiApplication>
#include <QQuickItem>
#include <QSize>
#include <QStringList>
#include <QStyleHints>
#include <algorithm>
#include <array>
#include <bit>
#include <cmath>
#include <cstdio>
#include <memory>
#include <optional>
#include <utility>
#include <vector>

namespace {

// Honesty note: fixture staging here is deliberately programmatic — project
// load, band focus, pencil mode, scroll reveal and selection-model state are
// arranged through production APIs because they are the conditions of the
// test, not its subject. What is never bypassed is delivery: every command
// under test reaches the shown Quick window as a real QTest key or mouse
// event.
constexpr int kTrack = 0;
constexpr uint8_t kController = 10;
constexpr uint64_t kFirstNoteTick = 960;
constexpr uint64_t kFirstPointTick = 48;
constexpr uint64_t kInsidePointTick = 72;
constexpr uint64_t kSecondPointTick = 96;
constexpr uint64_t kOutsidePointTick = 144;
constexpr uint64_t kPasteTick = 1200;

// Reserved fixture ticks (plan scenario 1): notes at kFirstNoteTick{+48,+96},
// automation lane points at kFirstPointTick/kInsidePointTick/kSecondPointTick/
// kOutsidePointTick, paste probe at kPasteTick. Scenario functions own
// disjoint tick ranges so an edit to one cannot silently retarget another.
constexpr int kAutomationSectionHeight = 250;
constexpr int kVelocitySectionHeight = 320;
constexpr int kVoiceChangesSectionHeight = 180;

int canonicalSectionHeight(EditorDrawerPage page)
{
    switch (page) {
    case EditorDrawerPage::Automations:
        return kAutomationSectionHeight;
    case EditorDrawerPage::Velocity:
        return kVelocitySectionHeight;
    case EditorDrawerPage::VoiceChanges:
        return kVoiceChangesSectionHeight;
    }
    return 0;
}

std::optional<EditorDrawerPage> drawerPageForBand(songview::TimelineBand band)
{
    switch (band) {
    case songview::TimelineBand::Automation:
        return EditorDrawerPage::Automations;
    case songview::TimelineBand::Velocity:
        return EditorDrawerPage::Velocity;
    case songview::TimelineBand::VoiceChanges:
        return EditorDrawerPage::VoiceChanges;
    default:
        return std::nullopt;
    }
}

struct ClickTarget {
    std::optional<QPoint> point;
    QString diagnostics;
};

QString describePoint(const QPointF &point)
{
    return QStringLiteral("(%1,%2)").arg(point.x(), 0, 'f', 2).arg(point.y(), 0, 'f', 2);
}

QString describeRect(const QRectF &rect)
{
    return QStringLiteral("(%1,%2 %3x%4)")
        .arg(rect.x(), 0, 'f', 2)
        .arg(rect.y(), 0, 'f', 2)
        .arg(rect.width(), 0, 'f', 2)
        .arg(rect.height(), 0, 'f', 2);
}

template <typename Range>
QString describeNoteIds(const Range &ids)
{
    static_assert(sizeof(NoteId) == sizeof(uint64_t));
    QStringList values;
    for (const NoteId id : ids) {
        values.push_back(QStringLiteral("0x%1").arg(
            static_cast<qulonglong>(std::bit_cast<uint64_t>(id)), 16, 16, QLatin1Char('0')));
    }
    return QStringLiteral("[%1]").arg(values.join(QLatin1Char(',')));
}

using selectionkey::deliverKey;
using selectionkey::firstBinding;
using selectionkey::KeymapRestore;
using selectionkey::rigDocument;
using selectionkey::rigInput;
using selectionkey::rigView;
using selectionkey::rigWindow;
using selectionkey::RigWorld;

std::vector<SongDocument::NewNote> coreNoteSpecs()
{
    return {{kFirstNoteTick, 60, 24, 100},
            {kFirstNoteTick + 48, 64, 24, 96},
            {kFirstNoteTick + 96, 67, 24, 88}};
}

checks::EditorRigConfig coreRigConfig(std::optional<EditorDrawerPage> drawerPage)
{
    checks::EditorRigConfig config;
    config.track = kTrack;
    if (drawerPage) {
        config.activePage = *drawerPage;
        config.sections = {{*drawerPage, canonicalSectionHeight(*drawerPage)}};
    }
    config.timeZoom = 96.0;
    return config;
}

void prepareCoreDocument(SongDocument &document)
{
    document.addLanePoint(kTrack, kController, kFirstPointTick, 32);
    document.addLanePoint(kTrack, kController, kSecondPointTick, 64);
    document.addLanePoint(kTrack, kController, kOutsidePointTick, 96);
    document.addLanePoint(kTrack, kController, kInsidePointTick, 48);
}

void configureDrawerSurface(RigWorld &fixture, std::optional<EditorDrawerPage> drawerPage)
{
    SongView &songView = rigView(fixture);
    constexpr std::array pages{EditorDrawerPage::Automations, EditorDrawerPage::Velocity,
                               EditorDrawerPage::VoiceChanges};
    for (const EditorDrawerPage page : pages)
        songView.setDrawerSectionVisible(page, false);
    if (drawerPage) {
        songView.setDrawerActivePage(*drawerPage);
        songView.setDrawerSectionHeight(*drawerPage, canonicalSectionHeight(*drawerPage));
        songView.setDrawerSectionVisible(*drawerPage, true);
    }
    selectionkey::settle();
}

bool deliverKeyEvent(QQuickWindow *window, QEvent::Type type, int key, bool autoRepeat)
{
    if (!window)
        return false;
    checks::events::sendKey(*window, type, key, Qt::NoModifier, QString{}, autoRepeat, 1);
    selectionkey::settle();
    return true;
}

// check() with the band name in the failure line, so multi-band scenarios
// report which band regressed.
bool bandCheck(int &failures, bool condition, const char *band, const char *message)
{
    if (condition)
        return true;
    std::fprintf(stderr, "selectionkeycorecheck: FAIL: %s band: %s\n", band, message);
    ++failures;
    return false;
}

bool focus(SongView &view, songview::TimelineBand band)
{
    const bool focused = view.focusTimelineBand(band, Qt::OtherFocusReason);
    selectionkey::settle();
    return focused;
}

songview::EditorSelectionModel::TimeSelection laneRange(uint64_t begin, uint64_t end)
{
    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = begin;
    selection.endTick = end;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    selection.lanes = {{kTrack, kController}};
    return selection;
}

songview::EditorSelectionModel::TimeSelection trackRange(uint64_t begin, uint64_t end)
{
    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = begin;
    selection.endTick = end;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Tracks;
    return selection;
}

template <std::size_t Count>
std::optional<std::array<QPoint, Count>>
laneWindowPoints(RigWorld &fixture, const std::array<std::pair<uint64_t, int>, Count> &pointSpecs,
                 QString *diagnostics = nullptr)
{
    static_assert(Count > 0);
    const auto probe = selectionkey::AutomationProbe::locate(
        rigView(fixture), rigInput(fixture, "timelineAutomationInput"), kTrack, kController,
        diagnostics);
    if (!probe)
        return std::nullopt;
    std::array<selectionkey::AutomationProbePoint, Count> requested{};
    std::array<QPoint, Count> result{};
    for (std::size_t index = 0; index < Count; ++index)
        requested[index] = {pointSpecs[index].first, pointSpecs[index].second};
    if (!probe->project(requested, result, diagnostics))
        return std::nullopt;
    return result;
}

std::optional<QPoint> laneWindowPoint(RigWorld &fixture, uint64_t tick, int value,
                                      QString *diagnostics = nullptr)
{
    const auto points = laneWindowPoints<1>(fixture, {{{tick, value}}}, diagnostics);
    return points ? std::optional(points->front()) : std::nullopt;
}

ClickTarget emptyAutomationLanePoint(RigWorld &fixture)
{
    ClickTarget result;
    const auto probe = selectionkey::AutomationProbe::locate(
        rigView(fixture), rigInput(fixture, "timelineAutomationInput"), kTrack, kController,
        &result.diagnostics);
    QPoint point;
    if (probe && probe->emptyNodePoint(64, point, &result.diagnostics))
        result.point = point;
    return result;
}

ClickTarget selectedVelocityStemPoint(RigWorld &fixture)
{
    ClickTarget result;
    songview::TimelineInputItem *const velocityInput = rigInput(fixture, "timelineVelocityInput");
    EditorDrawer *const drawer = rigView(fixture).editorDrawer();
    VelocityArea *const area = drawer ? drawer->velocityArea() : nullptr;
    const auto note = selectionkey::noteById(rigDocument(fixture), fixture.notes[0]);
    if (!velocityInput || !area || !note) {
        result.diagnostics =
            QStringLiteral("input=%1,velocity-area=%2,target-note=%3")
                .arg(velocityInput ? QStringLiteral("present") : QStringLiteral("missing"),
                     area ? QStringLiteral("present") : QStringLiteral("missing"),
                     note ? QStringLiteral("present") : QStringLiteral("missing"));
        return result;
    }
    rigView(fixture).ensureRangeVisible(note->tick, note->tick + note->duration, true);
    selectionkey::settle();
    const QPointF inputPoint(
        rigView(fixture).camera().displayX(double(note->tick) + double(note->duration) * 0.75, 0.0,
                                           velocityInput->devicePixelRatio()),
        area->axis().velocityToY(note->velocity));
    const QPoint windowPoint = velocityInput->mapToScene(inputPoint).toPoint();
    const bool ready =
        velocityInput->window() == rigWindow(fixture) &&
        velocityInput->bounds().contains(inputPoint) &&
        velocityInput->bounds().contains(velocityInput->mapFromScene(QPointF(windowPoint)));
    result.diagnostics =
        QStringLiteral("input-bounds=%1,chosen-input=%2,chosen-window=%3,selection=%4")
            .arg(describeRect(velocityInput->bounds()), describePoint(inputPoint),
                 describePoint(windowPoint),
                 describeNoteIds(rigView(fixture).selectionModel().noteSelection()));
    if (ready)
        result.point = windowPoint;
    return result;
}

std::optional<QPoint> plainRulerPoint(RigWorld &fixture, songview::TimelineInputItem *ruler)
{
    // An ordinary ruler click near the center, clear of loop markers and
    // time-signature chips whose press-drag state commits on release.
    if (!ruler || ruler->bounds().isEmpty())
        return std::nullopt;
    std::vector<qreal> reservedX;
    const auto reserve = [&reservedX, &fixture, ruler](uint64_t tick) {
        if (tick != UINT64_MAX)
            reservedX.push_back(
                rigView(fixture).camera().displayX(double(tick), 0.0, ruler->devicePixelRatio()));
    };
    reserve(rigDocument(fixture).loopTick(false));
    reserve(rigDocument(fixture).loopTick(true));
    for (const DocTimeSig &signature : rigDocument(fixture).timeSigs())
        reserve(signature.tick);
    const QRectF bounds = ruler->bounds();
    for (qreal x = bounds.center().x(); x + 24.0 < bounds.right(); x += 16.0) {
        const bool reserved = std::any_of(reservedX.begin(), reservedX.end(), [x](qreal reserved) {
            return std::abs(x - reserved) <= 24.0;
        });
        if (!reserved)
            return std::optional(ruler->mapToScene(QPointF(x, bounds.center().y())).toPoint());
    }
    return std::nullopt;
}

void arrowsFollowNotesAcrossClickedBands(int &failures, const QString &projectRoot,
                                         const QString &songLabel)
{
    // Automation uses an empty visible lane click. Velocity exercises the
    // intended selected-stem contract with a real threshold-crossing drag:
    // a press/release without relative movement intentionally becomes a
    // singleton selection. Other surfaces retain their production click
    // semantics before focus and arrow routing are staged explicitly.
    enum class IncidentalClick {
        AutomationLaneGap,
        SelectedVelocityStemDrag,
        PlainRuler,
        BandCenter
    };
    struct BandProbe {
        songview::TimelineBand timelineBand;
        const char *item;
        const char *label;
        bool clickTakesFocus;
        IncidentalClick click;
    };
    const std::array<BandProbe, 5> bands{
        BandProbe{songview::TimelineBand::Automation, "timelineAutomationInput", "automation", true,
                  IncidentalClick::AutomationLaneGap},
        BandProbe{songview::TimelineBand::Velocity, "timelineVelocityInput", "velocity", true,
                  IncidentalClick::SelectedVelocityStemDrag},
        BandProbe{songview::TimelineBand::VoiceChanges, "timelineVoiceChangesInput",
                  "voice changes", true, IncidentalClick::BandCenter},
        BandProbe{songview::TimelineBand::Ruler, "timelineRulerInput", "ruler", false,
                  IncidentalClick::PlainRuler},
        BandProbe{songview::TimelineBand::OtherEvents, "timelineOtherEventsInput", "other events",
                  false, IncidentalClick::BandCenter}};

    QString error;
    auto fixture =
        selectionkey::makeRigWorld(projectRoot, songLabel, kTrack, coreNoteSpecs(),
                                   coreRigConfig(std::nullopt), prepareCoreDocument, error);
    if (!selectionkey::check(failures, fixture != nullptr,
                             "could not create cross-band note fixture", "selectionkeycorecheck"))
        return;
    QQuickWindow *const quick = rigWindow(*fixture);
    SongView &songView = rigView(*fixture);
    const std::vector<NoteId> selection{fixture->notes[0], fixture->notes[1]};

    const auto snapshotNotes = [&fixture]() -> std::optional<std::array<DocNote, 3>> {
        std::array<DocNote, 3> snapshot{};
        for (std::size_t index = 0; index < snapshot.size(); ++index) {
            const auto note = selectionkey::noteById(rigDocument(*fixture), fixture->notes[index]);
            if (!note)
                return std::nullopt;
            snapshot[index] = *note;
        }
        return snapshot;
    };
    const auto selectionMatches = [&](const char *label, const char *stage,
                                      const QString &diagnostics = QString{}) {
        const std::vector<NoteId> &actual = songView.selectionModel().noteSelection();
        if (actual == selection)
            return true;
        std::fprintf(stderr,
                     "selectionkeycorecheck: FAIL: %s band %s: actual-selection=%s "
                     "intended-selection=%s%s%s\n",
                     label, stage, qUtf8Printable(describeNoteIds(actual)),
                     qUtf8Printable(describeNoteIds(selection)), diagnostics.isEmpty() ? "" : "; ",
                     diagnostics.isEmpty() ? "" : qUtf8Printable(diagnostics));
        ++failures;
        return false;
    };
    // Every failure names its band and direction and prints the actual and
    // expected state of the affected note. This keeps one bad direction
    // distinguishable from the following checks.
    const auto notesMatch = [&](const char *label, const char *direction,
                                const std::array<DocNote, 3> &snapshot, int keyDelta,
                                int64_t tickDelta) {
        bool all = true;
        for (std::size_t index = 0; index < snapshot.size(); ++index) {
            const DocNote &before = snapshot[index];
            const int keyShift = index < 2 ? keyDelta : 0;
            const int64_t tickShift = index < 2 ? tickDelta : 0;
            const int expectedKey = int(before.key) + keyShift;
            const uint64_t expectedTick = uint64_t(int64_t(before.tick) + tickShift);
            const auto actual =
                selectionkey::noteById(rigDocument(*fixture), fixture->notes[index]);
            if (actual && int(actual->key) == expectedKey && actual->tick == expectedTick)
                continue;
            std::fprintf(stderr,
                         "selectionkeycorecheck: FAIL: %s band %s arrow note[%zu] (%s): "
                         "actual=(present=%d,key=%d,tick=%llu) expected=(key=%d,tick=%llu)\n",
                         label, direction, index, index < 2 ? "selected" : "unselected",
                         actual.has_value() ? 1 : 0, actual ? int(actual->key) : -1,
                         actual ? static_cast<unsigned long long>(actual->tick) : 0ULL, expectedKey,
                         static_cast<unsigned long long>(expectedTick));
            ++failures;
            all = false;
        }
        return all;
    };

    bool bandsClean = true;
    for (const BandProbe &probe : bands) {
        configureDrawerSurface(*fixture, drawerPageForBand(probe.timelineBand));
        songview::TimelineInputItem *const band = rigInput(*fixture, probe.item);
        if (!selectionkey::check(failures, band != nullptr && QTest::qWaitFor([band, quick] {
                                               return !band->bounds().isEmpty() &&
                                                      band->window() == quick;
                                           }),
                                 "Quick band input is unavailable", "selectionkeycorecheck")) {
            bandsClean = false;
            continue;
        }

        // Each click begins from the same eligible note selection. A real
        // selection transition cannot poison the next band's click target.
        songView.selectionModel().setNoteSelection(selection);
        selectionkey::settle();
        std::optional<QPoint> point;
        QString clickDiagnostics;
        switch (probe.click) {
        case IncidentalClick::AutomationLaneGap: {
            const ClickTarget target = emptyAutomationLanePoint(*fixture);
            point = target.point;
            clickDiagnostics = target.diagnostics;
            break;
        }
        case IncidentalClick::SelectedVelocityStemDrag: {
            const ClickTarget target = selectedVelocityStemPoint(*fixture);
            point = target.point;
            clickDiagnostics = target.diagnostics;
            break;
        }
        case IncidentalClick::PlainRuler:
            point = plainRulerPoint(*fixture, band);
            break;
        case IncidentalClick::BandCenter:
            point = band->mapToScene(band->bounds().center()).toPoint();
            break;
        }
        if (clickDiagnostics.isEmpty()) {
            clickDiagnostics =
                QStringLiteral("input-bounds=%1; chosen-window=%2")
                    .arg(describeRect(band->bounds()))
                    .arg(point ? describePoint(*point) : QStringLiteral("unavailable"));
        }
        const bool pointAvailable =
            bandCheck(failures, point.has_value(), probe.label, "Quick click point is unavailable");
        if (!pointAvailable)
            std::fprintf(stderr, "selectionkeycorecheck: %s band click diagnostics: %s\n",
                         probe.label, qUtf8Printable(clickDiagnostics));
        bool delivered = false;
        if (pointAvailable && probe.click == IncidentalClick::SelectedVelocityStemDrag) {
            const QPointF pressPoint(*point);
            const QPointF inputPoint = band->mapFromScene(pressPoint);
            const qreal dragY =
                qMin(band->bounds().bottom() - 2.0,
                     inputPoint.y() + QGuiApplication::styleHints()->startDragDistance() + 4.0);
            const QPoint dragPoint = band->mapToScene(QPointF(inputPoint.x(), dragY)).toPoint();
            delivered = checks::events::primeMouseMove(*quick, *band, *point);
            if (delivered) {
                selectionkey::sendMouseEvent(*quick, QEvent::MouseButtonPress, *point,
                                             Qt::LeftButton);
                selectionkey::sendMouseEvent(*quick, QEvent::MouseMove, dragPoint, Qt::NoButton);
                delivered = QTest::qWaitFor([&] {
                    return songView.userGestureActive() &&
                           songView.selectionModel().noteSelection() == selection;
                });
                selectionkey::sendMouseEvent(*quick, QEvent::MouseButtonRelease, dragPoint,
                                             Qt::LeftButton);
                selectionkey::settle();
            }
            bandCheck(failures, delivered, probe.label,
                      "selected velocity-stem drag did not activate and retain the group");
        } else {
            delivered = pointAvailable &&
                        bandCheck(failures, selectionkey::clickTimelineInput(quick, band, *point),
                                  probe.label, "Quick click did not reach its target band");
        }
        if (pointAvailable && !delivered)
            std::fprintf(stderr, "selectionkeycorecheck: %s band input diagnostics: %s\n",
                         probe.label, qUtf8Printable(clickDiagnostics));
        if (delivered) {
            if (probe.clickTakesFocus)
                bandCheck(failures, band->hasActiveFocus(), probe.label,
                          "Quick band input did not focus its band");
            if (probe.click == IncidentalClick::AutomationLaneGap) {
                const bool noReplacementRange = bandCheck(
                    failures, !songView.selectionModel().timeSelection().active(), probe.label,
                    "the incidental automation click made a replacement range");
                if (!noReplacementRange)
                    std::fprintf(stderr,
                                 "selectionkeycorecheck: automation band click diagnostics: %s\n",
                                 qUtf8Printable(clickDiagnostics));
            }
            if (probe.click == IncidentalClick::AutomationLaneGap ||
                probe.click == IncidentalClick::SelectedVelocityStemDrag)
                selectionMatches(probe.label, "after selection-preserving input", clickDiagnostics);
        }

        // Ruler and other-events clicks intentionally do not focus. Focus is
        // therefore explicit for every band's keyboard contract rather than
        // accidentally inherited from the preceding loop iteration.
        if (!bandCheck(failures, focus(songView, probe.timelineBand), probe.label,
                       "could not stage band focus for arrows")) {
            bandsClean = false;
            continue;
        }
        songView.selectionModel().setNoteSelection(selection);
        selectionkey::settle();

        const auto arrowMoves = [&](Qt::Key key, const char *direction) {
            // Restage before each direction so an earlier failed command
            // cannot turn the remaining direction verdicts into cascades.
            songView.selectionModel().setNoteSelection(selection);
            selectionkey::settle();
            const auto before = snapshotNotes();
            if (!bandCheck(failures, before.has_value(), probe.label,
                           "a cross-band fixture note vanished before an arrow"))
                return false;
            const int64_t tick = int64_t(before->at(0).tick);
            const int64_t tickDelta =
                key == Qt::Key_Right
                    ? int64_t(songView.grid().snapTickUp(double(tick) + 1.0)) - tick
                : key == Qt::Key_Left
                    ? int64_t(songView.grid().snapTickDown(double(tick) - 1.0)) - tick
                    : 0;
            const int keyDelta = key == Qt::Key_Up ? 1 : key == Qt::Key_Down ? -1 : 0;
            if (!deliverKey(quick, key)) {
                std::fprintf(stderr,
                             "selectionkeycorecheck: FAIL: %s band %s arrow: Quick window "
                             "did not accept the key\n",
                             probe.label, direction);
                ++failures;
                return false;
            }
            const bool notesMoved =
                notesMatch(probe.label, direction, *before, keyDelta, tickDelta);
            return selectionMatches(probe.label, direction) && notesMoved;
        };
        bandsClean = arrowMoves(Qt::Key_Up, "Up") && bandsClean;
        bandsClean = arrowMoves(Qt::Key_Down, "Down") && bandsClean;
        bandsClean = arrowMoves(Qt::Key_Right, "Right") && bandsClean;
        bandsClean = arrowMoves(Qt::Key_Left, "Left") && bandsClean;
    }

    // The arrows route through the production mergeable-move history, and a
    // clean run leaves every band's move command cancelled out, so one extra
    // transposing press proves increment/undo/redo preservation end to end.
    // With a dirty history the extra undo could revert an unrelated leftover
    // command; the band failures above already record that outcome.
    if (bandsClean) {
        songView.selectionModel().setNoteSelection(selection);
        selectionkey::settle();
        const std::optional<std::array<DocNote, 3>> beforeUndo = snapshotNotes();
        if (selectionkey::check(failures, beforeUndo.has_value(),
                                "the fixture notes vanished before the "
                                "undo proof",
                                "selectionkeycorecheck") &&
            selectionkey::check(failures, deliverKey(quick, Qt::Key_Up),
                                "Quick window did not accept the undo-proof key",
                                "selectionkeycorecheck")) {
            notesMatch("undo proof", "Up", *beforeUndo, +1, 0);
            rigDocument(*fixture).undoStack()->undo();
            notesMatch("undo proof", "Undo", *beforeUndo, 0, 0);
            rigDocument(*fixture).undoStack()->redo();
            notesMatch("undo proof", "Redo", *beforeUndo, +1, 0);
            selectionkey::check(failures, deliverKey(quick, Qt::Key_Down),
                                "Quick window did not accept the undo-proof key",
                                "selectionkeycorecheck");
            notesMatch("undo proof", "Down", *beforeUndo, 0, 0);
        }
    }
}

void drawerTransposeAuditionReleasesOnPhysicalKeyUp(int &failures, const QString &projectRoot,
                                                    const QString &songLabel)
{
    QString error;
    auto fixture = selectionkey::makeRigWorld(projectRoot, songLabel, kTrack, coreNoteSpecs(),
                                              coreRigConfig(EditorDrawerPage::Automations),
                                              prepareCoreDocument, error);
    if (!selectionkey::check(failures, fixture != nullptr,
                             "could not create drawer-audition fixture", "selectionkeycorecheck"))
        return;
    QQuickWindow *const quick = rigWindow(*fixture);
    SongView &songView = rigView(*fixture);
    if (!selectionkey::check(
            failures,
            selectionkey::focusTimelineInput(quick, rigInput(*fixture, "timelineAutomationInput")),
            "could not focus the automation drawer for transpose audition",
            "selectionkeycorecheck")) {
        return;
    }
    songView.selectionModel().setNoteSelection({fixture->notes[0]});
    std::vector<std::pair<int, int>> auditions;
    const QMetaObject::Connection connection = QObject::connect(
        &songView, &SongView::auditionNote, &songView,
        [&auditions](int, int key, int velocity) { auditions.emplace_back(key, velocity); });

    selectionkey::check(failures, deliverKeyEvent(quick, QEvent::KeyPress, Qt::Key_Up, false),
                        "drawer transpose key-down did not reach the Quick window",
                        "selectionkeycorecheck");
    const std::size_t started = auditions.size();
    selectionkey::check(failures, started == 1 && auditions.back().second > 0,
                        "drawer transpose key-down did not start a live audition",
                        "selectionkeycorecheck");

    selectionkey::check(failures, deliverKeyEvent(quick, QEvent::KeyRelease, Qt::Key_Up, true),
                        "drawer autorepeat key-up did not reach the Quick window",
                        "selectionkeycorecheck");
    selectionkey::check(failures, auditions.size() == started,
                        "drawer autorepeat key-up prematurely ended the live audition",
                        "selectionkeycorecheck");

    selectionkey::check(failures, deliverKeyEvent(quick, QEvent::KeyRelease, Qt::Key_Up, false),
                        "drawer physical key-up did not reach the Quick window",
                        "selectionkeycorecheck");
    // The shared release path ends the audition with the velocity-0
    // release of the engine's single preview slot; that emission repeats
    // the slot, not the sounding key (AudioEngine::previewNote replaces
    // whatever preview sounded).
    selectionkey::check(failures, auditions.size() == started + 1 && auditions.back().second == 0,
                        "drawer physical key-up did not end the transposed note audition",
                        "selectionkeycorecheck");
    QObject::disconnect(connection);
}

void automationRangeAndReboundDelete(int &failures, const QString &projectRoot,
                                     const QString &songLabel)
{
    QString error;
    auto fixture = selectionkey::makeRigWorld(projectRoot, songLabel, kTrack, coreNoteSpecs(),
                                              coreRigConfig(EditorDrawerPage::Automations),
                                              prepareCoreDocument, error);
    if (!selectionkey::check(failures, fixture != nullptr,
                             "could not create automation-range fixture", "selectionkeycorecheck"))
        return;
    QQuickWindow *const quick = rigWindow(*fixture);
    songview::TimelineInputItem *const automation = rigInput(*fixture, "timelineAutomationInput");
    const auto points = laneWindowPoints<2>(
        *fixture,
        std::array<std::pair<uint64_t, int>, 2>{{{kFirstPointTick, 80}, {kOutsidePointTick, 80}}});
    if (!selectionkey::check(failures, quick && automation && points,
                             "automation Quick range surface is unavailable",
                             "selectionkeycorecheck")) {
        return;
    }

    SongView &songView = rigView(*fixture);
    if (!selectionkey::check(failures, focus(songView, songview::TimelineBand::Automation),
                             "could not stage automation focus for range delivery",
                             "selectionkeycorecheck")) {
        return;
    }
    songView.selectionModel().setNoteSelection({fixture->notes[0]});
    selectionkey::settle();
    const bool startDelivered = selectionkey::check(
        failures, selectionkey::moveMouseToTimelineInput(quick, automation, points->at(0)),
        "automation range start did not reach the Quick input item", "selectionkeycorecheck");
    if (startDelivered) {
        QTest::mousePress(quick, Qt::RightButton, Qt::NoModifier, points->at(0));
        QTest::mouseMove(quick, points->at(1));
        QTest::mouseRelease(quick, Qt::RightButton, Qt::NoModifier, points->at(1));
        selectionkey::settle();
    }
    const auto &selection = songView.selectionModel().timeSelection();
    const bool rangeReady =
        selection.active() && selection.startTick == kFirstPointTick &&
        selection.endTick == kOutsidePointTick &&
        selection.scope == songview::EditorSelectionModel::TimeSelection::Lanes &&
        selection.lanes == std::vector<std::pair<int, uint8_t>>{{kTrack, kController}} &&
        songView.selectionModel().noteSelection().empty();
    if (!selectionkey::check(
            failures, rangeReady,
            "actual automation range did not replace note selection with lane scope",
            "selectionkeycorecheck"))
        return;

    KeymapRestore restore;
    restore.registry().setBinding(QStringLiteral("roll.delete"),
                                  QKeySequence(QStringLiteral("Alt+Backspace")));
    selectionkey::check(failures, deliverKey(quick, Qt::Key_Backspace, Qt::AltModifier),
                        "rebound Delete did not reach the Quick automation surface",
                        "selectionkeycorecheck");
    selectionkey::check(
        failures,
        !rigDocument(*fixture).findLanePoint(kTrack, kController, kFirstPointTick, nullptr) &&
            !rigDocument(*fixture).findLanePoint(kTrack, kController, kInsidePointTick, nullptr) &&
            !rigDocument(*fixture).findLanePoint(kTrack, kController, kSecondPointTick, nullptr) &&
            rigDocument(*fixture).findLanePoint(kTrack, kController, kOutsidePointTick, nullptr),
        "automation range Delete did not affect only its selected points", "selectionkeycorecheck");
}

void deletePrecedenceAndPencilHover(int &failures, const QString &projectRoot,
                                    const QString &songLabel)
{
    KeymapRestore restore;
    restore.registry().setBinding(QStringLiteral("roll.delete"),
                                  QKeySequence(QStringLiteral("Alt+Backspace")));

    const auto exercise = [&](auto &&prepare, auto &&verify, const char *label) {
        QString error;
        auto fixture = selectionkey::makeRigWorld(projectRoot, songLabel, kTrack, coreNoteSpecs(),
                                                  coreRigConfig(EditorDrawerPage::Automations),
                                                  prepareCoreDocument, error);
        if (!selectionkey::check(failures, fixture != nullptr, label, "selectionkeycorecheck"))
            return;
        QQuickWindow *const quick = rigWindow(*fixture);
        songview::TimelineInputItem *const automation =
            rigInput(*fixture, "timelineAutomationInput");
        const auto point = laneWindowPoint(*fixture, kSecondPointTick, 64);
        if (!selectionkey::check(failures, quick && automation && point,
                                 "automation hover fixture is unavailable",
                                 "selectionkeycorecheck"))
            return;
        AutomationCanvas *const canvas =
            rigView(*fixture).editorDrawer()->automationPage()->canvas();
        canvas->setPencilMode(true);
        if (!selectionkey::check(failures,
                                 focus(rigView(*fixture), songview::TimelineBand::Automation),
                                 "could not stage automation focus for pencil-hover Delete",
                                 "selectionkeycorecheck"))
            return;
        if (!selectionkey::check(
                failures, selectionkey::moveMouseToTimelineInput(quick, automation, *point),
                "automation hover did not reach the Quick input item", "selectionkeycorecheck"))
            return;
        prepare(*fixture);
        selectionkey::settle();
        const QByteArray before = rigDocument(*fixture).smf().write();
        selectionkey::check(failures, deliverKey(quick, Qt::Key_Backspace, Qt::AltModifier),
                            "rebound Delete did not reach the pencil-hover surface",
                            "selectionkeycorecheck");
        verify(*fixture, before);
    };

    exercise(
        [](RigWorld &fixture) {
            rigView(fixture).selectionModel().setNoteSelection({fixture.notes[0]});
        },
        [&](RigWorld &fixture, const QByteArray &) {
            selectionkey::check(failures,
                                !selectionkey::noteExists(rigDocument(fixture), fixture.notes[0]) &&
                                    rigDocument(fixture).findLanePoint(kTrack, kController,
                                                                       kSecondPointTick, nullptr),
                                "selected notes did not win over pencil hover Delete",
                                "selectionkeycorecheck");
        },
        "could not create note-precedence fixture");

    exercise(
        [](RigWorld &fixture) {
            rigView(fixture).selectionModel().setTimeSelection(
                trackRange(kFirstNoteTick, kFirstNoteTick + 24));
        },
        [&](RigWorld &fixture, const QByteArray &) {
            selectionkey::check(failures,
                                !selectionkey::noteExists(rigDocument(fixture), fixture.notes[0]) &&
                                    rigDocument(fixture).findLanePoint(kTrack, kController,
                                                                       kSecondPointTick, nullptr),
                                "track time selection did not win over pencil hover Delete",
                                "selectionkeycorecheck");
        },
        "could not create time-precedence fixture");

    exercise(
        [](RigWorld &) {},
        [&](RigWorld &fixture, const QByteArray &) {
            selectionkey::check(
                failures,
                !rigDocument(fixture).findLanePoint(kTrack, kController, kSecondPointTick, nullptr),
                "eligible pencil hover Delete did not remove the hovered point",
                "selectionkeycorecheck");
        },
        "could not create hover-delete fixture");

    QString error;
    auto missFixture = selectionkey::makeRigWorld(projectRoot, songLabel, kTrack, coreNoteSpecs(),
                                                  coreRigConfig(EditorDrawerPage::Automations),
                                                  prepareCoreDocument, error);
    if (!selectionkey::check(failures, missFixture != nullptr,
                             "could not create hover-miss fixture", "selectionkeycorecheck"))
        return;
    QQuickWindow *const quick = rigWindow(*missFixture);
    songview::TimelineInputItem *const automation =
        rigInput(*missFixture, "timelineAutomationInput");
    const auto miss = laneWindowPoint(*missFixture, kOutsidePointTick + 24, 1);
    if (!selectionkey::check(failures, quick && automation && miss,
                             "automation hover-miss surface is unavailable",
                             "selectionkeycorecheck"))
        return;
    rigView(*missFixture).editorDrawer()->automationPage()->canvas()->setPencilMode(true);
    if (!selectionkey::check(
            failures, focus(rigView(*missFixture), songview::TimelineBand::Automation),
            "could not stage automation focus for pencil-hover miss", "selectionkeycorecheck"))
        return;
    if (!selectionkey::check(
            failures, selectionkey::moveMouseToTimelineInput(quick, automation, *miss),
            "automation hover miss did not reach the Quick input item", "selectionkeycorecheck"))
        return;
    const QByteArray before = rigDocument(*missFixture).smf().write();
    selectionkey::check(failures, deliverKey(quick, Qt::Key_Backspace, Qt::AltModifier),
                        "rebound Delete did not reach the pencil-hover miss surface",
                        "selectionkeycorecheck");
    selectionkey::check(failures, rigDocument(*missFixture).smf().write() == before,
                        "pencil hover miss Delete changed the document", "selectionkeycorecheck");
}

void laneNudgeConsumesVerticalAndMovesHorizontal(int &failures, const QString &projectRoot,
                                                 const QString &songLabel)
{
    QString error;
    auto fixture = selectionkey::makeRigWorld(projectRoot, songLabel, kTrack, coreNoteSpecs(),
                                              coreRigConfig(EditorDrawerPage::Automations),
                                              prepareCoreDocument, error);
    if (!selectionkey::check(failures, fixture != nullptr, "could not create lane-nudge fixture",
                             "selectionkeycorecheck"))
        return;
    QQuickWindow *const quick = rigWindow(*fixture);
    if (!selectionkey::check(failures, focus(rigView(*fixture), songview::TimelineBand::Automation),
                             "could not focus the automation Quick band", "selectionkeycorecheck"))
        return;
    SongView &songView = rigView(*fixture);
    songView.selectionModel().setTimeSelection(laneRange(kSecondPointTick, kOutsidePointTick));
    const QByteArray beforeVertical = rigDocument(*fixture).smf().write();
    deliverKey(quick, Qt::Key_Up);
    selectionkey::check(failures, rigDocument(*fixture).smf().write() == beforeVertical,
                        "lane-scoped vertical arrow mutated automation or hidden notes",
                        "selectionkeycorecheck");

    const uint64_t destination = songView.grid().snapTickUp(double(kSecondPointTick) + 1.0);
    deliverKey(quick, Qt::Key_Right);
    const auto &moved = songView.selectionModel().timeSelection();
    selectionkey::check(
        failures,
        rigDocument(*fixture).findLanePoint(kTrack, kController, destination, nullptr) &&
            !rigDocument(*fixture).findLanePoint(kTrack, kController, kSecondPointTick, nullptr) &&
            moved.startTick == destination &&
            moved.endTick == kOutsidePointTick + destination - kSecondPointTick,
        "lane-scoped horizontal arrow did not nudge points and the selected interval",
        "selectionkeycorecheck");
}
void keyboardClipboardParity(int &failures, const QString &projectRoot, const QString &songLabel)
{
    const auto copy = firstBinding(QStringLiteral("roll.copy"));
    const auto paste = firstBinding(QStringLiteral("roll.paste"));
    if (!selectionkey::check(failures, copy.has_value() && paste.has_value(),
                             "keyboard clipboard commands have no single-key binding",
                             "selectionkeycorecheck")) {
        return;
    }
    const auto pasteFrom = [&](songview::TimelineBand band, const char *missing,
                               const char *failure) {
        QString error;
        auto fixture = selectionkey::makeRigWorld(projectRoot, songLabel, kTrack, coreNoteSpecs(),
                                                  coreRigConfig(drawerPageForBand(band)),
                                                  prepareCoreDocument, error);
        if (!selectionkey::check(failures, fixture != nullptr, missing, "selectionkeycorecheck"))
            return;
        SongView &songView = rigView(*fixture);
        QQuickWindow *const quick = rigWindow(*fixture);
        songView.selectionModel().setNoteSelection({fixture->notes[0]});
        if (!selectionkey::check(failures, focus(songView, songview::TimelineBand::Roll),
                                 "could not focus the roll for keyboard Copy",
                                 "selectionkeycorecheck")) {
            return;
        }
        deliverKey(quick, copy->key(), copy->keyboardModifiers());
        songView.selectionModel().clearNoteSelection();
        songView.commitEditCursor(kPasteTick);
        if (!selectionkey::check(failures, focus(songView, band),
                                 "could not focus paste destination band", "selectionkeycorecheck"))
            return;
        deliverKey(quick, paste->key(), paste->keyboardModifiers());
        selectionkey::check(failures,
                            selectionkey::noteExists(rigDocument(*fixture), kTrack, kPasteTick, 60),
                            failure, "selectionkeycorecheck");
    };
    pasteFrom(songview::TimelineBand::Roll, "could not create roll clipboard fixture",
              "keyboard Paste in the roll did not use the copied note clip");
    pasteFrom(songview::TimelineBand::Automation, "could not create drawer clipboard fixture",
              "keyboard Paste in the drawer did not match the roll destination");
}

void selectAllFromEmptyAndTimeSelection(int &failures, const QString &projectRoot,
                                        const QString &songLabel)
{
    const auto shortcut = firstBinding(QStringLiteral("roll.select_all"));
    if (!selectionkey::check(failures, shortcut.has_value(),
                             "Select All Notes has no single-key binding", "selectionkeycorecheck"))
        return;
    QString error;
    auto fixture = selectionkey::makeRigWorld(projectRoot, songLabel, kTrack, coreNoteSpecs(),
                                              coreRigConfig(EditorDrawerPage::Velocity),
                                              prepareCoreDocument, error);
    if (!selectionkey::check(failures, fixture != nullptr, "could not create Select All fixture",
                             "selectionkeycorecheck"))
        return;
    SongView &songView = rigView(*fixture);
    QQuickWindow *const quick = rigWindow(*fixture);
    songView.selectionModel().clearBothSelections();
    selectionkey::settle();
    selectionkey::check(
        failures,
        selectionkey::focusTimelineInput(quick, rigInput(*fixture, "timelineVelocityInput")),
        "could not focus the velocity band before Select All", "selectionkeycorecheck");
    if (!selectionkey::check(failures, focus(songView, songview::TimelineBand::Velocity),
                             "could not stage velocity focus before Select All",
                             "selectionkeycorecheck"))
        return;
    selectionkey::check(failures, deliverKey(quick, shortcut->key(), shortcut->keyboardModifiers()),
                        "Select All key did not reach the velocity band", "selectionkeycorecheck");
    // >= is deliberate: the project fixture carries pre-existing primary-track notes.
    selectionkey::check(failures,
                        songView.selectionModel().noteSelection().size() >= fixture->notes.size() &&
                            !songView.selectionModel().timeSelection().active(),
                        "Select All Notes from empty selection did not select primary-track notes",
                        "selectionkeycorecheck");

    songView.selectionModel().setTimeSelection(trackRange(kFirstNoteTick, kFirstNoteTick + 48));
    selectionkey::settle();
    configureDrawerSurface(*fixture, std::nullopt);
    songview::TimelineInputItem *const ruler = rigInput(*fixture, "timelineRulerInput");
    const auto rulerPoint = ruler ? plainRulerPoint(*fixture, ruler) : std::optional<QPoint>{};
    selectionkey::check(
        failures,
        ruler && rulerPoint && selectionkey::clickTimelineInput(quick, ruler, *rulerPoint),
        "could not deliver the ruler click before Select All", "selectionkeycorecheck");
    if (!selectionkey::check(failures, focus(songView, songview::TimelineBand::Ruler),
                             "could not stage ruler focus before Select All",
                             "selectionkeycorecheck"))
        return;
    selectionkey::check(failures, deliverKey(quick, shortcut->key(), shortcut->keyboardModifiers()),
                        "Select All key did not reach the ruler band", "selectionkeycorecheck");
    // >= is deliberate: the project fixture carries pre-existing primary-track notes.
    selectionkey::check(failures,
                        songView.selectionModel().noteSelection().size() >= fixture->notes.size() &&
                            !songView.selectionModel().timeSelection().active(),
                        "Select All Notes did not replace a time selection from incidental chrome",
                        "selectionkeycorecheck");
}

} // namespace

int runSelectionKeyCoreCheck(const QString &projectRoot, const QString &songLabel)
{
    KeymapRestore keymapRestore;
    keymapRestore.registry().resetAll();
    int failures = 0;
    arrowsFollowNotesAcrossClickedBands(failures, projectRoot, songLabel);
    drawerTransposeAuditionReleasesOnPhysicalKeyUp(failures, projectRoot, songLabel);
    automationRangeAndReboundDelete(failures, projectRoot, songLabel);
    deletePrecedenceAndPencilHover(failures, projectRoot, songLabel);
    laneNudgeConsumesVerticalAndMovesHorizontal(failures, projectRoot, songLabel);
    keyboardClipboardParity(failures, projectRoot, songLabel);
    selectAllFromEmptyAndTimeSelection(failures, projectRoot, songLabel);
    std::fprintf(stderr, "selectionkeycorecheck: %s\n", failures == 0 ? "PASS" : "FAIL");
    return failures == 0 ? 0 : 1;
}
