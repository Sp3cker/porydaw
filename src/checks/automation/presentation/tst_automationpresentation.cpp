#include "checks/automation/presentation/tst_automationpresentation.h"

#include <limits>
#include <utility>

#include <QtTest>

#include <QCoreApplication>
#include <QCursor>
#include <QEnterEvent>
#include <QFont>
#include <QPalette>
#include <QPixmap>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRectF>

#include "checks/support/eventsynth.h"
#include "checks/support/timelinequickcheck.h"

#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/songview/quick/timelineinput.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"

namespace {

constexpr int kTrack = 0;
constexpr uint8_t kPanController = 10;
constexpr uint8_t kLfoController = 21;
constexpr Tick kEndTick = 384;

class CursorDprHost final : public songview::TimelineInputHost
{
  public:
    CursorDprHost(QRectF bounds, qreal devicePixelRatio)
        : m_bounds(bounds)
        , m_devicePixelRatio(devicePixelRatio)
    {}

    void setDevicePixelRatio(qreal devicePixelRatio) noexcept
    {
        m_devicePixelRatio = devicePixelRatio;
    }

    const QCursor &cursor() const noexcept { return m_cursor; }

    QRectF bounds() const override { return m_bounds; }
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
    QRectF m_bounds;
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

SmfEvent programChange(Tick tick, uint8_t program)
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
    m_document->writeLanePoints(kTrack, 7, 0, CoreTimeDefaults::kNoTick, {{24, 48}});
    m_document->writeLanePoints(kTrack, kPanController, 0, CoreTimeDefaults::kNoTick,
                                {{48, 32}, {144, 96}});
    m_document->writeLanePoints(kTrack, kLfoController, 0, CoreTimeDefaults::kNoTick,
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

QPointF AutomationPresentationTest::lanePoint(LaneHandle handle, Tick tick, int value) const
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
    QQuickWindow *const window = input.window();
    QQuickItem *const content = window ? window->contentItem() : nullptr;
    return content ? content->mapFromScene(input.mapToScene(contentPoint)).toPoint() : QPoint{};
}

QQuickItem *AutomationPresentationTest::parameterLabelItem(int index) const
{
    songview::TimelineQuickView *const quick = m_rig ? m_rig->view().quickView() : nullptr;
    QQuickItem *const root = quick ? quick->rootObject() : nullptr;
    return checks::support::visualDescendant(root,
                                             QStringLiteral("automationParameterTab%1").arg(index));
}

bool AutomationPresentationTest::activateParameter(const EditorAutomationRowId &row)
{
    AutomationPage *const automationPage = page();
    AutomationCanvas *const canvas = automationPage ? automationPage->canvas() : nullptr;
    const int index = canvas ? checks::support::automationParameterIndex(*canvas, row) : -1;
    if (!canvas || index < 0 || !m_quickWindow)
        return false;
    QQuickItem *label = nullptr;
    if (!QTest::qWaitFor([this, index, &label] {
            label = parameterLabelItem(index);
            return label && label->isVisible() && label->isEnabled() && label->width() > 0.0 &&
                   label->height() > 0.0 && label->window();
        })) {
        return false;
    }
    QQuickWindow *const window = label->window();
    QQuickItem *const content = window ? window->contentItem() : nullptr;
    if (!content)
        return false;
    const QPointF point = content->mapFromScene(
        label->mapToScene(QPointF(label->width() / 2.0, label->height() / 2.0)));
    if (!content->boundingRect().contains(point))
        return false;
    QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, point.toPoint());
    return QTest::qWaitFor([canvas, index] { return canvas->activeParameter() == index; });
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

void AutomationPresentationTest::pencilCursorUsesPlotGutterBoundary()
{
    AutomationPage *const automationPage = page();
    QVERIFY(automationPage);
    const EditorAutomationRowId panRow{EditorAutomationRowKind::ControlChange, kTrack,
                                       kPanController};
    QVERIFY(activateParameter(panRow));
    const LaneHandle pan = findRow(panRow);
    QVERIFY(pan.valid());
    const QRect plot = automationPage->canvas()->laneBody(pan);
    QVERIFY(!plot.isEmpty());
    automationPage->canvas()->setPencilMode(true);
    const QPointF plotPoint = lanePoint(pan, 24, 64);
    mouseMove(*m_plotInput, plotPoint);
    QVERIFY(!m_plotInput->cursor().pixmap().isNull());

    mouseMove(*m_gutterInput, {m_gutterInput->bounds().center().x(), plotPoint.y()});
    QCOMPARE(m_gutterInput->cursor().shape(), Qt::ArrowCursor);

    QVERIFY(activateParameter({EditorAutomationRowKind::Tempo, 0, 0}));
    mouseMove(*m_plotInput, plotPoint);
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

    CursorDprHost host{m_plotInput->bounds(), 1.0};
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
