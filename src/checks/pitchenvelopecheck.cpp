#include "pitchenvelopecheck.hpp"
#include "pitchenvelopecheck_persistence.hpp"

#include "ui/m4asemantics.h"
#include "ui/songview/pitchenvelopemapping.h"

#include <QCoreApplication>
#include <QEvent>
#include <QLabel>
#include <QMouseEvent>
#include <QPoint>
#include <QPointF>
#include <QToolButton>
#include <QWidget>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <optional>
#include <vector>

extern "C" {
#include "m4a_engine.h"
}

namespace {

constexpr uint8_t kBendRangeController = 0x14;
constexpr int kSourceProgram = 124;
constexpr int kSecondProgram = 123;
constexpr int kWaveProgram = 122;
constexpr int kIneligibleProgram = 125;

void sendCurveMouse(QWidget *widget, QEvent::Type type, QPoint position, Qt::MouseButton button,
                    Qt::MouseButtons buttons)
{
    QMouseEvent event(type, QPointF(position), QPointF(widget->mapToGlobal(position)), button,
                      buttons, Qt::NoModifier);
    QCoreApplication::sendEvent(widget, &event);
}

struct PitchEnvelopeFixture {
    int undoIndex = 0;
    SongView::ViewState beforeViewState;
    int firstTrack = -1;
    int secondTrack = -1;
    LoadedVoiceGroup voicegroup{};
    std::optional<DocNote> templateSource;
    std::optional<DocNote> sourcePeer;
    std::optional<DocNote> clippedProjection;
    std::optional<DocNote> clippingNote;
    std::optional<DocNote> finalProjection;
    std::optional<DocNote> finalPeer;
    uint64_t sourceEndTick = 0;
    uint64_t clippedWindowEndTick = 0;
    uint64_t finalEndTick = 0;
    uint64_t preservedGapTick = 0;
    int preservedGapValue = 347;
    uint64_t postSpanTick = 0;
    int postSpanValue = -521;
    std::vector<pitchenvelopecheck::PitchEnvelopeProjection> fullProjections;
};

class PitchEnvelopeCheckContext final
{
  public:
    PitchEnvelopeCheckContext(SongDocument &document, SongView &view, const DocNote &fixtureNote,
                              const QString &songLabel)
        : m_document(document)
        , m_view(view)
        , m_fixtureNote(fixtureNote)
        , m_songLabel(songLabel)
        , m_entryVoicegroup(view.voicegroup())
    {}

    int run()
    {
        runEligibilityTruthTable();
        const PitchEnvelopeFixture fixture = prepareFixture();
        m_view.setVoicegroup(&fixture.voicegroup);
        drainQueuedEvents();
        runCreationAndHeaderChecks(fixture);
        const auto persistence = runGestureAndUndoChecks(fixture);
        if (persistence)
            runTrackScopeChecks(fixture);
        runMissingVoiceCheck(fixture);
        restoreFixture(fixture);
        return m_failures;
    }

  private:
    void fail(const char *what)
    {
        std::fprintf(stderr, "rollcheck: FAIL %s: %s\n", qUtf8Printable(m_songLabel), what);
        m_failures++;
    }

    static void drainQueuedEvents()
    {
        QCoreApplication::processEvents();
        QCoreApplication::processEvents();
    }

    QToolButton *pitchEnvelopeButtonFor(int track) const
    {
        auto *header = m_view.findChild<QWidget *>(QStringLiteral("trackHeaderRow%1").arg(track));
        return header ? header->findChild<QToolButton *>(QStringLiteral("pitchEnvelopeButton"))
                      : nullptr;
    }

    bool pitchEnvelopeOpenFor(int track) const
    {
        const std::optional<int> openTrack = m_view.pitchEnvelopeTrack();
        return openTrack && *openTrack == track;
    }

    static songview::EditableCurveGraph *graphFor(QWidget *host)
    {
        auto *widget =
            host ? host->findChild<QWidget *>(QStringLiteral("pitchEnvelopeGraph")) : nullptr;
        return dynamic_cast<songview::EditableCurveGraph *>(widget);
    }

    std::optional<DocNote> addEnvelopeNote(int track, uint64_t tick)
    {
        for (int key = 0; key < 128; key++) {
            DocNote note;
            if (m_document.findNote(track, tick, uint8_t(key), &note))
                continue;
            m_document.addNote(track, tick, uint8_t(key),
                               std::max<uint32_t>(1, m_fixtureNote.duration), 100);
            if (m_document.findNote(track, tick, uint8_t(key), &note))
                return note;
        }
        return std::nullopt;
    }

    uint64_t fixtureStartTick(int track) const
    {
        uint64_t lastTick = 0;
        for (const DocNote &note : m_document.notesForTrack(track))
            lastTick = std::max(lastTick, note.tick + uint64_t(note.duration));
        const auto considerLane = [&](uint8_t controller) {
            for (const DocLanePoint &point : m_document.lanePoints(track, controller))
                lastTick = std::max(lastTick, point.tick);
        };
        considerLane(DOC_CC_BEND);
        considerLane(DOC_CC_VOICE);
        considerLane(kBendRangeController);
        return lastTick + 2 * std::max<uint64_t>(1, m_document.ticksPerClock());
    }

    PitchEnvelopeFixture prepareFixture()
    {
        PitchEnvelopeFixture fixture;
        fixture.undoIndex = m_document.undoStack()->index();
        fixture.beforeViewState = m_view.viewState();
        fixture.firstTrack = m_view.selectionModel().primaryTrack();
        fixture.secondTrack = fixture.firstTrack == 0 ? 1 : 0;
        if (fixture.firstTrack < 0) {
            fail("no selected track was available for pitch-envelope checks");
            return fixture;
        }
        if (fixture.secondTrack >= m_document.engineTrackCount()) {
            if (!m_document.canAddTrack()) {
                fail("could not create a second track for pitch-envelope checks");
                fixture.secondTrack = -1;
            } else {
                fixture.secondTrack = m_document.addTrack(kSourceProgram);
            }
        }
        for (ToneData &voice : fixture.voicegroup.voices)
            voice.type = VOICE_SQUARE_1;
        fixture.voicegroup.voices[kSecondProgram].type = VOICE_SQUARE_2;
        fixture.voicegroup.voices[kWaveProgram].type = VOICE_PROGRAMMABLE_WAVE;
        fixture.voicegroup.voices[kIneligibleProgram].type = VOICE_NOISE;

        if (!m_view.timeline()) {
            fail("pitch-envelope checks had no timeline");
            return fixture;
        }
        const uint64_t grid = std::max<uint64_t>(1, m_document.ticksPerClock());
        const uint64_t sourceTick = fixtureStartTick(fixture.firstTrack);
        m_document.addLanePoint(fixture.firstTrack, DOC_CC_VOICE, sourceTick, kSourceProgram);
        m_document.addLanePoint(fixture.firstTrack, kBendRangeController, sourceTick, 2);
        fixture.templateSource = addEnvelopeNote(fixture.firstTrack, sourceTick);
        fixture.sourcePeer = addEnvelopeNote(fixture.firstTrack, sourceTick);
        if (!fixture.templateSource || !fixture.sourcePeer) {
            fail("could not create same-tick eligible pitch-envelope fixture notes");
            return fixture;
        }
        fixture.sourceEndTick = songview::pitch_envelope::creationEndTick(
            m_view.timeline(), fixture.templateSource->tick);
        if (fixture.sourceEndTick <= fixture.templateSource->tick + 1) {
            fail("pitch-envelope fixture did not have a usable 100ms source interval");
            return fixture;
        }

        const uint64_t clippedTick = fixture.sourceEndTick + 2 * grid;
        m_document.addLanePoint(fixture.firstTrack, DOC_CC_VOICE, clippedTick, kSecondProgram);
        m_document.addLanePoint(fixture.firstTrack, kBendRangeController, clippedTick, 12);
        fixture.clippedProjection = addEnvelopeNote(fixture.firstTrack, clippedTick);
        if (!fixture.clippedProjection) {
            fail("could not create clipped eligible pitch-envelope fixture note");
            return fixture;
        }
        fixture.clippedWindowEndTick = songview::pitch_envelope::creationEndTick(
            m_view.timeline(), fixture.clippedProjection->tick);
        const uint64_t clippingTick =
            fixture.clippedProjection->tick +
            (fixture.clippedWindowEndTick - fixture.clippedProjection->tick) / 2;
        if (clippingTick <= fixture.clippedProjection->tick ||
            clippingTick >= fixture.clippedWindowEndTick) {
            fail("pitch-envelope fixture did not have a usable clipping interval");
            return fixture;
        }
        m_document.addLanePoint(fixture.firstTrack, DOC_CC_VOICE, clippingTick, kIneligibleProgram);
        fixture.clippingNote = addEnvelopeNote(fixture.firstTrack, clippingTick);
        if (!fixture.clippingNote) {
            fail("could not create ineligible clipping pitch-envelope fixture note");
            return fixture;
        }

        const uint64_t finalTick =
            songview::pitch_envelope::creationEndTick(m_view.timeline(), clippingTick) + 2 * grid;
        m_document.addLanePoint(fixture.firstTrack, DOC_CC_VOICE, finalTick, kWaveProgram);
        m_document.addLanePoint(fixture.firstTrack, kBendRangeController, finalTick, 7);
        fixture.finalProjection = addEnvelopeNote(fixture.firstTrack, finalTick);
        fixture.finalPeer = addEnvelopeNote(fixture.firstTrack, finalTick);
        if (!fixture.finalProjection || !fixture.finalPeer) {
            fail("could not create final same-tick pitch-envelope fixture notes");
            return fixture;
        }
        fixture.finalEndTick = songview::pitch_envelope::creationEndTick(
            m_view.timeline(), fixture.finalProjection->tick);
        if (fixture.finalEndTick <= fixture.finalProjection->tick + 1) {
            fail("pitch-envelope fixture did not have a usable final projection interval");
            return fixture;
        }
        m_document.addLanePoint(fixture.firstTrack, kBendRangeController,
                                fixture.finalProjection->tick +
                                    (fixture.finalEndTick - fixture.finalProjection->tick) / 2,
                                12);
        fixture.preservedGapTick = fixture.sourceEndTick + grid;
        m_document.writeLanePoints(fixture.firstTrack, DOC_CC_BEND, fixture.templateSource->tick,
                                   fixture.finalEndTick, {});
        m_document.addLanePoint(fixture.firstTrack, DOC_CC_BEND, fixture.preservedGapTick,
                                fixture.preservedGapValue);
        fixture.postSpanTick = fixture.finalEndTick + grid;
        m_document.addLanePoint(fixture.firstTrack, DOC_CC_BEND, fixture.postSpanTick,
                                fixture.postSpanValue);
        fixture.fullProjections = {
            {*fixture.templateSource, fixture.sourceEndTick, fixture.sourceEndTick, 2},
            {*fixture.finalProjection, fixture.finalEndTick, fixture.finalEndTick, 7}};

        if (fixture.secondTrack >= 0) {
            m_document.addLanePoint(fixture.secondTrack, DOC_CC_VOICE, 0, kSourceProgram);
            if (!addEnvelopeNote(fixture.secondTrack, sourceTick))
                fail("could not create an eligible pitch-envelope note on the second track");
        }
        return fixture;
    }

    void runCreationAndHeaderChecks(const PitchEnvelopeFixture &fixture)
    {
        if (fixture.firstTrack < 0)
            return;
        m_view.selectTrack(fixture.firstTrack);
        m_view.selectionModel().clearNoteSelection();
        if (fixture.clippingNote)
            m_view.setEditCursorTick(fixture.clippingNote->tick);
        m_view.setPlayheadSample(0, false);
        drainQueuedEvents();
        (void)m_view.grab();
        if (!m_view.trackHasPitchEnvelopeVoice(fixture.firstTrack) ||
            !m_view.pitchEnvelopeCreationEnabled(fixture.firstTrack)) {
            fail("eligible track did not enable pitch-envelope authoring without a note selection");
        }
        auto *firstButton = pitchEnvelopeButtonFor(fixture.firstTrack);
        if (!firstButton || firstButton->isHidden() || !firstButton->isEnabled()) {
            fail("eligible track did not expose an enabled pitch-envelope button");
        } else {
            firstButton->click();
            auto *host = m_view.findChild<QWidget *>(QStringLiteral("pitchEnvelopeHost"));
            auto *graph = graphFor(host);
            if (!pitchEnvelopeOpenFor(fixture.firstTrack) || !firstButton->isChecked() || !host ||
                host->isHidden() || !graph || graph->isHidden() || !graph->isEnabled()) {
                fail("track pitch-envelope editor did not open enabled without a note selection");
            }
            firstButton->click();
            if (m_view.pitchEnvelopeTrack())
                fail("pitch-envelope button did not close its selected track");
            firstButton->click();
            if (!pitchEnvelopeOpenFor(fixture.firstTrack) || !firstButton->isChecked())
                fail("pitch-envelope button did not re-open its selected track");
        }
        if (fixture.secondTrack < 0)
            return;
        m_view.selectTrack(fixture.secondTrack);
        m_view.selectionModel().clearNoteSelection();
        drainQueuedEvents();
        if (m_view.pitchEnvelopeTrack())
            fail("selecting another track left its pitch envelope open");
        if (!m_view.pitchEnvelopeCreationEnabled(fixture.secondTrack))
            fail("second eligible track did not enable authoring without a note selection");
        auto *secondButton = pitchEnvelopeButtonFor(fixture.secondTrack);
        if (!secondButton || secondButton->isHidden() || !secondButton->isEnabled()) {
            fail("second eligible track did not expose an enabled pitch-envelope button");
        } else {
            secondButton->click();
            drainQueuedEvents();
            auto *host = m_view.findChild<QWidget *>(QStringLiteral("pitchEnvelopeHost"));
            auto *graph = graphFor(host);
            auto *status = m_view.findChild<QLabel *>(QStringLiteral("pitchEnvelopeStatus"));
            if (!pitchEnvelopeOpenFor(fixture.secondTrack) || !secondButton->isChecked() || !host ||
                host->isHidden() || !graph || graph->isHidden() || !graph->isEnabled() || !status ||
                status->isHidden() || status->text().isEmpty()) {
                fail("second track pitch-envelope editor did not remain enabled without a note "
                     "selection");
            }
        }
        m_document.addLanePoint(fixture.secondTrack, DOC_CC_VOICE,
                                fixture.templateSource ? fixture.templateSource->tick : 0,
                                kSourceProgram);
        drainQueuedEvents();
        secondButton = pitchEnvelopeButtonFor(fixture.secondTrack);
        if (!pitchEnvelopeOpenFor(fixture.secondTrack) || !secondButton ||
            secondButton->isHidden() || !secondButton->isEnabled() || !secondButton->isChecked()) {
            fail("pitch-envelope checked state did not survive a header rebuild");
        }
        m_view.selectTrack(fixture.firstTrack);
        m_view.selectionModel().clearNoteSelection();
        if (fixture.clippingNote)
            m_view.setEditCursorTick(fixture.clippingNote->tick);
        drainQueuedEvents();
        firstButton = pitchEnvelopeButtonFor(fixture.firstTrack);
        if (!m_view.pitchEnvelopeCreationEnabled(fixture.firstTrack) || !firstButton ||
            firstButton->isHidden() || !firstButton->isEnabled()) {
            fail("ineligible cursor span disabled track-wide pitch-envelope authoring");
        } else {
            firstButton->click();
            if (!pitchEnvelopeOpenFor(fixture.firstTrack) || !firstButton->isChecked())
                fail("eligible track did not become the open pitch envelope");
        }
    }

    std::optional<pitchenvelopecheck::PitchEnvelopePersistenceResult>
    runGestureAndUndoChecks(const PitchEnvelopeFixture &fixture)
    {
        if (!fixture.templateSource || !fixture.clippedProjection || !fixture.clippingNote ||
            !fixture.finalProjection || fixture.fullProjections.size() != 2) {
            fail("could not resolve track pitch-envelope fixture notes");
            return std::nullopt;
        }
        const DocNote templateSource = *fixture.templateSource;
        const uint64_t startSample = m_view.timeline()->sampleForTick(templateSource.tick);
        const uint64_t targetEndSample =
            startSample + uint64_t(std::llround(0.100 * m_view.timeline()->sampleRate));
        const uint64_t expectedEndTick = fixture.sourceEndTick;
        const uint64_t nextGridSample = m_view.timeline()->sampleForTick(
            templateSource.tick + std::max<uint64_t>(1, m_document.ticksPerClock()));
        const uint64_t playableGridSamples = std::max<uint64_t>(1, nextGridSample - startSample);
        m_view.selectionModel().clearNoteSelection();
        m_view.setPitchEnvelopeVisible(fixture.firstTrack, false);
        auto *button = pitchEnvelopeButtonFor(fixture.firstTrack);
        if (!button || button->isHidden() || !button->isEnabled()) {
            fail("pitch-envelope toggle disappeared for an eligible track");
            m_view.setPitchEnvelopeVisible(fixture.firstTrack, true);
        } else {
            button->click();
        }
        QCoreApplication::processEvents();
        (void)m_view.grab();
        auto *host = m_view.findChild<QWidget *>(QStringLiteral("pitchEnvelopeHost"));
        auto *graph = graphFor(host);
        auto *status = m_view.findChild<QLabel *>(QStringLiteral("pitchEnvelopeStatus"));
        if (!host || host->isHidden() || !graph || graph->isHidden() || !graph->isEnabled() ||
            !status) {
            fail("track pitch-envelope toggle did not expose enabled host widgets");
            return std::nullopt;
        }
        m_view.setGridFeel(SongView::GridFeel::Straight);
        m_view.setGridMinDenom(4);
        QCoreApplication::processEvents();
        const uint64_t authoredGridTicks = m_view.gridTicksAt(templateSource.tick);
        const auto initialCurve = graph->points();
        const double initialEndMilliseconds = initialCurve.empty() ? 0.0 : initialCurve.back().x;
        const uint64_t initialEndSample =
            startSample +
            uint64_t(std::llround(initialEndMilliseconds * m_view.timeline()->sampleRate / 1000.0));
        const uint64_t initialEndpointError = initialEndSample > targetEndSample
                                                  ? initialEndSample - targetEndSample
                                                  : targetEndSample - initialEndSample;
        const bool zeroEndpoints =
            initialCurve.size() >= 2 && std::abs(initialCurve.front().x) <= 1e-9 &&
            std::abs(initialCurve.front().y) <= 1e-9 && std::abs(initialCurve.back().y) <= 1e-9;
        if (!zeroEndpoints)
            fail("new track pitch envelope did not expose mandatory zero endpoints");
        if (initialEndpointError > playableGridSamples)
            fail("new track pitch-envelope end was not within one grid step of 100ms");
        const QRect canvas = graph->canvasRect();
        if (canvas.width() < 3 || canvas.height() < 3) {
            fail("track pitch-envelope graph has no usable canvas");
            return std::nullopt;
        }
        const QPoint detentX(canvas.left() + canvas.width() / 3, canvas.center().y() + 8);
        sendCurveMouse(graph, QEvent::MouseButtonPress, detentX, Qt::LeftButton, Qt::LeftButton);
        const bool withinDetent = std::abs(graph->liveValue()) <= 1e-9;
        graph->cancelGesture();
        const QPoint outsideDetent(detentX.x(), detentX.y() + 1);
        sendCurveMouse(graph, QEvent::MouseButtonPress, outsideDetent, Qt::LeftButton,
                       Qt::LeftButton);
        const bool beyondDetent = std::abs(graph->liveValue()) > 1e-9;
        graph->cancelGesture();
        if (!withinDetent || !beyondDetent)
            fail("pitch-envelope graph did not apply its 8-pixel zero detent");
        const QByteArray beforeCurve = m_document.smf().write();
        const int curveUndoIndex = m_document.undoStack()->index();
        const QPoint strokeStart(canvas.left() + canvas.width() / 3, canvas.center().y());
        const QPoint strokeEnd(canvas.left() + 2 * canvas.width() / 3,
                               canvas.top() + canvas.height() / 4);
        sendCurveMouse(graph, QEvent::MouseButtonPress, strokeStart, Qt::LeftButton,
                       Qt::LeftButton);
        sendCurveMouse(graph, QEvent::MouseMove, strokeEnd, Qt::NoButton, Qt::LeftButton);
        if (!graph->hasGesture() || m_document.undoStack()->index() != curveUndoIndex)
            fail("track pitch-envelope gesture escaped graph preview before release");
        const auto authoredCurve = graph->points();
        sendCurveMouse(graph, QEvent::MouseButtonRelease, strokeEnd, Qt::LeftButton, Qt::NoButton);
        QCoreApplication::processEvents();
        const auto result = pitchenvelopecheck::verifyPitchEnvelopePersistence(
            {m_document,
             m_view,
             fixture.voicegroup,
             *graph,
             authoredCurve,
             templateSource,
             fixture.fullProjections,
             fixture.finalProjection->tick,
             {*fixture.clippedProjection, fixture.clippingNote->tick, fixture.clippedWindowEndTick,
              12},
             *fixture.clippingNote,
             fixture.firstTrack,
             expectedEndTick,
             targetEndSample,
             playableGridSamples,
             authoredGridTicks,
             fixture.preservedGapTick,
             fixture.preservedGapValue,
             fixture.postSpanTick,
             fixture.postSpanValue,
             beforeCurve,
             curveUndoIndex,
             m_songLabel});
        m_failures += result.failures;
        return result;
    }

    void runTrackScopeChecks(const PitchEnvelopeFixture &fixture)
    {
        if (!fixture.clippingNote || !fixture.finalProjection)
            return;
        m_view.setEditCursorTick(fixture.clippingNote->tick);
        drainQueuedEvents();
        auto *button = pitchEnvelopeButtonFor(fixture.firstTrack);
        auto *host = m_view.findChild<QWidget *>(QStringLiteral("pitchEnvelopeHost"));
        auto *graph = graphFor(host);
        auto *status = m_view.findChild<QLabel *>(QStringLiteral("pitchEnvelopeStatus"));
        const auto hostRemainsAuthorable = [&] {
            return pitchEnvelopeOpenFor(fixture.firstTrack) && button && !button->isHidden() &&
                   button->isEnabled() && button->isChecked() && host && !host->isHidden() &&
                   graph && !graph->isHidden() && graph->isEnabled() && status &&
                   !status->isHidden() && !status->text().isEmpty() &&
                   m_view.pitchEnvelopeCreationEnabled(fixture.firstTrack);
        };
        if (!hostRemainsAuthorable())
            fail("ineligible program span disabled the selected track's pitch-envelope editor");
        m_view.setPlayheadSample(m_view.timeline()->sampleForTick(fixture.clippingNote->tick),
                                 true);
        drainQueuedEvents();
        const bool beforeProgramChange = hostRemainsAuthorable();
        m_view.setPlayheadSample(m_view.timeline()->sampleForTick(fixture.finalProjection->tick),
                                 true);
        drainQueuedEvents();
        if (!beforeProgramChange || !hostRemainsAuthorable())
            fail("playhead program change flickered track pitch-envelope authoring");
        m_view.setPlayheadSample(0, false);
    }

    void runMissingVoiceCheck(const PitchEnvelopeFixture &fixture)
    {
        m_view.setVoicegroup(nullptr);
        drainQueuedEvents();
        if (m_view.trackHasPitchEnvelopeVoice(fixture.firstTrack) ||
            m_view.pitchEnvelopeCreationEnabled(fixture.firstTrack)) {
            fail("missing voice permitted track pitch-envelope authoring");
        }
        m_view.setVoicegroup(m_entryVoicegroup);
        drainQueuedEvents();
    }

    void restoreFixture(const PitchEnvelopeFixture &fixture)
    {
        if (m_fixtureRestored)
            return;
        m_fixtureRestored = true;
        while (m_document.undoStack()->index() > fixture.undoIndex &&
               m_document.undoStack()->canUndo())
            m_document.undoStack()->undo();
        m_view.applyViewState(fixture.beforeViewState);
        m_view.selectTrack(m_fixtureNote.engineTrack);
        m_view.selectionModel().clearNoteSelection();
        m_view.setEditCursorTick(0);
        m_view.setPlayheadSample(0, false);
        m_view.setVoicegroup(m_entryVoicegroup);
        drainQueuedEvents();
    }

    void runEligibilityTruthTable()
    {
        const auto supportsPitchEnvelope = [](uint8_t type) {
            return voiceSupportsPitchEnvelope(type);
        };
        if (!supportsPitchEnvelope(VOICE_SQUARE_1) || !supportsPitchEnvelope(VOICE_SQUARE_2) ||
            !supportsPitchEnvelope(VOICE_PROGRAMMABLE_WAVE) ||
            !supportsPitchEnvelope(VOICE_SQUARE_1_ALT) ||
            !supportsPitchEnvelope(VOICE_SQUARE_2_ALT) ||
            !supportsPitchEnvelope(VOICE_PROGRAMMABLE_WAVE_ALT)) {
            fail("pitch-envelope eligibility rejected a square or wave voice");
        }
        if (supportsPitchEnvelope(VOICE_NOISE) || supportsPitchEnvelope(VOICE_NOISE_ALT) ||
            supportsPitchEnvelope(VOICE_DIRECTSOUND) ||
            supportsPitchEnvelope(VOICE_DIRECTSOUND_ALT) ||
            supportsPitchEnvelope(VOICE_DIRECTSOUND_NO_RESAMPLE) ||
            supportsPitchEnvelope(VOICE_CRY) || supportsPitchEnvelope(VOICE_KEYSPLIT) ||
            supportsPitchEnvelope(VOICE_KEYSPLIT_ALL)) {
            fail("pitch-envelope eligibility accepted an ineligible voice");
        }
    }

    SongDocument &m_document;
    SongView &m_view;
    const DocNote &m_fixtureNote;
    const QString &m_songLabel;
    const LoadedVoiceGroup *m_entryVoicegroup = nullptr;
    bool m_fixtureRestored = false;
    int m_failures = 0;
};

} // namespace

int runPitchEnvelopeCheck(SongDocument &document, SongView &view, QWidget *,
                          const DocNote &fixtureNote, const QString &songLabel)
{
    return PitchEnvelopeCheckContext(document, view, fixtureNote, songLabel).run();
}
