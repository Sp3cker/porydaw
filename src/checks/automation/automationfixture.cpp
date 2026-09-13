#include "checks/automation/tst_automationediting.h"

#include <QtTest>

#include <algorithm>
#include <array>
#include <optional>
#include <utility>

#include <QAction>
#include <QCoreApplication>
#include <QEnterEvent>
#include <QKeyEvent>
#include <QQuickItem>
#include <QWheelEvent>

#include "checks/support/support.h"
#include "checks/support/timelinequickcheck.h"
#include "core/timedefaults.h"
#include "core/tracklimits.h"
#include "project/projectidentity.h"
#include "project/voicegroupsource.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/tempolane.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"

namespace {

constexpr uint8_t kPilotController = 10;
constexpr Tick kPilotDraggedTick = 48;
constexpr Tick kPilotIndependentTick = 96;
constexpr Tick kPilotEndTick = 192;
constexpr int kPilotDraggedValue = 40;
constexpr int kPilotIndependentValue = 100;
constexpr double kFixtureSampleRate = 48000.0;

SmfEvent programChange(Tick tick, uint8_t program)
{
    SmfEvent event;
    event.status = 0xC0;
    event.tick = tick;
    event.data0 = program;
    return event;
}

SmfEvent controlChange(Tick tick, uint8_t controller, uint8_t value)
{
    SmfEvent event;
    event.status = 0xB0;
    event.tick = tick;
    event.data0 = controller;
    event.data1 = value;
    return event;
}

SmfFile pilotSmf()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    SmfTrack track;
    // MidiTimeline derives its editable extent from events, not the SMF end marker.
    track.events = {
        programChange(0, 0),
        controlChange(kPilotEndTick, CoreTimeDefaults::kCcVolume,
                      uint8_t(CoreTimeDefaults::controllerDefault(CoreTimeDefaults::kCcVolume))),
    };
    track.endTick = kPilotEndTick;
    smf.tracks.push_back(track);
    return smf;
}

std::pair<int, int> valueRange(const AutomationPage &page, LaneHandle lane)
{
    if (!lane.valid() || lane.index == 0)
        return {CoreTimeDefaults::kMinTempoBpm, CoreTimeDefaults::kMaxTempoBpm};

    const auto &rows = page.canvas()->rows();
    const int row = lane.index - 1;
    if (row < 0 || row >= int(rows.size()))
        return {0, 127};

    const uint8_t controller = rows[std::size_t(row)].id.controller;
    return {CoreTimeDefaults::laneValueMinimum(controller),
            CoreTimeDefaults::laneValueMaximum(controller)};
}

} // namespace

QPoint automation_test::windowFromContent(const AutomationPage &,
                                          const songview::TimelineInputItem &input,
                                          const QPointF &contentPoint)
{
    return input.mapToScene(contentPoint).toPoint();
}

QPointF automation_test::contentFromWindow(const AutomationPage &,
                                           const songview::TimelineInputItem &input,
                                           const QPoint &windowPoint)
{
    return input.mapFromScene(QPointF(windowPoint));
}

QPointF automation_test::effectiveDragContent(const AutomationPage &,
                                              const songview::TimelineInputItem &input,
                                              const QPoint &press, const QPoint &activation,
                                              const QPoint &end)
{
    return input.mapFromScene(QPointF(press)) + input.mapFromScene(QPointF(end)) -
           input.mapFromScene(QPointF(activation));
}

void AutomationEditingTest::init()
{
    m_heldButtons = Qt::NoButton;
    m_lastModifiers = Qt::NoModifier;
    m_heldKeys.clear();
    m_windowEntered = false;
    m_lastWindowPos = {};

    m_bank = LoadedVoiceGroup{};
    m_bank.voices[0].type = VOICE_DIRECTSOUND;
    m_bank.voices[1].type = VOICE_SQUARE_1;
    m_bank.voices[2].type = VOICE_PROGRAMMABLE_WAVE;
    m_bank.voices[3].type = VOICE_NOISE;

    QVERIFY(stageSong(pilotSmf()));
    arrangeCcLane();

    QTRY_VERIFY(m_quickWindow && m_quickWindow->isVisible() && m_quickWindow->isExposed());
    QTRY_VERIFY(m_automationInput && !m_automationInput->bounds().isEmpty());
    QTRY_COMPARE(m_automationInput->window(), m_quickWindow.data());

    // The pilot drives the Pan lane, so its rendered selector label must
    // activate it before the plot probes run against the single active
    // parameter.
    const EditorAutomationRowId ccRow{EditorAutomationRowKind::ControlChange, 0, kPilotController};
    QVERIFY(activateParameter(ccRow));

    const LaneHandle lane = findRow(ccRow);
    QTRY_VERIFY(lane.valid());
    QTRY_VERIFY(!laneBody(lane).isEmpty());

    const QPointF draggedViewport = ccPoint(kPilotDraggedTick, kPilotDraggedValue);
    QVERIFY(m_automationInput->bounds().contains(draggedViewport));
    QVERIFY(laneValue(kPilotDraggedTick) == kPilotDraggedValue);
    QVERIFY(laneValue(kPilotIndependentTick) == kPilotIndependentValue);
    QVERIFY(focusAutomationBand());
}

void AutomationEditingTest::cleanup()
{
    const bool mouseGrabCleared = quiesceInput();
    m_page.clear();
    m_automationInput.clear();
    m_automationGutterInput.clear();
    m_voiceInput.clear();
    m_quickWindow.clear();
    m_tab.reset();

    QVERIFY(mouseGrabCleared);
}

bool AutomationEditingTest::stage(SmfFile smf)
{
    const bool inputCleared = quiesceInput();
    m_page.clear();
    m_automationInput.clear();
    m_automationGutterInput.clear();
    m_voiceInput.clear();
    m_quickWindow.clear();
    m_tab.reset();
    return inputCleared && stageSong(std::move(smf));
}

bool AutomationEditingTest::stageSong(SmfFile smf)
{
    const std::optional<SongName> name = SongName::create(QStringLiteral("automation-editing"));
    const std::optional<VoicegroupId> identity =
        VoicegroupId::create(QStringLiteral("automation-editing-check"), QString());
    if (!name || !identity)
        return false;

    auto candidate = std::make_unique<SongTab>(std::move(*name));
    candidate->resize(960, 480);
    candidate->setSampleRate(kFixtureSampleRate);

    SongInfo song;
    song.label = QStringLiteral("automation-editing");
    song.hasMid = true;
    candidate->applyMidiStage(std::move(song), std::move(smf), track_limits::kHardwareCapacity);
    if (!candidate->presentationError().isEmpty())
        return false;
    candidate->applyBankView(LoadedBankView{*identity, borrowVoicegroupLease(&m_bank), QString()});
    candidate->applyVoicegroupBound(*identity);
    if (!candidate->isReady() || candidate->voicegroupLease().get() != &m_bank)
        return false;
    checks::support::bindEditActionsForTest(candidate->view());

    SongView &view = candidate->view();
    view.setDrawerActivePage(EditorDrawerPage::Automations);
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, 320);
    AutomationPage *const candidatePage =
        view.editorDrawer() ? view.editorDrawer()->automationPage() : nullptr;
    songview::TimelineQuickView *const quick = view.quickView();
    QQuickWindow *const candidateWindow = quick ? quick->quickWindow() : nullptr;
    QObject *const quickRoot = quick ? quick->rootObject() : nullptr;
    auto *const candidateAutomation = quickRoot
                                          ? quickRoot->findChild<songview::TimelineInputItem *>(
                                                QStringLiteral("timelineAutomationInput"))
                                          : nullptr;
    auto *const candidateGutter = quickRoot ? quickRoot->findChild<songview::TimelineInputItem *>(
                                                  QStringLiteral("timelineAutomationGutterInput"))
                                            : nullptr;
    auto *const candidateVoice = quickRoot ? quickRoot->findChild<songview::TimelineInputItem *>(
                                                 QStringLiteral("timelineVoiceChangesInput"))
                                           : nullptr;
    if (!candidatePage || !candidateWindow || !candidateAutomation || !candidateGutter ||
        !candidateVoice) {
        return false;
    }

    candidate->show();
    // Staged contract mirrors the tail below plus exposure: only the
    // Automations section is staged visible, so hidden bands (voice,
    // velocity) legitimately keep empty bounds and must not gate staging.
    if (!QTest::qWaitFor([candidateWindow, candidateAutomation] {
            return candidateAutomation && candidateWindow->isVisible() &&
                   candidateWindow->isExposed() && !candidateAutomation->bounds().isEmpty() &&
                   candidateAutomation->window() == candidateWindow;
        })) {
        return false;
    }

    m_page = candidatePage;
    m_automationInput = candidateAutomation;
    m_automationGutterInput = candidateGutter;
    m_voiceInput = candidateVoice;
    m_windowEntered = false;
    m_quickWindow = candidateWindow;
    m_tab = std::move(candidate);
    return !m_automationInput->bounds().isEmpty() &&
           m_automationInput->window() == m_quickWindow.data();
}

bool AutomationEditingTest::quiesceInput()
{
    bool mouseGrabCleared = true;
    if (m_quickWindow) {
        QTest::keyClick(m_quickWindow, Qt::Key_Escape, Qt::NoModifier);
        for (const Qt::MouseButton button :
             std::array{Qt::LeftButton, Qt::RightButton, Qt::MiddleButton, Qt::BackButton,
                        Qt::ForwardButton}) {
            if (!m_heldButtons.testFlag(button))
                continue;
            QTest::mouseRelease(m_quickWindow, button, m_lastModifiers, m_lastWindowPos);
            m_heldButtons.setFlag(button, false);
        }
        for (auto key = m_heldKeys.crbegin(); key != m_heldKeys.crend(); ++key)
            QTest::keyRelease(m_quickWindow, *key, m_lastModifiers);
        if (QQuickItem *grabber = m_quickWindow->mouseGrabberItem())
            grabber->ungrabMouse();
        mouseGrabCleared = QTest::qWaitFor(
            [this] { return !m_quickWindow || !m_quickWindow->mouseGrabberItem(); });
    }
    m_heldButtons = Qt::NoButton;
    m_lastModifiers = Qt::NoModifier;
    m_heldKeys.clear();
    return mouseGrabCleared;
}

LaneHandle AutomationEditingTest::findRow(const EditorAutomationRowId &row) const
{
    if (!m_page)
        return {};
    if (row.kind == EditorAutomationRowKind::Tempo)
        return {0};

    const auto &rows = m_page->canvas()->rows();
    for (int index = 0; index < int(rows.size()); ++index) {
        if (rows[std::size_t(index)].id == row)
            return {index + 1};
    }
    return {};
}

QRect AutomationEditingTest::laneBody(LaneHandle lane) const
{
    return m_page ? m_page->canvas()->laneBody(lane) : QRect{};
}

QPointF AutomationEditingTest::inputPoint(LaneHandle lane, double tick, int value) const
{
    if (!m_tab || !m_automationInput)
        return {};

    const QRect body = laneBody(lane);
    if (body.isEmpty())
        return {};
    const auto [minimum, maximum] = valueRange(page(), lane);
    return {
        m_tab->view().camera().displayX(tick, 0.0, m_automationInput->devicePixelRatio()),
        AutomationProjection::valueY(body, AutomationGeometry::resolve(), minimum, maximum, value)};
}

AutomationProjection::PointerMapping
AutomationEditingTest::pointerMapping(LaneHandle lane, QPointF contentPoint) const
{
    if (!m_page || !m_tab || !lane.valid())
        return {};

    const QRect body = laneBody(lane);
    if (body.isEmpty())
        return {};

    const AutomationProjection projection{AutomationGeometry::resolve(), m_page.data()};
    if (lane.index == 0) {
        TempoLane tempoLane(m_tab->document());
        return projection.pointerMapping(tempoLane, body, contentPoint.x(), contentPoint.y());
    }

    const auto &rows = m_page->canvas()->rows();
    const int row = lane.index - 1;
    if (row < 0 || row >= int(rows.size()))
        return {};

    const EditorAutomationRowId &id = rows[std::size_t(row)].id;
    if (id.kind != EditorAutomationRowKind::ControlChange)
        return {};

    CCLaneAdapter ccLane(m_tab->document(), id.track, id.controller);
    return projection.pointerMapping(ccLane, body, contentPoint.x(), contentPoint.y());
}

QPoint AutomationEditingTest::windowPoint(const songview::TimelineInputItem &input,
                                          QPointF itemPoint) const
{
    if (!m_quickWindow || input.window() != m_quickWindow)
        return {};
    return input.mapToScene(itemPoint).toPoint();
}

QPoint AutomationEditingTest::automationWindowPoint(QPointF contentPoint) const
{
    return m_automationInput
               ? automation_test::windowFromContent(page(), *m_automationInput, contentPoint)
               : QPoint{};
}

QPoint AutomationEditingTest::automationGutterWindowPoint(QPointF contentPoint) const
{
    return m_automationGutterInput
               ? automation_test::windowFromContent(page(), *m_automationGutterInput, contentPoint)
               : QPoint{};
}

QPoint AutomationEditingTest::voiceWindowPoint(QPointF itemPoint) const
{
    return m_voiceInput ? windowPoint(*m_voiceInput, itemPoint) : QPoint{};
}

QPointF AutomationEditingTest::voicePoint(uint64_t tick) const
{
    if (!m_tab || !m_voiceInput)
        return {};
    return {m_tab->view().camera().displayX(double(tick), 0.0, m_voiceInput->devicePixelRatio()),
            m_voiceInput->bounds().center().y()};
}

void AutomationEditingTest::setPencilMode(bool enabled)
{
    if (QAction *const action = pencilModeAction(); action && action->isChecked() != enabled)
        action->trigger();
}

QAction *AutomationEditingTest::pencilModeAction() const
{
    if (!m_tab)
        return nullptr;
    EditorDrawer *const drawer = m_tab->view().editorDrawer();
    AutomationPage *const page = drawer ? drawer->automationPage() : nullptr;
    return page ? page->pencilModeAction() : nullptr;
}

songview::TimelineQuickScene *AutomationEditingTest::quickScene() const
{
    return m_tab ? m_tab->view().findChild<songview::TimelineQuickScene *>() : nullptr;
}

SongTab &AutomationEditingTest::tab() noexcept
{
    return *m_tab;
}

const SongTab &AutomationEditingTest::tab() const noexcept
{
    return *m_tab;
}

AutomationPage &AutomationEditingTest::page() noexcept
{
    return *m_page;
}

const AutomationPage &AutomationEditingTest::page() const noexcept
{
    return *m_page;
}

songview::TimelineInputItem &AutomationEditingTest::automationInput() noexcept
{
    return *m_automationInput;
}

songview::TimelineInputItem &AutomationEditingTest::automationGutterInput() noexcept
{
    return *m_automationGutterInput;
}

songview::TimelineInputItem &AutomationEditingTest::voiceChangeInput() noexcept
{
    return *m_voiceInput;
}

QQuickWindow &AutomationEditingTest::quickWindow() noexcept
{
    return *m_quickWindow;
}

AutomationEditingTest::FrozenDocumentState
AutomationEditingTest::frozenDocumentState(int documentChanges, int edits) const
{
    return {
        .smf = m_tab->document().smf().write(),
        .revision = m_tab->document().revision(),
        .undoCount = m_tab->document().undoStack()->count(),
        .undoIndex = m_tab->document().undoStack()->index(),
        .documentChanges = documentChanges,
        .edits = edits,
    };
}

void AutomationEditingTest::mousePress(Qt::MouseButton button, const QPoint &windowPos,
                                       Qt::KeyboardModifiers modifiers)
{
    if (!m_quickWindow)
        return;
    mouseMove(windowPos, modifiers);
    QTest::mousePress(m_quickWindow, button, modifiers, m_lastWindowPos);
    m_heldButtons.setFlag(button, true);
}

void AutomationEditingTest::mouseMove(const QPoint &windowPos, Qt::KeyboardModifiers modifiers)
{
    if (!m_quickWindow)
        return;
    m_lastWindowPos = windowPos;
    m_lastModifiers = modifiers;
    if (!m_windowEntered) {
        const QPointF windowPosition(m_lastWindowPos);
        QEnterEvent enter(windowPosition, windowPosition,
                          QPointF(m_quickWindow->mapToGlobal(m_lastWindowPos)));
        QCoreApplication::sendEvent(m_quickWindow, &enter);
        m_windowEntered = true;
    }
    QTest::mouseEvent(QTest::MouseMove, m_quickWindow, Qt::NoButton, modifiers, m_lastWindowPos);
}

void AutomationEditingTest::mouseRelease(Qt::MouseButton button, const QPoint &windowPos,
                                         Qt::KeyboardModifiers modifiers)
{
    if (!m_quickWindow)
        return;
    m_lastWindowPos = windowPos;
    m_lastModifiers = modifiers;
    QTest::mouseRelease(m_quickWindow, button, modifiers, m_lastWindowPos);
    m_heldButtons.setFlag(button, false);
}

void AutomationEditingTest::mouseDClick(Qt::MouseButton button, const QPoint &windowPos,
                                        Qt::KeyboardModifiers modifiers)
{
    if (!m_quickWindow)
        return;
    mouseMove(windowPos, modifiers);
    QTest::mouseDClick(m_quickWindow, button, modifiers, m_lastWindowPos);
}

void AutomationEditingTest::mousePress(const songview::TimelineInputItem &input,
                                       Qt::MouseButton button, QPointF itemPoint,
                                       Qt::KeyboardModifiers modifiers)
{
    mousePress(button, windowPoint(input, itemPoint), modifiers);
}

void AutomationEditingTest::mouseMove(const songview::TimelineInputItem &input, QPointF itemPoint,
                                      Qt::KeyboardModifiers modifiers)
{
    mouseMove(windowPoint(input, itemPoint), modifiers);
}

void AutomationEditingTest::mouseRelease(const songview::TimelineInputItem &input,
                                         Qt::MouseButton button, QPointF itemPoint,
                                         Qt::KeyboardModifiers modifiers)
{
    mouseRelease(button, windowPoint(input, itemPoint), modifiers);
}

void AutomationEditingTest::mouseDClick(const songview::TimelineInputItem &input,
                                        Qt::MouseButton button, QPointF itemPoint,
                                        Qt::KeyboardModifiers modifiers)
{
    mouseDClick(button, windowPoint(input, itemPoint), modifiers);
}

void AutomationEditingTest::wheel(const songview::TimelineInputItem &input, QPointF itemPoint,
                                  QPoint angleDelta, Qt::KeyboardModifiers modifiers)
{
    if (!m_quickWindow)
        return;
    const QPointF windowPos = input.mapToScene(itemPoint);
    QWheelEvent event(windowPos, m_quickWindow->mapToGlobal(windowPos), QPoint{}, angleDelta,
                      Qt::NoButton, modifiers, Qt::NoScrollPhase, false);
    QCoreApplication::sendEvent(m_quickWindow, &event);
}

void AutomationEditingTest::sendWindowDeactivate()
{
    if (!m_quickWindow)
        return;
    QEvent event(QEvent::WindowDeactivate);
    QCoreApplication::sendEvent(m_quickWindow, &event);
}

void AutomationEditingTest::keyEvent(QEvent::Type type, Qt::Key key,
                                     Qt::KeyboardModifiers modifiers, bool autoRepeat)
{
    if (!m_quickWindow)
        return;
    QKeyEvent event(type, key, modifiers, QString{}, autoRepeat);
    QCoreApplication::sendEvent(m_quickWindow, &event);
    if (autoRepeat)
        return;
    if (type == QEvent::KeyPress) {
        if (std::find(m_heldKeys.cbegin(), m_heldKeys.cend(), key) == m_heldKeys.cend())
            m_heldKeys.push_back(key);
    } else if (type == QEvent::KeyRelease) {
        const auto held = std::find(m_heldKeys.cbegin(), m_heldKeys.cend(), key);
        if (held != m_heldKeys.cend())
            m_heldKeys.erase(held);
    }
    m_lastModifiers = modifiers;
}

void AutomationEditingTest::keyPress(Qt::Key key, Qt::KeyboardModifiers modifiers)
{
    if (!m_quickWindow)
        return;
    QTest::keyPress(m_quickWindow, key, modifiers);
    if (std::find(m_heldKeys.cbegin(), m_heldKeys.cend(), key) == m_heldKeys.cend())
        m_heldKeys.push_back(key);
    m_lastModifiers = modifiers;
}

void AutomationEditingTest::keyRelease(Qt::Key key, Qt::KeyboardModifiers modifiers)
{
    if (!m_quickWindow)
        return;
    QTest::keyRelease(m_quickWindow, key, modifiers);
    const auto held = std::find(m_heldKeys.cbegin(), m_heldKeys.cend(), key);
    if (held != m_heldKeys.cend())
        m_heldKeys.erase(held);
    m_lastModifiers = modifiers;
}

void AutomationEditingTest::keyClick(Qt::Key key, Qt::KeyboardModifiers modifiers)
{
    if (!m_quickWindow)
        return;
    QTest::keyClick(m_quickWindow, key, modifiers);
    m_lastModifiers = modifiers;
}

bool AutomationEditingTest::focusAutomationBand()
{
    if (!m_tab || !m_automationInput || !m_quickWindow)
        return false;
    if (!m_tab->view().quickView()->focusBand(songview::TimelineBand::Automation,
                                              Qt::OtherFocusReason)) {
        return false;
    }
    return QTest::qWaitFor([this] {
        return m_tab->view().quickView()->focusedBand() == songview::TimelineBand::Automation &&
               m_quickWindow->activeFocusItem() ==
                   static_cast<QQuickItem *>(m_automationInput.data());
    });
}

bool AutomationEditingTest::activateParameter(const EditorAutomationRowId &row)
{
    const int index = checks::support::automationParameterIndex(*page().canvas(), row);
    if (index < 0)
        return false;
    if (!clickParameterTab(row))
        return false;
    return QTest::qWaitFor([this, index] { return page().canvas()->activeParameter() == index; });
}

bool AutomationEditingTest::clickParameterTab(const EditorAutomationRowId &row,
                                              Qt::KeyboardModifiers modifiers)
{
    const int index = checks::support::automationParameterIndex(*page().canvas(), row);
    if (index < 0 || !m_quickWindow)
        return false;
    auto *quick = tab().view().quickView();
    QQuickItem *root = quick ? quick->rootObject() : nullptr;
    if (!root)
        return false;
    auto *item = checks::support::visualDescendant(
        root, QStringLiteral("automationParameterTab%1").arg(index));
    if (!item || !item->isVisible() || !item->isEnabled())
        return false;
    const QPoint where =
        item->mapToScene(QPointF(item->width() / 2.0, item->height() / 2.0)).toPoint();
    QTest::mouseClick(m_quickWindow, Qt::LeftButton, modifiers, where);
    return true;
}

void AutomationEditingTest::arrangeCcLane()
{
    m_tab->document().writeLanePoints(
        0, kPilotController, 0, kPilotEndTick,
        {{kPilotDraggedTick, kPilotDraggedValue}, {kPilotIndependentTick, kPilotIndependentValue}});
}
