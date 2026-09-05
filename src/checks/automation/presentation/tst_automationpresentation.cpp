#include "checks/automation/presentation/tst_automationpresentation.h"

#include <algorithm>
#include <limits>
#include <utility>

#include <QtTest>

#include <QCoreApplication>
#include <QCursor>
#include <QEnterEvent>
#include <QFont>
#include <QImage>
#include <QPalette>
#include <QPixmap>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRectF>
#include <QWheelEvent>

#include "checks/support/eventsynth.h"

#include "checks/support/quickframebuffer.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/layout.h"
#include "ui/songview/quick/timelineinput.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"

namespace {

constexpr int kTrack = 0;
constexpr uint8_t kPanController = 10;
constexpr uint8_t kLfoController = 21;
constexpr uint64_t kEndTick = 384;

class CursorDprHost final : public songview::TimelineInputHost
{
  public:
    explicit CursorDprHost(qreal devicePixelRatio) : m_devicePixelRatio(devicePixelRatio) {}

    void setDevicePixelRatio(qreal devicePixelRatio) noexcept
    {
        m_devicePixelRatio = devicePixelRatio;
    }

    const QCursor &cursor() const noexcept { return m_cursor; }

    QRectF bounds() const override { return {}; }
    qreal devicePixelRatio() const override { return m_devicePixelRatio; }
    QFont font() const override { return {}; }
    QPalette palette() const override { return {}; }
    QPointF mapFromGlobal(QPointF position) const override { return position; }
    QPointF mapToGlobal(QPointF position) const override { return position; }
    void requestFocus(Qt::FocusReason) override {}
    void setCursor(const QCursor &cursor) override { m_cursor = cursor; }
    void clearCursor() override { m_cursor = QCursor{Qt::ArrowCursor}; }
    void releasePointerGrab() override {}
    void setAccessibilityDescription(const QString &) override {}

  private:
    qreal m_devicePixelRatio = 1.0;
    QCursor m_cursor{Qt::ArrowCursor};
};

class ScopedAutomationInputHost final
{
  public:
    ScopedAutomationInputHost(songview::TimelineInputItem &physicalHost, AutomationCanvas &canvas)
        : m_physicalHost(physicalHost)
        , m_canvas(canvas)
        , m_originalInteraction(physicalHost.interaction())
        , m_originalPencilMode(canvas.pencilMode())
    {
        m_physicalHost.setInteraction(nullptr);
    }

    ~ScopedAutomationInputHost()
    {
        if (m_testHost)
            m_canvas.detachInputHost(*m_testHost);
        if (m_canvas.pencilMode() != m_originalPencilMode)
            m_canvas.setPencilMode(m_originalPencilMode);
        if (m_originalInteraction)
            m_physicalHost.setInteraction(m_originalInteraction);
    }

    ScopedAutomationInputHost(const ScopedAutomationInputHost &) = delete;
    ScopedAutomationInputHost &operator=(const ScopedAutomationInputHost &) = delete;

    void attach(CursorDprHost &host)
    {
        m_canvas.attachInputHost(host);
        m_testHost = &host;
    }

  private:
    songview::TimelineInputItem &m_physicalHost;
    AutomationCanvas &m_canvas;
    songview::TimelineBandInteraction *m_originalInteraction = nullptr;
    bool m_originalPencilMode = false;
    CursorDprHost *m_testHost = nullptr;
};

songview::TimelinePointerInput plotPointerInput(QPointF position, songview::TimelineInputHost &host)
{
    return {
        .position = position,
        .globalPosition = {},
        .button = Qt::NoButton,
        .buttons = Qt::NoButton,
        .modifiers = Qt::NoModifier,
        .surface = songview::TimelineInputSurface::Plot,
        .host = &host,
    };
}

SmfEvent programChange(uint64_t tick, uint8_t program)
{
    return {.tick = tick, .status = 0xC0, .data0 = program};
}

} // namespace

SmfFile AutomationPresentationTest::presentationSmf()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    SmfTrack track;
    track.events = {programChange(0, 0)};
    track.endTick = kEndTick;
    smf.tracks.push_back(std::move(track));
    return smf;
}

void AutomationPresentationTest::init()
{
    m_heldButton = Qt::NoButton;
    m_lastWindowPoint = {};
    m_windowEntered = false;
    m_bank = {};
    m_bank.voices[0].type = VOICE_DIRECTSOUND;
    m_bank.voices[1].type = VOICE_SQUARE_1;
    m_bank.voices[2].type = VOICE_PROGRAMMABLE_WAVE;
    m_bank.voices[3].type = VOICE_NOISE;

    m_document = std::make_unique<SongDocument>();
    SongInfo song;
    song.label = QStringLiteral("automation-presentation");
    song.hasMid = true;
    QString error;
    QVERIFY2(m_document->adoptSmf(presentationSmf(), song, &error), qPrintable(error));
    m_document->writeLanePoints(kTrack, 7, 0, std::numeric_limits<uint64_t>::max(), {{24, 48}});
    m_document->writeLanePoints(kTrack, kPanController, 0, std::numeric_limits<uint64_t>::max(),
                                {{48, 32}, {144, 96}});
    m_document->writeLanePoints(kTrack, kLfoController, 0, std::numeric_limits<uint64_t>::max(),
                                {{96, 32}, {96, 96}});

    checks::EditorRigConfig config;
    config.voicegroup = &m_bank;
    config.track = kTrack;
    config.activePage = EditorDrawerPage::Automations;
    config.sections = {{EditorDrawerPage::Automations, 320}};
    config.timeZoom = 96.0;
    config.applyEditCursor = true;
    config.editCursorTick = 24;
    m_rig = checks::EditorRig::create(*m_document, config, error);
    QVERIFY2(m_rig, qPrintable(error));

    EditorViewState state = m_rig->view().editorViewState();
    state.emptyLanes.insert({EditorAutomationRowKind::ControlChange, kTrack, kPanController});
    m_rig->view().applyEditorViewState(state);
    QCoreApplication::processEvents();

    QObject *const root = m_rig->quickRoot();
    QVERIFY(root);
    m_plotInput =
        root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineAutomationInput"));
    m_gutterInput = root->findChild<songview::TimelineInputItem *>(
        QStringLiteral("timelineAutomationGutterInput"));
    QVERIFY(m_plotInput);
    QVERIFY(m_gutterInput);
    m_quickWindow = m_plotInput->window();
    QVERIFY(m_quickWindow);
    QTRY_VERIFY(m_quickWindow->isVisible() && m_quickWindow->isExposed());
    QTRY_VERIFY(!m_plotInput->bounds().isEmpty());
    QTRY_VERIFY(!m_gutterInput->bounds().isEmpty());
    QTRY_VERIFY(page() && page()->canvas());
    QCOMPARE(m_gutterInput->window(), m_quickWindow.data());
    QVERIFY(m_plotInput->interaction() == page()->canvas());
    QVERIFY(m_gutterInput->interaction() == page()->canvas());
    QTRY_VERIFY(quickScene());
}

void AutomationPresentationTest::cleanup()
{
    bool mouseGrabCleared = true;
    if (m_quickWindow) {
        QTest::keyClick(m_quickWindow, Qt::Key_Escape);
        if (m_heldButton != Qt::NoButton)
            QTest::mouseRelease(m_quickWindow, m_heldButton, Qt::NoModifier, m_lastWindowPoint);
        if (QQuickItem *grabber = m_quickWindow->mouseGrabberItem())
            grabber->ungrabMouse();
        mouseGrabCleared = QTest::qWaitFor(
            [this] { return !m_quickWindow || !m_quickWindow->mouseGrabberItem(); });
    }
    m_heldButton = Qt::NoButton;
    m_plotInput.clear();
    m_gutterInput.clear();
    m_quickWindow.clear();
    m_rig.reset();
    m_document.reset();
    QVERIFY(mouseGrabCleared);
}

AutomationPage *AutomationPresentationTest::page() const
{
    if (!m_rig || !m_rig->view().editorDrawer())
        return nullptr;
    return m_rig->view().editorDrawer()->automationPage();
}

songview::TimelineQuickScene *AutomationPresentationTest::quickScene() const
{
    return m_rig ? m_rig->quickScene() : nullptr;
}

LaneHandle AutomationPresentationTest::findRow(EditorAutomationRowId id) const
{
    const AutomationPage *const automationPage = page();
    if (!automationPage)
        return {};
    const auto &rows = automationPage->canvas()->rows();
    for (int index = 0; index < int(rows.size()); ++index) {
        if (rows[std::size_t(index)].id == id)
            return {index + 1};
    }
    return {};
}

QPointF AutomationPresentationTest::lanePoint(LaneHandle handle, uint64_t tick, int value) const
{
    const AutomationPage *const automationPage = page();
    if (!automationPage || !m_plotInput)
        return {};
    const QRect body = automationPage->canvas()->laneBody(handle);
    if (body.isEmpty())
        return {};
    const qreal x =
        m_rig->view().camera().displayX(double(tick), 0.0, m_plotInput->devicePixelRatio());
    return {x, AutomationProjection::valueY(body, AutomationGeometry::resolve(), 0, 127, value)};
}

QPoint AutomationPresentationTest::windowPoint(const songview::TimelineInputItem &input,
                                               QPointF contentPoint) const
{
    const AutomationPage *const automationPage = page();
    if (!automationPage)
        return {};
    contentPoint.ry() -= automationPage->verticalScroll();
    return input.mapToScene(contentPoint).toPoint();
}

QPointF AutomationPresentationTest::tempoHeaderPoint() const
{
    const AutomationPage *const automationPage = page();
    const QRect tempo = automationPage ? automationPage->canvas()->pinnedTempoRect() : QRect{};
    return {qreal(layout::space(layout::Space::One)), qreal(tempo.center().y())};
}

int AutomationPresentationTest::maximumScroll() const
{
    const AutomationPage *const automationPage = page();
    return automationPage ? std::max(0, automationPage->automationContentHeight() -
                                            automationPage->automationViewportSize().height())
                          : 0;
}

bool AutomationPresentationTest::tempoPinnedToViewport() const
{
    const AutomationPage *const automationPage = page();
    if (!automationPage)
        return false;
    const QRect tempo = automationPage->canvas()->pinnedTempoRect();
    return !tempo.isEmpty() && tempo.bottom() + 1 - automationPage->verticalScroll() ==
                                   automationPage->automationViewportSize().height();
}

bool AutomationPresentationTest::setTempoExpanded(bool expanded)
{
    const AutomationPage *const automationPage = page();
    if (!automationPage || !m_gutterInput)
        return false;
    const bool current = !automationPage->canvas()->laneBody(LaneHandle{0}).isEmpty();
    if (current == expanded)
        return true;
    gutterClick(tempoHeaderPoint());
    QCoreApplication::processEvents();
    return !automationPage->canvas()->laneBody(LaneHandle{0}).isEmpty() == expanded;
}

void AutomationPresentationTest::mouseMove(songview::TimelineInputItem &input, QPointF contentPoint)
{
    if (!m_quickWindow)
        return;
    QCOMPARE(input.window(), m_quickWindow.data());
    m_lastWindowPoint = windowPoint(input, contentPoint);
    if (!m_windowEntered) {
        const QPointF windowPosition = m_lastWindowPoint;
        QEnterEvent enter(windowPosition, windowPosition,
                          QPointF(m_quickWindow->mapToGlobal(m_lastWindowPoint)));
        QCoreApplication::sendEvent(m_quickWindow, &enter);
        m_windowEntered = true;
    }
    checks::events::primeMouseMove(*m_quickWindow, input, m_lastWindowPoint);
    QTest::mouseEvent(QTest::MouseMove, m_quickWindow, Qt::NoButton, Qt::NoModifier,
                      m_lastWindowPoint);
    QCoreApplication::processEvents();
}

void AutomationPresentationTest::gutterClick(QPointF contentPoint)
{
    if (!m_quickWindow || !m_gutterInput)
        return;
    m_lastWindowPoint = windowPoint(*m_gutterInput, contentPoint);
    QTest::mousePress(m_quickWindow, Qt::LeftButton, Qt::NoModifier, m_lastWindowPoint);
    m_heldButton = Qt::LeftButton;
    QTest::mouseRelease(m_quickWindow, Qt::LeftButton, Qt::NoModifier, m_lastWindowPoint);
    m_heldButton = Qt::NoButton;
    QCoreApplication::processEvents();
}

void AutomationPresentationTest::collapsedTempoGeometryIsPinned()
{
    AutomationPage *const automationPage = page();
    QVERIFY(automationPage);
    const AutomationGeometry geometry = AutomationGeometry::resolve();
    const QRect collapsed = automationPage->canvas()->laneBody(LaneHandle{0});
    QVERIFY(collapsed.isEmpty());
    QCOMPARE(automationPage->canvas()->pinnedTempoRect().height(), geometry.addLaneStripHeight);
    QVERIFY(tempoPinnedToViewport());
}

void AutomationPresentationTest::headerClickExpandsTempoToConfiguredHeight()
{
    AutomationPage *const automationPage = page();
    QVERIFY(automationPage);
    const AutomationGeometry geometry = AutomationGeometry::resolve();
    const EditorAutomationRowId tempoRow{EditorAutomationRowKind::Tempo, 0, 0};
    EditorViewState state = m_rig->view().editorViewState();
    state.laneHeights[tempoRow] = geometry.rowDefaultHeight + layout::singlePixel();
    m_rig->view().applyEditorViewState(state);
    QCoreApplication::processEvents();

    const int collapsedMinimumHeight = automationPage->canvas()->minimumContentHeight();
    QVERIFY(setTempoExpanded(true));
    const QRect expanded = automationPage->canvas()->laneBody(LaneHandle{0});
    QVERIFY(!expanded.isEmpty());
    QCOMPARE(expanded.height(), geometry.rowDefaultHeight + layout::singlePixel());
    QCOMPARE(expanded, automationPage->canvas()->pinnedTempoRect());
    QVERIFY(tempoPinnedToViewport());
    QVERIFY(automationPage->canvas()->minimumContentHeight() > collapsedMinimumHeight);
}

void AutomationPresentationTest::verticalScrollPinsTempoOverCcContent()
{
    AutomationPage *const automationPage = page();
    QVERIFY(automationPage);
    const AutomationGeometry geometry = AutomationGeometry::resolve();
    const int originalHeight = m_rig->view().drawerSectionHeight(EditorDrawerPage::Automations);
    m_rig->view().setDrawerSectionHeight(EditorDrawerPage::Automations,
                                         2 * geometry.rowDefaultHeight);
    QCoreApplication::processEvents();
    QVERIFY(setTempoExpanded(true));
    const QRect bodyBefore = automationPage->canvas()->laneBody(LaneHandle{0});
    const int pageYBefore = bodyBefore.top() - automationPage->verticalScroll();
    const auto &band =
        m_rig->view().timelineBandLayout().geometry(songview::TimelineBand::Automation);
    QVERIFY(band);
    const QImage viewportBefore = checks::support::captureQuickBand(m_rig->view(), band->rect);
    QVERIFY(!viewportBefore.isNull());

    const QPoint wheelPoint = windowPoint(*m_gutterInput, tempoHeaderPoint());
    QWheelEvent wheel(wheelPoint, m_quickWindow->mapToGlobal(wheelPoint), QPoint{},
                      QPoint(0, -std::max(1, maximumScroll())), Qt::NoButton, Qt::NoModifier,
                      Qt::NoScrollPhase, false);
    QCoreApplication::sendEvent(m_quickWindow, &wheel);
    QTRY_VERIFY(automationPage->verticalScroll() > 0);

    const QRect bodyAfter = automationPage->canvas()->laneBody(LaneHandle{0});
    const QImage viewportAfter = checks::support::captureQuickBand(m_rig->view(), band->rect);
    QVERIFY(!viewportAfter.isNull());
    QCOMPARE(bodyAfter.top() - automationPage->verticalScroll(), pageYBefore);
    QCOMPARE(bodyAfter, automationPage->canvas()->pinnedTempoRect());
    QVERIFY(tempoPinnedToViewport());
    QVERIFY(viewportAfter != viewportBefore);
    m_rig->view().setDrawerSectionHeight(EditorDrawerPage::Automations, originalHeight);
}

void AutomationPresentationTest::viewportResizeKeepsTempoPinned()
{
    AutomationPage *const automationPage = page();
    QVERIFY(automationPage);
    const AutomationGeometry geometry = AutomationGeometry::resolve();
    QVERIFY(setTempoExpanded(true));
    const int originalHeight = m_rig->view().drawerSectionHeight(EditorDrawerPage::Automations);
    const QRect before = automationPage->canvas()->laneBody(LaneHandle{0});
    const int viewportBefore = automationPage->automationViewportSize().height();
    m_rig->view().setDrawerSectionHeight(EditorDrawerPage::Automations,
                                         geometry.rowDefaultHeight +
                                             layout::space(layout::Space::One));
    QCoreApplication::processEvents();
    const QRect after = automationPage->canvas()->laneBody(LaneHandle{0});
    const int viewportAfter = automationPage->automationViewportSize().height();
    QVERIFY(viewportAfter < viewportBefore);
    QCOMPARE(after.height(), before.height());
    QCOMPARE(after.top() - before.top(), viewportAfter - viewportBefore);
    QCOMPARE(after, automationPage->canvas()->pinnedTempoRect());
    QVERIFY(tempoPinnedToViewport());
    m_rig->view().setDrawerSectionHeight(EditorDrawerPage::Automations, originalHeight);
}

void AutomationPresentationTest::headerClickRecollapsesTempoAndRecoversCanvasSpace()
{
    AutomationPage *const automationPage = page();
    QVERIFY(automationPage);
    const int collapsedMinimumHeight = automationPage->canvas()->minimumContentHeight();
    QVERIFY(setTempoExpanded(true));
    const int expandedMinimumHeight = automationPage->canvas()->minimumContentHeight();
    QVERIFY(setTempoExpanded(false));
    QVERIFY(automationPage->canvas()->laneBody(LaneHandle{0}).isEmpty());
    QCOMPARE(automationPage->canvas()->minimumContentHeight(), collapsedMinimumHeight);
    QVERIFY(expandedMinimumHeight > collapsedMinimumHeight);
}

void AutomationPresentationTest::headerReexpansionRestoresConfiguredTempoHeight()
{
    AutomationPage *const automationPage = page();
    QVERIFY(automationPage);
    const AutomationGeometry geometry = AutomationGeometry::resolve();
    const EditorAutomationRowId tempoRow{EditorAutomationRowKind::Tempo, 0, 0};
    EditorViewState state = m_rig->view().editorViewState();
    state.laneHeights[tempoRow] = geometry.rowMaximumHeight;
    m_rig->view().applyEditorViewState(state);
    QVERIFY(setTempoExpanded(true));
    const int expandedMinimumHeight = automationPage->canvas()->minimumContentHeight();
    QVERIFY(setTempoExpanded(false));
    QVERIFY(setTempoExpanded(true));
    const QRect reexpanded = automationPage->canvas()->laneBody(LaneHandle{0});
    QCOMPARE(reexpanded.height(), geometry.rowMaximumHeight);
    QCOMPARE(automationPage->canvas()->minimumContentHeight(), expandedMinimumHeight);
    QCOMPARE(reexpanded, automationPage->canvas()->pinnedTempoRect());
}

void AutomationPresentationTest::pencilCursorUsesPlotGutterBoundaryAndTempoPrecedence()
{
    AutomationPage *const automationPage = page();
    QVERIFY(automationPage);
    const LaneHandle pan =
        findRow({EditorAutomationRowKind::ControlChange, kTrack, kPanController});
    const QRect panBody = automationPage->canvas()->laneBody(pan);
    QVERIFY(pan.valid());
    QVERIFY(!panBody.isEmpty());
    automationPage->canvas()->setPencilMode(true);
    const QPointF plotPoint = lanePoint(pan, 24, 64);
    mouseMove(*m_plotInput, plotPoint);
    QVERIFY(!m_plotInput->cursor().pixmap().isNull());

    mouseMove(*m_gutterInput, {m_gutterInput->bounds().center().x(), plotPoint.y()});
    QCOMPARE(m_gutterInput->cursor().shape(), Qt::ArrowCursor);
    mouseMove(*m_gutterInput, {m_gutterInput->bounds().center().x(), qreal(panBody.bottom())});
    QCOMPARE(m_gutterInput->cursor().shape(), Qt::SplitVCursor);

    const int addLaneY = automationPage->automationContentHeight() -
                         AutomationGeometry::resolve().addLaneStripHeight / 2;
    mouseMove(*m_gutterInput, {m_gutterInput->bounds().center().x(), qreal(addLaneY)});
    QCOMPARE(m_gutterInput->cursor().shape(), Qt::ArrowCursor);
    mouseMove(*m_gutterInput, tempoHeaderPoint());
    QCOMPARE(m_gutterInput->cursor().shape(), Qt::ArrowCursor);

    QVERIFY(setTempoExpanded(true));
    mouseMove(*m_plotInput, lanePoint(LaneHandle{0}, 24, 60));
    QVERIFY(!m_plotInput->cursor().pixmap().isNull());
}

void AutomationPresentationTest::pencilCursorUsesInputDevicePixelRatio()
{
    AutomationPage *const automationPage = page();
    QVERIFY(automationPage);
    const LaneHandle pan =
        findRow({EditorAutomationRowKind::ControlChange, kTrack, kPanController});
    QVERIFY(pan.valid());
    automationPage->canvas()->setPencilMode(true);
    mouseMove(*m_plotInput, lanePoint(pan, 24, 64));
    const QPixmap pixmap = m_plotInput->cursor().pixmap();
    QVERIFY(!pixmap.isNull());
    QCOMPARE(pixmap.devicePixelRatio(), m_plotInput->devicePixelRatio());
}

void AutomationPresentationTest::pencilCursorScalesWithInjectedDevicePixelRatio()
{
    AutomationPage *const automationPage = page();
    QVERIFY(automationPage);
    AutomationCanvas *const canvas = automationPage->canvas();
    QVERIFY(canvas);
    QVERIFY(m_plotInput);
    QVERIFY(m_plotInput->interaction() == canvas);
    const LaneHandle pan =
        findRow({EditorAutomationRowKind::ControlChange, kTrack, kPanController});
    QVERIFY(pan.valid());

    CursorDprHost host{1.0};
    ScopedAutomationInputHost hostSwap(*m_plotInput, *canvas);
    canvas->setPencilMode(true);
    hostSwap.attach(host);
    const QPointF plotPoint = lanePoint(pan, 24, 64);

    QVERIFY(canvas->pointerMove(plotPointerInput(plotPoint, host)));
    const QPixmap pixmapAtOne = host.cursor().pixmap();
    QVERIFY(!pixmapAtOne.isNull());
    QVERIFY(qFuzzyCompare(pixmapAtOne.devicePixelRatio(), 1.0));

    host.setDevicePixelRatio(2.0);
    QVERIFY(canvas->pointerMove(plotPointerInput(plotPoint, host)));
    const QPixmap pixmapAtTwo = host.cursor().pixmap();
    QVERIFY(!pixmapAtTwo.isNull());
    QVERIFY(qFuzzyCompare(pixmapAtTwo.devicePixelRatio(), 2.0));

    host.setDevicePixelRatio(1.0);
    QVERIFY(canvas->pointerMove(plotPointerInput(plotPoint, host)));
    const QPixmap pixmapAtOneAgain = host.cursor().pixmap();
    QVERIFY(!pixmapAtOneAgain.isNull());
    QVERIFY(qFuzzyCompare(pixmapAtOneAgain.devicePixelRatio(), 1.0));
}

void AutomationPresentationTest::pencilCursorTurnsOffToArrow()
{
    AutomationPage *const automationPage = page();
    QVERIFY(automationPage);
    const LaneHandle pan =
        findRow({EditorAutomationRowKind::ControlChange, kTrack, kPanController});
    QVERIFY(pan.valid());
    const QPointF plotPoint = lanePoint(pan, 24, 64);
    automationPage->canvas()->setPencilMode(true);
    mouseMove(*m_plotInput, plotPoint);
    QVERIFY(!m_plotInput->cursor().pixmap().isNull());
    automationPage->canvas()->setPencilMode(false);
    mouseMove(*m_plotInput, plotPoint);
    QCOMPARE(m_plotInput->cursor().shape(), Qt::ArrowCursor);
}

int runAutomationPresentationCheck(const QStringList &qtArguments)
{
    AutomationPresentationTest test;
    QStringList arguments{QStringLiteral("automation-presentation")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
