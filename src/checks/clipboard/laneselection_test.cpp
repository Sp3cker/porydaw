#include <QtTest>

#include <memory>
#include <utility>
#include <vector>

#include "checks/support/editorrig.h"
#include "core/smf.h"
#include "core/songdocument.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/laneselection.h"
#include "ui/editorviewstate.h"
#include "ui/songview.h"
#include "ui/songview/editorselectionmodel.h"

namespace {

using EditorSelectionModel = songview::EditorSelectionModel;

EditorAutomationRowId ccId(int track, uint8_t controller)
{
    return {EditorAutomationRowKind::ControlChange, uint8_t(track), controller};
}

AutomationRow ccRow(int track, uint8_t controller)
{
    return AutomationRow{ccId(track, controller)};
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
                                                 QString &error)
    {
        error.clear();
        auto rig = std::unique_ptr<ProjectionRig>(new ProjectionRig);
        SmfFile smf;
        smf.format = 1;
        smf.division = 24;
        smf.tracks.push_back({{}, 0});
        SongInfo info;
        info.label = QStringLiteral("lane-selection-check");
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

    AutomationProjection projection() const
    {
        return AutomationProjection(AutomationGeometry::resolve(), &m_editor->view());
    }

  private:
    SongDocument m_document;
    std::unique_ptr<checks::EditorRig> m_editor;
};

class LaneSelectionTest final : public QObject
{
    Q_OBJECT

  public:
    LaneSelectionTest() = default;
    Q_DISABLE_COPY_MOVE(LaneSelectionTest)

  private slots:
    void emptySelectionAndEndpointPayload()
    {
        const uint32_t usedTracks = uint32_t{1} << 0;
        const std::vector<AutomationRow> rows = {ccRow(0, 7), ccRow(0, 10), ccRow(0, 21)};
        EditorSelectionModel model;
        LaneSelection view(model, rows, usedTracks);

        QVERIFY(!view.active());
        QVERIFY(!view.coversLane(tempoId()));
        QVERIFY(!view.coversNodes(tempoId()));
        QVERIFY(!view.coversLane(ccId(0, 7)));
        QVERIFY(!view.coversNodes(ccId(0, 7)));
        QVERIFY(!view.coversLane(invalidId()));
        QVERIFY(!view.coversNodes(invalidId()));
        QVERIFY(view.visibleLanes().empty());

        // laneSet is endpoint-driven; it intentionally does not consult active().
        const auto set = view.laneSet(tempoId(), ccId(0, 10));
        QVERIFY(set.first);
        QVERIFY((set.second == std::vector<std::pair<int, uint8_t>>{{0, 7}, {0, 10}}));
    }

    void laneScopeCoverage()
    {
        const uint32_t usedTracks = uint32_t{1} << 0;
        const std::vector<AutomationRow> rows = {ccRow(0, 7), ccRow(0, 10), ccRow(0, 21)};
        EditorSelectionModel model = selectedModel(
            24, 48, EditorSelectionModel::TimeSelection::Lanes, {{0, 7}, {0, 21}}, true);
        LaneSelection view(model, rows, usedTracks);

        QVERIFY(view.active());
        QVERIFY(view.coversLane(tempoId()));
        QVERIFY(view.coversNodes(tempoId()));
        QVERIFY(view.coversLane(ccId(0, 7)));
        QVERIFY(view.coversNodes(ccId(0, 7)));
        QVERIFY(view.coversLane(ccId(0, 21)));
        QVERIFY(view.coversNodes(ccId(0, 21)));
        QVERIFY(!view.coversLane(ccId(0, 10)));
        QVERIFY(!view.coversNodes(ccId(0, 10)));
        QVERIFY(!view.coversLane(ccId(0, 99)));
        QVERIFY(!view.coversNodes(ccId(0, 99)));
        QVERIFY((view.visibleLanes() == std::vector<std::pair<int, uint8_t>>{{0, 7}, {0, 21}}));

        EditorSelectionModel noTempoModel =
            selectedModel(24, 48, EditorSelectionModel::TimeSelection::Lanes, {{0, 7}}, false);
        LaneSelection noTempo(noTempoModel, rows, usedTracks);
        QVERIFY(!noTempo.coversLane(tempoId()));
        QVERIFY(!noTempo.coversNodes(tempoId()));
    }

    void trackScopeSeparatesLaneAndNodeCoverage()
    {
        const uint32_t usedTracks = uint32_t{1} << 0;
        const std::vector<AutomationRow> rows = {ccRow(0, 7), ccRow(0, 10), ccRow(0, 21)};
        EditorSelectionModel model =
            selectedModel(24, 48, EditorSelectionModel::TimeSelection::Tracks);
        LaneSelection full(model, rows, usedTracks);

        QVERIFY(full.coversLane(tempoId()));
        QVERIFY(full.coversNodes(tempoId()));
        QVERIFY(!full.coversLane(ccId(0, 7)));
        QVERIFY(full.coversNodes(ccId(0, 7)));

        LaneSelection partial(model, rows, usedTracks | (uint32_t{1} << 1));
        QVERIFY(!partial.coversLane(tempoId()));
        QVERIFY(!partial.coversNodes(tempoId()));
    }

    void hiddenLanesAreNotCovered()
    {
        const uint32_t usedTracks = uint32_t{1} << 0;
        EditorSelectionModel model = selectedModel(
            24, 48, EditorSelectionModel::TimeSelection::Lanes, {{0, 7}, {0, 21}}, false);
        const std::vector<AutomationRow> rows = {ccRow(0, 7), ccRow(0, 10)};
        LaneSelection view(model, rows, usedTracks);

        QVERIFY(view.coversLane(ccId(0, 7)));
        QVERIFY(view.coversNodes(ccId(0, 7)));
        QVERIFY(!view.coversLane(ccId(0, 10)));
        QVERIFY(!view.coversNodes(ccId(0, 10)));
        QVERIFY((view.visibleLanes() == std::vector<std::pair<int, uint8_t>>{{0, 7}}));
    }

    void rowRebuildFollowsIdentity()
    {
        const uint32_t usedTracks = uint32_t{1} << 0;
        EditorSelectionModel model = selectedModel(
            24, 48, EditorSelectionModel::TimeSelection::Lanes, {{0, 7}, {0, 21}}, true);
        std::vector<AutomationRow> rows = {ccRow(0, 7), ccRow(0, 10), ccRow(0, 21)};
        LaneSelection view(model, rows, usedTracks);

        rows.insert(rows.cbegin() + 2, ccRow(0, 11));
        view.setUsedTrackMask(usedTracks);
        QVERIFY(view.coversLane(tempoId()));
        QVERIFY(view.coversLane(ccId(0, 7)));
        QVERIFY(!view.coversLane(ccId(0, 10)));
        QVERIFY(!view.coversLane(ccId(0, 11)));
        QVERIFY(view.coversLane(ccId(0, 21)));
        QVERIFY((view.visibleLanes() == std::vector<std::pair<int, uint8_t>>{{0, 7}, {0, 21}}));

        rows.erase(rows.cbegin() + 2);
        view.setUsedTrackMask(usedTracks);
        QVERIFY(view.coversLane(ccId(0, 21)));
        QVERIFY(!view.coversLane(ccId(0, 11)));
        QVERIFY(view.laneSet(ccId(0, 11), ccId(0, 11)).second.empty());

        EditorSelectionModel trackModel =
            selectedModel(24, 48, EditorSelectionModel::TimeSelection::Lanes, {{0, 10}}, false);
        const std::vector<AutomationRow> trackRows = {ccRow(0, 10), ccRow(1, 10)};
        LaneSelection trackView(trackModel, trackRows, usedTracks | (uint32_t{1} << 1));
        QVERIFY(trackView.coversLane(ccId(0, 10)));
        QVERIFY(!trackView.coversLane(ccId(1, 10)));
        QVERIFY(trackView.coversNodes(ccId(0, 10)));
        QVERIFY(!trackView.coversNodes(ccId(1, 10)));
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
        std::unique_ptr<ProjectionRig> rig = ProjectionRig::create(zoom, scroll, error);
        QVERIFY2(rig, qPrintable(error));
        const std::vector<AutomationRow> rows = {ccRow(0, 7), ccRow(0, 10), ccRow(0, 21)};
        EditorSelectionModel model =
            active
                ? selectedModel(48, 96, EditorSelectionModel::TimeSelection::Lanes, {{0, 7}}, false)
                : selectedModel(96, 48, EditorSelectionModel::TimeSelection::Lanes, {{0, 7}},
                                false);
        LaneSelection view(model, rows, uint32_t{1} << 0);
        const AutomationProjection projection = rig->projection();
        const qreal startX = projection.displayX(48, dpr);
        const qreal endX = projection.displayX(96, dpr);
        const qreal midX = (startX + endX) / 2.0;

        if (!active) {
            QVERIFY(!view.hitTest(ccId(0, 7), midX, projection, dpr));
            return;
        }

        QVERIFY(view.hitTest(ccId(0, 7), startX, projection, dpr));
        QVERIFY(view.hitTest(ccId(0, 7), midX, projection, dpr));
        QVERIFY(!view.hitTest(ccId(0, 7), startX - 1.0, projection, dpr));
        QVERIFY(!view.hitTest(ccId(0, 7), endX, projection, dpr));
        QVERIFY(!view.hitTest(ccId(0, 10), midX, projection, dpr));
        QVERIFY(!view.hitTest(tempoId(), midX, projection, dpr));
    }

    void endpointSemantics()
    {
        const uint32_t usedTracks = uint32_t{1} << 0;
        const std::vector<AutomationRow> rows = {ccRow(0, 7), ccRow(0, 10), ccRow(0, 21)};
        EditorSelectionModel model;
        LaneSelection view(model, rows, usedTracks);

        const auto tempoOnly = view.laneSet(tempoId(), tempoId());
        QVERIFY(tempoOnly.first);
        QVERIFY(tempoOnly.second.empty());
        const auto ccOnly = view.laneSet(ccId(0, 7), ccId(0, 7));
        QVERIFY(!ccOnly.first);
        QVERIFY((ccOnly.second == std::vector<std::pair<int, uint8_t>>{{0, 7}}));
        const auto mixed = view.laneSet(tempoId(), ccId(0, 10));
        QVERIFY(mixed.first);
        QVERIFY((mixed.second == std::vector<std::pair<int, uint8_t>>{{0, 7}, {0, 10}}));
        const auto reversed = view.laneSet(ccId(0, 10), tempoId());
        QVERIFY(reversed.first);
        QVERIFY(reversed.second == mixed.second);
        const auto invalid = view.laneSet(invalidId(), ccId(0, 7));
        QVERIFY(!invalid.first);
        QVERIFY(invalid.second.empty());
    }
};

} // namespace

int runLaneSelectionCheck(const QStringList &qtArguments)
{
    LaneSelectionTest test;
    QStringList arguments{QStringLiteral("laneselectioncheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "laneselection_test.moc"
