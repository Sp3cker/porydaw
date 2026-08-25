#include <QApplication>
#include <QComboBox>
#include <QDial>
#include <QEventLoop>
#include <QFile>
#include <QImage>
#include <QKeyEvent>
#include <QLabel>
#include <QLineEdit>
#include <QPointer>
#include <QSettings>
#include <QSizePolicy>
#include <QSpinBox>
#include <QTimer>
#include <QToolBar>
#include <QToolButton>
#include <QUndoGroup>
#include <QUndoStack>
#include <QtMath>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <memory>

#include "checks/support/eventsynth.h"
#include "mainwindow.h"
#include "porydaw_scale.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/theme/themeruntime.h"
#include "ui/transportbar.h"
#include "ui/workspaceui.h"

// --tabcheck <projectRoot> <songA> <songB>: multi-tab check. Two songs open
// in tabs with fully separate documents and undo stacks; switching tabs
// stops playback and rebinds the audio engine to the active tab's timeline
// and voicegroup; closing and replacing tabs behave; the open-tab set
// round-trips through QSettings (the second half, in runTabCheck's caller,
// restores it into a fresh window). A clean background tab whose voicegroup
// file changed on disk reloads it on activation. QSettings is redirected
// into a temp dir; view sidecars are written into the project on tab
// close — run against a scratch copy.

bool MainWindow::runTabCheck(const QString &projectRoot, const QString &songA, const QString &songB)
{
    // m_persistSession stays true (the caller redirected QSettings) so the
    // tab persistence written for restoreSession is exercised for real.
    if (!m_audioOk) {
        std::fprintf(stderr, "tabcheck: no audio device available\n");
        return false;
    }
    const auto openProject = [this](const QString &root) {
        struct OpenState {
            bool completed = false;
            bool succeeded = false;
        };
        const auto state = std::make_shared<OpenState>();
        QEventLoop openLoop;
        QTimer poll;
        QTimer timeout;
        QObject::connect(&poll, &QTimer::timeout, &openLoop, [&] {
            if (state->completed)
                openLoop.quit();
        });
        QObject::connect(&timeout, &QTimer::timeout, &openLoop, &QEventLoop::quit);
        timeout.setSingleShot(true);
        openProjectDir(root, /*interactive=*/false, [state](bool succeeded) {
            state->succeeded = succeeded;
            state->completed = true;
        });
        if (!state->completed) {
            poll.start(1);
            timeout.start(30000);
            openLoop.exec();
            poll.stop();
            timeout.stop();
        }
        return state->completed && state->succeeded;
    };
    if (!openProject(projectRoot)) {
        std::fprintf(stderr, "tabcheck: project failed to open\n");
        return false;
    }

    int failures = 0;
    const auto check = [&failures](bool ok, const char *what) {
        if (!ok) {
            std::fprintf(stderr, "tabcheck: FAIL: %s\n", what);
            failures++;
        }
        return ok;
    };
    QEventLoop loop;
    const auto wait = [&loop](int ms) {
        QTimer::singleShot(ms, &loop, &QEventLoop::quit);
        loop.exec();
    };
    const auto waitForLoaded = [this, &failures](SongSession *session, const char *what) {
        const auto isLive = [this](SongSession *candidate) {
            return candidate &&
                   std::any_of(m_sessions.cbegin(), m_sessions.cend(),
                               [candidate](const auto &owned) { return owned.get() == candidate; });
        };
        if (!isLive(session)) {
            std::fprintf(stderr, "tabcheck: FAIL: %s session disappeared before loading\n", what);
            failures++;
            return false;
        }

        constexpr int loadTimeoutMs = 15000;
        QEventLoop loadLoop;
        QTimer poll;
        QTimer deadline;
        bool timedOut = false;
        const auto observe = [&] {
            if (!isLive(session) || session->isInteractive())
                loadLoop.quit();
        };
        poll.setInterval(1);
        deadline.setSingleShot(true);
        QObject::connect(&poll, &QTimer::timeout, &loadLoop, observe);
        QObject::connect(&deadline, &QTimer::timeout, &loadLoop, [&] {
            timedOut = true;
            loadLoop.quit();
        });
        observe();
        if (isLive(session) && !session->isInteractive()) {
            poll.start();
            deadline.start(loadTimeoutMs);
            loadLoop.exec();
        }
        poll.stop();
        deadline.stop();

        if (!isLive(session)) {
            std::fprintf(stderr, "tabcheck: FAIL: %s session was destroyed while loading\n", what);
            failures++;
            return false;
        }
        if (!session->isInteractive()) {
            if (timedOut)
                std::fprintf(stderr, "tabcheck: FAIL: timed out waiting for %s (%d ms)\n", what,
                             loadTimeoutMs);
            else
                std::fprintf(stderr, "tabcheck: FAIL: %s did not become ready\n", what);
            failures++;
            return false;
        }
        return true;
    };
    const auto waitForVoicegroupRefresh = [this, &failures](
                                              SongSession *session, const LoadedVoiceGroup *before,
                                              const QDateTime &beforeTime, const char *what) {
        const auto isLive = [this, session] {
            return session &&
                   std::any_of(m_sessions.cbegin(), m_sessions.cend(),
                               [session](const auto &owned) { return owned.get() == session; });
        };
        if (!isLive()) {
            std::fprintf(stderr, "tabcheck: FAIL: %s session disappeared before refresh\n", what);
            failures++;
            return false;
        }
        constexpr int refreshTimeoutMs = 15000;
        QEventLoop refreshLoop;
        QTimer poll;
        QTimer deadline;
        bool timedOut = false;
        const auto observe = [&] {
            const bool changed = session->voicegroup != before || session->vgFileTime != beforeTime;
            if (!isLive() ||
                (session->pendingVgProbeRequest == 0 && session->pendingVgRequest == 0 && changed))
                refreshLoop.quit();
        };
        poll.setInterval(1);
        deadline.setSingleShot(true);
        QObject::connect(&poll, &QTimer::timeout, &refreshLoop, observe);
        QObject::connect(&deadline, &QTimer::timeout, &refreshLoop, [&] {
            timedOut = true;
            refreshLoop.quit();
        });
        observe();
        const bool changedBefore =
            session->voicegroup != before || session->vgFileTime != beforeTime;
        if (isLive() && !(session->pendingVgProbeRequest == 0 && session->pendingVgRequest == 0 &&
                          changedBefore)) {
            poll.start();
            deadline.start(refreshTimeoutMs);
            refreshLoop.exec();
        }
        poll.stop();
        deadline.stop();
        if (!isLive()) {
            std::fprintf(stderr, "tabcheck: FAIL: %s session was destroyed while refreshing\n",
                         what);
            failures++;
            return false;
        }
        const bool changed = session->voicegroup != before || session->vgFileTime != beforeTime;
        if (!changed || session->pendingVgProbeRequest != 0 || session->pendingVgRequest != 0) {
            if (timedOut)
                std::fprintf(stderr, "tabcheck: FAIL: timed out waiting for %s (%d ms)\n", what,
                             refreshTimeoutMs);
            else
                std::fprintf(stderr, "tabcheck: FAIL: %s did not complete\n", what);
            failures++;
            return false;
        }
        return true;
    };
    const auto waitForSave = [this, &failures](SongSession *session, const char *what) {
        const auto isLive = [this, session] {
            return session &&
                   std::any_of(m_sessions.cbegin(), m_sessions.cend(),
                               [session](const auto &owned) { return owned.get() == session; });
        };
        if (!isLive()) {
            std::fprintf(stderr, "tabcheck: FAIL: %s session disappeared before save\n", what);
            failures++;
            return false;
        }
        struct SaveState {
            bool completed = false;
            bool succeeded = false;
        };
        const auto state = std::make_shared<SaveState>();
        QEventLoop saveLoop;
        QPointer<QEventLoop> loopGuard = &saveLoop;
        QTimer timeout;
        timeout.setSingleShot(true);
        QObject::connect(&timeout, &QTimer::timeout, &saveLoop, &QEventLoop::quit);
        saveSession(*session, [state, loopGuard](bool succeeded) mutable {
            state->completed = true;
            state->succeeded = succeeded;
            if (loopGuard)
                loopGuard->quit();
        });
        if (!state->completed) {
            timeout.start(30000);
            saveLoop.exec();
            timeout.stop();
        }
        if (!state->completed || !state->succeeded) {
            std::fprintf(stderr, "tabcheck: FAIL: %s did not complete successfully\n", what);
            failures++;
            return false;
        }
        return true;
    };

    auto *rootCombo = findChild<QComboBox *>(QStringLiteral("transportScaleRoot"));
    auto *scaleCombo = findChild<QComboBox *>(QStringLiteral("transportScaleType"));
    auto *highlightButton = findChild<QToolButton *>(QStringLiteral("transportScaleHighlight"));
    auto *foldButton = findChild<QToolButton *>(QStringLiteral("transportScaleFold"));
    const bool haveScaleControls = check(rootCombo && scaleCombo && highlightButton && foldButton,
                                         "transport scale controls not found");
    if (haveScaleControls) {
        check(!rootCombo->isEnabled() && !scaleCombo->isEnabled() &&
                  !highlightButton->isEnabled() && !foldButton->isEnabled(),
              "scale controls are enabled without a tab");
        check(rootCombo->focusPolicy() == Qt::NoFocus && scaleCombo->focusPolicy() == Qt::NoFocus &&
                  highlightButton->focusPolicy() == Qt::NoFocus &&
                  foldButton->focusPolicy() == Qt::NoFocus,
              "transport scale controls accept keyboard focus");
    }

    // 1. First song presents an empty, active tab before either async result.
    loadSongByLabel(songA);
    SongSession *tabA = m_active;
    if (!tabA) {
        std::fprintf(stderr, "tabcheck: song '%s' did not create a session\n",
                     qUtf8Printable(songA));
        return false;
    }
    check(m_workspace->openSessionCount() == 1, "first song did not open exactly one tab");
    check(m_active == tabA && m_workspace->isSessionAttached(*tabA) &&
              !m_workspace->viewFor(*tabA).isHidden(),
          "first song did not present an active visible tab immediately");
    check(!tabA->midiBound && !tabA->vgBound && !tabA->sidecarBound,
          "first song bound data before loadSongByLabel returned");
    if (!waitForLoaded(tabA, "first song"))
        return false;
    check(tabA->doc.label() == songA, "first song did not finish loading");
    check(m_audio.timeline() == tabA->timeline.get() && m_audio.voicegroup() == tabA->voicegroup,
          "engine is not borrowing the first tab's data");
    check(m_uiTimer->interval() == 500, "paused UI cadence is not 500 ms");

    // 2. Second song in a new tab becomes the active one.
    loadSongByLabel(songB, /*newTab=*/true);
    SongSession *tabB = m_active;
    if (!tabB || tabB == tabA) {
        std::fprintf(stderr, "tabcheck: song '%s' did not open in a new tab\n",
                     qUtf8Printable(songB));
        return false;
    }
    check(m_workspace->openSessionCount() == 2, "second song did not open a second tab");
    check(m_active == tabB && m_workspace->isSessionAttached(*tabB) &&
              !m_workspace->viewFor(*tabB).isHidden(),
          "second song did not present its active tab immediately");
    check(!tabB->midiBound && !tabB->vgBound && !tabB->sidecarBound,
          "second song bound data before loadSongByLabel returned");
    if (!waitForLoaded(tabB, "second song"))
        return false;
    check(tabB->doc.label() == songB, "second song did not finish loading");
    check(m_audio.timeline() == tabB->timeline.get(), "engine did not rebind to the new tab");
    check(m_undoGroup->activeStack() == tabB->doc.undoStack(),
          "undo group is not on the new tab's stack");
    check(sessionForLabel(songA) == tabA && !tabA->doc.isDirty(),
          "first tab did not survive the second one opening");

    if (haveScaleControls) {
        check(!m_workspace->viewFor(*tabA).scaleHighlight() &&
                  !m_workspace->viewFor(*tabA).scaleFold() &&
                  m_workspace->viewFor(*tabA).scaleRoot() == 0 &&
                  m_workspace->viewFor(*tabA).scaleId() == porydaw_scale::ScaleId::major,
              "first tab does not start at C Major with both scale features disabled");
        check(!m_workspace->viewFor(*tabB).scaleHighlight() &&
                  !m_workspace->viewFor(*tabB).scaleFold() &&
                  m_workspace->viewFor(*tabB).scaleRoot() == 0 &&
                  m_workspace->viewFor(*tabB).scaleId() == porydaw_scale::ScaleId::major &&
                  rootCombo->currentData().toInt() == 0 &&
                  scaleCombo->currentData().toInt() ==
                      static_cast<int>(porydaw_scale::ScaleId::major) &&
                  !highlightButton->isChecked() && !foldButton->isChecked(),
              "second tab or its controls do not start with both scale features disabled");
    }

    // 3. Separate documents and undo stacks: an edit in one tab dirties
    // only that tab.
    m_workspace->activateSession(tabA);
    check(m_active == tabA && m_audio.timeline() == tabA->timeline.get(),
          "switching tabs did not rebind the engine to the first tab");
    check(m_undoGroup->activeStack() == tabA->doc.undoStack(),
          "undo group did not follow the tab switch");
    if (tabA->doc.engineTrackCount() == 0) {
        std::fprintf(stderr, "tabcheck: song '%s' has no tracks\n", qUtf8Printable(songA));
        return false;
    }
    uint64_t base = 0;
    for (const SmfTrack &tr : tabA->doc.smf().tracks)
        base = std::max(base, tr.endTick);
    tabA->doc.addNote(0, base + 96, 72, 24, 93);
    check(tabA->doc.isDirty() && !tabB->doc.isDirty(), "edit in one tab did not stay in that tab");
    check(m_workspace->sessionTitle(*tabA).endsWith(QLatin1Char('*')),
          "dirty tab title has no asterisk");
    check(!m_workspace->sessionTitle(*tabB).endsWith(QLatin1Char('*')),
          "clean tab title grew an asterisk");

    // 4. Switching tabs stops playback in the tab being left.
    m_audio.play();
    wait(200);
    check(m_audio.transport() == Transport::Playing, "playback did not start");
    synchronizePlayhead();
    check(m_uiTimer->interval() == 100, "playback UI cadence is not 100 ms");
    m_workspace->activateSession(tabB);
    check(m_audio.transport() == Transport::Stopped, "switching tabs did not stop playback");
    check(m_uiTimer->interval() == 500, "stopped UI cadence is not 500 ms");
    check(m_audio.timeline() == tabB->timeline.get(),
          "engine timeline is not the newly active tab's");

    // 5. The dirty edit survives the round trip; each stack undoes its own.
    m_workspace->activateSession(tabA);
    check(tabA->doc.isDirty(), "first tab's edit vanished across the switch");
    m_undoGroup->activeStack()->undo();
    check(!tabA->doc.isDirty() && !tabB->doc.isDirty(),
          "undo through the group did not clean the active tab");

    // 5b. The transport master-volume spinbox mirrors the active tab's cfg,
    // follows tab switches, and drives the same undoable cfg edit as Song
    // Settings (so undo reverts both the cfg and the spinbox).
    auto *transport = findChild<QToolBar *>(QStringLiteral("transportToolbar"));
    auto *transportSpacer = findChild<QWidget *>(QStringLiteral("transportVolumeSpacer"));
    auto *volCaption = findChild<QLabel *>(QStringLiteral("transportMasterVolumeCaption"));
    auto *volSpin = findChild<QSpinBox *>(QStringLiteral("transportMasterVolume"));
    auto *outputCaption = findChild<QLabel *>(QStringLiteral("transportOutputVolumeCaption"));
    auto *outputDial = findChild<QDial *>(QStringLiteral("transportOutputVolume"));
    TransportBar defaultTransport;
    auto *defaultOutputDial =
        defaultTransport.findChild<QDial *>(QStringLiteral("transportOutputVolume"));
    check(defaultOutputDial && defaultOutputDial->value() == 100,
          "application-output dial does not default to 100 percent");
    if (defaultOutputDial) {
        QImage outputDialImage(defaultOutputDial->size(), QImage::Format_ARGB32_Premultiplied);
        outputDialImage.fill(Qt::transparent);
        defaultOutputDial->render(&outputDialImage);
        const int outputTickInset = layout::space(layout::Space::One);
        const QRect outputDialRect = defaultOutputDial->rect().adjusted(
            outputTickInset, outputTickInset, -outputTickInset, -outputTickInset);
        const int outputDialCenterX = outputDialRect.left() + outputDialRect.width() / 2;
        const int outputDialCenterY = outputDialRect.top() + outputDialRect.height() / 2;
        const QPointF outputDialCenter(outputDialCenterX + 0.5, outputDialCenterY + 0.5);
        const qreal outputDialHorizontalRadius = std::min(
            outputDialCenter.x(), qreal(defaultOutputDial->width() - 1) - outputDialCenter.x());
        const qreal outputDialVerticalRadius = std::min(
            outputDialCenter.y(), qreal(defaultOutputDial->height() - 1) - outputDialCenter.y());
        const qreal outputDialOuterRadius =
            std::min(outputDialHorizontalRadius, outputDialVerticalRadius) - layout::singlePixel();
        const qreal outputTickRadius =
            outputDialOuterRadius - qreal(layout::space(layout::Space::Half)) / 2.0;
        const QColor outputTickColor = themes::color(themes::Role::toolbar_outline);
        const auto hasOutputTickAt = [&](qreal degrees) {
            const qreal radians = qDegreesToRadians(degrees);
            const QPoint probe =
                (outputDialCenter + QPointF(qCos(radians), -qSin(radians)) * outputTickRadius)
                    .toPoint();
            for (int y = probe.y() - 2; y <= probe.y() + 2; ++y) {
                for (int x = probe.x() - 2; x <= probe.x() + 2; ++x) {
                    if (!outputDialImage.valid(x, y))
                        continue;
                    const QColor pixel = outputDialImage.pixelColor(x, y);
                    if (std::abs(pixel.red() - outputTickColor.red()) <= 8 &&
                        std::abs(pixel.green() - outputTickColor.green()) <= 8 &&
                        std::abs(pixel.blue() - outputTickColor.blue()) <= 8) {
                        return true;
                    }
                }
            }
            return false;
        };
        check(hasOutputTickAt(240.0) && hasOutputTickAt(-60.0),
              "application-output dial ticks do not align to 0 and 100 percent");
        check(!hasOutputTickAt(270.0),
              "application-output dial renders a tick in its unreachable lower arc");
    }
    if (check(volSpin && volCaption && outputDial && outputCaption && transport && transportSpacer,
              "transport volume controls, spacer, or toolbar not found")) {
        const QList<QAction *> actions = transport->actions();
        int spacerActionIndex = -1;
        int captionActionIndex = -1;
        int volumeActionIndex = -1;
        int outputCaptionActionIndex = -1;
        int outputActionIndex = -1;
        for (int i = 0; i < actions.size(); i++) {
            QWidget *widget = transport->widgetForAction(actions.at(i));
            if (widget == transportSpacer)
                spacerActionIndex = i;
            else if (widget == volCaption)
                captionActionIndex = i;
            else if (widget == volSpin)
                volumeActionIndex = i;
            else if (widget == outputCaption)
                outputCaptionActionIndex = i;
            else if (widget == outputDial)
                outputActionIndex = i;
        }
        check(spacerActionIndex >= 0 && spacerActionIndex < captionActionIndex &&
                  captionActionIndex + 1 == volumeActionIndex &&
                  volumeActionIndex < outputCaptionActionIndex &&
                  outputCaptionActionIndex < outputActionIndex &&
                  transportSpacer->sizePolicy().horizontalPolicy() == QSizePolicy::Expanding &&
                  outputActionIndex == actions.size() - 1,
              "application-output dial is not at the transport bar's right edge");
        check(volSpin->isEnabled() && volSpin->value() == tabA->doc.cfg().masterVolume,
              "spinbox does not show the active tab's master volume");
        const int songVolumeBeforeOutputEdit = tabA->doc.cfg().masterVolume;
        const int documentUndoCountBeforeOutputEdit = tabA->doc.undoStack()->count();
        outputDial->setValue(37);
        QSettings outputSettings;
        check(outputDial->minimum() == 0 && outputDial->maximum() == 100,
              "application-output dial range changed");
        check(outputDial->toolTip().contains(QStringLiteral("Does not change the song volume")),
              "application-output dial lost its explanatory tooltip");
        check(m_audio.outputVolume() == 37 &&
                  outputSettings.value(QStringLiteral("outputVolume")).toInt() == 37,
              "application-output dial did not reach the audio engine or settings");
        check(tabA->doc.cfg().masterVolume == songVolumeBeforeOutputEdit &&
                  tabA->doc.undoStack()->count() == documentUndoCountBeforeOutputEdit &&
                  m_undoGroup->activeStack() == tabA->doc.undoStack() && !tabA->doc.isDirty(),
              "application-output dial changed song state or document undo state");
        outputDial->setValue(50);

        const QPointF outputCenter(outputDial->rect().center());
        const int documentUndoCount = tabA->doc.undoStack()->count();
        checks::events::sendMouse(*outputDial, QEvent::MouseButtonPress, outputCenter,
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*outputDial, QEvent::MouseButtonRelease, outputCenter,
                                  Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
        check(outputDial->value() == 50 && tabA->doc.undoStack()->count() == documentUndoCount &&
                  m_undoGroup->activeStack() == tabA->doc.undoStack(),
              "application-output dial treated a plain click as an edit");

        checks::events::sendMouse(*outputDial, QEvent::MouseButtonPress, outputCenter,
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*outputDial, QEvent::MouseMove, outputCenter + QPointF(0.0, 11.0),
                                  Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*outputDial, QEvent::MouseButtonRelease,
                                  outputCenter + QPointF(0.0, 11.0), Qt::LeftButton, Qt::NoButton,
                                  Qt::NoModifier);
        check(outputDial->value() > 50 && tabA->doc.undoStack()->count() == documentUndoCount &&
                  m_undoGroup->activeStack() == tabA->doc.undoStack(),
              "dragging down did not increase application output volume");

        outputDial->setValue(50);
        checks::events::sendMouse(*outputDial, QEvent::MouseButtonPress, outputCenter,
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*outputDial, QEvent::MouseMove,
                                  outputCenter + QPointF(0.0, -11.0), Qt::NoButton, Qt::LeftButton,
                                  Qt::NoModifier);
        checks::events::sendMouse(*outputDial, QEvent::MouseButtonRelease,
                                  outputCenter + QPointF(0.0, -11.0), Qt::LeftButton, Qt::NoButton,
                                  Qt::NoModifier);
        check(outputDial->value() < 50 && tabA->doc.undoStack()->count() == documentUndoCount &&
                  m_undoGroup->activeStack() == tabA->doc.undoStack(),
              "dragging up did not decrease application output volume");
        outputDial->setValue(50);
        outputDial->setValue(42);
        check(outputDial->value() == 42 && m_audio.outputVolume() == 42 &&
                  outputSettings.value(QStringLiteral("outputVolume")).toInt() == 42,
              "application-output edit did not reach the audio engine or settings");
        check(tabA->doc.undoStack()->count() == documentUndoCount &&
                  m_undoGroup->activeStack() == tabA->doc.undoStack() && !tabA->doc.isDirty(),
              "application-output edit entered or stole document undo history");
        outputDial->setValue(37);
        const int volBefore = tabA->doc.cfg().masterVolume;
        const int volEdited = volBefore == 100 ? 101 : 100;
        volSpin->setValue(volEdited);
        check(tabA->doc.cfg().masterVolume == volEdited && tabA->doc.isDirty(),
              "spinbox edit did not land as an undoable cfg change");
        check(m_undoGroup->activeStack() == tabA->doc.undoStack(),
              "a song edit did not restore the document undo stack");
        check(tabA->appliedVolume == volEdited,
              "spinbox edit did not reach the engine-applied volume");
        m_workspace->activateSession(tabB);
        check(volSpin->value() == tabB->doc.cfg().masterVolume,
              "spinbox did not follow the tab switch");
        check(outputDial->value() == 37, "application-output dial changed with the active tab");
        check(m_audio.outputVolume() == 37,
              "application-output engine volume changed with the active tab");
        check(!tabB->doc.isDirty(), "tab switch leaked a volume edit into the other tab");
        m_workspace->activateSession(tabA);
        check(volSpin->value() == volEdited,
              "spinbox lost the edited tab's volume across the round trip");
        m_undoGroup->activeStack()->undo();
        check(tabA->doc.cfg().masterVolume == volBefore && !tabA->doc.isDirty(),
              "undo did not revert the spinbox's cfg edit");
        check(volSpin->value() == volBefore,
              "undo did not sync the spinbox back to the old volume");

        // The focused spinbox must not starve the play/pause shortcut: its
        // line edit (the focus proxy that sees key events) refuses Space's
        // ShortcutOverride, while still claiming digits for normal typing.
        auto *volEdit = volSpin->findChild<QLineEdit *>();
        if (check(volEdit != nullptr, "volume spinbox has no line edit")) {
            QKeyEvent spaceOverride(QEvent::ShortcutOverride, Qt::Key_Space, Qt::NoModifier,
                                    QStringLiteral(" "), false, 1);
            spaceOverride.ignore();
            QApplication::sendEvent(volEdit, &spaceOverride);
            check(!spaceOverride.isAccepted(),
                  "volume spinbox claimed Space from the play/pause shortcut");
            QKeyEvent digitOverride(QEvent::ShortcutOverride, Qt::Key_5, Qt::NoModifier,
                                    QStringLiteral("5"), false, 1);
            digitOverride.ignore();
            QApplication::sendEvent(volEdit, &digitOverride);
            check(digitOverride.isAccepted(), "volume spinbox no longer claims plain digit keys");
        }
    }

    // 5c. Scale controls route only to the active tab. Highlight and Fold
    // remain independent across selected logical-track changes.
    if (haveScaleControls) {
        const auto chooseComboData = [&check](QComboBox *combo, int value, const char *what) {
            const int index = combo->findData(value);
            if (!check(index >= 0, what))
                return false;
            combo->setCurrentIndex(index);
            return true;
        };
        constexpr int rootA = 9;
        constexpr int rootB = 2;
        constexpr auto scaleA = porydaw_scale::ScaleId::dorian;
        constexpr auto scaleB = porydaw_scale::ScaleId::minor_pentatonic;

        m_workspace->activateSession(tabA);
        chooseComboData(rootCombo, rootA, "A root is missing from the transport control");
        chooseComboData(scaleCombo, static_cast<int>(scaleA),
                        "A scale is missing from the transport control");
        highlightButton->click();
        check(m_workspace->viewFor(*tabA).scaleRoot() == rootA &&
                  m_workspace->viewFor(*tabA).scaleId() == scaleA &&
                  m_workspace->viewFor(*tabA).scaleHighlight() &&
                  !m_workspace->viewFor(*tabA).scaleFold() && highlightButton->isChecked() &&
                  !foldButton->isChecked(),
              "scale controls did not enable Highlight for the first tab");
        highlightButton->click();
        check(!m_workspace->viewFor(*tabA).scaleHighlight() &&
                  !m_workspace->viewFor(*tabA).scaleFold() && !highlightButton->isChecked() &&
                  !foldButton->isChecked(),
              "clicking active Highlight did not disable Highlight");
        highlightButton->click();
        m_workspace->activateSession(tabB);
        chooseComboData(rootCombo, rootB, "B root is missing from the transport control");
        chooseComboData(scaleCombo, static_cast<int>(scaleB),
                        "B scale is missing from the transport control");
        SongView &bView = m_workspace->viewFor(*tabB);
        const int originalTrack = bView.selectionModel().primaryTrack();
        bool addedTrack = false;
        int differentTrack = -1;
        if (tabB->doc.engineTrackCount() < 2) {
            differentTrack = tabB->doc.addTrack(0);
            addedTrack = differentTrack >= 0;
        } else {
            for (int track = 0; track < tabB->doc.engineTrackCount(); track++) {
                if (track != originalTrack) {
                    differentTrack = track;
                    break;
                }
            }
        }
        if (check(differentTrack >= 0, "could not create a second routing-check track")) {
            bView.selectTrack(originalTrack);
            foldButton->click();
            check(bView.scaleRoot() == rootB && bView.scaleId() == scaleB &&
                      !bView.scaleHighlight() && bView.scaleFold() &&
                      rootCombo->currentData().toInt() == rootB &&
                      scaleCombo->currentData().toInt() == static_cast<int>(scaleB) &&
                      !highlightButton->isChecked() && foldButton->isChecked(),
                  "second tab did not retain its Fold scale control values");

            highlightButton->click();
            check(bView.scaleHighlight() && bView.scaleFold() && highlightButton->isChecked() &&
                      foldButton->isChecked(),
                  "Highlight and Fold could not be active together");
            highlightButton->click();
            check(!bView.scaleHighlight() && bView.scaleFold() && !highlightButton->isChecked() &&
                      foldButton->isChecked(),
                  "clicking active Highlight altered Fold");
            highlightButton->click();
            foldButton->click();
            check(bView.scaleHighlight() && !bView.scaleFold() && highlightButton->isChecked() &&
                      !foldButton->isChecked(),
                  "clicking active Fold altered Highlight");
            foldButton->click();
            check(bView.scaleHighlight() && bView.scaleFold() && highlightButton->isChecked() &&
                      foldButton->isChecked(),
                  "re-enabling Fold did not preserve Highlight");

            m_workspace->activateSession(tabA);
            check(rootCombo->currentData().toInt() == rootA &&
                      scaleCombo->currentData().toInt() == static_cast<int>(scaleA) &&
                      highlightButton->isChecked() && !foldButton->isChecked(),
                  "scale controls did not follow the first tab");
            m_workspace->activateSession(tabB);
            check(rootCombo->currentData().toInt() == rootB &&
                      scaleCombo->currentData().toInt() == static_cast<int>(scaleB) &&
                      highlightButton->isChecked() && foldButton->isChecked(),
                  "scale controls did not return to the second tab");

            bView.selectTrack(differentTrack);
            check(bView.scaleHighlight() && bView.scaleFold() && highlightButton->isChecked() &&
                      foldButton->isChecked(),
                  "a selected-track change altered active Highlight or Fold");
            bView.selectTrack(originalTrack);
            check(bView.scaleHighlight() && bView.scaleFold(),
                  "returning to the previous track altered active Highlight or Fold");

            bView.setScaleHighlight(false);
            bView.setScaleFold(false);
            bView.selectTrack(differentTrack);
            bView.selectTrack(originalTrack);
            check(!bView.scaleHighlight() && !bView.scaleFold(),
                  "track change enabled a disabled scale feature");
            bView.setScaleHighlight(true);
            bView.selectTrack(differentTrack);
            check(bView.scaleHighlight() && !bView.scaleFold(),
                  "track change altered independent Highlight");
            bView.selectTrack(originalTrack);
            bView.setScaleFold(true);
            bView.selectTrack(0);
            bView.deleteTrack(0);
            check(bView.scaleHighlight() && bView.scaleFold(),
                  "deleting the selected track altered active Highlight or Fold");
            tabB->doc.undoStack()->undo();

            const int remappedTrack = std::max(originalTrack, differentTrack);
            bView.selectTrack(remappedTrack);
            bView.setScaleHighlight(true);
            bView.setScaleFold(true);
            bView.deleteTrack(0);
            check(bView.scaleHighlight() && bView.scaleFold(),
                  "deleting a lower track altered active Highlight or Fold during an index remap");
            tabB->doc.undoStack()->undo();
            check(bView.scaleHighlight() && bView.scaleFold(),
                  "undoing a lower-track deletion altered active Highlight or Fold during an index "
                  "remap");
            if (addedTrack)
                tabB->doc.undoStack()->undo();
            check(!tabB->doc.isDirty(), "scale routing check left the second tab dirty");

            m_workspace->activateSession(tabA);
            check(m_workspace->viewFor(*tabA).scaleRoot() == rootA &&
                      m_workspace->viewFor(*tabA).scaleId() == scaleA &&
                      m_workspace->viewFor(*tabA).scaleHighlight() &&
                      !m_workspace->viewFor(*tabA).scaleFold(),
                  "inactive first-tab scale state was not preserved");
            m_workspace->activateSession(tabB);
            check(m_workspace->viewFor(*tabB).scaleRoot() == rootB &&
                      m_workspace->viewFor(*tabB).scaleId() == scaleB &&
                      m_workspace->viewFor(*tabB).scaleHighlight() &&
                      m_workspace->viewFor(*tabB).scaleFold(),
                  "inactive second-tab scale state was not preserved");
        }
    }

    // 6. Re-opening an already open song focuses its tab, no duplicates.
    loadSongByLabel(songB, /*newTab=*/true);
    check(m_workspace->openSessionCount() == 2 && m_active == tabB,
          "re-opening an open song did not just focus its tab");

    // 7. Closing a tab hands the engine to the survivor.
    closeSession(*tabB);
    check(m_workspace->openSessionCount() == 1 && m_active == tabA &&
              m_audio.timeline() == tabA->timeline.get(),
          "closing the active tab did not fall back to the other tab");
    check(sessionForLabel(songB) == nullptr, "closed tab's session lingered");

    loadSongByLabel(songB);
    tabB = m_active;
    if (!waitForLoaded(tabB, "in-place replacement"))
        return false;
    check(m_workspace->openSessionCount() == 1 && tabB && tabB->doc.label() == songB &&
              sessionForLabel(songA) == nullptr,
          "activating a song did not replace the current tab's");
    check(m_audio.timeline() == tabB->timeline.get(),
          "engine did not rebind after the in-place replace");

    // 8b. Re-activating the current tab's own song reloads it from disk —
    // the only reload path for a .mid edited externally. The cleared undo
    // stack is the observable difference (a plain focus keeps it).
    uint64_t base2 = 0;
    for (const SmfTrack &tr : tabB->doc.smf().tracks)
        base2 = std::max(base2, tr.endTick);
    tabB->doc.addNote(0, base2 + 96, 72, 24, 93);
    m_undoGroup->activeStack()->undo();
    check(!tabB->doc.isDirty() && tabB->doc.undoStack()->count() == 1,
          "reload precondition: clean doc with undo history");
    loadSongByLabel(songB);
    if (!waitForLoaded(tabB, "in-place reload"))
        return false;
    check(m_workspace->openSessionCount() == 1 && m_active == tabB &&
              tabB->doc.undoStack()->count() == 0,
          "re-activating the open song did not reload it in place");

    // 9. Closing the final playing tab restores the no-tab UI cadence.
    m_audio.play();
    wait(200);
    synchronizePlayhead();
    check(m_uiTimer->interval() == 100, "final-tab close precondition is not playback cadence");
    closeSession(*tabB);
    check(m_workspace->openSessionCount() == 0 && m_active == nullptr &&
              m_uiTimer->interval() == 500,
          "closing final playing tab did not restore 500 ms UI cadence");
    if (haveScaleControls) {
        check(!rootCombo->isEnabled() && !scaleCombo->isEnabled() &&
                  !highlightButton->isEnabled() && !foldButton->isEnabled(),
              "scale controls remained enabled after closing the final tab");
    }

    loadSongByLabel(songB);
    tabB = m_active;
    if (!waitForLoaded(tabB, "post-close song reopen"))
        return false;

    // 10. The open-tab set is recorded for restoreSession.
    loadSongByLabel(songA, /*newTab=*/true);
    tabA = m_active;
    if (!waitForLoaded(tabA, "persistence song reopen"))
        return false;
    {
        QSettings settings;
        const QStringList open = settings.value(QStringLiteral("lastOpenSongs")).toStringList();
        check(open == QStringList({songB, songA}),
              "lastOpenSongs does not list the open tabs in order");
        check(settings.value(QStringLiteral("lastSongLabel")).toString() == songA,
              "lastSongLabel is not the active tab");
    }

    // 10b. Saving a voicegroup refreshes every other CLEAN tab on the same
    // file immediately — waiting for activation would leave a stale parse
    // whose next save reverts this one. Needs two songs sharing a -G.
    if (tabA->vgSource && tabB->vgSource &&
        tabA->vgSource->filePath() == tabB->vgSource->filePath()) {
        int dsSlot = -1;
        for (int i = 0; i < VOICEGROUP_SIZE && dsSlot < 0; i++) {
            const VgVoice *v = tabA->vgSource->voiceAt(i);
            if (v &&
                (v->macro == VgMacro::DirectSound || v->macro == VgMacro::DirectSoundNoResample ||
                 v->macro == VgMacro::DirectSoundAlt))
                dsSlot = i;
        }
        if (dsSlot >= 0) {
            VgVoice edited = *tabA->vgSource->voiceAt(dsSlot);
            edited.release = edited.release == 25 ? 26 : 25;
            onVoiceEditRequested(dsSlot, edited, false); // active tab = A
            const LoadedVoiceGroup *bVgBefore = tabB->voicegroup;
            const QDateTime bVgTimeBefore = tabB->vgFileTime;
            check(waitForSave(tabA, "shared-voicegroup save"), "shared-voicegroup save failed");
            check(waitForVoicegroupRefresh(tabB, bVgBefore, bVgTimeBefore,
                                           "sibling voicegroup refresh"),
                  "sibling voicegroup refresh did not complete");
            check(tabB->voicegroup && tabB->voicegroup != bVgBefore,
                  "voicegroup save did not refresh the sibling tab's voicegroup");
            check(tabB->vgSource && tabB->vgSource->voiceAt(dsSlot) &&
                      tabB->vgSource->voiceAt(dsSlot)->release == edited.release &&
                      !tabB->vgSource->dirty(),
                  "sibling tab's voicegroup source did not follow the save");
        } else {
            std::printf("tabcheck: note: shared voicegroup has no sample "
                        "voices, save-refresh check skipped\n");
        }
    } else {
        std::printf("tabcheck: note: songs don't share a voicegroup, "
                    "save-refresh check skipped (use e.g. mus_b_dome + "
                    "mus_b_dome_lobby)\n");
    }

    // 11. A clean background tab follows its voicegroup file when the file
    // changes on disk (as after a save from another tab).
    if (tabB->vgSource) {
        const QString vgPath = tabB->vgSource->filePath();
        QFile f(vgPath);
        if (f.open(QIODevice::ReadWrite)) {
            // Same bytes, definitely-new mtime.
            const QDateTime beforeTime = tabB->vgFileTime;
            f.setFileTime(QDateTime::currentDateTime().addSecs(2),
                          QFileDevice::FileModificationTime);
            f.close();
            const LoadedVoiceGroup *before = tabB->voicegroup;
            m_workspace->activateSession(tabB);
            check(waitForVoicegroupRefresh(tabB, before, beforeTime, "clean voicegroup refresh"),
                  "clean tab voicegroup refresh did not complete");
            check(tabB->voicegroup != nullptr && tabB->voicegroup != before,
                  "clean tab did not reload its changed voicegroup file");
            check(tabB->vgSource && !tabB->vgSource->dirty(),
                  "voicegroup auto-refresh left the source dirty");
        } else {
            std::printf("tabcheck: note: voicegroup file not writable, "
                        "auto-refresh check skipped\n");
            m_workspace->activateSession(tabB);
        }
    } else {
        std::printf("tabcheck: note: no editable voicegroup source, "
                    "auto-refresh check skipped\n");
        m_workspace->activateSession(tabB);
    }

    std::printf("tabcheck: %s (%d failures)\n", failures ? "FAIL" : "PASS", failures);
    return failures == 0;
}

bool MainWindow::checkTabRestore(const QString &songA, const QString &songB)
{
    int failures = 0;
    const auto check = [&failures](bool ok, const char *what) {
        if (!ok) {
            std::fprintf(stderr, "tabcheck: FAIL: %s\n", what);
            failures++;
        }
        return ok;
    };

    const auto restoredReady = [this] {
        const auto sessions = m_workspace->sessionsInDisplayOrder();
        return sessions.size() == 2 &&
               std::all_of(sessions.cbegin(), sessions.cend(), [this](SongSession *session) {
                   return session && session->isInteractive() &&
                          m_workspace->isSessionAttached(*session);
               });
    };
    QEventLoop restoreLoop;
    QTimer poll;
    QTimer deadline;
    bool timedOut = false;
    poll.setInterval(1);
    deadline.setSingleShot(true);
    QObject::connect(&poll, &QTimer::timeout, &restoreLoop, [&] {
        if (restoredReady())
            restoreLoop.quit();
    });
    QObject::connect(&deadline, &QTimer::timeout, &restoreLoop, [&] {
        timedOut = true;
        restoreLoop.quit();
    });
    if (!restoredReady()) {
        poll.start();
        deadline.start(30000);
        restoreLoop.exec();
    }
    poll.stop();
    deadline.stop();
    if (!restoredReady()) {
        check(false, timedOut ? "restoreSession timed out waiting for interactive tabs"
                              : "restoreSession did not leave interactive tabs");
        return false;
    }

    const auto sessions = m_workspace->sessionsInDisplayOrder();
    const bool restoredBoth = m_workspace->openSessionCount() == 2 && sessions.size() == 2;
    check(restoredBoth, "relaunch did not restore both tabs");
    if (restoredBoth) {
        check(m_workspace->sessionTitle(*sessions[0]) == songB &&
                  m_workspace->sessionTitle(*sessions[1]) == songA,
              "restored tabs are not in the saved order");
        SongSession *active = m_workspace->activeSession();
        check(active && m_workspace->sessionTitle(*active) == songB,
              "relaunch did not re-activate the last active tab");
    }

    return failures == 0;
}

int runTabCheck(const QString &projectRoot, const QString &songA, const QString &songB)
{
    {
        MainWindow window;
        if (!window.runTabCheck(projectRoot, songA, songB))
            return 1;
    } // the first window's audio device is gone before the second opens

    // Relaunch: the whole tab set comes back, with the same active tab
    // (songB was active at the end of runTabCheck).
    int failures = 0;
    const auto check = [&failures](bool ok, const char *what) {
        if (!ok) {
            std::fprintf(stderr, "tabcheck: FAIL: %s\n", what);
            failures++;
        }
        return ok;
    };
    {
        MainWindow window;
        window.restoreSession();
        check(window.checkTabRestore(songA, songB),
              "restoreSession did not preserve tab order and active session");
        auto *outputDial = window.findChild<QDial *>(QStringLiteral("transportOutputVolume"));
        check(outputDial && outputDial->value() == 37,
              "relaunch did not restore application-output volume");
    }
    if (failures == 0)
        std::printf("tabcheck: restore PASS\n");
    return failures == 0 ? 0 : 1;
}
