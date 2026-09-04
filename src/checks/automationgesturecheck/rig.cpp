#include "rig.h"

#include <QAction>
#include <QCoreApplication>
#include <QEventLoop>
#include <QGuiApplication>
#include <QImage>
#include <QMouseEvent>
#include <QQuickWindow>
#include <QTimer>
#include <QWidget>
#include <QWindow>
#include <algorithm>
#include <cstring>
#include <utility>

#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "core/miditimeline.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timelinebandlayout.h"

namespace {
constexpr double kCheckSampleRate = 48000.0;

const QWidget *automationHostWidget(const AutomationPage &page)
{
    return qobject_cast<const SongView *>(page.parent());
}

// Rig plot helpers speak plot-local content coordinates; normalized
// TimelinePointerInput values speak plot-local viewport coordinates, so remove
// vertical scroll once here and map globals through the recorded plot host.
songview::TimelinePointerInput pointerInput(AutomationGestureCheckRig &rig, const QPointF &position,
                                            Qt::MouseButton button, Qt::MouseButtons buttons,
                                            Qt::KeyboardModifiers modifiers)
{
    const QPointF viewportPosition = rig.automationContentToViewport(position);
    return {
        .position = viewportPosition,
        .globalPosition = rig.automationHost().mapToGlobal(viewportPosition),
        .button = button,
        .buttons = buttons,
        .modifiers = modifiers,
        .surface = songview::TimelineInputSurface::Plot,
        .host = &rig.automationHost(),
    };
}
} // namespace

AutomationInputHost::AutomationInputHost(const AutomationPage &page,
                                         const songview::TimelineInputItem &gutterInput)
    : m_page(page)
    , m_gutterInput(gutterInput)
    , m_dpr(qGuiApp->devicePixelRatio())
{}

QCursor AutomationInputHost::cursor() const noexcept
{
    return m_cursorSet ? m_cursor : QCursor{Qt::ArrowCursor};
}

bool AutomationInputHost::cursorSet() const noexcept
{
    return m_cursorSet;
}

int AutomationInputHost::cursorAssignments() const noexcept
{
    return m_cursorAssignments;
}

int AutomationInputHost::cursorClears() const noexcept
{
    return m_cursorClears;
}

int AutomationInputHost::focusRequests() const noexcept
{
    return m_focusRequests;
}

Qt::FocusReason AutomationInputHost::lastFocusReason() const noexcept
{
    return m_lastFocusReason;
}

int AutomationInputHost::grabReleases() const noexcept
{
    return m_grabReleases;
}

int AutomationInputHost::globalMappings() const noexcept
{
    return m_globalMappings;
}

const QString &AutomationInputHost::accessibilityDescription() const noexcept
{
    return m_accessibilityDescription;
}

const QPointF &AutomationInputHost::globalOffset() const noexcept
{
    return m_globalOffset;
}

void AutomationInputHost::setDevicePixelRatio(qreal dpr) noexcept
{
    m_dpr = dpr;
}

void AutomationInputHost::setGlobalOffset(QPointF offset) noexcept
{
    m_globalOffset = offset;
}

QRectF AutomationInputHost::bounds() const
{
    const QSize size = m_page.automationViewportSize();
    const qreal gutterWidth = m_gutterInput.bounds().width();
    return QRectF(0.0, 0.0, std::max(0.0, qreal(size.width()) - gutterWidth), qreal(size.height()));
}

qreal AutomationInputHost::devicePixelRatio() const
{
    return m_dpr;
}

QFont AutomationInputHost::font() const
{
    if (const QWidget *view = automationHostWidget(m_page))
        return view->font();
    return qGuiApp->font();
}

QPalette AutomationInputHost::palette() const
{
    if (const QWidget *view = automationHostWidget(m_page))
        return view->palette();
    return qGuiApp->palette();
}

QPointF AutomationInputHost::mapFromGlobal(QPointF position) const
{
    ++m_globalMappings;
    return position - m_globalOffset;
}

QPointF AutomationInputHost::mapToGlobal(QPointF position) const
{
    ++m_globalMappings;
    return position + m_globalOffset;
}

void AutomationInputHost::requestFocus(Qt::FocusReason reason)
{
    ++m_focusRequests;
    m_lastFocusReason = reason;
}

void AutomationInputHost::setCursor(const QCursor &cursor)
{
    m_cursor = cursor;
    m_cursorSet = true;
    ++m_cursorAssignments;
}

void AutomationInputHost::clearCursor()
{
    m_cursorSet = false;
    ++m_cursorClears;
}

void AutomationInputHost::releasePointerGrab()
{
    ++m_grabReleases;
}

void AutomationInputHost::setAccessibilityDescription(const QString &description)
{
    m_accessibilityDescription = description;
}

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
    if (m_page && m_inputHost) {
        m_page->canvas()->detachInputHost(*m_inputHost);
        if (m_automationPlotInput && m_productionInteraction)
            m_automationPlotInput->setInteraction(m_productionInteraction);
    }
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

AutomationInputHost &AutomationGestureCheckRig::automationHost() noexcept
{
    return *m_inputHost;
}

const AutomationInputHost &AutomationGestureCheckRig::automationHost() const noexcept
{
    return *m_inputHost;
}
songview::TimelineInputItem &AutomationGestureCheckRig::automationGutterInput() noexcept
{
    return *m_automationGutterInput;
}

const songview::TimelineInputItem &AutomationGestureCheckRig::automationGutterInput() const noexcept
{
    return *m_automationGutterInput;
}

QCursor AutomationGestureCheckRig::automationCursor() const noexcept
{
    return m_inputHost->cursor();
}

bool AutomationGestureCheckRig::automationCursorSet() const noexcept
{
    return m_inputHost->cursorSet();
}

qreal AutomationGestureCheckRig::automationDpr() const noexcept
{
    return m_inputHost->devicePixelRatio();
}

int AutomationGestureCheckRig::automationContentHeight() const noexcept
{
    return page().automationContentHeight();
}

QSize AutomationGestureCheckRig::automationViewportSize() const noexcept
{
    return m_inputHost->bounds().size().toSize();
}

void AutomationGestureCheckRig::resizeAutomationViewport(const QSize &size)
{
    const int gutterWidth = qRound(m_automationGutterInput->bounds().width());
    page().synchronizeAutomationViewport(
        QSize(std::max(0, size.width() + gutterWidth), size.height()));
}

void AutomationGestureCheckRig::canvasHostAppearanceChanged()
{
    canvas().hostAppearanceChanged();
}

songview::TimelineInputItem &AutomationGestureCheckRig::voiceInput() noexcept
{
    return *m_voiceInput;
}

const songview::TimelineInputItem &AutomationGestureCheckRig::voiceInput() const noexcept
{
    return *m_voiceInput;
}

const songview::TimelineQuickScene &AutomationGestureCheckRig::quickScene() const noexcept
{
    return *m_quickScene;
}

QAction *AutomationGestureCheckRig::pencilModeAction() const noexcept
{
    if (!m_view)
        return nullptr;
    for (QAction *action : m_view->actions()) {
        if (action->text() == QStringLiteral("Pencil Mode"))
            return action;
    }
    return nullptr;
}

AutomationGeometry AutomationGestureCheckRig::geometry() const
{
    return AutomationGeometry::resolve();
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
    const QPointF position(m_view->camera().displayX(tick, 0.0, automationDpr()),
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
    gutterMousePress(tempoHeaderPoint());
    gutterMouseRelease(tempoHeaderPoint());
    pump();
    return !canvas().laneBody(kTempoHandle).isEmpty();
}

QPointF AutomationGestureCheckRig::tempoHeaderPoint() const
{
    const QRect tempo = canvas().pinnedTempoRect();
    return {m_automationGutterInput->bounds().center().x(), qreal(tempo.center().y())};
}

QPointF AutomationGestureCheckRig::tempoBodyPoint(double tick, int bpm) const
{
    return pointAt(kTempoHandle, tick, bpm).position;
}

QPointF AutomationGestureCheckRig::automationContentToViewport(const QPointF &position) const
{
    return {position.x(), position.y() - qreal(page().verticalScroll())};
}

QPoint AutomationGestureCheckRig::automationContentToViewport(const QPoint &position) const
{
    return {position.x(), position.y() - page().verticalScroll()};
}

QRect AutomationGestureCheckRig::automationContentToViewport(const QRect &rect) const
{
    return rect.translated(automationContentToViewport(QPoint{}));
}

QRect AutomationGestureCheckRig::automationViewportInContent() const
{
    return {QPoint(0, page().verticalScroll()), page().automationViewportSize()};
}

QImage AutomationGestureCheckRig::renderAutomationViewport(QString *error)
{
    const auto &geometry = view().timelineBandLayout().geometry(songview::TimelineBand::Automation);
    return checks::support::captureQuickBand(view(), geometry ? geometry->rect : QRect{}, error);
}

QImage AutomationGestureCheckRig::renderAutomationContent(const QRect &contentRect, QString *error)
{
    const QRect viewportRect = automationContentToViewport(contentRect);
    if (!QRect{QPoint(0, 0), page().automationViewportSize()}.contains(viewportRect)) {
        if (error)
            *error = QStringLiteral("Automation content crop is outside the automation viewport");
        return {};
    }
    const QImage viewportImage = renderAutomationViewport(error);
    if (viewportImage.isNull())
        return {};
    const qreal dpr = viewportImage.devicePixelRatio();
    const int left = qRound(viewportRect.left() * dpr);
    const int top = qRound(viewportRect.top() * dpr);
    const int right = qRound((viewportRect.right() + 1) * dpr);
    const int bottom = qRound((viewportRect.bottom() + 1) * dpr);
    const QRect crop{left, top, right - left, bottom - top};
    if (!viewportImage.rect().contains(crop)) {
        if (error)
            *error = QStringLiteral("Automation content crop is outside the viewport framebuffer");
        return {};
    }
    QImage result = viewportImage.copy(crop);
    result.setDevicePixelRatio(dpr);
    return result;
}

QImage AutomationGestureCheckRig::renderVoiceChanges(QString *error)
{
    const auto &geometry =
        view().timelineBandLayout().geometry(songview::TimelineBand::VoiceChanges);
    return checks::support::captureQuickBand(view(), geometry ? geometry->rect : QRect{}, error);
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
    // Mirror MainWindow's document-change path: the drawer paints Voice
    // changes from SongViewModel, so refreshing only the page leaves its
    // presentation model on the fixture's original timeline.
    m_timeline = document().buildTimeline(kCheckSampleRate);
    m_view->updateSong(m_timeline.get());
    refreshPage();
    pump();
}

void AutomationGestureCheckRig::setAutomationZoom(double zoom)
{
    m_view->setEditorTimeZoom(zoom);
    m_live.timeZoom = m_view->camera().pxPerBeat();
    m_live.horizontalScroll = m_view->camera().scrollX();
    refreshPage();
    pump();
}

void AutomationGestureCheckRig::setAutomationScroll(double scroll)
{
    m_view->setEditorHorizontalScroll(scroll);
    m_live.horizontalScroll = m_view->camera().scrollX();
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
    canvas().pointerPress(
        pointerInput(*this, position, button, Qt::MouseButtons(button), modifiers));
}

bool AutomationGestureCheckRig::dispatchMousePress(const QPointF &position,
                                                   Qt::KeyboardModifiers modifiers,
                                                   Qt::MouseButton button)
{
    return canvas().pointerPress(
        pointerInput(*this, position, button, Qt::MouseButtons(button), modifiers));
}

void AutomationGestureCheckRig::mouseMove(const QPointF &position, Qt::MouseButtons buttons,
                                          Qt::KeyboardModifiers modifiers)
{
    canvas().pointerMove(pointerInput(*this, position, Qt::NoButton, buttons, modifiers));
}

void AutomationGestureCheckRig::mouseRelease(const QPointF &position,
                                             Qt::KeyboardModifiers modifiers,
                                             Qt::MouseButton button)
{
    canvas().pointerRelease(pointerInput(*this, position, button, Qt::NoButton, modifiers));
}

void AutomationGestureCheckRig::mouseDoubleClick(const QPointF &position,
                                                 Qt::KeyboardModifiers modifiers)
{
    canvas().pointerDoubleClick(
        pointerInput(*this, position, Qt::LeftButton, Qt::LeftButton, modifiers));
}

void AutomationGestureCheckRig::gutterMousePress(const QPointF &position,
                                                 Qt::KeyboardModifiers modifiers,
                                                 Qt::MouseButton button)
{
    checks::events::sendMouse(*m_automationGutterInput, QEvent::MouseButtonPress,
                              automationContentToViewport(position), button,
                              Qt::MouseButtons(button), modifiers);
}

bool AutomationGestureCheckRig::dispatchGutterMousePress(const QPointF &position,
                                                         Qt::KeyboardModifiers modifiers,
                                                         Qt::MouseButton button)
{
    const QPointF viewportPosition = automationContentToViewport(position);
    QMouseEvent event(QEvent::MouseButtonPress, viewportPosition,
                      m_automationGutterInput->mapToGlobal(viewportPosition), button,
                      Qt::MouseButtons(button), modifiers);
    event.setAccepted(false);
    QCoreApplication::sendEvent(m_automationGutterInput, &event);
    return event.isAccepted();
}

void AutomationGestureCheckRig::gutterMouseMove(const QPointF &position, Qt::MouseButtons buttons,
                                                Qt::KeyboardModifiers modifiers)
{
    checks::events::sendMouse(*m_automationGutterInput, QEvent::MouseMove,
                              automationContentToViewport(position), Qt::NoButton, buttons,
                              modifiers);
}

void AutomationGestureCheckRig::gutterMouseRelease(const QPointF &position,
                                                   Qt::KeyboardModifiers modifiers,
                                                   Qt::MouseButton button)
{
    checks::events::sendMouse(*m_automationGutterInput, QEvent::MouseButtonRelease,
                              automationContentToViewport(position), button, Qt::NoButton,
                              modifiers);
}

void AutomationGestureCheckRig::voiceMousePress(const QPointF &position,
                                                Qt::KeyboardModifiers modifiers)
{
    checks::events::sendMouse(*m_voiceInput, QEvent::MouseButtonPress, position, Qt::LeftButton,
                              Qt::LeftButton, modifiers);
}

bool AutomationGestureCheckRig::dispatchVoiceMousePress(const QPointF &position,
                                                        Qt::KeyboardModifiers modifiers)
{
    QMouseEvent event(QEvent::MouseButtonPress, position, m_voiceInput->mapToGlobal(position),
                      Qt::LeftButton, Qt::LeftButton, modifiers);
    event.setAccepted(false);
    QCoreApplication::sendEvent(m_voiceInput, &event);
    return event.isAccepted();
}

void AutomationGestureCheckRig::voiceMouseMove(const QPointF &position,
                                               Qt::KeyboardModifiers modifiers)
{
    checks::events::sendMouse(*m_voiceInput, QEvent::MouseMove, position, Qt::NoButton,
                              Qt::LeftButton, modifiers);
}

void AutomationGestureCheckRig::voiceMouseRelease(const QPointF &position,
                                                  Qt::KeyboardModifiers modifiers)
{
    checks::events::sendMouse(*m_voiceInput, QEvent::MouseButtonRelease, position, Qt::LeftButton,
                              Qt::NoButton, modifiers);
}

void AutomationGestureCheckRig::keyToVoiceArea(QEvent::Type type, int key,
                                               Qt::KeyboardModifiers modifiers)
{
    checks::events::sendKey(*m_voiceInput, type, key, modifiers, QString{}, false, 1);
}

void AutomationGestureCheckRig::keyToArea(QEvent::Type type, int key,
                                          Qt::KeyboardModifiers modifiers, bool autoRepeat)
{
    const songview::TimelineKeyInput keyInput{key, modifiers, QString{}, autoRepeat};
    if (type == QEvent::KeyPress)
        canvas().keyPress(keyInput);
    else if (type == QEvent::KeyRelease)
        canvas().keyRelease(keyInput);
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
    waitForTimers(0);
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents(QEventLoop::AllEvents);
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
    pump();
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
    m_timeline = songDocument.buildTimeline(kCheckSampleRate);
    m_view = std::make_unique<SongView>();
    m_view->resize(960, 720);
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
    m_view->show();
    pump();
    auto *drawer = m_view->editorDrawer();
    m_page = drawer ? drawer->automationPage() : nullptr;
    m_quickScene = m_view->findChild<songview::TimelineQuickScene *>();
    auto *quickCanvas =
        m_view->findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    QQuickItem *const quickRoot = quickCanvas ? quickCanvas->rootObject() : nullptr;
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
    m_inputHost = std::make_unique<AutomationInputHost>(*m_page, *m_automationGutterInput);
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

void AutomationGestureCheckRig::refreshPage()
{
    m_live.documentRevision = document().revision();
    m_page->refreshLiveState(m_live);
}
