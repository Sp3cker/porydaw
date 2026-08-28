#include <QApplication>
#include <QComboBox>
#include <QDateTime>
#include <QDial>
#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QImage>
#include <QKeyEvent>
#include <QLabel>
#include <QLineEdit>
#include <QSettings>
#include <QSizePolicy>
#include <QSpinBox>
#include <QTabWidget>
#include <QTimer>
#include <QToolBar>
#include <QToolButton>
#include <QUndoStack>
#include <QtMath>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <optional>

#include "checks/support/asyncwait.h"
#include "checks/support/eventsynth.h"
#include "checks/support/voicegroupbrowserdriver.h"
#include "core/smf.h"
#include "mainwindow.h"
#include "porydaw_scale.h"
#include "ui/dragspinbox.h"
#include "ui/layout.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/theme/themeruntime.h"
#include "ui/transportbar.h"
#include "ui/workspaceui.h"

// --tabcheck <projectRoot> <songA> <songB>: multi-tab check. Two songs open
// in tabs through the WorkspaceUi request seams with fully separate documents
// and undo histories; switching tabs stops playback and rebinds the audio
// engine to the active tab's timeline and voicegroup lease; closing and
// replacing tabs behave; the open-tab set round-trips through the QSettings
// recipe (the second half, in runTabCheck's caller, relaunches into a fresh
// window whose ProjectWorkspace queues the saved open by itself). A clean
// tab follows an externally touched voicegroup file through the mtime-gated
// reload. QSettings is redirected into a temp dir; view sidecars are written
// into the project on tab close — run against a scratch copy.

bool MainWindow::runTabCheck(const QString &projectRoot, const QString &songA, const QString &songB)
{
    // m_persistSession stays true (the caller redirected QSettings) so the
    // recipe written for the relaunch is exercised for real.
    if (!m_audioOk) {
        std::fprintf(stderr, "tabcheck: no audio device available\n");
        return false;
    }
    const std::optional<SongName> nameA = SongName::create(songA);
    const std::optional<SongName> nameB = SongName::create(songB);
    if (!nameA || !nameB) {
        std::fprintf(stderr, "tabcheck: song labels were rejected as identities\n");
        return false;
    }

    // Project opens are asynchronous: request, then await the Ready state.
    m_workspace->requestProjectOpenAt(projectRoot);
    const auto projectReady = [this] {
        return m_workspace->projectState().state == ProjectOpenState::Ready;
    };
    if (checks::async_wait::waitUntil([] { return true; }, projectReady, 30000, 1) !=
        checks::async_wait::Result::Ready) {
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
    // Await a tab's terminal payload while it stays open; the engine handoff
    // for the selected tab is synchronous with readiness.
    const auto waitForTabReady = [this, &failures](SongTab *tab, const char *what) {
        const auto isLive = [this, tab] {
            return tab && m_workspace->songTabFor(tab->name()) == tab;
        };
        if (!isLive()) {
            std::fprintf(stderr, "tabcheck: FAIL: %s tab disappeared before loading\n", what);
            failures++;
            return false;
        }
        constexpr int loadTimeoutMs = 15000;
        const auto result = checks::async_wait::waitUntil(
            isLive, [tab] { return tab->isReady(); }, loadTimeoutMs, 1);
        if (result == checks::async_wait::Result::Destroyed || !isLive()) {
            std::fprintf(stderr, "tabcheck: FAIL: %s tab was destroyed while loading\n", what);
            failures++;
            return false;
        }
        if (!tab->isReady()) {
            std::fprintf(stderr, "tabcheck: FAIL: timed out waiting for %s (%d ms)\n", what,
                         loadTimeoutMs);
            failures++;
            return false;
        }
        return true;
    };
    // Open (or focus) a song and await its readiness; nullptr on failure.
    const auto openSong = [this, &waitForTabReady](const SongName &name, bool newTab,
                                                   const char *what) -> SongTab * {
        m_workspace->requestSongOpen(name, newTab);
        SongTab *tab = m_workspace->songTabFor(name);
        if (!tab || !waitForTabReady(tab, what))
            return nullptr;
        return tab;
    };
    QTabWidget *const tabWidget = findChild<QTabWidget *>();
    const auto tabTitle = [tabWidget](SongTab *tab) {
        return tabWidget && tab ? tabWidget->tabText(tabWidget->indexOf(tab)) : QString();
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
    m_workspace->requestSongOpen(*nameA);
    SongTab *tabA = m_workspace->selectedSongTab();
    if (!tabA) {
        std::fprintf(stderr, "tabcheck: song '%s' did not create a tab\n", qUtf8Printable(songA));
        return false;
    }
    check(m_workspace->openTabCount() == 1, "first song did not open exactly one tab");
    check(m_selectedTab == tabA && m_workspace->selectedSongTab() == tabA &&
              !tabA->view().isHidden(),
          "first song did not present an active visible tab immediately");
    check(!tabA->isReady(), "first song bound data before requestSongOpen returned");
    if (!waitForTabReady(tabA, "first song"))
        return false;
    check(tabA->document().label() == songA, "first song did not finish loading");
    check(m_audio.timeline() == tabA->timeline().get() &&
              m_audio.voicegroup() == tabA->voicegroupLease().get(),
          "engine is not borrowing the first tab's data");
    check(m_uiTimer->interval() == 500, "paused UI cadence is not 500 ms");

    // 2. Second song in a new tab becomes the active one.
    m_workspace->requestSongOpen(*nameB, /*newTab=*/true);
    SongTab *tabB = m_workspace->selectedSongTab();
    if (!tabB || tabB == tabA) {
        std::fprintf(stderr, "tabcheck: song '%s' did not open in a new tab\n",
                     qUtf8Printable(songB));
        return false;
    }
    check(m_workspace->openTabCount() == 2, "second song did not open a second tab");
    check(m_selectedTab == tabB && m_workspace->selectedSongTab() == tabB &&
              !tabB->view().isHidden(),
          "second song did not present its active tab immediately");
    check(!tabB->isReady(), "second song bound data before requestSongOpen returned");
    if (!waitForTabReady(tabB, "second song"))
        return false;
    check(tabB->document().label() == songB, "second song did not finish loading");
    check(m_audio.timeline() == tabB->timeline().get(), "engine did not rebind to the new tab");
    check(m_workspace->songTabFor(*nameA) == tabA && !tabA->document().isDirty(),
          "first tab did not survive the second one opening");

    if (haveScaleControls) {
        check(!tabA->view().scaleHighlight() && !tabA->view().scaleFold() &&
                  tabA->view().scaleRoot() == 0 &&
                  tabA->view().scaleId() == porydaw_scale::ScaleId::major,
              "first tab does not start at C Major with both scale features disabled");
        check(!tabB->view().scaleHighlight() && !tabB->view().scaleFold() &&
                  tabB->view().scaleRoot() == 0 &&
                  tabB->view().scaleId() == porydaw_scale::ScaleId::major &&
                  rootCombo->currentData().toInt() == 0 &&
                  scaleCombo->currentData().toInt() ==
                      static_cast<int>(porydaw_scale::ScaleId::major) &&
                  !highlightButton->isChecked() && !foldButton->isChecked(),
              "second tab or its controls do not start with both scale features disabled");
    }

    // 3. Separate documents and undo histories: an edit in one tab dirties
    // only that tab.
    m_workspace->selectSongTab(tabA);
    check(m_selectedTab == tabA && m_audio.timeline() == tabA->timeline().get(),
          "switching tabs did not rebind the engine to the first tab");
    SongDocument *const docA = tabA->view().document();
    if (!check(docA != nullptr, "first tab has no document"))
        return false;
    if (docA->engineTrackCount() == 0) {
        std::fprintf(stderr, "tabcheck: song '%s' has no tracks\n", qUtf8Printable(songA));
        return false;
    }
    uint64_t base = 0;
    for (const SmfTrack &tr : docA->smf().tracks)
        base = std::max(base, tr.endTick);
    docA->addNote(0, base + 96, 72, 24, 93);
    check(tabA->document().isDirty() && !tabB->document().isDirty(),
          "edit in one tab did not stay in that tab");
    check(tabTitle(tabA).endsWith(QLatin1Char('*')), "dirty tab title has no asterisk");
    check(!tabTitle(tabB).endsWith(QLatin1Char('*')), "clean tab title grew an asterisk");

    // 4. Switching tabs stops playback in the tab being left.
    m_audio.play();
    wait(200);
    check(m_audio.transport() == Transport::Playing, "playback did not start");
    synchronizePlayhead();
    check(m_uiTimer->interval() == 100, "playback UI cadence is not 100 ms");
    m_workspace->selectSongTab(tabB);
    check(m_audio.transport() == Transport::Stopped, "switching tabs did not stop playback");
    check(m_uiTimer->interval() == 500, "stopped UI cadence is not 500 ms");
    check(m_audio.timeline() == tabB->timeline().get(),
          "engine timeline is not the newly active tab's");

    // 5. The dirty edit survives the round trip; each history undoes its own.
    m_workspace->selectSongTab(tabA);
    check(tabA->document().isDirty(), "first tab's edit vanished across the switch");
    check(!tabB->history().canUndo(), "second tab inherited the first tab's undo entry");
    m_workspace->requestUndo();
    check(!tabA->document().isDirty() && !tabB->document().isDirty(),
          "undo did not clean the selected tab's document");

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
        check(volSpin->isEnabled() && volSpin->value() == tabA->document().cfg().masterVolume,
              "spinbox does not show the active tab's master volume");
        const int songVolumeBeforeOutputEdit = tabA->document().cfg().masterVolume;
        const int documentUndoCountBeforeOutputEdit = docA->undoStack()->count();
        outputDial->setValue(37);
        QSettings outputSettings;
        check(outputDial->minimum() == 0 && outputDial->maximum() == 100,
              "application-output dial range changed");
        check(outputDial->toolTip().contains(QStringLiteral("Does not change the song volume")),
              "application-output dial lost its explanatory tooltip");
        check(m_audio.outputVolume() == 37 &&
                  outputSettings.value(QStringLiteral("outputVolume")).toInt() == 37,
              "application-output dial did not reach the audio engine or settings");
        check(tabA->document().cfg().masterVolume == songVolumeBeforeOutputEdit &&
                  docA->undoStack()->count() == documentUndoCountBeforeOutputEdit &&
                  !tabA->document().isDirty(),
              "application-output dial changed song state or document undo state");
        outputDial->setValue(50);

        const QPointF outputCenter(outputDial->rect().center());
        const int documentUndoCount = docA->undoStack()->count();
        checks::events::sendMouse(*outputDial, QEvent::MouseButtonPress, outputCenter,
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*outputDial, QEvent::MouseButtonRelease, outputCenter,
                                  Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
        check(outputDial->value() == 50 && docA->undoStack()->count() == documentUndoCount,
              "application-output dial treated a plain click as an edit");

        checks::events::sendMouse(*outputDial, QEvent::MouseButtonPress, outputCenter,
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*outputDial, QEvent::MouseMove, outputCenter + QPointF(0.0, 11.0),
                                  Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*outputDial, QEvent::MouseButtonRelease,
                                  outputCenter + QPointF(0.0, 11.0), Qt::LeftButton, Qt::NoButton,
                                  Qt::NoModifier);
        check(outputDial->value() > 50 && docA->undoStack()->count() == documentUndoCount,
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
        check(outputDial->value() < 50 && docA->undoStack()->count() == documentUndoCount,
              "dragging up did not decrease application output volume");
        outputDial->setValue(50);
        outputDial->setValue(42);
        check(outputDial->value() == 42 && m_audio.outputVolume() == 42 &&
                  outputSettings.value(QStringLiteral("outputVolume")).toInt() == 42,
              "application-output edit did not reach the audio engine or settings");
        check(docA->undoStack()->count() == documentUndoCount && !tabA->document().isDirty(),
              "application-output edit entered or stole document undo history");
        outputDial->setValue(37);
        const int volBefore = tabA->document().cfg().masterVolume;
        const int volEdited = volBefore == 100 ? 101 : 100;
        volSpin->setValue(volEdited);
        check(tabA->document().cfg().masterVolume == volEdited && tabA->document().isDirty(),
              "spinbox edit did not land as an undoable cfg change");
        check(tabA->history().canUndo(), "a song edit did not restore the document undo stack");
        check(m_appliedSettings && m_appliedSettings->songVolume == uint8_t(volEdited),
              "spinbox edit did not reach the engine-applied volume");
        m_workspace->selectSongTab(tabB);
        check(volSpin->value() == tabB->document().cfg().masterVolume,
              "spinbox did not follow the tab switch");
        check(outputDial->value() == 37, "application-output dial changed with the active tab");
        check(m_audio.outputVolume() == 37,
              "application-output engine volume changed with the active tab");
        check(!tabB->document().isDirty(), "tab switch leaked a volume edit into the other tab");
        m_workspace->selectSongTab(tabA);
        check(volSpin->value() == volEdited,
              "spinbox lost the edited tab's volume across the round trip");
        m_workspace->requestUndo();
        check(tabA->document().cfg().masterVolume == volBefore && !tabA->document().isDirty(),
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

        m_workspace->selectSongTab(tabA);
        chooseComboData(rootCombo, rootA, "A root is missing from the transport control");
        chooseComboData(scaleCombo, static_cast<int>(scaleA),
                        "A scale is missing from the transport control");
        highlightButton->click();
        check(tabA->view().scaleRoot() == rootA && tabA->view().scaleId() == scaleA &&
                  tabA->view().scaleHighlight() && !tabA->view().scaleFold() &&
                  highlightButton->isChecked() && !foldButton->isChecked(),
              "scale controls did not enable Highlight for the first tab");
        highlightButton->click();
        check(!tabA->view().scaleHighlight() && !tabA->view().scaleFold() &&
                  !highlightButton->isChecked() && !foldButton->isChecked(),
              "clicking active Highlight did not disable Highlight");
        highlightButton->click();
        m_workspace->selectSongTab(tabB);
        chooseComboData(rootCombo, rootB, "B root is missing from the transport control");
        chooseComboData(scaleCombo, static_cast<int>(scaleB),
                        "B scale is missing from the transport control");
        SongView &bView = tabB->view();
        const int originalTrack = bView.selectionModel().primaryTrack();
        bool addedTrack = false;
        int differentTrack = -1;
        SongDocument *const docB = tabB->view().document();
        if (!check(docB != nullptr, "second tab has no document for the scale routing check"))
            return false;
        if (docB->engineTrackCount() < 2) {
            differentTrack = docB->addTrack(0);
            addedTrack = differentTrack >= 0;
        } else {
            for (int track = 0; track < docB->engineTrackCount(); track++) {
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

            m_workspace->selectSongTab(tabA);
            check(rootCombo->currentData().toInt() == rootA &&
                      scaleCombo->currentData().toInt() == static_cast<int>(scaleA) &&
                      highlightButton->isChecked() && !foldButton->isChecked(),
                  "scale controls did not follow the first tab");
            m_workspace->selectSongTab(tabB);
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
            m_workspace->requestUndo();

            const int remappedTrack = std::max(originalTrack, differentTrack);
            bView.selectTrack(remappedTrack);
            bView.setScaleHighlight(true);
            bView.setScaleFold(true);
            bView.deleteTrack(0);
            check(bView.scaleHighlight() && bView.scaleFold(),
                  "deleting a lower track altered active Highlight or Fold during an index remap");
            m_workspace->requestUndo();
            check(bView.scaleHighlight() && bView.scaleFold(),
                  "undoing a lower-track deletion altered active Highlight or Fold during an index "
                  "remap");
            if (addedTrack)
                m_workspace->requestUndo();
            check(!tabB->document().isDirty(), "scale routing check left the second tab dirty");

            m_workspace->selectSongTab(tabA);
            check(tabA->view().scaleRoot() == rootA && tabA->view().scaleId() == scaleA &&
                      tabA->view().scaleHighlight() && !tabA->view().scaleFold(),
                  "inactive first-tab scale state was not preserved");
            m_workspace->selectSongTab(tabB);
            check(tabB->view().scaleRoot() == rootB && tabB->view().scaleId() == scaleB &&
                      tabB->view().scaleHighlight() && tabB->view().scaleFold(),
                  "inactive second-tab scale state was not preserved");
        }
    }

    // 6. Re-opening an already open song focuses its tab, no duplicates.
    m_workspace->requestSongOpen(*nameB, /*newTab=*/true);
    check(m_workspace->openTabCount() == 2 && m_workspace->selectedSongTab() == tabB,
          "re-opening an open song did not just focus its tab");

    // 7. Closing a tab hands the engine to the survivor.
    m_workspace->requestCloseSelectedTab(); // tabB is selected and clean
    check(m_workspace->openTabCount() == 1 && m_workspace->selectedSongTab() == tabA &&
              m_audio.timeline() == tabA->timeline().get(),
          "closing the active tab did not fall back to the other tab");
    check(m_workspace->songTabFor(*nameB) == nullptr, "closed tab's session lingered");

    tabB = openSong(*nameB, /*newTab=*/false, "in-place replacement");
    if (!tabB)
        return false;
    check(m_workspace->openTabCount() == 1 && tabB->document().label() == songB &&
              m_workspace->songTabFor(*nameA) == nullptr,
          "activating a song did not replace the current tab's");
    check(m_audio.timeline() == tabB->timeline().get(),
          "engine did not rebind after the in-place replace");

    // 8b. Re-activating the current tab's own song reloads it from disk —
    // the only reload path for a .mid edited externally. The cleared history
    // is the observable difference (a plain focus keeps it).
    SongDocument *const docB = tabB->view().document();
    if (!check(docB != nullptr, "in-place replacement has no document"))
        return false;
    uint64_t base2 = 0;
    for (const SmfTrack &tr : docB->smf().tracks)
        base2 = std::max(base2, tr.endTick);
    docB->addNote(0, base2 + 96, 72, 24, 93);
    m_workspace->requestUndo();
    check(!tabB->document().isDirty() && docB->undoStack()->count() == 1,
          "reload precondition: clean doc with undo history");
    m_workspace->requestSongOpen(*nameB);
    const auto reloadWait = checks::async_wait::waitUntil(
        [this, tabB] { return m_workspace->songTabFor(tabB->name()) == tabB; },
        [this, tabB, docB] {
            return tabB->isReady() && docB->undoStack()->count() == 0 &&
                   m_workspace->openProjectEnabled();
        });
    check(reloadWait == checks::async_wait::Result::Ready && m_workspace->openTabCount() == 1 &&
              m_workspace->selectedSongTab() == tabB,
          "re-activating the open song did not reload it in place");

    // 9. Closing the final playing tab restores the no-tab UI cadence.
    m_audio.play();
    wait(200);
    synchronizePlayhead();
    check(m_uiTimer->interval() == 100, "final-tab close precondition is not playback cadence");
    m_workspace->requestCloseSelectedTab();
    check(m_workspace->openTabCount() == 0 && m_workspace->selectedSongTab() == nullptr &&
              m_uiTimer->interval() == 500,
          "closing final playing tab did not restore 500 ms UI cadence");
    if (haveScaleControls) {
        check(!rootCombo->isEnabled() && !scaleCombo->isEnabled() &&
                  !highlightButton->isEnabled() && !foldButton->isEnabled(),
              "scale controls remained enabled after closing the final tab");
    }

    tabB = openSong(*nameB, /*newTab=*/false, "post-close song reopen");
    if (!tabB)
        return false;

    // 10. The open-tab set is recorded for the relaunch's saved recipe.
    tabA = openSong(*nameA, /*newTab=*/true, "persistence song reopen");
    if (!tabA)
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
    // whose next save reverts this one. Needs two songs sharing a -G. The
    // edit rides the production browser seam (slot selection, then the
    // release spin) into the shared-bank coordinator, and the save carries
    // the dirty bank recipe to the worker.
    SongTab *const source = tabA; // selected and edited
    SongTab *const observer = tabB;
    if (source->voicegroupId() && observer->voicegroupId() &&
        *source->voicegroupId() == *observer->voicegroupId()) {
        checks::VoicegroupBrowserDriver driver(*m_workspace);
        if (check(driver.isAvailable() && driver.selectedBankView() != nullptr &&
                      driver.releaseSpinBox() != nullptr,
                  "voicegroup browser chrome not found")) {
            int dsSlot = -1;
            const VoicegroupLease sourceLease = source->voicegroupLease();
            for (int i = 0; i < VOICEGROUP_SIZE && dsSlot < 0; i++) {
                const uint8_t type = sourceLease->voices[i].type;
                if (type == VOICE_DIRECTSOUND || type == VOICE_DIRECTSOUND_NO_RESAMPLE ||
                    type == VOICE_DIRECTSOUND_ALT)
                    dsSlot = i;
            }
            if (check(dsSlot >= 0, "shared voicegroup has no sample voices")) {
                const uint8_t beforeRelease = sourceLease->voices[dsSlot].release;
                const int editedRelease = beforeRelease == 25 ? 26 : 25;
                const LoadedVoiceGroup *const sourceBefore = sourceLease.get();
                const LoadedVoiceGroup *const observerBefore = observer->voicegroupLease().get();
                driver.selectSlot(dsSlot);
                check(driver.releaseSpinBox()->value() == int(beforeRelease),
                      "browser editor does not show the selected slot's release");
                driver.releaseSpinBox()->setValue(editedRelease);
                // The picker edit settles when the previewed bank lands on
                // the edited tab and the shared-bank gate reopens.
                const auto editLanded = [&] {
                    return m_workspace->bankActionsEnabled() &&
                           source->voicegroupLease().get() != sourceBefore &&
                           source->voicegroupLease()->voices[dsSlot].release ==
                               uint8_t(editedRelease);
                };
                if (check(checks::async_wait::waitUntil([] { return true; }, editLanded, 15000,
                                                        1) == checks::async_wait::Result::Ready,
                          "voicegroup edit did not land in the edited tab's bank")) {
                    m_workspace->saveSelectedSong();
                    // The save refreshes the sibling through the keyed
                    // LoadedBankView publication before SongSaved lands.
                    const auto siblingRefreshed = [&] {
                        return !m_workspace->selectedSongDirty() &&
                               observer->voicegroupLease().get() != observerBefore &&
                               observer->voicegroupLease()->voices[dsSlot].release ==
                                   uint8_t(editedRelease);
                    };
                    check(checks::async_wait::waitUntil([] { return true; }, siblingRefreshed,
                                                        30000,
                                                        1) == checks::async_wait::Result::Ready &&
                              observer->voicegroupLease()->voices[dsSlot].release ==
                                  uint8_t(editedRelease),
                          "voicegroup save did not refresh the sibling tab's voicegroup");
                    // The sibling followed the save cleanly: with it selected,
                    // the production dirty gate stays open.
                    m_workspace->selectSongTab(observer);
                    check(!m_workspace->selectedSongDirty(),
                          "sibling tab did not follow the save cleanly");
                }
            }
        }
    } else {
        std::printf("tabcheck: note: songs don't share a voicegroup, "
                    "save-refresh check skipped (use e.g. mus_b_dome + "
                    "mus_b_dome_lobby)\n");
    }

    // 11. An externally touched voicegroup file reaches a clean tab through
    // the mtime-gated reload: the worker reuses its cached bank only while
    // the file's modification time is unchanged.
    if (observer->voicegroupId()) {
        const QString vgPath =
            QDir(projectRoot).filePath(observer->voicegroupId()->sourceRelativePath());
        QFile f(vgPath);
        if (f.open(QIODevice::ReadWrite)) {
            // Same bytes, definitely-new mtime.
            const LoadedVoiceGroup *before = observer->voicegroupLease().get();
            f.setFileTime(QDateTime::currentDateTime().addSecs(2),
                          QFileDevice::FileModificationTime);
            f.close();
            m_workspace->selectSongTab(observer);
            m_workspace->requestSongOpen(observer->name());
            const auto bankReloaded = [&] {
                return observer->isReady() && observer->voicegroupLease().get() != before;
            };
            check(checks::async_wait::waitUntil([] { return true; }, bankReloaded, 15000, 1) ==
                          checks::async_wait::Result::Ready &&
                      !m_workspace->selectedSongDirty(),
                  "clean tab did not reload its touched voicegroup file on reload");
        } else {
            std::printf("tabcheck: note: voicegroup file not writable, "
                        "auto-refresh check skipped\n");
        }
    } else {
        std::printf("tabcheck: note: no editable voicegroup source, "
                    "auto-refresh check skipped\n");
    }
    m_workspace->selectSongTab(source);
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

    const std::optional<SongName> nameA = SongName::create(songA);
    const std::optional<SongName> nameB = SongName::create(songB);
    if (!check(nameA && nameB, "restore fixture labels were rejected as identities"))
        return false;

    // Startup restoration is autonomous: the relaunch's ProjectWorkspace
    // constructor queued the saved recipe's open for this event loop, and the
    // named placeholder tabs load as ordinary keyed song updates.
    const auto restoredReady = [this, &nameA, &nameB] {
        if (m_workspace->openTabCount() != 2)
            return false;
        SongTab *const tabA = m_workspace->songTabFor(*nameA);
        SongTab *const tabB = m_workspace->songTabFor(*nameB);
        return tabA && tabB && tabA->isReady() && tabB->isReady();
    };
    const auto result = checks::async_wait::waitUntil([] { return true; }, restoredReady, 30000, 1);
    if (!restoredReady()) {
        check(false, result == checks::async_wait::Result::TimedOut
                         ? "startup restoration timed out waiting for ready tabs"
                         : "startup restoration did not leave ready tabs");
        return false;
    }

    const std::vector<SongTab *> tabs = m_workspace->tabsInDisplayOrder();
    const bool restoredBoth = m_workspace->openTabCount() == 2 && tabs.size() == 2;
    check(restoredBoth, "relaunch did not restore both tabs");
    if (restoredBoth) {
        check(tabs[0]->name() == *nameB && tabs[1]->name() == *nameA,
              "restored tabs are not in the saved order");
        SongTab *const active = m_workspace->selectedSongTab();
        check(active && active->name() == *nameA,
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

    // Relaunch: the whole tab set comes back on its own — the fresh window's
    // construction queues the saved recipe's open (ProjectWorkspace drives
    // it), and checkTabRestore awaits the restored tabs. songA was the last
    // active tab at the end of the first half.
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
        check(window.checkTabRestore(songA, songB),
              "startup restoration did not preserve tab order and active tab");
        auto *outputDial = window.findChild<QDial *>(QStringLiteral("transportOutputVolume"));
        check(outputDial && outputDial->value() == 37,
              "relaunch did not restore application-output volume");
    }
    if (failures == 0)
        std::printf("tabcheck: restore PASS\n");
    return failures == 0 ? 0 : 1;
}
