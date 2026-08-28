#include "rig.h"

#include <QAction>
#include <QCoreApplication>
#include <QEventLoop>
#include <QImage>
#include <QTimer>
#include <QWindow>
#include <algorithm>
#include <cstring>
#include <utility>

#include "checks/support/eventsynth.h"
#include "core/miditimeline.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/songview.h"

std::unique_ptr<AutomationGestureCheckRig>
AutomationGestureCheckRig::create(const QString &project, const QString &song, QString &error)
{
    error.clear();
    auto loadedSong = checks::LoadedSong::load(project, song, error);
    if (!loadedSong)
        return nullptr;
    auto rig = std::unique_ptr<AutomationGestureCheckRig>(new AutomationGestureCheckRig);
    rig->m_song = std::move(loadedSong);
    if (!rig->initialize(error))
        return nullptr;
    return rig;
}

AutomationGestureCheckRig::~AutomationGestureCheckRig()
{
    if (m_view) {
        m_view->setSong(nullptr, nullptr);
        m_view->setDocument(nullptr);
    }
}

SongDocument &AutomationGestureCheckRig::document() noexcept
{
    return m_song->document();
}

const SongDocument &AutomationGestureCheckRig::document() const noexcept
{
    return m_song->document();
}

SongView &AutomationGestureCheckRig::view() noexcept
{
    return *m_view;
}

const SongView &AutomationGestureCheckRig::view() const noexcept
{
    return *m_view;
}

AutomationPage &AutomationGestureCheckRig::page() noexcept
{
    return *m_page;
}

const AutomationPage &AutomationGestureCheckRig::page() const noexcept
{
    return *m_page;
}

AutomationCanvas &AutomationGestureCheckRig::canvas() noexcept
{
    return *m_page->canvas();
}

const AutomationCanvas &AutomationGestureCheckRig::canvas() const noexcept
{
    return *m_page->canvas();
}

QAction *AutomationGestureCheckRig::pencilModeAction() const noexcept
{
    for (QAction *action : m_page->actions()) {
        if (action->text() == QStringLiteral("Pencil Mode"))
            return action;
    }
    return nullptr;
}

AutomationGeometry AutomationGestureCheckRig::geometry() const
{
    auto result = AutomationGeometry::resolve();
    result.plotOrigin = canvas().plotOrigin();
    return result;
}

AutomationProjection AutomationGestureCheckRig::projection() const
{
    return {geometry(), m_page};
}

int AutomationGestureCheckRig::rowIndex(const Lane &lane) const noexcept
{
    const auto &rows = canvas().rows();
    for (int index = 0; index < int(rows.size()); ++index) {
        if (rows[std::size_t(index)].id == lane.row)
            return index;
    }
    return -1;
}

LaneHandle AutomationGestureCheckRig::handleFor(const Lane &lane) const noexcept
{
    const int index = rowIndex(lane);
    return index >= 0 ? LaneHandle{index + 1} : LaneHandle{};
}

QRect AutomationGestureCheckRig::bodyFor(LaneHandle handle) const
{
    return canvas().laneBody(handle);
}

QRect AutomationGestureCheckRig::bodyFor(const Lane &lane) const
{
    return bodyFor(handleFor(lane));
}

namespace {

class MappingLane final : public NodeLane
{
  public:
    MappingLane(int minimum, int maximum) noexcept : m_minimum(minimum), m_maximum(maximum) {}
    QString title() const override { return {}; }
    std::vector<NodePoint> points() const override { return {}; }
    int minimumValue() const override { return m_minimum; }
    int maximumValue() const override { return m_maximum; }
    QString valueText(int) const override { return {}; }
    bool promptValue(QWidget *, int, int *) const override { return false; }
    void replaceSpan(uint64_t, uint64_t, const std::vector<NodePoint> &) override {}

  private:
    int m_minimum = 0;
    int m_maximum = 0;
};

} // namespace

AutomationGestureCheckRig::ValueRange AutomationGestureCheckRig::valueRange(LaneHandle handle) const
{
    if (!handle.valid() || handle.index == 0)
        return {CoreTimeDefaults::kMinTempoBpm, CoreTimeDefaults::kMaxTempoBpm};
    const auto &rows = canvas().rows();
    const int row = handle.index - 1;
    if (row < 0 || row >= int(rows.size()))
        return {0, 127};
    const auto controller = rows[std::size_t(row)].id.controller;
    return {CoreTimeDefaults::laneValueMinimum(controller),
            CoreTimeDefaults::laneValueMaximum(controller)};
}

AutomationProjection::PointerMapping
AutomationGestureCheckRig::mappingAt(LaneHandle handle, const QPointF &position) const
{
    const auto range = valueRange(handle);
    MappingLane lane(range.min, range.max);
    return projection().pointerMapping(lane, bodyFor(handle), position.x(), position.y());
}

AutomationGestureCheckRig::InputPoint
AutomationGestureCheckRig::pointAt(LaneHandle handle, double tick, int value) const
{
    const auto geom = geometry();
    const auto range = valueRange(handle);
    const QRect body = bodyFor(handle);
    const QPointF position(m_view->displayX(tick, geom.plotOrigin, canvas().devicePixelRatioF()),
                           AutomationProjection::valueY(body, geom, range.min, range.max, value));
    return {position, mappingAt(handle, position)};
}

AutomationGestureCheckRig::InputPoint
AutomationGestureCheckRig::pointAt(const Lane &lane, double tick, int value) const
{
    return pointAt(handleFor(lane), tick, value);
}

bool AutomationGestureCheckRig::expandTempo()
{
    if (!canvas().laneBody(kTempoHandle).isEmpty())
        return true;
    mousePress(tempoHeaderPoint());
    mouseRelease(tempoHeaderPoint());
    pump();
    return !canvas().laneBody(kTempoHandle).isEmpty();
}

QPointF AutomationGestureCheckRig::tempoHeaderPoint() const
{
    const QRect tempo = canvas().pinnedTempoRect();
    return {geometry().plotOrigin / 2.0, qreal(tempo.center().y())};
}

QPointF AutomationGestureCheckRig::tempoBodyPoint(double tick, int bpm) const
{
    return pointAt(kTempoHandle, tick, bpm).position;
}

QImage AutomationGestureCheckRig::renderArea()
{
    return canvas().grab().toImage();
}

AutomationGestureCheckRig::Snapshot AutomationGestureCheckRig::snapshot(int track,
                                                                        uint8_t controller) const
{
    SongDocument &document = m_song->document();
    return {document.smf().write(), document.revision(), document.undoStack()->index(),
            document.lanePoints(track, controller)};
}

void AutomationGestureCheckRig::documentChanged()
{
    m_page->documentChanged();
    refreshPage();
    pump();
}

void AutomationGestureCheckRig::setAutomationZoom(double zoom)
{
    m_live.timeZoom = zoom;
    m_view->setEditorTimeZoom(zoom);
    m_live.horizontalScroll = m_view->viewState().scrollPx;
    refreshPage();
    pump();
}

void AutomationGestureCheckRig::setAutomationScroll(double scroll)
{
    m_live.horizontalScroll = scroll;
    m_view->setEditorHorizontalScroll(scroll);
    refreshPage();
    pump();
}

void AutomationGestureCheckRig::setPersistentPencil(bool enabled)
{
    if (QAction *action = pencilModeAction())
        action->setChecked(enabled);
}

void AutomationGestureCheckRig::mousePress(const QPointF &position, Qt::KeyboardModifiers modifiers,
                                           Qt::MouseButton button)
{
    checks::events::sendMouse(canvas(), QEvent::MouseButtonPress, position, button, button,
                              modifiers);
}

void AutomationGestureCheckRig::mouseMove(const QPointF &position, Qt::MouseButtons buttons,
                                          Qt::KeyboardModifiers modifiers)
{
    checks::events::sendMouse(canvas(), QEvent::MouseMove, position, Qt::NoButton, buttons,
                              modifiers);
}

void AutomationGestureCheckRig::mouseRelease(const QPointF &position,
                                             Qt::KeyboardModifiers modifiers,
                                             Qt::MouseButton button)
{
    checks::events::sendMouse(canvas(), QEvent::MouseButtonRelease, position, button, Qt::NoButton,
                              modifiers);
}

void AutomationGestureCheckRig::mouseDoubleClick(const QPointF &position,
                                                 Qt::KeyboardModifiers modifiers)
{
    checks::events::sendMouse(canvas(), QEvent::MouseButtonDblClick, position, Qt::LeftButton,
                              Qt::LeftButton, modifiers);
}

void AutomationGestureCheckRig::keyToArea(QEvent::Type type, int key,
                                          Qt::KeyboardModifiers modifiers, bool autoRepeat)
{
    checks::events::sendKey(canvas(), type, key, modifiers, QString{}, autoRepeat, 1);
}

void AutomationGestureCheckRig::keyToView(QEvent::Type type, int key,
                                          Qt::KeyboardModifiers modifiers, bool autoRepeat)
{
    checks::events::sendKey(*m_view, type, key, modifiers, QString{}, autoRepeat, 1);
}

void AutomationGestureCheckRig::keyToWindow(QEvent::Type type, int key,
                                            Qt::KeyboardModifiers modifiers, bool autoRepeat)
{
    checks::events::sendKey(*m_view->windowHandle(), type, key, modifiers, QString{}, autoRepeat,
                            1);
}

void AutomationGestureCheckRig::pump()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
}

void AutomationGestureCheckRig::waitForTimers(int milliseconds)
{
    QEventLoop loop;
    QTimer::singleShot(milliseconds, &loop, &QEventLoop::quit);
    loop.exec();
}

bool AutomationGestureCheckRig::isIdle() const noexcept
{
    return !canvas().isPanning() && !view().userGestureActive();
}

void AutomationGestureCheckRig::resetView(double zoom, double scroll)
{
    setAutomationZoom(zoom);
    setAutomationScroll(scroll);
    pump();
}

void AutomationGestureCheckRig::commitTimers(int milliseconds)
{
    waitForTimers(milliseconds);
}

bool AutomationGestureCheckRig::initialize(QString &error)
{
    SongDocument &songDocument = document();
    if (songDocument.engineTrackCount() == 0) {
        error = QStringLiteral("%1 has no engine tracks").arg(m_song->songInfo().label);
        return false;
    }
    songDocument.addLanePoint(volume.track, volume.controller, 24, 32);
    songDocument.writeLanePoints(lfo.track, lfo.controller, 96, 96, {{96, 32}, {96, 96}});
    m_voicegroup = std::make_unique<LoadedVoiceGroup>();
    m_voicegroup->voices[3].type = VOICE_NOISE;
    std::strncpy(m_voicegroup->voiceNames[3], "automation-voice",
                 sizeof(m_voicegroup->voiceNames[3]) - 1);
    m_timeline = songDocument.buildTimeline(48000.0);
    m_view = std::make_unique<SongView>();
    m_view->resize(960, 720);
    m_view->setDocument(&songDocument);
    m_view->setSong(m_timeline.get(), m_voicegroup.get());
    EditorViewState state;
    state.emptyLanes.insert(pan.row);
    m_view->applyEditorViewState(state);
    m_view->setDrawerActivePage(EditorDrawerPage::Automations);
    m_view->setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    m_view->setDrawerSectionHeight(EditorDrawerPage::Automations, 360);
    m_view->show();
    pump();
    auto *drawer = m_view->editorDrawer();
    m_page = drawer ? drawer->automationPage() : nullptr;
    if (!m_page) {
        error = QStringLiteral("concrete SongView did not expose AutomationPage");
        return false;
    }
    m_page->resize(960, 360);
    m_page->songChanged();
    m_live.documentRevision = songDocument.revision();
    m_live.timeZoom = 96.0;
    m_live.editCursorTick = 24;
    m_view->setEditorTimeZoom(m_live.timeZoom);
    m_live.horizontalScroll = m_view->viewState().scrollPx;
    m_page->refreshLiveState(m_live);
    m_page->show();
    pump();
    return true;
}

void AutomationGestureCheckRig::refreshPage()
{
    m_live.documentRevision = document().revision();
    m_page->refreshLiveState(m_live);
}
