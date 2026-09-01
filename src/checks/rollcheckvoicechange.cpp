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
#include <QQuickItem>
#include <QQuickWidget>
#include <QTemporaryDir>
#include <QTimer>

#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "core/miditimeline.h"
#include "core/smf.h"
#include "core/songdocument.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/editorviewstate.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickscene.h"

namespace {

// Self-contained fixture: one synthesized two-track song, one voicegroup,
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
    smf.tracks.resize(3);
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
    SongInfo info;
    info.label = QStringLiteral("voicechange-area-fixture");
    info.midPath = env.dir.filePath(QStringLiteral("voicechange-fixture.mid"));
    info.hasMid = true;
    if (!smf.writeFile(info.midPath, &error) || !env.document.load(info, &error)) {
        error = QStringLiteral("voice-change fixture song failed to load: %1").arg(error);
        return false;
    }
    if (env.document.engineTrackCount() < 2) {
        error = QStringLiteral("voice-change fixture did not expose two engine tracks");
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

int changedPixelsOutside(const QImage &before, const QImage &after, const QRectF &logical,
                         qreal dpr)
{
    if (before.size() != after.size() || before.format() != after.format())
        return -1;
    const QRect excluded = deviceRect(logical, dpr, before.size()).intersected(before.rect());
    if (excluded.isEmpty())
        return -1;
    auto count = 0;
    for (int y = 0; y < before.height(); ++y) {
        for (int x = 0; x < before.width(); ++x) {
            if (!excluded.contains(x, y) && before.pixel(x, y) != after.pixel(x, y))
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
    const QImage idle = checks::support::captureQuickBand(*env.view, *area);
    const qreal dpr = idle.devicePixelRatio();
    const uint64_t revisionBefore = env.document.revision();
    const int undoBefore = env.document.undoStack()->index();

    env.document.addLanePoint(0, DOC_CC_VOICE, 120, 5);
    pump();
    const QImage marked = checks::support::captureQuickBand(*env.view, *area);
    const double markerX = xForTick(env, 120);
    check(env.document.revision() == revisionBefore + 1 &&
              env.document.undoStack()->index() == undoBefore + 1 &&
              env.document.undoStack()->text(undoBefore) == QStringLiteral("add voice change"),
          QStringLiteral("document commit was not one undo step labelled 'add voice change'"));
    check(changedPixels(idle, marked, QRectF(markerX - 8, 0, 16, area->height()), dpr) > 0,
          QStringLiteral("added voice change marker painted no column at its tick"));

    env.document.undoStack()->undo();
    pump();
    const QImage unmarked = checks::support::captureQuickBand(*env.view, *area);
    check(changedPixels(idle, unmarked, area->rect(), dpr) == 0,
          QStringLiteral("undo did not restore the marker-free paint"));

    // Playhead-only presentations must not rebuild content within one held
    // span, and must invalidate once when the displayed context crosses it.
    const auto warm = area->diagnostics();
    env.view->setPlayheadSample(env.timeline->sampleForTick(16), true);
    pump();
    const QImage playingA = checks::support::captureQuickBand(*env.view, *area);
    const auto afterFirstPresent = area->diagnostics();
    env.view->setPlayheadSample(env.timeline->sampleForTick(32), true);
    pump();
    check(area->diagnostics() == afterFirstPresent,
          QStringLiteral("same-span playhead presentations invalidated voice content"));
    env.view->setPlayheadSample(env.timeline->sampleForTick(64), true);
    pump();
    check(area->diagnostics().contentInvalidationCount > afterFirstPresent.contentInvalidationCount,
          QStringLiteral("playhead crossing the voice change did not refresh the context"));
    const QImage playingB = checks::support::captureQuickBand(*env.view, *area);
    check(changedPixels(playingA, playingB,
                        QRectF(area->plotOrigin() + area->plotWidth() / 2.0, 0,
                               area->plotWidth() / 2.0, area->height()),
                        dpr) > 0,
          QStringLiteral("playhead crossing did not repaint the current-voice readout"));
    env.view->setPlayheadSample(0, false);
    pump();
    check(checks::support::captureQuickBand(*env.view, *area) == idle,
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
    check(changedPixels(idle, checks::support::captureQuickBand(*env.view, *area), area->rect(),
                        dpr) == 0,
          QStringLiteral("song re-attach did not restore the marker-free paint"));
}

// Hover: dotted line plus held label away from markers, label suppressed on
// the marker tick, Quick-only framebuffer deltas, and clearing on leave/hide/Escape.
void checkAreaHover(AreaFixture &env, int &failures)
{
    auto *area = env.area;
    const auto check = [&failures](bool condition, const QString &message) {
        if (condition)
            return;
        std::fprintf(stderr, "drawer: FAIL voice-change-area: %s\n", qUtf8Printable(message));
        ++failures;
    };
    // Enter playback before establishing hover so crossing the voice slot
    // below is a presentation-only content invalidation, not a lifecycle reset.
    env.view->setPlayheadSample(env.timeline->sampleForTick(64), true);
    pump();
    env.view->setPlayheadSample(env.timeline->sampleForTick(16), true);
    pump();
    const QImage idle = checks::support::captureQuickBand(*env.view, *area);
    const qreal dpr = idle.devicePixelRatio();
    auto *scene = env.view->findChild<songview::TimelineQuickScene *>();
    auto *voiceChangesTextModel = scene ? scene->voiceChangesTextModel() : nullptr;
    auto *voiceChangesHoverTextModel = scene ? scene->voiceChangesHoverTextModel() : nullptr;
    if (!voiceChangesTextModel || !voiceChangesHoverTextModel) {
        check(false, QStringLiteral("Voice Changes Quick text models were not available"));
        return;
    }
    const auto currentHoverLabelRect = [voiceChangesHoverTextModel] {
        return voiceChangesHoverTextModel
            ->data(voiceChangesHoverTextModel->index(0, 0),
                   songview::TimelineQuickTextModel::RectRole)
            .toRectF();
    };
    const int mainTextRowCount = voiceChangesTextModel->rowCount();
    check(voiceChangesHoverTextModel->rowCount() == 0,
          QStringLiteral("Voice Changes hover model was not empty before hovering"));

    const double offMarkerX = xForTick(env, 96);
    checks::events::sendMouse(*area, QEvent::MouseMove, QPointF(offMarkerX, area->height() / 2.0),
                              Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    pump();
    const QImage offMarker = checks::support::captureQuickBand(*env.view, *area);
    const QRectF hoverLabelRect = currentHoverLabelRect();
    const QRectF hoverRegion = QRectF(offMarkerX - 2.0, 0.0, 4.0, area->height())
                                   .united(hoverLabelRect.adjusted(-2.0, -2.0, 2.0, 2.0));
    const auto hoverProbe = [area](double x, const QRectF &labelRect) {
        return QRectF(x - 2.0, 0.0, 4.0, area->height())
            .united(QRectF(labelRect.left() - 2.0, labelRect.top() - 2.0,
                           std::min<qreal>(144.0, labelRect.width() + 4.0),
                           labelRect.height() + 4.0));
    };
    check(voiceChangesHoverTextModel->rowCount() == 1 &&
              voiceChangesTextModel->rowCount() == mainTextRowCount,
          QStringLiteral("off-marker hover did not isolate its Quick text model"));
    check(hoverLabelRect.isValid() && changedPixels(idle, offMarker, hoverRegion, dpr) > 0,
          QStringLiteral("off-marker hover changed no pixels in its Quick line/label region"));
    check(changedPixelsOutside(idle, offMarker, hoverRegion, dpr) == 0,
          QStringLiteral("off-marker hover changed pixels outside its Quick line/label region"));
    const uint64_t contentInvalidations = area->diagnostics().contentInvalidationCount;
    env.view->setPlayheadSample(env.timeline->sampleForTick(64), true);
    pump();
    const QImage contentOnlyHover = checks::support::captureQuickBand(*env.view, *area);
    const QRectF contentOnlyLabelRect = currentHoverLabelRect();
    check(area->diagnostics().contentInvalidationCount > contentInvalidations,
          QStringLiteral(
              "playhead context crossing did not trigger full voice content invalidation"));
    check(voiceChangesHoverTextModel->rowCount() == 1 &&
              voiceChangesTextModel->rowCount() == mainTextRowCount &&
              contentOnlyLabelRect == hoverLabelRect &&
              changedPixels(idle, contentOnlyHover, hoverProbe(offMarkerX, contentOnlyLabelRect),
                            dpr) > 0,
          QStringLiteral("full Voice Changes rebuild did not restore active Quick hover"));

    checks::events::sendMouse(*area, QEvent::MouseMove, QPointF(offMarkerX, area->height() / 2.0),
                              Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    pump();
    const QImage samePointerHover = checks::support::captureQuickBand(*env.view, *area);
    const QRectF samePointerLabelRect = currentHoverLabelRect();
    check(voiceChangesHoverTextModel->rowCount() == 1 &&
              samePointerLabelRect == contentOnlyLabelRect &&
              samePointerHover == contentOnlyHover &&
              changedPixels(idle, samePointerHover, hoverProbe(offMarkerX, samePointerLabelRect),
                            dpr) > 0,
          QStringLiteral("same-pointer hover stayed suppressed after the full Quick rebuild"));

    const double coalescedHoverX = xForTick(env, 120);
    const uint64_t coalescedInvalidations = area->diagnostics().contentInvalidationCount;
    // Queue a second hover target before the full-content flush coalesces.
    env.view->setPlayheadSample(env.timeline->sampleForTick(16), true);
    checks::events::sendMouse(*area, QEvent::MouseMove,
                              QPointF(coalescedHoverX, area->height() / 2.0), Qt::NoButton,
                              Qt::NoButton, Qt::NoModifier);
    pump();
    const QImage coalescedHover = checks::support::captureQuickBand(*env.view, *area);
    const QRectF coalescedLabelRect = currentHoverLabelRect();
    check(area->diagnostics().contentInvalidationCount > coalescedInvalidations,
          QStringLiteral("coalesced hover did not trigger full voice content invalidation"));
    check(voiceChangesHoverTextModel->rowCount() == 1 &&
              voiceChangesTextModel->rowCount() == mainTextRowCount &&
              coalescedLabelRect.isValid() &&
              changedPixels(idle, coalescedHover, hoverProbe(coalescedHoverX, coalescedLabelRect),
                            dpr) > 0,
          QStringLiteral("coalesced Voice Changes content and hover rebuild lost Quick hover"));

    const double markerX = xForTick(env, 48);
    checks::events::sendMouse(*area, QEvent::MouseMove, QPointF(markerX, area->height() / 2.0),
                              Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    pump();
    const QImage onMarker = checks::support::captureQuickBand(*env.view, *area);
    check(voiceChangesHoverTextModel->rowCount() == 0 &&
              voiceChangesTextModel->rowCount() == mainTextRowCount,
          QStringLiteral("marker hover did not keep the Quick text models isolated"));
    check(changedPixels(offMarker, onMarker, QRectF(markerX - 8, 0, 16, area->height()), dpr) > 0,
          QStringLiteral("hover did not track the marker tick"));
    check(labelCrop(onMarker, markerX, dpr) == labelCrop(idle, markerX, dpr),
          QStringLiteral("hovering the marker painted a held label on top of it"));

    QEvent leave(QEvent::Leave);
    QCoreApplication::sendEvent(area, &leave);
    pump();
    check(checks::support::captureQuickBand(*env.view, *area) == idle &&
              voiceChangesHoverTextModel->rowCount() == 0 &&
              voiceChangesTextModel->rowCount() == mainTextRowCount,
          QStringLiteral("leave did not clear the Quick hover state"));

    checks::events::sendMouse(*area, QEvent::MouseMove, QPointF(offMarkerX, area->height() / 2.0),
                              Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    pump();
    checks::events::sendKey(*area, QEvent::KeyPress, Qt::Key_Escape, Qt::NoModifier, QString{},
                            false, 1);
    pump();
    check(checks::support::captureQuickBand(*env.view, *area) == idle &&
              voiceChangesHoverTextModel->rowCount() == 0 &&
              voiceChangesTextModel->rowCount() == mainTextRowCount,
          QStringLiteral("Escape did not clear the Quick hover state"));

    checks::events::sendMouse(*area, QEvent::MouseMove, QPointF(offMarkerX, area->height() / 2.0),
                              Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    pump();
    env.view->setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
    env.view->setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    pump();
    check(checks::support::captureQuickBand(*env.view, *area) == idle &&
              voiceChangesHoverTextModel->rowCount() == 0 &&
              voiceChangesTextModel->rowCount() == mainTextRowCount,
          QStringLiteral("page hide and re-show did not clear the Quick hover state"));
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
    const QImage track0 = checks::support::captureQuickBand(*env.view, *area);

    env.view->selectTrack(1);
    pump();
    const QImage track1 = checks::support::captureQuickBand(*env.view, *area);
    check(track1 != track0,
          QStringLiteral("selecting another primary track did not recapture the area"));

    auto *quickCanvas = env.view->findChild<QQuickWidget *>(QStringLiteral("timelineQuickCanvas"));
    auto *quickRoot = quickCanvas ? quickCanvas->rootObject() : nullptr;
    if (!quickRoot) {
        check(false, QStringLiteral("Voice Changes Quick root was not available"));
        return;
    }
    env.view->setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
    pump();
    const QImage hidden = checks::support::captureQuickBand(*env.view, *area);
    check(!area->isVisible() && !quickRoot->property("voiceChangesBandVisible").toBool() &&
              quickRoot->property("voiceChangesBandRect").toRectF().isEmpty() && hidden != track1,
          QStringLiteral("hiding Voice Changes did not remove its Quick band"));
    env.view->selectTrack(0);
    env.view->setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    pump();
    const QImage reopened = checks::support::captureQuickBand(*env.view, *area);
    check(reopened == track0,
          QStringLiteral("reopening Voice Changes after a hidden context change was stale"));

    env.view->setVoicegroup(nullptr);
    pump();
    check(checks::support::captureQuickBand(*env.view, *area) != track0,
          QStringLiteral("clearing the voicegroup did not repaint unresolved labels"));
    env.view->setVoicegroup(&env.voicegroup);
    pump();
    check(checks::support::captureQuickBand(*env.view, *area) == track0,
          QStringLiteral("restoring the voicegroup did not repaint cached labels"));

    std::strncpy(env.voicegroup.voiceNames[3], "renamed-check",
                 sizeof(env.voicegroup.voiceNames[3]) - 1);
    env.view->setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
    env.view->setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    pump();
    check(checks::support::captureQuickBand(*env.view, *area) != track0,
          QStringLiteral("renaming a voice in place did not refresh the cached labels"));
    std::strncpy(env.voicegroup.voiceNames[3], "voice-check",
                 sizeof(env.voicegroup.voiceNames[3]) - 1);
    env.view->setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
    env.view->setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    pump();
    check(checks::support::captureQuickBand(*env.view, *area) == track0,
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
    const QImage afterUndo = checks::support::captureQuickBand(*env.view, *area);
    document.undoStack()->redo();
    pump();
    check(document.findLanePoint(0, DOC_CC_VOICE, 96, &inserted) && inserted.value == 3 &&
              changedPixels(afterUndo, checks::support::captureQuickBand(*env.view, *area),
                            QRectF(xForTick(env, 96) - 8, 0, 16, area->height()),
                            afterUndo.devicePixelRatio()) > 0,
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
    const QImage home = checks::support::captureQuickBand(*env.view, *area);
    const auto warm = area->diagnostics();
    const double homeZoom = env.view->pxPerBeat();
    const double homeScroll = env.view->viewState().scrollPx;

    env.view->setEditorHorizontalScroll(64.0);
    pump();
    check(area->diagnostics().contentInvalidationCount > warm.contentInvalidationCount &&
              checks::support::captureQuickBand(*env.view, *area) != home,
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
    const QImage atZero = checks::support::captureQuickBand(*env.view, *area);
    const QPointF panStart(area->plotOrigin() + 40, area->height() / 2.0);
    checks::events::sendMouse(*area, QEvent::MouseButtonPress, panStart, Qt::MiddleButton,
                              Qt::MiddleButton, Qt::NoModifier);
    checks::events::sendMouse(*area, QEvent::MouseMove, panStart + QPointF(80, 0), Qt::NoButton,
                              Qt::MiddleButton, Qt::NoModifier);
    pump();
    check(env.view->viewState().scrollPx == minScroll &&
              checks::support::captureQuickBand(*env.view, *area) == atZero,
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
    check(changedPixels(home, checks::support::captureQuickBand(*env.view, *area), area->rect(),
                        home.devicePixelRatio()) == 0,
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
    checkAreaCamera(env, failures);
    if (env.document.smf().write() != baselineSmf) {
        std::fprintf(stderr, "drawer: FAIL voice-change-area: fixture document not restored\n");
        ++failures;
    }
    env.view->hide();
    pump();
}
