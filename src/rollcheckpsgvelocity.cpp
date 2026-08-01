#include "core/velocitymodel.h"
#include "ui/editordrawer.h"
#include "ui/velocityarea.h"
#include "ui/velocityaxis.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <optional>
#include <vector>

#include <QApplication>
#include <QEvent>
#include <QImage>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QPainter>
#include <QTemporaryDir>

#include "core/miditimeline.h"
#include "core/songdocument.h"
#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/songview.h"

namespace {

SmfEvent noteEvent(uint8_t status, uint64_t tick, uint8_t key, uint8_t velocity)
{
    SmfEvent event;
    event.status = status;
    event.tick = tick;
    event.data0 = key;
    event.data1 = velocity;
    return event;
}

void sendMouse(QWidget &widget, QEvent::Type type, const QPointF &position, Qt::MouseButton button,
               Qt::MouseButtons buttons = Qt::NoButton,
               Qt::KeyboardModifiers modifiers = Qt::NoModifier)
{
    QMouseEvent event(type, position, button, buttons, modifiers);
    QApplication::sendEvent(&widget, &event);
}

uint64_t drawerContextTick(double tick)
{
    return static_cast<uint64_t>(std::floor(std::max(0.0, tick) + 0.5));
}

bool samePixels(const QImage &left, const QImage &right)
{
    if (left.size() != right.size())
        return false;
    for (int y = 0; y < left.height(); ++y) {
        for (int x = 0; x < left.width(); ++x) {
            if (left.pixel(x, y) != right.pixel(x, y))
                return false;
        }
    }
    return true;
}

bool hasColorNear(const QImage &image, const QRect &bounds, const QColor &expected, int tolerance)
{
    const QRect clipped = bounds.intersected(image.rect());
    for (int y = clipped.top(); y <= clipped.bottom(); ++y) {
        for (int x = clipped.left(); x <= clipped.right(); ++x) {
            const QColor actual(image.pixel(x, y));
            if (std::abs(actual.red() - expected.red()) <= tolerance &&
                std::abs(actual.green() - expected.green()) <= tolerance &&
                std::abs(actual.blue() - expected.blue()) <= tolerance) {
                return true;
            }
        }
    }
    return false;
}

bool hasDarkOutlinePixel(const QImage &image, const QPointF &center, qreal innerRadius,
                         qreal outerRadius)
{
    const int left = std::max(0, int(std::floor(center.x() - outerRadius)));
    const int right = std::min(image.width() - 1, int(std::ceil(center.x() + outerRadius)));
    const int top = std::max(0, int(std::floor(center.y() - outerRadius)));
    const int bottom = std::min(image.height() - 1, int(std::ceil(center.y() + outerRadius)));
    for (int y = top; y <= bottom; ++y) {
        for (int x = left; x <= right; ++x) {
            const qreal dx = qreal(x) + 0.5 - center.x();
            const qreal dy = qreal(y) + 0.5 - center.y();
            const qreal distance = std::hypot(dx, dy);
            if (dx >= 0.0 || distance < innerRadius || distance > outerRadius)
                continue;
            const QColor pixel(image.pixel(x, y));
            if (std::max({pixel.red(), pixel.green(), pixel.blue()}) <= 160 &&
                pixel.red() + pixel.green() + pixel.blue() <= 320) {
                return true;
            }
        }
    }
    return false;
}

} // namespace

int runVelocityPageCheck(const QString &scratchProject, const QString &songLabel,
                         const QString &screenshotPath)
{
    (void)scratchProject;
    (void)songLabel;
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        if (!condition) {
            std::fprintf(stderr, "velocity-page: FAIL: %s\n", message);
            ++failures;
        }
    };
    QTemporaryDir temporary;
    QString error;
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    SmfTrack track;
    track.events = {
        noteEvent(0xC0, 0, 0, 0),   noteEvent(0x90, 12, 60, 20), noteEvent(0x90, 12, 60, 70),
        noteEvent(0x80, 36, 60, 0), noteEvent(0x80, 36, 60, 0),  noteEvent(0x90, 60, 64, 70),
        noteEvent(0x80, 84, 64, 0),
    };
    track.endTick = 84;
    smf.tracks.push_back(track);
    const QString midiPath = temporary.path() + QStringLiteral("/velocity.mid");
    SongInfo song;
    song.label = QStringLiteral("velocity");
    song.midPath = midiPath;
    song.hasMid = true;
    SongDocument document;
    check(temporary.isValid() && smf.writeFile(midiPath, &error) && document.load(song, &error),
          "synthetic duplicate-note fixture should load");
    const std::vector<DocNote> notes = document.notesForTrack(0);
    check(notes.size() == 3 && notes[0].noteId != notes[1].noteId,
          "duplicate notes must keep distinct NoteId values");
    if (notes.size() != 3)
        return 1;

    ToneData directSound{};
    directSound.type = VOICE_DIRECTSOUND;
    ToneData square{};
    square.type = VOICE_SQUARE_1;
    ToneData wave{};
    wave.type = VOICE_PROGRAMMABLE_WAVE;
    ToneData noise{};
    noise.type = VOICE_NOISE;
    LoadedVoiceGroup voicegroup{};
    voicegroup.voices[0] = directSound;
    auto timeline = document.buildTimeline(48000.0);
    check(timeline != nullptr, "concrete velocity fixture should build a timeline");
    if (!timeline)
        return 1;
    SongView view;
    view.resize(960, 480);
    view.setDocument(&document);
    view.setSong(timeline.get(), &voicegroup);
    view.setDrawerPage(EditorDrawerPage::Velocity);
    view.setDrawerVisible(true);
    view.setDrawerHeight(320);
    view.show();
    QApplication::processEvents();
    auto *drawer = view.editorDrawer();
    auto *areaPtr = drawer ? drawer->velocityArea() : nullptr;
    check(drawer != nullptr && areaPtr != nullptr,
          "concrete SongView should expose its owned velocity area");
    if (!areaPtr)
        return 1;
    auto &area = *areaPtr;
    area.resize(layout::editorGeometry().plotOrigin + layout::space(layout::Space::Eight),
                layout::editorGeometry().velocityDensityThresholdD4 +
                    layout::space(layout::Space::Six));
    area.songChanged();
    EditorPageLiveState live;
    live.documentRevision = document.revision();
    live.timeZoom = 48.0;
    live.trackColor = QColor(Qt::cyan);
    area.refreshLiveState(live);
    area.show();
    QApplication::processEvents();
    check(area.axis().mode() == VelocityAxis::Mode::Continuous &&
              static_cast<const QWidget &>(area).accessibleDescription() ==
                  QStringLiteral("Velocity"),
          "DirectSound with no selection should publish the continuous accessible axis");
    check(area.focusPolicy() == Qt::ClickFocus && !VelocityAxis::nodesFocusable() &&
              !VelocityAxis::graduationLabelsFocusable(),
          "velocity nodes and ruler labels must add no focus targets");

    area.resize(layout::editorGeometry().plotOrigin + layout::space(layout::Space::Eight),
                layout::editorGeometry().velocityDensityThresholdD2 +
                    layout::space(layout::Space::One));
    QApplication::processEvents();
    const auto &directSoundLabels = area.axis().labels();
    check(area.axis().tickCount() == 9 && area.axis().labelCount() == 5 &&
              directSoundLabels[0].velocity == 127 && directSoundLabels[1].velocity == 96 &&
              directSoundLabels[2].velocity == 64 && directSoundLabels[3].velocity == 32 &&
              directSoundLabels[4].velocity == 1,
          "DirectSound must retain the original medium-height continuous graduations");
    area.resize(layout::editorGeometry().plotOrigin + layout::space(layout::Space::Eight),
                layout::editorGeometry().velocityDensityThresholdD4 +
                    layout::space(layout::Space::Six));
    QApplication::processEvents();

    view.setSelection({notes[0].noteId, notes[1].noteId});
    live.editCursorTick++;
    area.refreshLiveState(live);
    voicegroup.voices[0] = square;
    view.setVoicegroup(&voicegroup);
    area.songChanged();
    live.editCursorTick++;
    area.refreshLiveState(live);
    check(area.axis().mode() == VelocityAxis::Mode::Intrinsic &&
              static_cast<const QWidget &>(area).accessibleDescription() ==
                  QStringLiteral("Velocity. Square 1 has 16 volume levels."),
          "compatible Square selection should publish intrinsic graduations");
    voicegroup.voices[0] = wave;
    view.setVoicegroup(&voicegroup);
    area.songChanged();
    live.editCursorTick++;
    area.refreshLiveState(live);
    check(area.axis().mode() == VelocityAxis::Mode::Intrinsic &&
              area.axis().graduationCount() == 5 &&
              static_cast<const QWidget &>(area).accessibleDescription() ==
                  QStringLiteral("Velocity. Programmable Wave has 5 volume levels."),
          "Wave selection should publish five intrinsic graduations");
    voicegroup.voices[0] = noise;
    view.setVoicegroup(&voicegroup);
    area.songChanged();
    live.editCursorTick++;
    area.refreshLiveState(live);
    check(area.axis().mode() == VelocityAxis::Mode::Intrinsic &&
              area.axis().graduationCount() == 16 &&
              static_cast<const QWidget &>(area).accessibleDescription() ==
                  QStringLiteral("Velocity. Noise has 16 volume levels."),
          "Noise selection should publish all intrinsic graduations");
    const auto &noiseGraduations = area.axis().graduations();
    const double intrinsicLeft = double(layout::space(layout::Space::Two));
    const double intrinsicRight = intrinsicLeft + area.axis().intrinsicColumnWidth() +
                                  double(layout::space(layout::Space::One));
    check(area.axis().intrinsicColumnCount() == 2 && noiseGraduations[0].column == 1 &&
              noiseGraduations[1].column == 0 &&
              std::abs(noiseGraduations[0].x - intrinsicRight) < 0.001 &&
              std::abs(noiseGraduations[1].x - intrinsicLeft) < 0.001 &&
              noiseGraduations[0].x + noiseGraduations[0].width <=
                  double(area.plotOrigin() - layout::singlePixel() -
                         layout::space(layout::Space::Two)) &&
              noiseGraduations[2].labelText() == "Volume 3 (20)" &&
              noiseGraduations[8].labelText() == "Volume 9 (70)",
          "intrinsic labels must use the original staggered left-gutter graduation layout");

    view.setSelection({notes[0].noteId});
    ++live.editCursorTick;
    area.refreshLiveState(live);
    area.resize(layout::editorGeometry().plotOrigin + 4 * layout::space(layout::Space::Eight),
                layout::editorGeometry().velocityDensityThresholdD4 +
                    layout::space(layout::Space::Six));
    QApplication::processEvents();
    const VelocityMap map = VelocityMap::resolve(&noise, notes[0].key);
    const std::optional<std::size_t> selectedLevel = map.levelOf(notes[0].velocity);
    const std::optional<std::size_t> unselectedLevel = map.levelOf(notes[1].velocity);
    const double paintNodeX =
        double(area.plotOrigin()) +
        double(notes[0].tick) * live.timeZoom / double(timeline->ticksPerBeat) -
        live.horizontalScroll;
    const double selectedY = selectedLevel ? area.axis().levelToY(int(*selectedLevel))
                                           : area.axis().velocityToY(notes[0].velocity);
    const double unselectedY = unselectedLevel ? area.axis().levelToY(int(*unselectedLevel))
                                               : area.axis().velocityToY(notes[1].velocity);
    const QImage velocityImage = area.grab().toImage();
    const qreal imageScale = velocityImage.devicePixelRatio();
    const auto pixelRect = [imageScale](const QRectF &logical) {
        return QRect(qRound(logical.x() * imageScale), qRound(logical.y() * imageScale),
                     qMax(1, qRound(logical.width() * imageScale)),
                     qMax(1, qRound(logical.height() * imageScale)));
    };
    const QColor expectedStem = songview::mixTowardOklab(live.trackColor, Qt::black, 1.0 / 3.0);
    const QRect stemBounds = pixelRect(QRectF(paintNodeX + 8.0, unselectedY - 3.0, 16.0, 6.0));
    const QPointF unselectedNodeCenter(paintNodeX * imageScale, unselectedY * imageScale);
    const qreal outlineRadius = layout::editorGeometry().velocityNodePaintRadius * imageScale;
    const qreal outlineWidth = layout::editorGeometry().velocityNodeOutlineDipWidth * imageScale;
    const QRect selectedRingBounds =
        pixelRect(QRectF(paintNodeX - 6.0, selectedY - 6.0, 4.0, 12.0));
    check(selectedLevel && unselectedLevel &&
              hasColorNear(velocityImage, stemBounds, expectedStem, 4),
          "unselected velocity duration stems must use the OKLab track shade");
    check(hasDarkOutlinePixel(velocityImage, unselectedNodeCenter,
                              std::max(0.0, outlineRadius - outlineWidth),
                              outlineRadius + outlineWidth),
          "unselected velocity nodes must retain black outlines");
    check(hasColorNear(velocityImage, selectedRingBounds, area.palette().highlight().color(), 16),
          "selected velocity nodes must retain selection rings");
    const QRect rulerAccentBounds =
        pixelRect(QRectF(double(area.plotOrigin() - layout::singlePixel() -
                                3 * layout::space(layout::Space::Half) - 1),
                         selectedY - 2.0, double(3 * layout::space(layout::Space::Half) + 2), 4.0));
    check(hasColorNear(velocityImage, rulerAccentBounds, area.palette().highlight().color(), 16),
          "intrinsic ruler paint must preserve the emphasized accent tick");

    area.clearTrackHeaderSelection();
    check(view.selection().empty(),
          "plain track-header clearing must clear shared NoteId selection");
    live.playback.playing = true;
    const std::array<double, 4> contextInputs = {-1.0, 0.49, 0.5, 0.51};
    const auto checkContextRounding = [&](const ToneData *tone, VelocityAxis::Mode expectedMode,
                                          const char *message) {
        voicegroup.voices[0] = *tone;
        view.setVoicegroup(&voicegroup);
        area.songChanged();
        ++live.editCursorTick;
        bool rounded = true;
        for (const double input : contextInputs) {
            live.playback.playheadTick = input;
            area.refreshLiveState(live);
            rounded = rounded &&
                      view.voiceContext(drawerContextTick(input)).voice == &voicegroup.voices[0];
        }
        check(rounded && area.axis().mode() == expectedMode, message);
    };
    checkContextRounding(&directSound, VelocityAxis::Mode::Continuous,
                         "continuous context must use drawerContextTick");
    checkContextRounding(&square, VelocityAxis::Mode::Intrinsic,
                         "Square context must use drawerContextTick");
    checkContextRounding(&wave, VelocityAxis::Mode::Intrinsic,
                         "Wave context must use drawerContextTick");
    checkContextRounding(&noise, VelocityAxis::Mode::Intrinsic,
                         "Noise context must use drawerContextTick");

    view.setSelection({notes[0].noteId, notes[1].noteId});
    live.playback.playing = false;
    live.editCursorTick++;
    area.refreshLiveState(live);
    const int undoDepth = document.undoStack()->count();
    const uint64_t revisionBeforeGesture = document.revision();
    const std::optional<std::size_t> selectedPsgLevel = map.levelOf(notes[0].velocity);
    const double nodeX = double(area.plotOrigin()) +
                         double(notes[0].tick) * live.timeZoom / double(timeline->ticksPerBeat) -
                         live.horizontalScroll;
    const double nodeY = selectedPsgLevel ? area.axis().levelToY(int(*selectedPsgLevel))
                                          : area.axis().velocityToY(notes[0].velocity);
    check(area.axis().mode() == VelocityAxis::Mode::Intrinsic && selectedPsgLevel &&
              nodeY != area.axis().velocityToY(notes[0].velocity),
          "compatible intrinsic notes must use their categorical graduation");
    const QPointF node(nodeX, nodeY);
    const QPointF firstDrag = node + QPointF(0.0, double(area.height()));
    const QPointF drag = node + QPointF(0.0, -double(area.height()));
    sendMouse(area, QEvent::MouseButtonPress, node, Qt::LeftButton, Qt::LeftButton);
    sendMouse(area, QEvent::MouseMove, firstDrag, Qt::NoButton, Qt::LeftButton);
    DocNote draggedFirst;
    DocNote draggedSecond;
    check(document.findNote(notes[0].noteId, &draggedFirst) &&
              document.findNote(notes[1].noteId, &draggedSecond) &&
              draggedFirst.velocity != notes[0].velocity &&
              draggedSecond.velocity != notes[1].velocity &&
              document.undoStack()->count() == undoDepth + 1,
          "relative drag must apply note velocities before mouse-up in one undo command");
    sendMouse(area, QEvent::MouseMove, drag, Qt::NoButton, Qt::LeftButton);
    DocNote finalDraggedFirst;
    check(document.findNote(notes[0].noteId, &finalDraggedFirst) &&
              finalDraggedFirst.velocity != draggedFirst.velocity &&
              document.undoStack()->count() == undoDepth + 1,
          "successive velocity updates in one drag must merge into one undo command");
    sendMouse(area, QEvent::MouseButtonRelease, drag, Qt::LeftButton);
    check(
        document.revision() == revisionBeforeGesture + 2 &&
            document.undoStack()->count() == undoDepth + 1,
        "relative drag must submit one revision-checked velocity batch and bracket follow scroll");
    const std::vector<NoteId> selectedBeforeUndo = view.selection();
    document.undoStack()->undo();
    area.documentChanged();
    check(view.selection() == selectedBeforeUndo,
          "Undo must preserve the shared selection identities of surviving notes");

    view.setSelection({notes[0].noteId});
    ++live.editCursorTick;
    area.refreshLiveState(live);
    const std::optional<std::size_t> secondLevel = map.levelOf(notes[1].velocity);
    const QPointF secondNode(nodeX, secondLevel ? area.axis().levelToY(int(*secondLevel))
                                                : area.axis().velocityToY(notes[1].velocity));
    const int undoDepthBeforeUngrab = document.undoStack()->count();
    sendMouse(area, QEvent::MouseButtonPress, secondNode, Qt::LeftButton, Qt::LeftButton);
    QEvent ungrabMouse(QEvent::UngrabMouse);
    QApplication::sendEvent(&area, &ungrabMouse);
    check(view.selection() == std::vector<NoteId>{notes[0].noteId} &&
              document.undoStack()->count() == undoDepthBeforeUngrab,
          "mouse ungrab must cancel a provisional selection without history residue");

    const QRect selectorProbe(area.plotOrigin() + layout::space(layout::Space::One),
                              area.height() / 2, layout::space(layout::Space::Three),
                              layout::space(layout::Space::Two));
    const auto grabSelectorProbe = [&area, &selectorProbe] {
        const QImage image = area.grab().toImage();
        const qreal dpr = image.devicePixelRatio();
        const int left = qFloor(selectorProbe.left() * dpr);
        const int top = qFloor(selectorProbe.top() * dpr);
        const int right = qCeil((selectorProbe.left() + selectorProbe.width()) * dpr);
        const int bottom = qCeil((selectorProbe.top() + selectorProbe.height()) * dpr);
        return image.copy(QRect(left, top, right - left, bottom - top));
    };
    const QPointF selectorStart(selectorProbe.left(), selectorProbe.top());
    const QPointF selectorEnd(selectorProbe.right(), selectorProbe.bottom());
    const QPointF selectorContractedEnd =
        selectorStart + QPointF(selectorProbe.width() / 2.0, selectorProbe.height() / 2.0);
    const auto abandonedCorner = [](const QImage &image) {
        return image.copy(QRect(image.width() * 3 / 4, image.height() * 3 / 4, image.width() / 4,
                                image.height() / 4));
    };
    const QImage bandBaseline = grabSelectorProbe();
    sendMouse(area, QEvent::MouseButtonPress, selectorStart, Qt::RightButton, Qt::RightButton);
    sendMouse(area, QEvent::MouseMove, selectorEnd, Qt::NoButton, Qt::RightButton);
    QApplication::processEvents();
    const QImage activeBand = grabSelectorProbe();
    check(!samePixels(bandBaseline, activeBand),
          "drag-select must visibly paint its selector overlay");
    const QColor activeBandInterior(
        activeBand.pixel(activeBand.width() / 2, activeBand.height() / 2));
    check(activeBandInterior != live.trackColor,
          "drag-select interior must remain translucent over velocity content");
    sendMouse(area, QEvent::MouseMove, selectorContractedEnd, Qt::NoButton, Qt::RightButton);
    QApplication::processEvents();
    const QImage contractedBand = grabSelectorProbe();
    check(!samePixels(bandBaseline, contractedBand) &&
              samePixels(abandonedCorner(bandBaseline), abandonedCorner(contractedBand)),
          "contracting drag-select must clear the abandoned selector area");
    sendMouse(area, QEvent::MouseButtonRelease, selectorContractedEnd, Qt::RightButton);
    QApplication::processEvents();
    check(samePixels(bandBaseline, grabSelectorProbe()),
          "completed drag-select must clear its selector overlay");

    view.setSelection({notes[0].noteId});
    ++live.editCursorTick;
    area.refreshLiveState(live);
    QApplication::processEvents();
    const QImage cancelledBandBaseline = grabSelectorProbe();
    sendMouse(area, QEvent::MouseButtonPress, selectorStart, Qt::RightButton, Qt::RightButton);
    sendMouse(area, QEvent::MouseMove, selectorEnd, Qt::NoButton, Qt::RightButton);
    QApplication::processEvents();
    QEvent cancelBand(QEvent::UngrabMouse);
    QApplication::sendEvent(&area, &cancelBand);
    QApplication::processEvents();
    check(view.selection() == std::vector<NoteId>{notes[0].noteId} &&
              samePixels(cancelledBandBaseline, grabSelectorProbe()),
          "cancelled drag-select must clear its selector overlay and restore selection");
    live.documentRevision = document.revision();
    area.refreshLiveState(live);
    QApplication::processEvents();
    DocNote currentFirst;
    DocNote currentSecond;
    check(document.findNote(notes[0].noteId, &currentFirst) &&
              document.findNote(notes[1].noteId, &currentSecond),
          "velocity node click fixture must resolve its notes");
    document.setNotesVelocity({currentSecond}, currentFirst.velocity);
    live.documentRevision = document.revision();
    area.refreshLiveState(live);
    QApplication::processEvents();
    const VelocityMap currentMap = VelocityMap::resolve(&noise, currentFirst.key);
    const std::optional<std::size_t> currentLevel = currentMap.levelOf(currentFirst.velocity);
    const QPointF currentNode(double(area.plotOrigin()) +
                                  double(currentFirst.tick) * live.timeZoom /
                                      double(timeline->ticksPerBeat) -
                                  live.horizontalScroll,
                              currentLevel ? area.axis().levelToY(int(*currentLevel))
                                           : area.axis().velocityToY(currentFirst.velocity));
    sendMouse(area, QEvent::MouseButtonPress, currentNode, Qt::LeftButton, Qt::LeftButton);
    sendMouse(area, QEvent::MouseButtonRelease, currentNode, Qt::LeftButton);
    check(view.selection() == std::vector<NoteId>{notes[0].noteId},
          "selected velocity node must win a stacked-node click");
    view.setSelection({notes[0].noteId, notes[2].noteId});
    DocNote paintFirstBefore;
    DocNote paintThirdBefore;
    document.findNote(notes[0].noteId, &paintFirstBefore);
    document.findNote(notes[2].noteId, &paintThirdBefore);
    const auto paintGestureX = [&area, &view, &timeline](const DocNote &note) {
        return double(area.plotOrigin()) +
               double(note.tick) * view.pxPerBeat() / double(timeline->ticksPerBeat) -
               view.viewState().scrollPx;
    };
    const QPointF paintStart(paintGestureX(paintFirstBefore), area.axis().levelToY(0));
    const QPointF paintEnd(paintGestureX(paintThirdBefore), area.axis().levelToY(4));
    const uint64_t revisionBeforePaint = document.revision();
    const int undoIndexBeforePaint = document.undoStack()->index();
    sendMouse(area, QEvent::MouseButtonPress, paintStart, Qt::LeftButton, Qt::LeftButton);
    sendMouse(area, QEvent::MouseMove, paintEnd, Qt::NoButton, Qt::LeftButton);
    check(view.selection() == std::vector<NoteId>({notes[0].noteId, notes[2].noteId}) &&
              document.revision() == revisionBeforePaint,
          "holding velocity paint must retain selection and defer document changes");
    sendMouse(area, QEvent::MouseButtonRelease, paintEnd, Qt::LeftButton);
    DocNote paintedFirst;
    DocNote paintedThird;
    check(document.revision() == revisionBeforePaint + 1 &&
              document.undoStack()->index() == undoIndexBeforePaint + 1 &&
              document.findNote(notes[0].noteId, &paintedFirst) &&
              document.findNote(notes[2].noteId, &paintedThird) &&
              paintedFirst.velocity == currentMap.representative(0) &&
              paintedThird.velocity == currentMap.representative(4),
          "held velocity paint must move every selected node column crossed");

    const QPointF blankPoint(double(area.plotOrigin() + area.plotWidth() - 4),
                             area.axis().levelToY(2));
    const uint64_t revisionBeforeBlankClick = document.revision();
    const int undoDepthBeforeBlankClick = document.undoStack()->count();
    sendMouse(area, QEvent::MouseButtonPress, blankPoint, Qt::LeftButton, Qt::LeftButton);
    check(view.selection() == std::vector<NoteId>({notes[0].noteId, notes[2].noteId}),
          "blank velocity press must retain selection until mouse-up");
    sendMouse(area, QEvent::MouseButtonRelease, blankPoint, Qt::LeftButton);
    check(view.selection().empty() && document.revision() == revisionBeforeBlankClick &&
              document.undoStack()->count() == undoDepthBeforeBlankClick,
          "blank velocity click must deselect only on mouse-up");

    view.setSelection({notes[0].noteId, notes[1].noteId});
    const VelocityAxisGraduation graduation = area.axis().graduations()[2];
    const QPointF graduationPoint(graduation.x + graduation.width / 2.0, graduation.y);
    sendMouse(area, QEvent::MouseButtonPress, graduationPoint, Qt::LeftButton, Qt::LeftButton);
    sendMouse(area, QEvent::MouseButtonRelease, graduationPoint, Qt::LeftButton);
    DocNote graduatedFirst;
    DocNote graduatedSecond;
    check(view.selection() == std::vector<NoteId>({notes[0].noteId, notes[1].noteId}) &&
              document.findNote(notes[0].noteId, &graduatedFirst) &&
              document.findNote(notes[1].noteId, &graduatedSecond) &&
              graduatedFirst.velocity == graduation.velocity &&
              graduatedSecond.velocity == graduation.velocity,
          "clicking a graduation must retain and move the selected nodes");

    auto *roll = view.findChild<QWidget *>(QStringLiteral("pianoRoll"));
    const auto velocityDragModifiers =
        keymap::Registry::instance().modifierBinding(QStringLiteral("roll.velocity_drag"));
    check(roll != nullptr && velocityDragModifiers != Qt::NoModifier,
          "velocity preview fixture must expose the piano roll drag shortcut");
    if (roll && velocityDragModifiers != Qt::NoModifier) {
        const int dragDelta = QApplication::startDragDistance() + 16;
        const QPointF rollNoteCenter(
            double(layout::editorGeometry().pianoKeyboardWidth) +
                double(view.contentX(double(graduatedFirst.tick) +
                                     double(graduatedFirst.duration) / 2.0)),
            (127.5 - double(graduatedFirst.key)) * view.keyHeight() - view.scrollY());
        const QPointF rollDragPosition = rollNoteCenter - QPointF(0.0, double(dragDelta));
        const uint64_t revisionBeforeRollDrag = document.revision();
        sendMouse(*roll, QEvent::MouseButtonPress, rollNoteCenter, Qt::LeftButton, Qt::LeftButton,
                  velocityDragModifiers);
        sendMouse(*roll, QEvent::MouseMove, rollDragPosition, Qt::NoButton, Qt::LeftButton,
                  velocityDragModifiers);
        QApplication::processEvents();
        const uint8_t previewVelocity =
            uint8_t(std::clamp(int(graduatedFirst.velocity) + dragDelta, 1, 127));
        const std::optional<std::size_t> previewLevel = map.levelOf(previewVelocity);
        const QImage rollDragPreview = area.grab().toImage();
        const QPointF previewNodeCenter(
            (double(area.plotOrigin()) + double(view.contentX(double(graduatedFirst.tick)))) *
                rollDragPreview.devicePixelRatio(),
            (previewLevel ? area.axis().levelToY(int(*previewLevel))
                          : area.axis().velocityToY(previewVelocity)) *
                rollDragPreview.devicePixelRatio());
        check(document.revision() == revisionBeforeRollDrag,
              "piano-roll velocity preview must not mutate the document before release");
        check(previewLevel && area.axis().graduations()[*previewLevel].active,
              "piano-roll velocity drag must update the velocity drawer's active graduation");
        check(hasDarkOutlinePixel(rollDragPreview, previewNodeCenter,
                                  std::max(0.0, outlineRadius - outlineWidth),
                                  outlineRadius + outlineWidth),
              "piano-roll velocity drag must move the velocity drawer node before release");
        sendMouse(*roll, QEvent::MouseButtonRelease, rollDragPosition, Qt::LeftButton, Qt::NoButton,
                  velocityDragModifiers);
        DocNote committedFirst;
        check(document.revision() == revisionBeforeRollDrag + 1 &&
                  document.findNote(graduatedFirst.noteId, &committedFirst) &&
                  committedFirst.velocity == previewVelocity,
              "piano-roll velocity drag must commit the previewed value on release");
        live.documentRevision = document.revision();
    }

    view.setSelection({notes[1].noteId});
    voicegroup.voices[0] = directSound;
    view.setVoicegroup(&voicegroup);
    area.songChanged();
    DocNote axisFirstBefore;
    DocNote axisSecondBefore;
    document.findNote(notes[0].noteId, &axisFirstBefore);
    document.findNote(notes[1].noteId, &axisSecondBefore);
    document.setNotesVelocity({axisFirstBefore}, 1);
    document.findNote(notes[0].noteId, &axisFirstBefore);
    document.setNotesVelocity({axisSecondBefore}, 70);
    document.findNote(notes[1].noteId, &axisSecondBefore);
    live.documentRevision = document.revision();
    live.playback.playing = false;
    ++live.editCursorTick;
    area.refreshLiveState(live);
    const int axisVelocity = 40;
    const QPointF axisPoint(double(area.plotOrigin()) +
                                double(axisSecondBefore.tick) * live.timeZoom /
                                    double(timeline->ticksPerBeat) -
                                live.horizontalScroll,
                            area.axis().velocityToY(axisVelocity));
    const uint64_t axisRevision = document.revision();
    const int axisUndoDepth = document.undoStack()->count();
    sendMouse(area, QEvent::MouseButtonPress, axisPoint, Qt::LeftButton, Qt::LeftButton);
    sendMouse(area, QEvent::MouseButtonRelease, axisPoint, Qt::LeftButton);
    DocNote axisFirstAfter;
    DocNote axisSecondAfter;
    check(area.axis().mode() == VelocityAxis::Mode::Continuous &&
              view.selection() == std::vector<NoteId>{notes[1].noteId} &&
              document.revision() == axisRevision + 1 &&
              document.undoStack()->count() == axisUndoDepth + 1 &&
              document.findNote(notes[0].noteId, &axisFirstAfter) &&
              document.findNote(notes[1].noteId, &axisSecondAfter) &&
              axisFirstAfter.velocity == axisFirstBefore.velocity &&
              axisSecondAfter.velocity == axisVelocity,
          "clicking below a selected node must set only that node to the clicked velocity");

    live.playback.playing = true;
    live.playback.playheadTick = -1.0;
    area.refreshLiveState(live);
    QApplication::processEvents();
    const VelocityAreaDiagnostics warm = area.diagnostics();
    for (int update = 0; update < 120; ++update) {
        live.playback.playheadTick = double(update);
        area.refreshLiveState(live);
        QApplication::processEvents();
    }
    check(area.diagnostics().contentBuildCount == warm.contentBuildCount &&
              area.diagnostics().presentedPlayheadTick == 119.0 &&
              area.diagnostics().playheadPresentationCount == warm.playheadPresentationCount + 120,
          "120 playhead presentations must not rebuild velocity content");

    QKeyEvent copy(QEvent::KeyPress, Qt::Key_C, Qt::ControlModifier);
    QApplication::sendEvent(&area, &copy);
    check(!view.clipboard().empty(), "click-focused velocity page must route shared edit commands");
    if (!screenshotPath.isEmpty())
        check(area.grab().save(screenshotPath), "optional velocity screenshot should save");
    area.hide();
    return failures == 0 ? 0 : 1;
}

namespace {

bool equals(const std::optional<std::size_t> &value, std::size_t expected)
{
    return value && *value == expected;
}

bool hasLabel(const VelocityAxis &axis, uint8_t velocity)
{
    for (std::size_t index = 0; index < axis.labelCount(); ++index) {
        if (axis.labels()[index].velocity == velocity)
            return true;
    }
    return false;
}

bool labelsMatch(const VelocityAxis &axis, const uint8_t *expected, std::size_t count)
{
    if (axis.labelCount() != count)
        return false;
    for (std::size_t index = 0; index < count; ++index) {
        if (axis.labels()[index].velocity != expected[index])
            return false;
    }
    return true;
}

bool intrinsicLevelsRoundTrip(const VelocityAxis &axis)
{
    for (std::size_t level = 0; level < axis.graduationCount(); ++level) {
        if (axis.yToLevel(axis.levelToY(int(level))) != int(level))
            return false;
    }
    return true;
}

VelocityAxisGeometry axisGeometry(double height, double labelWidth = 200.0)
{
    return {height, 6.0, labelWidth, 2.0, 1.0, 84.0, 112.0, 156.0, 300.0};
}

} // namespace

int runVelocityModelCheck()
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        if (!condition) {
            std::fprintf(stderr, "velocity-model: FAIL: %s\n", message);
            ++failures;
        }
    };

    ToneData squareTone{};
    squareTone.type = VOICE_SQUARE_1;
    ToneData squareTwoTone{};
    squareTwoTone.type = VOICE_SQUARE_2;
    ToneData noiseTone{};
    noiseTone.type = VOICE_NOISE;
    ToneData waveTone{};
    waveTone.type = VOICE_PROGRAMMABLE_WAVE;
    ToneData directSoundTone{};
    directSoundTone.type = VOICE_DIRECTSOUND;
    const VelocityMap square = VelocityMap::resolve(&squareTone, 60);
    const VelocityMap squareTwo = VelocityMap::resolve(&squareTwoTone, 60);
    const VelocityMap noise = VelocityMap::resolve(&noiseTone, 60);
    const VelocityMap wave = VelocityMap::resolve(&waveTone, 60);
    const VelocityMap directSound = VelocityMap::resolve(&directSoundTone, 60);
    const VelocityMap unresolved = VelocityMap::resolve(nullptr, std::nullopt);

    check(square.isPsg() && std::strcmp(square.voiceName(), "Square 1") == 0,
          "Square 1 should resolve intrinsically");
    check(squareTwo.isPsg() && std::strcmp(squareTwo.voiceName(), "Square 2") == 0,
          "Square 2 should resolve intrinsically");
    check(noise.isPsg() && std::strcmp(noise.voiceName(), "Noise") == 0,
          "Noise should resolve intrinsically");
    check(wave.isPsg() && std::strcmp(wave.voiceName(), "Programmable Wave") == 0,
          "Wave should resolve intrinsically");
    check(!directSound.isPsg(), "DirectSound should remain continuous");
    check(!unresolved.isPsg(), "missing voice should remain unresolved");

    ToneData invalidTone{};
    invalidTone.type = VOICE_CRY;
    const VelocityMap invalid = VelocityMap::resolve(&invalidTone, 60);
    check(!invalid.isPsg(), "invalid voice should remain continuous");
    std::array<ToneData, 128> nestedChildren{};
    nestedChildren[60].type = VOICE_KEYSPLIT;
    ToneData nestedSplit{};
    nestedSplit.type = VOICE_KEYSPLIT_ALL;
    nestedSplit.subGroup = nestedChildren.data();
    check(!VelocityMap::resolve(&nestedSplit, 60).isPsg(), "nested keysplit should be invalid");
    ToneData keylessSplit{};
    keylessSplit.type = VOICE_KEYSPLIT_ALL;
    keylessSplit.subGroup = nestedChildren.data();
    check(!VelocityMap::resolve(&keylessSplit, std::nullopt).isPsg(),
          "keyless keysplit should remain continuous");
    std::array<ToneData, 128> splitChildren{};
    std::array<uint8_t, 128> splitTable{};
    splitChildren[7].type = VOICE_PROGRAMMABLE_WAVE;
    splitTable[60] = 7;
    ToneData splitTone{};
    splitTone.type = VOICE_KEYSPLIT;
    splitTone.subGroup = splitChildren.data();
    splitTone.keySplitTable = splitTable.data();
    const VelocityMap keyedSplit = VelocityMap::resolve(&splitTone, 60);
    check(keyedSplit.isPsg() && std::strcmp(keyedSplit.voiceName(), "Programmable Wave") == 0,
          "keyed keysplit should resolve its selected voice");

    const std::array<uint8_t, 16> squareNoiseRepresentatives = {
        1, 12, 20, 28, 36, 44, 52, 60, 68, 76, 84, 92, 100, 108, 116, 127,
    };
    const std::array<uint8_t, 5> waveRepresentatives = {1, 32, 64, 96, 127};
    const auto representativesMatch = [](const VelocityMap &map, const auto &expected) {
        if (map.levelCount() != expected.size())
            return false;
        for (std::size_t level = 0; level < expected.size(); ++level) {
            if (map.representative(int(level)) != expected[level])
                return false;
        }
        return true;
    };
    check(representativesMatch(square, squareNoiseRepresentatives),
          "Square representatives should be exact");
    check(representativesMatch(wave, waveRepresentatives), "Wave representatives should be exact");
    check(representativesMatch(noise, squareNoiseRepresentatives),
          "Noise representatives should describe every hardware level");
    check(equals(square.levelOf(1), 0) && equals(square.levelOf(127), 15) &&
              equals(wave.levelOf(1), 0) && equals(wave.levelOf(127), 4),
          "intrinsic levels should include velocity boundaries");
    check(!directSound.levelOf(1), "DirectSound should not gain an intrinsic level");
    check(square.compatibleWith(square), "matching maps should be compatible");
    check(!square.compatibleWith(squareTwo) && !square.compatibleWith(noise),
          "different PSG voice identities should be incompatible");

    check(square.canonicalize(1) == 1 && square.canonicalize(127) == 127,
          "Square canonicalization should retain endpoints");
    check(square.canonicalize(64) == 60 && wave.canonicalize(80) == 64,
          "canonicalization should select the representative for its hardware class");
    check(square.canonicalize(8) == 1 && square.canonicalize(9) == 12 &&
              noise.canonicalize(8) == 1 && noise.canonicalize(9) == 12 &&
              wave.canonicalize(112) == 96,
          "canonicalization should preserve hardware classes at their boundaries");
    check(wave.canonicalize(65) == 64 && square.canonicalize(65) == 68 &&
              noise.canonicalize(65) == 68 && directSound.canonicalize(65) == 65 &&
              invalid.canonicalize(65) == 65,
          "canonicalization should respect every voice type and fallback");
    const std::optional<std::size_t> originLevel = wave.levelOf(95);
    check(equals(originLevel, 3) && wave.moveLevels(95, 0) == 95 && wave.moveLevels(95, -1) == 64,
          "returning to an origin level should restore its exact value");
    const std::array<uint8_t, 3> moved = {
        wave.moveLevels(95, 1),
        square.moveLevels(60, 1),
        directSound.moveLevels(65, 1),
    };
    check(moved == std::array<uint8_t, moved.size()>{127, 68, 66},
          "level movement should preserve heterogeneous exact origins");
    check(wave.moveLevels(1, -1) == 1 && square.moveLevels(127, 1) == 127 &&
              directSound.moveLevels(1, -1) == 1 && directSound.moveLevels(127, 1) == 127,
          "level movement should clamp at both velocity endpoints");

    const VelocityAxis continuous(VelocityMap::resolve(nullptr, std::nullopt), axisGeometry(200.0),
                                  std::array<uint8_t, 3>{12, 64, 100}.data(), 3);
    check(continuous.mode() == VelocityAxis::Mode::Continuous && continuous.top() == 6.0 &&
              continuous.bottom() == 194.0 && continuous.velocityToY(127) == 6.0 &&
              continuous.velocityToY(1) == 194.0 && continuous.velocityToY(64) == 100.0,
          "continuous placement should use inset endpoints");
    check(VelocityAxis(directSound, axisGeometry(200.0)).mode() == VelocityAxis::Mode::Continuous &&
              VelocityAxis(invalid, axisGeometry(200.0)).mode() == VelocityAxis::Mode::Continuous,
          "DirectSound and invalid contexts should select the continuous axis");
    check(continuous.yToVelocity(6.0) == 127 && continuous.yToVelocity(194.0) == 1 &&
              continuous.markerCount() == 2 && continuous.markers()[0].velocity == 12 &&
              continuous.markers()[1].velocity == 100,
          "continuous inverse placement and extrema should be exact");
    check(continuous.tickCount() == 17 && hasLabel(continuous, 127) && hasLabel(continuous, 112) &&
              hasLabel(continuous, 1),
          "continuous density should select the D3 band");
    check(continuous.inRuler(QPointF(0.0, 0.0), 200.0) &&
              !continuous.inRuler(QPointF(200.0, 0.0), 200.0) &&
              continuous.rulerVelocityAt(QPointF(0.0, continuous.labels()[0].y), 12.0) ==
                  continuous.labels()[0].velocity &&
              continuous.rulerVelocityAt(QPointF(0.0, continuous.labels()[0].y + 6.01), 12.0) == -1,
          "continuous ruler hit mapping should use label tolerance and bounds");
    QImage rulerImage(220, 200, QImage::Format_ARGB32);
    rulerImage.fill(Qt::white);
    VelocityAxisPaintStyle rulerStyle;
    rulerStyle.labelColor = QColor(Qt::red);
    rulerStyle.accentColor = QColor(Qt::blue);
    rulerStyle.labelFont = QFont{};
    rulerStyle.emphasizedFont = rulerStyle.labelFont;
    rulerStyle.separatorX = 198.0;
    rulerStyle.labelLeft = 2.0;
    rulerStyle.labelWidth = 190.0;
    rulerStyle.labelHeight = 12.0;
    rulerStyle.minorTickLength = 2.0;
    rulerStyle.majorTickLength = 6.0;
    rulerStyle.markerTickLength = 4.0;
    rulerStyle.graduationTickLength = 3.0;
    rulerStyle.contentClip = QRectF(198.0, 0.0, 22.0, 200.0);
    QPainter rulerPainter(&rulerImage);
    continuous.paintRuler(rulerPainter, rulerStyle);
    rulerPainter.end();
    bool paintedTick = false;
    for (int y = 5; y <= 7 && !paintedTick; ++y) {
        for (int x = 192; x <= 198; ++x) {
            if (rulerImage.pixelColor(x, y) == QColor(Qt::red)) {
                paintedTick = true;
                break;
            }
        }
    }
    check(paintedTick, "continuous ruler painter should render its major tick");
    check(VelocityAxis(unresolved, axisGeometry(83.0)).tickCount() == 5 &&
              VelocityAxis(unresolved, axisGeometry(84.0)).tickCount() == 9 &&
              VelocityAxis(unresolved, axisGeometry(112.0)).tickCount() == 9 &&
              VelocityAxis(unresolved, axisGeometry(156.0)).tickCount() == 17 &&
              VelocityAxis(unresolved, axisGeometry(300.0)).tickCount() == 32,
          "continuous density boundaries should be inclusive at each upper band");
    const std::array<uint8_t, 3> belowD2Labels = {127, 64, 1};
    const std::array<uint8_t, 5> atD2Labels = {127, 96, 64, 32, 1};
    const VelocityAxis belowD2(unresolved, axisGeometry(111.999));
    const VelocityAxis atD2(unresolved, axisGeometry(112.0));
    check(labelsMatch(belowD2, belowD2Labels.data(), belowD2Labels.size()) &&
              labelsMatch(atD2, atD2Labels.data(), atD2Labels.size()),
          "continuous labels should change at the D2 boundary");
    const std::array<uint8_t, 17> denseLabels = {
        127, 120, 112, 104, 96, 88, 80, 72, 64, 56, 48, 40, 32, 24, 16, 8, 1,
    };
    const VelocityAxis denseAxis(unresolved, axisGeometry(300.0));
    check(labelsMatch(denseAxis, denseLabels.data(), denseLabels.size()) &&
              denseAxis.tickCount() == 32 && denseAxis.ticks()[1].velocity == 123 &&
              denseAxis.ticks()[30].velocity == 7,
          "dense labels should be explicit and ordered apart from minor ticks");
    check(continuous.accessibleDescription() == "Velocity" && !VelocityAxis::nodesFocusable() &&
              !VelocityAxis::graduationLabelsFocusable(),
          "continuous accessibility should not create focus targets");

    const VelocityAxis noiseAxis(noise, axisGeometry(200.0));
    bool noiseAxisCorrect =
        noiseAxis.mode() == VelocityAxis::Mode::Intrinsic &&
        noiseAxis.graduationCount() == squareNoiseRepresentatives.size() &&
        noiseAxis.accessibleDescription() == "Velocity. Noise has 16 volume levels.";
    for (std::size_t level = 0; level < squareNoiseRepresentatives.size(); ++level) {
        const VelocityAxisGraduation &graduation = noiseAxis.graduations()[level];
        std::array<char, 24> expectedLabel{};
        std::snprintf(expectedLabel.data(), expectedLabel.size(), "Volume %u (%u)",
                      unsigned(level + 1), unsigned(squareNoiseRepresentatives[level]));
        noiseAxisCorrect = noiseAxisCorrect && graduation.level == uint8_t(level) &&
                           graduation.velocity == squareNoiseRepresentatives[level] &&
                           graduation.audible == (level != 0) &&
                           graduation.labelText() == expectedLabel.data() &&
                           !graduation.labelFocusable;
    }
    check(noiseAxisCorrect, "Noise axis should expose every level with its label and audibility");
    const VelocityAxis waveAxis(wave, axisGeometry(200.0), std::array<uint8_t, 1>{95}.data(), 1);
    check(waveAxis.mode() == VelocityAxis::Mode::Intrinsic && waveAxis.graduationCount() == 5 &&
              waveAxis.intrinsicColumnCount() == 1 && waveAxis.graduations()[3].velocity == 95 &&
              waveAxis.graduations()[3].labelText() == "Volume 4 (95)" &&
              !waveAxis.graduations()[0].audible && waveAxis.graduations()[1].audible &&
              waveAxis.accessibleDescription() ==
                  "Velocity. Programmable Wave has 5 volume levels.",
          "Wave labels should preserve one exact selected value");
    check(waveAxis.intrinsicColumnWidth() == 196.0 && waveAxis.graduations()[0].x == 2.0 &&
              waveAxis.graduations()[0].width == 196.0 && waveAxis.graduations()[4].x == 2.0 &&
              waveAxis.graduations()[4].width == 196.0 && waveAxis.graduations()[0].y == 194.0 &&
              waveAxis.graduations()[4].y == 6.0 && intrinsicLevelsRoundTrip(waveAxis),
          "one-column intrinsic geometry should preserve endpoints and level round trips");
    check(waveAxis.rulerVelocityAt(
              QPointF(waveAxis.graduations()[3].x + waveAxis.graduations()[3].width / 2.0,
                      waveAxis.graduations()[3].y),
              12.0) == 95 &&
              waveAxis.rulerVelocityAt(
                  QPointF(waveAxis.graduations()[3].x + waveAxis.graduations()[3].width + 0.1,
                          waveAxis.graduations()[3].y),
                  12.0) == -1,
          "intrinsic ruler hit mapping should honor staggered label rectangles");
    const std::array<uint8_t, 3> activeLevels = {1, 12, 20};
    const VelocityAxis squareAxis(square, axisGeometry(200.0), activeLevels.data(),
                                  activeLevels.size());
    check(squareAxis.graduationCount() == 16 && squareAxis.intrinsicColumnCount() == 2 &&
              !squareAxis.graduations()[0].audible && squareAxis.graduations()[1].audible &&
              squareAxis.graduations()[0].emphasized && !squareAxis.graduations()[1].emphasized &&
              squareAxis.graduations()[2].emphasized && squareAxis.graduations()[0].column == 1 &&
              squareAxis.graduations()[1].column == 0 &&
              !squareAxis.graduations()[0].labelFocusable,
          "intrinsic levels should use staggered columns and extrema emphasis");
    check(squareAxis.intrinsicColumnWidth() == 97.5 && squareAxis.graduations()[0].x == 100.5 &&
              squareAxis.graduations()[0].width == 97.5 && squareAxis.graduations()[1].x == 2.0 &&
              squareAxis.graduations()[1].width == 97.5 && squareAxis.graduations()[0].y == 194.0 &&
              squareAxis.graduations()[15].y == 6.0 && intrinsicLevelsRoundTrip(squareAxis),
          "two-column intrinsic geometry should preserve endpoints and level round trips");
    const std::array<uint8_t, 2> conflictingValues = {61, 64};
    const VelocityAxis conflictingAxis(square, axisGeometry(200.0), conflictingValues.data(),
                                       conflictingValues.size());
    check(conflictingAxis.graduations()[7].velocity == 60 &&
              conflictingAxis.graduations()[7].labelText() == "Volume 8 (60)",
          "conflicting exact values should fall back to the representative");
    const VelocityAxis narrowAxis(square, axisGeometry(200.0, 2.0));
    check(narrowAxis.intrinsicColumnWidth() == 0.0 && narrowAxis.graduations()[0].width == 0.0 &&
              narrowAxis.graduations()[0].x >= 0.0 && narrowAxis.graduations()[1].x >= 0.0,
          "narrow label geometry should remain non-negative");

    return failures == 0 ? 0 : 1;
}
