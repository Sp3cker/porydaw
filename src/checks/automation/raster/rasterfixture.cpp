#include "rasterfixture.h"

#include <algorithm>
#include <cstring>
#include <utility>

#include <QAction>
#include <QCoreApplication>
#include <QCursor>
#include <QEventLoop>
#include <QFont>
#include <QGuiApplication>
#include <QPalette>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRectF>
#include <QSize>
#include <QTimer>
#include <QWindow>

#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "core/miditimeline.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timelinebandlayout.h"

namespace {
constexpr double kCheckSampleRate = 48000.0;

} // namespace

class RasterAutomationInputHost final : public songview::TimelineInputHost
{
  public:
    RasterAutomationInputHost(const AutomationPage &page,
                              const songview::TimelineInputItem &gutterInput)
        : m_page(page)
        , m_gutterInput(gutterInput)
        , m_dpr(qGuiApp->devicePixelRatio())
    {}

    RasterAutomationInputHost(const RasterAutomationInputHost &) = delete;
    RasterAutomationInputHost &operator=(const RasterAutomationInputHost &) = delete;

    void setDevicePixelRatio(qreal dpr) noexcept { m_dpr = dpr; }

    void setGlobalOffset(QPointF offset) noexcept { m_globalOffset = offset; }

    QRectF bounds() const override
    {
        const QSize size = m_page.automationViewportSize();
        const qreal gutterWidth = m_gutterInput.bounds().width();
        return {0.0, 0.0, std::max(0.0, qreal(size.width()) - gutterWidth), qreal(size.height())};
    }

    qreal devicePixelRatio() const override { return m_dpr; }

    QFont font() const override { return qGuiApp->font(); }

    QPalette palette() const override { return qGuiApp->palette(); }

    QPointF mapFromGlobal(QPointF position) const override { return position - m_globalOffset; }
    QPointF mapToGlobal(QPointF position) const override { return position + m_globalOffset; }

    void requestFocus(Qt::FocusReason) override {}
    void setCursor(const QCursor &) override {}
    void clearCursor() override {}
    void releasePointerGrab() override {}
    void setAccessibilityDescription(const QString &) override {}

  private:
    const AutomationPage &m_page;
    const songview::TimelineInputItem &m_gutterInput;
    qreal m_dpr = 1.0;
    QPointF m_globalOffset;
};

std::unique_ptr<AutomationRasterFixture>
AutomationRasterFixture::create(const QString &project, const QString &song, QString &error)
{
    error.clear();
    auto loadedSong = checks::LoadedSong::load(project, song, error);
    if (!loadedSong)
        return nullptr;

    auto fixture = std::unique_ptr<AutomationRasterFixture>(new AutomationRasterFixture);
    fixture->m_song = std::move(loadedSong);
    if (!fixture->initialize(error))
        return nullptr;
    return fixture;
}

AutomationRasterFixture::~AutomationRasterFixture()
{
    shutdown();
}

SongDocument &AutomationRasterFixture::document() noexcept
{
    return m_song->document();
}

SongView &AutomationRasterFixture::view() noexcept
{
    return *m_view;
}

const SongView &AutomationRasterFixture::view() const noexcept
{
    return *m_view;
}

void AutomationRasterFixture::configurePainting()
{
    SongDocument &songDocument = document();
    songDocument.addLanePoint(0, LANE_CC_BEND, 72, 8191);
    songDocument.addLanePoint(0, DOC_CC_VOICE, 24, 3);

    EditorViewState state;
    const EditorAutomationRowId volume{EditorAutomationRowKind::ControlChange, 0, 7};
    const EditorAutomationRowId lfo{EditorAutomationRowKind::ControlChange, 0, 21};
    state.hideLane(volume);
    state.emptyLanes.insert(pan.row);
    state.laneHeights[lfo] = layout::fontPx(4.0) + layout::space(layout::Space::One);
    state.laneRanges[lfo] = 91;
    m_view->applyEditorViewState(state);
    m_view->setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
    m_view->setDrawerActivePage(EditorDrawerPage::Automations);
    m_view->setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    m_view->setDrawerSectionHeight(EditorDrawerPage::Automations, 360);
    m_view->setEditorTimeZoom(96.0);
    m_view->setEditorHorizontalScroll(0.0);
    m_view->setEditCursorTick(24);
    m_live.editCursorTick = 24;
    m_live.timeZoom = m_view->camera().pxPerBeat();
    m_live.horizontalScroll = m_view->camera().scrollX();
    documentChanged();
}

void AutomationRasterFixture::configureInteraction()
{
    m_view->setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    m_view->setDrawerSectionHeight(EditorDrawerPage::VoiceChanges, 180);
    m_view->setDrawerActivePage(EditorDrawerPage::Automations);
    m_view->setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    m_view->setDrawerSectionHeight(EditorDrawerPage::Automations, 360);
    m_view->setEditorTimeZoom(96.0);
    m_view->setEditorHorizontalScroll(0.0);
    m_view->setEditCursorTick(24);
    m_live.editCursorTick = 24;
    m_live.timeZoom = m_view->camera().pxPerBeat();
    m_live.horizontalScroll = m_view->camera().scrollX();
    setPersistentPencil(false);
    refreshPage();
    pump();
}

void AutomationRasterFixture::shutdown()
{
    if (m_shutdown)
        return;
    m_shutdown = true;

    if (m_page && m_inputHost) {
        m_page->canvas()->detachInputHost(*m_inputHost);
        if (m_automationPlotInput && m_productionInteraction)
            m_automationPlotInput->setInteraction(m_productionInteraction);
    }
    m_inputHost.reset();
    m_productionInteraction = nullptr;

    if (m_view) {
        m_view->setSong(nullptr, nullptr);
        m_view->setDocument(nullptr);
    }
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents(QEventLoop::AllEvents);
}

AutomationPage &AutomationRasterFixture::page() noexcept
{
    return *m_page;
}

const AutomationPage &AutomationRasterFixture::page() const noexcept
{
    return *m_page;
}

AutomationCanvas &AutomationRasterFixture::canvas() noexcept
{
    return *m_page->canvas();
}

const AutomationCanvas &AutomationRasterFixture::canvas() const noexcept
{
    return *m_page->canvas();
}

songview::TimelineInputItem &AutomationRasterFixture::automationGutterInput() noexcept
{
    return *m_automationGutterInput;
}

songview::TimelineInputItem &AutomationRasterFixture::voiceInput() noexcept
{
    return *m_voiceInput;
}

const songview::TimelineInputItem &AutomationRasterFixture::voiceInput() const noexcept
{
    return *m_voiceInput;
}

const songview::TimelineQuickScene &AutomationRasterFixture::quickScene() const noexcept
{
    return *m_quickScene;
}

AutomationGeometry AutomationRasterFixture::geometry() const
{
    return AutomationGeometry::resolve();
}

AutomationProjection AutomationRasterFixture::projection() const
{
    return {geometry(), m_page};
}

LaneHandle AutomationRasterFixture::handleFor(const Lane &lane) const noexcept
{
    const auto &rows = canvas().rows();
    for (int index = 0; index < int(rows.size()); ++index) {
        if (rows[std::size_t(index)].id == lane.row)
            return {index + 1};
    }
    return {};
}

QRect AutomationRasterFixture::bodyFor(LaneHandle handle) const
{
    return canvas().laneBody(handle);
}

qreal AutomationRasterFixture::automationDpr() const noexcept
{
    return m_inputHost->devicePixelRatio();
}

qreal AutomationRasterFixture::nativeAutomationDpr() const noexcept
{
    return m_automationPlotInput ? m_automationPlotInput->devicePixelRatio() : 0.0;
}

void AutomationRasterFixture::setAutomationDpr(qreal dpr) noexcept
{
    m_inputHost->setDevicePixelRatio(dpr);
}

QPointF AutomationRasterFixture::automationContentToViewport(const QPointF &position) const
{
    return {position.x(), position.y() - qreal(page().verticalScroll())};
}

bool AutomationRasterFixture::expandTempo()
{
    if (!canvas().laneBody(kTempoHandle).isEmpty())
        return true;
    const QPointF header = tempoHeaderPoint();
    const QPointF viewportPosition = automationContentToViewport(header);
    checks::events::sendMouse(*m_automationGutterInput, QEvent::MouseButtonPress, viewportPosition,
                              Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*m_automationGutterInput, QEvent::MouseButtonRelease,
                              viewportPosition, Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    pump();
    return !canvas().laneBody(kTempoHandle).isEmpty();
}

QPointF AutomationRasterFixture::tempoHeaderPoint() const
{
    const QRect tempo = canvas().pinnedTempoRect();
    return {m_automationGutterInput->bounds().center().x(), qreal(tempo.center().y())};
}

void AutomationRasterFixture::setAutomationZoom(double zoom)
{
    m_view->setEditorTimeZoom(zoom);
    m_live.timeZoom = m_view->camera().pxPerBeat();
    m_live.horizontalScroll = m_view->camera().scrollX();
    refreshPage();
    pump();
}

void AutomationRasterFixture::setAutomationScroll(double scroll)
{
    m_view->setEditorHorizontalScroll(scroll);
    m_live.horizontalScroll = m_view->camera().scrollX();
    refreshPage();
    pump();
}

void AutomationRasterFixture::setPersistentPencil(bool enabled)
{
    if (QAction *const action = m_page->pencilModeAction())
        action->setChecked(enabled);
}

void AutomationRasterFixture::documentChanged()
{
    m_page->documentChanged();
    auto newTimeline = document().buildTimeline(kCheckSampleRate);
    m_view->updateSong(newTimeline.get());
    m_timeline = std::move(newTimeline);
    refreshPage();
    pump();
}

void AutomationRasterFixture::automationMouseMove(const QPointF &position)
{
    const QPointF viewportPosition = automationContentToViewport(position);
    canvas().pointerMove({
        .position = viewportPosition,
        .globalPosition = m_inputHost->mapToGlobal(viewportPosition),
        .button = Qt::NoButton,
        .buttons = Qt::NoButton,
        .modifiers = Qt::NoModifier,
        .surface = songview::TimelineInputSurface::Plot,
        .host = m_inputHost.get(),
    });
}

void AutomationRasterFixture::automationPointerLeave()
{
    canvas().pointerLeave();
}

void AutomationRasterFixture::voiceMousePress(const QPointF &position)
{
    checks::events::sendMouse(*m_voiceInput, QEvent::MouseButtonPress, position, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
}

void AutomationRasterFixture::voiceMouseMove(const QPointF &position)
{
    checks::events::sendMouse(*m_voiceInput, QEvent::MouseMove, position, Qt::NoButton,
                              Qt::LeftButton, Qt::NoModifier);
}

void AutomationRasterFixture::voiceMouseRelease(const QPointF &position)
{
    checks::events::sendMouse(*m_voiceInput, QEvent::MouseButtonRelease, position, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
}

void AutomationRasterFixture::pump()
{
    QCoreApplication::sendPostedEvents();
    waitForTimers(0);
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents(QEventLoop::AllEvents);
}

QImage AutomationRasterFixture::renderAutomationViewport(QString *error)
{
    const auto &geometry = view().timelineBandLayout().geometry(songview::TimelineBand::Automation);
    return checks::support::captureQuickBand(view(), geometry ? geometry->rect : QRect{}, error);
}

QImage AutomationRasterFixture::renderVoiceChanges(QString *error)
{
    const auto &geometry =
        view().timelineBandLayout().geometry(songview::TimelineBand::VoiceChanges);
    return checks::support::captureQuickBand(view(), geometry ? geometry->rect : QRect{}, error);
}

bool AutomationRasterFixture::initialize(QString &error)
{
    SongDocument &songDocument = document();
    if (songDocument.engineTrackCount() == 0) {
        error = QStringLiteral("%1 has no engine tracks").arg(m_song->songInfo().label);
        return false;
    }

    // Interaction's narrower seed intentionally differs from painting's seed.
    songDocument.addLanePoint(0, 7, 24, 32);
    songDocument.writeLanePoints(0, 21, 96, 96, {{96, 32}, {96, 96}});
    m_voicegroup = std::make_unique<LoadedVoiceGroup>();
    m_voicegroup->voices[3].type = VOICE_NOISE;
    std::strncpy(m_voicegroup->voiceNames[3], "automation-voice",
                 sizeof(m_voicegroup->voiceNames[3]) - 1);
    m_timeline = songDocument.buildTimeline(kCheckSampleRate);
    m_view = std::make_unique<SongView>();
    songview::TimelineQuickView *const quick = m_view->quickView();
    if (!quick) {
        error = QStringLiteral("concrete SongView did not expose an unhosted Quick view");
        return false;
    }
    m_view->setDocument(&songDocument);
    m_view->setSong(m_timeline.get(), m_voicegroup.get());

    EditorViewState state;
    state.emptyLanes.insert(pan.row);
    m_view->applyEditorViewState(state);
    m_view->setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    m_view->setDrawerSectionHeight(EditorDrawerPage::VoiceChanges, 180);
    m_view->setDrawerActivePage(EditorDrawerPage::Automations);
    m_view->setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    m_view->setDrawerSectionHeight(EditorDrawerPage::Automations, 360);
    if (!checks::support::showQuickViewport(*m_view, QSize(960, 720))) {
        error = QStringLiteral("concrete SongView did not expose an unhosted Quick window");
        return false;
    }

    auto *drawer = m_view->editorDrawer();
    m_page = drawer ? drawer->automationPage() : nullptr;
    m_quickScene = m_view->findChild<songview::TimelineQuickScene *>();
    QQuickItem *const quickRoot = quick ? quick->rootObject() : nullptr;
    m_automationPlotInput = quickRoot ? quickRoot->findChild<songview::TimelineInputItem *>(
                                            QStringLiteral("timelineAutomationInput"))
                                      : nullptr;
    m_automationGutterInput = quickRoot ? quickRoot->findChild<songview::TimelineInputItem *>(
                                              QStringLiteral("timelineAutomationGutterInput"))
                                        : nullptr;
    m_voiceInput = quickRoot ? quickRoot->findChild<songview::TimelineInputItem *>(
                                   QStringLiteral("timelineVoiceChangesInput"))
                             : nullptr;
    if (!m_page || !m_automationPlotInput || !m_automationGutterInput || !m_voiceInput ||
        !m_quickScene) {
        error = QStringLiteral(
            "concrete SongView did not expose drawer pages and physical Quick inputs");
        return false;
    }

    m_inputHost = std::make_unique<RasterAutomationInputHost>(*m_page, *m_automationGutterInput);
    m_inputHost->setGlobalOffset(m_automationPlotInput->mapToGlobal(QPointF{}));
    if (const QQuickWindow *window = m_automationPlotInput->window())
        m_inputHost->setDevicePixelRatio(window->devicePixelRatio());
    m_productionInteraction = m_automationPlotInput->interaction();
    if (m_productionInteraction)
        m_automationPlotInput->setInteraction(nullptr);
    m_page->canvas()->attachInputHost(*m_inputHost);
    m_page->canvas()->hostAppearanceChanged();
    m_page->songChanged();
    m_live.documentRevision = songDocument.revision();
    m_live.editCursorTick = 24;
    m_view->setEditorTimeZoom(96.0);
    m_live.timeZoom = m_view->camera().pxPerBeat();
    m_live.horizontalScroll = m_view->camera().scrollX();
    m_page->refreshLiveState(m_live);
    pump();
    return true;
}

void AutomationRasterFixture::refreshPage()
{
    m_live.documentRevision = document().revision();
    m_page->refreshLiveState(m_live);
}

void AutomationRasterFixture::waitForTimers(int milliseconds)
{
    QEventLoop loop;
    QTimer::singleShot(milliseconds, &loop, &QEventLoop::quit);
    loop.exec();
}
