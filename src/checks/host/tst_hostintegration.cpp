#include "checks/fwd.hpp"

#include <cmath>
#include <memory>
#include <optional>
#include <utility>
#include <vector>

#include <QCloseEvent>
#include <QCryptographicHash>
#include <QCursor>
#include <QDirIterator>
#include <QFile>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QScopeGuard>
#include <QSettings>
#include <QStringList>
#include <QVariant>
#include <QtTest>
#include <algorithm>

#include "checks/host/hosttestsupport.h"
#include "checks/quickpopupguard.h"
#include "checks/support/asyncwait.h"
#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"
#include "core/miditimeline.h"
#include "mainwindow.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editorviewstate.h"
#include "ui/layout.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/workspacequick/workspacequickhost.h"
#include "ui/workspaceui.h"
namespace checks::host {

namespace {

bool waitForProjectReady(const WorkspaceUi &workspace)
{
    return checks::async_wait::waitUntil(
               [] { return true; },
               [&workspace] { return workspace.projectState().state == ProjectOpenState::Ready; },
               30000, 1) == checks::async_wait::Result::Ready;
}

bool waitForTabReady(const WorkspaceUi &workspace, SongTab *tab)
{
    return tab &&
           checks::async_wait::waitUntil(
               [&workspace, tab] { return workspace.songTabFor(tab->name()) == tab; },
               [tab] { return tab->isReady(); }, 30000, 1) == checks::async_wait::Result::Ready;
}

QByteArray fileBytes(const QString &path)
{
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray{};
}

QByteArray directoryFingerprint(const QString &root)
{
    QCryptographicHash hash(QCryptographicHash::Sha256);
    QDirIterator entries(root, QDir::Files, QDirIterator::Subdirectories);
    QStringList paths;
    while (entries.hasNext())
        paths.append(entries.next());
    std::sort(paths.begin(), paths.end());
    for (const QString &path : paths) {
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly))
            return {};
        hash.addData(path.mid(root.size()).toUtf8());
        hash.addData(file.readAll());
    }
    return hash.result();
}

QPointF velocityNodePosition(const SongView &view, const VelocityArea &area,
                             const MidiTimeline &timeline, const DocNote &note)
{
    const qreal x = qreal(note.tick) * view.camera().pxPerBeat() / timeline.ticksPerBeat -
                    view.camera().scrollX();
    return {x, area.axis().velocityToY(note.velocity)};
}

std::optional<QPointF> emptyRollCell(const SongView &view, const SongDocument &document, int track,
                                     const songview::TimelineInputItem &roll)
{
    const std::vector<DocNote> notes = document.notesForTrack(track);
    const auto occupied = [&notes](uint64_t tick, uint64_t duration, int key) {
        return std::any_of(notes.cbegin(), notes.cend(),
                           [tick, duration, key](const DocNote &note) {
                               return int(note.key) == key && note.tick < tick + duration &&
                                      tick < note.tick + note.duration;
                           });
    };
    const qreal dpr = roll.devicePixelRatio();
    const qreal rightLimit = roll.width() - 4.0;
    const double keyHeight = view.camera().keyHeight();
    const double scrollY = view.camera().scrollY();
    for (int key = 115; key >= 24; --key) {
        const qreal top = std::round(((127 - key) * keyHeight - scrollY) * dpr) / dpr;
        const qreal bottom = top + keyHeight;
        if (top < 0.0 || bottom > roll.height())
            continue;
        uint64_t tick = view.grid().snapTickUp(std::max(0.0, view.camera().tickAtContentX(4.0)));
        for (int guard = 0; guard < 1000; ++guard) {
            const uint64_t next = view.grid().snapTickUp(double(tick) + 1.0);
            if (next <= tick)
                break;
            const qreal left = view.camera().displayX(double(tick), 0.0, dpr);
            const qreal right = view.camera().displayX(double(next), 0.0, dpr);
            if (left > rightLimit)
                break;
            const uint64_t duration = view.grid().gridTicksAt(tick);
            if (left >= 4.0 && right <= rightLimit && right - left >= 4.0 &&
                !occupied(tick, duration, key))
                return QPointF((left + right) / 2.0, (top + bottom) / 2.0);
            tick = next;
        }
    }
    return std::nullopt;
}

songview::QuickPopupSession *openRulerMenuThroughWindow(SongView &view, QQuickWindow &window)
{
    auto *const quick =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    QQuickItem *const root = quick ? quick->rootObject() : nullptr;
    auto *const ruler =
        root ? root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineRulerInput"))
             : nullptr;
    if (!ruler || !ruler->bounds().contains(ruler->bounds().center()))
        return nullptr;
    QTest::mouseClick(&window, Qt::RightButton, Qt::NoModifier,
                      ruler->mapToScene(ruler->bounds().center()).toPoint());
    songview::QuickPopupSession *const popup = quick_popup::popupSession(view);
    if (!popup || !QTest::qWaitFor([popup] {
            QQuickItem *const panel = quick_popup::menuPanel(*popup);
            return popup->isOpen() && panel && quick_popup::menuModel(*panel);
        }))
        return nullptr;
    return popup;
}

class SettingsGuard final
{
  public:
    SettingsGuard()
    {
        for (const QString &key : m_settings.allKeys())
            m_values.emplace_back(key, m_settings.value(key));
        m_settings.clear();
    }

    ~SettingsGuard()
    {
        m_settings.clear();
        for (const auto &[key, value] : m_values)
            m_settings.setValue(key, value);
        m_settings.sync();
    }

    SettingsGuard(const SettingsGuard &) = delete;
    SettingsGuard &operator=(const SettingsGuard &) = delete;

  private:
    QSettings m_settings;
    std::vector<std::pair<QString, QVariant>> m_values;
};

struct Session final {
    std::unique_ptr<SettingsGuard> settings;
    std::unique_ptr<checks::ProjectFixture> fixture;
    std::unique_ptr<MainWindow> window;
    SongTab *first = nullptr;
    SongTab *active = nullptr;
};

} // namespace

class HostIntegrationTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(HostIntegrationTest)

  public:
    HostIntegrationTest(QString projectRoot, QString songA, QString songB, QString screenshotPath)
        : m_projectRoot(std::move(projectRoot))
        , m_songA(std::move(songA))
        , m_songB(std::move(songB))
        , m_screenshotPath(std::move(screenshotPath))
    {}

  private slots:
    void twoTabReadySessionWithTwoNoteSeed()
    {
        const std::optional<Session> session = openSession();
        QVERIFY(session.has_value());
        QVERIFY(session->first != session->active);
        QVERIFY(session->active->view().document());
        QVERIFY(twoNoteTrack(session->active->document()) >= 0);
        QCOMPARE(session->active->view().selectionModel().noteSelection().size(), size_t{2});
    }

    void steadyPlaybackIsPresentationOnly()
    {
        const std::optional<Session> session = openSession();
        QVERIFY(session.has_value());
        SongView &view = session->active->view();
        auto *velocity = view.editorDrawer()->velocityArea();
        QVERIFY(velocity);
        uint64_t first = 0;
        bool found = false;
        for (uint64_t candidate = 0; candidate < 4096 && !found; ++candidate) {
            const DrawerPageVoiceContext context = view.voiceContext(candidate);
            uint64_t previousSample = 0;
            found = true;
            for (uint64_t offset = 0; offset <= 120; ++offset) {
                const DrawerPageVoiceContext next = view.voiceContext(candidate + offset);
                const uint64_t sample =
                    session->active->timeline()->sampleForTick(candidate + offset);
                if (next.voice != context.voice || next.voiceSlot != context.voiceSlot ||
                    (offset && sample <= previousSample)) {
                    found = false;
                    break;
                }
                previousSample = sample;
            }
            if (found)
                first = candidate;
        }
        QVERIFY2(found, "required route101 fixture has no steady 120-tick voice context");
        view.setFollowPlayhead(false);
        view.setPlayheadSample(session->active->timeline()->sampleForTick(first), true);
        settle();
        const auto automationGeometry =
            view.timelineBandLayout().geometry(songview::TimelineBand::Automation);
        QVERIFY(automationGeometry.has_value());
        QString captureError;
        const QImage automationBefore =
            checks::support::captureQuickBand(view, automationGeometry->rect, &captureError);
        QVERIFY2(!automationBefore.isNull(), qPrintable(captureError));
        const auto before = velocity->diagnostics();
        for (uint64_t tick = first + 1; tick <= first + 120; ++tick)
            view.setPlayheadSample(session->active->timeline()->sampleForTick(tick), true);
        QCoreApplication::processEvents();
        QCOMPARE(uint64_t(view.playheadTick() + 0.5), first + 120);
        QCOMPARE(velocity->diagnostics().playheadPresentationCount,
                 before.playheadPresentationCount + 120);
        QCOMPARE(velocity->diagnostics().contentBuildCount, before.contentBuildCount);
        const QImage automationAfter =
            checks::support::captureQuickBand(view, automationGeometry->rect, &captureError);
        QVERIFY2(!automationAfter.isNull(), qPrintable(captureError));
        QCOMPARE(automationAfter, automationBefore);
    }

    void velocityEditCommitsOnceInvalidatesAndUndoes()
    {
        const std::optional<Session> session = openSession();
        QVERIFY(session.has_value());
        SongView &view = session->active->view();
        SongDocument &document = session->active->document();
        const int track = twoNoteTrack(document);
        QVERIFY(track >= 0);
        const std::vector<DocNote> notes = document.notesForTrack(track);
        view.selectTrack(track);
        view.selectionModel().setNoteSelection({notes[0].noteId, notes[1].noteId});
        auto *velocity = view.editorDrawer()->velocityArea();
        QVERIFY(velocity);
        QString captureError;
        const auto renderVelocity = [&]() {
            const auto geometry =
                view.timelineBandLayout().geometry(songview::TimelineBand::Velocity);
            return checks::support::captureQuickBand(view, geometry ? geometry->rect : QRect{},
                                                     &captureError);
        };
        const QImage baselineFrame = renderVelocity();
        QVERIFY2(!baselineFrame.isNull(), qPrintable(captureError));
        const auto before = velocity->diagnostics();
        const uint64_t revision = document.revision();
        const int undo = document.undoStack()->index();
        const uint8_t changed = notes[0].velocity == 127 ? 1 : uint8_t(notes[0].velocity + 1);
        QVERIFY(view.beginVelocityGesture(notes));
        QVERIFY(view.updateVelocityGesture({{notes[0].noteId, changed}}));
        QVERIFY(view.previewVelocity(notes[0].noteId).has_value());
        QCOMPARE(document.revision(), revision);
        QCOMPARE(document.undoStack()->index(), undo);
        QCOMPARE(view.commitVelocityGesture(), SongView::VelocityCommitResult::Committed);
        QCOMPARE(document.revision(), revision + 1);
        QCOMPARE(document.undoStack()->index(), undo + 1);
        DocNote landed;
        QVERIFY(document.findNote(notes[0].noteId, &landed));
        QCOMPARE(landed.velocity, changed);
        QVERIFY(!view.previewVelocity(notes[0].noteId));
        const QImage committedFrame = renderVelocity();
        QVERIFY2(!committedFrame.isNull(), qPrintable(captureError));
        QVERIFY(velocity->diagnostics().contentBuildCount > before.contentBuildCount);
        document.undoStack()->undo();
        const QImage undoneFrame = renderVelocity();
        QVERIFY2(!undoneFrame.isNull(), qPrintable(captureError));
        const auto selectionBefore = velocity->diagnostics();
        view.selectionModel().clearNoteSelection();
        const QImage deselectedFrame = renderVelocity();
        QVERIFY2(!deselectedFrame.isNull(), qPrintable(captureError));
        QVERIFY(velocity->diagnostics().contentBuildCount > selectionBefore.contentBuildCount);
        const auto zoomBefore = velocity->diagnostics();
        auto *quick = view.quickView();
        QVERIFY(quick && quick->quickWindow());
        view.zoomAroundContentX(1.1, qreal(quick->quickWindow()->width()) / 2.0);
        const QImage zoomedFrame = renderVelocity();
        QVERIFY2(!zoomedFrame.isNull(), qPrintable(captureError));
        QVERIFY(velocity->diagnostics().contentBuildCount > zoomBefore.contentBuildCount);
    }
    void readySongTabVelocityTransactionRetainsHeldAndCommittedContracts()
    {
        const std::optional<Session> session = openSession();
        QVERIFY(session.has_value());
        SongView &view = session->active->view();
        SongDocument &document = session->active->document();
        const int track = twoNoteTrack(document);
        QVERIFY(track >= 0);
        std::vector<DocNote> notes = document.notesForTrack(track);
        QVERIFY(notes.size() >= 2);
        view.selectTrack(track);
        const std::vector<NoteId> selected{notes[0].noteId, notes[1].noteId};
        view.selectionModel().setNoteSelection(selected);
        const uint64_t revision = document.revision();
        const int undo = document.undoStack()->index();
        QVERIFY(view.beginVelocityGesture(notes));
        QVERIFY(!view.updateVelocityGesture(
            {{notes[0].noteId, notes[0].velocity}, {notes[1].noteId, notes[1].velocity}}));
        QCOMPARE(view.commitVelocityGesture(), SongView::VelocityCommitResult::Unchanged);
        QCOMPARE(document.revision(), revision);
        QCOMPARE(document.undoStack()->index(), undo);
        const uint8_t first =
            notes[0].velocity == 127 ? uint8_t{1} : uint8_t(notes[0].velocity + 1);
        auto *quick =
            view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
        auto *velocityInput = quick ? quick->rootObject()->findChild<songview::TimelineInputItem *>(
                                          QStringLiteral("timelineVelocityInput"))
                                    : nullptr;
        auto *velocity = view.editorDrawer()->velocityArea();
        const std::shared_ptr<const MidiTimeline> timeline = session->active->timeline();
        QVERIFY(velocityInput && velocity && timeline);
        const QPointF node = velocityNodePosition(view, *velocity, *timeline, notes[0]);
        checks::events::sendMouse(*velocityInput, QEvent::MouseButtonPress, node, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*velocityInput, QEvent::MouseButtonRelease, node, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        QCOMPARE(document.revision(), revision);
        QCOMPARE(document.undoStack()->index(), undo);
        QCOMPARE(view.selectionModel().noteSelection().size(), size_t{1});
        QVERIFY(std::find(selected.cbegin(), selected.cend(),
                          view.selectionModel().noteSelection().front()) != selected.cend());
        view.selectionModel().setNoteSelection(selected);
        const uint8_t second =
            notes[1].velocity == 127 ? uint8_t{1} : uint8_t(notes[1].velocity + 1);
        QVERIFY(view.beginVelocityGesture(notes));
        QVERIFY(view.updateVelocityGesture({{notes[0].noteId, first}, {notes[1].noteId, second}}));
        QCOMPARE(view.previewVelocity(notes[0].noteId), std::optional<uint8_t>{first});
        QCOMPARE(view.previewVelocity(notes[1].noteId), std::optional<uint8_t>{second});
        DocNote held;
        QVERIFY(document.findNote(notes[0].noteId, &held));
        QCOMPARE(held.velocity, notes[0].velocity);
        QCOMPARE(document.revision(), revision);
        QCOMPARE(document.undoStack()->index(), undo);
        QCOMPARE(view.commitVelocityGesture(), SongView::VelocityCommitResult::Committed);
        QCOMPARE(document.revision(), revision + 1);
        QCOMPARE(document.undoStack()->index(), undo + 1);
        QVERIFY(document.findNote(notes[0].noteId, &held));
        QCOMPARE(held.velocity, first);
        QVERIFY(!view.previewVelocity(notes[0].noteId));
        QCOMPARE(view.selectionModel().noteSelection(), selected);
        document.undoStack()->undo();
        QCOMPARE(view.selectionModel().noteSelection(), selected);
        document.undoStack()->redo();
        notes = document.notesForTrack(track);
        const uint8_t staleTarget =
            notes[0].velocity == 127 ? uint8_t{1} : uint8_t(notes[0].velocity + 1);
        const uint8_t externalTarget =
            notes[1].velocity == 127 ? uint8_t{1} : uint8_t(notes[1].velocity + 1);
        QVERIFY(view.beginVelocityGesture(notes));

        QVERIFY(view.updateVelocityGesture({{notes[0].noteId, staleTarget}}));
        const uint64_t staleRevision = document.revision();
        document.blockSignals(true);
        document.setNotesVelocity({notes[1]}, externalTarget);
        document.blockSignals(false);
        QCOMPARE(view.commitVelocityGesture(), SongView::VelocityCommitResult::Rejected);
        QCOMPARE(document.revision(), staleRevision + 1);
        QCOMPARE(document.undoStack()->index(), undo + 2);
        DocNote staleFirst;
        DocNote externalSecond;
        QVERIFY(document.findNote(notes[0].noteId, &staleFirst));
        QVERIFY(document.findNote(notes[1].noteId, &externalSecond));
        QCOMPARE(staleFirst.velocity, notes[0].velocity);
        QCOMPARE(externalSecond.velocity, externalTarget);
        QVERIFY(!view.previewVelocity(notes[0].noteId));
        QVERIFY(!view.previewVelocity(notes[1].noteId));
        QCOMPARE(view.selectionModel().noteSelection(), selected);
    }
    void automationPanLifecycle_data()
    {
        QTest::addColumn<QString>("route");
        QTest::newRow("page-switch") << QStringLiteral("page-switch");
        QTest::newRow("quick-ungrab") << QStringLiteral("quick-ungrab");
        QTest::newRow("quick-focus-loss") << QStringLiteral("quick-focus-loss");
        QTest::newRow("quick-deactivate") << QStringLiteral("quick-deactivate");
    }

    void automationPanLifecycle()
    {
        QFETCH(QString, route);
        const std::optional<Session> session = openSession();
        QVERIFY(session.has_value());
        SongView &view = session->active->view();
        SongDocument &document = session->active->document();
        view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
        view.setDrawerActivePage(EditorDrawerPage::Automations);
        QCoreApplication::processEvents();
        auto *quick =
            view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
        auto *canvas = view.editorDrawer()->automationPage()->canvas();
        auto *input = quick ? quick->rootObject()->findChild<songview::TimelineInputItem *>(
                                  QStringLiteral("timelineAutomationInput"))
                            : nullptr;
        QVERIFY(quick && canvas && input);
        QQuickWindow *const quickWindow = quick->quickWindow();
        QVERIFY(quickWindow);
        QVERIFY(view.focusTimelineBand(songview::TimelineBand::Automation, Qt::OtherFocusReason));
        QTRY_VERIFY(view.focusedTimelineBand() == songview::TimelineBand::Automation);
        QTRY_VERIFY(input->hasActiveFocus());
        const QByteArray midi = document.smf().write();
        const uint64_t revision = document.revision();
        const int undo = document.undoStack()->count();
        const QPointF point(input->width() / 2.0, input->height() / 2.0);
        const QPoint windowPoint = input->mapToScene(point).toPoint();
        QTest::mouseEvent(QTest::MouseMove, quickWindow, Qt::NoButton, Qt::NoModifier, windowPoint);
        QTest::mousePress(quickWindow, Qt::MiddleButton, Qt::NoModifier, windowPoint);
        bool buttonHeld = true;
        const auto releaseButton = qScopeGuard([quickWindow, windowPoint, &buttonHeld] {
            if (buttonHeld)
                QTest::mouseRelease(quickWindow, Qt::MiddleButton, Qt::NoModifier, windowPoint);
        });
        QTRY_COMPARE(quickWindow->mouseGrabberItem(), static_cast<QQuickItem *>(input));
        QVERIFY(canvas->isPanning());
        if (route == QStringLiteral("page-switch")) {
            view.setDrawerActivePage(EditorDrawerPage::Velocity);
        } else if (route == QStringLiteral("quick-ungrab")) {
            input->ungrabMouse();
            QTRY_VERIFY(!quickWindow->mouseGrabberItem());
        } else if (route == QStringLiteral("quick-focus-loss")) {
            QVERIFY(view.focusTimelineBand(songview::TimelineBand::Velocity, Qt::OtherFocusReason));
            QTRY_VERIFY(view.focusedTimelineBand() == songview::TimelineBand::Velocity);
            QTRY_VERIFY(!input->hasActiveFocus());
        } else {
            QEvent event(QEvent::WindowDeactivate);
            QApplication::sendEvent(quickWindow, &event);
        }
        if (route == QStringLiteral("quick-focus-loss")) {
            QCOMPARE(quickWindow->mouseGrabberItem(), static_cast<QQuickItem *>(input));
            QVERIFY(canvas->isPanning());
        } else {
            QTRY_VERIFY(!canvas->isPanning());
        }
        QTest::mouseRelease(quickWindow, Qt::MiddleButton, Qt::NoModifier, windowPoint);
        buttonHeld = false;
        QTRY_VERIFY(!canvas->isPanning());
        QCOMPARE(document.smf().write(), midi);
        QCOMPARE(document.revision(), revision);
        QCOMPARE(document.undoStack()->count(), undo);
        QVERIFY(!quickWindow->mouseGrabberItem());
    }

    void lifecycleTermination_data()
    {
        QTest::addColumn<QString>("route");
        QTest::newRow("page-switch") << QStringLiteral("page-switch");
        QTest::newRow("drawer-hide") << QStringLiteral("drawer-hide");
        QTest::newRow("track-replace") << QStringLiteral("track-replace");
        QTest::newRow("song-null") << QStringLiteral("song-null");
        QTest::newRow("document-null") << QStringLiteral("document-null");
        QTest::newRow("voice-replace") << QStringLiteral("voice-replace");
        QTest::newRow("voice-null") << QStringLiteral("voice-null");
        QTest::newRow("quick-ungrab") << QStringLiteral("quick-ungrab");
        QTest::newRow("quick-focus-loss") << QStringLiteral("quick-focus-loss");
        QTest::newRow("quick-deactivate") << QStringLiteral("quick-deactivate");
        QTest::newRow("escape") << QStringLiteral("escape");
    }

    void lifecycleTermination()
    {
        QFETCH(QString, route);
        const std::optional<Session> session = openSession();
        QVERIFY(session.has_value());
        SongView &view = session->active->view();
        SongDocument &document = session->active->document();
        const int track = twoNoteTrack(document);
        QVERIFY(track >= 0);
        const std::vector<DocNote> notes = document.notesForTrack(track);
        QVERIFY(!notes.empty());
        view.selectTrack(track);
        view.selectionModel().setNoteSelection({notes[0].noteId});
        auto *quick =
            view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
        auto *velocity = view.editorDrawer()->velocityArea();
        auto *velocityInput = quick ? quick->rootObject()->findChild<songview::TimelineInputItem *>(
                                          QStringLiteral("timelineVelocityInput"))
                                    : nullptr;
        const std::shared_ptr<const MidiTimeline> timeline = session->active->timeline();
        QVERIFY(quick && velocity && velocityInput && timeline);
        QQuickWindow *const quickWindow = quick->quickWindow();
        QVERIFY(quickWindow);
        QVERIFY(view.focusTimelineBand(songview::TimelineBand::Velocity, Qt::OtherFocusReason));
        QTRY_VERIFY(view.focusedTimelineBand() == songview::TimelineBand::Velocity);
        const QPointF press = velocityNodePosition(view, *velocity, *timeline, notes[0]);
        const uint8_t targetVelocity = notes[0].velocity <= 64 ? uint8_t{127} : uint8_t{1};
        const QPointF drag(press.x(), velocity->axis().velocityToY(targetVelocity));
        QVERIFY(velocityInput->bounds().contains(press));
        QVERIFY(velocityInput->bounds().contains(drag));
        const QPoint pressWindow = velocityInput->mapToScene(press).toPoint();
        const QPoint dragWindow = velocityInput->mapToScene(drag).toPoint();
        const QByteArray midi = document.smf().write();
        const uint64_t revision = document.revision();
        const int undo = document.undoStack()->count();
        QTest::mouseEvent(QTest::MouseMove, quickWindow, Qt::NoButton, Qt::NoModifier, pressWindow);
        QTest::mousePress(quickWindow, Qt::LeftButton, Qt::NoModifier, pressWindow);
        bool buttonHeld = true;
        QPoint lastWindowPoint = pressWindow;
        const auto releaseButton = qScopeGuard([quickWindow, &lastWindowPoint, &buttonHeld] {
            if (buttonHeld)
                QTest::mouseRelease(quickWindow, Qt::LeftButton, Qt::NoModifier, lastWindowPoint);
        });
        QTRY_COMPARE(quickWindow->mouseGrabberItem(), static_cast<QQuickItem *>(velocityInput));
        lastWindowPoint = dragWindow;
        QTest::mouseEvent(QTest::MouseMove, quickWindow, Qt::NoButton, Qt::NoModifier, dragWindow);
        QTRY_VERIFY(view.previewVelocity(notes[0].noteId).has_value());
        QVERIFY(view.userGestureActive());
        const bool clearsSelection = route == QStringLiteral("track-replace") ||
                                     route == QStringLiteral("song-null") ||
                                     route == QStringLiteral("document-null");
        LoadedVoiceGroup replacement = {};
        if (route == QStringLiteral("page-switch")) {
            view.setDrawerActivePage(EditorDrawerPage::Automations);
        } else if (route == QStringLiteral("drawer-hide")) {
            view.setDrawerSectionVisible(EditorDrawerPage::Velocity, false);
        } else if (route == QStringLiteral("track-replace")) {
            view.selectTrack(track == 0 ? 1 : 0);
        } else if (route == QStringLiteral("song-null")) {
            view.setSong(nullptr, nullptr);
        } else if (route == QStringLiteral("document-null")) {
            view.setDocument(nullptr);
        } else if (route == QStringLiteral("voice-replace")) {
            view.setVoicegroup(&replacement);
        } else if (route == QStringLiteral("voice-null")) {
            view.setVoicegroup(nullptr);
        } else if (route == QStringLiteral("quick-ungrab")) {
            velocityInput->ungrabMouse();
            QTRY_VERIFY(!quickWindow->mouseGrabberItem());
        } else if (route == QStringLiteral("quick-focus-loss")) {
            QVERIFY(view.focusTimelineBand(songview::TimelineBand::Roll, Qt::OtherFocusReason));
            QTRY_VERIFY(view.focusedTimelineBand() == songview::TimelineBand::Roll);
        } else if (route == QStringLiteral("quick-deactivate")) {
            QEvent event(QEvent::WindowDeactivate);
            QApplication::sendEvent(quickWindow, &event);
        } else {
            QTest::keyClick(quickWindow, Qt::Key_Escape);
        }
        QTRY_VERIFY(!view.userGestureActive());
        QTest::mouseRelease(quickWindow, Qt::LeftButton, Qt::NoModifier, dragWindow);
        buttonHeld = false;
        QCOMPARE(document.smf().write(), midi);
        QCOMPARE(document.revision(), revision);
        QCOMPARE(document.undoStack()->count(), undo);
        QVERIFY(!view.previewVelocity(notes[0].noteId));
        if (clearsSelection)
            QVERIFY(view.selectionModel().noteSelection().empty());
        else
            QVERIFY(!view.selectionModel().noteSelection().empty());
        QVERIFY(!quickWindow->mouseGrabberItem());
        const QCursor *cursor = QApplication::overrideCursor();
        QVERIFY(!cursor || cursor->shape() != Qt::ClosedHandCursor);
        if (route == QStringLiteral("voice-replace"))
            view.setVoicegroup(nullptr);
    }

    void documentMutationUndoRedoAndReloadPreemptPreview_data()
    {
        QTest::addColumn<QString>("event");
        QTest::newRow("mutation") << QStringLiteral("mutation");
        QTest::newRow("undo") << QStringLiteral("undo");
        QTest::newRow("redo") << QStringLiteral("redo");
        QTest::newRow("reload") << QStringLiteral("reload");
    }

    void documentMutationUndoRedoAndReloadPreemptPreview()
    {
        QFETCH(QString, event);
        const std::optional<Session> session = openSession();
        QVERIFY(session.has_value());
        SongView &view = session->active->view();
        SongDocument &document = session->active->document();
        const int track = twoNoteTrack(document);
        QVERIFY(track >= 0);
        const std::vector<DocNote> notes = document.notesForTrack(track);
        view.selectTrack(track);
        view.selectionModel().setNoteSelection({notes[0].noteId});
        QVERIFY(view.beginVelocityGesture(notes));
        QVERIFY(view.updateVelocityGesture({{notes[0].noteId, 96}}));
        uint64_t revision = document.revision();
        int undoIndex = document.undoStack()->index();
        int undoCount = document.undoStack()->count();
        if (event == QStringLiteral("mutation")) {
            document.setNotesVelocity(
                {notes[0]}, notes[0].velocity == 127 ? uint8_t{1} : uint8_t(notes[0].velocity + 1));
            QCOMPARE(document.revision(), revision + 1);
            QCOMPARE(document.undoStack()->index(), undoIndex + 1);
            QCOMPARE(document.undoStack()->count(), undoCount + 1);
        } else if (event == QStringLiteral("undo")) {
            document.setNotesVelocity({notes[0]}, 95);
            revision = document.revision();
            undoIndex = document.undoStack()->index();
            document.undoStack()->undo();
            QCOMPARE(document.revision(), revision + 1);
            QCOMPARE(document.undoStack()->index(), undoIndex - 1);
        } else if (event == QStringLiteral("redo")) {
            document.setNotesVelocity({notes[0]}, 95);
            document.undoStack()->undo();
            revision = document.revision();
            undoIndex = document.undoStack()->index();
            document.undoStack()->redo();
            QCOMPARE(document.revision(), revision + 1);
            QCOMPARE(document.undoStack()->index(), undoIndex + 1);
        } else {
            session->window->m_workspace->requestSongOpen(session->active->name());
            QVERIFY(waitForTabReady(*session->window->m_workspace, session->active));
            QCOMPARE(document.undoStack()->count(), 0);
            QVERIFY(view.selectionModel().noteSelection().empty());
        }
        QVERIFY(!view.previewVelocity(notes[0].noteId));
    }

    void appearanceNotificationPreservesAutomationRaster()
    {
        const std::optional<Session> session = openSession();
        QVERIFY(session.has_value());
        SongView &view = session->active->view();
        auto *quick =
            view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
        QVERIFY(quick);
        QQuickItem *root = quick->rootObject();
        QVERIFY(root);
        auto *automation = root->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineAutomationInput"));
        QVERIFY(automation);
        const auto geometry =
            view.timelineBandLayout().geometry(songview::TimelineBand::Automation);
        QVERIFY(geometry.has_value());
        auto *page = view.editorDrawer()->automationPage();
        QVERIFY(page);
        const auto before = page->canvas()->rows();
        QString error;
        const QImage baseline = checks::support::captureQuickBand(view, geometry->rect, &error);
        QVERIFY2(!baseline.isNull(), qPrintable(error));
        automation->notifyHostAppearanceChanged();
        checks::support::pumpQuick();
        const QImage after = checks::support::captureQuickBand(view, geometry->rect, &error);
        QVERIFY2(!after.isNull(), qPrintable(error));
        QVERIFY(automationRowsEqual(page->canvas()->rows(), before));
        // Raster equality is intentionally a negative control after the
        // page-model assertion: an appearance notification must not alter
        // Automation content.
        QCOMPARE(after, baseline);
        if (!m_screenshotPath.isEmpty())
            QVERIFY2(after.save(m_screenshotPath), qPrintable(m_screenshotPath));
    }

    void nonSelectedEditorStateFansOutWithoutTouchingSongBytes()
    {
        const std::optional<Session> session = openSession();
        QVERIFY(session.has_value());
        SongView &origin = session->first->view();
        SongView &peer = session->active->view();
        const QByteArray beforeA = fileBytes(session->first->document().midPath());
        const QByteArray beforeB = fileBytes(session->active->document().midPath());
        const uint64_t revisionA = session->first->document().revision();
        const uint64_t revisionB = session->active->document().revision();
        const int undoA = session->first->document().undoStack()->count();
        const int undoB = session->active->document().undoStack()->count();
        EditorViewState state = origin.editorViewState();
        state.velocity = {true, 173};
        state.automation = {false, 44};
        state.voiceChanges = {true, 149};
        state.activePage = EditorDrawerPage::VoiceChanges;
        const EditorAutomationRowId lane{EditorAutomationRowKind::ControlChange, 0, 74};
        state.emptyLanes.insert(lane);
        state.laneRanges[lane] = 96;
        QSignalSpy publication(session->window->m_workspace.get(),
                               &WorkspaceUi::editorViewStateChanged);
        QSignalSpy persistence(session->window.get(), &MainWindow::editorViewStatePersisted);
        origin.setEditorViewState(state);
        QCoreApplication::processEvents();
        QCOMPARE(publication.count(), 1);
        QCOMPARE(persistence.count(), 1);
        QCOMPARE(origin.editorViewState(), state);
        QCOMPARE(peer.editorViewState(), state);
        QSettings settings;
        QCOMPARE(loadEditorViewState(settings), state);
        QCOMPARE(fileBytes(session->first->document().midPath()), beforeA);
        QCOMPARE(fileBytes(session->active->document().midPath()), beforeB);
        QCOMPARE(session->first->document().revision(), revisionA);
        QCOMPARE(session->active->document().revision(), revisionB);
        QCOMPARE(session->first->document().undoStack()->count(), undoA);
        QCOMPARE(session->active->document().undoStack()->count(), undoB);
    }

    void projectSwitchAndClosePreserveProjectBoundaries()
    {
        const std::optional<Session> session = openSession();
        QVERIFY(session.has_value());
        const QByteArray projectBefore = directoryFingerprint(session->fixture->root());
        QVERIFY(!projectBefore.isEmpty());
        const QByteArray beforeA = fileBytes(session->first->document().midPath());
        const QByteArray beforeB = fileBytes(session->active->document().midPath());
        const QString firstPath = session->first->document().midPath();
        const int undoA = session->first->document().undoStack()->count();
        const int undoB = session->active->document().undoStack()->count();
        const EditorViewState state = session->active->view().editorViewState();
        session->window->m_workspace->requestProjectOpenAt(session->fixture->root());
        QVERIFY(waitForProjectReady(*session->window->m_workspace));
        QCOMPARE(session->window->m_workspace->openTabCount(), qsizetype{0});
        QCOMPARE(directoryFingerprint(session->fixture->root()), projectBefore);
        QSettings settings;
        QCOMPARE(loadEditorViewState(settings), state);
        session->window->m_workspace->requestSongOpen(*SongName::create(m_songA));
        SongTab *reopened = session->window->m_workspace->selectedSongTab();
        QVERIFY(waitForTabReady(*session->window->m_workspace, reopened));
        QCOMPARE(reopened->view().editorViewState(), state);
        QCOMPARE(fileBytes(reopened->document().midPath()), beforeA);
        QCOMPARE(reopened->document().undoStack()->count(), undoA);
        session->window->m_workspace->requestSongOpen(*SongName::create(m_songB), true);
        SongTab *second = session->window->m_workspace->selectedSongTab();
        QVERIFY(waitForTabReady(*session->window->m_workspace, second));
        const QString secondPath = second->document().midPath();
        QCOMPARE(second->document().undoStack()->count(), undoB);
        QCOMPARE(session->window->m_workspace->openTabCount(), qsizetype{2});
        QCloseEvent event;
        QApplication::sendEvent(session->window.get(), &event);
        QVERIFY(event.isAccepted());
        QVERIFY(session->window->m_closeAccepted);
        QCOMPARE(fileBytes(firstPath), beforeA);
        QCOMPARE(fileBytes(secondPath), beforeB);
        QCOMPARE(directoryFingerprint(session->fixture->root()), projectBefore);
        QCOMPARE(loadEditorViewState(settings), state);
    }

    // A live ruler popup is queued in the selected page's real scene. Closing
    // that page must retire the popup before it can consume the shared window
    // again: a window-delivered edit and undo on the replacement page are the
    // consumer-visible proof. Project replacement then tears the last page
    // down while the shell and audio root remain alive.
    void selectedPageCloseCancelsPopupThenSiblingEditsAndProjectTeardown()
    {
        std::optional<Session> session = openSession();
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        WorkspaceUi &workspace = *window.m_workspace;
        SongTab *const sibling = session->first;
        SongTab *const outgoing = session->active;
        auto *const host = window.findChild<WorkspaceQuickHost *>();
        QVERIFY(host);
        QQuickWindow *const sharedWindow = host->window();
        QVERIFY(sharedWindow);
        QCOMPARE(workspace.selectedSongTab(), outgoing);
        QCOMPARE(workspace.openTabCount(), qsizetype{2});
        QCOMPARE(workspace.tabsInDisplayOrder(), (std::vector<SongTab *>{sibling, outgoing}));

        SongView &outgoingView = outgoing->view();
        auto *const outgoingQuick = outgoingView.findChild<songview::TimelineQuickView *>(
            QStringLiteral("timelineQuickCanvas"));
        QQuickItem *const outgoingRoot = outgoingQuick ? outgoingQuick->rootObject() : nullptr;
        QVERIFY(outgoingQuick && outgoingRoot);
        QCOMPARE(outgoingQuick->quickWindow(), sharedWindow);
        songview::QuickPopupSession *const popup =
            openRulerMenuThroughWindow(outgoingView, *sharedWindow);
        QVERIFY2(popup, "the selected page did not open its ruler popup in the workspace window");
        const QPointer<songview::QuickPopupSession> guardedPopup(popup);
        const auto cancelPopupOnFailure = qScopeGuard([guardedPopup] {
            if (guardedPopup && guardedPopup->isOpen())
                guardedPopup->cancel();
        });
        std::vector<SongTab *> selectionPublications;
        QObject::connect(
            &workspace, &WorkspaceUi::selectedSongTabChanged, &workspace,
            [&selectionPublications](SongTab *tab) { selectionPublications.push_back(tab); });

        workspace.requestCloseSelectedTab();
        QTRY_COMPARE(workspace.openTabCount(), qsizetype{1});
        settle(); // drain the retired popup's deferred scene work before sibling input
        QCOMPARE(selectionPublications, (std::vector<SongTab *>{nullptr, sibling}));
        QCOMPARE(workspace.selectedSongTab(), sibling);
        QCOMPARE(workspace.tabsInDisplayOrder(), (std::vector<SongTab *>{sibling}));
        QCOMPARE(window.m_selectedTab, sibling);
        QCOMPARE(window.m_appliedTimeline, sibling->timeline().get());
        QVERIFY(window.m_audio.songLoaded());
        QVERIFY(!sharedWindow->mouseGrabberItem());

        SongView &siblingView = sibling->view();
        auto *const siblingQuick = siblingView.findChild<songview::TimelineQuickView *>(
            QStringLiteral("timelineQuickCanvas"));
        QQuickItem *const siblingRoot = siblingQuick ? siblingQuick->rootObject() : nullptr;
        auto *const roll = siblingRoot ? siblingRoot->findChild<songview::TimelineInputItem *>(
                                             QStringLiteral("timelineRollInput"))
                                       : nullptr;
        QVERIFY(siblingQuick && siblingRoot && roll);
        QCOMPARE(siblingQuick->quickWindow(), sharedWindow);
        SongDocument &document = sibling->document();
        const int track = twoNoteTrack(document);
        QVERIFY(track >= 0);
        const std::optional<QPointF> emptyCell = emptyRollCell(siblingView, document, track, *roll);
        QVERIFY2(emptyCell.has_value(), "the selected sibling has no visible empty roll cell");
        QVERIFY(roll->bounds().contains(*emptyCell));
        const QByteArray beforeEdit = document.smf().write();
        const int undoBefore = document.undoStack()->index();
        QTest::mouseDClick(sharedWindow, Qt::LeftButton, Qt::NoModifier,
                           roll->mapToScene(*emptyCell).toPoint());
        settle();
        QCOMPARE(document.undoStack()->index(), undoBefore + 1);
        QVERIFY(document.smf().write() != beforeEdit);
        workspace.requestUndo();
        QTRY_COMPARE(document.undoStack()->index(), undoBefore);
        QCOMPARE(document.smf().write(), beforeEdit);
        QVERIFY(!document.isDirty());

        workspace.requestProjectOpenAt(session->fixture->root());
        QVERIFY(waitForProjectReady(workspace));
        QTRY_COMPARE(workspace.openTabCount(), qsizetype{0});
        settle();
        QCOMPARE(workspace.selectedSongTab(), static_cast<SongTab *>(nullptr));
        QVERIFY(workspace.tabsInDisplayOrder().empty());
        QCOMPARE(window.m_selectedTab, static_cast<SongTab *>(nullptr));
        QCOMPARE(window.m_appliedTimeline, static_cast<const MidiTimeline *>(nullptr));
        QVERIFY(!window.m_audio.songLoaded());
        QVERIFY(!sharedWindow->mouseGrabberItem());
        QCloseEvent event;
        QApplication::sendEvent(&window, &event);
        QVERIFY(event.isAccepted());
        QVERIFY(window.m_closeAccepted);
        session.reset();
    }

    // Note-off must reach audio before the outgoing page loses selection authority.
    void selectedPageCloseRoutesHeldAuditionBeforeSelectionHandoff_data()
    {
        QTest::addColumn<bool>("closePage");
        QTest::newRow("close") << true;
        QTest::newRow("selection-switch") << false;
    }

    void selectedPageCloseRoutesHeldAuditionBeforeSelectionHandoff()
    {
        QFETCH(bool, closePage);
        const std::optional<Session> session = openSession();
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        WorkspaceUi &workspace = *window.m_workspace;
        SongTab *const sibling = session->first;
        SongTab *const outgoing = session->active;
        auto *const host = window.findChild<WorkspaceQuickHost *>();
        QVERIFY(host);
        QQuickWindow *const sharedWindow = host->window();
        QVERIFY(sharedWindow);
        QCOMPARE(workspace.selectedSongTab(), outgoing);

        SongView &outgoingView = outgoing->view();
        auto *const outgoingQuick = outgoingView.findChild<songview::TimelineQuickView *>(
            QStringLiteral("timelineQuickCanvas"));
        QQuickItem *const outgoingRoot = outgoingQuick ? outgoingQuick->rootObject() : nullptr;
        auto *const gutter = outgoingRoot ? outgoingRoot->findChild<songview::TimelineInputItem *>(
                                                QStringLiteral("timelineRollGutterInput"))
                                          : nullptr;
        QVERIFY(outgoingQuick && outgoingRoot && gutter);
        QCOMPARE(outgoingQuick->quickWindow(), sharedWindow);

        enum class HandoffEvent {
            NoteOn,
            NoteOff,
            SelectionCleared,
            SiblingSelected,
        };
        std::vector<HandoffEvent> transitions;
        int heldTrack = -1;
        int heldKey = -1;
        QObject handoffMonitor;
        QObject::connect(
            &workspace, &WorkspaceUi::auditionNoteRequested, &handoffMonitor,
            [&transitions, &heldTrack, &heldKey](uint8_t track, uint8_t key, uint8_t velocity) {
                if (velocity > 0 && heldKey < 0) {
                    heldTrack = int(track);
                    heldKey = int(key);
                    transitions.push_back(HandoffEvent::NoteOn);
                } else if (velocity == 0 && int(track) == heldTrack && int(key) == heldKey) {
                    transitions.push_back(HandoffEvent::NoteOff);
                }
            });
        QObject::connect(&workspace, &WorkspaceUi::selectedSongTabChanged, &handoffMonitor,
                         [&transitions, sibling](SongTab *tab) {
                             if (!tab)
                                 transitions.push_back(HandoffEvent::SelectionCleared);
                             else if (tab == sibling)
                                 transitions.push_back(HandoffEvent::SiblingSelected);
                         });

        const QByteArray siblingBefore = sibling->document().smf().write();
        const int siblingUndoBefore = sibling->document().undoStack()->index();
        const QPoint heldPoint = gutter->mapToScene(gutter->bounds().center()).toPoint();
        QTest::mousePress(sharedWindow, Qt::LeftButton, Qt::NoModifier, heldPoint);
        QTRY_VERIFY(heldKey >= 0);
        if (closePage) {
            workspace.requestCloseSelectedTab();
            QTRY_COMPARE(workspace.openTabCount(), qsizetype{1});
        } else {
            workspace.selectSongTab(sibling);
            QCOMPARE(workspace.openTabCount(), qsizetype{2});
        }
        settle();

        const auto noteOn =
            std::find(transitions.cbegin(), transitions.cend(), HandoffEvent::NoteOn);
        const auto noteOff =
            std::find(transitions.cbegin(), transitions.cend(), HandoffEvent::NoteOff);
        const auto selectionCleared =
            std::find(transitions.cbegin(), transitions.cend(), HandoffEvent::SelectionCleared);
        const auto siblingSelected =
            std::find(transitions.cbegin(), transitions.cend(), HandoffEvent::SiblingSelected);
        QVERIFY(noteOn != transitions.cend());
        QVERIFY(noteOff != transitions.cend());
        QVERIFY(siblingSelected != transitions.cend());
        QVERIFY(noteOn < noteOff);
        QVERIFY(noteOff < siblingSelected);
        if (closePage) {
            QVERIFY(selectionCleared != transitions.cend());
            QVERIFY(noteOff < selectionCleared);
            QVERIFY(selectionCleared < siblingSelected);
        }
        QCOMPARE(workspace.selectedSongTab(), sibling);
        if (closePage)
            QCOMPARE(workspace.tabsInDisplayOrder(), (std::vector<SongTab *>{sibling}));
        QCOMPARE(window.m_selectedTab, sibling);
        QCOMPARE(window.m_appliedTimeline, sibling->timeline().get());
        QVERIFY(window.m_audio.songLoaded());

        int siblingNoteOn = 0;
        int siblingNoteOff = 0;
        QObject auditionMonitor;
        QObject::connect(
            &sibling->view(), &SongView::auditionNote, &auditionMonitor,
            [&](int, int, int velocity) { velocity > 0 ? ++siblingNoteOn : ++siblingNoteOff; });
        QTest::mouseRelease(sharedWindow, Qt::LeftButton, Qt::NoModifier, heldPoint);
        settle();
        QCOMPARE(sibling->document().smf().write(), siblingBefore);
        QCOMPARE(sibling->document().undoStack()->index(), siblingUndoBefore);
        QVERIFY(!sibling->document().isDirty());
        QVERIFY(!sharedWindow->mouseGrabberItem());
        QCOMPARE(siblingNoteOn, 0);
        QCOMPARE(siblingNoteOff, 0);
        auto *const siblingRoot = sibling->view().quickView()->rootObject();
        auto *const siblingGutter = siblingRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineRollGutterInput"));
        QVERIFY(siblingGutter);
        QTest::mouseClick(sharedWindow, Qt::LeftButton, Qt::NoModifier,
                          siblingGutter->mapToScene(siblingGutter->bounds().center()).toPoint());
        settle();
        QCOMPARE(siblingNoteOn, 1);
        QCOMPARE(siblingNoteOff, 1);
        QCOMPARE(sibling->document().smf().write(), siblingBefore);
        QCOMPARE(sibling->document().undoStack()->index(), siblingUndoBefore);
    }

  private:
    std::optional<Session> openSession() const
    {
        QString error;
        auto settings = std::make_unique<SettingsGuard>();
        std::unique_ptr<checks::ProjectFixture> fixture =
            checks::ProjectFixture::copyOf(m_projectRoot, error);
        if (!fixture)
            return std::nullopt;
        auto window = std::make_unique<MainWindow>();
        if (!window->m_audioOk)
            return std::nullopt;
        const std::optional<SongName> firstName = SongName::create(m_songA);
        const std::optional<SongName> secondName = SongName::create(m_songB);
        if (!firstName || !secondName)
            return std::nullopt;
        window->m_workspace->requestProjectOpenAt(fixture->root());
        if (!waitForProjectReady(*window->m_workspace))
            return std::nullopt;
        window->resize(960, 680);
        window->show();
        window->raise();
        window->activateWindow();
        if (checks::async_wait::waitUntil([] { return true; },
                                          [&window] { return window->isActiveWindow(); }, 2000,
                                          10) != checks::async_wait::Result::Ready)
            return std::nullopt;
        window->m_workspace->requestSongOpen(*firstName);
        SongTab *first = window->m_workspace->songTabFor(*firstName);
        window->m_workspace->requestSongOpen(*secondName, true);
        SongTab *active = window->m_workspace->selectedSongTab();
        if (!waitForTabReady(*window->m_workspace, first) ||
            !waitForTabReady(*window->m_workspace, active))
            return std::nullopt;
        SongView &view = active->view();
        SongDocument &document = active->document();
        const int track = twoNoteTrack(document);
        view.setDrawerActivePage(EditorDrawerPage::Velocity);
        view.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
        view.setDrawerSectionHeight(EditorDrawerPage::Velocity, 180);
        if (track >= 0) {
            const std::vector<DocNote> notes = document.notesForTrack(track);
            view.selectTrack(track);
            view.selectionModel().setNoteSelection({notes[0].noteId, notes[1].noteId});
        }
        settle();
        auto *const host = window->findChild<WorkspaceQuickHost *>();
        if (!host)
            return std::nullopt;
        host->focusEditor(Qt::OtherFocusReason);
        settle();
        return Session{std::move(settings), std::move(fixture), std::move(window), first, active};
    }

    static int twoNoteTrack(const SongDocument &document)
    {
        for (int track = 0; track < document.engineTrackCount(); ++track) {
            if (document.notesForTrack(track).size() >= 2)
                return track;
        }
        return -1;
    }

    QString m_projectRoot;
    QString m_songA;
    QString m_songB;
    QString m_screenshotPath;
};
} // namespace checks::host

int runHostIntegrationCheck(const QString &projectRoot, const QString &songA, const QString &songB,
                            const QString &screenshotPath, const QStringList &qtArguments)
{
    checks::host::HostIntegrationTest test(projectRoot, songA, songB, screenshotPath);
    QStringList arguments{QStringLiteral("host-integration")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "tst_hostintegration.moc"
