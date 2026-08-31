#include "rollcheckvoicechange.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <memory>

#include <QApplication>
#include <QCoreApplication>
#include <QDialog>
#include <QEvent>
#include <QImage>
#include <QListWidget>
#include <QMenu>
#include <QPointer>
#include <QTemporaryDir>
#include <QTimer>

#include "checks/support/eventsynth.h"
#include "core/miditimeline.h"
#include "core/smf.h"
#include "core/songdocument.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/editorviewstate.h"
#include "ui/songview.h"
#include "ui/theme/trackidentitycolors.h"

namespace {

// Self-contained fixture: one synthesized three-track song, one voicegroup,
// and a SongView whose Voice Changes drawer page is visible. Members are
// declared so the view is destroyed before the document it points at.
struct AreaFixture {
    QTemporaryDir dir;
    SongDocument document;
    LoadedVoiceGroup voicegroup{};
    std::unique_ptr<MidiTimeline> timeline;
    std::unique_ptr<SongView> view;
    VoiceChangeArea *area = nullptr;
};

bool createAreaFixture(AreaFixture &env, QString &error)
{
    error.clear();
    if (!env.dir.isValid()) {
        error = QStringLiteral("voice-change fixture could not create a temporary directory");
        return false;
    }
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    smf.tracks.resize(4);
    SmfTrack &conductor = smf.tracks[0];
    SmfEvent tempo;
    tempo.status = 0xFF;
    tempo.metaType = 0x51;
    tempo.blob = QByteArray("\x07\xA1\x20", 3); // 120 BPM
    conductor.events.push_back(tempo);
    conductor.endTick = 384;
    SmfTrack &lead = smf.tracks[1];
    SmfEvent leadVoice;
    leadVoice.status = 0xC0;
    leadVoice.data0 = 0;
    lead.events.push_back(leadVoice);
    SmfEvent leadOn;
    leadOn.status = 0x90;
    leadOn.data0 = 60;
    leadOn.data1 = 100;
    lead.events.push_back(leadOn);
    SmfEvent leadOff;
    leadOff.tick = 48;
    leadOff.status = 0x80;
    leadOff.data0 = 60;
    lead.events.push_back(leadOff);
    lead.endTick = 384;
    SmfTrack &bass = smf.tracks[2];
    SmfEvent bassVoice;
    bassVoice.status = 0xC1;
    bassVoice.data0 = 5;
    bass.events.push_back(bassVoice);
    SmfEvent bassOn;
    bassOn.status = 0x91;
    bassOn.data0 = 48;
    bassOn.data1 = 100;
    bass.events.push_back(bassOn);
    SmfEvent bassOff;
    bassOff.tick = 48;
    bassOff.status = 0x81;
    bassOff.data0 = 48;
    bass.events.push_back(bassOff);
    bass.endTick = 384;
    SmfTrack &voiceLess = smf.tracks[3];
    SmfEvent voiceLessOn;
    voiceLessOn.status = 0x92;
    voiceLessOn.data0 = 67;
    voiceLessOn.data1 = 100;
    voiceLess.events.push_back(voiceLessOn);
    SmfEvent voiceLessOff;
    voiceLessOff.tick = 48;
    voiceLessOff.status = 0x82;
    voiceLessOff.data0 = 67;
    voiceLess.events.push_back(voiceLessOff);
    voiceLess.endTick = 384;
    SongInfo info;
    info.label = QStringLiteral("voicechange-area-fixture");
    info.midPath = env.dir.filePath(QStringLiteral("voicechange-fixture.mid"));
    info.hasMid = true;
    if (!smf.writeFile(info.midPath, &error) || !env.document.load(info, &error)) {
        error = QStringLiteral("voice-change fixture song failed to load: %1").arg(error);
        return false;
    }
    if (env.document.engineTrackCount() < 3) {
        error = QStringLiteral("voice-change fixture did not expose three engine tracks");
        return false;
    }
    env.document.addLanePoint(0, DOC_CC_VOICE, 48, 3);
    env.voicegroup.voices[3].type = VOICE_NOISE;
    std::strncpy(env.voicegroup.voiceNames[3], "voice-check",
                 sizeof(env.voicegroup.voiceNames[3]) - 1);
    env.voicegroup.voices[5].type = VOICE_NOISE;
    std::strncpy(env.voicegroup.voiceNames[5], "alt-voice",
                 sizeof(env.voicegroup.voiceNames[5]) - 1);
    env.timeline = env.document.buildTimeline(48000.0);
    env.view = std::make_unique<SongView>();
    env.view->resize(1000, 640);
    env.view->setDocument(&env.document);
    env.view->setSong(env.timeline.get(), &env.voicegroup);
    env.view->selectTrack(0);
    env.view->setDrawerActivePage(EditorDrawerPage::VoiceChanges);
    env.view->setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    env.view->setDrawerSectionHeight(EditorDrawerPage::VoiceChanges, 160);
    env.view->show();
    QCoreApplication::processEvents();
    auto *drawer = env.view->editorDrawer();
    env.area = drawer ? drawer->voiceChangeArea() : nullptr;
    if (!env.area) {
        error = QStringLiteral("concrete SongView did not expose the VoiceChangeArea");
        return false;
    }
    env.view->setEditorTimeZoom(96.0);
    env.view->setEditCursorTick(24);
    QCoreApplication::processEvents();
    return true;
}

void pump()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
}

QRect deviceRect(const QRectF &logical, qreal dpr, const QSize &bound)
{
    const int left = std::clamp(int(std::floor(logical.left() * dpr)), 0, bound.width());
    const int top = std::clamp(int(std::floor(logical.top() * dpr)), 0, bound.height());
    const int right = std::clamp(int(std::ceil(logical.right() * dpr)), 0, bound.width());
    const int bottom = std::clamp(int(std::ceil(logical.bottom() * dpr)), 0, bound.height());
    return {left, top, std::max(0, right - left), std::max(0, bottom - top)};
}

int changedPixels(const QImage &before, const QImage &after, const QRectF &logical, qreal dpr)
{
    if (before.size() != after.size() || before.format() != after.format())
        return -1;
    const QRect rect = deviceRect(logical, dpr, before.size()).intersected(before.rect());
    if (rect.isEmpty())
        return -1;
    auto count = 0;
    for (int y = rect.top(); y <= rect.bottom(); ++y) {
        for (int x = rect.left(); x <= rect.right(); ++x) {
            if (before.pixel(x, y) != after.pixel(x, y))
                ++count;
        }
    }
    return count;
}

// Strip right of a hover line where the held "→ NNN name (type)" label is
// painted; the label probe compares this crop between two states.
QImage labelCrop(const QImage &image, double lineX, qreal dpr)
{
    const int line = qRound(lineX * dpr);
    const int gap = std::max(2, qRound(6.0 * dpr));
    const int left = std::clamp(line + gap, 0, image.width());
    const int width = std::clamp(qRound(140.0 * dpr), 0, image.width() - left);
    return image.copy(QRect(left, 0, width, image.height()));
}

double xForTick(const AreaFixture &env, double tick)
{
    return env.view->displayX(tick, env.area->plotOrigin(), env.area->devicePixelRatioF());
}

// Schedules one pickerDialog acceptance: records the modal picker's title and
// initial row, selects `row`, and accepts (or rejects when row < 0).
void driveVoicePicker(int row, QString *title, int *initialRow, bool *opened)
{
    QTimer::singleShot(0, [row, title, initialRow, opened] {
        auto *dialog = qobject_cast<QDialog *>(QApplication::activeModalWidget());
        auto *list = dialog ? dialog->findChild<QListWidget *>() : nullptr;
        if (!dialog || !list)
            return;
        *opened = true;
        *title = dialog->windowTitle();
        *initialRow = list->currentRow();
        if (row >= 0) {
            list->setCurrentRow(row);
            dialog->accept();
        } else {
            dialog->reject();
        }
    });
}

void doubleClickArea(const AreaFixture &env, const QPointF &position)
{
    checks::events::sendMouse(*env.area, QEvent::MouseButtonDblClick, position, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*env.area, QEvent::MouseButtonRelease, position, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    QCoreApplication::processEvents();
}

// Access, page membership, and shared-camera band registration.
void checkAreaSurfaceBasics(const AreaFixture &env, int &failures)
{
    const auto check = [&failures](bool condition, const QString &message) {
        if (condition)
            return;
        std::fprintf(stderr, "drawer: FAIL voice-change-area: %s\n", qUtf8Printable(message));
        ++failures;
    };
    check(env.view->drawerActivePage() == EditorDrawerPage::VoiceChanges &&
              env.view->drawerSectionVisible(EditorDrawerPage::VoiceChanges),
          QStringLiteral("Voice Changes page was not the visible drawer page"));
    const QRect plot = env.area->rect().adjusted(env.area->plotOrigin(), 0, 0, 0);
    check(env.area->plotWidth() > 0 && !plot.isEmpty(),
          QStringLiteral("VoiceChangeArea exposed no usable plot"));
    bool bandFound = false;
    for (const auto &band : env.view->timelineBands()) {
        if (&band.widget == env.area) {
            bandFound = band.timelineOrigin == env.area->plotOrigin();
            break;
        }
    }
    check(bandFound,
          QStringLiteral("SongView timeline bands did not register the VoiceChangeArea"));
}

// Paint lifecycle: document edits paint their marker, undo/song reattach
// restore the surface, and playhead context updates only on held-span changes.
void checkAreaPaintLifecycle(AreaFixture &env, int &failures)
{
    auto *area = env.area;
    const auto check = [&failures](bool condition, const QString &message) {
        if (condition)
            return;
        std::fprintf(stderr, "drawer: FAIL voice-change-area: %s\n", qUtf8Printable(message));
        ++failures;
    };
    const qreal dpr = area->devicePixelRatioF();
    const QImage idle = area->grab().toImage();
    const uint64_t revisionBefore = env.document.revision();
    const int undoBefore = env.document.undoStack()->index();

    env.document.addLanePoint(0, DOC_CC_VOICE, 120, 5);
    pump();
    const QImage marked = area->grab().toImage();
    const double markerX = xForTick(env, 120);
    check(env.document.revision() == revisionBefore + 1 &&
              env.document.undoStack()->index() == undoBefore + 1 &&
              env.document.undoStack()->text(undoBefore) == QStringLiteral("add voice change"),
          QStringLiteral("document commit was not one undo step labelled 'add voice change'"));
    check(changedPixels(idle, marked, QRectF(markerX - 8, 0, 16, area->height()), dpr) > 0,
          QStringLiteral("added voice change marker painted no column at its tick"));

    env.document.undoStack()->undo();
    pump();
    const QImage unmarked = area->grab().toImage();
    check(changedPixels(idle, unmarked, area->rect(), dpr) == 0,
          QStringLiteral("undo did not restore the marker-free paint"));

    // Playhead-only presentations must not rebuild content within one held
    // span, and must invalidate once when the displayed context crosses it.
    const auto warm = area->diagnostics();
    env.view->setPlayheadSample(env.timeline->sampleForTick(16), true);
    pump();
    const QImage playingA = area->grab().toImage();
    const auto afterFirstPresent = area->diagnostics();
    env.view->setPlayheadSample(env.timeline->sampleForTick(32), true);
    pump();
    check(area->diagnostics() == afterFirstPresent,
          QStringLiteral("same-span playhead presentations invalidated voice content"));
    env.view->setPlayheadSample(env.timeline->sampleForTick(64), true);
    pump();
    check(area->diagnostics().contentInvalidationCount > afterFirstPresent.contentInvalidationCount,
          QStringLiteral("playhead crossing the voice change did not refresh the context"));
    const QImage playingB = area->grab().toImage();
    check(changedPixels(playingA, playingB,
                        QRectF(area->plotOrigin() + area->plotWidth() / 2.0, 0,
                               area->plotWidth() / 2.0, area->height()),
                        dpr) > 0,
          QStringLiteral("playhead crossing did not repaint the current-voice readout"));
    env.view->setPlayheadSample(0, false);
    pump();
    check(area->grab().toImage() == idle,
          QStringLiteral("stopping playback did not restore the edit-cursor voice context"));

    // Reattaching resets the song-scoped camera and drawer state by contract;
    // restore those public settings before comparing the same surface.
    const double zoom = env.view->pxPerBeat();
    const double scroll = env.view->viewState().scrollPx;
    env.view->setSong(env.timeline.get(), &env.voicegroup);
    env.view->selectTrack(0);
    env.view->setDrawerActivePage(EditorDrawerPage::VoiceChanges);
    env.view->setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    env.view->setDrawerSectionHeight(EditorDrawerPage::VoiceChanges, 160);
    env.view->setEditorTimeZoom(zoom);
    env.view->setEditorHorizontalScroll(scroll);
    env.view->setEditCursorTick(24);
    pump();
    check(changedPixels(idle, area->grab().toImage(), area->rect(), dpr) == 0,
          QStringLiteral("song re-attach did not restore the marker-free paint"));
}

// Hover: dotted line plus held label away from markers, label suppressed on
// the marker tick, sliver-sized repaints, and clearing on leave/hide/Escape.
void checkAreaHover(AreaFixture &env, int &failures)
{
    auto *area = env.area;
    const auto check = [&failures](bool condition, const QString &message) {
        if (condition)
            return;
        std::fprintf(stderr, "drawer: FAIL voice-change-area: %s\n", qUtf8Printable(message));
        ++failures;
    };
    const qreal dpr = area->devicePixelRatioF();
    const QImage idle = area->grab().toImage();

    const double offMarkerX = xForTick(env, 96);
    const auto beforeHover = area->diagnostics();
    checks::events::sendMouse(*area, QEvent::MouseMove, QPointF(offMarkerX, area->height() / 2.0),
                              Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    pump();
    const QImage offMarker = area->grab().toImage();
    const auto afterHover = area->diagnostics();
    check(afterHover.contentPaintPixelCount > beforeHover.contentPaintPixelCount,
          QStringLiteral("off-marker hover painted no content"));
    check(afterHover.contentPaintPixelCount - beforeHover.contentPaintPixelCount <
              quint64(area->width()) * quint64(area->height()) * dpr * dpr / 2,
          QStringLiteral("off-marker hover repainted about half the surface or more"));
    check(labelCrop(idle, offMarkerX, dpr) != labelCrop(offMarker, offMarkerX, dpr),
          QStringLiteral("off-marker hover did not paint the held voice label"));

    const double markerX = xForTick(env, 48);
    checks::events::sendMouse(*area, QEvent::MouseMove, QPointF(markerX, area->height() / 2.0),
                              Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    pump();
    const QImage onMarker = area->grab().toImage();
    check(changedPixels(offMarker, onMarker, QRectF(markerX - 8, 0, 16, area->height()), dpr) > 0,
          QStringLiteral("hover did not track the marker tick"));
    check(labelCrop(onMarker, markerX, dpr) == labelCrop(idle, markerX, dpr),
          QStringLiteral("hovering the marker painted a held label on top of it"));

    QEvent leave(QEvent::Leave);
    QCoreApplication::sendEvent(area, &leave);
    pump();
    check(area->grab().toImage() == idle, QStringLiteral("leave did not clear the hover paint"));

    checks::events::sendMouse(*area, QEvent::MouseMove, QPointF(offMarkerX, area->height() / 2.0),
                              Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    pump();
    checks::events::sendKey(*area, QEvent::KeyPress, Qt::Key_Escape, Qt::NoModifier, QString{},
                            false, 1);
    pump();
    check(area->grab().toImage() == idle, QStringLiteral("Escape did not clear the hover paint"));

    checks::events::sendMouse(*area, QEvent::MouseMove, QPointF(offMarkerX, area->height() / 2.0),
                              Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    pump();
    env.view->setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
    env.view->setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    pump();
    check(area->grab().toImage() == idle,
          QStringLiteral("page hide and re-show did not clear the hover paint"));
}

// Primary-track and voicegroup refresh: selection, hidden reopens, pointer
// swaps, and an explicit song lifecycle refresh all rebuild current labels.
void checkAreaRefresh(AreaFixture &env, int &failures)
{
    auto *area = env.area;
    const auto check = [&failures](bool condition, const QString &message) {
        if (condition)
            return;
        std::fprintf(stderr, "drawer: FAIL voice-change-area: %s\n", qUtf8Printable(message));
        ++failures;
    };
    const QImage track0 = area->grab().toImage();

    env.view->selectTrack(1);
    pump();
    const QImage track1 = area->grab().toImage();
    check(track1 != track0,
          QStringLiteral("selecting another primary track did not recapture the area"));

    env.view->setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
    env.view->selectTrack(0);
    env.view->setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    pump();
    check(area->grab().toImage() == track0,
          QStringLiteral("reopening the hidden page rebuilt stale track state"));

    env.view->setVoicegroup(nullptr);
    pump();
    check(area->grab().toImage() != track0,
          QStringLiteral("clearing the voicegroup did not repaint unresolved labels"));
    env.view->setVoicegroup(&env.voicegroup);
    pump();
    check(area->grab().toImage() == track0,
          QStringLiteral("restoring the voicegroup did not repaint cached labels"));

    std::strncpy(env.voicegroup.voiceNames[3], "renamed-check",
                 sizeof(env.voicegroup.voiceNames[3]) - 1);
    env.view->setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
    env.view->setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    pump();
    check(area->grab().toImage() != track0,
          QStringLiteral("renaming a voice in place did not refresh the cached labels"));
    std::strncpy(env.voicegroup.voiceNames[3], "voice-check",
                 sizeof(env.voicegroup.voiceNames[3]) - 1);
    env.view->setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
    env.view->setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    pump();
    check(area->grab().toImage() == track0,
          QStringLiteral("restoring the voice name did not refresh the cached labels"));
}

// Picker and context-menu commits with exact revisions and undo labels.
void checkAreaCommits(AreaFixture &env, int &failures)
{
    auto *area = env.area;
    SongDocument &document = env.document;
    const auto check = [&failures](bool condition, const QString &message) {
        if (condition)
            return;
        std::fprintf(stderr, "drawer: FAIL voice-change-area: %s\n", qUtf8Printable(message));
        ++failures;
    };
    const uint64_t startRevision = document.revision();
    const int startUndo = document.undoStack()->index();
    const QByteArray startSmf = document.smf().write();
    const double markerY = area->height() / 2.0;

    // Change the seeded tick-48 marker: title "Change voice", initial 3.
    QString title;
    int initialRow = -1;
    bool opened = false;
    driveVoicePicker(5, &title, &initialRow, &opened);
    doubleClickArea(env, QPointF(xForTick(env, 48), markerY));
    check(opened && title == QStringLiteral("Change voice") && initialRow == 3,
          QStringLiteral("double-click on a marker did not open 'Change voice' seeded with its "
                         "value (opened %1, title '%2', initial %3)")
              .arg(opened)
              .arg(title)
              .arg(initialRow));
    DocLanePoint changed{};
    check(document.revision() == startRevision + 1 &&
              document.undoStack()->index() == startUndo + 1 &&
              document.undoStack()->text(startUndo) == QStringLiteral("change voice") &&
              document.findLanePoint(0, DOC_CC_VOICE, 48, &changed) && changed.value == 5,
          QStringLiteral("picker change did not move the marker to voice 5 in one 'change "
                         "voice' undo step"));
    const QByteArray changedSmf = document.smf().write();
    const uint64_t changedRevision = document.revision();
    const int changedUndo = document.undoStack()->index();

    // Same-value acceptance is a no-op: no commit, no undo, no repaint.
    const auto warm = area->diagnostics();
    title.clear();
    initialRow = -1;
    opened = false;
    driveVoicePicker(5, &title, &initialRow, &opened);
    doubleClickArea(env, QPointF(xForTick(env, 48), markerY));
    check(opened && title == QStringLiteral("Change voice") && initialRow == 5 &&
              document.smf().write() == changedSmf && document.revision() == changedRevision &&
              document.undoStack()->index() == changedUndo && area->diagnostics() == warm,
          QStringLiteral("same-value picker acceptance committed or repainted"));

    // Cancelling the picker is a no-op too.
    title.clear();
    initialRow = -1;
    opened = false;
    driveVoicePicker(-1, &title, &initialRow, &opened);
    doubleClickArea(env, QPointF(xForTick(env, 48), markerY));
    check(opened && title == QStringLiteral("Change voice") && initialRow == 5 &&
              document.smf().write() == changedSmf && document.revision() == changedRevision &&
              document.undoStack()->index() == changedUndo,
          QStringLiteral("cancelling the picker mutated the document"));
    // A modal picker must not commit through a document pointer detached
    // while the dialog is open.
    title.clear();
    initialRow = -1;
    opened = false;
    QTimer::singleShot(0, [&] {
        auto *dialog = qobject_cast<QDialog *>(QApplication::activeModalWidget());
        auto *list = dialog ? dialog->findChild<QListWidget *>() : nullptr;
        if (!dialog || !list)
            return;
        opened = true;
        title = dialog->windowTitle();
        initialRow = list->currentRow();
        env.view->setDocument(nullptr);
        list->setCurrentRow(7);
        dialog->accept();
    });
    doubleClickArea(env, QPointF(xForTick(env, 48), markerY));
    check(opened && title == QStringLiteral("Change voice") && initialRow == 5 &&
              document.smf().write() == changedSmf && document.revision() == changedRevision &&
              document.undoStack()->index() == changedUndo,
          QStringLiteral("picker committed through a detached document"));
    env.view->setDocument(&document);
    pump();

    // Double-click on empty plot inserts at the snapped tick seeded with the
    // currently held voice.
    title.clear();
    initialRow = -1;
    opened = false;
    driveVoicePicker(3, &title, &initialRow, &opened);
    doubleClickArea(env, QPointF(xForTick(env, 96), markerY));
    check(opened && title == QStringLiteral("Insert voice change") && initialRow == 5,
          QStringLiteral("double-click on empty plot did not open 'Insert voice change' seeded "
                         "with the held voice (opened %1, title '%2', initial %3)")
              .arg(opened)
              .arg(title)
              .arg(initialRow));
    DocLanePoint inserted{};
    check(document.revision() == startRevision + 2 &&
              document.undoStack()->index() == startUndo + 2 &&
              document.undoStack()->text(startUndo + 1) == QStringLiteral("add voice change") &&
              document.findLanePoint(0, DOC_CC_VOICE, 96, &inserted) && inserted.value == 3,
          QStringLiteral("picker insert did not add voice 3 at tick 96 in one 'add voice "
                         "change' undo step"));

    // Undo/redo round-trips the insert visually.
    document.undoStack()->undo();
    pump();
    const QImage afterUndo = area->grab().toImage();
    document.undoStack()->redo();
    pump();
    check(document.findLanePoint(0, DOC_CC_VOICE, 96, &inserted) && inserted.value == 3 &&
              changedPixels(afterUndo, area->grab().toImage(),
                            QRectF(xForTick(env, 96) - 8, 0, 16, area->height()),
                            area->devicePixelRatioF()) > 0,
          QStringLiteral("undo/redo did not remove and restore the inserted marker"));

    // Context menus: exact action lists, insert from empty plot, delete of
    // the exact marker point.
    const auto activateMenuAction = [](QMenu *menu, QAction *action) {
        const QRect actionRect = menu->actionGeometry(action);
        checks::events::sendMouse(*menu, QEvent::MouseButtonPress, actionRect.center(),
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*menu, QEvent::MouseButtonRelease, actionRect.center(),
                                  Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
        QCoreApplication::processEvents();
    };
    const uint64_t insertRevision = document.revision();
    const int insertUndo = document.undoStack()->index();
    QStringList menuActions;
    bool menuOpened = false;
    QTimer::singleShot(0, [&] {
        auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
        if (!menu)
            return;
        menuOpened = true;
        for (QAction *action : menu->actions())
            menuActions.push_back(action->text());
        QAction *insert = nullptr;
        for (QAction *action : menu->actions()) {
            if (action->text() == QStringLiteral("Insert voice change"))
                insert = action;
        }
        if (!insert) {
            menu->close();
            return;
        }
        activateMenuAction(menu, insert);
        QTimer::singleShot(0, [&] {
            auto *dialog = qobject_cast<QDialog *>(QApplication::activeModalWidget());
            auto *list = dialog ? dialog->findChild<QListWidget *>() : nullptr;
            if (!dialog || !list)
                return;
            list->setCurrentRow(7);
            dialog->accept();
        });
    });
    checks::events::sendMouse(*area, QEvent::MouseButtonPress, QPointF(xForTick(env, 144), markerY),
                              Qt::RightButton, Qt::RightButton, Qt::NoModifier);
    QCoreApplication::processEvents();
    checks::events::sendMouse(*area, QEvent::MouseButtonRelease,
                              QPointF(xForTick(env, 144), markerY), Qt::RightButton, Qt::NoButton,
                              Qt::NoModifier);
    pump();
    check(!QApplication::activePopupWidget(),
          QStringLiteral("the synthesized context event after release opened a second menu"));
    DocLanePoint contextInserted{};
    check(menuOpened && document.findLanePoint(0, DOC_CC_VOICE, 144, &contextInserted) &&
              contextInserted.value == 7 && document.revision() == insertRevision + 1 &&
              document.undoStack()->index() == insertUndo + 1 &&
              document.undoStack()->text(insertUndo) == QStringLiteral("add voice change"),
          QStringLiteral("context 'Insert voice change' did not commit voice 7 at tick 144"));

    title.clear();
    initialRow = -1;
    opened = false;
    driveVoicePicker(9, &title, &initialRow, &opened);
    doubleClickArea(env, QPointF(xForTick(env, 144), markerY));
    check(opened && document.findLanePoint(0, DOC_CC_VOICE, 144, &contextInserted) &&
              contextInserted.value == 9 && document.revision() == insertRevision + 2 &&
              document.undoStack()->text(insertUndo + 1) == QStringLiteral("change voice"),
          QStringLiteral("context insert did not leave a changeable marker at tick 144"));

    const uint64_t deleteRevision = document.revision();
    const int deleteUndo = document.undoStack()->index();
    menuActions.clear();
    menuOpened = false;
    QTimer::singleShot(0, [&] {
        auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
        if (!menu)
            return;
        menuOpened = true;
        for (QAction *action : menu->actions())
            menuActions.push_back(action->text());
        QAction *remove = nullptr;
        for (QAction *action : menu->actions()) {
            if (action->text() == QStringLiteral("Delete"))
                remove = action;
        }
        if (!remove) {
            menu->close();
            return;
        }
        activateMenuAction(menu, remove);
    });
    checks::events::sendMouse(*area, QEvent::MouseButtonPress, QPointF(xForTick(env, 144), markerY),
                              Qt::RightButton, Qt::RightButton, Qt::NoModifier);
    QCoreApplication::processEvents();
    checks::events::sendMouse(*area, QEvent::MouseButtonRelease,
                              QPointF(xForTick(env, 144), markerY), Qt::RightButton, Qt::NoButton,
                              Qt::NoModifier);
    pump();
    check(!QApplication::activePopupWidget(),
          QStringLiteral("the synthesized context event after delete opened a second menu"));
    check(menuOpened &&
              menuActions ==
                  QStringList{QStringLiteral("Change voice"), QStringLiteral("Delete")} &&
              !document.findLanePoint(0, DOC_CC_VOICE, 144, &contextInserted) &&
              document.revision() == deleteRevision + 1 &&
              document.undoStack()->index() == deleteUndo + 1 &&
              document.undoStack()->text(deleteUndo) == QStringLiteral("delete voice change(s)"),
          QStringLiteral("context delete did not remove exactly the tick-144 marker in one "
                         "'delete voice change(s)' undo step (menu %1)")
              .arg(menuActions.join(QLatin1Char(','))));

    // Restore the seeded state before the camera probes run.
    document.undoStack()->setIndex(startUndo);
    pump();
    check(document.smf().write() == startSmf,
          QStringLiteral("commit coverage did not restore its starting document"));
}

// Live picker previews must be projection-only until acceptance. This drives
// the actual drawer and track-header callers through their modal event loop.
void checkAreaLiveVoiceChanges(AreaFixture &env, int &failures)
{
    auto *area = env.area;
    SongDocument &document = env.document;
    const auto check = [&failures](bool condition, const QString &message) {
        if (condition)
            return;
        std::fprintf(stderr, "drawer: FAIL voice-change-area: %s\n", qUtf8Printable(message));
        ++failures;
    };
    const double markerY = area->height() / 2.0;
    const int baseIndex = document.undoStack()->index();
    const auto baseIdentity = document.history().currentDocumentIdentity();
    const bool baseDirty = document.isDirty();
    const QByteArray baseSmf = document.smf().write();

    // An existing marker tracks each row live, without changing document
    // history, its identity, or dirty state. Accept then lands exactly one
    // ordinary command, whose two history navigation paths both round-trip.
    bool opened = false;
    QTimer::singleShot(0, [&] {
        auto *dialog = qobject_cast<QDialog *>(QApplication::activeModalWidget());
        auto *list = dialog ? dialog->findChild<QListWidget *>() : nullptr;
        if (!dialog || !list)
            return;
        opened = true;
        const int previewIndex = document.undoStack()->index();
        const int previewCount = document.undoStack()->count();
        const auto previewIdentity = document.history().currentDocumentIdentity();
        const bool previewDirty = document.isDirty();
        for (const int voice : {3, 5, 7}) {
            list->setCurrentRow(voice);
            DocLanePoint live{};
            check(document.findLanePoint(0, DOC_CC_VOICE, 48, &live) && live.value == voice &&
                      document.undoStack()->index() == previewIndex &&
                      document.undoStack()->count() == previewCount &&
                      document.history().currentDocumentIdentity() == previewIdentity &&
                      document.isDirty() == previewDirty,
                  QStringLiteral("picker row %1 changed history or did not project the live "
                                 "voice at tick 48")
                      .arg(voice));
        }
        dialog->accept();
    });
    doubleClickArea(env, QPointF(xForTick(env, 48), markerY));
    DocLanePoint accepted{};
    const auto acceptedIdentity = document.history().currentDocumentIdentity();
    check(opened && document.undoStack()->index() == baseIndex + 1 &&
              document.undoStack()->count() == baseIndex + 1 &&
              document.undoStack()->text(baseIndex) == QStringLiteral("change voice") &&
              acceptedIdentity != baseIdentity &&
              document.findLanePoint(0, DOC_CC_VOICE, 48, &accepted) && accepted.value == 7,
          QStringLiteral("accepting the multi-row live preview did not add one 'change voice' "
                         "document entry"));
    (void)document.history().requestUndo();
    pump();
    check(document.history().currentDocumentIdentity() == baseIdentity &&
              document.findLanePoint(0, DOC_CC_VOICE, 48, &accepted) && accepted.value == 3,
          QStringLiteral("history undo did not restore the pre-preview voice"));
    (void)document.history().requestRedo();
    pump();
    check(document.history().currentDocumentIdentity() == acceptedIdentity &&
              document.findLanePoint(0, DOC_CC_VOICE, 48, &accepted) && accepted.value == 7,
          QStringLiteral("history redo did not restore the accepted voice"));
    document.undoStack()->undo();
    pump();
    check(document.findLanePoint(0, DOC_CC_VOICE, 48, &accepted) && accepted.value == 3,
          QStringLiteral("direct undo did not restore the pre-preview voice"));
    document.undoStack()->redo();
    pump();
    check(document.findLanePoint(0, DOC_CC_VOICE, 48, &accepted) && accepted.value == 7,
          QStringLiteral("direct redo did not restore the accepted voice"));
    document.undoStack()->setIndex(baseIndex);
    pump();

    // Rejecting after a pre-existing redo tail restores the byte-exact SMF
    // and leaves the stack structurally untouched. Revisions may advance as
    // the preview and its rollback publish ordinary document mutations.
    const QByteArray cancelSmf = document.smf().write();
    const int cancelIndex = document.undoStack()->index();
    const int cancelCount = document.undoStack()->count();
    const auto cancelIdentity = document.history().currentDocumentIdentity();
    const bool cancelDirty = document.isDirty();
    const bool cancelCanRedo = document.undoStack()->canRedo();
    opened = false;
    QTimer::singleShot(0, [&] {
        auto *dialog = qobject_cast<QDialog *>(QApplication::activeModalWidget());
        auto *list = dialog ? dialog->findChild<QListWidget *>() : nullptr;
        if (!dialog || !list)
            return;
        opened = true;
        list->setCurrentRow(5);
        list->setCurrentRow(7);
        dialog->reject();
    });
    doubleClickArea(env, QPointF(xForTick(env, 48), markerY));
    check(opened && document.smf().write() == cancelSmf &&
              document.undoStack()->index() == cancelIndex &&
              document.undoStack()->count() == cancelCount &&
              document.undoStack()->canRedo() == cancelCanRedo &&
              document.history().currentDocumentIdentity() == cancelIdentity &&
              document.isDirty() == cancelDirty,
          QStringLiteral("cancelling a live preview did not preserve its redo tail exactly"));

    // Empty ticks insert a marker on accept even if the inherited selection
    // was untouched; later row changes still collapse into a single insert.
    bool untouchedOpened = false;
    int untouchedInitial = -1;
    QTimer::singleShot(0, [&] {
        auto *dialog = qobject_cast<QDialog *>(QApplication::activeModalWidget());
        auto *list = dialog ? dialog->findChild<QListWidget *>() : nullptr;
        if (!dialog || !list)
            return;
        untouchedOpened = true;
        untouchedInitial = list->currentRow();
        dialog->accept();
    });
    doubleClickArea(env, QPointF(xForTick(env, 96), markerY));
    DocLanePoint inserted{};
    check(untouchedOpened && untouchedInitial == 3 &&
              document.undoStack()->index() == baseIndex + 1 &&
              document.undoStack()->count() == baseIndex + 1 &&
              document.undoStack()->text(baseIndex) == QStringLiteral("add voice change") &&
              document.findLanePoint(0, DOC_CC_VOICE, 96, &inserted) && inserted.value == 3,
          QStringLiteral("untouched empty-tick acceptance did not add exactly one inherited "
                         "voice marker"));
    document.undoStack()->undo();
    pump();
    check(!document.findLanePoint(0, DOC_CC_VOICE, 96, &inserted),
          QStringLiteral("undo did not remove the untouched empty-tick marker"));
    document.undoStack()->redo();
    pump();
    check(document.findLanePoint(0, DOC_CC_VOICE, 96, &inserted) && inserted.value == 3,
          QStringLiteral("redo did not restore the untouched empty-tick marker"));
    document.undoStack()->setIndex(baseIndex);
    pump();

    opened = false;
    QTimer::singleShot(0, [&] {
        auto *dialog = qobject_cast<QDialog *>(QApplication::activeModalWidget());
        auto *list = dialog ? dialog->findChild<QListWidget *>() : nullptr;
        if (!dialog || !list)
            return;
        opened = true;
        list->setCurrentRow(3);
        list->setCurrentRow(5);
        list->setCurrentRow(7);
        dialog->accept();
    });
    doubleClickArea(env, QPointF(xForTick(env, 96), markerY));
    check(opened && document.undoStack()->index() == baseIndex + 1 &&
              document.undoStack()->count() == baseIndex + 1 &&
              document.undoStack()->text(baseIndex) == QStringLiteral("add voice change") &&
              document.findLanePoint(0, DOC_CC_VOICE, 96, &inserted) && inserted.value == 7,
          QStringLiteral("multi-row empty-tick preview did not commit one final marker"));
    document.undoStack()->undo();
    pump();
    check(!document.findLanePoint(0, DOC_CC_VOICE, 96, &inserted),
          QStringLiteral("undo did not remove the multi-row empty-tick marker"));
    document.undoStack()->redo();
    pump();
    check(document.findLanePoint(0, DOC_CC_VOICE, 96, &inserted) && inserted.value == 7,
          QStringLiteral("redo did not restore the multi-row empty-tick marker"));
    document.undoStack()->setIndex(baseIndex);
    pump();

    // The track-header caller takes the same live path for both its existing
    // first program event and a track with no program event at tick zero.
    QString trackTitle;
    QTimer::singleShot(0, [&] {
        auto *dialog = qobject_cast<QDialog *>(QApplication::activeModalWidget());
        auto *list = dialog ? dialog->findChild<QListWidget *>() : nullptr;
        if (!dialog || !list)
            return;
        trackTitle = dialog->windowTitle();
        list->setCurrentRow(3);
        list->setCurrentRow(5);
        list->setCurrentRow(7);
        dialog->accept();
    });
    env.view->editTrackVoice(0);
    check(trackTitle == QStringLiteral("Track 1 voice") &&
              document.undoStack()->index() == baseIndex + 1 &&
              document.undoStack()->text(baseIndex) == QStringLiteral("change voice") &&
              document.findLanePoint(0, DOC_CC_VOICE, 0, &inserted) && inserted.value == 7,
          QStringLiteral("editTrackVoice did not commit its existing first marker once"));
    document.undoStack()->undo();
    pump();
    check(document.findLanePoint(0, DOC_CC_VOICE, 0, &inserted) && inserted.value == 0,
          QStringLiteral("track-header undo did not restore the original first program"));
    document.undoStack()->redo();
    pump();
    check(document.findLanePoint(0, DOC_CC_VOICE, 0, &inserted) && inserted.value == 7,
          QStringLiteral("track-header redo did not restore the selected first program"));
    document.undoStack()->setIndex(baseIndex);
    pump();

    trackTitle.clear();
    QTimer::singleShot(0, [&] {
        auto *dialog = qobject_cast<QDialog *>(QApplication::activeModalWidget());
        auto *list = dialog ? dialog->findChild<QListWidget *>() : nullptr;
        if (!dialog || !list)
            return;
        trackTitle = dialog->windowTitle();
        list->setCurrentRow(3);
        list->setCurrentRow(5);
        list->setCurrentRow(7);
        dialog->accept();
    });
    env.view->editTrackVoice(2);
    check(trackTitle == QStringLiteral("Track 3 voice") &&
              document.undoStack()->index() == baseIndex + 1 &&
              document.undoStack()->text(baseIndex) == QStringLiteral("add voice change") &&
              document.findLanePoint(2, DOC_CC_VOICE, 0, &inserted) && inserted.value == 7,
          QStringLiteral("track-header tick-zero insertion did not commit exactly once"));
    document.undoStack()->undo();
    pump();
    check(!document.findLanePoint(2, DOC_CC_VOICE, 0, &inserted),
          QStringLiteral("track-header insertion undo did not remove its tick-zero marker"));
    document.undoStack()->redo();
    pump();
    check(document.findLanePoint(2, DOC_CC_VOICE, 0, &inserted) && inserted.value == 7,
          QStringLiteral("track-header insertion redo did not restore its final voice"));
    document.undoStack()->setIndex(baseIndex);
    pump();

    // Detaching a view rejects the owned modal synchronously; after the
    // modal frame unwinds, its preview is restored before reattachment and
    // any later queued row/accept action is inert.
    const QByteArray detachedSmf = document.smf().write();
    const int detachedIndex = document.undoStack()->index();
    const int detachedCount = document.undoStack()->count();
    const auto detachedIdentity = document.history().currentDocumentIdentity();
    const bool detachedDirty = document.isDirty();
    bool detachedOpened = false;
    bool detachedRejected = false;
    bool lateActionRan = false;
    QPointer<QDialog> staleDialog;
    QPointer<QListWidget> staleList;
    QTimer::singleShot(0, [&] {
        auto *dialog = qobject_cast<QDialog *>(QApplication::activeModalWidget());
        auto *list = dialog ? dialog->findChild<QListWidget *>() : nullptr;
        if (!dialog || !list)
            return;
        detachedOpened = true;
        staleDialog = dialog;
        staleList = list;
        list->setCurrentRow(7);
        DocLanePoint previewed{};
        check(document.findLanePoint(0, DOC_CC_VOICE, 48, &previewed) && previewed.value == 7,
              QStringLiteral("detachment setup did not create the live preview"));
        env.view->setDocument(nullptr);
        detachedRejected = dialog->result() == QDialog::Rejected;
        QTimer::singleShot(0, [&] {
            lateActionRan = true;
            if (staleList)
                staleList->setCurrentRow(9);
            if (staleDialog)
                staleDialog->accept();
        });
    });
    doubleClickArea(env, QPointF(xForTick(env, 48), markerY));
    pump();
    check(detachedOpened && detachedRejected && lateActionRan &&
              document.smf().write() == detachedSmf &&
              document.undoStack()->index() == detachedIndex &&
              document.undoStack()->count() == detachedCount &&
              document.history().currentDocumentIdentity() == detachedIdentity &&
              document.isDirty() == detachedDirty,
          QStringLiteral("detached picker or its queued actions created a document command"));
    env.view->setDocument(&document);
    pump();

    // Once an unrelated mutation owns the revision, a direct session must
    // abandon rather than restore captured indices over that mutation.
    SongDocument guarded;
    SongInfo guardedInfo;
    guardedInfo.label = QStringLiteral("voicechange-revision-guard");
    guardedInfo.midPath = env.dir.filePath(QStringLiteral("voicechange-revision-guard.mid"));
    guardedInfo.hasMid = true;
    QString error;
    if (!document.smf().writeFile(guardedInfo.midPath, &error) ||
        !guarded.load(guardedInfo, &error)) {
        check(false, QStringLiteral("revision-abandon fixture could not load: %1").arg(error));
    } else {
        {
            auto session = guarded.beginVoiceChangeLiveSession(0, 48);
            session.select(8);
            guarded.addLanePoint(0, DOC_CC_VOICE, 192, 6);
            const QByteArray externallyChanged = guarded.smf().write();
            session.select(9);
            session.commit(9);
            check(guarded.smf().write() == externallyChanged,
                  QStringLiteral("revision-abandoned session accepted a later selection"));
        }
        DocLanePoint guardedVoice{};
        DocLanePoint unrelated{};
        check(guarded.findLanePoint(0, DOC_CC_VOICE, 48, &guardedVoice) &&
                  guardedVoice.value == 8 &&
                  guarded.findLanePoint(0, DOC_CC_VOICE, 192, &unrelated) && unrelated.value == 6 &&
                  guarded.undoStack()->count() == 1,
              QStringLiteral("revision-abandoned session reverted the preview or unrelated edit"));
    }

    check(document.smf().write() == baseSmf && document.undoStack()->index() == baseIndex &&
              document.history().currentDocumentIdentity() == baseIdentity &&
              document.isDirty() == baseDirty,
          QStringLiteral("live-picker coverage did not restore its fixture state"));
}

// Camera: pan pauses follow and clamps at tick zero, wheel zoom pins the
// tick under the cursor, and Escape ends a pan mid-gesture.
void checkAreaCamera(AreaFixture &env, int &failures)
{
    auto *area = env.area;
    const auto check = [&failures](bool condition, const QString &message) {
        if (condition)
            return;
        std::fprintf(stderr, "drawer: FAIL voice-change-area: %s\n", qUtf8Printable(message));
        ++failures;
    };
    const QImage home = area->grab().toImage();
    const auto warm = area->diagnostics();
    const double homeZoom = env.view->pxPerBeat();
    const double homeScroll = env.view->viewState().scrollPx;

    env.view->setEditorHorizontalScroll(64.0);
    pump();
    check(area->diagnostics().contentInvalidationCount > warm.contentInvalidationCount &&
              area->grab().toImage() != home,
          QStringLiteral("horizontal scroll did not scroll the voice content"));

    const QPointF zoomAnchor(area->plotOrigin() + area->plotWidth() / 2.0, area->height() / 2.0);
    const double tickBeforeZoom = env.view->tickAtContentX(zoomAnchor.x() - area->plotOrigin());
    const double zoomBefore = env.view->pxPerBeat();
    checks::events::sendWheel(*area, zoomAnchor, QPoint(), QPoint(0, 120), Qt::NoButton,
                              Qt::NoModifier, Qt::NoScrollPhase, false);
    pump();
    check(env.view->pxPerBeat() > zoomBefore,
          QStringLiteral("plain wheel did not zoom the shared timeline camera"));
    const qreal anchoredX =
        env.view->displayX(tickBeforeZoom, area->plotOrigin(), area->devicePixelRatioF());
    check(std::abs(anchoredX - zoomAnchor.x()) <= 1.0 / area->devicePixelRatioF(),
          QStringLiteral("wheel zoom did not preserve the tick under the cursor"));

    // The canonical camera's tick-zero home includes its documented lead pad.
    // Dragging farther left must clamp at that floor without changing paint.
    const double minScroll = -env.view->leadPadPx();
    env.view->setEditorTimeZoom(homeZoom);
    env.view->setEditorHorizontalScroll(minScroll);
    pump();
    const QImage atZero = area->grab().toImage();
    const QPointF panStart(area->plotOrigin() + 40, area->height() / 2.0);
    checks::events::sendMouse(*area, QEvent::MouseButtonPress, panStart, Qt::MiddleButton,
                              Qt::MiddleButton, Qt::NoModifier);
    checks::events::sendMouse(*area, QEvent::MouseMove, panStart + QPointF(80, 0), Qt::NoButton,
                              Qt::MiddleButton, Qt::NoModifier);
    pump();
    check(env.view->viewState().scrollPx == minScroll && area->grab().toImage() == atZero,
          QStringLiteral("panning left at tick-zero home overscrolled the voice lane"));
    checks::events::sendMouse(*area, QEvent::MouseButtonRelease, panStart + QPointF(80, 0),
                              Qt::MiddleButton, Qt::NoButton, Qt::NoModifier);
    pump();

    // A rightward pan scrolls; Escape mid-pan stops further movement.
    checks::events::sendMouse(*area, QEvent::MouseButtonPress, panStart, Qt::MiddleButton,
                              Qt::MiddleButton, Qt::NoModifier);
    checks::events::sendMouse(*area, QEvent::MouseMove, panStart + QPointF(-48, 0), Qt::NoButton,
                              Qt::MiddleButton, Qt::NoModifier);
    pump();
    const double scrolled = env.view->viewState().scrollPx;
    check(scrolled > minScroll, QStringLiteral("middle drag did not pan the voice lane"));
    checks::events::sendKey(*area, QEvent::KeyPress, Qt::Key_Escape, Qt::NoModifier, QString{},
                            false, 1);
    checks::events::sendMouse(*area, QEvent::MouseMove, panStart + QPointF(-96, 0), Qt::NoButton,
                              Qt::MiddleButton, Qt::NoModifier);
    checks::events::sendMouse(*area, QEvent::MouseButtonRelease, panStart + QPointF(-96, 0),
                              Qt::MiddleButton, Qt::NoButton, Qt::NoModifier);
    pump();
    check(env.view->viewState().scrollPx == scrolled,
          QStringLiteral("Escape did not stop the voice-lane pan"));
    QEvent leave(QEvent::Leave);
    QCoreApplication::sendEvent(area, &leave);
    env.view->setEditorTimeZoom(homeZoom);
    env.view->setEditorHorizontalScroll(homeScroll);
    pump();
    check(changedPixels(home, area->grab().toImage(), area->rect(), area->devicePixelRatioF()) == 0,
          QStringLiteral("camera probes did not restore the home framing"));
}

} // namespace

void checkVoiceChangeAreaPage(int &failures)
{
    AreaFixture env;
    QString error;
    if (!createAreaFixture(env, error)) {
        std::fprintf(stderr, "drawer: FAIL voice-change-area: %s\n", qUtf8Printable(error));
        ++failures;
        return;
    }
    const QByteArray baselineSmf = env.document.smf().write();
    checkAreaSurfaceBasics(env, failures);
    checkAreaPaintLifecycle(env, failures);
    checkAreaHover(env, failures);
    checkAreaRefresh(env, failures);
    checkAreaCommits(env, failures);
    checkAreaLiveVoiceChanges(env, failures);
    checkAreaCamera(env, failures);
    if (env.document.smf().write() != baselineSmf) {
        std::fprintf(stderr, "drawer: FAIL voice-change-area: fixture document not restored\n");
        ++failures;
    }
    env.view->hide();
    pump();
}
