#include "checks/scrollbar/tst_scrollbar.h"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QPointingDevice>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSize>
#include <QStyleHints>
#include <QUrl>
#include <QtTest>
#include <qqml.h>

#include <algorithm>
#include <cmath>
#include <optional>
#include <utility>

#include "checks/fwd.hpp"
#include "checks/support/editorrig.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"
#include "core/tracklimits.h"
#include "project/projectidentity.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/drawerchrome.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"

namespace {

constexpr int kViewWidth = 1280;
constexpr int kViewHeight = 800;
constexpr int kDefaultAutomationHeight = 400;
constexpr int kAutomationDragHeight = 180;
constexpr qreal kGeometryTolerance = 0.01;

constexpr auto kStandaloneScrollbarQml = R"(
import QtQuick
import Porydaw.Ui
Item {
    id: root
    property real modelMinimum: -80
    property real modelMaximum: 80
    property real modelValue: -80
    property real modelPageStep: 20
    x: 40
    y: 40
    width: 240
    height: 20
    TimelineScrollbar {
        id: control
        objectName: "standaloneTimelineScrollbar"
        anchors.fill: parent
        orientation: Qt.Horizontal
        minimum: root.modelMinimum
        maximum: root.modelMaximum
        value: root.modelValue
        pageStep: root.modelPageStep
        singleStep: 5
        minimumThumbLength: 24
        handleColor: Qt.white
        handleHoverColor: Qt.white
        visibleWhenNotScrollable: true
        thumbObjectName: "standaloneTimelineScrollbarThumb"
        onValueRequested: (value) => root.modelValue = value
    }
}
)";

QQuickItem *createStandaloneScrollbar(QQuickItem &sceneRoot, QString *error)
{
    QQmlEngine *const engine = qmlEngine(&sceneRoot);
    if (!engine) {
        *error = QStringLiteral("Quick scene has no QML engine");
        return nullptr;
    }

    QQmlComponent component(engine);
    component.setData(kStandaloneScrollbarQml,
                      QUrl(QStringLiteral("qrc:/qt/qml/Porydaw/Ui/ScrollbarCheck.qml")));
    if (component.status() != QQmlComponent::Ready) {
        *error = component.errorString();
        return nullptr;
    }

    QObject *const object = component.create();
    auto *const item = qobject_cast<QQuickItem *>(object);
    if (!item) {
        delete object;
        if (component.errorString().isEmpty())
            *error = QStringLiteral("standalone TimelineScrollbar did not create a Quick item");
        else
            *error = component.errorString();
        return nullptr;
    }
    item->setParent(&sceneRoot);
    item->setParentItem(&sceneRoot);
    return item;
}

bool closeEnough(qreal actual, qreal expected)
{
    return std::abs(actual - expected) <= kGeometryTolerance;
}

bool itemWithinTrack(const QQuickItem &track, const QQuickItem &handle, Qt::Orientation orientation)
{
    if (orientation == Qt::Horizontal) {
        return handle.x() >= -kGeometryTolerance &&
               handle.x() + handle.width() <= track.width() + kGeometryTolerance &&
               closeEnough(handle.y(), 0.0) && closeEnough(handle.height(), track.height());
    }
    return handle.y() >= -kGeometryTolerance &&
           handle.y() + handle.height() <= track.height() + kGeometryTolerance &&
           closeEnough(handle.x(), 0.0) && closeEnough(handle.width(), track.width());
}

} // namespace

ScrollbarTest::ScrollbarTest(const QString &projectRoot, const QString &songLabel)
    : m_projectRoot(projectRoot)
    , m_songLabel(songLabel)
{}

ScrollbarTest::~ScrollbarTest() = default;

void ScrollbarTest::init()
{
    m_heldButton = Qt::NoButton;
    m_lastWindowPosition = {};
    m_wheelSessions = {};

    QString error;
    const std::unique_ptr<checks::LoadedSong> loaded =
        checks::LoadedSong::load(m_projectRoot, m_songLabel, error);
    QVERIFY2(loaded, qPrintable(error));

    const std::optional<SongName> name = SongName::create(m_songLabel);
    QVERIFY(name.has_value());

    m_bank = {};
    m_bank.voices[0].type = VOICE_DIRECTSOUND;
    m_bank.voices[1].type = VOICE_SQUARE_1;
    m_bank.voices[2].type = VOICE_PROGRAMMABLE_WAVE;
    m_bank.voices[3].type = VOICE_NOISE;

    m_tab = std::make_unique<SongTab>(std::move(*name));
    m_host =
        std::make_unique<checks::QuickSceneHost>(m_tab->view(), QSize(kViewWidth, kViewHeight));
    m_tab->setSampleRate(48000.0);

    const std::optional<VoicegroupId> identity =
        VoicegroupId::create(QStringLiteral("scrollbar-check"), QString());
    QVERIFY(identity.has_value());

    m_tab->applyMidiStage(loaded->songInfo(), loaded->document().smf(),
                          track_limits::kHardwareCapacity);
    QVERIFY(m_tab->presentationError().isEmpty());
    m_tab->applyBankView(LoadedBankView{*identity, borrowVoicegroupLease(&m_bank), QString()});
    m_tab->applyVoicegroupBound(*identity);

    QTRY_VERIFY(m_tab->isReady());
    QVERIFY(m_tab->voicegroupLease().get() == &m_bank);

    SongView &songView = view();
    songView.setDrawerActivePage(EditorDrawerPage::Automations);
    songView.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    songView.setDrawerSectionHeight(EditorDrawerPage::Automations, kDefaultAutomationHeight);
    songView.setEditorTimeZoom(64.0);
    songView.setScaleFold(false);
    songView.setEventListVisible(false);

    songview::TimelineQuickView *const quick = songView.quickView();
    QVERIFY(quick);
    m_window = quick->quickWindow();
    QVERIFY(m_window);
    QVERIFY2(checks::support::showQuickViewport(songView, QSize(kViewWidth, kViewHeight)),
             "scrollbar Quick host did not expose its viewport");
    m_window->requestActivate();

    QTRY_VERIFY(m_window && m_window->isVisible());
    QTRY_VERIFY((m_root = quick->rootObject()));
    QTRY_VERIFY((m_horizontalBar = m_root->findChild<QQuickItem *>(
                     QStringLiteral("timelineHorizontalScrollBar"))));
    QTRY_VERIFY((m_horizontalThumb = m_root->findChild<QQuickItem *>(
                     QStringLiteral("timelineHorizontalScrollThumb"))));
    QTRY_VERIFY(
        (m_verticalBar = m_root->findChild<QQuickItem *>(QStringLiteral("timelineRollScrollBar"))));
    QTRY_VERIFY((m_verticalThumb =
                     m_root->findChild<QQuickItem *>(QStringLiteral("timelineRollScrollThumb"))));
    QTRY_VERIFY(m_horizontalBar->isVisible() && m_horizontalThumb->isVisible() &&
                m_verticalBar->isVisible() && m_verticalThumb->isVisible());
    QTRY_VERIFY(!m_horizontalBar->boundingRect().isEmpty() &&
                !m_horizontalThumb->boundingRect().isEmpty() &&
                !m_verticalBar->boundingRect().isEmpty() &&
                !m_verticalThumb->boundingRect().isEmpty());
    QTRY_VERIFY(withinTrack(Qt::Horizontal) && withinTrack(Qt::Vertical));
    QTRY_VERIFY(m_horizontalBar->property("thumbTravel").toReal() > 0.0 &&
                m_verticalBar->property("thumbTravel").toReal() > 0.0);
    // Application-focus staging: bare forceActiveFocus only resolves window-local
    // scope, so the keyboard rows need the Quick window active first. Stage real
    // Roll-band focus through the normal host path before scrollbar work.
    songview::TimelineInputItem *const rollInput =
        m_root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineRollInput"));
    QVERIFY(rollInput);
    QVERIFY(songView.focusTimelineBand(songview::TimelineBand::Roll, Qt::OtherFocusReason));
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
    QTRY_VERIFY(QGuiApplication::focusWindow() == m_window &&
                QGuiApplication::focusObject() == rollInput && rollInput->hasActiveFocus());
}

void ScrollbarTest::cleanup()
{
    endWheel(Qt::Horizontal);
    endWheel(Qt::Vertical);

    if (m_window) {
        QTest::keyClick(m_window, Qt::Key_Escape);
        release();
        if (QQuickItem *const grabber = m_window->mouseGrabberItem())
            grabber->ungrabMouse();
    }
    m_heldButton = Qt::NoButton;

    m_horizontalThumb.clear();
    m_horizontalBar.clear();
    m_verticalThumb.clear();
    m_verticalBar.clear();
    m_root.clear();
    m_window.clear();
    m_touchpad.reset();
    m_host.reset();
    m_tab.reset();
}

void ScrollbarTest::automationTrackPages()
{
    view().setDrawerSectionHeight(EditorDrawerPage::Automations, kAutomationDragHeight);
    EditorDrawer *const drawer = view().editorDrawer();
    QVERIFY(drawer);
    AutomationPage *const page = drawer->automationPage();
    QVERIFY(page);

    QQuickItem *const scrollbar =
        m_root->findChild<QQuickItem *>(QStringLiteral("drawerAutomationScrollBar"));
    QQuickItem *const scrollbarThumb =
        m_root->findChild<QQuickItem *>(QStringLiteral("drawerAutomationScrollThumb"));
    QVERIFY(scrollbar);
    QVERIFY(scrollbarThumb);
    QTRY_VERIFY(scrollbar->isVisible() && scrollbarThumb->isVisible());

    const int maximum = drawer->chrome().automationMaximumScrollY();
    const int viewportHeight = drawer->chrome().automationViewportHeight();
    QVERIFY(maximum > 0);
    QVERIFY(viewportHeight > 0);
    QTRY_COMPARE(scrollbar->property("pageStep").toInt(), viewportHeight);
    QTRY_VERIFY(scrollbar->height() > scrollbarThumb->height());

    page->setVerticalScroll(0);
    QTRY_COMPARE(page->verticalScroll(), 0);
    const QPointF afterThumb(
        scrollbar->width() / 2.0,
        scrollbarThumb->y() + scrollbarThumb->height() +
            (scrollbar->height() - scrollbarThumb->y() - scrollbarThumb->height()) / 2.0);
    const int expected = std::min(maximum, viewportHeight);
    press(scrollbar->mapToScene(afterThumb));
    release();
    QTRY_COMPARE(page->verticalScroll(), expected);
}

void ScrollbarTest::automationDragClampsAndReverses()
{
    view().setDrawerSectionHeight(EditorDrawerPage::Automations, kAutomationDragHeight);
    EditorDrawer *const drawer = view().editorDrawer();
    QVERIFY(drawer);
    AutomationPage *const page = drawer->automationPage();
    QVERIFY(page);

    QQuickItem *const scrollbar =
        m_root->findChild<QQuickItem *>(QStringLiteral("drawerAutomationScrollBar"));
    QQuickItem *const scrollbarThumb =
        m_root->findChild<QQuickItem *>(QStringLiteral("drawerAutomationScrollThumb"));
    QVERIFY(scrollbar);
    QVERIFY(scrollbarThumb);
    QTRY_VERIFY(scrollbar->isVisible() && scrollbarThumb->isVisible());
    QTRY_VERIFY(drawer->chrome().automationMaximumScrollY() > 0);
    const int maximum = drawer->chrome().automationMaximumScrollY();
    QTRY_COMPARE(scrollbar->property("maximum").toInt(), maximum);
    QTRY_VERIFY(scrollbar->height() > scrollbarThumb->height());

    const auto beginAutomationDrag = [&](qreal direction) {
        const QPointF pressPosition =
            scrollbarThumb->mapToScene(scrollbarThumb->boundingRect().center());
        press(pressPosition);
        const qreal activation = QGuiApplication::styleHints()->startDragDistance() + 1.0;
        move(pressPosition + QPointF(0.0, direction * activation));
        const QPointF dragPosition = pressPosition + QPointF(0.0, direction * (activation + 1.0));
        move(dragPosition);
        return dragPosition;
    };

    page->setVerticalScroll(0);
    QTRY_COMPARE(page->verticalScroll(), 0);
    QTRY_VERIFY(closeEnough(scrollbarThumb->y(), 0.0));
    QVERIFY(itemWithinTrack(*scrollbar, *scrollbarThumb, Qt::Vertical));
    QPointF drag = beginAutomationDrag(1.0);
    QTRY_VERIFY(page->verticalScroll() > 0);
    move(QPointF(drag.x(), window().height() - 1.0));
    QTRY_COMPARE(page->verticalScroll(), maximum);
    QVERIFY(itemWithinTrack(*scrollbar, *scrollbarThumb, Qt::Vertical));
    const QPointF middle = scrollbar->mapToScene(scrollbar->boundingRect().center());
    move(middle);
    QTRY_VERIFY(page->verticalScroll() > 0 && page->verticalScroll() < maximum);
    QVERIFY(itemWithinTrack(*scrollbar, *scrollbarThumb, Qt::Vertical));
    release();

    page->setVerticalScroll(maximum);
    QTRY_COMPARE(page->verticalScroll(), maximum);
    QTRY_VERIFY(closeEnough(scrollbarThumb->y() + scrollbarThumb->height(), scrollbar->height()));
    QVERIFY(itemWithinTrack(*scrollbar, *scrollbarThumb, Qt::Vertical));
    drag = beginAutomationDrag(-1.0);
    QTRY_VERIFY(page->verticalScroll() < maximum);
    move(QPointF(drag.x(), 1.0));
    QTRY_COMPARE(page->verticalScroll(), 0);
    QVERIFY(itemWithinTrack(*scrollbar, *scrollbarThumb, Qt::Vertical));
    move(middle);
    QTRY_VERIFY(page->verticalScroll() > 0 && page->verticalScroll() < maximum);
    QVERIFY(itemWithinTrack(*scrollbar, *scrollbarThumb, Qt::Vertical));
    release();
}

void ScrollbarTest::automationZeroRangeIgnoresDrag()
{
    EditorDrawer *const drawer = view().editorDrawer();
    QVERIFY(drawer);
    AutomationPage *const page = drawer->automationPage();
    QVERIFY(page);

    QQuickItem *const scrollbar =
        m_root->findChild<QQuickItem *>(QStringLiteral("drawerAutomationScrollBar"));
    QQuickItem *const scrollbarThumb =
        m_root->findChild<QQuickItem *>(QStringLiteral("drawerAutomationScrollThumb"));
    QVERIFY(scrollbar);
    QVERIFY(scrollbarThumb);

    const int sectionHeight = view().drawerSectionHeight(EditorDrawerPage::Automations);
    const int overhead = std::max(0, sectionHeight - drawer->chrome().automationViewportHeight());
    const int fittingHeight =
        std::min(drawer->maximumSectionHeight(), page->canvas()->minimumContentHeight() + overhead);
    view().setDrawerSectionHeight(EditorDrawerPage::Automations, fittingHeight);

    QTRY_COMPARE(drawer->chrome().automationMaximumScrollY(), 0);
    QTRY_VERIFY(closeEnough(scrollbarThumb->height(), scrollbar->height()));
    QVERIFY(itemWithinTrack(*scrollbar, *scrollbarThumb, Qt::Vertical));

    const QPointF pressPosition =
        scrollbarThumb->mapToScene(scrollbarThumb->boundingRect().center());
    press(pressPosition);
    move(pressPosition - QPointF(0.0, 2.0 * scrollbar->height()));
    QTRY_COMPARE(page->verticalScroll(), 0);
    QVERIFY(closeEnough(scrollbarThumb->height(), scrollbar->height()));
    QVERIFY(itemWithinTrack(*scrollbar, *scrollbarThumb, Qt::Vertical));
    release();
    QCOMPARE(page->verticalScroll(), 0);
    QVERIFY(closeEnough(scrollbarThumb->height(), scrollbar->height()));
    QVERIFY(itemWithinTrack(*scrollbar, *scrollbarThumb, Qt::Vertical));
}

void ScrollbarTest::signedRangeDragRebasesAndTracksModel()
{
    QString error;
    QQuickItem *const standaloneRoot = createStandaloneScrollbar(*m_root, &error);
    QVERIFY2(standaloneRoot, qPrintable(error));
    QQuickItem *const scrollbar =
        standaloneRoot->findChild<QQuickItem *>(QStringLiteral("standaloneTimelineScrollbar"));
    QQuickItem *const scrollbarThumb =
        standaloneRoot->findChild<QQuickItem *>(QStringLiteral("standaloneTimelineScrollbarThumb"));
    QVERIFY(scrollbar);
    QVERIFY(scrollbarThumb);

    QTRY_VERIFY(scrollbar->width() > 0.0 && scrollbarThumb->width() > 0.0);
    const qreal initialExpectedWidth = 20.0 / (80.0 - -80.0 + 20.0) * scrollbar->width();
    QVERIFY(closeEnough(scrollbarThumb->width(), initialExpectedWidth));
    QVERIFY(itemWithinTrack(*scrollbar, *scrollbarThumb, Qt::Horizontal));

    const QPointF pressPosition =
        scrollbarThumb->mapToScene(scrollbarThumb->boundingRect().center());
    press(pressPosition);
    const qreal activation = QGuiApplication::styleHints()->startDragDistance() + 1.0;
    move(pressPosition + QPointF(activation, 0.0));
    const QPointF initialMove = pressPosition + QPointF(scrollbar->width() / 4.0, 0.0);
    move(initialMove);
    QTRY_VERIFY(standaloneRoot->property("modelValue").toReal() > -80.0 &&
                standaloneRoot->property("modelValue").toReal() < 80.0);
    const qreal valueBeforeResize = standaloneRoot->property("modelValue").toReal();

    standaloneRoot->setProperty("modelMaximum", 180.0);
    standaloneRoot->setProperty("modelPageStep", 60.0);
    const qreal resizedExpectedWidth = 60.0 / (180.0 - -80.0 + 60.0) * scrollbar->width();
    QTRY_VERIFY(closeEnough(standaloneRoot->property("modelValue").toReal(), valueBeforeResize));
    QTRY_VERIFY(closeEnough(scrollbarThumb->width(), resizedExpectedWidth));
    QVERIFY(itemWithinTrack(*scrollbar, *scrollbarThumb, Qt::Horizontal));

    const qreal resizedTravel = scrollbar->property("thumbTravel").toReal();
    QVERIFY(resizedTravel > 0.0);
    move(initialMove + QPointF(1.0, 0.0));
    const qreal expectedOnePixel = valueBeforeResize + 260.0 / resizedTravel;
    QTRY_VERIFY(closeEnough(standaloneRoot->property("modelValue").toReal(), expectedOnePixel));

    move(initialMove + QPointF(2.0 * scrollbar->width(), 0.0));
    QTRY_COMPARE(standaloneRoot->property("modelValue").toReal(), 180.0);
    QVERIFY(closeEnough(scrollbarThumb->x() + scrollbarThumb->width(), scrollbar->width()));
    QVERIFY(itemWithinTrack(*scrollbar, *scrollbarThumb, Qt::Horizontal));
    release();

    standaloneRoot->setProperty("modelValue", 20.0);
    const qreal expectedX = 100.0 / 260.0 * (scrollbar->width() - scrollbarThumb->width());
    QTRY_VERIFY(closeEnough(scrollbarThumb->x(), expectedX));
}

int runScrollbarCheck(const QString &projectRoot, const QString &songLabel,
                      const QStringList &qtArguments)
{
    ScrollbarTest test(projectRoot, songLabel);
    QStringList arguments{QStringLiteral("scrollbar")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
