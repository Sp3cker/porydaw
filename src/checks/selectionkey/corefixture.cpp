#include "checks/selectionkey/corefixture.h"

#include "checks/selectionkey/automationprobe.h"

#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/songview/editorselectionmodel.h"
#include "ui/songview/quick/timelineinputitem.h"

#include <QQuickWindow>
#include <QtGlobal>

#include <algorithm>
#include <array>
#include <bit>
#include <cmath>
#include <utility>

// Honesty note: fixture staging here is deliberately programmatic — project
// load, band focus, pencil mode, horizontal reveal and selection-model state
// are arranged through production APIs because they are the conditions of the
// test, not its subject. Parameter activation and every command under test
// reach the shown Quick window as real QTest key or mouse events.

namespace selectionkey {
namespace {

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

bool activateCoreAutomation(RigWorld &world, QString *diagnostics = nullptr)
{
    const auto probe =
        AutomationProbe::locate(rigView(world), rigInput(world, "timelineAutomationInput"), kTrack,
                                kController, diagnostics);
    return probe && probe->activateParameter(diagnostics);
}

} // namespace

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

QString describeNoteIds(const std::vector<NoteId> &ids)
{
    static_assert(sizeof(NoteId) == sizeof(uint64_t));
    QStringList values;
    for (const NoteId id : ids) {
        values.push_back(QStringLiteral("0x%1").arg(
            static_cast<qulonglong>(std::bit_cast<uint64_t>(id)), 16, 16, QLatin1Char('0')));
    }
    return QStringLiteral("[%1]").arg(values.join(QLatin1Char(',')));
}

songview::EditorSelectionModel::TimeSelection coreLaneRange(uint64_t begin, uint64_t end)
{
    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = begin;
    selection.endTick = end;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    selection.lanes = {{kTrack, kController}};
    return selection;
}

songview::EditorSelectionModel::TimeSelection coreTrackRange(uint64_t begin, uint64_t end)
{
    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = begin;
    selection.endTick = end;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Tracks;
    return selection;
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

std::unique_ptr<CoreFixture> CoreFixture::create(const QString &projectRoot,
                                                 const QString &songLabel,
                                                 std::optional<EditorDrawerPage> drawerPage,
                                                 QString &error)
{
    auto fixture = std::unique_ptr<CoreFixture>(new CoreFixture);
    fixture->m_world = makeRigWorld(projectRoot, songLabel, kTrack, coreNoteSpecs(),
                                    coreRigConfig(drawerPage), prepareCoreDocument, error);
    if (!fixture->m_world)
        return nullptr;
    if (drawerPage == EditorDrawerPage::Automations &&
        !activateCoreAutomation(*fixture->m_world, &error)) {
        return nullptr;
    }
    return fixture;
}

void CoreFixture::configureDrawerSurface(std::optional<EditorDrawerPage> drawerPage)
{
    SongView &songView = rigView(*m_world);
    constexpr std::array pages{EditorDrawerPage::Automations, EditorDrawerPage::Velocity,
                               EditorDrawerPage::VoiceChanges};
    for (const EditorDrawerPage page : pages)
        songView.setDrawerSectionVisible(page, false);
    if (drawerPage) {
        songView.setDrawerActivePage(*drawerPage);
        songView.setDrawerSectionHeight(*drawerPage, canonicalSectionHeight(*drawerPage));
        songView.setDrawerSectionVisible(*drawerPage, true);
    }
    settle();
    if (drawerPage == EditorDrawerPage::Automations)
        activateCoreAutomation(*m_world);
}

bool CoreFixture::focusBand(songview::TimelineBand band)
{
    const bool focused = rigView(*m_world).focusTimelineBand(band, Qt::OtherFocusReason);
    settle();
    return focused;
}

std::optional<DocNote> CoreFixture::note(std::size_t index) const
{
    Q_ASSERT(index < m_world->notes.size());
    return noteById(rigDocument(*m_world), m_world->notes[index]);
}

std::optional<std::array<DocNote, 3>> CoreFixture::snapshotNotes() const
{
    std::array<DocNote, 3> snapshot{};
    for (std::size_t index = 0; index < snapshot.size(); ++index) {
        const auto note = noteById(rigDocument(*m_world), m_world->notes[index]);
        if (!note)
            return std::nullopt;
        snapshot[index] = *note;
    }
    return snapshot;
}

ClickTarget CoreFixture::emptyAutomationLanePoint() const
{
    ClickTarget result;
    const auto probe =
        AutomationProbe::locate(rigView(*m_world), rigInput(*m_world, "timelineAutomationInput"),
                                kTrack, kController, &result.diagnostics);
    QPoint point;
    if (probe && probe->emptyNodePoint(64, point, &result.diagnostics))
        result.point = point;
    return result;
}

ClickTarget CoreFixture::selectedVelocityStemPoint() const
{
    ClickTarget result;
    songview::TimelineInputItem *const velocityInput = rigInput(*m_world, "timelineVelocityInput");
    EditorDrawer *const drawer = rigView(*m_world).editorDrawer();
    VelocityArea *const area = drawer ? drawer->velocityArea() : nullptr;
    const auto note = noteById(rigDocument(*m_world), m_world->notes[0]);
    if (!velocityInput || !area || !note) {
        result.diagnostics =
            QStringLiteral("input=%1,velocity-area=%2,target-note=%3")
                .arg(velocityInput ? QStringLiteral("present") : QStringLiteral("missing"),
                     area ? QStringLiteral("present") : QStringLiteral("missing"),
                     note ? QStringLiteral("present") : QStringLiteral("missing"));
        return result;
    }
    rigView(*m_world).ensureRangeVisible(note->tick, note->tick + note->duration, true);
    settle();
    const QPointF inputPoint(
        rigView(*m_world).camera().displayX(double(note->tick) + double(note->duration) * 0.75, 0.0,
                                            velocityInput->devicePixelRatio()),
        area->axis().velocityToY(note->velocity));
    const QPoint windowPoint = velocityInput->mapToScene(inputPoint).toPoint();
    const bool ready =
        velocityInput->window() == rigWindow(*m_world) &&
        velocityInput->bounds().contains(inputPoint) &&
        velocityInput->bounds().contains(velocityInput->mapFromScene(QPointF(windowPoint)));
    result.diagnostics =
        QStringLiteral("input-bounds=%1,chosen-input=%2,chosen-window=%3,selection=%4")
            .arg(describeRect(velocityInput->bounds()), describePoint(inputPoint),
                 describePoint(windowPoint),
                 describeNoteIds(rigView(*m_world).selectionModel().noteSelection()));
    if (ready)
        result.point = windowPoint;
    return result;
}

std::optional<QPoint> CoreFixture::plainRulerPoint(songview::TimelineInputItem *ruler) const
{
    // An ordinary ruler click near the center, clear of loop markers and
    // time-signature chips whose press-drag state commits on release.
    if (!ruler || ruler->bounds().isEmpty())
        return std::nullopt;
    std::vector<qreal> reservedX;
    const auto reserve = [&reservedX, this, ruler](uint64_t tick) {
        if (tick != UINT64_MAX)
            reservedX.push_back(
                rigView(*m_world).camera().displayX(double(tick), 0.0, ruler->devicePixelRatio()));
    };
    reserve(rigDocument(*m_world).loopTick(false));
    reserve(rigDocument(*m_world).loopTick(true));
    for (const DocTimeSig &signature : rigDocument(*m_world).timeSigs())
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

std::optional<std::vector<QPoint>>
CoreFixture::laneWindowPoints(const std::vector<std::pair<uint64_t, int>> &pointSpecs,
                              QString *diagnostics) const
{
    const auto probe =
        AutomationProbe::locate(rigView(*m_world), rigInput(*m_world, "timelineAutomationInput"),
                                kTrack, kController, diagnostics);
    if (!probe)
        return std::nullopt;
    std::vector<AutomationProbePoint> requested;
    requested.reserve(pointSpecs.size());
    for (const auto &spec : pointSpecs)
        requested.push_back({spec.first, spec.second});
    std::vector<QPoint> projected(pointSpecs.size());
    if (!probe->project(requested, projected, diagnostics))
        return std::nullopt;
    return projected;
}

std::optional<QPoint> CoreFixture::laneWindowPoint(uint64_t tick, int value,
                                                   QString *diagnostics) const
{
    const auto points = laneWindowPoints({{tick, value}}, diagnostics);
    return points ? std::optional(points->front()) : std::nullopt;
}

} // namespace selectionkey
