#include <QApplication>
#include <QComboBox>
#include <QDial>
#include <QEventLoop>
#include <QFile>
#include <QImage>
#include <QKeyEvent>
#include <QLabel>
#include <QLineEdit>
#include <QMouseEvent>
#include <QSettings>
#include <QSizePolicy>
#include <QSpinBox>
#include <QTabWidget>
#include <QTemporaryDir>
#include <QTimer>
#include <QToolBar>
#include <QToolButton>
#include <QUndoGroup>
#include <QUndoStack>
#include <QtMath>
#include <algorithm>
#include <cmath>
#include <cstdio>

#include "mainwindow.h"
#include "porydaw_scale.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/theme/themeruntime.h"
#include "ui/transportbar.h"

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
    if (!openProjectDir(projectRoot, /*interactive=*/false)) {
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

    // 1. First song loads into the first tab; the engine borrows its data.
    loadSongByLabel(songA);
    SongSession *tabA = m_active;
    if (!tabA || tabA->doc.label() != songA) {
        std::fprintf(stderr, "tabcheck: song '%s' did not load\n", qUtf8Printable(songA));
        return false;
    }
    check(m_tabs->count() == 1, "first song did not open exactly one tab");
    check(m_audio.timeline() == tabA->timeline.get() && m_audio.voicegroup() == tabA->voicegroup,
          "engine is not borrowing the first tab's data");
    check(m_uiTimer->interval() == 500, "paused UI cadence is not 500 ms");

    // 2. Second song in a new tab becomes the active one.
    loadSongByLabel(songB, /*newTab=*/true);
    SongSession *tabB = m_active;
    if (!tabB || tabB == tabA || tabB->doc.label() != songB) {
        std::fprintf(stderr, "tabcheck: song '%s' did not open in a new tab\n",
                     qUtf8Printable(songB));
        return false;
    }
    check(m_tabs->count() == 2, "second song did not open a second tab");
    check(m_audio.timeline() == tabB->timeline.get(), "engine did not rebind to the new tab");
    check(m_undoGroup->activeStack() == tabB->doc.undoStack(),
          "undo group is not on the new tab's stack");
    check(sessionForLabel(songA) == tabA && !tabA->doc.isDirty(),
          "first tab did not survive the second one opening");

    if (haveScaleControls) {
        check(!tabA->view->scaleHighlight() && !tabA->view->scaleFold() &&
                  tabA->view->scaleRoot() == 0 &&
                  tabA->view->scaleId() == porydaw_scale::ScaleId::major,
              "first tab does not start at C Major with both scale features disabled");
        check(!tabB->view->scaleHighlight() && !tabB->view->scaleFold() &&
                  tabB->view->scaleRoot() == 0 &&
                  tabB->view->scaleId() == porydaw_scale::ScaleId::major &&
                  rootCombo->currentData().toInt() == 0 &&
                  scaleCombo->currentData().toInt() ==
                      static_cast<int>(porydaw_scale::ScaleId::major) &&
                  !highlightButton->isChecked() && !foldButton->isChecked(),
              "second tab or its controls do not start with both scale features disabled");
    }

    // 3. Separate documents and undo stacks: an edit in one tab dirties
    // only that tab.
    m_tabs->setCurrentWidget(tabA->view);
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
    check(m_tabs->tabText(m_tabs->indexOf(tabA->view)).endsWith(QLatin1Char('*')),
          "dirty tab title has no asterisk");
    check(!m_tabs->tabText(m_tabs->indexOf(tabB->view)).endsWith(QLatin1Char('*')),
          "clean tab title grew an asterisk");

    // 4. Switching tabs stops playback in the tab being left.
    m_audio.play();
    wait(200);
    check(m_audio.transport() == Transport::Playing, "playback did not start");
    synchronizePlayhead();
    check(m_uiTimer->interval() == 100, "playback UI cadence is not 100 ms");
    m_tabs->setCurrentWidget(tabB->view);
    check(m_audio.transport() == Transport::Stopped, "switching tabs did not stop playback");
    check(m_uiTimer->interval() == 500, "stopped UI cadence is not 500 ms");
    check(m_audio.timeline() == tabB->timeline.get(),
          "engine timeline is not the newly active tab's");

    // 5. The dirty edit survives the round trip; each stack undoes its own.
    m_tabs->setCurrentWidget(tabA->view);
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
    check(defaultOutputDial && defaultOutputDial->value() == 68,
          "application-output dial does not default to 68 percent");
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
        outputDial->setValue(68);

        const auto sendOutputMouse = [outputDial](QEvent::Type type, const QPointF &position,
                                                  Qt::MouseButton button, Qt::MouseButtons buttons,
                                                  Qt::KeyboardModifiers modifiers) {
            QMouseEvent event(type, position, QPointF(outputDial->mapToGlobal(position.toPoint())),
                              button, buttons, modifiers);
            QApplication::sendEvent(outputDial, &event);
        };
        const QPointF outputCenter(outputDial->rect().center());
        const qreal outputRadius =
            qreal(std::min(outputDial->width(), outputDial->height())) / 2.0 -
            layout::singlePixel();
        const QPointF rotaryPress = outputCenter + QPointF(0.0, -outputRadius * 0.75);
        const int documentUndoCount = tabA->doc.undoStack()->count();
        sendOutputMouse(QEvent::MouseButtonPress, rotaryPress, Qt::LeftButton, Qt::LeftButton,
                        Qt::NoModifier);
        check(outputDial->value() == 68,
              "application-output dial jumped to the rotary press position");
        sendOutputMouse(QEvent::MouseButtonRelease, rotaryPress, Qt::LeftButton, Qt::NoButton,
                        Qt::NoModifier);
        check(outputDial->value() == 68 && tabA->doc.undoStack()->count() == documentUndoCount &&
                  m_undoGroup->activeStack() == tabA->doc.undoStack(),
              "application-output dial treated a plain click as an edit");

        const QPointF rotaryMove =
            outputCenter + QPointF(outputRadius * 0.53, -outputRadius * 0.53);
        sendOutputMouse(QEvent::MouseButtonPress, rotaryPress, Qt::LeftButton, Qt::LeftButton,
                        Qt::NoModifier);
        sendOutputMouse(QEvent::MouseMove, rotaryMove, Qt::NoButton, Qt::LeftButton,
                        Qt::NoModifier);
        const int rotaryValue = outputDial->value();
        sendOutputMouse(QEvent::MouseButtonRelease, rotaryMove, Qt::LeftButton, Qt::NoButton,
                        Qt::NoModifier);
        check(rotaryValue > 68 && rotaryValue < 90 &&
                  tabA->doc.undoStack()->count() == documentUndoCount &&
                  m_undoGroup->activeStack() == tabA->doc.undoStack(),
              "application-output rotary drag changed document undo history");
        outputDial->setValue(68);

        sendOutputMouse(QEvent::MouseButtonPress, outputCenter, Qt::LeftButton, Qt::LeftButton,
                        Qt::NoModifier);
        sendOutputMouse(QEvent::MouseMove, outputCenter + QPointF(0.0, -2.0), Qt::NoButton,
                        Qt::LeftButton, Qt::NoModifier);
        check(outputDial->value() == 68,
              "application-output linear drag ignored its press dead zone");
        sendOutputMouse(QEvent::MouseMove, outputCenter + QPointF(0.0, -11.0), Qt::NoButton,
                        Qt::LeftButton, Qt::NoModifier);
        sendOutputMouse(QEvent::MouseButtonRelease, outputCenter + QPointF(0.0, -11.0),
                        Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
        check(outputDial->value() == 72 && tabA->doc.undoStack()->count() == documentUndoCount &&
                  m_undoGroup->activeStack() == tabA->doc.undoStack(),
              "application-output linear drag changed document undo history");
        outputDial->setValue(68);
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
        m_tabs->setCurrentWidget(tabB->view);
        check(volSpin->value() == tabB->doc.cfg().masterVolume,
              "spinbox did not follow the tab switch");
        check(outputDial->value() == 37, "application-output dial changed with the active tab");
        check(m_audio.outputVolume() == 37,
              "application-output engine volume changed with the active tab");
        check(!tabB->doc.isDirty(), "tab switch leaked a volume edit into the other tab");
        m_tabs->setCurrentWidget(tabA->view);
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
                                    QStringLiteral(" "));
            spaceOverride.ignore();
            QApplication::sendEvent(volEdit, &spaceOverride);
            check(!spaceOverride.isAccepted(),
                  "volume spinbox claimed Space from the play/pause shortcut");
            QKeyEvent digitOverride(QEvent::ShortcutOverride, Qt::Key_5, Qt::NoModifier,
                                    QStringLiteral("5"));
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

        m_tabs->setCurrentWidget(tabA->view);
        chooseComboData(rootCombo, rootA, "A root is missing from the transport control");
        chooseComboData(scaleCombo, static_cast<int>(scaleA),
                        "A scale is missing from the transport control");
        highlightButton->click();
        check(tabA->view->scaleRoot() == rootA && tabA->view->scaleId() == scaleA &&
                  tabA->view->scaleHighlight() && !tabA->view->scaleFold() &&
                  highlightButton->isChecked() && !foldButton->isChecked(),
              "scale controls did not enable Highlight for the first tab");
        highlightButton->click();
        check(!tabA->view->scaleHighlight() && !tabA->view->scaleFold() &&
                  !highlightButton->isChecked() && !foldButton->isChecked(),
              "clicking active Highlight did not disable Highlight");
        highlightButton->click();
        m_tabs->setCurrentWidget(tabB->view);
        chooseComboData(rootCombo, rootB, "B root is missing from the transport control");
        chooseComboData(scaleCombo, static_cast<int>(scaleB),
                        "B scale is missing from the transport control");
        SongView *bView = tabB->view;
        const int originalTrack = bView->selectedTrack();
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
            bView->selectTrack(originalTrack);
            foldButton->click();
            check(bView->scaleRoot() == rootB && bView->scaleId() == scaleB &&
                      !bView->scaleHighlight() && bView->scaleFold() &&
                      rootCombo->currentData().toInt() == rootB &&
                      scaleCombo->currentData().toInt() == static_cast<int>(scaleB) &&
                      !highlightButton->isChecked() && foldButton->isChecked(),
                  "second tab did not retain its Fold scale control values");

            highlightButton->click();
            check(bView->scaleHighlight() && bView->scaleFold() && highlightButton->isChecked() &&
                      foldButton->isChecked(),
                  "Highlight and Fold could not be active together");
            highlightButton->click();
            check(!bView->scaleHighlight() && bView->scaleFold() && !highlightButton->isChecked() &&
                      foldButton->isChecked(),
                  "clicking active Highlight altered Fold");
            highlightButton->click();
            foldButton->click();
            check(bView->scaleHighlight() && !bView->scaleFold() && highlightButton->isChecked() &&
                      !foldButton->isChecked(),
                  "clicking active Fold altered Highlight");
            foldButton->click();
            check(bView->scaleHighlight() && bView->scaleFold() && highlightButton->isChecked() &&
                      foldButton->isChecked(),
                  "re-enabling Fold did not preserve Highlight");

            m_tabs->setCurrentWidget(tabA->view);
            check(rootCombo->currentData().toInt() == rootA &&
                      scaleCombo->currentData().toInt() == static_cast<int>(scaleA) &&
                      highlightButton->isChecked() && !foldButton->isChecked(),
                  "scale controls did not follow the first tab");
            m_tabs->setCurrentWidget(tabB->view);
            check(rootCombo->currentData().toInt() == rootB &&
                      scaleCombo->currentData().toInt() == static_cast<int>(scaleB) &&
                      highlightButton->isChecked() && foldButton->isChecked(),
                  "scale controls did not return to the second tab");

            bView->selectTrack(differentTrack);
            check(bView->scaleHighlight() && bView->scaleFold() && highlightButton->isChecked() &&
                      foldButton->isChecked(),
                  "a selected-track change altered active Highlight or Fold");
            bView->selectTrack(originalTrack);
            check(bView->scaleHighlight() && bView->scaleFold(),
                  "returning to the previous track altered active Highlight or Fold");

            bView->setScaleHighlight(false);
            bView->setScaleFold(false);
            bView->selectTrack(differentTrack);
            bView->selectTrack(originalTrack);
            check(!bView->scaleHighlight() && !bView->scaleFold(),
                  "track change enabled a disabled scale feature");
            bView->setScaleHighlight(true);
            bView->selectTrack(differentTrack);
            check(bView->scaleHighlight() && !bView->scaleFold(),
                  "track change altered independent Highlight");
            bView->selectTrack(originalTrack);
            bView->setScaleFold(true);
            bView->selectTrack(0);
            bView->deleteTrack(0);
            check(bView->scaleHighlight() && bView->scaleFold(),
                  "deleting the selected track altered active Highlight or Fold");
            tabB->doc.undoStack()->undo();

            const int remappedTrack = std::max(originalTrack, differentTrack);
            bView->selectTrack(remappedTrack);
            bView->setScaleHighlight(true);
            bView->setScaleFold(true);
            bView->deleteTrack(0);
            check(bView->scaleHighlight() && bView->scaleFold(),
                  "deleting a lower track altered active Highlight or Fold during an index remap");
            tabB->doc.undoStack()->undo();
            check(bView->scaleHighlight() && bView->scaleFold(),
                  "undoing a lower-track deletion altered active Highlight or Fold during an index "
                  "remap");
            if (addedTrack)
                tabB->doc.undoStack()->undo();
            check(!tabB->doc.isDirty(), "scale routing check left the second tab dirty");

            m_tabs->setCurrentWidget(tabA->view);
            check(tabA->view->scaleRoot() == rootA && tabA->view->scaleId() == scaleA &&
                      tabA->view->scaleHighlight() && !tabA->view->scaleFold(),
                  "inactive first-tab scale state was not preserved");
            m_tabs->setCurrentWidget(tabB->view);
            check(tabB->view->scaleRoot() == rootB && tabB->view->scaleId() == scaleB &&
                      tabB->view->scaleHighlight() && tabB->view->scaleFold(),
                  "inactive second-tab scale state was not preserved");
        }
    }

    // 6. Re-opening an already open song focuses its tab, no duplicates.
    loadSongByLabel(songB, /*newTab=*/true);
    check(m_tabs->count() == 2 && m_active == tabB,
          "re-opening an open song did not just focus its tab");

    // 7. Closing a tab hands the engine to the survivor.
    closeTab(m_tabs->indexOf(tabB->view));
    check(m_tabs->count() == 1 && m_active == tabA && m_audio.timeline() == tabA->timeline.get(),
          "closing the active tab did not fall back to the other tab");
    check(sessionForLabel(songB) == nullptr, "closed tab's session lingered");

    // 8. Plain activation replaces the current tab's song (tab count
    // unchanged) — the pre-tabs behavior.
    loadSongByLabel(songB);
    tabB = m_active;
    check(m_tabs->count() == 1 && tabB && tabB->doc.label() == songB &&
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
    check(m_tabs->count() == 1 && m_active == tabB && tabB->doc.undoStack()->count() == 0,
          "re-activating the open song did not reload it in place");

    // 9. Closing the final playing tab restores the no-tab UI cadence.
    m_audio.play();
    wait(200);
    synchronizePlayhead();
    check(m_uiTimer->interval() == 100, "final-tab close precondition is not playback cadence");
    closeTab(m_tabs->indexOf(tabB->view));
    check(m_tabs->count() == 0 && m_active == nullptr && m_uiTimer->interval() == 500,
          "closing final playing tab did not restore 500 ms UI cadence");
    if (haveScaleControls) {
        check(!rootCombo->isEnabled() && !scaleCombo->isEnabled() &&
                  !highlightButton->isEnabled() && !foldButton->isEnabled(),
              "scale controls remained enabled after closing the final tab");
    }

    // Reopen through the normal lifecycle so the restoration contract below
    // still persists both tabs with song A active.
    loadSongByLabel(songB);
    tabB = m_active;

    // 10. The open-tab set is recorded for restoreSession.
    loadSongByLabel(songA, /*newTab=*/true);
    tabA = m_active;
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
            check(saveSession(*tabA), "shared-voicegroup save failed");
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
            f.setFileTime(QDateTime::currentDateTime().addSecs(2),
                          QFileDevice::FileModificationTime);
            f.close();
            const LoadedVoiceGroup *before = tabB->voicegroup;
            m_tabs->setCurrentWidget(tabB->view);
            check(tabB->voicegroup != nullptr && tabB->voicegroup != before,
                  "clean tab did not reload its changed voicegroup file");
            check(tabB->vgSource && !tabB->vgSource->dirty(),
                  "voicegroup auto-refresh left the source dirty");
        } else {
            std::printf("tabcheck: note: voicegroup file not writable, "
                        "auto-refresh check skipped\n");
            m_tabs->setCurrentWidget(tabB->view);
        }
    } else {
        std::printf("tabcheck: note: no editable voicegroup source, "
                    "auto-refresh check skipped\n");
        m_tabs->setCurrentWidget(tabB->view);
    }

    std::printf("tabcheck: %s (%d failures)\n", failures ? "FAIL" : "PASS", failures);
    return failures == 0;
}

int runTabCheck(const QString &projectRoot, const QString &songA, const QString &songB)
{
    // Redirected settings: the user's real session is never touched.
    QTemporaryDir settingsDir;
    if (!settingsDir.isValid()) {
        std::fprintf(stderr, "tabcheck: no temp dir for settings\n");
        return 1;
    }
    QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, settingsDir.path());
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, settingsDir.path());
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
        auto *tabs = window.findChild<QTabWidget *>();
        check(tabs && tabs->count() == 2, "relaunch did not restore both tabs");
        if (tabs && tabs->count() == 2) {
            check(tabs->tabText(0) == songB && tabs->tabText(1) == songA,
                  "restored tabs are not in the saved order");
        }
        check(window.windowTitle().startsWith(songB),
              "relaunch did not re-activate the last active tab");
        auto *outputDial = window.findChild<QDial *>(QStringLiteral("transportOutputVolume"));
        check(outputDial && outputDial->value() == 37,
              "relaunch did not restore application-output volume");
    }
    if (failures == 0)
        std::printf("tabcheck: restore PASS\n");
    return failures == 0 ? 0 : 1;
}
