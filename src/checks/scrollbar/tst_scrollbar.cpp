#include "checks/scrollbar/tst_scrollbar.h"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QPointingDevice>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QStyleHints>
#include <QUrl>
#include <QtTest>
#include <qqml.h>

#include <cmath>
#include <optional>
#include <utility>

#include "checks/fwd.hpp"
#include "checks/support/songfixture.h"
#include "checks/support/timelinequickcheck.h"
#include "core/tracklimits.h"
#include "project/projectidentity.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"

namespace {

constexpr int kViewWidth = 1280;
constexpr int kViewHeight = 800;
constexpr int kDefaultAutomationHeight = 400;
constexpr int kResizedAutomationHeight = 520;
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

// The catalog position comes from the production mapping only; clicking the
// real selector label is the same activation path a user takes.
bool activateParameterLabel(AutomationCanvas &canvas, QQuickItem &root,
                            const EditorAutomationRowId &row)
{
    const int index = checks::support::automationParameterIndex(canvas, row);
    if (index < 0)
        return false;
    QQuickItem *label = nullptr;
    if (!QTest::qWaitFor([&root, &label, index] {
            label = checks::support::visualDescendant(
                &root, QStringLiteral("automationParameterTab%1").arg(index));
            return label && label->isVisible() && label->isEnabled() && label->width() > 0.0 &&
                   label->height() > 0.0 && label->window();
        }))
        return false;
    QQuickWindow *const window = label->window();
    QQuickItem *const content = window ? window->contentItem() : nullptr;
    if (!content)
        return false;
    const QPointF point = content->mapFromScene(
        label->mapToScene(QPointF(label->width() / 2.0, label->height() / 2.0)));
    if (!content->boundingRect().contains(point))
        return false;
    QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, point.toPoint());
    return QTest::qWaitFor([&canvas, index] { return canvas.activeParameter() == index; });
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
    m_tab->resize(kViewWidth, kViewHeight);
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
    m_tab->show();

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
    m_tab.reset();
}

void ScrollbarTest::automationLabelActivatesAfterResize()
{
    EditorDrawer *const drawer = view().editorDrawer();
    QVERIFY(drawer);
    AutomationPage *const page = drawer->automationPage();
    QVERIFY(page);
    AutomationCanvas *const canvas = page->canvas();
    QVERIFY(canvas);

    // The automation scrollbar is removed end to end: neither its track nor
    // its thumb may exist anywhere in the visual tree, so no gutter strip is
    // reserved for them.
    QVERIFY(
        !checks::support::visualDescendant(m_root, QStringLiteral("drawerAutomationScrollBar")));
    QVERIFY(
        !checks::support::visualDescendant(m_root, QStringLiteral("drawerAutomationScrollThumb")));

    // Resizing the section re-flows the compact selector grid; a real click
    // on the repositioned song-global Tempo label proves the reclaimed
    // gutter/body geometry stays interactive.
    view().setDrawerSectionHeight(EditorDrawerPage::Automations, kResizedAutomationHeight);
    const EditorAutomationRowId tempoRow{EditorAutomationRowKind::Tempo, 0, 0};
    QVERIFY(activateParameterLabel(*canvas, *m_root, tempoRow));

    // The newly active plot resolves the Tempo row to a live body at the
    // resized geometry.
    QTRY_VERIFY(!canvas->laneBody(LaneHandle{0}).isEmpty());
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
