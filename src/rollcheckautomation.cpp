#include "rollcheckautomation.h"

#include <QAction>
#include <QApplication>
#include <QCoreApplication>
#include <QDialog>
#include <QEvent>
#include <QFile>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QKeyEvent>
#include <QLabel>
#include <QMenu>
#include <QMouseEvent>
#include <QStackedWidget>
#include <QTemporaryDir>
#include <QTimer>
#include <QWidget>
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <utility>
#include <vector>

#include "core/songdocument.h"
#include "project/decompproject.h"
#include "ui/songview.h"
#include "ui/velocityarea.h"
#include "ui/theme/themeruntime.h"
#include "ui/velocityaxis.h"
#include "ui/viewsidecar.h"

namespace {

constexpr uint8_t kAudibleLaneCcs[] = {0x01, 0x07, 0x0A, 0x14, 0x15};

void processUiEvents() { QCoreApplication::processEvents(); }

void sendMouse(QWidget *widget, QEvent::Type type, QPoint position,
               Qt::MouseButton button, Qt::MouseButtons buttons,
               Qt::KeyboardModifiers modifiers = Qt::NoModifier) {
  QMouseEvent event(type, QPointF(position),
                    QPointF(widget->mapToGlobal(position)), button, buttons,
                    modifiers);
  QCoreApplication::sendEvent(widget, &event);
}

void click(QWidget *widget, QPoint position) {
  sendMouse(widget, QEvent::MouseButtonPress, position, Qt::LeftButton,
            Qt::LeftButton);
  sendMouse(widget, QEvent::MouseButtonRelease, position, Qt::LeftButton,
            Qt::NoButton);
}

void sendKey(QWidget *widget, int key, Qt::KeyboardModifiers modifiers) {
  QKeyEvent press(QEvent::KeyPress, key, modifiers);
  QCoreApplication::sendEvent(widget, &press);
  QKeyEvent release(QEvent::KeyRelease, key, modifiers);
  QCoreApplication::sendEvent(widget, &release);
}

QImage captureLogical(QWidget &widget) {
  QImage image(widget.size(), QImage::Format_ARGB32_Premultiplied);
  image.fill(Qt::transparent);
  widget.render(&image);
  return image;
}

int changedPixelCount(const QImage &before, const QImage &after,
                      const QRect &region) {
  int changedPixels = 0;
  const QRect compared =
      region.intersected(before.rect()).intersected(after.rect());
  for (int y = compared.top(); y <= compared.bottom(); ++y) {
    for (int x = compared.left(); x <= compared.right(); ++x) {
      if (before.pixel(x, y) != after.pixel(x, y))
        ++changedPixels;
    }
  }
  return changedPixels;
}

int colorPixelCount(const QImage &image, const QRect &region,
                    const QColor &color) {
  int matchingPixels = 0;
  const QRect compared = region.intersected(image.rect());
  for (int y = compared.top(); y <= compared.bottom(); ++y) {
    for (int x = compared.left(); x <= compared.right(); ++x) {
      if (image.pixel(x, y) == color.rgba())
        ++matchingPixels;
    }
  }
  return matchingPixels;
}

bool separatorClickOpenedMenu(QWidget *widget, QPoint position,
                              Qt::MouseButton button) {
  bool opened = false;
  QTimer menuPoll;
  menuPoll.setInterval(0);
  QObject::connect(&menuPoll, &QTimer::timeout, [&] {
    if (QWidget *popup = QApplication::activePopupWidget()) {
      opened = true;
      popup->close();
    }
  });
  menuPoll.start();
  sendMouse(widget, QEvent::MouseButtonPress, position, button, button);
  sendMouse(widget, QEvent::MouseButtonRelease, position, button, Qt::NoButton);
  processUiEvents();
  menuPoll.stop();
  return opened;
}

bool prepareKnownTracks(const SongInfo &song, int exactTrackCount,
                        const QString &scenario, SongDocument &document,
                        QStringList &failures) {
  QString error;
  if (!document.load(song, &error)) {
    failures.append(
        QStringLiteral("could not load song for %1: %2").arg(scenario, error));
    return false;
  }
  while (document.engineTrackCount() > 0) {
    const int before = document.engineTrackCount();
    document.deleteTrack(before - 1);
    if (document.engineTrackCount() != before - 1) {
      failures.append(
          QStringLiteral("could not clear tracks for %1").arg(scenario));
      return false;
    }
  }
  for (int track = 0; track < exactTrackCount; ++track) {
    if (document.addTrack(5 + track) != track) {
      failures.append(QStringLiteral("could not create %1 tracks for %2")
                          .arg(exactTrackCount)
                          .arg(scenario));
      return false;
    }
  }
  document.undoStack()->clear();
  if (document.engineTrackCount() != exactTrackCount) {
    failures.append(QStringLiteral("%1 did not have exactly %2 tracks")
                        .arg(scenario)
                        .arg(exactTrackCount));
    return false;
  }
  return true;
}

void showOffscreen(SongView &view) {
  view.resize(1280, 800);
  view.setAttribute(Qt::WA_DontShowOnScreen);
  view.show();
  processUiEvents();
  (void)captureLogical(view);
  processUiEvents();
}

void checkVoicePreview(const SongInfo &song, QStringList &failures) {
  SongDocument document;
  if (!prepareKnownTracks(song, 1, QStringLiteral("voice preview"), document,
                          failures))
    return;
  auto timeline = document.buildTimeline(48000.0);
  SongView view;
  view.setSong(timeline.get(), nullptr);
  view.setDocument(&document);
  QObject::connect(&document, &SongDocument::documentChanged, &view, [&] {
    auto rebuilt = document.buildTimeline(48000.0);
    view.updateSong(rebuilt.get());
    timeline = std::move(rebuilt);
  });
  view.setGridMinDenom(4);
  showOffscreen(view);
  auto *automationArea =
      view.findChild<QWidget *>(QStringLiteral("automationArea"));
  if (!automationArea || automationArea->width() <= songview::kGutterW ||
      automationArea->height() <= 0) {
    failures.append("automation area not found or not laid out");
    return;
  }
  constexpr int track = 0;
  constexpr int baseProgram = 5;
  constexpr int changedProgram = 6;
  const uint64_t voiceTick =
      std::max<uint64_t>(1, uint64_t(document.ticksPerClock()) * 24);
  view.setEditCursorTick(0);
  if (view.currentProgram(track) != baseProgram)
    failures.append("voice label did not begin at the known track program");
  document.addLanePoint(track, DOC_CC_VOICE, voiceTick, changedProgram);
  if (view.currentProgram(track) != baseProgram)
    failures.append("voice label at the start changed before the voice event");
  view.setEditCursorTick(voiceTick);
  if (view.currentProgram(track) != changedProgram)
    failures.append(
        "voice label did not follow the edit cursor past the change");
  view.setEditCursorTick(0);
  view.setPlayheadSample(timeline->sampleForTick(voiceTick), true);
  if (view.currentProgram(track) != changedProgram)
    failures.append("voice label did not follow the playing playhead");
  view.setPlayheadSample(0, false);
  if (view.currentProgram(track) != baseProgram)
    failures.append("voice label did not return to the edit cursor after stop");

  const int laneHeight = view.viewState().laneHeight;
  const int voiceRowTop = laneHeight;
  const int voiceRowCenter = voiceRowTop + laneHeight / 2;
  int cursorX = -1;
  int insertionX = -1;
  uint64_t insertionTick = 0;
  for (int candidateX = songview::kGutterW + 24;
       candidateX < automationArea->width() - 24; candidateX += 7) {
    const double rawTick =
        std::max(0.0, view.tickAtContentX(candidateX - songview::kGutterW));
    const uint64_t candidateTick = view.snapTick(rawTick);
    const int candidateInsertionX =
        songview::kGutterW + view.contentX(double(candidateTick));
    bool nearVoiceChange = false;
    for (const VoiceChange &change : view.model().voices) {
      if (change.track != track)
        continue;
      const int changeX =
          songview::kGutterW + view.contentX(double(change.tick));
      if (std::abs(changeX - candidateX) < 12 ||
          std::abs(changeX - candidateInsertionX) < 12) {
        nearVoiceChange = true;
        break;
      }
    }
    DocLanePoint existingChange;
    if (!nearVoiceChange &&
        !document.findLanePoint(track, DOC_CC_VOICE, candidateTick,
                                &existingChange)) {
      cursorX = candidateInsertionX;
      insertionX = candidateInsertionX;
      insertionTick = candidateTick;
      break;
    }
  }
  if (cursorX < 0) {
    failures.append("no empty visible voice-row position for hover");
    return;
  }
  constexpr int markerHitRadius = 9;
  const auto voiceMarkerX = [&](uint64_t tick) {
    return songview::kGutterW + view.contentX(double(tick));
  };
  uint64_t leftMarkerTick = insertionTick;
  while (leftMarkerTick > 0 &&
         insertionX - voiceMarkerX(leftMarkerTick) < markerHitRadius)
    --leftMarkerTick;
  uint64_t rightMarkerTick = insertionTick;
  while (voiceMarkerX(rightMarkerTick) - insertionX < markerHitRadius)
    ++rightMarkerTick;
  const int previewVoiceProgram = view.currentProgram(track);
  const int undoIndexBeforePreviewMarkers = document.undoStack()->index();
  document.addLanePoint(track, DOC_CC_VOICE, leftMarkerTick,
                        previewVoiceProgram);
  document.addLanePoint(track, DOC_CC_VOICE, rightMarkerTick,
                        previewVoiceProgram);
  const QRect voiceRow(songview::kGutterW, voiceRowTop,
                       automationArea->width() - songview::kGutterW,
                       laneHeight);
  QEvent leaveAutomation(QEvent::Leave);
  QCoreApplication::sendEvent(automationArea, &leaveAutomation);
  processUiEvents();
  const QImage withoutPreview = captureLogical(*automationArea);
  // Project marker centers for the logical paint device, rather than
  // truncating their fractional content coordinates.
  const auto captureDpr = withoutPreview.devicePixelRatioF();
  const int leftMarkerX = int(
      view.displayX(double(leftMarkerTick), songview::kGutterW, captureDpr));
  const int rightMarkerX = int(
      view.displayX(double(rightMarkerTick), songview::kGutterW, captureDpr));
  sendMouse(automationArea, QEvent::MouseMove, QPoint(cursorX, voiceRowCenter),
            Qt::NoButton, Qt::NoButton);
  processUiEvents();
  const QImage withPreview = captureLogical(*automationArea);
  if (changedPixelCount(withoutPreview, withPreview, voiceRow) == 0) {
    failures.append("voice-row hover did not paint an insertion preview");
  } else {
    const QRect leftOfMarkers(voiceRow.left(), voiceRow.top(),
                              std::max(0, leftMarkerX - voiceRow.left() - 2),
                              voiceRow.height());
    const QRect rightOfMarkers(rightMarkerX + 2, voiceRow.top(),
                               std::max(0, voiceRow.right() - rightMarkerX - 1),
                               voiceRow.height());
    if (changedPixelCount(withoutPreview, withPreview, leftOfMarkers) +
            changedPixelCount(withoutPreview, withPreview, rightOfMarkers) ==
        0) {
      failures.append("voice identity disappeared between close markers");
    }
    constexpr int markerStrokeWidth = 2;
    const QRect leftMarkerStroke(leftMarkerX - markerStrokeWidth / 2,
                                 voiceRow.top() + 4, markerStrokeWidth,
                                 voiceRow.height() - 8);
    const QRect rightMarkerStroke(rightMarkerX - markerStrokeWidth / 2,
                                  voiceRow.top() + 4, markerStrokeWidth,
                                  voiceRow.height() - 8);
    const QColor markerColor = SongView::trackColor(track);
    const int leftPixelsBefore =
        colorPixelCount(withoutPreview, leftMarkerStroke, markerColor);
    const int leftPixelsAfter =
        colorPixelCount(withPreview, leftMarkerStroke, markerColor);
    const int rightPixelsBefore =
        colorPixelCount(withoutPreview, rightMarkerStroke, markerColor);
    const int rightPixelsAfter =
        colorPixelCount(withPreview, rightMarkerStroke, markerColor);
    if (leftPixelsAfter == 0 || leftPixelsAfter < leftPixelsBefore ||
        rightPixelsAfter == 0 || rightPixelsAfter < rightPixelsBefore) {
      failures.append(
          QStringLiteral("voice preview obscured an adjacent marker "
                         "(left %1/%2, right %3/%4)")
              .arg(leftPixelsAfter)
              .arg(leftPixelsBefore)
              .arg(rightPixelsAfter)
              .arg(rightPixelsBefore));
    }
  }
  sendMouse(automationArea, QEvent::MouseMove,
            QPoint(cursorX, voiceRow.bottom()), Qt::NoButton, Qt::NoButton);
  processUiEvents();
  const QImage overResizeHandle = captureLogical(*automationArea);
  if (changedPixelCount(withoutPreview, overResizeHandle, voiceRow) != 0)
    failures.append("voice-row preview remained over a resize handle");
  sendMouse(automationArea, QEvent::MouseMove, QPoint(cursorX, voiceRowCenter),
            Qt::NoButton, Qt::NoButton);
  processUiEvents();
  int expectedVoiceProgram = 0;
  for (const VoiceChange &change : view.model().voices) {
    if (change.tick > insertionTick)
      break;
    if (change.track == track)
      expectedVoiceProgram = change.program;
  }
  bool pickerAccepted = false;
  QTimer pickerPoll;
  pickerPoll.setInterval(0);
  QObject::connect(&pickerPoll, &QTimer::timeout, [&] {
    if (QDialog *dialog = view.findChild<QDialog *>()) {
      pickerAccepted = true;
      dialog->accept();
    }
  });
  pickerPoll.start();
  click(automationArea, QPoint(cursorX, voiceRowCenter));
  pickerPoll.stop();
  processUiEvents();
  DocLanePoint insertedChange;
  if (!pickerAccepted ||
      !document.findLanePoint(track, DOC_CC_VOICE, insertionTick,
                              &insertedChange) ||
      insertedChange.value != expectedVoiceProgram) {
    failures.append("voice-row click disagreed with its hover preview");
  } else {
    QCoreApplication::sendEvent(automationArea, &leaveAutomation);
    processUiEvents();
    const QImage markerWithoutHover = captureLogical(*automationArea);
    sendMouse(automationArea, QEvent::MouseMove,
              QPoint(insertionX, voiceRowCenter), Qt::NoButton, Qt::NoButton);
    processUiEvents();
    const QImage markerWithHover = captureLogical(*automationArea);
    if (changedPixelCount(markerWithoutHover, markerWithHover, voiceRow) != 0)
      failures.append("insert preview remained over an existing voice marker");
  }
  while (document.undoStack()->index() > undoIndexBeforePreviewMarkers)
    document.undoStack()->undo();
  processUiEvents();
}

void checkEditorDrawerAndLanes(const SongInfo &song, QStringList &failures) {
  SongDocument document;
  if (!prepareKnownTracks(song, 1, QStringLiteral("editor drawer"), document,
                          failures))
    return;
  const uint32_t clock = std::max<uint32_t>(1, document.ticksPerClock());
  const uint64_t noteTick = uint64_t(clock) * 8;
  constexpr uint8_t noteKey = 60;
  document.addNote(0, noteTick, noteKey, clock * 4, 100);
  document.undoStack()->clear();
  auto timeline = document.buildTimeline(48000.0);
  SongView view;
  view.setSong(timeline.get(), nullptr);
  view.setDocument(&document);
  QObject::connect(&document, &SongDocument::documentChanged, &view, [&] {
    auto rebuilt = document.buildTimeline(48000.0);
    view.updateSong(rebuilt.get());
    timeline = std::move(rebuilt);
  });
  view.setGridMinDenom(4);
  showOffscreen(view);
  auto *roll = view.findChild<QWidget *>(QStringLiteral("pianoRoll"));
  auto *automationArea =
      view.findChild<QWidget *>(QStringLiteral("automationArea"));
  auto *velocityArea = dynamic_cast<songview::VelocityArea *>(
      view.findChild<QWidget *>(QStringLiteral("velocityArea")));
  auto *drawer =
      view.findChild<QStackedWidget *>(QStringLiteral("editorDrawer"));
  auto *automationTab =
      view.findChild<QWidget *>(QStringLiteral("automationDrawerTab"));
  auto *velocityTab =
      view.findChild<QWidget *>(QStringLiteral("velocityDrawerTab"));
  auto *velocityAction =
      view.findChild<QAction *>(QStringLiteral("velocityDrawerAction"));
  auto *headerScroll =
      view.findChild<QWidget *>(QStringLiteral("trackHeaderScroll"));
  auto *drawerHandle =
      view.findChild<QWidget *>(QStringLiteral("editorDrawerHandle"));
  if (!roll || !automationArea || !velocityArea || !drawer || !automationTab ||
      !velocityTab || !velocityAction || !headerScroll || !drawerHandle) {
    failures.append("editor drawer controls not found");
    return;
  }
  if (!velocityAction->icon().isNull() ||
      velocityTab->findChild<QLabel *>(QString(), Qt::FindDirectChildrenOnly)) {
    failures.append("Velocity drawer tab is not text-only");
  }
  if (headerScroll->geometry() != headerScroll->parentWidget()->rect())
    failures.append("editor drawer shortened the track-header viewport");
  if (drawerHandle->geometry().x() != songview::kHeaderW ||
      drawerHandle->geometry().right() !=
          drawerHandle->parentWidget()->width() - 1) {
    failures.append("editor drawer divider extends underneath its tabs");
  }
  const SongView::ViewState initialState = view.viewState();
  const QList<int> openSizes = initialState.splitterSizes;
  if (!initialState.drawerVisible ||
      initialState.drawerPage != SongView::DrawerPage::Automations ||
      openSizes.size() != 2 || openSizes[0] <= 0 || openSizes[1] <= 0) {
    failures.append("editor drawer did not begin open with positive sizes");
  }
  const int expectedDrawerHeight = drawer->parentWidget()->height() / 5;
  if (openSizes.size() == 2 && openSizes[1] != expectedDrawerHeight) {
    failures.append(
        QStringLiteral("editor drawer default height was %1, expected %2")
            .arg(openSizes[1])
            .arg(expectedDrawerHeight));
  }

  // VelocityArea is an editor surface: make its page current and render it
  // before delivering a representative shared command. The offscreen harness
  // cannot activate a native window, so focusability is checked from the
  // widget contract and the event is delivered to that visible surface.
  view.setDrawerPage(SongView::DrawerPage::Velocity);
  view.setDrawerVisible(true);
  (void)captureLogical(view);
  processUiEvents();
  const bool velocityPageReady = drawer->currentWidget() == velocityArea &&
                                 velocityArea->isVisibleTo(&view) &&
                                 !velocityArea->size().isEmpty();
  if (!velocityPageReady)
    failures.append("velocity editor page was not visible with positive size");
  if (velocityArea->focusPolicy() == Qt::NoFocus)
    failures.append("velocity editor is not focusable");
  QWidget *const velocityKeyTarget = velocityArea;

  const uint64_t middleTick = noteTick + uint64_t(clock) * 8;
  const uint64_t minimumTick = noteTick + uint64_t(clock) * 16;
  constexpr uint8_t middleKey = noteKey + 1;
  constexpr uint8_t minimumKey = noteKey + 2;
  constexpr uint8_t middleVelocity = 60;
  constexpr uint8_t minimumVelocity = 20;
  document.addNote(0, middleTick, middleKey, clock * 4, middleVelocity);
  document.addNote(0, minimumTick, minimumKey, clock * 4, minimumVelocity);
  document.undoStack()->clear();
  const std::vector<SongView::NoteId> velocityLabelSelection{
      {uint32_t(noteTick), noteKey},
      {uint32_t(middleTick), middleKey},
      {uint32_t(minimumTick), minimumKey},
  };
  view.setSelection(velocityLabelSelection);
  processUiEvents();
  const QImage selectedVelocityLabels = captureLogical(*velocityArea);
  const auto selectedTextPixelsAt = [&](int velocity) {
    const int centerY =
        qRound(songview::velocityToY(velocity, velocityArea->height()));
    const QRect labelRegion(songview::kGutterW - 46, centerY - 12, 35, 24);
    return colorPixelCount(
        selectedVelocityLabels, labelRegion,
        themes::color(themes::Role::item_selected_background));
  };
  if (selectedTextPixelsAt(minimumVelocity) == 0 ||
      selectedTextPixelsAt(100) == 0) {
    failures.append(
        "velocity graduation omitted a selected minimum or maximum value");
  }
  if (selectedTextPixelsAt(middleVelocity) != 0) {
    failures.append(
        "velocity graduation rendered a selected value between the extrema");
  }

  // One Delete press is the representative shared note command. Assert that
  // exact command count, undo it, and clear the local stack so the fixture is
  // net-neutral before the cosmetic drawer checks continue.
  view.setSelection({SongView::NoteId{uint32_t(noteTick), noteKey}});
  const QByteArray midiBeforeSharedDelete = document.smf().write();
  const int undoCountBeforeSharedDelete = document.undoStack()->count();
  const int undoIndexBeforeSharedDelete = document.undoStack()->index();
  constexpr int expectedSharedDeleteCommands = 1;
  sendKey(velocityKeyTarget, Qt::Key_Delete, Qt::NoModifier);
  processUiEvents();
  DocNote deletedNote;
  if (document.findNote(0, noteTick, noteKey, &deletedNote))
    failures.append("VelocityArea did not route the shared Delete command");
  const int sharedDeleteCommands =
      document.undoStack()->count() - undoCountBeforeSharedDelete;
  if (sharedDeleteCommands != expectedSharedDeleteCommands ||
      document.undoStack()->index() !=
          undoIndexBeforeSharedDelete + expectedSharedDeleteCommands) {
    failures.append(
        QStringLiteral("VelocityArea Delete pushed %1 undo commands; expected "
                       "%2")
            .arg(sharedDeleteCommands)
            .arg(expectedSharedDeleteCommands));
  }
  while (document.undoStack()->index() > undoIndexBeforeSharedDelete)
    document.undoStack()->undo();
  processUiEvents();
  DocNote restoredNote;
  if (!document.findNote(0, noteTick, noteKey, &restoredNote) ||
      document.smf().write() != midiBeforeSharedDelete) {
    failures.append("undoing the VelocityArea Delete command did not restore "
                    "the fixture");
  }
  document.undoStack()->clear();
  velocityArea->setFocus(Qt::OtherFocusReason);
  sendKey(velocityArea, Qt::Key_A, Qt::NoModifier);
  processUiEvents();
  if (!view.drawerVisible() ||
      view.drawerPage() != SongView::DrawerPage::Automations) {
    failures.append("A from VelocityArea did not route to Automations");
  }
  view.setDrawerPage(SongView::DrawerPage::Velocity);
  view.setDrawerVisible(true);
  processUiEvents();
  velocityArea->setFocus(Qt::OtherFocusReason);
  sendKey(velocityArea, Qt::Key_V, Qt::NoModifier);
  processUiEvents();
  if (view.drawerVisible() ||
      view.drawerPage() != SongView::DrawerPage::Velocity) {
    failures.append("V from VelocityArea did not hide the Velocity drawer");
  }

  // Drawer shortcuts are window commands, not editor-surface commands. They
  // must still work when focus is on a non-text sibling of SongView.
  QWidget shortcutWindow;
  shortcutWindow.resize(640, 360);
  SongView shortcutView(&shortcutWindow);
  shortcutView.setGeometry(shortcutWindow.rect());
  QWidget shortcutProbe(&shortcutWindow);
  shortcutProbe.setFocusPolicy(Qt::StrongFocus);
  shortcutProbe.resize(1, 1);
  shortcutWindow.show();
  shortcutWindow.activateWindow();
  shortcutProbe.show();
  shortcutProbe.raise();
  processUiEvents();
  shortcutView.setDrawerVisible(false);
  shortcutProbe.setFocus(Qt::OtherFocusReason);
  sendKey(&shortcutProbe, Qt::Key_A, Qt::NoModifier);
  processUiEvents();
  if (!shortcutView.drawerVisible() ||
      shortcutView.drawerPage() != SongView::DrawerPage::Automations) {
    failures.append("A did not open the drawer from window focus");
  }
  shortcutProbe.setFocus(Qt::OtherFocusReason);
  sendKey(&shortcutProbe, Qt::Key_V, Qt::NoModifier);
  processUiEvents();
  if (!shortcutView.drawerVisible() ||
      shortcutView.drawerPage() != SongView::DrawerPage::Velocity) {
    failures.append("V did not open its drawer page from window focus");
  }
  shortcutWindow.close();
  view.setDrawerPage(SongView::DrawerPage::Automations);
  view.setDrawerVisible(true);
  processUiEvents();

  const QByteArray midiBeforeDrawer = document.smf().write();
  const int undoCountBeforeDrawer = document.undoStack()->count();
  const int rollHeightBeforeDrawer = roll->height();
  const int headerHeightBeforeDrawer = headerScroll->height();
  click(automationTab, automationTab->rect().center());
  processUiEvents();
  const SongView::ViewState tabHiddenState = view.viewState();
  if (view.drawerVisible() || !drawer->isHidden() ||
      tabHiddenState.drawerVisible) {
    failures.append("Automations tab did not hide the editor drawer");
  }
  if (!drawerHandle->isHidden())
    failures.append("editor drawer divider remained after closing the drawer");
  if (roll->height() != rollHeightBeforeDrawer ||
      headerScroll->height() != headerHeightBeforeDrawer) {
    failures.append("closing the editor overlay changed SongView flow");
  }
  if (tabHiddenState.splitterSizes != openSizes)
    failures.append("hidden editor drawer forgot its expanded sizes");
  if (automationTab->isHidden())
    failures.append("hiding the editor drawer also hid its Automations tab");
  roll->setFocus(Qt::OtherFocusReason);
  sendKey(roll, Qt::Key_A, Qt::NoModifier);
  processUiEvents();
  if (!view.drawerVisible() || drawer->isHidden())
    failures.append("A did not reopen the automation drawer");
  if (drawerHandle->isHidden())
    failures.append("A did not restore the editor drawer divider");
  if (roll->height() != rollHeightBeforeDrawer ||
      headerScroll->height() != headerHeightBeforeDrawer) {
    failures.append("opening the editor overlay changed SongView flow");
  }
  if (view.viewState().splitterSizes != openSizes)
    failures.append("reopening the drawer did not restore its sizes");
  view.setEventListVisible(true);
  auto *eventTable =
      view.findChild<QWidget *>(QStringLiteral("eventListTable"));
  if (!eventTable) {
    failures.append("event list table not found for drawer shortcut check");
  } else {
    eventTable->setFocus(Qt::OtherFocusReason);
    const bool drawerVisibleFromEventList = view.drawerVisible();
    const SongView::DrawerPage drawerPageFromEventList = view.drawerPage();
    sendKey(eventTable, Qt::Key_A, Qt::NoModifier);
    processUiEvents();
    if (view.drawerVisible() != drawerVisibleFromEventList ||
        view.drawerPage() != drawerPageFromEventList) {
      failures.append("A changed the drawer from the event list");
    }
  }
  view.setEventListVisible(false);
  roll->setFocus(Qt::OtherFocusReason);
  sendKey(roll, Qt::Key_A, Qt::NoModifier);
  processUiEvents();
  const SongView::ViewState hiddenState = view.viewState();
  if (view.drawerVisible() || hiddenState.drawerVisible)
    failures.append("A did not hide the automation drawer");
  QTemporaryDir drawerSidecarRoot;
  SongView::ViewState restoredDrawerState;
  const QString drawerSidecarSong = QStringLiteral("rollcheck_editor_drawer");
  const bool drawerRoundTripped =
      drawerSidecarRoot.isValid() &&
      ViewSidecar::save(drawerSidecarRoot.path(), drawerSidecarSong,
                        hiddenState) &&
      ViewSidecar::load(drawerSidecarRoot.path(), drawerSidecarSong,
                        &restoredDrawerState);
  view.setDrawerVisible(true);
  if (!drawerRoundTripped) {
    failures.append("editor drawer state did not persist through its sidecar");
  } else {
    view.applyViewState(restoredDrawerState);
    if (view.drawerVisible() || restoredDrawerState.drawerVisible ||
        view.viewState().splitterSizes != openSizes) {
      failures.append("sidecar round trip lost the hidden drawer or its size");
    }
  }
  view.setDrawerVisible(true);
  if (!view.drawerVisible() || view.viewState().splitterSizes != openSizes)
    failures.append("drawer did not reopen at its sidecar-restored size");
  if (document.smf().write() != midiBeforeDrawer ||
      document.undoStack()->count() != undoCountBeforeDrawer) {
    failures.append("editor drawer visibility changed MIDI or undo state");
  }

  int laneCc = -1;
  bool addedEmptyLane = false;
  for (const AutoLane &lane : view.model().lanes) {
    if (lane.track == 0 && !view.laneHidden(lane.track, lane.cc)) {
      laneCc = lane.cc;
      break;
    }
  }
  if (laneCc < 0) {
    for (uint8_t cc : kAudibleLaneCcs) {
      if (!view.model().findLane(0, cc)) {
        laneCc = cc;
        view.addEmptyLane(0, cc);
        addedEmptyLane = true;
        break;
      }
    }
  }
  if (laneCc < 0) {
    failures.append(
        "no automation lane available for separator and hide checks");
    return;
  }
  const uint8_t checkedLaneCc = uint8_t(laneCc);
  const SongView::ViewState laneState = view.viewState();
  const int tempoHeight =
      laneState.rowStates.value(SongView::AutomationRowId::tempo())
          .height.value_or(laneState.laneHeight);
  const int voiceHeight =
      laneState.rowStates.value(SongView::AutomationRowId::voice(0))
          .height.value_or(laneState.laneHeight);
  const int controllerHeight =
      laneState.rowStates
          .value(SongView::AutomationRowId::controller(0, checkedLaneCc))
          .height.value_or(laneState.laneHeight);
  const int separatorY = tempoHeight + voiceHeight + controllerHeight - 1;
  const int undoCountBeforeSeparators = document.undoStack()->count();
  const QByteArray midiBeforeSeparators = document.smf().write();
  if (separatorClickOpenedMenu(automationArea, QPoint(80, separatorY),
                               Qt::LeftButton)) {
    failures.append("left-clicking a lane separator opened a menu");
  }
  if (separatorClickOpenedMenu(automationArea, QPoint(80, separatorY),
                               Qt::RightButton)) {
    failures.append("right-clicking a lane separator opened a menu");
  }
  if (document.undoStack()->count() != undoCountBeforeSeparators ||
      document.smf().write() != midiBeforeSeparators) {
    failures.append("separator clicks changed MIDI or undo state");
  }

  const QByteArray documentBeforeHide = document.smf().write();
  const int heightBeforeHide = automationArea->minimumHeight();
  view.hideLane(0, checkedLaneCc);
  if (!view.laneHidden(0, checkedLaneCc) ||
      view.model().findLane(0, checkedLaneCc) == nullptr ||
      automationArea->minimumHeight() >= heightBeforeHide ||
      document.smf().write() != documentBeforeHide) {
    failures.append("hiding a lane changed its model data or kept its row");
  }
  bool showActionChosen = false;
  QTimer menuPoll;
  menuPoll.setInterval(0);
  QObject::connect(&menuPoll, &QTimer::timeout, [&] {
    QMenu *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
    if (!menu)
      return;
    for (QAction *action : menu->actions()) {
      if (!action->text().startsWith(QStringLiteral("Show:")))
        continue;
      showActionChosen = true;
      click(menu, menu->actionGeometry(action).center());
      return;
    }
    menu->close();
  });
  menuPoll.start();
  const QPoint addLanePosition(songview::kGutterW + 10,
                               automationArea->minimumHeight() - 10);
  sendMouse(automationArea, QEvent::MouseButtonPress, addLanePosition,
            Qt::RightButton, Qt::RightButton);
  menuPoll.stop();
  sendMouse(automationArea, QEvent::MouseButtonRelease, addLanePosition,
            Qt::RightButton, Qt::NoButton);
  processUiEvents();
  if (!showActionChosen || view.laneHidden(0, checkedLaneCc) ||
      automationArea->minimumHeight() != heightBeforeHide ||
      document.smf().write() != documentBeforeHide) {
    failures.append("the Add-lane menu did not restore hidden lane data");
  }
  view.hideLane(0, checkedLaneCc);
  const SongView::ViewState hiddenLaneState = view.viewState();
  QTemporaryDir laneSidecarRoot;
  SongView::ViewState restoredLaneState;
  const QString laneSidecarSong = QStringLiteral("rollcheck_hidden_lane");
  if (!laneSidecarRoot.isValid() ||
      !ViewSidecar::save(laneSidecarRoot.path(), laneSidecarSong,
                         hiddenLaneState) ||
      !ViewSidecar::load(laneSidecarRoot.path(), laneSidecarSong,
                         &restoredLaneState)) {
    failures.append(
        "hidden lane view state did not persist through its sidecar");
  } else {
    view.showLane(0, checkedLaneCc);
    view.applyViewState(restoredLaneState);
    if (!view.laneHidden(0, checkedLaneCc))
      failures.append("sidecar round trip lost a hidden lane");
  }
  view.showLane(0, checkedLaneCc);
  if (addedEmptyLane)
    view.removeEmptyLane(0, checkedLaneCc);
}

void checkLaneIdentityCodec(QStringList &failures) {
  QTemporaryDir sidecarRoot;
  if (!sidecarRoot.isValid()) {
    failures.append("could not create lane-codec sidecar directory");
    return;
  }
  const QString songLabel = QStringLiteral("rollcheck_lane_codec");
  SongView::ViewState source;
  source.valid = true;
  source.emptyLanes = {{1, uint8_t(0x01)}, {2, uint8_t(0x07)}};
  source.hiddenLanes = {{3, uint8_t(0x0A)}, {4, uint8_t(0x14)}};
  SongView::ViewState roundTripped;
  if (!ViewSidecar::save(sidecarRoot.path(), songLabel, source) ||
      !ViewSidecar::load(sidecarRoot.path(), songLabel, &roundTripped) ||
      roundTripped.emptyLanes != source.emptyLanes ||
      roundTripped.hiddenLanes != source.hiddenLanes) {
    failures.append("empty/hidden lane identities did not round trip");
    return;
  }
  const auto laneObject = [](const QJsonValue &track, const QJsonValue &cc) {
    QJsonObject lane;
    lane.insert(QLatin1String("track"), track);
    lane.insert(QLatin1String("cc"), cc);
    return lane;
  };
  QJsonArray emptyLanes;
  emptyLanes.append(laneObject(1, 0x07));
  emptyLanes.append(laneObject(-1, 0x07));
  emptyLanes.append(laneObject(1, 0x100));
  emptyLanes.append(laneObject(QStringLiteral("1"), 0x07));
  QJsonObject laneWithoutCc;
  laneWithoutCc.insert(QLatin1String("track"), 1);
  emptyLanes.append(laneWithoutCc);
  emptyLanes.append(7);
  QJsonArray hiddenLanes;
  hiddenLanes.append(laneObject(2, 0x0A));
  hiddenLanes.append(laneObject(16, 0x0A));
  hiddenLanes.append(laneObject(2, -1));
  hiddenLanes.append(laneObject(2, QStringLiteral("10")));
  hiddenLanes.append(QJsonArray());
  QJsonObject viewObject;
  viewObject.insert(QLatin1String("emptyLanes"), emptyLanes);
  viewObject.insert(QLatin1String("hiddenLanes"), hiddenLanes);
  QJsonObject rootObject;
  rootObject.insert(QLatin1String("view"), viewObject);
  QFile file(ViewSidecar::pathFor(sidecarRoot.path(), songLabel));
  if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate) ||
      file.write(QJsonDocument(rootObject).toJson(QJsonDocument::Compact)) <
          0) {
    failures.append("could not write rejected lane-codec values");
    return;
  }
  file.close();
  SongView::ViewState rejected;
  const std::vector<std::pair<int, uint8_t>> expectedEmpty = {
      {1, uint8_t(0x07)}};
  const std::vector<std::pair<int, uint8_t>> expectedHidden = {
      {2, uint8_t(0x0A)}};
  if (!ViewSidecar::load(sidecarRoot.path(), songLabel, &rejected) ||
      rejected.emptyLanes != expectedEmpty ||
      rejected.hiddenLanes != expectedHidden) {
    failures.append("empty/hidden lane codec accepted invalid identities");
  }
}

void checkLaneDeletionRemap(const SongInfo &song, QStringList &failures) {
  SongDocument document;
  if (!prepareKnownTracks(song, 2, QStringLiteral("lane deletion remap"),
                          document, failures))
    return;
  auto timeline = document.buildTimeline(48000.0);
  SongView view;
  view.setSong(timeline.get(), nullptr);
  view.setDocument(&document);
  QObject::connect(&document, &SongDocument::documentChanged, &view, [&] {
    auto rebuilt = document.buildTimeline(48000.0);
    view.updateSong(rebuilt.get());
    timeline = std::move(rebuilt);
  });
  constexpr uint8_t hiddenLaneCc = 0x01;
  constexpr uint8_t survivingLaneCc = 0x07;
  view.addEmptyLane(0, hiddenLaneCc);
  view.addEmptyLane(1, survivingLaneCc);
  view.hideLane(0, hiddenLaneCc);
  constexpr int survivingLaneHeight = 73;
  constexpr int survivingLaneRange = 91;
  SongView::AutomationRowDisplayState survivingRowState;
  survivingRowState.height = survivingLaneHeight;
  survivingRowState.range = survivingLaneRange;
  const auto survivingRowId = [](int track) {
    return SongView::AutomationRowId::controller(track, survivingLaneCc);
  };
  SongView::ViewState trackState = view.viewState();
  trackState.rowStates.insert(survivingRowId(1), survivingRowState);
  view.applyViewState(trackState);
  view.deleteTrack(0);
  processUiEvents();
  if (document.engineTrackCount() != 1)
    failures.append("hidden-lane owner was not deleted");
  if (view.laneHidden(0, hiddenLaneCc))
    failures.append("deleting a track left its hidden-lane state behind");
  const SongView::ViewState shiftedTrackState = view.viewState();
  if (shiftedTrackState.rowStates.value(survivingRowId(0)) !=
      survivingRowState) {
    failures.append("deleting a lower track left typed lane row state behind");
  }
  document.undoStack()->undo();
  processUiEvents();
  const SongView::ViewState restoredTrackState = view.viewState();
  if (document.engineTrackCount() != 2)
    failures.append("undoing track deletion did not restore the track");
  if (restoredTrackState.rowStates.value(survivingRowId(1)) !=
      survivingRowState) {
    failures.append("undoing track deletion left typed lane row state behind");
  }
  document.undoStack()->redo();
  processUiEvents();
  const SongView::ViewState redoneTrackState = view.viewState();
  if (redoneTrackState.rowStates.value(survivingRowId(0)) !=
      survivingRowState) {
    failures.append("redoing track deletion did not re-shift typed row state");
  }
}

void checkEngineRemap(const SongInfo &song, QStringList &failures) {
  SongDocument document;
  if (!prepareKnownTracks(song, 3, QStringLiteral("engine-slot remap"),
                          document, failures))
    return;
  constexpr int leadingSlotBeforeRemoval = 0;
  constexpr int removedSlotBeforeRemoval = 1;
  constexpr int stateOwnerSlotBeforeRemoval = 2;
  constexpr int leadingSlotAfterRemoval = 0;
  constexpr int stateOwnerSlotAfterRemoval = 1;
  const int leadingSmfChunk = document.smfTrackFor(leadingSlotBeforeRemoval);
  const int middleSmfChunk = document.smfTrackFor(removedSlotBeforeRemoval);
  const int stateOwnerSmfChunk =
      document.smfTrackFor(stateOwnerSlotBeforeRemoval);
  if (leadingSmfChunk < 0 || middleSmfChunk < 0 || stateOwnerSmfChunk < 0 ||
      !(leadingSmfChunk < middleSmfChunk &&
        middleSmfChunk < stateOwnerSmfChunk)) {
    failures.append("known remap tracks were not in SMF chunk order");
    return;
  }
  SmfEvent metadataEvent;
  metadataEvent.status = 0xFF;
  metadataEvent.metaType = 0x01;
  metadataEvent.blob = QByteArrayLiteral("rollcheck engine-slot remap");
  document.insertRawEvent(middleSmfChunk, metadataEvent);
  document.undoStack()->clear();
  auto timeline = document.buildTimeline(48000.0);
  SongView view;
  view.setSong(timeline.get(), nullptr);
  view.setDocument(&document);
  QObject::connect(&document, &SongDocument::documentChanged, &view, [&] {
    auto rebuilt = document.buildTimeline(48000.0);
    view.updateSong(rebuilt.get());
    timeline = std::move(rebuilt);
  });
  std::vector<size_t> middleChannelEventIndices;
  const auto &middleEvents = document.smf().tracks[middleSmfChunk].events;
  for (size_t eventIndex = 0; eventIndex < middleEvents.size(); ++eventIndex) {
    if (middleEvents[eventIndex].isChannel())
      middleChannelEventIndices.push_back(eventIndex);
  }
  if (middleChannelEventIndices.empty()) {
    failures.append("known middle track had no channel events to remove");
    return;
  }
  const auto onlySlotIsMuted = [&](int expectedMutedSlot) {
    for (int slot = 0; slot < 16; ++slot) {
      if (view.trackMuted(slot) != (slot == expectedMutedSlot))
        return false;
    }
    return true;
  };
  view.setTrackMute(stateOwnerSlotBeforeRemoval, true);
  if (!onlySlotIsMuted(stateOwnerSlotBeforeRemoval)) {
    failures.append("could not establish mute ownership before event removal");
    return;
  }
  document.deleteRawEvents(middleSmfChunk, middleChannelEventIndices);
  processUiEvents();
  const auto &middleEventsAfterRemoval =
      document.smf().tracks[middleSmfChunk].events;
  const bool middleChunkIsMetadataOnly =
      !middleEventsAfterRemoval.empty() &&
      std::all_of(middleEventsAfterRemoval.begin(),
                  middleEventsAfterRemoval.end(),
                  [](const SmfEvent &event) { return !event.isChannel(); });
  if (!middleChunkIsMetadataOnly || document.engineTrackCount() != 2) {
    failures.append(
        "channel-event removal did not leave a metadata-only chunk");
    return;
  }
  if (!onlySlotIsMuted(stateOwnerSlotAfterRemoval))
    failures.append("channel-event removal did not shift mute ownership");
  document.undoStack()->undo();
  processUiEvents();
  if (!onlySlotIsMuted(stateOwnerSlotBeforeRemoval))
    failures.append("event-removal undo did not restore mute ownership");
  document.undoStack()->redo();
  processUiEvents();
  if (!onlySlotIsMuted(stateOwnerSlotAfterRemoval))
    failures.append("event-removal redo did not re-shift mute ownership");

  // Re-establish one sentinel so reorder and inverse-remap checks are
  // independent of the removal phase.
  view.setSong(timeline.get(), nullptr);
  view.setTrackMute(stateOwnerSlotAfterRemoval, true);
  if (!onlySlotIsMuted(stateOwnerSlotAfterRemoval)) {
    failures.append("could not establish mute ownership before chunk reorder");
    return;
  }
  if (document.smfTrackFor(leadingSlotAfterRemoval) != leadingSmfChunk ||
      document.smfTrackFor(stateOwnerSlotAfterRemoval) != stateOwnerSmfChunk ||
      !(leadingSmfChunk < middleSmfChunk &&
        middleSmfChunk < stateOwnerSmfChunk)) {
    failures.append("metadata-only chunk was not between surviving tracks");
    return;
  }
  view.moveTrack(leadingSlotAfterRemoval, stateOwnerSlotAfterRemoval);
  processUiEvents();
  if (!onlySlotIsMuted(leadingSlotAfterRemoval))
    failures.append("metadata-crossing reorder did not move mute ownership");
  document.undoStack()->undo();
  processUiEvents();
  if (!onlySlotIsMuted(stateOwnerSlotAfterRemoval))
    failures.append("metadata-crossing reorder undo lost mute ownership");
  document.undoStack()->redo();
  processUiEvents();
  if (!onlySlotIsMuted(leadingSlotAfterRemoval))
    failures.append("metadata-crossing reorder redo lost mute ownership");
}

} // namespace

QStringList automationCheckFailures(const SongInfo &song) {
  QStringList failures;
  checkVoicePreview(song, failures);
  checkEditorDrawerAndLanes(song, failures);
  checkLaneIdentityCodec(failures);
  checkLaneDeletionRemap(song, failures);
  checkEngineRemap(song, failures);
  return failures;
}
