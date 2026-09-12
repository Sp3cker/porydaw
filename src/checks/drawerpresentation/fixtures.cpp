#include "checks/drawerpresentation/fixtures.h"

#include <algorithm>
#include <cstring>
#include <optional>

#include <QCoreApplication>
#include <QGuiApplication>
#include <QQuickItem>
#include <QTest>
#include <QtGlobal>

#include "checks/support/editorrig.h"
#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/support.h"
#include "core/miditimeline.h"
#include "core/smf.h"
#include "core/tracklimits.h"
#include "project/projectidentity.h"
#include "project/voicegroupsource.h"
#include "ui/editordrawer/drawerchrome.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"

namespace {

SmfEvent noteEvent(uint8_t status, uint64_t tick, uint8_t key, uint8_t velocity)
{
    return {.tick = tick, .status = status, .data0 = key, .data1 = velocity};
}

SmfFile voiceSmf()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    smf.tracks.resize(3);
    smf.tracks[0].events.push_back(
        {.tick = 0, .status = 0xFF, .metaType = 0x51, .blob = QByteArray("\x07\xA1\x20", 3)});
    smf.tracks[0].endTick = 384;
    smf.tracks[1].events = {noteEvent(0xC0, 0, 0, 0), noteEvent(0x90, 0, 60, 100),
                            noteEvent(0x80, 48, 60, 0)};
    smf.tracks[1].endTick = 384;
    smf.tracks[2].events = {noteEvent(0xC1, 0, 5, 0), noteEvent(0x91, 0, 48, 100),
                            noteEvent(0x81, 48, 48, 0)};
    smf.tracks[2].endTick = 384;
    return smf;
}

SmfFile velocitySmf()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    SmfTrack track;
    track.events = {noteEvent(0xC0, 0, 0, 0),    noteEvent(0x90, 12, 60, 20),
                    noteEvent(0x90, 12, 60, 70), noteEvent(0x80, 36, 60, 0),
                    noteEvent(0x80, 36, 60, 0),  noteEvent(0x90, 60, 64, 70),
                    noteEvent(0x80, 84, 64, 0)};
    track.endTick = 84;
    smf.tracks.push_back(std::move(track));
    return smf;
}

SmfFile drawerSmf()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    smf.tracks.resize(17);
    smf.tracks[0].events.push_back(
        {.tick = 0, .status = 0xFF, .metaType = 0x51, .blob = QByteArray("\x07\xA1\x20", 3)});
    smf.tracks[0].endTick = 48;
    for (int track = 1; track <= 16; ++track) {
        smf.tracks[track].events = {noteEvent(uint8_t(0xC0 + track - 1), 0, 0, 0),
                                    noteEvent(uint8_t(0x90 + track - 1), 0, 60, 100),
                                    noteEvent(uint8_t(0x80 + track - 1), 48, 60, 0)};
        smf.tracks[track].endTick = 48;
    }
    return smf;
}

QRect band(const SongView &view, songview::TimelineBand band)
{
    const auto &geometry = view.timelineBandLayout().geometry(band);
    return geometry ? geometry->rect : QRect{};
}

QRect plot(const SongView &view, songview::TimelineBand band)
{
    const auto &geometry = view.timelineBandLayout().geometry(band);
    return geometry ? geometry->plotRect : QRect{};
}

int fixedSpan(const SongView &view, songview::TimelineBand which)
{
    const QRect area = band(view, which);
    const QRect plotArea = plot(view, which);
    return std::max(0, plotArea.x() - area.x());
}

} // namespace

namespace checks::drawerpresentation {

void createVoiceFixture(VoiceFixture &fixture)
{
    QString error;
    if (!fixture.create(error))
        qFatal("%s", qPrintable(error));
}

void createVoiceFixture(VoiceTransactionFixture &fixture)
{
    QString error;
    if (!fixture.create(error))
        qFatal("%s", qPrintable(error));
}

void pump()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
}

void sendMouse(songview::TimelineInputItem &input, QEvent::Type type, const QPointF &position,
               Qt::MouseButton button, Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers)
{
    events::sendMouse(input, type, position, button, buttons, modifiers);
}

void sendKey(QObject &target, int key, Qt::KeyboardModifiers modifiers)
{
    events::sendKey(target, QEvent::KeyPress, key, modifiers, {}, false, 1);
    events::sendKey(target, QEvent::KeyRelease, key, modifiers, {}, false, 1);
}

bool layerTouches(const songview::TimelineQuickScene &scene, songview::TimelineQuickLayer layer,
                  const QRectF &probe, const QColor &color)
{
    const auto &data = scene.layer(layer);
    const auto rectTouches = [&probe, &color](const songview::TimelineQuickRect &rect) {
        return rect.rect.intersects(probe) &&
               (rect.topLeft == color || rect.topRight == color || rect.bottomLeft == color ||
                rect.bottomRight == color);
    };
    if (std::any_of(data.rects.cbegin(), data.rects.cend(), rectTouches))
        return true;
    const auto triangleTouches = [&probe, &color](const songview::TimelineQuickTriangle &triangle) {
        const QRectF bounds = QRectF(triangle.first, triangle.second)
                                  .normalized()
                                  .united(QRectF(triangle.first, triangle.third).normalized())
                                  .united(QRectF(triangle.second, triangle.third).normalized());
        return bounds.intersects(probe) &&
               (triangle.firstColor == color || triangle.secondColor == color ||
                triangle.thirdColor == color);
    };
    return std::any_of(data.triangles.cbegin(), data.triangles.cend(), triangleTouches);
}

bool layerEmpty(const songview::TimelineQuickScene &scene, songview::TimelineQuickLayer layer)
{
    const auto &data = scene.layer(layer);
    return data.rects.empty() && data.triangles.empty();
}

DrawerFixture::~DrawerFixture()
{
    destroy();
}

bool DrawerFixture::create(QString &error)
{
    error.clear();
    const std::optional<SongName> name = SongName::create(QStringLiteral("drawer-transaction"));
    const std::optional<VoicegroupId> identity =
        VoicegroupId::create(QStringLiteral("drawer-transaction"), QString());
    if (!name || !identity) {
        error = QStringLiteral("drawer fixture has invalid identities");
        return false;
    }
    voicegroup.voices[0].type = VOICE_DIRECTSOUND;
    auto candidate = std::make_unique<SongTab>(std::move(*name));
    candidate->resize(960, 480);
    candidate->setSampleRate(48000.0);
    SongInfo info;
    info.label = QStringLiteral("drawer-transaction");
    info.hasMid = true;
    candidate->applyMidiStage(std::move(info), drawerSmf(), track_limits::kHardwareCapacity);
    candidate->applyBankView(
        LoadedBankView{*identity, borrowVoicegroupLease(&voicegroup), QString()});
    candidate->applyVoicegroupBound(*identity);
    if (!candidate->isReady() || !candidate->presentationError().isEmpty()) {
        error = QStringLiteral("drawer fixture did not become ready");
        return false;
    }
    checks::support::bindEditActionsForTest(candidate->view());
    candidate->show();
    pump();
    view = &candidate->view();
    quick = view->quickView();
    quickRoot = quick ? quick->rootObject() : nullptr;
    if (!quickRoot) {
        error = QStringLiteral("drawer fixture has no Quick root");
        return false;
    }
    voiceHandle = quickRoot->findChild<songview::TimelineInputItem *>(
        QStringLiteral("drawerVoiceChangesHandleInput"));
    velocityHandle = quickRoot->findChild<songview::TimelineInputItem *>(
        QStringLiteral("drawerVelocityHandleInput"));
    automationHandle = quickRoot->findChild<songview::TimelineInputItem *>(
        QStringLiteral("drawerAutomationHandleInput"));
    bar = quickRoot->findChild<songview::TimelineInputItem *>(QStringLiteral("drawerBarInput"));
    detent =
        quickRoot->findChild<songview::TimelineInputItem *>(QStringLiteral("drawerDetentInput"));
    if (!quick || !voiceHandle || !velocityHandle || !automationHandle || !bar || !detent) {
        error = QStringLiteral("drawer fixture could not resolve chrome inputs");
        return false;
    }
    // Popups and focus-loss cancel paths key off live window focus: stage
    // real automation-band focus (requestFocus plus focusWindow/focusObject
    // convergence), not just page visibility.
    auto *automationInput = quickRoot->findChild<songview::TimelineInputItem *>(
        QStringLiteral("timelineAutomationInput"));
    QQuickWindow *const quickWindow = quick ? quick->quickWindow() : nullptr;
    if (!automationInput || !quickWindow) {
        error = QStringLiteral("drawer fixture could not resolve automation input");
        return false;
    }
    view->focusTimelineBand(songview::TimelineBand::Automation, Qt::OtherFocusReason);
    if (!QTest::qWaitFor([quickWindow, automationInput] {
            return QGuiApplication::focusWindow() == quickWindow &&
                   QGuiApplication::focusObject() == automationInput &&
                   automationInput->hasActiveFocus();
        })) {
        error = QStringLiteral("drawer fixture could not stage automation focus");
        return false;
    }
    if (!support::waitForQuickFrame(*quickWindow, &error))
        return false;
    tab = std::move(candidate);
    return true;
}

void DrawerFixture::destroy()
{
    if (tab)
        tab->hide();
    pump();
    tab.reset();
    view = nullptr;
    quick = nullptr;
    quickRoot = nullptr;
    voiceHandle = nullptr;
    velocityHandle = nullptr;
    automationHandle = nullptr;
    bar = nullptr;
    detent = nullptr;
}

DrawerChrome &DrawerFixture::chrome() const
{
    return view->editorDrawer()->chrome();
}

QRect DrawerFixture::bandRect(songview::TimelineBand which) const
{
    return band(*view, which);
}

void DrawerFixture::clickToggle(EditorDrawerPage page) const
{
    const QRectF toggle = page == EditorDrawerPage::VoiceChanges ? chrome().voiceChangesToggleRect()
                          : page == EditorDrawerPage::Velocity   ? chrome().velocityToggleRect()
                                                                 : chrome().automationToggleRect();
    const QPointF point = toggle.center() - chrome().barRect().topLeft();
    sendMouse(*bar, QEvent::MouseButtonPress, point, Qt::LeftButton, Qt::LeftButton);
    sendMouse(*bar, QEvent::MouseButtonRelease, point, Qt::LeftButton);
    pump();
}

bool VoiceFixture::create(QString &error)
{
    error.clear();
    if (!directory.isValid()) {
        error = QStringLiteral("voice fixture could not create temporary directory");
        return false;
    }
    SongInfo info;
    info.label = QStringLiteral("drawer-voice");
    info.hasMid = true;
    info.midPath = directory.filePath(QStringLiteral("voice.mid"));
    SmfFile smf = voiceSmf();
    if (!smf.writeFile(info.midPath, &error) || !document.load(info, &error))
        return false;
    document.addLanePoint(0, DOC_CC_VOICE, 48, 3);
    voicegroup.voices[3].type = VOICE_NOISE;
    voicegroup.voices[5].type = VOICE_NOISE;
    std::strncpy(voicegroup.voiceNames[3], "voice-check", sizeof(voicegroup.voiceNames[3]) - 1);
    std::strncpy(voicegroup.voiceNames[5], "alt-voice", sizeof(voicegroup.voiceNames[5]) - 1);
    EditorRigConfig config;
    config.voicegroup = &voicegroup;
    config.track = 0;
    config.activePage = EditorDrawerPage::VoiceChanges;
    config.sections = {{EditorDrawerPage::VoiceChanges, 160}};
    config.timeZoom = 96.0;
    config.applyEditCursor = true;
    config.editCursorTick = 24;
    rig = EditorRig::create(document, config, error);
    return bool(rig);
}

void VoiceFixture::destroy()
{
    pump();
    rig.reset();
}

Snapshot VoiceFixture::snapshot()
{
    return {document.smf().write(), document.revision(), document.undoStack()->index()};
}

QRect VoiceFixture::bandRect() const
{
    return band(rig->view(), songview::TimelineBand::VoiceChanges);
}

QRect VoiceFixture::plotRect() const
{
    return plot(rig->view(), songview::TimelineBand::VoiceChanges);
}

int VoiceFixture::fixedSpan() const
{
    return ::fixedSpan(rig->view(), songview::TimelineBand::VoiceChanges);
}

double VoiceFixture::xForTick(double tick) const
{
    return rig->view().camera().displayX(tick, 0.0, input().devicePixelRatio());
}

songview::TimelineInputItem &VoiceFixture::input() const
{
    return rig->voiceInput();
}

songview::TimelineQuickScene *VoiceFixture::scene() const
{
    return rig->quickScene();
}

bool VoiceTransactionFixture::create(QString &error)
{
    error.clear();
    const std::optional<SongName> name =
        SongName::create(QStringLiteral("drawer-voice-transaction"));
    const std::optional<VoicegroupId> identity =
        VoicegroupId::create(QStringLiteral("drawer-voice-transaction"), QString());
    if (!name || !identity) {
        error = QStringLiteral("voice transaction fixture has invalid identities");
        return false;
    }
    voicegroup.voices[3].type = VOICE_NOISE;
    voicegroup.voices[5].type = VOICE_NOISE;
    std::strncpy(voicegroup.voiceNames[3], "voice-check", sizeof(voicegroup.voiceNames[3]) - 1);
    std::strncpy(voicegroup.voiceNames[5], "alt-voice", sizeof(voicegroup.voiceNames[5]) - 1);
    auto candidate = std::make_unique<SongTab>(std::move(*name));
    candidate->resize(1000, 640);
    candidate->setSampleRate(48000.0);
    SongInfo info;
    info.label = QStringLiteral("drawer-voice-transaction");
    info.hasMid = true;
    candidate->applyMidiStage(std::move(info), voiceSmf(), track_limits::kHardwareCapacity);
    candidate->applyBankView(
        LoadedBankView{*identity, borrowVoicegroupLease(&voicegroup), QString()});
    candidate->applyVoicegroupBound(*identity);
    if (!candidate->isReady() || !candidate->presentationError().isEmpty()) {
        error = QStringLiteral("voice transaction fixture did not become ready");
        return false;
    }
    checks::support::bindEditActionsForTest(candidate->view());
    candidate->document().addLanePoint(0, DOC_CC_VOICE, 48, 3);
    SongView &candidateView = candidate->view();
    candidateView.selectTrack(0);
    candidateView.setDrawerActivePage(EditorDrawerPage::VoiceChanges);
    candidateView.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    candidateView.setDrawerSectionHeight(EditorDrawerPage::VoiceChanges, 160);
    songview::TimelineQuickView *const quick = candidateView.quickView();
    auto *root = quick ? quick->rootObject() : nullptr;
    auto *voiceInput = root ? root->findChild<songview::TimelineInputItem *>(
                                  QStringLiteral("timelineVoiceChangesInput"))
                            : nullptr;
    QQuickWindow *const window = quick ? quick->quickWindow() : nullptr;
    if (!voiceInput || !window) {
        error = QStringLiteral("voice transaction fixture could not resolve input");
        return false;
    }
    candidate->show();
    // Hosted container path: exposure and band-geometry publication land
    // after the external widget shows; wait for the staged contract.
    if (!QTest::qWaitFor([window, voiceInput] {
            return window->isVisible() && window->isExposed() && !voiceInput->bounds().isEmpty() &&
                   voiceInput->window() == window;
        })) {
        error = QStringLiteral("voice transaction fixture could not resolve input");
        return false;
    }
    // The picker and menu restore paths key off live window focus: stage
    // real voice-band focus (requestFocus plus focusWindow/focusObject
    // convergence), not just page visibility.
    candidateView.focusTimelineBand(songview::TimelineBand::VoiceChanges, Qt::OtherFocusReason);
    if (!QTest::qWaitFor([window, voiceInput] {
            return QGuiApplication::focusWindow() == window &&
                   QGuiApplication::focusObject() == voiceInput && voiceInput->hasActiveFocus();
        })) {
        error = QStringLiteral("voice transaction fixture could not stage voice focus");
        return false;
    }
    tab = std::move(candidate);
    return true;
}

VoiceTransactionFixture::~VoiceTransactionFixture()
{
    destroy();
}

void VoiceTransactionFixture::destroy()
{
    if (tab)
        tab->hide();
    pump();
    tab.reset();
}

SongDocument &VoiceTransactionFixture::document()
{
    return tab->document();
}

Snapshot VoiceTransactionFixture::snapshot()
{
    return {document().smf().write(), document().revision(), document().undoStack()->index()};
}

QRect VoiceTransactionFixture::bandRect()
{
    return band(view(), songview::TimelineBand::VoiceChanges);
}

double VoiceTransactionFixture::xForTick(double tick)
{
    return view().camera().displayX(tick, 0.0, input().devicePixelRatio());
}

SongView &VoiceTransactionFixture::view()
{
    return tab->view();
}

songview::TimelineInputItem &VoiceTransactionFixture::input()
{
    return *tab->view().quickView()->rootObject()->findChild<songview::TimelineInputItem *>(
        QStringLiteral("timelineVoiceChangesInput"));
}
VelocityTransactionFixture::~VelocityTransactionFixture()
{
    destroy();
}

bool VelocityTransactionFixture::create(QString &error)
{
    error.clear();
    const std::optional<SongName> name =
        SongName::create(QStringLiteral("drawer-velocity-transaction"));
    const std::optional<VoicegroupId> identity =
        VoicegroupId::create(QStringLiteral("drawer-velocity-transaction"), QString());
    if (!name || !identity) {
        error = QStringLiteral("velocity transaction fixture has invalid identities");
        return false;
    }
    voicegroup.voices[0].type = VOICE_DIRECTSOUND;
    auto candidate = std::make_unique<SongTab>(std::move(*name));
    candidate->resize(1000, 640);
    candidate->setSampleRate(48000.0);
    SongInfo info;
    info.label = QStringLiteral("drawer-velocity-transaction");
    info.hasMid = true;
    candidate->applyMidiStage(std::move(info), velocitySmf(), track_limits::kHardwareCapacity);
    candidate->applyBankView(
        LoadedBankView{*identity, borrowVoicegroupLease(&voicegroup), QString()});
    candidate->applyVoicegroupBound(*identity);
    if (!candidate->isReady() || !candidate->presentationError().isEmpty()) {
        error = QStringLiteral("velocity transaction fixture did not become ready");
        return false;
    }
    checks::support::bindEditActionsForTest(candidate->view());
    SongView &candidateView = candidate->view();
    candidateView.selectTrack(0);
    candidateView.setDrawerActivePage(EditorDrawerPage::Velocity);
    candidateView.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    candidateView.setDrawerSectionHeight(EditorDrawerPage::Velocity, 320);
    notes = candidate->document().notesForTrack(0);
    if (notes.size() != 3) {
        error = QStringLiteral("velocity transaction fixture did not resolve three notes");
        return false;
    }
    songview::TimelineQuickView *const quick = candidateView.quickView();
    auto *root = quick ? quick->rootObject() : nullptr;
    auto *velocityInput = root ? root->findChild<songview::TimelineInputItem *>(
                                     QStringLiteral("timelineVelocityInput"))
                               : nullptr;
    QQuickWindow *const window = quick ? quick->quickWindow() : nullptr;
    if (!velocityInput || !window) {
        error = QStringLiteral("velocity transaction fixture could not resolve input");
        return false;
    }
    candidate->show();
    // Hosted container path: exposure and band-geometry publication land
    // after the external widget shows; wait for the staged contract.
    if (!QTest::qWaitFor([window, velocityInput] {
            return window->isVisible() && window->isExposed() &&
                   !velocityInput->bounds().isEmpty() && velocityInput->window() == window;
        })) {
        error = QStringLiteral("velocity transaction fixture could not resolve input");
        return false;
    }
    tab = std::move(candidate);
    return true;
}

void VelocityTransactionFixture::destroy()
{
    if (tab)
        tab->hide();
    pump();
    tab.reset();
}

SongDocument &VelocityTransactionFixture::document()
{
    return tab->document();
}

Snapshot VelocityTransactionFixture::snapshot()
{
    return {document().smf().write(), document().revision(), document().undoStack()->index()};
}

SongView &VelocityTransactionFixture::view()
{
    return tab->view();
}

VelocityArea &VelocityTransactionFixture::area()
{
    return *view().editorDrawer()->velocityArea();
}

songview::TimelineInputItem &VelocityTransactionFixture::input()
{
    return *view().quickView()->rootObject()->findChild<songview::TimelineInputItem *>(
        QStringLiteral("timelineVelocityInput"));
}

double VelocityTransactionFixture::xForTick(double tick)
{
    return view().camera().displayX(tick, 0.0, input().devicePixelRatio());
}

bool VelocityFixture::create(QString &error)
{
    error.clear();
    if (!directory.isValid()) {
        error = QStringLiteral("velocity fixture could not create temporary directory");
        return false;
    }
    SongInfo info;
    info.label = QStringLiteral("drawer-velocity");
    info.hasMid = true;
    info.midPath = directory.filePath(QStringLiteral("velocity.mid"));
    SmfFile smf = velocitySmf();
    if (!smf.writeFile(info.midPath, &error) || !document.load(info, &error))
        return false;
    notes = document.notesForTrack(0);
    if (notes.size() != 3) {
        error = QStringLiteral("velocity fixture did not resolve three distinct notes");
        return false;
    }
    voicegroup.voices[0].type = VOICE_DIRECTSOUND;
    EditorRigConfig config;
    config.voicegroup = &voicegroup;
    config.track = 0;
    config.activePage = EditorDrawerPage::Velocity;
    config.sections = {{EditorDrawerPage::Velocity, 320}};
    config.timeZoom = 48.0;
    rig = EditorRig::create(document, config, error);
    if (!rig)
        return false;
    area = rig->view().editorDrawer()->velocityArea();
    drawerChrome = &rig->view().editorDrawer()->chrome();
    auto *root = rig->quickRoot();
    inputItem = root ? root->findChild<songview::TimelineInputItem *>(
                           QStringLiteral("timelineVelocityInput"))
                     : nullptr;
    gutterItem = root ? root->findChild<songview::TimelineInputItem *>(
                            QStringLiteral("timelineVelocityGutterInput"))
                      : nullptr;
    barItem = root
                  ? root->findChild<songview::TimelineInputItem *>(QStringLiteral("drawerBarInput"))
                  : nullptr;
    detentItem =
        root ? root->findChild<songview::TimelineInputItem *>(QStringLiteral("drawerDetentInput"))
             : nullptr;
    if (!area || !drawerChrome || !inputItem || !gutterItem || !barItem || !detentItem) {
        error = QStringLiteral("velocity fixture could not resolve its drawer surfaces");
        return false;
    }
    refresh();
    return true;
}

void VelocityFixture::destroy()
{
    pump();
    rig.reset();
    area = nullptr;
    drawerChrome = nullptr;
    inputItem = nullptr;
    gutterItem = nullptr;
    barItem = nullptr;
    detentItem = nullptr;
}

Snapshot VelocityFixture::snapshot()
{
    return {document.smf().write(), document.revision(), document.undoStack()->index()};
}

QRect VelocityFixture::bandRect() const
{
    return band(rig->view(), songview::TimelineBand::Velocity);
}

QRect VelocityFixture::plotRect() const
{
    return plot(rig->view(), songview::TimelineBand::Velocity);
}

int VelocityFixture::fixedSpan() const
{
    return ::fixedSpan(rig->view(), songview::TimelineBand::Velocity);
}

double VelocityFixture::xForTick(double tick) const
{
    return rig->view().camera().displayX(tick, 0.0, inputItem->devicePixelRatio());
}

void VelocityFixture::refresh(bool playing, double playheadTick)
{
    DrawerPageLiveState live;
    live.documentRevision = document.revision();
    live.timeZoom = rig->view().camera().pxPerBeat();
    live.horizontalScroll = rig->view().camera().scrollX();
    live.trackColor = Qt::cyan;
    live.playback.playing = playing;
    live.playback.playheadTick = playheadTick;
    area->refreshLiveState(live);
    pump();
}

} // namespace checks::drawerpresentation
