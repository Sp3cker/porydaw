#include "checks/support/support.h"
#include "mainwindowroutingfixture.h"
#include "ui/songview.h"

#include "checks/quickpopupguard.h"
#include "checks/trackheaders/trackheaderoracles.h"
#include "ui/mousehints/mousehints.h"
#include "ui/songview/quick/quickpopupsession.h"
#include "ui/songview/timelinebandlayout.h"
#include "ui/songview/trackheadermodel.h"
#include "ui/transportbar.h"

#include <QCloseEvent>
#include <QComboBox>
#include <QCursor>
#include <QDial>
#include <QQuickItem>
#include <QQuickWindow>

#include <QtTest>

namespace checks::mainwindowrouting {

class MainWindowRoutingLifecycleTest final : public QObject, private MainWindowRoutingFixture
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(MainWindowRoutingLifecycleTest)

  public:
    MainWindowRoutingLifecycleTest(QString projectRoot, QString songA, QString songB)
        : m_projectRoot(std::move(projectRoot))
        , m_songA(std::move(songA))
        , m_songB(std::move(songB))
    {}

  private slots:
    void closeAndReopenProjectsGlobalState()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        const EditorViewState state = completeSeed();
        session->b->view().setEditorViewState(state);
        const auto snapshot = porydawSnapshot(session->fixture->root());
        window.m_workspace->selectSongTab(session->b);
        const SongName name = session->b->name();
        window.m_workspace->requestCloseSelectedTab();
        QCOMPARE(window.m_workspace->openTabCount(), qsizetype{1});
        QVERIFY(window.m_workspace->songTabFor(name) == nullptr);
        QVERIFY(porydawSnapshot(session->fixture->root()) == snapshot);
        window.m_workspace->requestSongOpen(name, true);
        SongTab *reopened = window.m_workspace->selectedSongTab();
        QVERIFY(reopened);
        QVERIFY(waitForTabReady(*window.m_workspace, reopened));
        QCOMPARE(reopened->view().editorViewState(), state);
        QVERIFY(reopened->timeline());
        QVERIFY(hasCanonicalFreshViewState(reopened->view(), *reopened->timeline()));
        QVERIFY(porydawSnapshot(session->fixture->root()) == snapshot);
    }

    void readyReloadPreservesTransients()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        SongTab *reopened = session->b;
        SongView &view = reopened->view();
        const SongView::ViewState before = view.viewState();
        int alternateTrack = -1;
        for (int track = 0; track < 16; ++track) {
            if (reopened->timeline()->tracks[track].used && track != before.selectedTrack) {
                alternateTrack = track;
                break;
            }
        }
        QVERIFY(alternateTrack >= 0);
        SongView::ViewState requested;
        requested.valid = true;
        requested.pxPerBeat = before.pxPerBeat * 2.0;
        requested.keyHeight = before.keyHeight * 1.5;
        requested.scrollPx = (std::numeric_limits<double>::max)();
        requested.scrollY = (std::numeric_limits<double>::max)();
        requested.selectedTrack = alternateTrack;
        requested.editCursorTick =
            before.editCursorTick == 0 ? reopened->timeline()->ticksPerBeat : 0;
        requested.gridSelection = songview::GridSelection::musical(16);
        requested.gridTriplet = true;
        requested.eventList = true;
        view.applyViewState(requested);
        SongView::ViewState seeded = view.viewState();
        if (seeded.scrollPx == before.scrollPx || seeded.scrollY == before.scrollY) {
            if (seeded.scrollPx == before.scrollPx)
                requested.scrollPx = 0.0;
            if (seeded.scrollY == before.scrollY)
                requested.scrollY = 0.0;
            view.applyViewState(requested);
            seeded = view.viewState();
        }
        QVERIFY(seeded.scrollPx != before.scrollPx);
        QVERIFY(seeded.scrollY != before.scrollY);
        QCOMPARE(seeded.selectedTrack, alternateTrack);
        QCOMPARE(seeded.gridSelection, songview::GridSelection::musical(16));
        QVERIFY(seeded.gridTriplet);
        QVERIFY(seeded.eventList);
        QTabBar *tabBar = window.findChild<QTabBar *>();
        QVERIFY(tabBar);
        tabBar->setFocusPolicy(Qt::StrongFocus);
        tabBar->setFocus(Qt::OtherFocusReason);
        QCOMPARE(QApplication::focusWidget(), tabBar);
        QSignalSpy eventListTraffic(&view, &SongView::eventListVisibilityChanged);
        view.applyViewState(seeded);
        QCOMPARE(QApplication::focusWidget(), tabBar);
        eventListTraffic.clear();
        const MidiTimeline *beforeReload = reopened->timeline().get();
        const SongName name = reopened->name();
        const auto snapshot = porydawSnapshot(session->fixture->root());
        window.m_workspace->requestSongOpen(name);
        QVERIFY(!reopened->isReady());
        QCOMPARE(reopened->timeline().get(), beforeReload);
        bool stateDropped = false;
        const auto reload = checks::async_wait::waitUntil(
            [&window, reopened, &name] { return window.m_workspace->songTabFor(name) == reopened; },
            [&] {
                if (!reopened->isReady()) {
                    stateDropped =
                        stateDropped || !sameViewState(reopened->view().viewState(), seeded);
                    return false;
                }
                return reopened->timeline().get() != beforeReload;
            },
            30000, 1);
        QCOMPARE(reload, checks::async_wait::Result::Ready);
        QVERIFY(!stateDropped);
        QVERIFY(reopened->isReady());
        QVERIFY(reopened->timeline().get() != beforeReload);
        QVERIFY(sameViewState(reopened->view().viewState(), seeded));
        QCOMPARE(eventListTraffic.count(), 0);
        QCOMPARE(QApplication::focusWidget(), tabBar);
        QVERIFY(porydawSnapshot(session->fixture->root()) == snapshot);
    }

    void selectionDuringReloadFocusesWhenReady()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        WorkspaceUi &workspace = *session->window->m_workspace;
        SongTab *const a = session->a;
        SongTab *const b = session->b;
        QVERIFY(a->isReady());
        QVERIFY(b->isReady());
        QCOMPARE(workspace.selectedSongTab(), b);

        workspace.requestSongOpen(b->name());
        QVERIFY(!b->isReady());
        workspace.selectSongTab(a);
        QCOMPARE(workspace.selectedSongTab(), a);
        workspace.selectSongTab(b);
        QCOMPARE(workspace.selectedSongTab(), b);
        QVERIFY(!b->isReady());

        QVERIFY(waitForTabReady(workspace, b));
        QWidget *const focused = QApplication::focusWidget();
        QVERIFY(focused && (focused == b || b->isAncestorOf(focused)));
    }

    void freshBind()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        WorkspaceUi &workspace = *session->window->m_workspace;
        const SongName name = session->b->name();
        const auto &songs = workspace.projectState().snapshot.songs();
        const auto song = std::find_if(songs.cbegin(), songs.cend(), [&name](const SongInfo &info) {
            return info.label == name.value();
        });
        QVERIFY(song != songs.cend());
        QVERIFY(session->b->voicegroupId());
        SmfFile stage;
        QString error;
        QVERIFY(SmfFile::readFile(song->midPath, &stage, &error));
        LoadedVoiceGroup bank = {};
        SongTab probe(name);
        const EditorViewState global = completeSeed();
        probe.view().applyEditorViewState(global);
        QSignalSpy ready(&probe, &SongTab::readinessChanged);
        QVERIFY(!probe.isReady());
        probe.applyMidiStage(*song, std::move(stage),
                             workspace.projectState().snapshot.trackBudgetFor(*song));
        QVERIFY(!probe.isReady());
        QVERIFY(probe.timeline());
        QCOMPARE(probe.view().editorViewState(), global);
        QVERIFY(hasCanonicalFreshViewState(probe.view(), *probe.timeline()));
        QCOMPARE(ready.count(), 0);
        probe.applyBankView(LoadedBankView{
            .id = *session->b->voicegroupId(),
            .bank = borrowVoicegroupLease(&bank),
            .loadName = QString(),
            .slotViews = {},
        });
        QCOMPARE(ready.count(), 0);
        probe.applyVoicegroupBound(*session->b->voicegroupId());
        QVERIFY(probe.isReady());
        checks::support::bindEditActionsForTest(probe.view());
        QCOMPARE(ready.count(), 1);
    }

    void stagedReload()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        WorkspaceUi &workspace = *session->window->m_workspace;
        const SongName name = session->b->name();
        const auto &songs = workspace.projectState().snapshot.songs();
        const auto song = std::find_if(songs.cbegin(), songs.cend(), [&name](const SongInfo &info) {
            return info.label == name.value();
        });
        QVERIFY(song != songs.cend());
        QVERIFY(session->b->voicegroupId());
        QString error;
        SmfFile initial;
        SmfFile replacement;
        QVERIFY(SmfFile::readFile(song->midPath, &initial, &error));
        QVERIFY(SmfFile::readFile(song->midPath, &replacement, &error));
        const VoicegroupId identity = *session->b->voicegroupId();
        LoadedVoiceGroup bank = {};
        SongTab probe(name);
        const int budget = workspace.projectState().snapshot.trackBudgetFor(*song);
        probe.applyMidiStage(*song, std::move(initial), budget);
        probe.applyBankView(LoadedBankView{
            .id = identity,
            .bank = borrowVoicegroupLease(&bank),
            .loadName = QString(),
            .slotViews = {},
        });
        probe.applyVoicegroupBound(identity);
        checks::support::bindEditActionsForTest(probe.view());
        QVERIFY(probe.isReady());
        const MidiTimeline *bound = probe.timeline().get();
        SongView::ViewState state = probe.view().viewState();
        state.valid = true;
        state.pxPerBeat *= 2.0;
        state.keyHeight *= 1.5;
        state.editCursorTick = probe.timeline()->ticksPerBeat * 4;
        state.gridSelection = songview::GridSelection::musical(16);
        state.gridTriplet = true;
        probe.view().applyViewState(state);
        const SongView::ViewState retained = probe.view().viewState();
        QSignalSpy ready(&probe, &SongTab::readinessChanged);
        probe.beginMidiReload();
        QVERIFY(!probe.isReady());
        QCOMPARE(probe.timeline().get(), bound);
        QVERIFY(sameViewState(probe.view().viewState(), retained));
        QCOMPARE(ready.count(), 1);
        probe.applyMidiStage(*song, std::move(replacement), budget);
        QVERIFY(!probe.isReady());
        QVERIFY(probe.timeline().get() != bound);
        QVERIFY(sameViewState(probe.view().viewState(), retained));
        QCOMPARE(ready.count(), 1);
        probe.applyVoicegroupBound(identity);
        QVERIFY(probe.isReady());
        QVERIFY(sameViewState(probe.view().viewState(), retained));
        QCOMPARE(ready.count(), 2);
    }

    void bankRebind()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        WorkspaceUi &workspace = *session->window->m_workspace;
        const SongName name = session->b->name();
        const auto &songs = workspace.projectState().snapshot.songs();
        const auto song = std::find_if(songs.cbegin(), songs.cend(), [&name](const SongInfo &info) {
            return info.label == name.value();
        });
        QVERIFY(song != songs.cend());
        QVERIFY(session->b->voicegroupId());
        SmfFile stage;
        QString error;
        QVERIFY(SmfFile::readFile(song->midPath, &stage, &error));
        const VoicegroupId identity = *session->b->voicegroupId();
        LoadedVoiceGroup initial;
        LoadedVoiceGroup replacement;
        SongTab probe(name);
        probe.applyMidiStage(*song, std::move(stage),
                             workspace.projectState().snapshot.trackBudgetFor(*song));
        probe.applyBankView(LoadedBankView{
            .id = identity,
            .bank = borrowVoicegroupLease(&initial),
            .loadName = QString(),
            .slotViews = {},
        });
        probe.applyVoicegroupBound(identity);
        checks::support::bindEditActionsForTest(probe.view());
        QVERIFY(probe.isReady());
        const MidiTimeline *timeline = probe.timeline().get();
        const SongView::ViewState state = probe.view().viewState();
        QSignalSpy ready(&probe, &SongTab::readinessChanged);
        probe.applyBankView(LoadedBankView{
            .id = identity,
            .bank = borrowVoicegroupLease(&replacement),
            .loadName = QString(),
            .slotViews = {},
        });
        probe.applyVoicegroupBound(identity);
        QVERIFY(probe.isReady());
        QCOMPARE(probe.timeline().get(), timeline);
        QCOMPARE(probe.voicegroupLease().get(), &replacement);
        QVERIFY(sameViewState(probe.view().viewState(), state));
        QCOMPARE(ready.count(), 0);
    }

    void failedOpenPreservesLiveTab()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        WorkspaceUi &workspace = *window.m_workspace;
        const EditorViewState state = completeSeed();
        session->b->view().setEditorViewState(state);
        const auto snapshot = porydawSnapshot(session->fixture->root());
        SongTab *old = session->b;
        const qsizetype count = workspace.openTabCount();
        const QString label = old->document().label();
        QVERIFY(!old->document().isDirty());
        workspace.requestSongOpen(old->name());
        workspace.requestProjectOpenAt(session->fixture->root() +
                                       QStringLiteral("/missing-project"));
        const auto failed = [&workspace] {
            if (QPointer<QMessageBox> box =
                    qobject_cast<QMessageBox *>(QApplication::activeModalWidget());
                box && !box->property("dismissalQueued").toBool()) {
                box->setProperty("dismissalQueued", true);
                QTimer::singleShot(0, box, [box] { box->reject(); });
            }
            return workspace.projectState().state == ProjectOpenState::Failed;
        };
        QCOMPARE(checks::async_wait::waitUntil([] { return true; }, failed, 30000, 1),
                 checks::async_wait::Result::Ready);
        QCOMPARE(workspace.selectedSongTab(), old);
        QCOMPARE(workspace.openTabCount(), count);
        QCOMPARE(workspace.projectState().snapshot.root(), session->fixture->root());
        QVERIFY(porydawSnapshot(session->fixture->root()) == snapshot);
        QVERIFY(waitForTabReady(workspace, old));
        QCOMPARE(old->document().label(), label);
    }

    void projectSwitchAndQuitPreserveState()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        WorkspaceUi &workspace = *window.m_workspace;
        const EditorViewState state = completeSeed();
        session->b->view().setEditorViewState(state);
        const auto snapshot = porydawSnapshot(session->fixture->root());
        const QByteArray midiA = session->a->document().smf().write();
        const QByteArray midiB = session->b->document().smf().write();
        const int undoA = session->a->document().undoStack()->count();
        const int undoB = session->b->document().undoStack()->count();
        workspace.requestProjectOpenAt(session->fixture->root());
        QVERIFY(waitForProjectReady(workspace));
        QCOMPARE(workspace.openTabCount(), qsizetype{0});
        QVERIFY(porydawSnapshot(session->fixture->root()) == snapshot);
        QCOMPARE(loadEditorViewState(QSettings{}), state);
        const auto aName = SongName::create(m_songA);
        const auto bName = SongName::create(m_songB);
        QVERIFY(aName);
        QVERIFY(bName);
        workspace.requestSongOpen(*aName);
        SongTab *reopenedA = workspace.selectedSongTab();
        QVERIFY(waitForTabReady(workspace, reopenedA));
        QCOMPARE(reopenedA->view().editorViewState(), state);
        QCOMPARE(reopenedA->document().smf().write(), midiA);
        QCOMPARE(reopenedA->document().undoStack()->count(), undoA);
        workspace.requestSongOpen(*bName, true);
        SongTab *reopenedB = workspace.selectedSongTab();
        QVERIFY(waitForTabReady(workspace, reopenedB));
        QCOMPARE(reopenedB->view().editorViewState(), state);
        QCOMPARE(reopenedB->document().smf().write(), midiB);
        QCOMPARE(reopenedB->document().undoStack()->count(), undoB);
        QCloseEvent close;
        QApplication::sendEvent(&window, &close);
        QVERIFY(close.isAccepted());
        QVERIFY(window.m_closeAccepted);
        window.close();
        QCOMPARE(checks::async_wait::waitUntil(
                     [] { return true; }, [&window] { return window.m_closeAccepted; }, 30000, 1),
                 checks::async_wait::Result::Ready);
        QVERIFY(porydawSnapshot(session->fixture->root()) == snapshot);
        QCOMPARE(loadEditorViewState(QSettings{}), state);
    }

    void mouseHintWidgetDragSettlesOnRelease()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        ui::MouseHints &hints = mouseHints();
        TransportBar *const transport = window.m_workspace->transportBar();
        QVERIFY(transport);
        QDial *const dial = transport->findChild<QDial *>();
        QComboBox *const combo = transport->findChild<QComboBox *>();
        QVERIFY(dial && combo);
        // The packed transport toolbar overflows the fixture's 960px window
        // and hides the dial in the extension; widening relayouts it into
        // view. The session owns this window, so no restore is needed.
        window.resize(1400, 640);
        QTRY_VERIFY(dial->isVisibleTo(&window));

        // QCursor::setPos injects a real spontaneous move through the
        // windowing system and keeps QCursor::pos() honest for the observer's
        // scope reconcile; QTest::mouseMove delivers the event but leaves the
        // reported cursor position stale offscreen. Crossing the combo first
        // is the same path a pointer sweeping the transport bar takes.
        QWindow *const dialWindow = window.windowHandle();
        QVERIFY(dialWindow);
        const auto windowPoint = [dialWindow](QWidget *widget, const QPoint &local) {
            return dialWindow->mapFromGlobal(widget->mapToGlobal(local));
        };
        const int originalValue = dial->value();
        QCursor::setPos(combo->mapToGlobal(combo->rect().center()));
        QCursor::setPos(dial->mapToGlobal(dial->rect().center()));
        // underMouse proves Qt's Enter reached the dial; without it the
        // claim assert below cannot distinguish a delivery miss (covered or
        // overflowed widget) from an observer drop.
        QTRY_VERIFY(dial->underMouse());
        QTRY_VERIFY(hints.currentSource() == dial);
        const QString dialProfile = hints.currentText();
        QVERIFY(!dialProfile.isEmpty());

        // A real C++ drag on the output dial keeps the dial's profile for the
        // whole grab, and releasing over the combo settles on the actual leaf.
        // The value change proves the press reached the dial. The cursor is
        // parked on the combo before release so the post-release reconcile
        // resolves the leaf under it.
        dial->setValue(50);
        QTest::mousePress(dialWindow, Qt::LeftButton, Qt::NoModifier,
                          windowPoint(dial, dial->rect().center()));
        QTest::mouseMove(dialWindow, windowPoint(dial, dial->rect().center() + QPoint(0, -11)));
        QVERIFY(dial->value() < 50);
        QVERIFY(hints.currentSource() == dial && hints.currentText() == dialProfile);
        QCursor::setPos(combo->mapToGlobal(combo->rect().center()));
        QTest::mouseRelease(dialWindow, Qt::LeftButton, Qt::NoModifier,
                            windowPoint(combo, combo->rect().center()));
        QTRY_VERIFY(hints.currentSource() == combo && hints.currentText().isEmpty());
        dial->setValue(originalValue);
    }

    void mouseHintQuickDragSettlesOnRelease()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        SongView &view = session->b->view();
        ui::MouseHints &hints = mouseHints();
        QQuickWindow *const canvas = quickCanvas(view);
        QVERIFY(canvas);
        QQuickItem *const plot = quickItem(view, QLatin1String("timelineRollInput"));
        QVERIFY(plot);

        // A scrollable Quick scrollbar: the thumb drag is the ordinary QML
        // gesture whose release position settles the no-hint group.
        QQuickItem *scrollbar = nullptr;
        for (const char *name : {"timelineRollScrollBar", "timelineHorizontalScrollBar",
                                 "timelineTrackHeaderScrollBar"}) {
            QQuickItem *const candidate = quickItem(view, QLatin1String(name));
            if (candidate && candidate->isVisible() && candidate->property("scrollable").toBool() &&
                candidate->property("thumbTravel").toReal() > 0) {
                scrollbar = candidate;
                break;
            }
        }
        QVERIFY2(scrollbar, "no scrollable Quick scrollbar is visible in the fixture");

        const bool vertical = scrollbar->property("orientation").toInt() == int(Qt::Vertical);
        const qreal thumbPos = scrollbar->property("thumbPos").toReal();
        const qreal thumbLength = scrollbar->property("thumbLength").toReal();
        QVERIFY(thumbLength > 0);
        const QPointF thumbLocal =
            vertical ? QPointF(scrollbar->width() / 2.0, thumbPos + thumbLength / 2.0)
                     : QPointF(thumbPos + thumbLength / 2.0, scrollbar->height() / 2.0);
        const QPoint thumbScene = scrollbar->mapToScene(thumbLocal).toPoint();
        const QPoint plotScene = plot->mapToScene(plot->boundingRect().center()).toPoint();

        hoverAt(*canvas, thumbScene);
        QTRY_VERIFY(hints.currentSource() == scrollbar && hints.currentText().isEmpty());

        // The drag retains the originating empty claim; releasing outside the
        // scrollbar footprint settles on the covered plot's real profile.
        QTest::mousePress(canvas, Qt::LeftButton, Qt::NoModifier, thumbScene);
        QTest::mouseMove(canvas, plotScene);
        QVERIFY(hints.currentSource() == scrollbar && hints.currentText().isEmpty());
        QTest::mouseRelease(canvas, Qt::LeftButton, Qt::NoModifier, plotScene);
        QTRY_VERIFY(hints.currentSource() == plot && !hints.currentText().isEmpty());
    }

    void mouseHintHeaderDragSettlesOnRelease()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        SongView &view = session->b->view();
        ui::MouseHints &hints = mouseHints();
        QQuickWindow *const canvas = quickCanvas(view);
        QVERIFY(canvas);
        QQuickItem *const headers = quickItem(view, QLatin1String("timelineTrackHeadersInput"));
        QVERIFY(headers);
        songview::TrackHeaderModel *const model = trackHeaders(view);
        QVERIFY(model);
        QVERIFY(model->rowCount() >= 2);

        const std::optional<QPointF> title = headerRowPoint(
            *headers, *model, 0,
            model->data(model->index(0, 0), songview::TrackHeaderModel::TitleRectRole).toRectF());
        QVERIFY(title.has_value());
        const uint64_t commitRevision = session->b->document().revision();

        hoverAt(*canvas, headers->mapToScene(*title).toPoint());
        QTRY_VERIFY(hints.currentSource() == headers);
        const QString rowProfile = hints.currentText();
        QVERIFY(!rowProfile.isEmpty());

        // The header reorder drag keeps the row profile through the grab.
        // Delivery targets the input item directly — the same mechanism the
        // trackheader reorder checks use, which drive the interaction's
        // pointer handlers. The composed-window QTest path ends the grab
        // with mouseUngrabEvent, whose settle consults QCursor::pos(); that
        // stays stale offscreen under QTest::mouseMove, so the claim's
        // survival would hinge on Qt's post-release hover synthesis rather
        // than the product path. Selecting track 1 first makes the row-0
        // press's primary-track transition observable proof the press
        // reached the real handler.
        view.selectTrack(1);
        checks::events::sendMouse(*headers, QEvent::MouseButtonPress, *title, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        QCOMPARE(view.selectionModel().primaryTrack(), 0);
        checks::events::sendMouse(*headers, QEvent::MouseMove,
                                  *title + QPointF(0, model->rowHeight()), Qt::NoButton,
                                  Qt::LeftButton, Qt::NoModifier);
        QVERIFY(model->reorderIndicatorVisible());
        QVERIFY(hints.currentSource() == headers && hints.currentText() == rowProfile);

        // Releasing below the last track row drops into the end slot — the
        // proven commit coordinate the trackheader reorder checks use.
        int trackRows = 0;
        for (int row = 0; row < model->rowCount(); ++row) {
            if (!model->data(model->index(row, 0), songview::TrackHeaderModel::IsAddTrackRole)
                     .toBool())
                ++trackRows;
        }
        const QPointF dropPoint{title->x(), qreal(trackRows) * model->rowHeight()};
        checks::events::sendMouse(*headers, QEvent::MouseMove, dropPoint, Qt::NoButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*headers, QEvent::MouseButtonRelease, dropPoint, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        QTRY_VERIFY(session->b->document().revision() > commitRevision);
        QTRY_VERIFY(hints.currentSource() == headers && !hints.currentText().isEmpty());
    }

    void mouseHintSurvivesFocusChange()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        SongView &view = session->b->view();
        ui::MouseHints &hints = mouseHints();
        QQuickWindow *const canvas = quickCanvas(view);
        QVERIFY(canvas);
        QQuickItem *const plot = quickItem(view, QLatin1String("timelineRollInput"));
        QVERIFY(plot);

        hoverAt(*canvas, plot->mapToScene(plot->boundingRect().center()).toPoint());
        QTRY_VERIFY(hints.currentSource() == plot);
        const QString profile = hints.currentText();
        QVERIFY(!profile.isEmpty());

        // Keyboard focus changes under a stationary pointer leave the
        // displayed profile alone.
        QVERIFY(view.focusTimelineBand(songview::TimelineBand::TrackHeaders, Qt::OtherFocusReason));
        QTRY_VERIFY(view.focusedTimelineBand() == songview::TimelineBand::TrackHeaders);
        QVERIFY(hints.currentSource() == plot);
        QCOMPARE(hints.currentText(), profile);
        QTest::keyClick(canvas, Qt::Key_Tab);
        QCoreApplication::processEvents();
        QVERIFY(hints.currentSource() == plot);
        QCOMPARE(hints.currentText(), profile);
    }

    void mouseHintDiesWithItsTab()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        ui::MouseHints &hints = mouseHints();
        SongView &viewB = session->b->view();
        QQuickWindow *const canvasB = quickCanvas(viewB);
        QVERIFY(canvasB);
        QQuickItem *const plotB = quickItem(viewB, QLatin1String("timelineRollInput"));
        QVERIFY(plotB);

        hoverAt(*canvasB, plotB->mapToScene(plotB->boundingRect().center()).toPoint());
        QTRY_VERIFY(hints.currentSource() == plotB);
        QVERIFY(!hints.currentText().isEmpty());

        // Switching to another real tab hides B's canvas; its hint dies with
        // the hidden window's hover membership.
        window.m_workspace->selectSongTab(session->a);
        QTRY_VERIFY(hints.currentSource() != plotB);

        // Hovering A's canvas claims its own source.
        SongView &viewA = session->a->view();
        QQuickWindow *const canvasA = quickCanvas(viewA);
        QVERIFY(canvasA);
        QQuickItem *const plotA = quickItem(viewA, QLatin1String("timelineRollInput"));
        QVERIFY(plotA);
        hoverAt(*canvasA, plotA->mapToScene(plotA->boundingRect().center()).toPoint());
        QTRY_VERIFY(hints.currentSource() == plotA);
        QVERIFY(!hints.currentText().isEmpty());

        // Closing the hovered tab destroys the source; the service releases
        // it rather than keeping a dangling owner. The reshown tab may
        // legitimately reclaim the hint under the stationary cursor.
        window.m_workspace->requestCloseSelectedTab();
        QTRY_VERIFY(hints.currentSource() != plotA);
    }

  private:
    QString m_projectRoot;
    QString m_songA;
    QString m_songB;
};

int runMainWindowRoutingLifecycleCheck(const QString &projectRoot, const QString &songA,
                                       const QString &songB, const QStringList &qtArguments)
{
    MainWindowRoutingLifecycleTest test(projectRoot, songA, songB);
    QStringList arguments{QStringLiteral("mainwindow-routing-lifecycle")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

} // namespace checks::mainwindowrouting

#include "tst_mainwindowrouting_lifecycle.moc"
