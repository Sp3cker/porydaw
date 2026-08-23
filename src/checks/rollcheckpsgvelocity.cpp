#include "checks/support/eventsynth.h"
#include "checks/support/songfixture.h"

#include "core/velocitymodel.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editordrawer/velocityaxis.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <optional>
#include <utility>
#include <vector>

#include <QApplication>
#include <QEvent>
#include <QFontMetricsF>
#include <QImage>
#include <QPainter>
#include <QTemporaryDir>
#include <QToolButton>

#include "core/miditimeline.h"
#include "core/noteid.h"
#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"
#include "ui/velocitygesturemodel.h"

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
struct ExpectedVelocityGeometry {
    int plotOrigin;
    int pianoKeyboardWidth;
    int densityThresholdD2;
    int densityThresholdD4;
    qreal nodePaintRadius;
    qreal nodeOutlineDipWidth;
};

ExpectedVelocityGeometry expectedVelocityGeometry()
{
    const int pianoKeyboardWidth = layout::fontPx(13.0 / 3.0);
    return {
        layout::fontPx(17.5 + 13.0 / 3.0), pianoKeyboardWidth,
        layout::fontPx(25.0 / 3.0),        layout::fontPx(24.0),
        layout::fontPxF(7.0 / 24.0),       layout::fontPxF(1.0 / 12.0),
    };
}

} // namespace

int runVelocityPageCheck(const QString &scratchProject, const QString &songLabel,
                         const QString &screenshotPath)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        if (!condition) {
            std::fprintf(stderr, "velocity-page: FAIL: %s\n", message);
            ++failures;
        }
    };
    if (scratchProject.isEmpty() || songLabel.isEmpty()) {
        std::fprintf(stderr, "velocity-page: FAIL: scratch project and song label are required\n");
        return 1;
    }
    QString fixtureError;
    auto fixtureSong = checks::LoadedSong::load(scratchProject, songLabel, fixtureError);
    if (!fixtureSong) {
        std::fprintf(stderr, "velocity-page: FAIL %s: could not load fixture song: %s\n",
                     qUtf8Printable(songLabel), qUtf8Printable(fixtureError));
        return 1;
    }
    SongDocument &fixtureDocument = fixtureSong->document();
    auto fixtureTimeline = fixtureDocument.buildTimeline(48000.0);
    if (!fixtureTimeline) {
        std::fprintf(stderr, "velocity-page: FAIL %s: could not build fixture timeline\n",
                     qUtf8Printable(songLabel));
        return 1;
    }
    LoadedVoiceGroup fixtureVoicegroup{};
    for (ToneData &tone : fixtureVoicegroup.voices)
        tone.type = VOICE_DIRECTSOUND;
    SongView fixtureView;
    fixtureView.resize(960, 480);
    fixtureView.setDocument(&fixtureDocument);
    fixtureView.setSong(fixtureTimeline.get(), &fixtureVoicegroup);
    fixtureView.setDrawerActivePage(EditorDrawerPage::Velocity);
    fixtureView.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    fixtureView.setDrawerSectionHeight(EditorDrawerPage::Velocity, 320);
    fixtureView.show();
    QApplication::processEvents();
    auto *fixtureDrawer = fixtureView.editorDrawer();
    auto *fixtureArea = fixtureDrawer ? fixtureDrawer->velocityArea() : nullptr;
    if (!fixtureArea) {
        std::fprintf(stderr,
                     "velocity-page: FAIL %s: fixture SongView did not expose VelocityArea\n",
                     qUtf8Printable(songLabel));
        return 1;
    }
    const auto expected = expectedVelocityGeometry();
    fixtureArea->resize(expected.plotOrigin + layout::space(layout::Space::Eight),
                        expected.densityThresholdD4 + layout::space(layout::Space::Six));
    fixtureArea->songChanged();
    DrawerPageLiveState fixtureLive;
    fixtureLive.documentRevision = fixtureDocument.revision();
    fixtureLive.timeZoom = 48.0;
    fixtureView.setEditorTimeZoom(fixtureLive.timeZoom);
    fixtureLive.timeZoom = fixtureView.pxPerBeat();
    fixtureLive.horizontalScroll = fixtureView.viewState().scrollPx;
    fixtureArea->refreshLiveState(fixtureLive);
    fixtureArea->show();
    QApplication::processEvents();
    const qreal zoomAnchorContentX = std::max(1, fixtureArea->plotWidth() / 2);
    const QPoint zoomAnchor(fixtureArea->plotOrigin() + qRound(zoomAnchorContentX),
                            fixtureArea->height() / 2);
    const double tickBeforeZoom = fixtureView.tickAtContentX(zoomAnchorContentX);
    const double zoomBefore = fixtureView.pxPerBeat();
    checks::events::sendWheel(*fixtureArea, QPointF(zoomAnchor), QPoint(), QPoint(0, 120),
                              Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase, false);
    QApplication::processEvents();
    check(fixtureView.pxPerBeat() > zoomBefore, "plain wheel must change velocity-lane time zoom");
    check(std::abs(fixtureView.tickAtContentX(zoomAnchorContentX) - tickBeforeZoom) < 0.001,
          "velocity-lane time zoom must preserve the tick under the cursor");
    int fixtureTrack = -1;
    DocNote fixtureNote;
    for (int track = 0; track < std::min(fixtureDocument.engineTrackCount(), 16); ++track) {
        const auto notes = fixtureDocument.notesForTrack(track);
        const auto note = std::find_if(notes.begin(), notes.end(), [](const DocNote &candidate) {
            return candidate.noteId.isAssigned();
        });
        if (note != notes.end()) {
            fixtureTrack = track;
            fixtureNote = *note;
            break;
        }
    }
    if (fixtureTrack < 0) {
        std::fprintf(stderr,
                     "velocity-page: FAIL %s: fixture song has no real note on a usable track\n",
                     qUtf8Printable(songLabel));
        fixtureView.hide();
        return 1;
    }
    fixtureView.selectTrack(fixtureTrack);
    fixtureView.selectionModel().setNoteSelection({fixtureNote.noteId});
    ++fixtureLive.editCursorTick;
    fixtureArea->refreshLiveState(fixtureLive);
    DocNote resolvedFixtureNote;
    const auto &fixtureMarkers = fixtureArea->axis().markers();
    check(fixtureView.document() == &fixtureDocument &&
              fixtureView.selectionModel().primaryTrack() == fixtureTrack &&
              fixtureView.selectionModel().noteSelection() ==
                  std::vector<NoteId>{fixtureNote.noteId} &&
              fixtureDocument.findNote(fixtureNote.noteId, &resolvedFixtureNote) &&
              resolvedFixtureNote.noteId == fixtureNote.noteId &&
              resolvedFixtureNote.velocity == fixtureNote.velocity &&
              fixtureArea->axis().mode() == VelocityAxis::Mode::Continuous &&
              fixtureArea->axis().markerCount() == 1 &&
              fixtureMarkers[0].velocity == fixtureNote.velocity &&
              std::abs(fixtureMarkers[0].y -
                       fixtureArea->axis().velocityToY(fixtureNote.velocity)) < 0.001,
          "requested fixture note, velocity, and axis data must reach its concrete VelocityArea");
    fixtureView.hide();
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
    view.setDrawerActivePage(EditorDrawerPage::Velocity);
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    view.setDrawerSectionHeight(EditorDrawerPage::Velocity, 320);
    view.show();
    QApplication::processEvents();
    auto *drawer = view.editorDrawer();
    auto *areaPtr = drawer ? drawer->velocityArea() : nullptr;
    check(drawer != nullptr && areaPtr != nullptr,
          "concrete SongView should expose its owned velocity area");
    if (!areaPtr)
        return 1;
    auto *drawerSections = drawer->findChild<QWidget *>(QStringLiteral("drawerSections"));
    auto *velToggle =
        drawerSections
            ? drawerSections->findChild<QToolButton *>(QStringLiteral("velocityDrawerToggle"))
            : nullptr;
    auto *automationBar =
        drawerSections ? drawerSections->findChild<QWidget *>(QStringLiteral("automationDrawerBar"))
                       : nullptr;
    auto *automationToggle =
        drawerSections
            ? drawerSections->findChild<QToolButton *>(QStringLiteral("automationDrawerToggle"))
            : nullptr;
    auto &area = *areaPtr;
    const QRect toggleGroup = automationToggle && velToggle
                                  ? automationToggle->geometry().united(velToggle->geometry())
                                  : QRect{};
    const int pianoKeysCenter = area.geometry().x() + area.plotOrigin() / 2;
    check(velToggle && automationBar && automationToggle &&
              automationBar->geometry().contains(velToggle->geometry()) &&
              velToggle->x() == automationToggle->x() + automationToggle->width() +
                                    layout::space(layout::Space::One) &&
              velToggle->y() == automationToggle->y() &&
              std::abs(toggleGroup.center().x() - pianoKeysCenter) <= 1,
          "drawer toggles must sit together beneath the piano keys");
    area.resize(expected.plotOrigin + layout::space(layout::Space::Eight),
                expected.densityThresholdD4 + layout::space(layout::Space::Six));
    area.songChanged();
    DrawerPageLiveState live;
    live.documentRevision = document.revision();
    live.timeZoom = 48.0;
    live.trackColor = QColor(Qt::cyan);
    view.setEditorTimeZoom(live.timeZoom);
    view.setEditorHorizontalScroll(live.horizontalScroll);
    live.timeZoom = view.pxPerBeat();
    live.horizontalScroll = view.viewState().scrollPx;
    area.refreshLiveState(live);
    area.show();
    QApplication::processEvents();
    auto *detentToggle = drawer->findChild<QToolButton *>(QStringLiteral("velocityDetentToggle"));
    check(detentToggle && detentToggle->parentWidget() &&
              detentToggle->parentWidget()->objectName() == QStringLiteral("drawerSections") &&
              detentToggle->isCheckable() && !detentToggle->isChecked() &&
              !detentToggle->isEnabled() && !detentToggle->isVisible() &&
              detentToggle->focusPolicy() == Qt::NoFocus,
          "drawer-owned velocity detent toggle must hide for DirectSound");
    check(area.axis().mode() == VelocityAxis::Mode::Continuous &&
              static_cast<const QWidget &>(area).accessibleDescription() ==
                  QStringLiteral("Velocity"),
          "DirectSound with no selection should publish the continuous accessible axis");
    check(area.focusPolicy() == Qt::ClickFocus && !VelocityAxis::nodesFocusable() &&
              !VelocityAxis::graduationLabelsFocusable(),
          "velocity nodes and ruler labels must add no focus targets");
    // This fixture has no time signature, so the implicit grid is 4/4.
    const auto ticksPerBar = uint64_t{timeline->ticksPerBeat} * 4;
    const auto firstBarPastSongEnd = (timeline->lengthTicks / ticksPerBar + 1) * ticksPerBar;
    area.resize(area.plotOrigin() + qCeil(double(firstBarPastSongEnd + timeline->ticksPerBeat) *
                                          live.timeZoom / double(timeline->ticksPerBeat)),
                expected.densityThresholdD4 + layout::space(layout::Space::Six));
    QApplication::processEvents();
    const auto gridPastSongEnd = area.grab().toImage();
    const auto gridScale = gridPastSongEnd.devicePixelRatio();
    const auto firstBarPastSongEndX =
        qRound((double(area.plotOrigin()) +
                double(firstBarPastSongEnd) * live.timeZoom / double(timeline->ticksPerBeat)) *
               gridScale);
    auto expectedGrid = QImage(gridPastSongEnd.size(), QImage::Format_ARGB32);
    expectedGrid.setDevicePixelRatio(gridScale);
    const auto gridBackground = themes::color(themes::Role::song_view_piano_roll_background).rgba();
    expectedGrid.fill(gridBackground);
    {
        auto expectedGridPainter = QPainter(&expectedGrid);
        view.paintGrid(expectedGridPainter,
                       QRect(area.plotOrigin(), 0, area.plotWidth(), area.height()),
                       area.plotOrigin());
    }
    const auto pastSongEndBounds = QRect(firstBarPastSongEndX - 2, 0, 5, gridPastSongEnd.height())
                                       .intersected(gridPastSongEnd.rect());
    auto matchedExpectedGrid = false;
    for (int y = pastSongEndBounds.top(); y <= pastSongEndBounds.bottom(); ++y) {
        for (int x = pastSongEndBounds.left(); x <= pastSongEndBounds.right(); ++x) {
            if (expectedGrid.pixel(x, y) != gridBackground &&
                gridPastSongEnd.pixel(x, y) == expectedGrid.pixel(x, y)) {
                matchedExpectedGrid = true;
                break;
            }
        }
        if (matchedExpectedGrid)
            break;
    }
    check(matchedExpectedGrid, "velocity grid must continue to the piano grid beyond the song end");
    live.editCursorTick = 0;
    view.goToStart();
    live.timeZoom = view.pxPerBeat();
    live.horizontalScroll = view.viewState().scrollPx;
    area.refreshLiveState(live);
    QApplication::processEvents();
    const auto beforePanPastZero = area.grab().toImage();
    const auto panStart =
        QPointF(area.plotOrigin() + layout::space(layout::Space::Two), area.height() / 2.0);
    const auto panLeftPastZero = panStart + QPointF(layout::space(layout::Space::Eight), 0.0);
    checks::events::sendMouse(area, QEvent::MouseButtonPress, panStart, Qt::MiddleButton,
                              Qt::MiddleButton, Qt::NoModifier);
    checks::events::sendMouse(area, QEvent::MouseMove, panLeftPastZero, Qt::NoButton,
                              Qt::MiddleButton, Qt::NoModifier);
    checks::events::sendMouse(area, QEvent::MouseButtonRelease, panLeftPastZero, Qt::MiddleButton,
                              Qt::NoButton, Qt::NoModifier);
    QApplication::processEvents();
    const auto afterPanPastZero = area.grab().toImage();
    check(view.viewState().scrollPx == live.horizontalScroll &&
              samePixels(beforePanPastZero, afterPanPastZero),
          "panning left at tick zero must not visually overscroll the velocity lane");
    area.refreshLiveState(live);
    QApplication::processEvents();
    area.resize(expected.plotOrigin + layout::space(layout::Space::Eight),
                expected.densityThresholdD2 + layout::space(layout::Space::One));
    QApplication::processEvents();
    const auto &directSoundLabels = area.axis().labels();
    check(area.axis().tickCount() == 9 && area.axis().labelCount() == 5 &&
              directSoundLabels[0].velocity == 127 && directSoundLabels[1].velocity == 96 &&
              directSoundLabels[2].velocity == 64 && directSoundLabels[3].velocity == 32 &&
              directSoundLabels[4].velocity == 1,
          "DirectSound must retain the original medium-height continuous graduations");
    area.resize(expected.plotOrigin + layout::space(layout::Space::Eight),
                expected.densityThresholdD4 + layout::space(layout::Space::Six));
    QApplication::processEvents();

    view.selectionModel().setNoteSelection({notes[0].noteId, notes[1].noteId});
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

    view.selectionModel().setNoteSelection({notes[0].noteId});
    ++live.editCursorTick;
    area.refreshLiveState(live);
    area.resize(
        expected.plotOrigin +
            qCeil(double(timeline->lengthTicks) * live.timeZoom / double(timeline->ticksPerBeat)) +
            layout::space(layout::Space::Two),
        expected.densityThresholdD4 + layout::space(layout::Space::Six));
    QApplication::processEvents();
    const VelocityMap map = VelocityMap::resolve(&noise, notes[0].key);
    const uint8_t hoveredPsgVelocity = 74;
    const std::size_t hoveredPsgLevel = 9;
    check(view.beginVelocityGesture({notes[1]}) &&
              view.updateVelocityGesture({{notes[1].noteId, hoveredPsgVelocity}}),
          "could not stage the nonrepresentative PSG hover velocity");
    QApplication::processEvents();
    std::array<ToneData, 128> hoverSplitChildren{};
    hoverSplitChildren[60] = noise;
    hoverSplitChildren[64] = wave;
    ToneData hoverSplit{};
    hoverSplit.type = VOICE_KEYSPLIT_ALL;
    hoverSplit.subGroup = hoverSplitChildren.data();
    voicegroup.voices[0] = hoverSplit;
    view.setVoicegroup(&voicegroup);
    view.selectionModel().setNoteSelection({notes[2].noteId});
    area.songChanged();
    ++live.editCursorTick;
    area.refreshLiveState(live);
    QApplication::processEvents();
    const VelocityMap selectedMap = VelocityMap::resolve(&wave, notes[2].key);
    const VelocityAxis hoveredNoiseProjection(map, area.axis().geometry());
    check(area.axis().map() == selectedMap && selectedMap != map,
          "hover context fixture must begin on the selected Wave note");
    checks::events::sendMouse(
        area, QEvent::MouseMove,
        QPointF(double(area.plotOrigin()) +
                    double(notes[1].tick) * live.timeZoom / double(timeline->ticksPerBeat) -
                    live.horizontalScroll,
                hoveredNoiseProjection.levelToY(int(hoveredPsgLevel))),
        Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    QApplication::processEvents();
    const auto &contextGraduations = area.axis().graduations();
    check(area.axis().map() == map && area.axis().graduationCount() == map.levelCount() &&
              contextGraduations[hoveredPsgLevel].active,
          "hovered PSG node must replace an incompatible selected-note axis context");
    QEvent mismatchedContextLeave(QEvent::Leave);
    QApplication::sendEvent(&area, &mismatchedContextLeave);
    voicegroup.voices[0] = noise;
    view.setVoicegroup(&voicegroup);
    view.selectionModel().setNoteSelection({notes[0].noteId});
    area.songChanged();
    ++live.editCursorTick;
    area.refreshLiveState(live);
    QApplication::processEvents();
    const std::optional<std::size_t> selectedLevel = map.levelOf(notes[0].velocity);
    const std::optional<std::size_t> unselectedLevel = map.levelOf(notes[1].velocity);
    const double paintNodeX =
        double(area.plotOrigin()) +
        double(notes[0].tick) * live.timeZoom / double(timeline->ticksPerBeat) -
        live.horizontalScroll;
    const double selectedY = selectedLevel ? area.axis().levelToY(int(*selectedLevel))
                                           : area.axis().velocityToY(notes[0].velocity);
    const double unselectedY = area.axis().levelToY(int(hoveredPsgLevel));
    const QImage velocityImage = area.grab().toImage();
    const qreal imageScale = velocityImage.devicePixelRatio();
    const auto pixelRect = [imageScale](const QRectF &logical) {
        return QRect(qRound(logical.x() * imageScale), qRound(logical.y() * imageScale),
                     qMax(1, qRound(logical.width() * imageScale)),
                     qMax(1, qRound(logical.height() * imageScale)));
    };
    const QColor expectedStem = songview::mixTowardOklab(live.trackColor, Qt::black, 1.0 / 3.0);
    const QRect velocityLabelBounds = pixelRect(
        QRectF(double(layout::space(layout::Space::Two)), 0.0,
               double(area.plotOrigin() - 2 * layout::space(layout::Space::Two)), area.height()));
    checks::events::sendMouse(area, QEvent::MouseMove, QPointF(paintNodeX, unselectedY),
                              Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    QApplication::processEvents();
    const QImage hoveredVelocityImage = area.grab().toImage();
    const auto &hoveredGraduations = area.axis().graduations();
    const auto activeHoveredGraduationCount = std::count_if(
        hoveredGraduations.begin(), hoveredGraduations.begin() + area.axis().graduationCount(),
        [](const VelocityAxisGraduation &graduation) { return graduation.active; });
    const auto hoveredPreview = view.previewVelocity(notes[1].noteId);
    check(area.useDetents() && area.axis().mode() == VelocityAxis::Mode::Intrinsic &&
              hoveredPreview && *hoveredPreview == hoveredPsgVelocity &&
              map.representative(int(hoveredPsgLevel)) == 76 &&
              hoveredGraduations[hoveredPsgLevel].active && activeHoveredGraduationCount == 1 &&
              !samePixels(velocityImage.copy(velocityLabelBounds),
                          hoveredVelocityImage.copy(velocityLabelBounds)),
          "with PSG detents enabled, hovering MIDI velocity 74 must isolate Noise Vol 10 "
          "instead of raw MIDI 74");
    area.setUseDetents(false);
    QApplication::processEvents();
    const QImage rawHoveredVelocityImage = area.grab().toImage();
    const auto &rawHoveredMarkers = area.axis().markers();
    check(!area.useDetents() && area.axis().markerCount() == 1 &&
              rawHoveredMarkers[0].velocity == hoveredPsgVelocity &&
              std::abs(rawHoveredMarkers[0].y - area.axis().velocityToY(hoveredPsgVelocity)) <
                  0.001 &&
              !samePixels(hoveredVelocityImage.copy(velocityLabelBounds),
                          rawHoveredVelocityImage.copy(velocityLabelBounds)),
          "with PSG detents disabled, hovering MIDI velocity 74 must isolate raw MIDI 74");
    area.setUseDetents(true);
    QEvent velocityLeave(QEvent::Leave);
    QApplication::sendEvent(&area, &velocityLeave);
    QApplication::processEvents();
    const QImage restoredVelocityImage = area.grab().toImage();
    check(samePixels(velocityImage.copy(velocityLabelBounds),
                     restoredVelocityImage.copy(velocityLabelBounds)),
          "leaving a hovered velocity node must restore the graduation labels");
    const QRect stemBounds = pixelRect(QRectF(paintNodeX + 8.0, unselectedY - 3.0, 16.0, 6.0));
    const QPointF unselectedNodeCenter(paintNodeX * imageScale, unselectedY * imageScale);
    const qreal outlineRadius = expected.nodePaintRadius * imageScale;
    const qreal outlineWidth = expected.nodeOutlineDipWidth * imageScale;
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
    const QRect unselectedNodeFillBounds =
        pixelRect(QRectF(paintNodeX - 3.0, unselectedY - 3.0, 6.0, 6.0));
    check(hasColorNear(velocityImage, unselectedNodeFillBounds, live.trackColor, 4),
          "a single-node selection must preserve unselected velocity node colors");
    view.selectionModel().setNoteSelection({notes[0].noteId, notes[2].noteId});
    ++live.editCursorTick;
    area.refreshLiveState(live);
    QApplication::processEvents();
    const QImage multiSelectionImage = area.grab().toImage();
    check(hasColorNear(multiSelectionImage, unselectedNodeFillBounds, area.palette().mid().color(),
                       4),
          "nodes outside a multi-node velocity selection must turn gray");
    check(!hasDarkOutlinePixel(multiSelectionImage, unselectedNodeCenter,
                               std::max(0.0, outlineRadius - outlineWidth),
                               outlineRadius + outlineWidth),
          "nodes outside a multi-node velocity selection must omit their outlines");
    view.cancelVelocityGesture();
    QApplication::processEvents();
    view.selectionModel().setNoteSelection({notes[0].noteId});
    ++live.editCursorTick;
    area.refreshLiveState(live);
    const QRect rulerAccentBounds =
        pixelRect(QRectF(double(area.plotOrigin() - layout::singlePixel() -
                                3 * layout::space(layout::Space::Half) - 1),
                         selectedY - 2.0, double(3 * layout::space(layout::Space::Half) + 2), 4.0));
    check(hasColorNear(velocityImage, rulerAccentBounds, area.palette().highlight().color(), 16),
          "intrinsic ruler paint must preserve the emphasized accent tick");
    live.editCursorTick = 12;
    area.refreshLiveState(live);
    const QImage firstEditCursor = area.grab().toImage();
    live.editCursorTick = 18;
    area.refreshLiveState(live);
    const QImage secondEditCursor = area.grab().toImage();
    const qreal cursorX =
        (double(area.plotOrigin()) + 18.0 * live.timeZoom / double(timeline->ticksPerBeat) -
         live.horizontalScroll) *
        imageScale;
    const QRect cursorBounds(qRound(cursorX) - 2, 0, 5, secondEditCursor.height());
    check(!samePixels(firstEditCursor, secondEditCursor),
          "moving the edit cursor must repaint the velocity lane");
    check(hasColorNear(secondEditCursor, cursorBounds,
                       themes::color(themes::Role::song_view_edit_cursor), 16),
          "velocity lane must paint the shared edit cursor");

    area.clearTrackHeaderSelection();
    check(view.selectionModel().noteSelection().empty(),
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

    const auto rebuildConnection =
        QObject::connect(&document, &SongDocument::documentChanged, &view, [&] {
            auto rebuilt = document.buildTimeline(48000.0);
            if (!rebuilt)
                return;
            timeline = std::move(rebuilt);
            view.updateSong(timeline.get());
        });
    view.selectionModel().setNoteSelection({notes[0].noteId, notes[1].noteId});
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
    const double stemX =
        nodeX + double(notes[0].duration) * live.timeZoom / double(timeline->ticksPerBeat) * 0.5;
    const QPointF stem(stemX, nodeY);
    const QPointF firstDrag = stem + QPointF(0.0, double(area.height()));
    const QPointF drag = stem + QPointF(0.0, -double(area.height()));
    checks::events::sendMouse(area, QEvent::MouseButtonPress, stem, Qt::LeftButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(area, QEvent::MouseMove, firstDrag, Qt::NoButton, Qt::LeftButton,
                              Qt::NoModifier);
    check(view.selectionModel().noteSelection() ==
              std::vector<NoteId>({notes[0].noteId, notes[1].noteId}),
          "dragging selected velocity nodes must preserve their shared selection");
    const auto firstPreviewFirst = view.previewVelocity(notes[0].noteId);
    const auto firstPreviewSecond = view.previewVelocity(notes[1].noteId);
    DocNote draggedFirst;
    DocNote draggedSecond;
    check(
        document.findNote(notes[0].noteId, &draggedFirst) &&
            document.findNote(notes[1].noteId, &draggedSecond) &&
            draggedFirst.velocity == notes[0].velocity &&
            draggedSecond.velocity == notes[1].velocity && firstPreviewFirst &&
            firstPreviewSecond && *firstPreviewFirst != notes[0].velocity &&
            *firstPreviewSecond != notes[1].velocity &&
            document.revision() == revisionBeforeGesture &&
            document.undoStack()->count() == undoDepth,
        "velocity drag moves must update preview without changing document revision or undo depth");
    const QImage activeDrag = area.grab().toImage();
    const uint8_t firstPreviewVelocity = firstPreviewFirst.value_or(notes[0].velocity);
    const std::optional<std::size_t> firstDraggedLevel = map.levelOf(firstPreviewVelocity);
    const double firstDraggedY = firstDraggedLevel ? area.axis().levelToY(int(*firstDraggedLevel))
                                                   : area.axis().velocityToY(firstPreviewVelocity);
    const QRect activeDragRing = pixelRect(QRectF(nodeX - 6.0, firstDraggedY - 6.0, 4.0, 12.0));
    check(hasColorNear(activeDrag, activeDragRing, area.palette().highlight().color(), 16),
          "dragging a selected velocity node must retain its visible selection ring");
    checks::events::sendMouse(area, QEvent::MouseMove, drag, Qt::NoButton, Qt::LeftButton,
                              Qt::NoModifier);
    const auto finalPreviewFirst = view.previewVelocity(notes[0].noteId);
    const auto finalPreviewSecond = view.previewVelocity(notes[1].noteId);
    check(finalPreviewFirst && finalPreviewSecond && firstPreviewFirst &&
              *finalPreviewFirst != *firstPreviewFirst &&
              document.revision() == revisionBeforeGesture &&
              document.undoStack()->count() == undoDepth,
          "successive velocity updates must remain deferred while the drag is held");
    checks::events::sendMouse(area, QEvent::MouseButtonRelease, drag, Qt::LeftButton, Qt::NoButton,
                              Qt::NoModifier);
    QObject::disconnect(rebuildConnection);
    DocNote committedFirst;
    DocNote committedSecond;
    check(document.revision() == revisionBeforeGesture + 1 &&
              document.undoStack()->count() == undoDepth + 1 &&
              !view.previewVelocity(notes[0].noteId) && !view.previewVelocity(notes[1].noteId) &&
              finalPreviewFirst && finalPreviewSecond &&
              document.findNote(notes[0].noteId, &committedFirst) &&
              document.findNote(notes[1].noteId, &committedSecond) &&
              committedFirst.velocity == *finalPreviewFirst &&
              committedSecond.velocity == *finalPreviewSecond &&
              view.selectionModel().noteSelection() ==
                  std::vector<NoteId>({notes[0].noteId, notes[1].noteId}),
          "relative drag must commit both final previews in one batch and preserve selection");
    const std::vector<NoteId> selectedBeforeUndo = view.selectionModel().noteSelection();
    document.undoStack()->undo();
    area.documentChanged();
    live.documentRevision = document.revision();
    area.refreshLiveState(live);
    QApplication::processEvents();
    check(view.selectionModel().noteSelection() == selectedBeforeUndo,
          "Undo must preserve the shared selection identities of surviving notes");
    DocNote restoredFirst;
    check(document.findNote(notes[0].noteId, &restoredFirst),
          "click-collapse fixture must resolve the restored velocity note");
    const std::optional<std::size_t> restoredLevel = map.levelOf(restoredFirst.velocity);
    const QPointF restoredNode(nodeX, restoredLevel
                                          ? area.axis().levelToY(int(*restoredLevel))
                                          : area.axis().velocityToY(restoredFirst.velocity));
    checks::events::sendMouse(area, QEvent::MouseButtonPress, restoredNode, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(area, QEvent::MouseButtonRelease, restoredNode, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    check(view.selectionModel().noteSelection() == std::vector<NoteId>{notes[0].noteId},
          "clicking one selected velocity node must collapse the other selected nodes");

    view.selectionModel().setNoteSelection({notes[0].noteId});
    ++live.editCursorTick;
    area.refreshLiveState(live);
    const std::optional<std::size_t> secondLevel = map.levelOf(notes[1].velocity);
    const QPointF secondNode(nodeX, secondLevel ? area.axis().levelToY(int(*secondLevel))
                                                : area.axis().velocityToY(notes[1].velocity));
    const int undoDepthBeforeUngrab = document.undoStack()->count();
    checks::events::sendMouse(area, QEvent::MouseButtonPress, secondNode, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    QEvent ungrabMouse(QEvent::UngrabMouse);
    QApplication::sendEvent(&area, &ungrabMouse);
    check(view.selectionModel().noteSelection() == std::vector<NoteId>{notes[0].noteId} &&
              document.undoStack()->count() == undoDepthBeforeUngrab,
          "mouse ungrab must cancel a provisional selection without history residue");

    const QRect selectorProbe(area.plotOrigin() + layout::space(layout::Space::One),
                              area.height() / 3, 2 * layout::space(layout::Space::Eight),
                              layout::space(layout::Space::Eight));
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
    checks::events::sendMouse(area, QEvent::MouseButtonPress, selectorStart, Qt::RightButton,
                              Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(area, QEvent::MouseMove, selectorEnd, Qt::NoButton, Qt::RightButton,
                              Qt::NoModifier);
    QApplication::processEvents();
    const QImage activeBand = grabSelectorProbe();
    check(!samePixels(bandBaseline, activeBand),
          "drag-select must visibly paint its selector overlay");
    QColor selectionFill = themes::color(themes::Role::song_view_selection_fill);
    selectionFill.setAlpha(30);
    const auto blendedChannel = [&selectionFill](int background, int foreground) {
        return (foreground * selectionFill.alpha() + background * (255 - selectionFill.alpha()) +
                127) /
               255;
    };
    const auto channelDifference = [](int left, int right) { return std::abs(left - right); };
    const int interiorMargin = qCeil(2.0 * activeBand.devicePixelRatio());
    int sampledPixels = 0;
    int translucentPixels = 0;
    for (int y = interiorMargin; y < activeBand.height() - interiorMargin; ++y) {
        for (int x = interiorMargin; x < activeBand.width() - interiorMargin; ++x) {
            const QColor baselinePixel(bandBaseline.pixel(x, y));
            const QColor activePixel(activeBand.pixel(x, y));
            const QColor expectedPixel(blendedChannel(baselinePixel.red(), selectionFill.red()),
                                       blendedChannel(baselinePixel.green(), selectionFill.green()),
                                       blendedChannel(baselinePixel.blue(), selectionFill.blue()));
            ++sampledPixels;
            if (channelDifference(activePixel.red(), expectedPixel.red()) <= 1 &&
                channelDifference(activePixel.green(), expectedPixel.green()) <= 1 &&
                channelDifference(activePixel.blue(), expectedPixel.blue()) <= 1) {
                ++translucentPixels;
            }
        }
    }
    check(sampledPixels > 0 && translucentPixels * 2 >= sampledPixels,
          "drag-select must composite the translucent selection fill over velocity content");
    checks::events::sendMouse(area, QEvent::MouseMove, selectorContractedEnd, Qt::NoButton,
                              Qt::RightButton, Qt::NoModifier);
    QApplication::processEvents();
    const QImage contractedBand = grabSelectorProbe();
    check(!samePixels(bandBaseline, contractedBand) &&
              samePixels(abandonedCorner(bandBaseline), abandonedCorner(contractedBand)),
          "contracting drag-select must clear the abandoned selector area");
    checks::events::sendMouse(area, QEvent::MouseButtonRelease, selectorContractedEnd,
                              Qt::RightButton, Qt::NoButton, Qt::NoModifier);
    QApplication::processEvents();
    check(samePixels(bandBaseline, grabSelectorProbe()),
          "completed drag-select must clear its selector overlay");

    view.selectionModel().setNoteSelection({notes[0].noteId});
    ++live.editCursorTick;
    area.refreshLiveState(live);
    QApplication::processEvents();
    const QImage cancelledBandBaseline = grabSelectorProbe();
    checks::events::sendMouse(area, QEvent::MouseButtonPress, selectorStart, Qt::RightButton,
                              Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(area, QEvent::MouseMove, selectorEnd, Qt::NoButton, Qt::RightButton,
                              Qt::NoModifier);
    QApplication::processEvents();
    QEvent cancelBand(QEvent::UngrabMouse);
    QApplication::sendEvent(&area, &cancelBand);
    QApplication::processEvents();
    check(view.selectionModel().noteSelection() == std::vector<NoteId>{notes[0].noteId} &&
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
    checks::events::sendMouse(area, QEvent::MouseButtonPress, currentNode, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(area, QEvent::MouseButtonRelease, currentNode, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    check(view.selectionModel().noteSelection() == std::vector<NoteId>{notes[0].noteId},
          "selected velocity node must win a stacked-node click");
    document.addNote(0, currentFirst.tick + 8, currentFirst.key, currentFirst.duration,
                     currentFirst.velocity);
    live.documentRevision = document.revision();
    area.refreshLiveState(live);
    QApplication::processEvents();
    const std::vector<DocNote> overlapFixtureNotes = document.notesForTrack(0);
    live.timeZoom = view.pxPerBeat();
    live.horizontalScroll = view.viewState().scrollPx;
    const auto overlapIt = std::find_if(overlapFixtureNotes.cbegin(), overlapFixtureNotes.cend(),
                                        [&currentFirst](const DocNote &note) {
                                            return note.tick == currentFirst.tick + 8 &&
                                                   note.noteId != currentFirst.noteId;
                                        });
    check(overlapIt != overlapFixtureNotes.cend(),
          "velocity overlap fixture must add a circle candidate beside a duration stem");
    if (overlapIt != overlapFixtureNotes.cend()) {
        const DocNote overlapNote = *overlapIt;
        const auto velocityNode = [&area, &currentMap, &live, &timeline](const DocNote &note) {
            const double x = double(area.plotOrigin()) +
                             double(note.tick) * live.timeZoom / double(timeline->ticksPerBeat) -
                             live.horizontalScroll;
            const std::optional<std::size_t> level = currentMap.levelOf(note.velocity);
            const bool intrinsic = area.axis().mode() == VelocityAxis::Mode::Intrinsic &&
                                   area.axis().map().compatibleWith(currentMap);
            const double y = intrinsic && level ? area.axis().levelToY(int(*level))
                                                : area.axis().velocityToY(note.velocity);
            return QPointF(x, y);
        };
        view.selectionModel().setNoteSelection({});
        ++live.editCursorTick;
        area.refreshLiveState(live);
        QApplication::processEvents();
        const QPointF stackedNode = velocityNode(currentFirst);
        checks::events::sendMouse(area, QEvent::MouseButtonPress, stackedNode, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        check(view.selectionModel().noteSelection() == std::vector<NoteId>{notes[1].noteId},
              "overlapping circles must resolve to one later-painted target");
        checks::events::sendMouse(area, QEvent::MouseButtonRelease, stackedNode, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        check(view.selectionModel().noteSelection() == std::vector<NoteId>{notes[1].noteId},
              "overlapping-circle release must retain its frozen target");
        ++live.editCursorTick;
        view.selectionModel().setNoteSelection({notes[0].noteId});
        area.refreshLiveState(live);
        QApplication::processEvents();
        const QPointF selectedStackedNode = velocityNode(currentFirst);
        checks::events::sendMouse(area, QEvent::MouseButtonPress, selectedStackedNode,
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        check(view.selectionModel().noteSelection() == std::vector<NoteId>{notes[0].noteId},
              "selected overlapping velocity nodes must outrank unselected candidates");
        checks::events::sendMouse(area, QEvent::MouseButtonRelease, selectedStackedNode,
                                  Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
        check(view.selectionModel().noteSelection() == std::vector<NoteId>{notes[0].noteId},
              "selected-layer velocity click must keep its selected target");
        view.selectionModel().setNoteSelection({});
        ++live.editCursorTick;
        area.refreshLiveState(live);
        QApplication::processEvents();
        const QPointF circleNode = velocityNode(overlapNote);
        checks::events::sendMouse(area, QEvent::MouseButtonPress, circleNode, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        QApplication::processEvents();
        const QImage circleHeld = area.grab().toImage();
        const QRect circleRingBounds =
            pixelRect(QRectF(circleNode.x() - 6.0, circleNode.y() - 6.0, 4.0, 12.0));
        check(
            view.selectionModel().noteSelection() == std::vector<NoteId>{overlapNote.noteId} &&
                hasColorNear(circleHeld, circleRingBounds, area.palette().highlight().color(), 16),
            "a circle hit must outrank stem-only overlap and paint one selected ring");
        const QPointF movedRelease = velocityNode(currentFirst);
        checks::events::sendMouse(area, QEvent::MouseMove, movedRelease, Qt::NoButton,
                                  Qt::LeftButton, Qt::NoModifier);
        check(view.selectionModel().noteSelection() == std::vector<NoteId>{overlapNote.noteId},
              "a velocity gesture must retain its frozen target while the cursor moves");
        checks::events::sendMouse(area, QEvent::MouseButtonRelease, movedRelease, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        check(view.selectionModel().noteSelection() == std::vector<NoteId>{overlapNote.noteId},
              "moving release away from a velocity node must not click through to another target");
        const DocNote rightTarget = notes[2];
        view.selectionModel().setNoteSelection({notes[0].noteId});
        ++live.editCursorTick;
        area.refreshLiveState(live);
        QApplication::processEvents();
        const QPointF rightTargetNode = velocityNode(rightTarget);
        checks::events::sendMouse(area, QEvent::MouseButtonPress, rightTargetNode, Qt::RightButton,
                                  Qt::RightButton, Qt::NoModifier);
        QApplication::processEvents();
        const QImage rightNodeHeld = area.grab().toImage();
        const QRect rightNodeRingBounds =
            pixelRect(QRectF(rightTargetNode.x() - 6.0, rightTargetNode.y() - 6.0, 4.0, 12.0));
        check(
            view.selectionModel().noteSelection() == std::vector<NoteId>{rightTarget.noteId} &&
                hasColorNear(rightNodeHeld, rightNodeRingBounds, area.palette().highlight().color(),
                             16),
            "plain right press on an unselected velocity node must select and ring it immediately");
        checks::events::sendMouse(area, QEvent::MouseButtonRelease, rightTargetNode,
                                  Qt::RightButton, Qt::NoButton, Qt::NoModifier);
        QApplication::processEvents();
        const QImage rightNodeReleased = area.grab().toImage();
        check(view.selectionModel().noteSelection() == std::vector<NoteId>{rightTarget.noteId} &&
                  hasColorNear(rightNodeReleased, rightNodeRingBounds,
                               area.palette().highlight().color(), 16),
              "plain right release must retain its selected velocity node and ring");
        view.selectionModel().setNoteSelection({notes[0].noteId, rightTarget.noteId});
        ++live.editCursorTick;
        area.refreshLiveState(live);
        QApplication::processEvents();
        const QPointF selectedRightNode = velocityNode(currentFirst);
        checks::events::sendMouse(area, QEvent::MouseButtonPress, selectedRightNode,
                                  Qt::RightButton, Qt::RightButton, Qt::NoModifier);
        QApplication::processEvents();
        const QImage selectedRightHeld = area.grab().toImage();
        const QRect selectedRightRingBounds =
            pixelRect(QRectF(selectedRightNode.x() - 6.0, selectedRightNode.y() - 6.0, 4.0, 12.0));
        check(view.selectionModel().noteSelection() ==
                      std::vector<NoteId>({notes[0].noteId, rightTarget.noteId}) &&
                  hasColorNear(selectedRightHeld, selectedRightRingBounds,
                               area.palette().highlight().color(), 16),
              "plain right press on a selected velocity node must retain its visual group");
        checks::events::sendMouse(area, QEvent::MouseButtonRelease, selectedRightNode,
                                  Qt::RightButton, Qt::NoButton, Qt::NoModifier);
        QApplication::processEvents();
        const QImage selectedRightReleased = area.grab().toImage();
        check(view.selectionModel().noteSelection() ==
                      std::vector<NoteId>({notes[0].noteId, rightTarget.noteId}) &&
                  hasColorNear(selectedRightReleased, selectedRightRingBounds,
                               area.palette().highlight().color(), 16),
              "plain right release on a selected velocity node must retain its group ring");
        document.deleteNotes({overlapNote});
        live.documentRevision = document.revision();
        area.refreshLiveState(live);
        QApplication::processEvents();
    }
    view.selectionModel().setNoteSelection({notes[0].noteId, notes[2].noteId});
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
    checks::events::sendMouse(area, QEvent::MouseButtonPress, paintStart, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(area, QEvent::MouseMove, paintEnd, Qt::NoButton, Qt::LeftButton,
                              Qt::NoModifier);
    const auto paintPreviewFirst = view.previewVelocity(notes[0].noteId);
    const auto paintPreviewThird = view.previewVelocity(notes[2].noteId);
    check(view.selectionModel().noteSelection() ==
                  std::vector<NoteId>({notes[0].noteId, notes[2].noteId}) &&
              document.revision() == revisionBeforePaint &&
              document.undoStack()->index() == undoIndexBeforePaint && paintPreviewFirst &&
              paintPreviewThird && *paintPreviewFirst == currentMap.representative(0) &&
              *paintPreviewThird == currentMap.representative(4),
          "holding velocity paint must update preview while deferring document changes");
    checks::events::sendMouse(area, QEvent::MouseButtonRelease, paintEnd, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    DocNote paintedFirst;
    DocNote paintedThird;
    check(document.revision() == revisionBeforePaint + 1 &&
              document.undoStack()->index() == undoIndexBeforePaint + 1 &&
              !view.previewVelocity(notes[0].noteId) && !view.previewVelocity(notes[2].noteId) &&
              document.findNote(notes[0].noteId, &paintedFirst) &&
              document.findNote(notes[2].noteId, &paintedThird) &&
              paintedFirst.velocity == currentMap.representative(0) &&
              paintedThird.velocity == currentMap.representative(4),
          "held velocity paint must commit one batch and clear its preview");

    document.addNote(0, 36, paintFirstBefore.key, 12, currentMap.representative(3));
    const std::vector<DocNote> rampFixtureNotes = document.notesForTrack(0);
    const auto rampMiddleIt = std::find_if(rampFixtureNotes.cbegin(), rampFixtureNotes.cend(),
                                           [](const DocNote &note) { return note.tick == 36; });
    check(rampMiddleIt != rampFixtureNotes.cend(),
          "velocity ramp fixture must create its midpoint note");
    if (rampMiddleIt != rampFixtureNotes.cend()) {
        const DocNote rampMiddleBefore = *rampMiddleIt;
        live.documentRevision = document.revision();
        area.refreshLiveState(live);
        view.selectionModel().setNoteSelection(
            {notes[0].noteId, rampMiddleBefore.noteId, notes[2].noteId});
        const QPointF rampStart(paintGestureX(paintFirstBefore), area.axis().levelToY(0));
        const QPointF rampEnd(paintGestureX(paintThirdBefore), area.axis().levelToY(4));
        const uint64_t revisionBeforeRamp = document.revision();
        const int undoIndexBeforeRamp = document.undoStack()->index();
        checks::events::sendMouse(area, QEvent::MouseButtonPress, rampStart, Qt::LeftButton,
                                  Qt::LeftButton, Qt::ShiftModifier);
        checks::events::sendMouse(area, QEvent::MouseMove, rampEnd, Qt::NoButton, Qt::LeftButton,
                                  Qt::ShiftModifier);
        const auto rampPreviewFirst = view.previewVelocity(notes[0].noteId);
        const auto rampPreviewMiddle = view.previewVelocity(rampMiddleBefore.noteId);
        const auto rampPreviewThird = view.previewVelocity(notes[2].noteId);
        check(document.revision() == revisionBeforeRamp &&
                  document.undoStack()->index() == undoIndexBeforeRamp && rampPreviewFirst &&
                  rampPreviewMiddle && rampPreviewThird &&
                  *rampPreviewFirst == currentMap.representative(0) &&
                  *rampPreviewMiddle == currentMap.representative(2) &&
                  *rampPreviewThird == currentMap.representative(4),
              "holding a velocity ramp must update preview while deferring document changes");
        const QPointF rampQuarter = rampStart + 0.25 * (rampEnd - rampStart);
        const QImage rampPreview = area.grab().toImage();
        check(
            hasColorNear(rampPreview,
                         pixelRect(QRectF(rampQuarter.x() - 2.0, rampQuarter.y() - 2.0, 5.0, 5.0)),
                         themes::color(themes::Role::song_view_edit_preview_outline), 24),
            "velocity Shift-drag did not render its ramp line preview");
        checks::events::sendMouse(area, QEvent::MouseButtonRelease, rampEnd, Qt::LeftButton,
                                  Qt::NoButton, Qt::ShiftModifier);
        DocNote rampedFirst;
        DocNote rampedMiddle;
        DocNote rampedThird;
        check(document.revision() == revisionBeforeRamp + 1 &&
                  document.undoStack()->index() == undoIndexBeforeRamp + 1 &&
                  !view.previewVelocity(notes[0].noteId) &&
                  !view.previewVelocity(rampMiddleBefore.noteId) &&
                  !view.previewVelocity(notes[2].noteId) &&
                  view.selectionModel().noteSelection() ==
                      std::vector<NoteId>(
                          {notes[0].noteId, rampMiddleBefore.noteId, notes[2].noteId}) &&
                  document.findNote(notes[0].noteId, &rampedFirst) &&
                  document.findNote(rampMiddleBefore.noteId, &rampedMiddle) &&
                  document.findNote(notes[2].noteId, &rampedThird) &&
                  rampedFirst.velocity == currentMap.representative(0) &&
                  rampedMiddle.velocity == currentMap.representative(2) &&
                  rampedThird.velocity == currentMap.representative(4),
              "Shift-drag must commit one ramp batch and clear its preview");
        document.deleteNotes({rampMiddleBefore});
        live.documentRevision = document.revision();
        area.refreshLiveState(live);
        view.selectionModel().setNoteSelection({notes[0].noteId, notes[2].noteId});
    }

    const QPointF blankPoint(double(area.plotOrigin() + area.plotWidth() - 4),
                             area.axis().levelToY(2));
    const uint64_t revisionBeforeBlankClick = document.revision();
    const int undoDepthBeforeBlankClick = document.undoStack()->count();
    checks::events::sendMouse(area, QEvent::MouseButtonPress, blankPoint, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    check(view.selectionModel().noteSelection() ==
              std::vector<NoteId>({notes[0].noteId, notes[2].noteId}),
          "blank velocity press must retain selection until mouse-up");
    checks::events::sendMouse(area, QEvent::MouseButtonRelease, blankPoint, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    check(view.selectionModel().noteSelection().empty() &&
              document.revision() == revisionBeforeBlankClick &&
              document.undoStack()->count() == undoDepthBeforeBlankClick,
          "blank velocity click must deselect only on mouse-up");

    view.selectionModel().setNoteSelection({notes[0].noteId, notes[1].noteId});
    const VelocityAxisGraduation graduation = area.axis().graduations()[2];
    const QPointF graduationPoint(graduation.x + graduation.width / 2.0, graduation.y);
    checks::events::sendMouse(area, QEvent::MouseButtonPress, graduationPoint, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(area, QEvent::MouseButtonRelease, graduationPoint, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    DocNote graduatedFirst;
    DocNote graduatedSecond;
    check(view.selectionModel().noteSelection() ==
                  std::vector<NoteId>({notes[0].noteId, notes[1].noteId}) &&
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
            double(expected.pianoKeyboardWidth) +
                double(view.contentX(double(graduatedFirst.tick) +
                                     double(graduatedFirst.duration) / 2.0)),
            (127.5 - double(graduatedFirst.key)) * view.keyHeight() - view.scrollY());
        const QPointF rollDragPosition = rollNoteCenter - QPointF(0.0, double(dragDelta));
        const auto stageRollVelocityPreview = [&]() {
            checks::events::sendMouse(*roll, QEvent::MouseButtonPress, rollNoteCenter,
                                      Qt::LeftButton, Qt::LeftButton, velocityDragModifiers);
            checks::events::sendMouse(*roll, QEvent::MouseMove, rollDragPosition, Qt::NoButton,
                                      Qt::LeftButton, velocityDragModifiers);
            QApplication::processEvents();
        };

        DocNote cancelledBefore;
        DocNote cancelledBeforeSecond;
        check(document.findNote(graduatedFirst.noteId, &cancelledBefore) &&
                  document.findNote(graduatedSecond.noteId, &cancelledBeforeSecond),
              "piano-roll cancellation fixture must retain its target notes");
        const uint64_t revisionBeforeRollCancel = document.revision();
        const int undoIndexBeforeRollCancel = document.undoStack()->index();
        const int undoCountBeforeRollCancel = document.undoStack()->count();
        stageRollVelocityPreview();
        const auto cancellationPreview = view.previewVelocity(graduatedFirst.noteId);
        const auto cancellationPreviewSecond = view.previewVelocity(graduatedSecond.noteId);
        check(cancellationPreview && cancellationPreviewSecond &&
                  (*cancellationPreview != cancelledBefore.velocity ||
                   *cancellationPreviewSecond != cancelledBeforeSecond.velocity) &&
                  document.revision() == revisionBeforeRollCancel &&
                  document.undoStack()->index() == undoIndexBeforeRollCancel &&
                  document.undoStack()->count() == undoCountBeforeRollCancel,
              "piano-roll cancellation must stage a changed deferred velocity preview");
        view.cancelActiveInteractions();
        checks::events::sendMouse(*roll, QEvent::MouseMove, rollDragPosition, Qt::NoButton,
                                  Qt::LeftButton, velocityDragModifiers);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, rollDragPosition,
                                  Qt::LeftButton, Qt::NoButton, velocityDragModifiers);
        QApplication::processEvents();
        DocNote cancelledAfter;
        DocNote cancelledAfterSecond;
        check(!view.previewVelocity(graduatedFirst.noteId) &&
                  !view.previewVelocity(graduatedSecond.noteId) &&
                  document.revision() == revisionBeforeRollCancel &&
                  document.undoStack()->index() == undoIndexBeforeRollCancel &&
                  document.undoStack()->count() == undoCountBeforeRollCancel &&
                  document.findNote(graduatedFirst.noteId, &cancelledAfter) &&
                  document.findNote(graduatedSecond.noteId, &cancelledAfterSecond) &&
                  cancelledAfter.velocity == cancelledBefore.velocity &&
                  cancelledAfterSecond.velocity == cancelledBeforeSecond.velocity,
              "SongView cancellation must clear piano-roll local drag state and prevent commit");

        const uint64_t revisionBeforeRollDrag = document.revision();
        const int undoBeforeRollDrag = document.undoStack()->count();
        stageRollVelocityPreview();
        const uint8_t previewVelocity =
            uint8_t(std::clamp(int(graduatedFirst.velocity) + dragDelta, 1, 127));
        const uint8_t secondPreviewVelocity =
            uint8_t(std::clamp(int(graduatedSecond.velocity) + dragDelta, 1, 127));
        const auto rollPreviewValue = view.previewVelocity(graduatedFirst.noteId);
        const auto rollPreviewSecond = view.previewVelocity(graduatedSecond.noteId);
        const std::optional<std::size_t> previewLevel = map.levelOf(previewVelocity);
        const QImage rollDragPreview = area.grab().toImage();
        const QPointF previewNodeCenter(
            (double(area.plotOrigin()) + double(view.contentX(double(graduatedFirst.tick)))) *
                rollDragPreview.devicePixelRatio(),
            (previewLevel ? area.axis().levelToY(int(*previewLevel))
                          : area.axis().velocityToY(previewVelocity)) *
                rollDragPreview.devicePixelRatio());
        check(document.revision() == revisionBeforeRollDrag &&
                  document.undoStack()->count() == undoBeforeRollDrag && rollPreviewValue &&
                  rollPreviewSecond && *rollPreviewValue == previewVelocity &&
                  *rollPreviewSecond == secondPreviewVelocity,
              "piano-roll velocity preview must stage both selected targets before release");
        check(previewLevel && area.axis().graduations()[*previewLevel].active,
              "piano-roll velocity drag must update the velocity drawer's active graduation");
        check(hasDarkOutlinePixel(rollDragPreview, previewNodeCenter,
                                  std::max(0.0, outlineRadius - outlineWidth),
                                  outlineRadius + outlineWidth),
              "piano-roll velocity drag must move the velocity drawer node before release");
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, rollDragPosition,
                                  Qt::LeftButton, Qt::NoButton, velocityDragModifiers);
        DocNote committedFirst;
        DocNote committedSecond;
        check(document.revision() == revisionBeforeRollDrag + 1 &&
                  document.undoStack()->count() == undoBeforeRollDrag + 1 &&
                  !view.previewVelocity(graduatedFirst.noteId) &&
                  !view.previewVelocity(graduatedSecond.noteId) &&
                  document.findNote(graduatedFirst.noteId, &committedFirst) &&
                  document.findNote(graduatedSecond.noteId, &committedSecond) &&
                  committedFirst.velocity == previewVelocity &&
                  committedSecond.velocity == secondPreviewVelocity,
              "piano-roll velocity drag must commit both previews in one batch and clear them");
        live.documentRevision = document.revision();
    }

    view.selectionModel().setNoteSelection({notes[1].noteId});
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
    checks::events::sendMouse(area, QEvent::MouseButtonPress, axisPoint, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(area, QEvent::MouseButtonRelease, axisPoint, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    DocNote axisFirstAfter;
    DocNote axisSecondAfter;
    check(area.axis().mode() == VelocityAxis::Mode::Continuous &&
              view.selectionModel().noteSelection() == std::vector<NoteId>{notes[1].noteId} &&
              document.revision() == axisRevision + 1 &&
              document.undoStack()->count() == axisUndoDepth + 1 &&
              document.findNote(notes[0].noteId, &axisFirstAfter) &&
              document.findNote(notes[1].noteId, &axisSecondAfter) &&
              axisFirstAfter.velocity == axisFirstBefore.velocity &&
              axisSecondAfter.velocity == axisVelocity,
          "clicking below a selected node must set only that node to the clicked velocity");

    const Qt::KeyboardModifiers detentUnlockModifiers = Qt::ControlModifier;
    check(keymap::Registry::instance().modifierBinding(QStringLiteral("velocity.detent_unlock")) ==
              detentUnlockModifiers,
          "velocity detent unlock shortcut must retain its Ctrl default");
    // Earlier density checks resize the canvas directly. Restore container-owned
    // geometry before asserting sibling drawer chrome.
    const int velocitySectionHeight = view.drawerSectionHeight(EditorDrawerPage::Velocity);
    view.setDrawerSectionHeight(EditorDrawerPage::Velocity, std::nullopt);
    view.setDrawerSectionHeight(EditorDrawerPage::Velocity, velocitySectionHeight);
    QApplication::processEvents();
    live.timeZoom = view.pxPerBeat();
    live.horizontalScroll = view.viewState().scrollPx;
    if (detentUnlockModifiers != Qt::NoModifier) {
        voicegroup.voices[0] = wave;
        view.setVoicegroup(&voicegroup);
        area.songChanged();
        live.documentRevision = document.revision();
        ++live.editCursorTick;
        area.refreshLiveState(live);
        const VelocityMap unlockedMap = VelocityMap::resolve(&wave, notes[0].key);
        const auto isOffDetent = [&unlockedMap](int velocity) {
            return unlockedMap.canonicalize(velocity) != velocity;
        };
        const auto setVelocity = [&document](NoteId noteId, uint8_t velocity) {
            DocNote note;
            if (!document.findNote(noteId, &note))
                return false;
            document.setNotesVelocity({note}, velocity);
            return true;
        };

        const auto &psgGraduations = area.axis().graduations();
        const VelocityAxisGraduation &vol1 = psgGraduations[0];
        const double labelLeft = double(layout::space(layout::Space::Two));
        const double labelRight =
            std::max(labelLeft, double(area.plotOrigin() - layout::singlePixel() -
                                       layout::space(layout::Space::Two)));
        const double labelHeight = area.axis().geometry().labelHeight;
        const QRectF vol1LabelBounds =
            QFontMetricsF(typography::noteName(area.font()))
                .boundingRect(QRectF(labelLeft, vol1.y - labelHeight / 2.0, labelRight - labelLeft,
                                     labelHeight),
                              Qt::AlignRight | Qt::AlignVCenter, QStringLiteral("Vol 1"));
        const QPoint areaOrigin = area.mapTo(drawer, QPoint());
        const QRect detentBounds =
            detentToggle ? QRect(detentToggle->mapTo(drawer, QPoint()), detentToggle->size())
                         : QRect();
        const QRectF vol1LabelBoundsInDrawer =
            vol1LabelBounds.translated(areaOrigin.x(), areaOrigin.y());
        const QRect trackHeaderBounds(0, 0, areaOrigin.x(), drawer->height());
        check(detentToggle && detentToggle->isVisible() && detentToggle->isEnabled() &&
                  detentToggle->isChecked() && detentBounds.left() == areaOrigin.x() &&
                  detentBounds.right() < areaOrigin.x() + area.plotOrigin(),
              "velocity detent toggle must stay inside the PSG label gutter");
        check(detentBounds.bottom() == areaOrigin.y() + area.height() - 1,
              "velocity detent toggle must stay flush with the PSG label gutter bottom");
        check(!detentBounds.intersects(trackHeaderBounds),
              "velocity detent toggle must not cover the track headers");
        check(area.axis().graduationCount() > 0 && vol1.labelVisible && detentToggle &&
                  !QRectF(detentBounds).intersects(vol1LabelBoundsInDrawer),
              "PSG detent toggle must not overlap the Vol 1 label");
        if (detentToggle) {
            voicegroup.voices[0] = directSound;
            view.selectionModel().setNoteSelection({notes[0].noteId, notes[2].noteId});
            check(!detentToggle->isVisible() && !detentToggle->isEnabled() &&
                      !detentToggle->isChecked(),
                  "velocity detent toggle must hide and turn off for a DirectSound selection");
            check(setVelocity(notes[0].noteId, 1) && setVelocity(notes[2].noteId, 127),
                  "detent toggle fixture must reset its ruler values");
            live.documentRevision = document.revision();
            area.refreshLiveState(live);
            QApplication::processEvents();
            const QImage directSoundRuler = area.grab().toImage();
            voicegroup.voices[0] = wave;
            area.songChanged();
            check(detentToggle->isVisible() && detentToggle->isEnabled(),
                  "velocity detent toggle must reappear immediately for a PSG selection");
            detentToggle->click();
            QApplication::processEvents();
            const QImage unlockedPsgRuler = area.grab().toImage();
            const qreal rulerScale = unlockedPsgRuler.devicePixelRatio();
            const int rulerHeight =
                qFloor(double(detentBounds.top() - areaOrigin.y()) * rulerScale);
            const QRect rulerBounds(0, 0, qCeil(double(area.plotOrigin()) * rulerScale),
                                    rulerHeight);
            check(
                samePixels(directSoundRuler.copy(rulerBounds), unlockedPsgRuler.copy(rulerBounds)),
                "disabled PSG detents must show the continuous sample-voice ruler");
            const int toggleUnlockedVelocity = 73;
            const QPointF toggleUnlockedRuler(double(area.plotOrigin()) - 1.0,
                                              area.axis().velocityToY(toggleUnlockedVelocity));
            checks::events::sendMouse(area, QEvent::MouseButtonPress, toggleUnlockedRuler,
                                      Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
            checks::events::sendMouse(area, QEvent::MouseButtonRelease, toggleUnlockedRuler,
                                      Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
            DocNote toggleUnlockedFirst;
            DocNote toggleUnlockedThird;
            check(!detentToggle->isChecked() &&
                      document.findNote(notes[0].noteId, &toggleUnlockedFirst) &&
                      document.findNote(notes[2].noteId, &toggleUnlockedThird) &&
                      toggleUnlockedFirst.velocity == toggleUnlockedVelocity &&
                      toggleUnlockedThird.velocity == toggleUnlockedVelocity &&
                      isOffDetent(toggleUnlockedVelocity),
                  "disabled velocity detents must write exact PSG velocities without a modifier");
            const QImage unlockedNodeImage = area.grab().toImage();
            const qreal unlockedNodeScale = unlockedNodeImage.devicePixelRatio();
            const QPointF unlockedNodeCenter(paintGestureX(toggleUnlockedFirst) * unlockedNodeScale,
                                             area.axis().velocityToY(toggleUnlockedVelocity) *
                                                 unlockedNodeScale);
            check(hasDarkOutlinePixel(
                      unlockedNodeImage, unlockedNodeCenter,
                      std::max(0.0, expected.nodePaintRadius * unlockedNodeScale -
                                        expected.nodeOutlineDipWidth * unlockedNodeScale),
                      expected.nodePaintRadius * unlockedNodeScale),
                  "disabled velocity detents must keep idle nodes at exact velocity positions");
            detentToggle->click();
            check(detentToggle->isChecked(),
                  "velocity detent toggle must restore snapped PSG editing");
        }

        view.selectionModel().setNoteSelection({notes[0].noteId, notes[2].noteId});
        check(setVelocity(notes[0].noteId, 1) && setVelocity(notes[2].noteId, 127),
              "unlocked wave fixture must reset its ruler values");
        live.documentRevision = document.revision();
        area.refreshLiveState(live);
        const int lockedPaintVelocity = 73;
        const QPointF lockedPaintStart(paintGestureX(notes[0]),
                                       area.axis().velocityToY(lockedPaintVelocity));
        const QPointF lockedPaintEnd(paintGestureX(notes[2]),
                                     area.axis().velocityToY(lockedPaintVelocity));
        const uint64_t revisionBeforeLockedPaint = document.revision();
        checks::events::sendMouse(area, QEvent::MouseButtonPress, lockedPaintStart, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(area, QEvent::MouseMove, lockedPaintEnd, Qt::NoButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(area, QEvent::MouseButtonRelease, lockedPaintEnd, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        DocNote lockedPaintFirst;
        DocNote lockedPaintThird;
        check(document.findNote(notes[0].noteId, &lockedPaintFirst) &&
                  document.findNote(notes[2].noteId, &lockedPaintThird) &&
                  document.revision() == revisionBeforeLockedPaint + 1 &&
                  lockedPaintFirst.velocity == unlockedMap.canonicalize(lockedPaintVelocity) &&
                  lockedPaintThird.velocity == unlockedMap.canonicalize(lockedPaintVelocity) &&
                  isOffDetent(lockedPaintVelocity),
              "no-modifier velocity paint must retain snapped PSG semantics");
        view.selectionModel().setNoteSelection({notes[0].noteId, notes[2].noteId});
        check(setVelocity(notes[0].noteId, 1) && setVelocity(notes[2].noteId, 127),
              "unlocked wave fixture must reset its ruler values");
        live.documentRevision = document.revision();
        area.refreshLiveState(live);
        const int unlockedRulerVelocity = 73;
        const QPointF unlockedRuler(double(area.plotOrigin()) - 1.0,
                                    area.axis().velocityToY(unlockedRulerVelocity));
        checks::events::sendMouse(area, QEvent::MouseButtonPress, unlockedRuler, Qt::LeftButton,
                                  Qt::LeftButton, detentUnlockModifiers);
        checks::events::sendMouse(area, QEvent::MouseButtonRelease, unlockedRuler, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        DocNote rulerUnlockedFirst;
        DocNote rulerUnlockedThird;
        check(document.findNote(notes[0].noteId, &rulerUnlockedFirst) &&
                  document.findNote(notes[2].noteId, &rulerUnlockedThird) &&
                  rulerUnlockedFirst.velocity == unlockedRulerVelocity &&
                  rulerUnlockedThird.velocity == unlockedRulerVelocity &&
                  isOffDetent(unlockedRulerVelocity),
              "unlocked intrinsic ruler clicks must write exact off-detent values");

        view.selectionModel().setNoteSelection({notes[0].noteId, notes[2].noteId});
        check(setVelocity(notes[0].noteId, 1) && setVelocity(notes[2].noteId, 127),
              "unlocked wave paint fixture must reset its endpoints");
        live.documentRevision = document.revision();
        area.refreshLiveState(live);
        DocNote paintUnlockedFirst;
        DocNote paintUnlockedThird;
        document.findNote(notes[0].noteId, &paintUnlockedFirst);
        document.findNote(notes[2].noteId, &paintUnlockedThird);
        const int unlockedPaintFirstVelocity = 37;
        const int unlockedPaintThirdVelocity = 91;
        const QPointF unlockedPaintStart(paintGestureX(paintUnlockedFirst),
                                         area.axis().velocityToY(unlockedPaintFirstVelocity));
        const QPointF unlockedPaintEnd(paintGestureX(paintUnlockedThird),
                                       area.axis().velocityToY(unlockedPaintThirdVelocity));
        const uint64_t revisionBeforeUnlockedPaint = document.revision();
        checks::events::sendMouse(area, QEvent::MouseButtonPress, unlockedPaintStart,
                                  Qt::LeftButton, Qt::LeftButton, detentUnlockModifiers);
        checks::events::sendMouse(area, QEvent::MouseMove, unlockedPaintEnd, Qt::NoButton,
                                  Qt::LeftButton, Qt::NoModifier);
        const QImage unlockedPaintPreview = area.grab().toImage();
        const qreal unlockedPaintScale = unlockedPaintPreview.devicePixelRatio();
        const QPointF unlockedPaintCenter(paintGestureX(paintUnlockedFirst) * unlockedPaintScale,
                                          area.axis().velocityToY(unlockedPaintFirstVelocity) *
                                              unlockedPaintScale);
        check(document.revision() == revisionBeforeUnlockedPaint &&
                  hasDarkOutlinePixel(
                      unlockedPaintPreview, unlockedPaintCenter,
                      std::max(0.0, expected.nodePaintRadius * unlockedPaintScale -
                                        expected.nodeOutlineDipWidth * unlockedPaintScale),
                      expected.nodePaintRadius * unlockedPaintScale),
              "unlocked paint preview must remain at its continuous y position");
        checks::events::sendMouse(area, QEvent::MouseButtonRelease, unlockedPaintEnd,
                                  Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
        DocNote paintedUnlockedFirst;
        DocNote paintedUnlockedThird;
        check(document.findNote(notes[0].noteId, &paintedUnlockedFirst) &&
                  document.findNote(notes[2].noteId, &paintedUnlockedThird) &&
                  paintedUnlockedFirst.velocity == unlockedPaintFirstVelocity &&
                  paintedUnlockedThird.velocity == unlockedPaintThirdVelocity &&
                  isOffDetent(unlockedPaintFirstVelocity) &&
                  isOffDetent(unlockedPaintThirdVelocity),
              "unlocked paint must commit exact off-detent wave values");

        view.selectionModel().setNoteSelection({notes[0].noteId, notes[2].noteId});
        check(setVelocity(notes[0].noteId, 33) && setVelocity(notes[2].noteId, 87),
              "unlocked wave relative fixture must reset its origins");
        live.documentRevision = document.revision();
        area.refreshLiveState(live);
        const int lockedRelativeOriginFirst = 33;
        const int lockedRelativeOriginThird = 87;
        const int lockedRelativeDelta = 20;
        const double lockedRelativeStartY =
            area.axis().levelToY(int(unlockedMap.levelOf(lockedRelativeOriginFirst).value()));
        const double lockedRelativeEndY =
            area.axis().velocityToY(lockedRelativeOriginFirst + lockedRelativeDelta);
        const QPointF lockedRelativeStart(paintGestureX(notes[0]), lockedRelativeStartY);
        const QPointF lockedRelativeEnd(lockedRelativeStart.x(), lockedRelativeEndY);
        const int lockedRelativeLevelDelta =
            area.axis().yToLevel(lockedRelativeEndY) - area.axis().yToLevel(lockedRelativeStartY);
        const int lockedProposedFirst = lockedRelativeOriginFirst + lockedRelativeDelta;
        const int lockedProposedThird = lockedRelativeOriginThird + lockedRelativeDelta;
        const uint8_t lockedExpectedFirst =
            unlockedMap.moveLevels(uint8_t(lockedRelativeOriginFirst), lockedRelativeLevelDelta);
        const uint8_t lockedExpectedThird =
            unlockedMap.moveLevels(uint8_t(lockedRelativeOriginThird), lockedRelativeLevelDelta);
        const uint64_t revisionBeforeLockedStart = document.revision();
        checks::events::sendMouse(area, QEvent::MouseButtonPress, lockedRelativeStart,
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(area, QEvent::MouseMove, lockedRelativeEnd, Qt::NoButton,
                                  Qt::LeftButton, detentUnlockModifiers);
        checks::events::sendMouse(area, QEvent::MouseButtonRelease, lockedRelativeEnd,
                                  Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
        DocNote lockedRelativeFirst;
        DocNote lockedRelativeThird;
        check(document.findNote(notes[0].noteId, &lockedRelativeFirst) &&
                  document.findNote(notes[2].noteId, &lockedRelativeThird) &&
                  document.revision() == revisionBeforeLockedStart + 1 &&
                  lockedRelativeFirst.velocity == lockedExpectedFirst &&
                  lockedRelativeThird.velocity == lockedExpectedThird &&
                  lockedRelativeLevelDelta != 0 && isOffDetent(lockedProposedFirst) &&
                  isOffDetent(lockedProposedThird),
              "unlock added after a gesture starts must not bypass snapped PSG semantics");
        view.selectionModel().setNoteSelection({notes[0].noteId, notes[2].noteId});
        check(setVelocity(notes[0].noteId, lockedRelativeOriginFirst) &&
                  setVelocity(notes[2].noteId, lockedRelativeOriginThird),
              "unlocked wave relative fixture must reset its origins");
        live.documentRevision = document.revision();
        area.refreshLiveState(live);
        DocNote relativeUnlockedFirst;
        DocNote relativeUnlockedThird;
        document.findNote(notes[0].noteId, &relativeUnlockedFirst);
        document.findNote(notes[2].noteId, &relativeUnlockedThird);
        const int unlockedRelativeDelta = 7;
        const QPointF unlockedRelativeStart(
            paintGestureX(relativeUnlockedFirst),
            area.axis().levelToY(int(unlockedMap.levelOf(relativeUnlockedFirst.velocity).value())));
        const QPointF unlockedRelativeEnd(
            unlockedRelativeStart.x(),
            area.axis().velocityToY(relativeUnlockedFirst.velocity + unlockedRelativeDelta));
        checks::events::sendMouse(area, QEvent::MouseButtonPress, unlockedRelativeStart,
                                  Qt::LeftButton, Qt::LeftButton, detentUnlockModifiers);
        checks::events::sendMouse(area, QEvent::MouseMove, unlockedRelativeEnd, Qt::NoButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(area, QEvent::MouseButtonRelease, unlockedRelativeEnd,
                                  Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
        DocNote relativeUnlockedFirstAfter;
        DocNote relativeUnlockedThirdAfter;
        check(document.findNote(notes[0].noteId, &relativeUnlockedFirstAfter) &&
                  document.findNote(notes[2].noteId, &relativeUnlockedThirdAfter) &&
                  relativeUnlockedFirstAfter.velocity == 40 &&
                  relativeUnlockedThirdAfter.velocity == 94 &&
                  isOffDetent(relativeUnlockedFirstAfter.velocity) &&
                  isOffDetent(relativeUnlockedThirdAfter.velocity),
              "unlocked relative drag must preserve exact off-detent origins");

        document.addNote(0, 36, relativeUnlockedFirst.key, 12, 56);
        const std::vector<DocNote> unlockedRampNotes = document.notesForTrack(0);
        const auto unlockedRampMiddleIt =
            std::find_if(unlockedRampNotes.cbegin(), unlockedRampNotes.cend(),
                         [](const DocNote &note) { return note.tick == 36; });
        check(unlockedRampMiddleIt != unlockedRampNotes.cend(),
              "unlocked wave ramp fixture must create its midpoint note");
        if (unlockedRampMiddleIt != unlockedRampNotes.cend()) {
            const DocNote unlockedRampMiddleBefore = *unlockedRampMiddleIt;
            view.selectionModel().setNoteSelection(
                {notes[0].noteId, unlockedRampMiddleBefore.noteId, notes[2].noteId});
            live.documentRevision = document.revision();
            area.refreshLiveState(live);
            const DocNote unlockedRampFirst = relativeUnlockedFirstAfter;
            const DocNote unlockedRampThird = relativeUnlockedThirdAfter;
            const double unlockedRampStartX = paintGestureX(unlockedRampFirst);
            const double unlockedRampEndX = paintGestureX(unlockedRampThird);
            const int unlockedRampFirstVelocity = 37;
            const int unlockedRampThirdVelocity = 93;
            const QPointF unlockedRampStart(unlockedRampStartX,
                                            area.axis().velocityToY(unlockedRampFirstVelocity));
            const QPointF unlockedRampEnd(unlockedRampEndX,
                                          area.axis().velocityToY(unlockedRampThirdVelocity));
            const double middleRatio =
                (paintGestureX(unlockedRampMiddleBefore) - unlockedRampStartX) /
                (unlockedRampEndX - unlockedRampStartX);
            const int unlockedRampMiddleVelocity = area.axis().yToVelocity(
                unlockedRampStart.y() +
                middleRatio * (unlockedRampEnd.y() - unlockedRampStart.y()));
            const uint64_t revisionBeforeUnlockedRamp = document.revision();
            const Qt::KeyboardModifiers unlockedRampModifiers =
                detentUnlockModifiers | Qt::ShiftModifier;
            checks::events::sendMouse(area, QEvent::MouseButtonPress, unlockedRampStart,
                                      Qt::LeftButton, Qt::LeftButton, unlockedRampModifiers);
            checks::events::sendMouse(area, QEvent::MouseMove, unlockedRampEnd, Qt::NoButton,
                                      Qt::LeftButton, Qt::NoModifier);
            check(document.revision() == revisionBeforeUnlockedRamp,
                  "unlocked Shift-ramp must defer document changes");
            checks::events::sendMouse(area, QEvent::MouseButtonRelease, unlockedRampEnd,
                                      Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
            DocNote rampedUnlockedFirst;
            DocNote rampedUnlockedMiddle;
            DocNote rampedUnlockedThird;
            check(document.findNote(notes[0].noteId, &rampedUnlockedFirst) &&
                      document.findNote(unlockedRampMiddleBefore.noteId, &rampedUnlockedMiddle) &&
                      document.findNote(notes[2].noteId, &rampedUnlockedThird) &&
                      rampedUnlockedFirst.velocity == unlockedRampFirstVelocity &&
                      rampedUnlockedMiddle.velocity == unlockedRampMiddleVelocity &&
                      rampedUnlockedThird.velocity == unlockedRampThirdVelocity &&
                      isOffDetent(rampedUnlockedFirst.velocity) &&
                      isOffDetent(rampedUnlockedMiddle.velocity) &&
                      isOffDetent(rampedUnlockedThird.velocity),
                  "unlocked Shift-ramp must commit exact continuous wave values");
            document.deleteNotes({unlockedRampMiddleBefore});
            live.documentRevision = document.revision();
            area.refreshLiveState(live);
        }
    }

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

    view.selectionModel().setNoteSelection({notes[0].noteId, notes[2].noteId});
    const std::vector<NoteId> selectedBeforeKeyboard = view.selectionModel().noteSelection();
    DocNote firstBeforeKeyboard;
    DocNote thirdBeforeKeyboard;
    check(document.findNote(notes[0].noteId, &firstBeforeKeyboard) &&
              document.findNote(notes[2].noteId, &thirdBeforeKeyboard),
          "focused velocity keyboard fixture must resolve its selected notes");
    const uint64_t revisionBeforeKeyboard = document.revision();
    area.setFocus(Qt::OtherFocusReason);
    checks::events::sendKey(area, QEvent::KeyPress, Qt::Key_Up, Qt::ShiftModifier, QString(), false,
                            1);
    DocNote firstAfterKeyboard;
    DocNote thirdAfterKeyboard;
    check(document.revision() == revisionBeforeKeyboard &&
              view.selectionModel().noteSelection() == selectedBeforeKeyboard &&
              document.findNote(notes[0].noteId, &firstAfterKeyboard) &&
              document.findNote(notes[2].noteId, &thirdAfterKeyboard) &&
              firstAfterKeyboard.key == firstBeforeKeyboard.key &&
              thirdAfterKeyboard.key == thirdBeforeKeyboard.key,
          "focused velocity keyboard pitch editing must leave selected notes unchanged");
    if (!screenshotPath.isEmpty())
        check(area.grab().save(screenshotPath), "optional velocity screenshot should save");
    area.hide();
    return failures == 0 ? 0 : 1;
}
