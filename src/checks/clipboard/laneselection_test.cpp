#include <QtTest>

#include <memory>
#include <utility>
#include <vector>

#include "checks/support/editorrig.h"
#include "core/smf.h"
#include "core/songdocument.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/automationviewmodel.h"
#include "ui/editorviewstate.h"
#include "ui/songview.h"
#include "ui/songview/editorselectionmodel.h"

namespace {

using EditorSelectionModel = songview::EditorSelectionModel;

EditorAutomationRowId ccId(int track, uint8_t controller)
{
    return {EditorAutomationRowKind::ControlChange, uint8_t(track), controller};
}

EditorAutomationRowId tempoId()
{
    return {EditorAutomationRowKind::Tempo, 0, 0};
}

EditorAutomationRowId invalidId()
{
    return ccId(0, 99);
}

EditorSelectionModel selectedModel(Tick startTick, Tick endTick,
                                   EditorSelectionModel::TimeSelection::Scope scope,
                                   std::vector<std::pair<int, uint8_t>> lanes = {},
                                   bool tempo = false)
{
    EditorSelectionModel model;
    EditorSelectionModel::TimeSelection selection;
    selection.startTick = startTick;
    selection.endTick = endTick;
    selection.scope = scope;
    selection.lanes = std::move(lanes);
    selection.tempo = tempo;
    model.setTimeSelection(std::move(selection));
    return model;
}

class ProjectionRig final
{
  public:
    static std::unique_ptr<ProjectionRig> create(double zoom, double horizontalScroll,
                                                 QString &error, bool includeSecondary = false)
    {
        error.clear();
        auto rig = std::unique_ptr<ProjectionRig>(new ProjectionRig);
        SmfFile smf;
        smf.format = 1;
        smf.division = 24;

        SmfTrack primary;
        primary.events.push_back(noteEvent(0x90, 0, 60, 64));
        primary.endTick = 1;
        smf.tracks.push_back(std::move(primary));
        if (includeSecondary) {
            SmfTrack secondary;
            secondary.events.push_back(noteEvent(0x91, 0, 67, 64));
            secondary.endTick = 1;
            smf.tracks.push_back(std::move(secondary));
        }

        SongInfo info;
        info.label = QStringLiteral("automation-coverage-check");
        if (!rig->m_document.adoptSmf(std::move(smf), info, &error))
            return nullptr;

        checks::EditorRigConfig config;
        config.timeZoom = zoom;
        config.show = true;
        rig->m_editor = checks::EditorRig::create(rig->m_document, config, error);
        if (!rig->m_editor)
            return nullptr;
        rig->m_editor->view().setEditorHorizontalScroll(horizontalScroll);
        QCoreApplication::processEvents();
        return rig;
    }

    SongDocument &document() noexcept { return m_document; }
    const SongDocument &document() const noexcept { return m_document; }
    const MidiTimeline *timeline() const noexcept { return &m_editor->timeline(); }

    AutomationProjection projection() const
    {
        return AutomationProjection(AutomationGeometry::resolve(), &m_editor->view());
    }

  private:
    static SmfEvent noteEvent(uint8_t status, uint64_t tick, uint8_t key, uint8_t velocity)
    {
        SmfEvent event;
        event.status = status;
        event.tick = tick;
        event.data0 = key;
        event.data1 = velocity;
        return event;
    }

    SongDocument m_document;
    std::unique_ptr<checks::EditorRig> m_editor;
};

AutomationViewModel modelFor(const ProjectionRig &rig, const EditorSelectionModel &selection)
{
    return buildAutomationViewModel(rig.document(), rig.timeline(), selection, true);
}

const AutomationViewModel::Row *rowFor(const AutomationViewModel &model,
                                       const EditorAutomationRowId &id)
{
    return model.find(id);
}

bool coversLane(const AutomationViewModel &model, const EditorAutomationRowId &id)
{
    const auto *const row = rowFor(model, id);
    return row && row->coversLane;
}

bool coversNodes(const AutomationViewModel &model, const EditorAutomationRowId &id)
{
    const auto *const row = rowFor(model, id);
    return row && row->coversNodes;
}

class AutomationCoverageTest final : public QObject
{
    Q_OBJECT

  public:
    AutomationCoverageTest() = default;
    Q_DISABLE_COPY_MOVE(AutomationCoverageTest)

  private slots:
    void emptySelectionAndEndpointPayload()
    {
        QString error;
        const auto rig = ProjectionRig::create(96.0, 0.0, error);
        QVERIFY2(rig, qPrintable(error));
        const EditorSelectionModel selection;
        const AutomationViewModel model = modelFor(*rig, selection);

        QVERIFY(!model.activeTickRange);
        QVERIFY(!coversLane(model, tempoId()));
        QVERIFY(!coversNodes(model, tempoId()));
        QVERIFY(!coversLane(model, ccId(0, 7)));
        QVERIFY(!coversNodes(model, ccId(0, 7)));
        QVERIFY(!coversLane(model, invalidId()));
        QVERIFY(!coversNodes(model, invalidId()));
        QVERIFY(model.visibleLanes(selection).empty());

        // laneSet is endpoint-driven; it intentionally does not consult activeTickRange.
        const auto set = model.laneSet(tempoId(), ccId(0, 10));
        QVERIFY(set.first);
        QVERIFY((set.second == std::vector<std::pair<int, uint8_t>>{{0, 7}, {0, 10}}));
    }

    void laneScopeCoverage()
    {
        QString error;
        const auto rig = ProjectionRig::create(96.0, 0.0, error);
        QVERIFY2(rig, qPrintable(error));
        const EditorSelectionModel selection = selectedModel(
            24, 48, EditorSelectionModel::TimeSelection::Lanes, {{0, 7}, {0, 21}}, true);
        const AutomationViewModel model = modelFor(*rig, selection);

        QVERIFY(model.activeTickRange == (std::optional<std::pair<Tick, Tick>>{{24, 48}}));
        QVERIFY(coversLane(model, tempoId()));
        QVERIFY(coversNodes(model, tempoId()));
        QVERIFY(coversLane(model, ccId(0, 7)));
        QVERIFY(coversNodes(model, ccId(0, 7)));
        QVERIFY(coversLane(model, ccId(0, 21)));
        QVERIFY(coversNodes(model, ccId(0, 21)));
        QVERIFY(!coversLane(model, ccId(0, 10)));
        QVERIFY(!coversNodes(model, ccId(0, 10)));
        QVERIFY(!coversLane(model, ccId(0, 99)));
        QVERIFY(!coversNodes(model, ccId(0, 99)));
        QVERIFY((model.visibleLanes(selection) ==
                 std::vector<std::pair<int, uint8_t>>{{0, 7}, {0, 21}}));

        const EditorSelectionModel noTempoSelection =
            selectedModel(24, 48, EditorSelectionModel::TimeSelection::Lanes, {{0, 7}}, false);
        const AutomationViewModel noTempo = modelFor(*rig, noTempoSelection);
        QVERIFY(!coversLane(noTempo, tempoId()));
        QVERIFY(!coversNodes(noTempo, tempoId()));
    }

    void trackScopeSeparatesLaneAndNodeCoverage()
    {
        QString error;
        const auto rig = ProjectionRig::create(96.0, 0.0, error);
        QVERIFY2(rig, qPrintable(error));
        const EditorSelectionModel selection =
            selectedModel(24, 48, EditorSelectionModel::TimeSelection::Tracks);
        const AutomationViewModel full = modelFor(*rig, selection);

        QVERIFY(coversLane(full, tempoId()));
        QVERIFY(coversNodes(full, tempoId()));
        QVERIFY(!coversLane(full, ccId(0, 7)));
        QVERIFY(coversNodes(full, ccId(0, 7)));

        QString secondaryError;
        const auto secondaryRig = ProjectionRig::create(96.0, 0.0, secondaryError, true);
        QVERIFY2(secondaryRig, qPrintable(secondaryError));
        const AutomationViewModel partial = modelFor(*secondaryRig, selection);
        QVERIFY(!coversLane(partial, tempoId()));
        QVERIFY(!coversNodes(partial, tempoId()));
    }

    void hiddenLanesAreNotCovered()
    {
        QString error;
        const auto rig = ProjectionRig::create(96.0, 0.0, error);
        QVERIFY2(rig, qPrintable(error));
        // Supported controllers (including CC21) always have rows; CC99 is absent.
        const EditorSelectionModel selection = selectedModel(
            24, 48, EditorSelectionModel::TimeSelection::Lanes, {{0, 7}, {0, 99}}, false);
        const AutomationViewModel model = modelFor(*rig, selection);

        QVERIFY(coversLane(model, ccId(0, 7)));
        QVERIFY(coversNodes(model, ccId(0, 7)));
        QVERIFY(!coversLane(model, ccId(0, 10)));
        QVERIFY(!coversNodes(model, ccId(0, 10)));
        QVERIFY(!coversLane(model, invalidId()));
        QVERIFY(!coversNodes(model, invalidId()));
        QVERIFY((model.visibleLanes(selection) == std::vector<std::pair<int, uint8_t>>{{0, 7}}));

        // Page readiness hides supported rows without removing their document facts.
        const AutomationViewModel hidden =
            buildAutomationViewModel(rig->document(), rig->timeline(), selection, false);
        QVERIFY(rowFor(hidden, ccId(0, 7)));
        QVERIFY(!coversLane(hidden, ccId(0, 7)));
        QVERIFY(!coversNodes(hidden, ccId(0, 7)));
        QVERIFY(hidden.visibleLanes(selection).empty());
    }

    void documentFactsFollowIdentity()
    {
        QString error;
        const auto rig = ProjectionRig::create(96.0, 0.0, error);
        QVERIFY2(rig, qPrintable(error));
        const EditorSelectionModel selection =
            selectedModel(24, 48, EditorSelectionModel::TimeSelection::Lanes, {{0, 7}}, false);
        AutomationViewModel model = modelFor(*rig, selection);
        QCOMPARE(rowFor(model, ccId(0, 7))->eventCount, std::size_t{0});

        rig->document().addLanePoint(0, 7, 24, 64);
        model = modelFor(*rig, selection);
        QCOMPARE(rowFor(model, ccId(0, 7))->eventCount, std::size_t{1});
        QVERIFY(rowFor(model, ccId(0, 10)));
        QVERIFY(!rowFor(model, invalidId()));
    }

    void hitTest_data()
    {
        QTest::addColumn<double>("zoom");
        QTest::addColumn<double>("scroll");
        QTest::addColumn<double>("dpr");
        QTest::addColumn<bool>("active");
        QTest::newRow("base_dpr1") << 96.0 << 0.0 << 1.0 << true;
        QTest::newRow("zoomed_out_scrolled") << 64.0 << 96.0 << 1.0 << true;
        QTest::newRow("zoomed_in_dpr2") << 144.0 << 192.0 << 2.0 << true;
        QTest::newRow("inactive_reversed_selection") << 96.0 << 48.0 << 2.0 << false;
    }

    void hitTest()
    {
        QFETCH(double, zoom);
        QFETCH(double, scroll);
        QFETCH(double, dpr);
        QFETCH(bool, active);
        QString error;
        const auto rig = ProjectionRig::create(zoom, scroll, error);
        QVERIFY2(rig, qPrintable(error));
        const EditorSelectionModel selection =
            active
                ? selectedModel(48, 96, EditorSelectionModel::TimeSelection::Lanes, {{0, 7}}, false)
                : selectedModel(96, 48, EditorSelectionModel::TimeSelection::Lanes, {{0, 7}},
                                false);
        const AutomationViewModel model = modelFor(*rig, selection);
        const AutomationProjection projection = rig->projection();
        const qreal startX = projection.displayX(48, dpr);
        const qreal endX = projection.displayX(96, dpr);
        const qreal midX = (startX + endX) / 2.0;

        if (!active) {
            QVERIFY(!model.hitTest(ccId(0, 7), midX, projection, dpr, selection));
            return;
        }

        QVERIFY(model.hitTest(ccId(0, 7), startX, projection, dpr, selection));
        QVERIFY(model.hitTest(ccId(0, 7), midX, projection, dpr, selection));
        QVERIFY(!model.hitTest(ccId(0, 7), startX - 1.0, projection, dpr, selection));
        QVERIFY(!model.hitTest(ccId(0, 7), endX, projection, dpr, selection));
        QVERIFY(!model.hitTest(ccId(0, 10), midX, projection, dpr, selection));
        QVERIFY(!model.hitTest(tempoId(), midX, projection, dpr, selection));
    }

    void endpointSemantics()
    {
        QString error;
        const auto rig = ProjectionRig::create(96.0, 0.0, error);
        QVERIFY2(rig, qPrintable(error));
        const EditorSelectionModel selection;
        const AutomationViewModel model = modelFor(*rig, selection);

        const auto tempoOnly = model.laneSet(tempoId(), tempoId());
        QVERIFY(tempoOnly.first);
        QVERIFY(tempoOnly.second.empty());
        const auto ccOnly = model.laneSet(ccId(0, 7), ccId(0, 7));
        QVERIFY(!ccOnly.first);
        QVERIFY((ccOnly.second == std::vector<std::pair<int, uint8_t>>{{0, 7}}));
        const auto mixed = model.laneSet(tempoId(), ccId(0, 10));
        QVERIFY(mixed.first);
        QVERIFY((mixed.second == std::vector<std::pair<int, uint8_t>>{{0, 7}, {0, 10}}));
        const auto reversed = model.laneSet(ccId(0, 10), tempoId());
        QVERIFY(reversed.first);
        QVERIFY(reversed.second == mixed.second);
        const auto invalid = model.laneSet(invalidId(), ccId(0, 7));
        QVERIFY(!invalid.first);
        QVERIFY(invalid.second.empty());
    }
};

} // namespace

int runLaneSelectionCheck(const QStringList &qtArguments)
{
    AutomationCoverageTest test;
    QStringList arguments{QStringLiteral("laneselectioncheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "laneselection_test.moc"
